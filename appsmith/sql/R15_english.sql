-- ============================================================================
-- R15: teks sistem ke bahasa Inggris + tanpa em dash (13 Okt 2026, keputusan user).
-- Jalankan SETELAH R14_audit_stage.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi.
--
-- Dibuat otomatis oleh tools/r15/make_r15_sql.py dari definisi fungsi & view setelah R14 (kamus tools/r15/en_db.py).
-- Isi: 88 fungsi/view dibuat ulang dengan pesan & label bahasa Inggris. Logika tidak berubah, kecuali:
--   - kode status harga (fn_price_state) jadi bahasa Inggris: BERLAKU -> ACTIVE, AKAN BERLAKU -> UPCOMING,
--     MENUNGGU APPROVAL -> PENDING APPROVAL, DITOLAK -> REJECTED, DIBATALKAN -> CANCELLED, RIWAYAT -> EXPIRED,
--     BELUM ADA HARGA -> NO PRICE (dihitung, tidak tersimpan; app R15 memakai kode baru)
--   - selisih Target FOB: SESUAI -> MATCH
--   - pesan error menyebut stage dengan label (Pullover, Preview, Production)
-- Data yang sudah tersimpan (mis. alasan "Revisi awal." di change log lama) tidak diubah.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_stage_label(text)') IS NULL THEN
    RAISE EXCEPTION 'R14 is not installed. Run sql/R14_audit_stage.sql first.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_auth_any(p_token text, p_permissions text[])
 RETURNS text
 LANGUAGE plpgsql
AS $function$

DECLARE

  v_email text := fn_auth(p_token, NULL);   -- SESI_HABIS kalau token tidak valid

  v_perm  text;

BEGIN

  FOREACH v_perm IN ARRAY p_permissions LOOP

    IF fn_has_perm(v_email, v_perm) THEN

      RETURN fn_auth(p_token, v_perm);        -- cek wajib-ganti-password + catat user audit

    END IF;

  END LOOP;

  RAISE EXCEPTION 'Role % has no access to this action.',

    fn_role_label((SELECT role FROM app_user WHERE email = v_email));

END;

$function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$

DECLARE

  v_other text;

BEGIN

  NEW.name := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));

  IF NEW.name = '' THEN

    RAISE EXCEPTION 'Supplier name is required.';

  END IF;

  SELECT name INTO v_other FROM supplier

   WHERE name_key = fn_normalize(NEW.name) AND id <> NEW.id;

  IF v_other IS NOT NULL THEN

    RAISE EXCEPTION 'Supplier "%" already exists.', v_other;

  END IF;

  RETURN NEW;

END;

$function$;

CREATE OR REPLACE FUNCTION public.fn_article_delete_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$

BEGIN

  IF fn_article_is_used(OLD.id) THEN

    RAISE EXCEPTION 'Article % is used in a specsheet/CBD and cannot be deleted. Drop it in the specsheet instead.', OLD.code;

  END IF;

  RETURN OLD;

END;

$function$;

CREATE OR REPLACE FUNCTION public.fn_auth(p_token text, p_permission text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text;
  v_role  text;
  v_must  boolean;
BEGIN
  SELECT u.email, u.role, u.must_change_password INTO v_email, v_role, v_must
    FROM app_session s JOIN app_user u ON u.email = s.email
   WHERE s.token_hash = fn_token_hash(p_token) AND s.expires_at > now() AND u.is_active;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'SESI_HABIS: Your session has expired. Please log in again.';
  END IF;
  IF coalesce(p_permission, '') <> '' THEN
    IF v_must THEN
      RAISE EXCEPTION 'Please change your password before using the app.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM role_permission WHERE role = v_role AND permission = p_permission) THEN
      RAISE EXCEPTION 'Role % has no access to this action.', fn_role_label(v_role);
    END IF;
  END IF;
  PERFORM set_config('app.user', v_email, true);   -- dibaca trigger audit
  RETURN v_email;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_price_line(p_line_id uuid)
 RETURNS cbd_line
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_line cbd_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM cbd_line WHERE id = p_line_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CBD line not found. Please reload the page.';
  END IF;
  PERFORM fn_cbd_draft(v_line.cbd_revision_id);
  IF v_line.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'The price of a line missing from the specsheet (MISSING_IN_SPEC) cannot be changed.';
  END IF;
  RETURN v_line;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_check_price(p_price numeric, p_currency text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF p_price IS NULL OR p_price <= 0 THEN
    RAISE EXCEPTION 'Price is required and must be above 0.';
  END IF;
  IF coalesce(p_currency, '') NOT IN ('IDR', 'USD') THEN
    RAISE EXCEPTION 'Select a currency (IDR / USD).';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_login(p_email text, p_password text)
 RETURNS TABLE(ok boolean, message text, token text, must_change_password boolean)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_user  app_user%ROWTYPE;
  v_token text;
BEGIN
  SELECT * INTO v_user FROM app_user WHERE app_user.email = v_email;

  IF NOT FOUND OR NOT v_user.is_active OR v_user.password_hash IS NULL THEN
    PERFORM fn_audit(v_email, 'app_user', v_email, 'LOGIN_FAILED');
    RETURN QUERY SELECT false, 'Wrong email or password.'::text, NULL::text, NULL::boolean;
    RETURN;
  END IF;

  IF v_user.locked_until IS NOT NULL AND v_user.locked_until > now() THEN
    RETURN QUERY SELECT false,
      format('Account locked after 5 wrong passwords. Try again after %s WIB, or ask the System Admin to reset your password.',
             to_char(v_user.locked_until AT TIME ZONE 'Asia/Jakarta', 'HH24:MI')),
      NULL::text, NULL::boolean;
    RETURN;
  END IF;

  IF v_user.password_hash <> crypt(coalesce(p_password, ''), v_user.password_hash) THEN
    UPDATE app_user
       SET failed_attempts = CASE WHEN failed_attempts + 1 >= 5 THEN 0 ELSE failed_attempts + 1 END,
           locked_until    = CASE WHEN failed_attempts + 1 >= 5 THEN now() + interval '15 minutes' END
     WHERE app_user.email = v_email;
    PERFORM fn_audit(v_email, 'app_user', v_email, 'LOGIN_FAILED');
    RETURN QUERY SELECT false, 'Wrong email or password.'::text, NULL::text, NULL::boolean;
    RETURN;
  END IF;

  v_token := encode(gen_random_bytes(32), 'hex');
  DELETE FROM app_session WHERE app_session.expires_at < now();
  INSERT INTO app_session (token_hash, email, expires_at)
  VALUES (fn_token_hash(v_token), v_email, now() + interval '12 hours');
  UPDATE app_user SET failed_attempts = 0, locked_until = NULL, last_login_at = now()
   WHERE app_user.email = v_email;
  PERFORM fn_audit(v_email, 'app_user', v_email, 'LOGIN');
  RETURN QUERY SELECT true, NULL::text, v_token, v_user.must_change_password;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_change_password(p_token text, p_old text, p_new text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, NULL);
  v_hash  text;
BEGIN
  SELECT password_hash INTO v_hash FROM app_user WHERE email = v_email;
  IF v_hash IS NULL OR v_hash <> crypt(coalesce(p_old, ''), v_hash) THEN
    RAISE EXCEPTION 'The old password is wrong.';
  END IF;
  IF length(coalesce(p_new, '')) < 8 THEN
    RAISE EXCEPTION 'The new password must be at least 8 characters.';
  END IF;
  IF p_new = p_old THEN
    RAISE EXCEPTION 'The new password must be different from the old one.';
  END IF;
  UPDATE app_user
     SET password_hash = crypt(p_new, gen_salt('bf', 10)), must_change_password = false, updated_by = v_email
   WHERE email = v_email;
  -- sesi lain (perangkat lain) ikut keluar
  DELETE FROM app_session WHERE email = v_email AND token_hash <> fn_token_hash(p_token);
  PERFORM fn_audit(v_email, 'app_user', v_email, 'PASSWORD_CHANGE');
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_user_reset_password(p_token text, p_email text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_actor text := fn_auth(p_token, 'manage_users');
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_pass  text := fn_random_password();
BEGIN
  IF v_email = v_actor THEN
    RAISE EXCEPTION 'For your own account, use Change Password.';
  END IF;
  UPDATE app_user
     SET password_hash = crypt(v_pass, gen_salt('bf', 10)), must_change_password = true,
         failed_attempts = 0, locked_until = NULL, updated_by = v_actor
   WHERE email = v_email;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % not found.', v_email;
  END IF;
  DELETE FROM app_session WHERE email = v_email;
  PERFORM fn_audit(v_actor, 'app_user', v_email, 'PASSWORD_RESET');
  RETURN v_pass;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_component_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$

DECLARE

  v_group component_group%ROWTYPE;

  v_other text;

BEGIN

  NEW.name := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));

  IF NEW.name = '' THEN

    RAISE EXCEPTION 'Component name is required.';

  END IF;

  -- Ubah status saja tidak perlu cek ulang nomor

  IF TG_OP = 'UPDATE' AND NEW.number IS NOT DISTINCT FROM OLD.number

     AND NEW.group_code IS NOT DISTINCT FROM OLD.group_code THEN

    RETURN NEW;

  END IF;

  IF NEW.number IS NULL THEN

    RAISE EXCEPTION 'Component number is required.';

  END IF;

  SELECT * INTO v_group FROM component_group WHERE code = NEW.group_code;

  IF NOT FOUND THEN

    RAISE EXCEPTION 'Component group is required.';

  END IF;

  IF NEW.number % 10 <> 0 THEN

    RAISE EXCEPTION 'Component number must be a multiple of 10.';

  END IF;

  IF NEW.number NOT BETWEEN v_group.range_start AND v_group.range_end THEN

    RAISE EXCEPTION 'The number must be in the range %–% for group %.',

      v_group.range_start, v_group.range_end, v_group.name;

  END IF;

  SELECT name INTO v_other FROM component WHERE number = NEW.number AND id <> NEW.id;

  IF v_other IS NOT NULL THEN

    RAISE EXCEPTION 'Number % is used by component "%" and cannot be reused.', NEW.number, v_other;

  END IF;

  RETURN NEW;

END;

$function$;

CREATE OR REPLACE FUNCTION public.fn_material_supplier_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_sup supplier%ROWTYPE;
BEGIN
  IF NEW.status = 'INACTIVE' THEN
    NEW.is_preferred := false;          -- supplier nonaktif tidak bisa jadi supplier utama
  END IF;
  IF TG_OP = 'INSERT' OR NEW.supplier_id IS DISTINCT FROM OLD.supplier_id THEN
    SELECT * INTO v_sup FROM supplier WHERE id = NEW.supplier_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Supplier not found in Master Supplier.';
    END IF;
    IF v_sup.status = 'INACTIVE' THEN
      RAISE EXCEPTION 'Supplier % is inactive in Master Supplier.', v_sup.name;
    END IF;
    IF EXISTS (SELECT 1 FROM material_supplier
                WHERE material_id = NEW.material_id AND supplier_id = NEW.supplier_id AND id <> NEW.id) THEN
      RAISE EXCEPTION 'Supplier % is already added to this material.', v_sup.name;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_price_activate(p_price_id uuid, p_actor text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_row  material_price%ROWTYPE;
  v_open material_price%ROWTYPE;
  v_code text;
BEGIN
  SELECT * INTO v_row FROM material_price WHERE id = p_price_id;
  SELECT * INTO v_open FROM material_price
   WHERE material_supplier_id = v_row.material_supplier_id AND variant_id = v_row.variant_id
     AND status = 'APPROVED' AND valid_to IS NULL AND id <> v_row.id
   ORDER BY valid_from DESC LIMIT 1;
  IF FOUND THEN
    IF v_row.valid_from < v_open.valid_from THEN
      SELECT code INTO v_code FROM material_variant WHERE id = v_row.variant_id;
      RAISE EXCEPTION 'Variant %: a price is already active from %. The proposal starts on % (earlier). Reject this proposal.',
        v_code, to_char(v_open.valid_from, 'DD-MM-YYYY'), to_char(v_row.valid_from, 'DD-MM-YYYY');
    END IF;
    UPDATE material_price SET valid_to = v_row.valid_from, updated_by = p_actor WHERE id = v_open.id;
  END IF;
  UPDATE material_price
     SET status = 'APPROVED', decided_by = p_actor, decided_at = now(), reject_reason = NULL, updated_by = p_actor
   WHERE id = p_price_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_cost_label(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_type WHEN 'LABOUR' THEN 'Direct Labour' WHEN 'AMORTIZATION' THEN 'Amortization'
                     WHEN 'ADJUSTMENT' THEN 'Adjustment' ELSE 'Other' END
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_check_cost(p_type text, p_amount numeric)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF p_type <> 'ADJUSTMENT' AND coalesce(p_amount, 0) < 0 THEN
    RAISE EXCEPTION 'Value % cannot be negative (only Adjustment can be negative).', fn_cbd_cost_label(p_type);
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_cost_item(p_item_id uuid)
 RETURNS cbd_cost_item
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_item cbd_cost_item%ROWTYPE;
BEGIN
  SELECT * INTO v_item FROM cbd_cost_item WHERE id = p_item_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cost line not found. Please reload the page.';
  END IF;
  PERFORM fn_cbd_draft(v_item.cbd_revision_id);
  RETURN v_item;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_cost_add(p_token text, p_cbd_revision_id uuid, p_type text, p_name text, p_amount numeric, p_remarks text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev   cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
  v_id    uuid;
BEGIN
  IF coalesce(p_type, '') NOT IN ('LABOUR', 'AMORTIZATION', 'ADJUSTMENT', 'OTHER') THEN
    RAISE EXCEPTION 'Select a cost type.';
  END IF;
  PERFORM fn_cbd_check_cost(p_type, p_amount);
  INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, remarks, is_default, sort_order, updated_by)
  VALUES (v_rev.id, p_type, coalesce(nullif(btrim(coalesce(p_name, '')), ''), fn_cbd_cost_label(p_type)),
          coalesce(p_amount, 0), nullif(btrim(coalesce(p_remarks, '')), ''), false,
          (SELECT coalesce(max(sort_order), 0) + 1 FROM cbd_cost_item WHERE cbd_revision_id = v_rev.id), v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_specsheet_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$

BEGIN

  NEW.season := upper(regexp_replace(coalesce(NEW.season, ''), '\s+', '', 'g'));

  IF NEW.season !~ '^(SS|FH)[0-9]{2}$' THEN

    RAISE EXCEPTION 'Season must be SS[year] or FH[year], e.g. SS26 or FH26.';

  END IF;

  IF TG_OP = 'UPDATE' AND NEW.model_id IS DISTINCT FROM OLD.model_id THEN

    RAISE EXCEPTION 'A season cannot be moved to another model.';

  END IF;

  IF EXISTS (SELECT 1 FROM specsheet WHERE model_id = NEW.model_id AND season = NEW.season AND id <> NEW.id) THEN

    RAISE EXCEPTION 'Season % already exists for this model.', NEW.season;

  END IF;

  RETURN NEW;

END;

$function$;

CREATE OR REPLACE FUNCTION public.fn_article_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.code     := btrim(regexp_replace(coalesce(NEW.code, ''), '\s+', ' ', 'g'));
  NEW.colorway := btrim(regexp_replace(coalesce(NEW.colorway, ''), '\s+', ' ', 'g'));
  IF NEW.code = ''     THEN RAISE EXCEPTION 'Article code is required.'; END IF;
  IF NEW.colorway = '' THEN RAISE EXCEPTION 'Colorway is required.'; END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.specsheet_id IS DISTINCT FROM OLD.specsheet_id THEN
      RAISE EXCEPTION 'An article cannot be moved to another season.';
    END IF;
    IF NEW.code IS DISTINCT FROM OLD.code AND fn_article_is_used(OLD.id) THEN
      RAISE EXCEPTION 'Article code % cannot be changed because it is used in a specsheet/CBD.', OLD.code;
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    PERFORM 1 FROM specsheet WHERE id = NEW.specsheet_id FOR UPDATE;   -- antre per season (cek kode unik)
  END IF;
  IF EXISTS (SELECT 1 FROM article WHERE specsheet_id = NEW.specsheet_id AND upper(code) = upper(NEW.code)
                                     AND id <> NEW.id) THEN
    RAISE EXCEPTION 'Article code % already exists in this season.', NEW.code;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_price_cancel(p_token text, p_price_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, 'manage_price');
  v_row   material_price%ROWTYPE;
  v_fac   uuid;
BEGIN
  SELECT * INTO v_row FROM material_price WHERE id = p_price_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Price not found.';
  END IF;
  SELECT m.factory_id INTO v_fac FROM material_supplier ms JOIN material m ON m.id = ms.material_id
   WHERE ms.id = v_row.material_supplier_id;
  PERFORM fn_assert_factory(v_email, v_fac);
  IF v_row.status <> 'PROPOSED' THEN
    RAISE EXCEPTION 'Only proposals that are not processed yet can be cancelled.';
  END IF;
  DELETE FROM material_price WHERE id = p_price_id AND status = 'PROPOSED';
  RETURN p_price_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_lock_published()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_row    jsonb;
  v_rev    uuid;
  v_status text;
BEGIN
  IF TG_OP = 'DELETE' THEN v_row := to_jsonb(OLD); ELSE v_row := to_jsonb(NEW); END IF;
  IF TG_TABLE_NAME = 'bom_cell' THEN
    SELECT revision_id INTO v_rev FROM bom_line WHERE id = (v_row ->> 'bom_line_id')::uuid;
  ELSE
    v_rev := (v_row ->> 'revision_id')::uuid;
  END IF;
  SELECT status INTO v_status FROM specsheet_revision WHERE id = v_rev;
  IF v_status = 'PUBLISHED' THEN
    RAISE EXCEPTION 'This revision is published and cannot be changed. Create a new revision for changes.';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_revision_lock()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF OLD.status = 'PUBLISHED' THEN
    RAISE EXCEPTION 'Revision % r% is published and cannot be changed or deleted.', fn_stage_label(OLD.stage), OLD.revision_no;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF NEW.specsheet_id IS DISTINCT FROM OLD.specsheet_id OR NEW.stage IS DISTINCT FROM OLD.stage
     OR NEW.revision_no IS DISTINCT FROM OLD.revision_no THEN
    RAISE EXCEPTION 'Season, stage, and revision number cannot be changed.';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_revision_draft(p_revision_id uuid)
 RETURNS specsheet_revision
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_rev specsheet_revision%ROWTYPE;
BEGIN
  SELECT * INTO v_rev FROM specsheet_revision WHERE id = p_revision_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Revision not found.';
  END IF;
  IF v_rev.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'This revision is published and cannot be changed. Create a new revision for changes.';
  END IF;
  RETURN v_rev;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_thickness_label(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT coalesce(nullif(btrim(coalesce(p, '')), ''), 'no thickness')
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_line_lock()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_status text;
BEGIN
  SELECT status INTO v_status FROM cbd_revision
   WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.cbd_revision_id ELSE NEW.cbd_revision_id END;
  IF v_status = 'PUBLISHED' THEN
    RAISE EXCEPTION 'This CBD revision is published and cannot be changed. Create a new revision for changes.';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_revision_lock()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$

BEGIN

  IF OLD.status = 'PUBLISHED' THEN

    IF TG_OP = 'DELETE' THEN

      RAISE EXCEPTION 'CBD revision % r% is published and cannot be deleted.', fn_stage_label(OLD.stage), OLD.revision_no;

    END IF;

    -- stage_order = kolom generated: di BEFORE trigger nilai NEW-nya belum dihitung -> tidak ikut dibandingkan

    IF (to_jsonb(NEW) - 'sync_status' - 'specsheet_revision_id' - 'updated_at' - 'updated_by' - 'stage_order')

       IS DISTINCT FROM (to_jsonb(OLD) - 'sync_status' - 'specsheet_revision_id' - 'updated_at' - 'updated_by' - 'stage_order') THEN

      RAISE EXCEPTION 'CBD revision % r% is published and cannot be changed. Create a new revision for changes.',

        fn_stage_label(OLD.stage), OLD.revision_no;

    END IF;

  END IF;

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;

  IF NEW.article_id IS DISTINCT FROM OLD.article_id THEN

    RAISE EXCEPTION 'The article of a CBD revision cannot be changed.';

  END IF;

  RETURN NEW;

END;

$function$;

CREATE OR REPLACE FUNCTION public.fn_price_state(p_status text, p_valid_from date, p_valid_to date)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN p_status = 'PROPOSED' THEN 'PENDING APPROVAL'
              WHEN p_status = 'REJECTED' THEN 'REJECTED'
              WHEN p_valid_to IS NOT NULL AND p_valid_to <= p_valid_from THEN 'CANCELLED'
              WHEN p_valid_to IS NOT NULL AND p_valid_to <= fn_today() THEN 'EXPIRED'
              WHEN p_valid_from > fn_today() THEN 'UPCOMING'
              ELSE 'ACTIVE' END
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_delete_draft(p_token text, p_cbd_revision_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev   cbd_revision%ROWTYPE;
BEGIN
  SELECT * INTO v_rev FROM cbd_revision WHERE id = p_cbd_revision_id FOR UPDATE;
  IF v_rev.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'This CBD revision is published and cannot be deleted.';
  END IF;
  DELETE FROM cbd_revision WHERE id = v_rev.id;
  RETURN v_rev.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_line_set(p_token text, p_line_id uuid, p_field text, p_value numeric)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_line_factory(p_line_id));
  v_line  cbd_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM cbd_line WHERE id = p_line_id;
  PERFORM fn_cbd_draft(v_line.cbd_revision_id);
  IF v_line.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'This line is no longer in the specsheet (MISSING_IN_SPEC) and cannot be changed.';
  END IF;
  IF p_field = 'YIELD' THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION 'Yield must be above 0.';
    END IF;
    UPDATE cbd_line SET yield_value = p_value, value_origin = 'INPUT', updated_by = v_email WHERE id = v_line.id;
  ELSIF p_field = 'LOSS' THEN
    IF p_value < 0 OR p_value >= 100 THEN
      RAISE EXCEPTION 'Loss %% must be from 0 to below 100 (empty = 0).';
    END IF;
    UPDATE cbd_line SET loss_pct = p_value, value_origin = 'INPUT', updated_by = v_email WHERE id = v_line.id;
  ELSE
    RAISE EXCEPTION 'Invalid field.';
  END IF;
  RETURN v_line.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_auth_in(p_token text, p_perm text, p_factory uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, p_perm);
BEGIN
  IF p_factory IS NULL THEN
    RAISE EXCEPTION 'Data not found. Please reload the page.';
  END IF;
  PERFORM fn_assert_factory(v_email, p_factory);
  RETURN v_email;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_model_option_ref(p_id uuid, p_kind text, p_factory uuid, p_old uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_opt model_option%ROWTYPE;
BEGIN
  IF p_id IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO v_opt FROM model_option WHERE id = p_id;
  IF NOT FOUND OR v_opt.kind <> p_kind THEN
    RAISE EXCEPTION 'Option % is not valid. Please reload the page.', fn_option_kind_label(p_kind);
  END IF;
  IF v_opt.factory_id IS NOT NULL AND v_opt.factory_id IS DISTINCT FROM p_factory THEN
    RAISE EXCEPTION '% "%" belongs to another factory.', fn_option_kind_label(p_kind), v_opt.value;
  END IF;
  IF v_opt.status = 'INACTIVE' AND p_id IS DISTINCT FROM p_old THEN
    RAISE EXCEPTION '% "%" is INACTIVE.', fn_option_kind_label(p_kind), v_opt.value;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_rev_article_set(p_token text, p_revision_id uuid, p_article_id uuid, p_status text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_rev_factory(p_revision_id));
  v_rev   specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'DROPPED') THEN
    RAISE EXCEPTION 'Invalid article status.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM article WHERE id = p_article_id AND specsheet_id = v_rev.specsheet_id) THEN
    RAISE EXCEPTION 'The article does not belong to this revision''s season.';
  END IF;
  INSERT INTO revision_article (revision_id, article_id, status, updated_by)
  VALUES (v_rev.id, p_article_id, p_status, v_email)
  ON CONFLICT (revision_id, article_id) DO UPDATE SET status = EXCLUDED.status, updated_by = EXCLUDED.updated_by;
  IF p_status = 'ACTIVE' THEN
    INSERT INTO bom_cell (bom_line_id, article_id, updated_by)
    SELECT l.id, p_article_id, v_email FROM bom_line l WHERE l.revision_id = v_rev.id AND l.is_active
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN p_article_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_add_line(p_token text, p_revision_id uuid, p_component_id uuid, p_local_no integer, p_local_name text, p_material_id uuid, p_thickness text, p_supplier_id uuid, p_process text, p_fill_color text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory uuid := fn_rev_factory(p_revision_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_rev     specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
  v_comp    component%ROWTYPE;
  v_name    text := nullif(btrim(regexp_replace(coalesce(p_local_name, ''), '\s+', ' ', 'g')), '');
  v_thick   text := fn_clean_thickness(p_thickness);
  v_fill    text := nullif(btrim(coalesce(p_fill_color, '')), '');
  v_id      uuid;
BEGIN
  PERFORM fn_bom_check_material(p_material_id, v_factory);
  IF p_component_id IS NOT NULL THEN
    SELECT * INTO v_comp FROM component WHERE id = p_component_id;
    IF NOT FOUND OR v_comp.status <> 'ACTIVE' THEN
      RAISE EXCEPTION 'Master component not found or INACTIVE. For a new component, use a local component.';
    END IF;
    IF EXISTS (SELECT 1 FROM bom_line WHERE revision_id = v_rev.id AND is_active AND parent_line_key IS NULL
                                        AND component_id = p_component_id AND material_id = p_material_id
                                        AND thickness IS NOT DISTINCT FROM v_thick) THEN
      RAISE EXCEPTION 'Component % with this material (same thickness) is already in this revision.', v_comp.number;
    END IF;
  ELSE
    IF p_local_no IS NULL THEN
      RAISE EXCEPTION 'The component is not in the master. Fill in No. for a local component.';
    END IF;
    IF p_local_no % 10 = 0 THEN
      RAISE EXCEPTION 'A local component no. cannot be a multiple of 10 (multiples of 10 are for master components).';
    END IF;
    IF v_name IS NULL THEN
      RAISE EXCEPTION 'Local component name is required.';
    END IF;
    IF EXISTS (SELECT 1 FROM bom_line WHERE revision_id = v_rev.id AND is_active AND parent_line_key IS NULL
                                        AND local_component_no = p_local_no) THEN
      RAISE EXCEPTION 'Local no. % is already used in this revision.', p_local_no;
    END IF;
  END IF;
  PERFORM fn_bom_check_supplier(p_material_id, p_supplier_id);

  INSERT INTO bom_line (revision_id, line_key, component_id, local_component_no, local_component_name,
                        material_id, thickness, supplier_id, process, sort_order, updated_by)
  VALUES (v_rev.id, gen_random_uuid(), p_component_id,
          CASE WHEN p_component_id IS NULL THEN p_local_no END,
          CASE WHEN p_component_id IS NULL THEN v_name END,
          p_material_id, v_thick, p_supplier_id, nullif(btrim(coalesce(p_process, '')), ''),
          coalesce((SELECT max(sort_order) FROM bom_line WHERE revision_id = v_rev.id), 0) + 1, v_email)
  RETURNING id INTO v_id;
  PERFORM fn_bom_create_cells(v_id, v_email);
  IF v_fill IS NOT NULL THEN
    UPDATE bom_cell SET color = v_fill, updated_by = v_email WHERE bom_line_id = v_id;
  END IF;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_check_supplier(p_material_id uuid, p_supplier_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_sup supplier%ROWTYPE;
BEGIN
  IF p_supplier_id IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO v_sup FROM supplier WHERE id = p_supplier_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'The supplier is not in Master Supplier.';
  END IF;
  IF v_sup.status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Supplier % is inactive. Select another supplier.', v_sup.name;
  END IF;
  PERFORM fn_ensure_link(p_material_id, p_supplier_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_factory_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_other text;
BEGIN
  NEW.name := upper(btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g')));
  IF NEW.name = '' THEN
    RAISE EXCEPTION 'Factory name is required.';
  END IF;
  SELECT name INTO v_other FROM factory WHERE name_key = fn_normalize(NEW.name) AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Factory "%" already exists.', v_other;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.status = 'INACTIVE' AND OLD.status <> 'INACTIVE'
     AND EXISTS (SELECT 1 FROM app_user WHERE factory_id = NEW.id AND is_active) THEN
    RAISE EXCEPTION 'Factory % still has active users. Deactivate or move them first.', NEW.name;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_assert_factory(p_email text, p_factory_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  IF NOT fn_can_see_factory(p_email, p_factory_id) THEN
    RAISE EXCEPTION 'This data belongs to another factory.';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_user_save(p_token text, p_email text, p_full_name text, p_role text, p_is_active boolean, p_is_new boolean, p_factory_id uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_actor   text := fn_auth(p_token, 'manage_users');
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_name    text := btrim(coalesce(p_full_name, ''));
  v_factory uuid := CASE WHEN fn_is_factory_role(p_role) THEN p_factory_id END;
  v_pass    text;
BEGIN
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'Invalid email format.';
  END IF;
  IF v_name = '' THEN
    RAISE EXCEPTION 'Name is required.';
  END IF;
  IF coalesce(p_role, '') = '' THEN
    RAISE EXCEPTION 'Role is required.';
  END IF;
  IF fn_is_factory_role(p_role) THEN
    IF v_factory IS NULL THEN
      RAISE EXCEPTION 'Role % needs a factory.', fn_role_label(p_role);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM factory WHERE id = v_factory AND status = 'ACTIVE') THEN
      RAISE EXCEPTION 'The selected factory does not exist or is inactive.';
    END IF;
  END IF;
  IF v_email = v_actor AND (p_role <> 'SYSTEM_ADMIN' OR NOT coalesce(p_is_active, true)) THEN
    RAISE EXCEPTION 'You cannot change your own role or deactivate your own account.';
  END IF;

  IF p_is_new THEN
    IF EXISTS (SELECT 1 FROM app_user WHERE email = v_email) THEN
      RAISE EXCEPTION 'Email % is already registered.', v_email;
    END IF;
    v_pass := fn_random_password();
    INSERT INTO app_user (email, full_name, role, factory_id, is_active, password_hash, must_change_password, updated_by)
    VALUES (v_email, v_name, p_role, v_factory, coalesce(p_is_active, true), crypt(v_pass, gen_salt('bf', 10)),
            true, v_actor);
  ELSE
    UPDATE app_user
       SET full_name = v_name, role = p_role, factory_id = v_factory, is_active = coalesce(p_is_active, true),
           updated_by = v_actor
     WHERE email = v_email;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'User % not found.', v_email;
    END IF;
    -- pindah role/pabrik atau nonaktif: sesi lama ditutup supaya izin & lingkup data langsung berlaku
    DELETE FROM app_session WHERE email = v_email;
  END IF;
  RETURN v_pass;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_factory_save(p_token text, p_id uuid, p_name text, p_status text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_actor text := fn_auth(p_token, 'manage_factory');
  v_id    uuid;
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Factory status is required.';
  END IF;
  IF p_id IS NULL THEN
    INSERT INTO factory (name, status, updated_by) VALUES (p_name, p_status, v_actor) RETURNING id INTO v_id;
  ELSE
    UPDATE factory SET name = p_name, status = p_status, updated_by = v_actor WHERE id = p_id RETURNING id INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Factory not found.';
    END IF;
  END IF;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_ensure_link(p_material_id uuid, p_supplier_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_link material_supplier%ROWTYPE;
  v_id   uuid;
BEGIN
  IF p_supplier_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_link FROM material_supplier WHERE material_id = p_material_id AND supplier_id = p_supplier_id;
  IF FOUND THEN
    IF v_link.status = 'INACTIVE' THEN
      RAISE EXCEPTION 'Supplier % is inactive for material %. Select another supplier.',
        (SELECT name FROM supplier WHERE id = p_supplier_id), (SELECT name FROM material WHERE id = p_material_id);
    END IF;
    RETURN v_link.id;
  END IF;
  INSERT INTO material_supplier (material_id, supplier_id, status, updated_by)
  VALUES (p_material_id, p_supplier_id, 'ACTIVE', nullif(current_setting('app.user', true), ''))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_price_end(p_token text, p_price_id uuid, p_valid_to date)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, 'approve_price');
  v_row   material_price%ROWTYPE;
  v_fac   uuid;
BEGIN
  SELECT * INTO v_row FROM material_price WHERE id = p_price_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Price not found.';
  END IF;
  SELECT m.factory_id INTO v_fac FROM material_supplier ms JOIN material m ON m.id = ms.material_id
   WHERE ms.id = v_row.material_supplier_id;
  PERFORM fn_assert_factory(v_email, v_fac);
  IF v_row.status <> 'APPROVED' THEN
    RAISE EXCEPTION 'Only approved prices can be ended. For proposals, use Reject.';
  END IF;
  IF v_row.valid_to IS NOT NULL THEN
    RAISE EXCEPTION 'This price has already ended.';
  END IF;
  IF v_row.valid_from > fn_today() THEN
    UPDATE material_price SET valid_to = NULL, updated_by = v_email
     WHERE material_supplier_id = v_row.material_supplier_id AND variant_id = v_row.variant_id
       AND status = 'APPROVED' AND id <> v_row.id AND valid_to = v_row.valid_from
       AND valid_from < v_row.valid_from;           -- R11b: bukan harga lain yang sudah dibatalkan (0 hari)
    UPDATE material_price SET valid_to = valid_from, updated_by = v_email WHERE id = p_price_id;
    RETURN p_price_id;
  END IF;
  UPDATE material_price
     SET valid_to = greatest(coalesce(p_valid_to, fn_today()), valid_from), updated_by = v_email
   WHERE id = p_price_id;
  RETURN p_price_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_similar_names(p_token text, p_kind text, p_text text, p_exclude uuid)
 RETURNS TABLE(ref_id uuid, label text, info text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email   text := fn_auth(p_token, 'view_master');
  v_factory uuid := fn_user_factory(v_email);
  v_key     text := fn_similar_key(p_text);
  v_kind    text;
BEGIN
  IF length(v_key) < 2 THEN
    RETURN;
  END IF;
  IF p_kind = 'SUPPLIER' THEN
    RETURN QUERY
      SELECT s.id, s.name, s.status
        FROM supplier s
       WHERE s.id IS DISTINCT FROM p_exclude AND fn_similar_match(fn_similar_key(s.name), v_key)
       ORDER BY fn_similar_key(s.name) = v_key DESC, abs(length(fn_similar_key(s.name)) - length(v_key)), s.name
       LIMIT 8;
  ELSIF p_kind = 'COMPONENT' THEN
    RETURN QUERY
      SELECT c.id, c.name, 'No. ' || c.number || ' · ' || c.status
        FROM component c
       WHERE c.id IS DISTINCT FROM p_exclude AND fn_similar_match(fn_similar_key(c.name), v_key)
       ORDER BY fn_similar_key(c.name) = v_key DESC, abs(length(fn_similar_key(c.name)) - length(v_key)), c.number
       LIMIT 8;
  ELSIF p_kind = 'MATERIAL' THEN
    RETURN QUERY
      SELECT m.id, m.name, m.category || ' · ' || m.uom || ' · ' || m.status
        FROM material m
       WHERE m.id IS DISTINCT FROM p_exclude AND fn_can_see_factory(v_email, m.factory_id)
         AND fn_similar_match(fn_similar_key(m.name), v_key)
       ORDER BY fn_similar_key(m.name) = v_key DESC, abs(length(fn_similar_key(m.name)) - length(v_key)), m.name
       LIMIT 8;
  ELSIF p_kind LIKE 'OPTION:%' THEN
    v_kind := substr(p_kind, 8);
    RETURN QUERY
      SELECT o.id, o.value, o.status
        FROM model_option o
       WHERE o.kind = v_kind AND o.id IS DISTINCT FROM p_exclude
         AND (o.factory_id IS NULL OR fn_can_see_factory(v_email, o.factory_id))
         AND fn_similar_match(fn_similar_key(o.value), v_key)
       ORDER BY fn_similar_key(o.value) = v_key DESC, abs(length(fn_similar_key(o.value)) - length(v_key)), o.value
       LIMIT 8;
  ELSE
    RAISE EXCEPTION 'Unknown search type %.', p_kind;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_supplier_save(p_token text, p_id uuid, p_name text, p_status text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_old   supplier%ROWTYPE;
  v_used  text;
  v_id    uuid;
BEGIN
  IF p_id IS NULL THEN
    INSERT INTO supplier (name, status, updated_by) VALUES (p_name, 'ACTIVE', v_email) RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  SELECT * INTO v_old FROM supplier WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Supplier not found.';
  END IF;
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Supplier status is required (ACTIVE / INACTIVE).';
  END IF;
  IF fn_normalize(p_name) IS DISTINCT FROM v_old.name_key THEN
    v_used := fn_master_usage('SUPPLIER', p_id, true);
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION 'The name of supplier % cannot be changed: it is used in published documents (%). Add a new supplier if needed.', v_old.name, v_used;
    END IF;
  END IF;
  IF p_status = 'INACTIVE' AND v_old.status <> 'INACTIVE' THEN
    v_used := fn_master_usage('SUPPLIER', p_id, false);
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION 'Supplier % is still used in drafts: %. Replace it in those drafts first.', v_old.name, v_used;
    END IF;
  END IF;
  UPDATE supplier SET name = p_name, status = p_status, updated_by = v_email WHERE id = p_id;
  RETURN p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_component_save(p_token text, p_id uuid, p_group_code text, p_number integer, p_name text, p_status text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_old   component%ROWTYPE;
  v_used  text;
BEGIN
  SELECT * INTO v_old FROM component WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Component not found.';
  END IF;
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Component status is required (ACTIVE / INACTIVE).';
  END IF;
  IF fn_normalize(p_name) IS DISTINCT FROM fn_normalize(v_old.name)
     OR p_number IS DISTINCT FROM v_old.number OR p_group_code IS DISTINCT FROM v_old.group_code THEN
    v_used := fn_master_usage('COMPONENT', p_id, true);
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION 'Name, number, and group of component % cannot be changed: it is used in published documents (%).', v_old.number, v_used;
    END IF;
  END IF;
  IF p_status = 'INACTIVE' AND v_old.status <> 'INACTIVE' THEN
    v_used := fn_master_usage('COMPONENT', p_id, false);
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION 'Component % is still used in drafts: %. Replace it in those drafts first.', v_old.number, v_used;
    END IF;
  END IF;
  UPDATE component
     SET group_code = p_group_code, number = p_number, name = p_name, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_material_add(p_token text, p_name text, p_category text, p_uom text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email   text := fn_auth(p_token, 'manage_master');
  v_factory uuid := fn_user_factory(v_email);
  v_id      uuid;
BEGIN
  IF v_factory IS NULL THEN
    RAISE EXCEPTION 'Your account has no factory yet. Ask the System Admin to set your factory.';
  END IF;
  INSERT INTO material (factory_id, name, category, uom, price_method, status, updated_by)
  VALUES (v_factory, p_name, p_category, p_uom, 'CATALOG', 'ACTIVE', v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_link_save(p_token text, p_link_id uuid, p_material_id uuid, p_supplier_id uuid, p_is_preferred boolean, p_status text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_old   material_supplier%ROWTYPE;
  v_mat   uuid;
  v_id    uuid;
  v_pref  boolean := coalesce(p_is_preferred, false);
BEGIN
  IF p_link_id IS NULL THEN
    IF p_supplier_id IS NULL THEN
      RAISE EXCEPTION 'Select a supplier.';
    END IF;
    SELECT factory_id INTO v_mat FROM material WHERE id = p_material_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Material not found.';
    END IF;
    PERFORM fn_assert_factory(v_email, v_mat);
    INSERT INTO material_supplier (material_id, supplier_id, status, updated_by)
    VALUES (p_material_id, p_supplier_id, 'ACTIVE', v_email)
    RETURNING * INTO v_old;
  ELSE
    SELECT * INTO v_old FROM material_supplier WHERE id = p_link_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Material supplier not found.';
    END IF;
    PERFORM fn_assert_factory(v_email, (SELECT factory_id FROM material WHERE id = v_old.material_id));
    IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
      RAISE EXCEPTION 'Material supplier status is required (ACTIVE / INACTIVE).';
    END IF;
    UPDATE material_supplier
       SET status = p_status,
           is_preferred = CASE WHEN p_status = 'INACTIVE' THEN false ELSE is_preferred END,
           updated_by = v_email
     WHERE id = p_link_id
    RETURNING * INTO v_old;
    IF v_old.status = 'INACTIVE' THEN
      v_pref := false;                  -- dinonaktifkan: otomatis bukan supplier utama lagi
    END IF;
  END IF;
  v_id := v_old.id;

  -- Supplier utama: maksimal satu per material induk (= per pabrik)
  IF v_pref AND NOT v_old.is_preferred THEN
    UPDATE material_supplier SET is_preferred = false, updated_by = v_email
     WHERE material_id = v_old.material_id AND is_preferred AND id <> v_id;
    UPDATE material_supplier SET is_preferred = true, updated_by = v_email WHERE id = v_id;
  ELSIF NOT v_pref AND v_old.is_preferred THEN
    UPDATE material_supplier SET is_preferred = false, updated_by = v_email WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_option_kind_label(p_kind text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_kind
    WHEN 'KATEGORI' THEN 'Category' WHEN 'CONSTRUCTION' THEN 'Construction' WHEN 'GENDER' THEN 'Gender'
    WHEN 'UKURAN' THEN 'Size' WHEN 'LAST' THEN 'Last' WHEN 'OUTSOLE_MOLD' THEN 'Outsole mold'
    ELSE p_kind END
$function$;

CREATE OR REPLACE FUNCTION public.fn_material_update(p_token text, p_id uuid, p_name text, p_category text, p_uom text, p_status text, p_price_method text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email  text := fn_auth_any(p_token, ARRAY['manage_master', 'manage_price']);
  v_master boolean := fn_has_perm(v_email, 'manage_master');
  v_price  boolean := fn_has_perm(v_email, 'manage_price');
  v_old    material%ROWTYPE;
BEGIN
  SELECT * INTO v_old FROM material WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Material not found.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_old.factory_id);
  IF NOT v_master AND (
       fn_normalize(p_name) IS DISTINCT FROM v_old.name_key
    OR fn_normalize(p_category) IS DISTINCT FROM fn_normalize(v_old.category)
    OR fn_normalize(p_uom) IS DISTINCT FROM fn_normalize(v_old.uom)
    OR p_status IS DISTINCT FROM v_old.status) THEN
    RAISE EXCEPTION 'Material data and status can only be changed by the specsheet team (Vendor Spec).';
  END IF;
  IF NOT v_price AND p_price_method IS DISTINCT FROM v_old.price_method THEN
    RAISE EXCEPTION 'The price method can only be changed by the CBD team.';
  END IF;
  IF v_master AND coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Material status is required (ACTIVE / INACTIVE).';
  END IF;
  IF v_price AND coalesce(p_price_method, '') NOT IN ('CATALOG', 'QUOTATION') THEN
    RAISE EXCEPTION 'Price method is required.';
  END IF;
  -- T57: dokumen terbit membaca nama / kategori / UoM material langsung dari master
  IF v_master AND (fn_normalize(p_name) IS DISTINCT FROM v_old.name_key
                   OR fn_normalize(p_category) IS DISTINCT FROM fn_normalize(v_old.category)
                   OR fn_normalize(p_uom) IS DISTINCT FROM fn_normalize(v_old.uom))
     AND fn_material_used_published(p_id) THEN
    RAISE EXCEPTION 'Name, category, and UoM of material % cannot be changed: it is used in a published specsheet / CBD. Add a new material if needed (the status can still be changed).', v_old.name;
  END IF;
  UPDATE material
     SET name         = CASE WHEN v_master THEN p_name     ELSE name END,
         category     = CASE WHEN v_master THEN p_category ELSE category END,
         uom          = CASE WHEN v_master THEN p_uom      ELSE uom END,
         status       = CASE WHEN v_master THEN p_status   ELSE status END,
         price_method = CASE WHEN v_price  THEN p_price_method ELSE price_method END,
         updated_by   = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_model_option_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_other text;
BEGIN
  NEW.value := upper(btrim(regexp_replace(coalesce(NEW.value, ''), '\s+', ' ', 'g')));
  IF NEW.value = '' THEN
    RAISE EXCEPTION 'Option value is required.';
  END IF;
  IF TG_OP = 'UPDATE' AND (NEW.kind IS DISTINCT FROM OLD.kind OR NEW.factory_id IS DISTINCT FROM OLD.factory_id) THEN
    RAISE EXCEPTION 'The option type and factory cannot be changed.';
  END IF;
  IF NEW.kind = 'UKURAN' THEN
    IF NEW.value !~ '^[0-9]{1,2}$' OR NEW.value::integer < 1 THEN
      RAISE EXCEPTION 'Size must be a whole number (e.g. 40), no half sizes.';
    END IF;
    NEW.value := NEW.value::integer::text;          -- "040" -> "40"
    NEW.sort_order := NEW.value::integer;           -- ukuran selalu urut angka
  END IF;
  SELECT value INTO v_other FROM model_option
   WHERE kind = NEW.kind AND factory_id IS NOT DISTINCT FROM NEW.factory_id
     AND value_key = fn_normalize(NEW.value) AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION '% "%" already exists.', fn_option_kind_label(NEW.kind), v_other;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_option_save(p_token text, p_id uuid, p_kind text, p_value text, p_sort_order integer, p_status text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email   text := fn_auth(p_token, 'manage_master');
  v_factory uuid := fn_user_factory(v_email);
  v_old     model_option%ROWTYPE;
  v_used    text;
  v_id      uuid;
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Option status is required (ACTIVE / INACTIVE).';
  END IF;
  IF p_id IS NULL THEN
    IF p_kind IS NULL OR p_kind NOT IN ('KATEGORI', 'CONSTRUCTION', 'GENDER', 'UKURAN', 'LAST', 'OUTSOLE_MOLD') THEN
      RAISE EXCEPTION 'Select an option type.';
    END IF;
    IF fn_option_is_factory_kind(p_kind) AND v_factory IS NULL THEN
      RAISE EXCEPTION '% is set per factory, but your account has no factory.', fn_option_kind_label(p_kind);
    END IF;
    INSERT INTO model_option (kind, factory_id, value, sort_order, status, updated_by)
    VALUES (p_kind, CASE WHEN fn_option_is_factory_kind(p_kind) THEN v_factory END, p_value, p_sort_order, p_status, v_email)
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  SELECT * INTO v_old FROM model_option WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Option not found.';
  END IF;
  IF v_old.factory_id IS NOT NULL THEN
    PERFORM fn_assert_factory(v_email, v_old.factory_id);
  END IF;
  IF fn_normalize(p_value) IS DISTINCT FROM v_old.value_key THEN
    IF v_old.kind = 'UKURAN' THEN
      SELECT string_agg(pm.name, ', ' ORDER BY pm.name) INTO v_used
        FROM product_model pm WHERE v_old.value ~ '^[0-9]+$' AND v_old.value::integer = ANY (pm.sizes);
    ELSE
      SELECT string_agg(DISTINCT pm.name, ', ') INTO v_used
        FROM product_model pm
       WHERE p_id IN (pm.category_id, pm.construction_id, pm.gender_id, pm.last_id, pm.outsole_mold_id)
         AND EXISTS (SELECT 1 FROM specsheet sh JOIN specsheet_revision r ON r.specsheet_id = sh.id
                      WHERE sh.model_id = pm.id AND r.status = 'PUBLISHED');
    END IF;
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION '% "%" is used by model %, so its value cannot be changed. Set it INACTIVE and add a new value.',
        fn_option_kind_label(v_old.kind), v_old.value, left(v_used, 200);
    END IF;
  END IF;
  UPDATE model_option SET value = p_value, sort_order = p_sort_order, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_material_variant_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory uuid;
  v_other   record;
  v_tkey    text;
  v_ckey    text;
  v_confirm boolean := coalesce(current_setting('app.variant_confirm', true), '') = 'on';
BEGIN
  NEW.code      := upper(btrim(regexp_replace(coalesce(NEW.code, ''), '\s+', ' ', 'g')));
  NEW.color     := upper(btrim(regexp_replace(coalesce(NEW.color, ''), '\s+', ' ', 'g')));
  NEW.thickness := fn_clean_thickness(NEW.thickness);
  v_tkey := fn_normalize(coalesce(NEW.thickness, ''));
  v_ckey := fn_normalize(NEW.color);
  IF NEW.code = '' THEN
    RAISE EXCEPTION 'Material Code is required.';
  END IF;
  IF NEW.color = '' THEN
    RAISE EXCEPTION 'Color is required.';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.material_id IS DISTINCT FROM OLD.material_id THEN
    RAISE EXCEPTION 'A variant cannot be moved to another material.';
  END IF;
  SELECT factory_id INTO v_factory FROM material WHERE id = NEW.material_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Parent material not found.';
  END IF;
  NEW.factory_id := v_factory;

  -- TOLAK: kode unik per pabrik
  SELECT v.code, m.name, v.color, v.thickness INTO v_other
    FROM material_variant v JOIN material m ON m.id = v.material_id
   WHERE v.factory_id = NEW.factory_id AND v.code = NEW.code AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material Code % is already used: % · % · %.',
      NEW.code, v_other.name, v_other.color, fn_thickness_label(v_other.thickness);
  END IF;

  -- TOLAK: satu kode per material + thickness + warna
  SELECT v.code INTO v_other
    FROM material_variant v
   WHERE v.material_id = NEW.material_id AND v.thickness_key = v_tkey AND v.color_key = v_ckey AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Variant % · % already exists in this material (code %). If ERP really has another code, make the color name differ as in ERP (e.g. WHITE C).',
      NEW.color, fn_thickness_label(NEW.thickness), v_other.code;
  END IF;

  -- KONFIRMASI: bagian kode ERP (10 karakter) yang sudah punya arti lain di pabrik ini.
  -- Hanya dicek saat varian baru atau kode / warna / thickness berubah (ubah status saja tidak ditanya lagi).
  IF length(NEW.code) = 10 AND NOT v_confirm
     AND (TG_OP = 'INSERT' OR NEW.code IS DISTINCT FROM OLD.code OR NEW.color IS DISTINCT FROM OLD.color
          OR NEW.thickness IS DISTINCT FROM OLD.thickness) THEN
    SELECT v.code, v.thickness INTO v_other
      FROM material_variant v
     WHERE v.factory_id = NEW.factory_id AND length(v.code) = 10 AND v.id <> NEW.id
       AND substr(v.code, 5, 3) = substr(NEW.code, 5, 3) AND v.thickness_key <> v_tkey
     ORDER BY v.created_at LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'Confirmation needed: thickness code % is recorded as "%" (code %), not "%". Check the Material Code; if it matches ERP, tick the confirmation and save.',
        substr(NEW.code, 5, 3), fn_thickness_label(v_other.thickness), v_other.code, fn_thickness_label(NEW.thickness);
    END IF;
    SELECT v.code, v.color INTO v_other
      FROM material_variant v
     WHERE v.factory_id = NEW.factory_id AND length(v.code) = 10 AND v.id <> NEW.id
       AND substr(v.code, 8, 3) = substr(NEW.code, 8, 3) AND v.color_key <> v_ckey
     ORDER BY v.created_at LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'Confirmation needed: color code % is recorded as "%" (code %), not "%". Check the Material Code; if it matches ERP, tick the confirmation and save.',
        substr(NEW.code, 8, 3), v_other.color, v_other.code, NEW.color;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_price_propose(p_token text, p_link_id uuid, p_variant_ids jsonb, p_price numeric, p_currency text, p_valid_from date, p_reference text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, 'manage_price');
  v_link  record;
  v_ids   uuid[] := fn_uuid_list(p_variant_ids);
  v_from  date := coalesce(p_valid_from, fn_today());
  v_ref   text := nullif(btrim(coalesce(p_reference, '')), '');
  v_batch uuid := gen_random_uuid();
  v_bad   text;
BEGIN
  SELECT ms.id, ms.status, ms.material_id, s.name AS supplier_name, s.status AS supplier_status,
         m.factory_id, m.name AS material_name, m.status AS material_status, m.price_method
    INTO v_link
    FROM material_supplier ms
    JOIN supplier s ON s.id = ms.supplier_id
    JOIN material m ON m.id = ms.material_id
   WHERE ms.id = p_link_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Select a supplier.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_link.factory_id);
  IF v_link.material_status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Material % is INACTIVE and cannot get a new price.', v_link.material_name;
  END IF;
  IF v_link.price_method = 'QUOTATION' THEN
    RAISE EXCEPTION 'This material uses the Quotation price method. Its price is entered per CBD, not in the master.';
  END IF;
  IF v_link.status = 'INACTIVE' OR v_link.supplier_status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Supplier % is inactive for this material and cannot get a new price.', v_link.supplier_name;
  END IF;
  IF p_price IS NULL OR p_price <= 0 THEN
    RAISE EXCEPTION 'Price must be above 0.';
  END IF;
  IF coalesce(p_currency, '') NOT IN ('IDR', 'USD') THEN
    RAISE EXCEPTION 'Currency is required (IDR or USD).';
  END IF;
  IF cardinality(v_ids) = 0 THEN
    RAISE EXCEPTION 'Tick at least one variant.';
  END IF;

  IF EXISTS (SELECT 1 FROM unnest(v_ids) AS x(id)
              WHERE NOT EXISTS (SELECT 1 FROM material_variant v WHERE v.id = x.id AND v.material_id = v_link.material_id)) THEN
    RAISE EXCEPTION 'Some variants do not belong to this material. Please reload the page.';
  END IF;
  SELECT string_agg(v.code, ', ' ORDER BY v.code) INTO v_bad
    FROM material_variant v WHERE v.id = ANY (v_ids) AND v.status = 'INACTIVE';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'INACTIVE variants cannot get a price: %.', v_bad;
  END IF;
  SELECT string_agg(v.code || ' (' || trim_scale(mp.price)::text || ' ' || mp.currency || ')', ', ' ORDER BY v.code) INTO v_bad
    FROM material_price mp JOIN material_variant v ON v.id = mp.variant_id
   WHERE mp.material_supplier_id = p_link_id AND mp.variant_id = ANY (v_ids) AND mp.status = 'PROPOSED';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'There are still price proposals from % waiting for approval for: %. Cancel them first or wait for Manager Costing to process them.',
      v_link.supplier_name, v_bad;
  END IF;
  SELECT string_agg(v.code || ' (active ' || to_char(mp.valid_from, 'DD-MM-YYYY') || ')', ', ' ORDER BY v.code) INTO v_bad
    FROM material_price mp JOIN material_variant v ON v.id = mp.variant_id
   WHERE mp.material_supplier_id = p_link_id AND mp.variant_id = ANY (v_ids)
     AND mp.status = 'APPROVED' AND mp.valid_to IS NULL AND mp.valid_from > v_from;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'The start date cannot be earlier than an existing price: %.', v_bad;
  END IF;

  INSERT INTO material_price (material_supplier_id, variant_id, batch_id, price, currency, valid_from, reference,
                              status, updated_by)
  SELECT p_link_id, x.id, v_batch, p_price, p_currency, v_from, v_ref, 'PROPOSED', v_email
    FROM unnest(v_ids) AS x(id);
  RETURN v_batch;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_price_copy(p_token text, p_source_id uuid, p_target_ids jsonb, p_valid_from date, p_reference text)
 RETURNS TABLE(batch_id uuid, created integer, skipped text)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  v_email   text := fn_auth(p_token, 'manage_price');
  v_src     record;
  v_ids     uuid[];
  v_from    date := coalesce(p_valid_from, fn_today());
  v_ref     text;
  v_batch   uuid := gen_random_uuid();
  v_n       integer := 0;
  v_sources integer := 0;
  v_skip    text[] := ARRAY[]::text[];
  r         record;
  t         record;
  v_date    date;
BEGIN
  SELECT v.id, v.code, v.material_id, v.status, m.factory_id, m.name AS material_name,
         m.status AS material_status, m.price_method
    INTO v_src
    FROM material_variant v JOIN material m ON m.id = v.material_id
   WHERE v.id = p_source_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Select a source variant.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_src.factory_id);
  IF v_src.material_status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Material % is INACTIVE and cannot get a new price.', v_src.material_name;
  END IF;
  IF v_src.price_method = 'QUOTATION' THEN
    RAISE EXCEPTION 'This material uses the Quotation price method. Its price is entered per CBD, not in the master.';
  END IF;
  v_ids := array_remove(fn_uuid_list(p_target_ids), p_source_id);
  IF cardinality(v_ids) = 0 THEN
    RAISE EXCEPTION 'Tick at least one target variant.';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_ids) AS x(id)
              WHERE NOT EXISTS (SELECT 1 FROM material_variant v WHERE v.id = x.id AND v.material_id = v_src.material_id)) THEN
    RAISE EXCEPTION 'Target variants must be from the same material. Please reload the page.';
  END IF;
  IF EXISTS (SELECT 1 FROM material_variant v WHERE v.id = ANY (v_ids) AND v.status = 'INACTIVE') THEN
    RAISE EXCEPTION 'INACTIVE variants cannot get a price: %.',
      (SELECT string_agg(v.code, ', ' ORDER BY v.code) FROM material_variant v WHERE v.id = ANY (v_ids) AND v.status = 'INACTIVE');
  END IF;
  v_ref := coalesce(nullif(btrim(coalesce(p_reference, '')), ''), 'Copied from ' || v_src.code);

  FOR r IN
    SELECT ms.id AS link_id, s.name AS supplier_name, lp.price, lp.currency
      FROM material_supplier ms
      JOIN supplier s ON s.id = ms.supplier_id
      CROSS JOIN LATERAL fn_price_lookup(p_source_id, ms.supplier_id) AS lp
     WHERE ms.material_id = v_src.material_id
     ORDER BY s.name
  LOOP
    v_sources := v_sources + 1;
    FOR t IN SELECT v.id, v.code FROM material_variant v WHERE v.id = ANY (v_ids) ORDER BY v.code LOOP
      IF EXISTS (SELECT 1 FROM material_price mp
                  WHERE mp.material_supplier_id = r.link_id AND mp.variant_id = t.id AND mp.status = 'PROPOSED') THEN
        v_skip := v_skip || (t.code || ' · ' || r.supplier_name || ': a proposal is still pending');
        CONTINUE;
      END IF;
      SELECT max(mp.valid_from) INTO v_date FROM material_price mp
       WHERE mp.material_supplier_id = r.link_id AND mp.variant_id = t.id
         AND mp.status = 'APPROVED' AND mp.valid_to IS NULL AND mp.valid_from > v_from;
      IF v_date IS NOT NULL THEN
        v_skip := v_skip || (t.code || ' · ' || r.supplier_name || ': already has a price from ' || to_char(v_date, 'DD-MM-YYYY'));
        CONTINUE;
      END IF;
      INSERT INTO material_price (material_supplier_id, variant_id, batch_id, price, currency, valid_from, reference,
                                  status, updated_by)
      VALUES (r.link_id, t.id, v_batch, r.price, r.currency, v_from, v_ref, 'PROPOSED', v_email);
      v_n := v_n + 1;
    END LOOP;
  END LOOP;

  IF v_sources = 0 THEN
    RAISE EXCEPTION 'Source variant % has no active (approved) price from an active supplier.', v_src.code;
  END IF;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'No prices were copied: %.', array_to_string(v_skip, '; ');
  END IF;
  RETURN QUERY SELECT v_batch, v_n, nullif(array_to_string(v_skip, '; '), '');
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_model_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_other text;
BEGIN
  NEW.name := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  IF NEW.name = '' THEN
    RAISE EXCEPTION 'Model name is required.';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.factory_id IS DISTINCT FROM OLD.factory_id THEN
    RAISE EXCEPTION 'The model factory cannot be changed.';
  END IF;
  SELECT name INTO v_other FROM product_model
   WHERE factory_id = NEW.factory_id AND name_key = fn_normalize(NEW.name) AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Model "%" already exists in this factory.', v_other;
  END IF;
  NEW.sizes := nullif(ARRAY(SELECT DISTINCT x FROM unnest(coalesce(NEW.sizes, ARRAY[]::integer[])) AS x
                             WHERE x IS NOT NULL ORDER BY x), ARRAY[]::integer[]);
  IF EXISTS (SELECT 1 FROM unnest(coalesce(NEW.sizes, ARRAY[]::integer[])) AS x WHERE x < 1 OR x > 99) THEN
    RAISE EXCEPTION 'Sizes must be whole numbers 1–99.';
  END IF;
  IF NEW.sample_size IS NOT NULL AND NOT (NEW.sample_size = ANY (coalesce(NEW.sizes, ARRAY[]::integer[]))) THEN
    RAISE EXCEPTION 'Sample size % must be one of the model sizes.', NEW.sample_size;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_check_material(p_material_id uuid, p_factory uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_mat material%ROWTYPE;
BEGIN
  SELECT * INTO v_mat FROM material WHERE id = p_material_id;
  IF NOT FOUND OR v_mat.factory_id IS DISTINCT FROM p_factory THEN
    RAISE EXCEPTION 'Select a material from this factory''s Master Material.';
  END IF;
  IF v_mat.status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Material % is INACTIVE. Select another material.', v_mat.name;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_add_sub(p_token text, p_parent_line_id uuid, p_sub_name text, p_material_id uuid, p_thickness text, p_supplier_id uuid, p_process text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory uuid := fn_line_factory(p_parent_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_parent  bom_line%ROWTYPE;
  v_name    text := nullif(btrim(regexp_replace(coalesce(p_sub_name, ''), '\s+', ' ', 'g')), '');
  v_id      uuid;
BEGIN
  SELECT * INTO v_parent FROM bom_line WHERE id = p_parent_line_id;
  IF NOT FOUND OR NOT v_parent.is_active THEN
    RAISE EXCEPTION 'Parent line not found or no longer active.';
  END IF;
  PERFORM fn_revision_draft(v_parent.revision_id);
  IF v_parent.parent_line_key IS NOT NULL THEN
    RAISE EXCEPTION 'A subcomponent cannot be added under another subcomponent.';
  END IF;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Subcomponent name is required.';
  END IF;
  PERFORM fn_bom_check_material(p_material_id, v_factory);
  PERFORM fn_bom_check_supplier(p_material_id, p_supplier_id);

  INSERT INTO bom_line (revision_id, line_key, parent_line_key, sub_seq, sub_name, material_id, thickness, supplier_id,
                        process, sort_order, updated_by)
  VALUES (v_parent.revision_id, gen_random_uuid(), v_parent.line_key,
          coalesce((SELECT max(sub_seq) FROM bom_line
                     WHERE revision_id = v_parent.revision_id AND parent_line_key = v_parent.line_key), 0) + 1,
          v_name, p_material_id, fn_clean_thickness(p_thickness), p_supplier_id, nullif(btrim(coalesce(p_process, '')), ''),
          v_parent.sort_order, v_email)
  RETURNING id INTO v_id;
  PERFORM fn_bom_create_cells(v_id, v_email);
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_replace_material(p_token text, p_line_id uuid, p_material_id uuid, p_thickness text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory uuid := fn_line_factory(p_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_old     bom_line%ROWTYPE;
  v_thick   text := fn_clean_thickness(p_thickness);
  v_key     uuid := gen_random_uuid();
  v_id      uuid;
BEGIN
  SELECT * INTO v_old FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_old.is_active THEN
    RAISE EXCEPTION 'Line not found or no longer active. Please reload the page.';
  END IF;
  PERFORM fn_revision_draft(v_old.revision_id);
  IF v_old.material_id = p_material_id AND v_old.thickness IS NOT DISTINCT FROM v_thick THEN
    RAISE EXCEPTION 'The new material and thickness are the same as the current ones.';
  END IF;
  PERFORM fn_bom_check_material(p_material_id, v_factory);
  IF v_old.parent_line_key IS NULL AND EXISTS (
       SELECT 1 FROM bom_line WHERE revision_id = v_old.revision_id AND is_active AND parent_line_key IS NULL
          AND id <> v_old.id AND material_id = p_material_id AND thickness IS NOT DISTINCT FROM v_thick
          AND component_id IS NOT DISTINCT FROM v_old.component_id
          AND local_component_no IS NOT DISTINCT FROM v_old.local_component_no) THEN
    RAISE EXCEPTION 'This component with that material + thickness is already in this revision.';
  END IF;
  IF v_old.material_id <> p_material_id THEN
    PERFORM fn_bom_check_supplier(p_material_id, v_old.supplier_id);
  END IF;

  UPDATE bom_line SET is_active = false, updated_by = v_email WHERE id = v_old.id;
  INSERT INTO bom_line (revision_id, line_key, origin_line_key, replaces_line_key, component_id,
                        local_component_no, local_component_name, parent_line_key, sub_seq, sub_name,
                        material_id, thickness, supplier_id, process, sort_order, updated_by)
  VALUES (v_old.revision_id, v_key, v_old.origin_line_key, v_old.line_key, v_old.component_id,
          v_old.local_component_no, v_old.local_component_name, v_old.parent_line_key, v_old.sub_seq,
          v_old.sub_name, p_material_id, v_thick, v_old.supplier_id, v_old.process, v_old.sort_order, v_email)
  RETURNING id INTO v_id;
  INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
  SELECT v_id, article_id, color, v_email FROM bom_cell WHERE bom_line_id = v_old.id;
  PERFORM fn_bom_create_cells(v_id, v_email);
  UPDATE bom_line SET parent_line_key = v_key, updated_by = v_email
   WHERE revision_id = v_old.revision_id AND parent_line_key = v_old.line_key AND is_active;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_set_supplier(p_token text, p_line_id uuid, p_supplier_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Line not found or no longer active. Please reload the page.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  PERFORM fn_bom_check_supplier(v_line.material_id, p_supplier_id);
  UPDATE bom_line SET supplier_id = p_supplier_id, updated_by = v_email WHERE id = v_line.id;
  RETURN v_line.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_set_process(p_token text, p_line_id uuid, p_process text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Line not found or no longer active. Please reload the page.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  UPDATE bom_line SET process = nullif(btrim(coalesce(p_process, '')), ''), updated_by = v_email WHERE id = v_line.id;
  RETURN v_line.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_cell_set(p_token text, p_line_id uuid, p_article_id uuid, p_color text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory uuid := fn_line_factory(p_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_line    bom_line%ROWTYPE;
  v_color   text := nullif(upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g'))), '');
  v_var     record;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Line not found or no longer active. Please reload the page.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  IF NOT EXISTS (SELECT 1 FROM revision_article
                  WHERE revision_id = v_line.revision_id AND article_id = p_article_id AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'This article is not active in this revision.';
  END IF;
  IF v_color IS NOT NULL THEN
    SELECT v.material_id, v.thickness, v.thickness_key, v.color, v.status, m.name INTO v_var
      FROM material_variant v JOIN material m ON m.id = v.material_id
     WHERE v.factory_id = v_factory AND v.code = v_color;
    IF FOUND THEN
      IF v_var.material_id <> v_line.material_id
         OR v_var.thickness_key <> fn_normalize(coalesce(v_line.thickness, '')) THEN
        RAISE EXCEPTION 'Code % is % · % · %. It does not match the material / thickness of this line.',
          v_color, v_var.name, fn_thickness_label(v_var.thickness), v_var.color;
      END IF;
      IF v_var.status = 'INACTIVE' THEN
        RAISE EXCEPTION 'Code % is INACTIVE.', v_color;
      END IF;
      v_color := v_var.color;
    END IF;
  END IF;
  INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
  VALUES (v_line.id, p_article_id, v_color, v_email)
  ON CONFLICT (bom_line_id, article_id) DO UPDATE SET color = EXCLUDED.color, updated_by = EXCLUDED.updated_by;
  RETURN v_line.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_change_category_label(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p WHEN 'EX_RATE' THEN 'Exchange rate' WHEN 'LOP' THEN 'LOP' WHEN 'AMORTIZATION' THEN 'Amortization'
                WHEN 'MATERIAL' THEN 'Material' WHEN 'YIELD' THEN 'Yield / Loss %' WHEN 'COMPONENT' THEN 'Component'
                WHEN 'TREATMENT' THEN 'Treatment' WHEN 'OTHER' THEN 'Other' ELSE p END
$function$;

CREATE OR REPLACE FUNCTION public.fn_revision_publish(p_token text, p_revision_id uuid, p_category text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_specsheet', fn_rev_factory(p_revision_id));
  v_rev    specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
  v_chk    v_revision_checklist%ROWTYPE;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_id     uuid;
BEGIN
  SELECT * INTO v_chk FROM v_revision_checklist WHERE revision_id = v_rev.id;
  IF v_chk.active_articles = 0 THEN
    RAISE EXCEPTION 'The specsheet needs at least one active article before publishing.';
  END IF;
  IF v_chk.unused_articles IS NOT NULL THEN
    RAISE EXCEPTION 'Article % is not used in any BOM line (enter a color in at least one line).', v_chk.unused_articles;
  END IF;
  IF v_chk.inactive_materials IS NOT NULL THEN
    RAISE EXCEPTION 'Some lines use INACTIVE materials: %. Replace them first.', v_chk.inactive_materials;
  END IF;
  IF v_chk.no_supplier_lines > 0 THEN
    RAISE EXCEPTION '% BOM line(s) have no supplier. Fill in the supplier of all lines first.', v_chk.no_supplier_lines;
  END IF;
  IF v_chk.yellow_cells > 0 THEN
    RAISE EXCEPTION '% color cell(s) have no Material Code (yellow cells): %. Register the variants first.',
      v_chk.yellow_cells, v_chk.yellow_list;
  END IF;
  IF v_chk.inactive_suppliers IS NOT NULL THEN
    RAISE EXCEPTION 'Some suppliers are inactive: %. Replace them first.', v_chk.inactive_suppliers;
  END IF;
  IF coalesce(p_category, '') NOT IN ('EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER') THEN
    RAISE EXCEPTION 'Select a change category.';
  END IF;
  IF v_chk.requires_reason AND v_reason IS NULL THEN
    RAISE EXCEPTION 'A change reason is required for this revision.';
  END IF;

  UPDATE specsheet_revision
     SET status = 'PUBLISHED', published_at = now(), published_by = v_email, updated_by = v_email
   WHERE id = v_rev.id;

  INSERT INTO change_log (doc_type, revision_id, category, reason, created_by)
  VALUES ('SPECSHEET', v_rev.id, p_category, coalesce(v_reason, 'Initial revision.'), v_email)
  RETURNING id INTO v_id;

  PERFORM fn_cbd_sync_spec(v_rev.id, v_email);   -- F8
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_material_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_other record;
BEGIN
  NEW.name     := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  NEW.category := btrim(regexp_replace(coalesce(NEW.category, ''), '\s+', ' ', 'g'));
  NEW.uom      := upper(btrim(coalesce(NEW.uom, '')));
  IF NEW.factory_id IS NULL THEN RAISE EXCEPTION 'Material factory is required.'; END IF;
  IF NEW.name = ''          THEN RAISE EXCEPTION 'Material name is required.'; END IF;
  IF NEW.category = ''      THEN RAISE EXCEPTION 'Material category is required.'; END IF;
  IF NEW.uom = ''           THEN RAISE EXCEPTION 'UoM is required.'; END IF;
  IF TG_OP = 'UPDATE' AND NEW.factory_id IS DISTINCT FROM OLD.factory_id THEN
    RAISE EXCEPTION 'The material factory cannot be changed.';
  END IF;
  SELECT name, uom INTO v_other FROM material
   WHERE factory_id = NEW.factory_id AND name_key = fn_normalize(NEW.name) AND uom = NEW.uom AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material "%" (%) already exists in this factory. Add the variant to that material.', v_other.name, v_other.uom;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_header_set(p_token text, p_cbd_revision_id uuid, p_field text, p_value numeric)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev   cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
BEGIN
  IF p_field = 'RATE' THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION 'Exchange rate must be above 0 (leave empty if not known yet).';
    END IF;
    UPDATE cbd_revision SET exchange_rate = p_value, updated_by = v_email WHERE id = v_rev.id;
  ELSIF p_field = 'TARGET_FOB' THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION 'Target FOB must be above 0 (leave empty if not known yet).';
    END IF;
    UPDATE cbd_revision SET target_fob = p_value, updated_by = v_email WHERE id = v_rev.id;
  ELSE
    RAISE EXCEPTION 'Invalid field (selling price & margin are not saved in the CBD).';
  END IF;
  RETURN v_rev.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_cost_set(p_token text, p_item_id uuid, p_field text, p_value text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_item_factory(p_item_id));
  v_item  cbd_cost_item%ROWTYPE := fn_cbd_cost_item(p_item_id);
  v_text  text := nullif(btrim(coalesce(p_value, '')), '');
  v_num   numeric;
BEGIN
  IF p_field = 'NAME' THEN
    IF v_text IS NULL THEN
      RAISE EXCEPTION 'Cost description is required.';
    END IF;
    UPDATE cbd_cost_item SET name = v_text, updated_by = v_email WHERE id = v_item.id;
  ELSIF p_field = 'AMOUNT' THEN
    IF v_text IS NOT NULL AND v_text !~ '^-?[0-9]+(\.[0-9]+)?$' THEN
      RAISE EXCEPTION 'Cost value must be a number.';
    END IF;
    v_num := coalesce(v_text::numeric, 0);
    PERFORM fn_cbd_check_cost(v_item.item_type, v_num);
    UPDATE cbd_cost_item SET amount = v_num, updated_by = v_email WHERE id = v_item.id;
  ELSIF p_field = 'REMARKS' THEN
    UPDATE cbd_cost_item SET remarks = v_text, updated_by = v_email WHERE id = v_item.id;
  ELSE
    RAISE EXCEPTION 'Invalid field.';
  END IF;
  RETURN v_item.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_cost_delete(p_token text, p_item_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_item_factory(p_item_id));
  v_item  cbd_cost_item%ROWTYPE := fn_cbd_cost_item(p_item_id);
BEGIN
  IF v_item.is_default THEN
    RAISE EXCEPTION 'Line % is always present and cannot be deleted (enter 0 if not used).', v_item.name;
  END IF;
  DELETE FROM cbd_cost_item WHERE id = v_item.id;
  RETURN v_item.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_refresh_prices(p_token text, p_cbd_revision_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev   cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
  v_n     integer;
BEGIN
  UPDATE cbd_line l
     SET price_original = pc.master_price, currency = pc.master_currency,
         price_source = CASE WHEN pc.master_price_id IS NOT NULL THEN 'MASTER' END,
         material_price_id = pc.master_price_id, price_override_reason = NULL, price_reference = NULL,
         updated_by = v_email
    FROM v_cbd_price_check pc
   WHERE pc.line_id = l.id AND pc.cbd_revision_id = v_rev.id AND pc.master_stale;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'All line prices already match the master.';
  END IF;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_set_quotation(p_token text, p_line_id uuid, p_price numeric, p_currency text, p_reference text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_line_factory(p_line_id));
  v_line  cbd_line%ROWTYPE := fn_cbd_price_line(p_line_id);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM material WHERE id = v_line.material_id AND price_method = 'QUOTATION') THEN
    RAISE EXCEPTION 'Quotation prices are only for materials with the Quotation price method. Catalog materials use master prices.';
  END IF;
  IF p_price IS NULL THEN
    UPDATE cbd_line SET price_original = NULL, currency = NULL, price_source = NULL, material_price_id = NULL,
                        price_override_reason = NULL, price_reference = NULL, updated_by = v_email
     WHERE id = v_line.id;
  ELSE
    PERFORM fn_cbd_check_price(p_price, p_currency);
    UPDATE cbd_line SET price_original = p_price, currency = p_currency, price_source = 'QUOTATION',
                        material_price_id = NULL, price_override_reason = NULL,
                        price_reference = nullif(btrim(coalesce(p_reference, '')), ''),
                        no_charge = false, no_charge_reason = NULL, updated_by = v_email
     WHERE id = v_line.id;
  END IF;
  RETURN v_line.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_revision_create(p_token text, p_specsheet_id uuid, p_mode text, p_stage text, p_source_specsheet_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_specsheet', fn_sheet_factory(p_specsheet_id));
  v_stages text[] := fn_stages();
  v_sheet  specsheet%ROWTYPE;
  v_srcsp  specsheet%ROWTYPE;
  v_src    specsheet_revision%ROWTYPE;
  v_tgtm   product_model%ROWTYPE;
  v_srcm   product_model%ROWTYPE;
  v_cross  boolean := false;
  v_stage  text;
  v_no     integer := 0;
  v_id     uuid;
BEGIN
  SELECT * INTO v_sheet FROM specsheet WHERE id = p_specsheet_id FOR UPDATE;   -- antre per season
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Season not found.';
  END IF;
  IF EXISTS (SELECT 1 FROM specsheet_revision WHERE specsheet_id = p_specsheet_id AND status = 'DRAFT') THEN
    RAISE EXCEPTION 'Season % already has a DRAFT revision. Publish or delete that draft first.', v_sheet.season;
  END IF;

  IF p_mode IN ('EMPTY', 'COPY') THEN
    IF EXISTS (SELECT 1 FROM specsheet_revision WHERE specsheet_id = p_specsheet_id) THEN
      RAISE EXCEPTION 'Season % already has revisions. Use Next revision or Next stage.', v_sheet.season;
    END IF;
    v_stage := coalesce(nullif(p_stage, ''), 'PULL');
    IF NOT v_stage = ANY (v_stages) THEN
      RAISE EXCEPTION 'Invalid stage.';
    END IF;
    IF p_mode = 'COPY' THEN
      SELECT * INTO v_srcsp FROM specsheet WHERE id = p_source_specsheet_id;
      IF NOT FOUND OR v_srcsp.id = v_sheet.id THEN
        RAISE EXCEPTION 'Select a source season.';
      END IF;
      IF v_srcsp.model_id <> v_sheet.model_id THEN
        SELECT * INTO v_tgtm FROM product_model WHERE id = v_sheet.model_id;
        SELECT * INTO v_srcm FROM product_model WHERE id = v_srcsp.model_id;
        IF v_srcm.factory_id IS DISTINCT FROM v_tgtm.factory_id THEN
          RAISE EXCEPTION 'A specsheet can only be copied from a model of the same factory.';
        END IF;
        IF v_srcm.category_id IS DISTINCT FROM v_tgtm.category_id THEN
          RAISE EXCEPTION 'Copying from another model is only for models with the same category.';
        END IF;
        v_cross := true;
      END IF;
      SELECT * INTO v_src FROM specsheet_revision
       WHERE specsheet_id = v_srcsp.id AND status = 'PUBLISHED'
       ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Season % has no published revision to copy.', v_srcsp.season;
      END IF;
    END IF;

    INSERT INTO specsheet_revision (specsheet_id, stage, revision_no, source_revision_id, updated_by)
    VALUES (p_specsheet_id, v_stage, 0, v_src.id, v_email)
    RETURNING id INTO v_id;

    IF p_mode = 'COPY' THEN
      WITH src AS MATERIALIZED (
        SELECT l.*, gen_random_uuid() AS new_key FROM bom_line l WHERE l.revision_id = v_src.id AND l.is_active
      )
      INSERT INTO bom_line (revision_id, line_key, origin_line_key, component_id, local_component_no,
                            local_component_name, parent_line_key, sub_seq, sub_name, material_id, thickness,
                            supplier_id, process, sort_order, updated_by)
      SELECT v_id, s.new_key, s.line_key, s.component_id, s.local_component_no, s.local_component_name,
             p.new_key, s.sub_seq, s.sub_name, s.material_id, s.thickness, s.supplier_id, s.process, s.sort_order, v_email
        FROM src s LEFT JOIN src p ON p.line_key = s.parent_line_key
       WHERE s.parent_line_key IS NULL OR p.line_key IS NOT NULL;
      IF v_cross AND v_tgtm.parent_model_id IS NULL THEN
        UPDATE product_model SET parent_model_id = v_srcm.id, updated_by = v_email WHERE id = v_tgtm.id;
      END IF;
    END IF;

    INSERT INTO revision_article (revision_id, article_id, updated_by)
    SELECT v_id, a.id, v_email FROM article a WHERE a.specsheet_id = p_specsheet_id;
    INSERT INTO bom_cell (bom_line_id, article_id, updated_by)
    SELECT l.id, a.id, v_email
      FROM bom_line l CROSS JOIN article a
     WHERE l.revision_id = v_id AND a.specsheet_id = p_specsheet_id;

  ELSIF p_mode IN ('NEXT_REVISION', 'NEXT_STAGE') THEN
    SELECT * INTO v_src FROM specsheet_revision
     WHERE specsheet_id = p_specsheet_id AND status = 'PUBLISHED'
     ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Season % has no published revision yet.', v_sheet.season;
    END IF;
    IF p_mode = 'NEXT_REVISION' THEN
      v_stage := v_src.stage;
      SELECT max(revision_no) + 1 INTO v_no FROM specsheet_revision
       WHERE specsheet_id = p_specsheet_id AND stage = v_stage;
    ELSE
      -- R14: stage tujuan boleh melompat (mis. Pullover -> SMS); kosong = stage berikutnya
      v_stage := nullif(btrim(coalesce(p_stage, '')), '');
      IF v_stage IS NULL THEN
        IF v_src.stage = v_stages[array_length(v_stages, 1)] THEN
          RAISE EXCEPTION 'Already at the last stage (%). Use Next revision.', fn_stage_label(v_src.stage);
        END IF;
        v_stage := v_stages[fn_stage_order(v_src.stage) + 1];
      ELSIF NOT v_stage = ANY (v_stages) THEN
        RAISE EXCEPTION 'Unknown stage %.', fn_stage_label(v_stage);
      ELSIF fn_stage_order(v_stage) <= v_src.stage_order THEN
        RAISE EXCEPTION 'Stage must be higher than the latest published stage (%).', fn_stage_label(v_src.stage);
      END IF;
      v_no := 0;
    END IF;

    INSERT INTO specsheet_revision (specsheet_id, stage, revision_no, source_revision_id, updated_by)
    VALUES (p_specsheet_id, v_stage, v_no, v_src.id, v_email)
    RETURNING id INTO v_id;

    INSERT INTO bom_line (revision_id, line_key, origin_line_key, replaces_line_key, component_id,
                          local_component_no, local_component_name, parent_line_key, sub_seq, sub_name,
                          material_id, thickness, supplier_id, process, sort_order, updated_by)
    SELECT v_id, l.line_key, l.origin_line_key, l.replaces_line_key, l.component_id, l.local_component_no,
           l.local_component_name, l.parent_line_key, l.sub_seq, l.sub_name, l.material_id, l.thickness, l.supplier_id,
           l.process, l.sort_order, v_email
      FROM bom_line l WHERE l.revision_id = v_src.id AND l.is_active;
    INSERT INTO revision_article (revision_id, article_id, status, updated_by)
    SELECT v_id, ra.article_id, ra.status, v_email FROM revision_article ra WHERE ra.revision_id = v_src.id;
    INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
    SELECT n.id, c.article_id, c.color, v_email
      FROM bom_cell c
      JOIN bom_line o ON o.id = c.bom_line_id AND o.revision_id = v_src.id AND o.is_active
      JOIN bom_line n ON n.revision_id = v_id AND n.line_key = o.line_key;
  ELSE
    RAISE EXCEPTION 'Choose how to create the revision.';
  END IF;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_refresh_from_spec(p_token text, p_cbd_revision_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev    cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);   -- dikunci, article ACTIVE di stage-nya
  v_spec   specsheet_revision%ROWTYPE;
  v_lines  cbd_line[];
  v_n      integer;
BEGIN
  SELECT sr.* INTO v_spec FROM specsheet_revision sr
   WHERE sr.id = fn_spec_latest_pub_stage((SELECT specsheet_id FROM article WHERE id = v_rev.article_id), v_rev.stage);
  IF v_spec.id = v_rev.specsheet_revision_id THEN
    RAISE EXCEPTION 'This CBD already uses the latest published % specsheet (% r%).', fn_stage_label(v_rev.stage), fn_stage_label(v_spec.stage), v_spec.revision_no;
  END IF;

  SELECT array_agg(l ORDER BY l.sort_order) INTO v_lines FROM cbd_line l WHERE l.cbd_revision_id = v_rev.id;
  DELETE FROM cbd_line WHERE cbd_revision_id = v_rev.id;
  UPDATE cbd_revision SET specsheet_revision_id = v_spec.id, updated_by = v_email WHERE id = v_rev.id;
  v_n := fn_cbd_populate(v_rev.id, v_rev.article_id, v_spec.id, v_lines, true, NULL, v_email);
  PERFORM fn_audit(v_email, 'cbd_revision', v_rev.id::text, 'REFRESH_FROM_SPEC');
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_price_propose(p_token text, p_line_id uuid, p_price numeric, p_currency text, p_valid_from date, p_reference text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'manage_price', fn_cbd_line_factory(p_line_id));
  v_line  record;
  v_link  uuid;
BEGIN
  SELECT cl.status, cl.variant_id, cl.supplier_id, cl.material_id, m.price_method, m.name AS material_name
    INTO v_line
    FROM cbd_line cl JOIN material m ON m.id = cl.material_id
   WHERE cl.id = p_line_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CBD line not found. Please reload the page.';
  END IF;
  IF v_line.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'This line is no longer in the specsheet (MISSING_IN_SPEC).';
  END IF;
  IF v_line.price_method <> 'CATALOG' THEN
    RAISE EXCEPTION 'Material % uses the Quotation method. Enter its price with Enter price, not as a master price.', v_line.material_name;
  END IF;
  IF v_line.variant_id IS NULL THEN
    RAISE EXCEPTION 'This line has no Material Code (variant). Register it in the specsheet first.';
  END IF;
  IF v_line.supplier_id IS NULL THEN
    RAISE EXCEPTION 'This line has no supplier in the specsheet.';
  END IF;
  SELECT id INTO v_link FROM material_supplier WHERE material_id = v_line.material_id AND supplier_id = v_line.supplier_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This line''s supplier is not linked to the material. Link it in Material Detail.';
  END IF;
  RETURN fn_price_propose(p_token, v_link, jsonb_build_array(v_line.variant_id), p_price, p_currency, p_valid_from, p_reference);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_variant_save(p_token text, p_id uuid, p_material_id uuid, p_code text, p_color text, p_thickness text, p_status text, p_confirm boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_mat   material%ROWTYPE;
  v_old   material_variant%ROWTYPE;
  v_id    uuid;
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Variant status is required (ACTIVE / INACTIVE).';
  END IF;
  PERFORM set_config('app.variant_confirm', CASE WHEN coalesce(p_confirm, false) THEN 'on' ELSE 'off' END, true);
  IF p_id IS NULL THEN
    SELECT * INTO v_mat FROM material WHERE id = p_material_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Material not found.';
    END IF;
    PERFORM fn_assert_factory(v_email, v_mat.factory_id);
    IF v_mat.status = 'INACTIVE' THEN
      RAISE EXCEPTION 'Material % is INACTIVE. Activate it before adding variants.', v_mat.name;
    END IF;
    INSERT INTO material_variant (material_id, factory_id, code, color, thickness, status, updated_by)
    VALUES (p_material_id, v_mat.factory_id, p_code, p_color, p_thickness, p_status, v_email)
    RETURNING id INTO v_id;
    PERFORM set_config('app.variant_confirm', 'off', true);
    RETURN v_id;
  END IF;
  SELECT * INTO v_old FROM material_variant WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Variant not found.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_old.factory_id);
  IF (upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g'))) IS DISTINCT FROM v_old.code
      OR upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g'))) IS DISTINCT FROM v_old.color
      OR fn_clean_thickness(p_thickness) IS DISTINCT FROM v_old.thickness)
     AND fn_variant_used_published(p_id) THEN
    RAISE EXCEPTION 'Variant % is used in published documents. Its Material Code, color, and thickness cannot be changed. Set it INACTIVE and register a new variant.', v_old.code;
  END IF;
  UPDATE material_variant
     SET code = p_code, color = p_color, thickness = p_thickness, status = p_status, updated_by = v_email
   WHERE id = p_id;
  PERFORM set_config('app.variant_confirm', 'off', true);
  RETURN p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_variant_delete_block(p_variant_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nullif(concat_ws('; ',
    (SELECT 'used in ' || count(DISTINCT l.revision_id) || ' specsheet revision(s)'
       FROM bom_cell bc JOIN bom_line l ON l.id = bc.bom_line_id
      WHERE bc.variant_id = p_variant_id HAVING count(*) > 0),
    (SELECT 'used in ' || count(DISTINCT cl.cbd_revision_id) || ' CBD revision(s)'
       FROM cbd_line cl WHERE cl.variant_id = p_variant_id HAVING count(*) > 0),
    (SELECT 'still has prices: ' || string_agg(DISTINCT x.state, ' / ') || ' (' || count(*) || ')'
       FROM material_price mp
       CROSS JOIN LATERAL (SELECT fn_price_state(mp.status, mp.valid_from, mp.valid_to) AS state) x
      WHERE mp.variant_id = p_variant_id AND x.state IN ('PENDING APPROVAL', 'ACTIVE', 'UPCOMING')
      HAVING count(*) > 0)
  ), '')
$function$;

CREATE OR REPLACE FUNCTION public.fn_variant_delete(p_token text, p_id uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_row   material_variant%ROWTYPE;
  v_block text;
BEGIN
  SELECT * INTO v_row FROM material_variant WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Variant not found (maybe already deleted). Please reload the page.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_row.factory_id);
  v_block := fn_variant_delete_block(p_id);
  IF v_block IS NOT NULL THEN
    RAISE EXCEPTION 'Variant % cannot be deleted: %. Set it INACTIVE if it is no longer used.', v_row.code, v_block;
  END IF;
  DELETE FROM material_price WHERE variant_id = p_id;     -- tinggal harga berakhir / ditolak
  DELETE FROM material_variant WHERE id = p_id;
  RETURN v_row.code;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_model_save(p_token text, p_id uuid, p_name text, p_category_id uuid, p_construction_id uuid, p_gender_id uuid, p_last_id uuid, p_outsole_mold_id uuid, p_sizes jsonb, p_sample_size integer)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email   text := fn_auth(p_token, 'edit_model');
  v_old     product_model%ROWTYPE;
  v_factory uuid;
  v_sizes   integer[];
  v_id      uuid;
BEGIN
  IF p_id IS NULL THEN
    v_factory := fn_user_factory(v_email);
    IF v_factory IS NULL THEN
      RAISE EXCEPTION 'Your account has no factory yet. Ask the System Admin to set your factory.';
    END IF;
  ELSE
    SELECT * INTO v_old FROM product_model WHERE id = p_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Model not found.';
    END IF;
    PERFORM fn_assert_factory(v_email, v_old.factory_id);
    v_factory := v_old.factory_id;
    -- T57: nama model tampil di specsheet / CBD terbit
    IF fn_normalize(p_name) IS DISTINCT FROM v_old.name_key
       AND EXISTS (SELECT 1 FROM specsheet sh JOIN specsheet_revision r ON r.specsheet_id = sh.id
                    WHERE sh.model_id = p_id AND r.status = 'PUBLISHED') THEN
      RAISE EXCEPTION 'The name of model % cannot be changed: it is used in a published specsheet.', v_old.name;
    END IF;
  END IF;
  IF p_category_id IS NULL THEN
    RAISE EXCEPTION 'Category is required.';
  END IF;
  PERFORM fn_model_option_ref(p_category_id, 'KATEGORI', v_factory, v_old.category_id);
  PERFORM fn_model_option_ref(p_construction_id, 'CONSTRUCTION', v_factory, v_old.construction_id);
  PERFORM fn_model_option_ref(p_gender_id, 'GENDER', v_factory, v_old.gender_id);
  PERFORM fn_model_option_ref(p_last_id, 'LAST', v_factory, v_old.last_id);
  PERFORM fn_model_option_ref(p_outsole_mold_id, 'OUTSOLE_MOLD', v_factory, v_old.outsole_mold_id);
  IF jsonb_typeof(coalesce(p_sizes, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'Invalid size list.';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(coalesce(p_sizes, '[]'::jsonb)) AS e WHERE e !~ '^[0-9]{1,2}$') THEN
    RAISE EXCEPTION 'Sizes must be whole numbers (no half sizes).';
  END IF;
  v_sizes := ARRAY(SELECT DISTINCT e::integer FROM jsonb_array_elements_text(coalesce(p_sizes, '[]'::jsonb)) AS e ORDER BY 1);

  IF p_id IS NULL THEN
    INSERT INTO product_model (factory_id, name, category_id, construction_id, gender_id, last_id, outsole_mold_id,
                               sizes, sample_size, updated_by)
    VALUES (v_factory, p_name, p_category_id, p_construction_id, p_gender_id, p_last_id, p_outsole_mold_id,
            v_sizes, p_sample_size, v_email)
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  UPDATE product_model
     SET name = p_name, category_id = p_category_id, construction_id = p_construction_id, gender_id = p_gender_id,
         last_id = p_last_id, outsole_mold_id = p_outsole_mold_id, sizes = v_sizes, sample_size = p_sample_size,
         updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_price_decide(p_token text, p_price_ids jsonb, p_decision text, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email  text := fn_auth(p_token, 'approve_price');
  v_ids    uuid[] := fn_uuid_list(p_price_ids);
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_n      integer := 0;
  r        record;
BEGIN
  IF coalesce(p_decision, '') NOT IN ('APPROVE', 'REJECT') THEN
    RAISE EXCEPTION 'Unknown decision.';
  END IF;
  IF cardinality(v_ids) = 0 THEN
    RAISE EXCEPTION 'Select at least one price.';
  END IF;
  IF p_decision = 'REJECT' AND v_reason IS NULL THEN
    RAISE EXCEPTION 'Reject reason is required.';
  END IF;
  PERFORM 1 FROM material_price WHERE id = ANY (v_ids) ORDER BY id FOR UPDATE;
  FOR r IN
    SELECT x.id AS req_id, mp.id, mp.status, mp.created_by, v.code, v.status AS variant_status,
           ms.status AS link_status, s.name AS supplier_name, s.status AS supplier_status,
           m.price_method, m.factory_id
      FROM unnest(v_ids) AS x(id)
      LEFT JOIN material_price mp ON mp.id = x.id
      LEFT JOIN material_variant v ON v.id = mp.variant_id
      LEFT JOIN material_supplier ms ON ms.id = mp.material_supplier_id
      LEFT JOIN supplier s ON s.id = ms.supplier_id
      LEFT JOIN material m ON m.id = ms.material_id
     ORDER BY v.code, s.name
  LOOP
    IF r.id IS NULL THEN
      RAISE EXCEPTION 'Some proposals no longer exist (maybe cancelled by the proposer). Please reload the page.';
    END IF;
    PERFORM fn_assert_factory(v_email, r.factory_id);
    IF r.status <> 'PROPOSED' THEN
      RAISE EXCEPTION 'Proposal % · % is already processed (%). Please reload the page.', r.code, r.supplier_name, r.status;
    END IF;
    IF r.created_by = v_email THEN
      RAISE EXCEPTION 'You cannot process your own proposals.';
    END IF;
    IF p_decision = 'APPROVE' THEN
      IF r.price_method <> 'CATALOG' THEN
        RAISE EXCEPTION 'The material now uses the Quotation method. Reject proposal %.', r.code;
      END IF;
      IF r.link_status = 'INACTIVE' OR r.supplier_status = 'INACTIVE' THEN
        RAISE EXCEPTION 'Supplier % is inactive. Reject proposal %.', r.supplier_name, r.code;
      END IF;
      IF r.variant_status = 'INACTIVE' THEN
        RAISE EXCEPTION 'Variant % is INACTIVE. Reject its proposal.', r.code;
      END IF;
      PERFORM fn_price_activate(r.id, v_email);
    ELSE
      UPDATE material_price
         SET status = 'REJECTED', reject_reason = v_reason, decided_by = v_email, decided_at = now(), updated_by = v_email
       WHERE id = r.id AND status = 'PROPOSED';
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_delete_line(p_token text, p_line_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
  v_old   bom_line%ROWTYPE;
  v_subs  integer;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Line not found or no longer active. Please reload the page.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  SELECT * INTO v_old FROM bom_line WHERE id = fn_bom_undo_target(v_line.id);
  IF FOUND THEN
    UPDATE bom_line SET parent_line_key = v_old.line_key, updated_by = v_email
     WHERE revision_id = v_line.revision_id AND parent_line_key = v_line.line_key;
    DELETE FROM bom_line WHERE id = v_line.id;
    UPDATE bom_line SET is_active = true, updated_by = v_email WHERE id = v_old.id;
    UPDATE bom_cell SET color = color WHERE bom_line_id = v_old.id;     -- sambungkan ulang Material Code (trigger)
    PERFORM fn_bom_create_cells(v_old.id, v_email);                     -- article yang ditambah setelah penggantian
    RETURN 0;
  END IF;
  DELETE FROM bom_line WHERE revision_id = v_line.revision_id AND parent_line_key = v_line.line_key;
  GET DIAGNOSTICS v_subs = ROW_COUNT;
  DELETE FROM bom_line WHERE id = v_line.id;
  RETURN v_subs + 1;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_set_no_charge(p_token text, p_line_id uuid, p_on boolean, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_line_factory(p_line_id));
  v_line   cbd_line%ROWTYPE := fn_cbd_price_line(p_line_id);     -- draft + baris ACTIVE
  v_reason text := nullif(btrim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g')), '');
BEGIN
  IF coalesce(p_on, false) THEN
    IF v_reason IS NULL THEN
      RAISE EXCEPTION 'Enter the no-charge reason (e.g. "price included in line 10").';
    END IF;
    UPDATE cbd_line SET no_charge = true, no_charge_reason = left(v_reason, 200), updated_by = v_email WHERE id = v_line.id;
  ELSE
    UPDATE cbd_line SET no_charge = false, no_charge_reason = NULL, updated_by = v_email WHERE id = v_line.id;
  END IF;
  RETURN v_line.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_bridge(p_rev uuid)
 RETURNS TABLE(seq integer, key text, category text, description text, amount numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
#variable_conflict use_column
DECLARE
  v_prev  uuid := fn_cbd_prev_published(p_rev);
  v_rc    numeric;
  v_rp    numeric;
  v_rate  numeric := 0;
  v_n     integer := 0;
  v_used  uuid[] := '{}';
  c       record;
  p       record;
  it      record;
  v_okc   boolean;
  v_okp   boolean;
  v_ufc   numeric;
  v_ufp   numeric;
  v_costc numeric;
  v_costp numeric;
  v_pe    numeric;
  v_ye    numeric;
  v_re    numeric;
  v_lbl   text;
  v_parts text[];
  v_out   jsonb := '[]';
BEGIN
  IF v_prev IS NULL THEN
    RETURN;
  END IF;
  SELECT exchange_rate INTO v_rc FROM cbd_revision WHERE id = p_rev;
  SELECT exchange_rate INTO v_rp FROM cbd_revision WHERE id = v_prev;

  FOR c IN SELECT * FROM v_cbd_line WHERE cbd_revision_id = p_rev AND status = 'ACTIVE' ORDER BY group_sort, sort_order LOOP
    SELECT * INTO p FROM v_cbd_line
     WHERE cbd_revision_id = v_prev AND status = 'ACTIVE' AND NOT (id = ANY (v_used)) AND line_key = c.line_key LIMIT 1;
    IF NOT FOUND AND c.replaces_line_key IS NOT NULL THEN
      SELECT * INTO p FROM v_cbd_line
       WHERE cbd_revision_id = v_prev AND status = 'ACTIVE' AND NOT (id = ANY (v_used)) AND line_key = c.replaces_line_key LIMIT 1;
    END IF;
    IF p.id IS NULL THEN          -- sama dengan fn_cbd_populate: komponen + material + thickness (+ sub) sama
      SELECT v.* INTO p
        FROM v_cbd_line v
        JOIN cbd_line x ON x.id = v.id
        JOIN cbd_line y ON y.id = c.id
       WHERE v.cbd_revision_id = v_prev AND v.status = 'ACTIVE' AND NOT (v.id = ANY (v_used))
         AND fn_cbd_identity(x.component_id, x.local_component_no, x.sub_seq, x.sub_name, x.material_id, x.thickness)
           = fn_cbd_identity(y.component_id, y.local_component_no, y.sub_seq, y.sub_name, y.material_id, y.thickness)
       ORDER BY v.sort_order LIMIT 1;
    END IF;
    v_lbl := btrim(concat_ws(' ', c.display_no, c.display_name));
    v_costc := coalesce(c.cost_per_pair, 0);
    IF p.id IS NULL THEN
      IF v_costc <> 0 THEN
        v_out := v_out || jsonb_build_object('key', 'L:' || c.line_key || ':ADD', 'category', 'COMPONENT', 'amount', v_costc,
                   'description', '+ ' || v_lbl || ' · ' || c.material_name || coalesce(' ' || c.thickness, ''));
      END IF;
      CONTINUE;
    END IF;
    v_used := v_used || p.id;
    v_costp := coalesce(p.cost_per_pair, 0);
    v_okc := NOT c.no_charge AND c.usage_value IS NOT NULL AND c.price_original IS NOT NULL AND c.price_idr IS NOT NULL;
    v_okp := NOT p.no_charge AND p.usage_value IS NOT NULL AND p.price_original IS NOT NULL AND p.price_idr IS NOT NULL;
    v_re := 0;
    IF v_okc AND v_okp AND c.currency = 'USD' AND p.currency = 'USD' THEN
      v_ufp := p.usage_value * (1 + coalesce(p.loss_pct, 0) / 100);
      v_re := v_ufp * p.price_original * (v_rc - v_rp);
      v_rate := v_rate + v_re;
    END IF;
    IF v_okc AND v_okp AND c.material_id = p.material_id AND c.variant_id IS NOT DISTINCT FROM p.variant_id THEN
      v_ufc := c.usage_value * (1 + coalesce(c.loss_pct, 0) / 100);
      v_ufp := p.usage_value * (1 + coalesce(p.loss_pct, 0) / 100);
      v_pe := CASE WHEN c.currency = 'USD' AND p.currency = 'USD' THEN v_ufp * (c.price_original - p.price_original) * v_rc
                   ELSE v_ufp * (c.price_idr - p.price_idr) END;
      v_ye := (v_ufc - v_ufp) * c.price_idr;
      IF v_pe <> 0 THEN
        v_out := v_out || jsonb_build_object('key', 'L:' || c.line_key || ':PRICE', 'category', 'MATERIAL', 'amount', v_pe,
                   'description', v_lbl || ' · ' || c.material_name || ': price ' || fn_fmt_id(p.price_original, 4) || ' '
                                  || p.currency || ' → ' || fn_fmt_id(c.price_original, 4) || ' ' || c.currency);
      END IF;
      IF v_ye <> 0 THEN
        v_parts := '{}';
        IF c.yield_value IS DISTINCT FROM p.yield_value THEN
          v_parts := v_parts || ('yield ' || fn_fmt_id(p.yield_value, 6) || ' → ' || fn_fmt_id(c.yield_value, 6));
        END IF;
        IF coalesce(c.loss_pct, 0) <> coalesce(p.loss_pct, 0) THEN
          v_parts := v_parts || ('loss ' || fn_fmt_id(coalesce(p.loss_pct, 0), 2) || '% → ' || fn_fmt_id(coalesce(c.loss_pct, 0), 2) || '%');
        END IF;
        v_out := v_out || jsonb_build_object('key', 'L:' || c.line_key || ':YIELD', 'category', 'YIELD', 'amount', v_ye,
                   'description', v_lbl || ' · ' || c.material_name || ': '
                                  || coalesce(nullif(array_to_string(v_parts, ', '), ''), 'usage changed'));
      END IF;
    ELSIF v_costc - v_costp - v_re <> 0 THEN
      v_out := v_out || jsonb_build_object('key', 'L:' || c.line_key || ':MAT', 'category', 'MATERIAL',
                 'amount', v_costc - v_costp - v_re,
                 'description', v_lbl || ': ' ||
                   CASE WHEN c.no_charge AND NOT p.no_charge THEN 'set to no charge (' || c.no_charge_reason || ')'
                        WHEN p.no_charge AND NOT c.no_charge THEN 'no longer no charge'
                        WHEN c.material_id <> p.material_id OR c.variant_id IS DISTINCT FROM p.variant_id
                          THEN 'material changed: ' || p.material_name || coalesce(' [' || p.material_code || ']', '') || ' → '
                               || c.material_name || coalesce(' [' || c.material_code || ']', '')
                        ELSE 'cost ' || fn_fmt_id(v_costp, 2) || ' → ' || fn_fmt_id(v_costc, 2) END);
    END IF;
  END LOOP;

  -- baris lama yang tidak ada lagi
  FOR p IN SELECT * FROM v_cbd_line WHERE cbd_revision_id = v_prev AND status = 'ACTIVE' AND NOT (id = ANY (v_used))
           ORDER BY group_sort, sort_order LOOP
    IF coalesce(p.cost_per_pair, 0) <> 0 THEN
      v_out := v_out || jsonb_build_object('key', 'L:' || p.line_key || ':DEL', 'category', 'COMPONENT', 'amount', -p.cost_per_pair,
                 'description', '− ' || btrim(concat_ws(' ', p.display_no, p.display_name)) || ' · ' || p.material_name
                                || coalesce(' ' || p.thickness, ''));
    END IF;
  END LOOP;

  IF v_rate <> 0 THEN
    v_out := jsonb_build_object('key', 'RATE', 'category', 'EX_RATE', 'amount', v_rate,
               'description', 'Exchange rate ' || fn_fmt_id(v_rp, 4) || ' → ' || fn_fmt_id(v_rc, 4)) || v_out;
  END IF;

  -- baris biaya (cocok per jenis + nama)
  FOR it IN
    SELECT coalesce(a.item_type, b.item_type) AS item_type, coalesce(a.name, b.name) AS name,
           coalesce(a.amount, 0) AS amt_c, coalesce(b.amount, 0) AS amt_p, a.name IS NOT NULL AS in_c, b.name IS NOT NULL AS in_p
      FROM (SELECT item_type, fn_normalize(name) AS k, min(name) AS name, sum(amount) AS amount, min(sort_order) AS so
              FROM cbd_cost_item WHERE cbd_revision_id = p_rev GROUP BY 1, 2) a
      FULL JOIN (SELECT item_type, fn_normalize(name) AS k, min(name) AS name, sum(amount) AS amount, min(sort_order) AS so
                   FROM cbd_cost_item WHERE cbd_revision_id = v_prev GROUP BY 1, 2) b
        ON b.item_type = a.item_type AND b.k = a.k
     ORDER BY fn_change_category_sort(CASE coalesce(a.item_type, b.item_type) WHEN 'LABOUR' THEN 'LOP'
                                       WHEN 'AMORTIZATION' THEN 'AMORTIZATION' ELSE 'OTHER' END),
              coalesce(a.so, b.so), coalesce(a.name, b.name)
  LOOP
    IF it.amt_c - it.amt_p <> 0 THEN
      v_out := v_out || jsonb_build_object('key', 'I:' || it.item_type || ':' || fn_normalize(it.name),
                 'category', CASE it.item_type WHEN 'LABOUR' THEN 'LOP' WHEN 'AMORTIZATION' THEN 'AMORTIZATION' ELSE 'OTHER' END,
                 'amount', it.amt_c - it.amt_p,
                 'description', CASE WHEN NOT it.in_p THEN '+ ' || it.name || ' ' || fn_fmt_id(it.amt_c, 2)
                                     WHEN NOT it.in_c THEN '− ' || it.name || ' ' || fn_fmt_id(it.amt_p, 2)
                                     ELSE it.name || ' ' || fn_fmt_id(it.amt_p, 2) || ' → ' || fn_fmt_id(it.amt_c, 2) END);
    END IF;
  END LOOP;

  RETURN QUERY
    SELECT (row_number() OVER (ORDER BY fn_change_category_sort(x ->> 'category'), o.ord))::integer,
           x ->> 'key', x ->> 'category', x ->> 'description', (x ->> 'amount')::numeric
      FROM jsonb_array_elements(v_out) WITH ORDINALITY AS o(x, ord)
     ORDER BY 1;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_change_log_attach(p_token text, p_change_log_id uuid, p_file_name text, p_data text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_log   change_log%ROWTYPE;
  v_email text;
  v_bytes bytea;
  v_mime  text;
  v_id    uuid;
BEGIN
  SELECT * INTO v_log FROM change_log WHERE id = p_change_log_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Change log not found.';
  END IF;
  v_email := fn_auth_in(p_token, CASE v_log.doc_type WHEN 'CBD' THEN 'edit_cbd' ELSE 'edit_specsheet' END,
                        CASE v_log.doc_type WHEN 'CBD' THEN fn_cbd_factory(v_log.revision_id)
                                            ELSE fn_rev_factory(v_log.revision_id) END);
  IF v_log.created_by IS DISTINCT FROM v_email OR v_log.created_at < now() - interval '1 hour' THEN
    RAISE EXCEPTION 'Images can only be attached by the publisher, while publishing.';
  END IF;
  IF (SELECT count(*) FROM change_log_attachment WHERE change_log_id = v_log.id) >= 5 THEN
    RAISE EXCEPTION 'Max 5 images per publish.';
  END IF;
  BEGIN
    v_bytes := decode(regexp_replace(coalesce(p_data, ''), '^data:[^,]*,', ''), 'base64');
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'Invalid image content.';
  END;
  IF length(v_bytes) = 0 THEN
    RAISE EXCEPTION 'The image is empty.';
  END IF;
  IF length(v_bytes) > 3670016 THEN
    RAISE EXCEPTION 'Max image size is 3.5 MB.';
  END IF;
  IF substring(v_bytes FROM 1 FOR 8) = '\x89504e470d0a1a0a'::bytea THEN
    v_mime := 'image/png';
  ELSIF substring(v_bytes FROM 1 FOR 3) = '\xffd8ff'::bytea THEN
    v_mime := 'image/jpeg';
  ELSE
    RAISE EXCEPTION 'Only PNG or JPG images.';
  END IF;
  INSERT INTO change_log_attachment (change_log_id, file_name, mime_type, size_bytes, content, updated_by)
  VALUES (v_log.id, coalesce(nullif(btrim(coalesce(p_file_name, '')), ''), 'image'), v_mime, length(v_bytes), v_bytes, v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_publish(p_token text, p_cbd_revision_id uuid, p_category text, p_reason text, p_bridge jsonb DEFAULT NULL::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email    text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev      cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
  v_chk      v_cbd_checklist%ROWTYPE;
  v_reason   text := nullif(btrim(coalesce(p_reason, '')), '');
  v_category text := p_category;
  v_prev     cbd_revision%ROWTYPE;
  v_rows     jsonb := '[]';
  v_edits    jsonb := CASE WHEN jsonb_typeof(p_bridge) = 'array' THEN p_bridge ELSE '[]'::jsonb END;
  v_fob      numeric;
  v_pfob     numeric;
  v_diff     jsonb;
  v_id       uuid;
  v_higher   text;
  c_cats     text[] := ARRAY['EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER'];
BEGIN
  SELECT * INTO v_chk FROM v_cbd_checklist WHERE cbd_revision_id = v_rev.id;
  IF v_chk.spec_stale THEN
    RAISE EXCEPTION 'The reference % specsheet of this CBD has a newer published revision. Click "Refresh from Specsheet" first.', fn_stage_label(v_rev.stage);
  END IF;
  SELECT fn_rev_label(o.stage, o.revision_no) INTO v_higher FROM cbd_revision o
   WHERE o.article_id = v_rev.article_id AND o.status = 'PUBLISHED' AND o.stage_order > v_rev.stage_order
   ORDER BY o.stage_order DESC, o.revision_no DESC LIMIT 1;
  IF v_higher IS NOT NULL THEN
    RAISE EXCEPTION 'A % CBD is already published. The % CBD cannot be published anymore. Delete this draft.', v_higher, fn_stage_label(v_rev.stage);
  END IF;
  IF NOT v_chk.rate_ok THEN
    RAISE EXCEPTION 'Fill in the exchange rate (above 0) in the recap first.';
  END IF;
  IF v_chk.pending_prices > 0 THEN
    RAISE EXCEPTION '% line(s) have prices waiting for Manager Costing approval (%). Wait until they are processed, then refresh prices.',
      v_chk.pending_prices, v_chk.pending_list;
  END IF;
  IF v_chk.stale_prices > 0 THEN
    RAISE EXCEPTION 'Master prices for % line(s) have changed. Click "Refresh Prices from Master" first.', v_chk.stale_prices;
  END IF;
  IF v_chk.no_yield_count > 0 THEN
    RAISE EXCEPTION '% priced line(s) have no Yield.', v_chk.no_yield_count;
  END IF;

  -- A4: rincian perubahan vs revisi terbit sebelumnya
  SELECT * INTO v_prev FROM cbd_revision WHERE id = fn_cbd_prev_published(v_rev.id);
  IF v_prev.id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_edits) x
                WHERE nullif(btrim(x ->> 'category'), '') IS NOT NULL AND NOT (btrim(x ->> 'category') = ANY (c_cats))) THEN
      RAISE EXCEPTION 'Invalid change breakdown category.';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'seq', b.seq, 'key', b.key, 'amount', b.amount, 'auto_category', b.category,
             'category', coalesce(e.cat, b.category),
             'description', left(coalesce(e.descr, b.description), 300)) ORDER BY b.seq), '[]'::jsonb)
      INTO v_rows
      FROM fn_cbd_bridge(v_rev.id) b
      LEFT JOIN LATERAL (SELECT nullif(btrim(x ->> 'category'), '') AS cat,
                                nullif(btrim(regexp_replace(coalesce(x ->> 'description', ''), '\s+', ' ', 'g')), '') AS descr
                           FROM jsonb_array_elements(v_edits) x
                          WHERE x ->> 'key' = b.key LIMIT 1) e ON true;
    v_fob  := (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = v_rev.id);
    v_pfob := (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = v_prev.id);
    IF abs(coalesce((SELECT sum((r ->> 'amount')::numeric) FROM jsonb_array_elements(v_rows) r), 0) - (v_fob - v_pfob)) > 0.000001 THEN
      RAISE EXCEPTION 'The change breakdown does not match the Actual FOB difference. Contact the developer (revision %).', v_rev.id;
    END IF;
    v_diff := jsonb_build_object('prev_revision_id', v_prev.id, 'prev_label', fn_rev_label(v_prev.stage, v_prev.revision_no),
                                 'prev_fob', v_pfob, 'fob', v_fob, 'rows', v_rows);
  END IF;

  IF jsonb_array_length(v_rows) > 0 THEN
    SELECT r ->> 'category' INTO v_category FROM jsonb_array_elements(v_rows) r
     ORDER BY abs((r ->> 'amount')::numeric) DESC, (r ->> 'seq')::integer LIMIT 1;
    IF v_reason IS NULL THEN
      SELECT string_agg(fn_change_category_label(g.cat) || ' ' || CASE WHEN g.amt >= 0 THEN '+' ELSE '−' END
                        || fn_fmt_id(abs(g.amt), 2), '; ' ORDER BY fn_change_category_sort(g.cat))
        INTO v_reason
        FROM (SELECT r ->> 'category' AS cat, sum((r ->> 'amount')::numeric) AS amt
                FROM jsonb_array_elements(v_rows) r GROUP BY 1) g;
    END IF;
  ELSE
    IF coalesce(v_category, '') NOT IN ('EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER') THEN
      RAISE EXCEPTION 'Select a change category.';
    END IF;
    IF v_chk.requires_reason AND v_reason IS NULL THEN
      RAISE EXCEPTION 'A change reason is required for this revision.';
    END IF;
  END IF;

  UPDATE cbd_revision
     SET status = 'PUBLISHED', sync_status = 'IN_SYNC', published_at = now(), published_by = v_email,
         po_factor = (SELECT s.po_factor FROM stage_setting s WHERE s.stage = v_rev.stage),   -- dibekukan
         updated_by = v_email
   WHERE id = v_rev.id;

  INSERT INTO change_log (doc_type, revision_id, category, reason, diff, created_by)
  VALUES ('CBD', v_rev.id, v_category, coalesce(v_reason, 'Initial revision.'), v_diff, v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_attachment_add(p_token text, p_article_id uuid, p_file_name text, p_base64 text, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email   text := fn_auth_in(p_token, 'edit_model', fn_article_factory(p_article_id));
  v_content bytea;
  v_mime    text;
  v_name    text := btrim(coalesce(p_file_name, ''));
  v_id      uuid;
BEGIN
  IF coalesce(p_base64, '') = '' THEN
    RAISE EXCEPTION 'Select a file to upload.';
  END IF;
  BEGIN
    v_content := decode(regexp_replace(regexp_replace(p_base64, '^data:[^,]*,', ''), '\s', '', 'g'), 'base64');
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'The file cannot be read (invalid Base64 format).';
  END;
  IF length(v_content) > 3670016 THEN
    RAISE EXCEPTION 'File size is % MB. The maximum is 3.5 MB.', replace((ceil(length(v_content) / 104857.6) / 10)::numeric(6,1)::text, '.', ',');
  END IF;
  v_mime := CASE
    WHEN substring(v_content FROM 1 FOR 3) = '\xffd8ff'::bytea           THEN 'image/jpeg'
    WHEN substring(v_content FROM 1 FOR 8) = '\x89504e470d0a1a0a'::bytea THEN 'image/png'
    WHEN substring(v_content FROM 1 FOR 5) = '\x255044462d'::bytea       THEN 'application/pdf'
  END;
  IF v_mime IS NULL THEN
    RAISE EXCEPTION 'File type not supported. Only JPG, PNG, or PDF.';
  END IF;
  IF v_name = '' THEN
    v_name := 'attachment' || CASE v_mime WHEN 'image/jpeg' THEN '.jpg' WHEN 'image/png' THEN '.png' ELSE '.pdf' END;
  END IF;
  INSERT INTO article_attachment (article_id, file_name, mime_type, size_bytes, content, note, updated_by)
  VALUES (p_article_id, v_name, v_mime, length(v_content), v_content,
          nullif(btrim(coalesce(p_note, '')), ''), v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_draft(p_cbd_revision_id uuid)
 RETURNS cbd_revision
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_rev    cbd_revision%ROWTYPE;
  v_status text;
BEGIN
  SELECT * INTO v_rev FROM cbd_revision WHERE id = p_cbd_revision_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CBD revision not found.';
  END IF;
  IF v_rev.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'This CBD revision is published and cannot be changed. Create a new revision for changes.';
  END IF;
  v_status := fn_cbd_article_spec_status(v_rev.article_id);
  IF v_status = 'DROPPED' THEN
    RAISE EXCEPTION 'This article is dropped in the latest published specsheet. Its CBD is view only (a draft can be deleted).';
  ELSIF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'This article is not in a published specsheet revision.';
  END IF;
  -- R13: acuan = specsheet terbit terakhir di stage draft ini
  IF fn_cbd_stage_spec_status(v_rev.article_id, v_rev.stage) <> 'ACTIVE' THEN
    RAISE EXCEPTION 'This article is not active in the latest published % specsheet. The % CBD draft can only be deleted.',
      fn_stage_label(v_rev.stage), fn_stage_label(v_rev.stage);
  END IF;
  RETURN v_rev;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_create(p_token text, p_article_id uuid, p_mode text, p_source_article_id uuid, p_stage text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_article_factory(p_article_id));
  v_art    article%ROWTYPE;
  v_srcart article%ROWTYPE;
  v_spec   specsheet_revision%ROWTYPE;
  v_src    cbd_revision%ROWTYPE;
  v_lines  cbd_line[];
  v_status text;
  v_stage  text;
  v_maxpub cbd_revision%ROWTYPE;
  v_no     integer;
  v_ref    text;
  v_cross  boolean := false;
  v_model  uuid;
  v_smodel uuid;
  v_origin uuid;
  v_id     uuid;
BEGIN
  SELECT * INTO v_art FROM article WHERE id = p_article_id FOR UPDATE;   -- antre per article
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Article not found.';
  END IF;
  v_status := fn_cbd_article_spec_status(v_art.id);
  IF v_status = 'DROPPED' THEN
    RAISE EXCEPTION 'Article % is dropped in the latest published specsheet. Its CBD cannot be created anymore.', v_art.code;
  ELSIF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article % is not in a published specsheet revision. Publish the specsheet first.', v_art.code;
  END IF;
  IF EXISTS (SELECT 1 FROM cbd_revision WHERE article_id = v_art.id AND status = 'DRAFT') THEN
    RAISE EXCEPTION 'Article % already has a CBD DRAFT. Publish or delete that draft first.', v_art.code;
  END IF;

  -- R13: stage dipilih (default stage specsheet terbit terbaru); acuan = specsheet terbit terakhir di stage itu
  v_stage := coalesce(nullif(btrim(coalesce(p_stage, '')), ''),
                      (SELECT stage FROM specsheet_revision WHERE id = fn_spec_latest_pub(v_art.specsheet_id)));
  IF NOT (v_stage = ANY (fn_stages())) THEN
    RAISE EXCEPTION 'Unknown stage %.', fn_stage_label(v_stage);
  END IF;
  SELECT * INTO v_spec FROM specsheet_revision WHERE id = fn_spec_latest_pub_stage(v_art.specsheet_id, v_stage);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No published % specsheet for article % yet.', fn_stage_label(v_stage), v_art.code;
  END IF;
  IF fn_cbd_stage_spec_status(v_art.id, v_stage) <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article % is not active in specsheet % r%. The % CBD cannot be created.',
      v_art.code, fn_stage_label(v_spec.stage), v_spec.revision_no, fn_stage_label(v_stage);
  END IF;
  SELECT * INTO v_maxpub FROM cbd_revision
   WHERE article_id = v_art.id AND status = 'PUBLISHED'
   ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
  IF FOUND AND v_maxpub.stage_order > v_spec.stage_order THEN
    RAISE EXCEPTION 'Article % already has a published % CBD. A CBD for an earlier stage (%) cannot be created anymore.',
      v_art.code, fn_stage_label(v_maxpub.stage), fn_stage_label(v_stage);
  END IF;

  IF p_mode IN ('NEW', 'COPY') THEN
    IF EXISTS (SELECT 1 FROM cbd_revision WHERE article_id = v_art.id) THEN
      RAISE EXCEPTION 'Article % already has a CBD. Use Next revision.', v_art.code;
    END IF;
    IF p_mode = 'COPY' THEN
      SELECT * INTO v_srcart FROM article WHERE id = p_source_article_id;
      IF NOT FOUND OR v_srcart.id = v_art.id THEN
        RAISE EXCEPTION 'Select a source article.';
      END IF;
      v_model  := (SELECT model_id FROM specsheet WHERE id = v_art.specsheet_id);
      v_smodel := (SELECT model_id FROM specsheet WHERE id = v_srcart.specsheet_id);
      IF v_smodel IS DISTINCT FROM v_model THEN
        v_origin := fn_sheet_origin_model(v_art.specsheet_id);
        IF v_origin IS NULL OR v_smodel IS DISTINCT FROM v_origin THEN
          RAISE EXCEPTION 'A CBD can only be copied from an article of the same model, or of this specsheet''s origin model (cross-model copy).';
        END IF;
        v_cross := true;
      END IF;
      SELECT * INTO v_src FROM cbd_revision
       WHERE article_id = v_srcart.id AND status = 'PUBLISHED'
       ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Article % has no published CBD to copy.', v_srcart.code;
      END IF;
    END IF;
  ELSIF p_mode = 'NEXT' THEN
    IF v_maxpub.id IS NULL THEN
      RAISE EXCEPTION 'Article % has no published CBD yet.', v_art.code;
    END IF;
    v_src := v_maxpub;
  ELSE
    RAISE EXCEPTION 'Choose how to create the CBD.';
  END IF;

  SELECT coalesce(max(revision_no) + 1, 0) INTO v_no
    FROM cbd_revision WHERE article_id = v_art.id AND stage = v_spec.stage;

  -- Rekap ikut dari sumber; lintas model: Target FOB kosong
  INSERT INTO cbd_revision (article_id, stage, revision_no, specsheet_revision_id, exchange_rate,
                            target_fob, source_cbd_revision_id, updated_by)
  VALUES (v_art.id, v_spec.stage, v_no, v_spec.id, v_src.exchange_rate,
          CASE WHEN v_cross THEN NULL ELSE v_src.target_fob END, v_src.id, v_email)
  RETURNING id INTO v_id;

  IF v_src.id IS NOT NULL THEN
    SELECT pm.name || ' / ' || sp.season || ' / ' || a.code || ' / ' || fn_rev_label(v_src.stage, v_src.revision_no) INTO v_ref
      FROM article a JOIN specsheet sp ON sp.id = a.specsheet_id JOIN product_model pm ON pm.id = sp.model_id
     WHERE a.id = v_src.article_id;
    SELECT array_agg(l ORDER BY l.sort_order) INTO v_lines FROM cbd_line l WHERE l.cbd_revision_id = v_src.id;
    -- baris biaya ikut; lintas model: hanya Direct Labour (LOP), lainnya default 0
    INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, remarks, is_default, sort_order, updated_by)
    SELECT v_id, c.item_type, c.name, c.amount, c.remarks, c.is_default, c.sort_order, v_email
      FROM cbd_cost_item c WHERE c.cbd_revision_id = v_src.id AND (NOT v_cross OR c.item_type = 'LABOUR');
  END IF;
  PERFORM fn_cbd_cost_defaults(v_id, v_email);
  PERFORM fn_cbd_populate(v_id, v_art.id, v_spec.id, v_lines, p_mode = 'NEXT', v_ref, v_email, v_cross);
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_stage_options(p_token text, p_article_id uuid)
 RETURNS TABLE(stage text, stage_order integer, spec_revision_id uuid, spec_label text, next_no integer, next_label text, available boolean, note text, is_default boolean)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_article_factory(p_article_id));
BEGIN
  RETURN QUERY
  WITH a AS (SELECT * FROM article WHERE id = p_article_id),
  maxpub AS (SELECT max(r.stage_order) AS o,
                    (array_agg(r.stage ORDER BY r.stage_order DESC))[1] AS s
               FROM cbd_revision r WHERE r.article_id = p_article_id AND r.status = 'PUBLISHED'),
  st AS (
    SELECT s.stage, s.ord::integer AS ord, sr.id AS sid, fn_rev_label(sr.stage, sr.revision_no) AS slabel,
           coalesce(ra.status, 'NOT_PUBLISHED') AS art_status,
           (SELECT coalesce(max(c.revision_no) + 1, 0)::integer FROM cbd_revision c
             WHERE c.article_id = p_article_id AND c.stage = s.stage) AS nno
      FROM unnest(fn_stages()) WITH ORDINALITY s(stage, ord)
      CROSS JOIN a
      JOIN specsheet_revision sr ON sr.id = fn_spec_latest_pub_stage(a.specsheet_id, s.stage)
      LEFT JOIN revision_article ra ON ra.revision_id = sr.id AND ra.article_id = a.id
  ),
  ev AS (
    SELECT st.*, (ov.s = 'ACTIVE' AND st.art_status = 'ACTIVE' AND (m.o IS NULL OR st.ord >= m.o)) AS ok,
           CASE WHEN ov.s = 'DROPPED' THEN 'Article dropped in the latest published specsheet'
                WHEN ov.s <> 'ACTIVE' THEN 'Article not in the latest published specsheet'
                WHEN st.art_status = 'DROPPED' THEN 'Article dropped in specsheet ' || st.slabel
                WHEN st.art_status <> 'ACTIVE' THEN 'Article not in specsheet ' || st.slabel
                WHEN m.o IS NOT NULL AND st.ord < m.o THEN 'A ' || fn_stage_label(m.s) || ' CBD is already published'
           END AS why
      FROM st CROSS JOIN maxpub m
      CROSS JOIN (SELECT fn_cbd_article_spec_status(p_article_id) AS s) ov
  )
  SELECT ev.stage, ev.ord, ev.sid, ev.slabel, ev.nno, fn_rev_label(ev.stage, ev.nno), ev.ok, ev.why,
         ev.ok AND ev.ord = (SELECT max(e2.ord) FROM ev e2 WHERE e2.ok)
    FROM ev
   ORDER BY ev.ord;
END;
$function$;

CREATE OR REPLACE VIEW v_price_pending AS
 SELECT mp.id,
    COALESCE(mp.batch_id, mp.id) AS batch_id,
    m.id AS material_id,
    m.factory_id,
    m.name AS material_name,
    m.uom,
    v.id AS variant_id,
    v.code,
    v.color,
    fn_thickness_label(v.thickness) AS thickness_label,
    s.name AS supplier_name,
    mp.price,
    mp.currency,
    mp.valid_from,
    mp.reference,
    mp.created_by,
    mp.created_at,
    cur.price AS cur_price,
    cur.currency AS cur_currency,
    cur.valid_from AS cur_valid_from,
        CASE
            WHEN (m.price_method <> 'CATALOG'::text) THEN 'Material is now Quotation'::text
            WHEN ((ms.status = 'INACTIVE'::text) OR (s.status = 'INACTIVE'::text)) THEN 'Supplier inactive'::text
            WHEN (v.status = 'INACTIVE'::text) THEN 'Variant INACTIVE'::text
            WHEN (cur.valid_from > mp.valid_from) THEN (('Earlier than the active price ('::text || to_char((cur.valid_from)::timestamp with time zone, 'DD-MM-YYYY'::text)) || ')'::text)
            ELSE NULL::text
        END AS problem
   FROM (((((material_price mp
     JOIN material_variant v ON ((v.id = mp.variant_id)))
     JOIN material_supplier ms ON ((ms.id = mp.material_supplier_id)))
     JOIN supplier s ON ((s.id = ms.supplier_id)))
     JOIN material m ON ((m.id = ms.material_id)))
     LEFT JOIN LATERAL ( SELECT o.price,
            o.currency,
            o.valid_from
           FROM material_price o
          WHERE ((o.material_supplier_id = mp.material_supplier_id) AND (o.variant_id = mp.variant_id) AND (o.status = 'APPROVED'::text) AND (o.valid_to IS NULL))
          ORDER BY o.valid_from DESC
         LIMIT 1) cur ON (true))
  WHERE (mp.status = 'PROPOSED'::text);

CREATE OR REPLACE VIEW v_worklist_admin AS
 SELECT 'PRICE'::text AS kind,
    batch_id AS ref_id,
    (array_agg(material_id))[1] AS material_id,
    string_agg(DISTINCT material_name, ', '::text) AS title,
    (((('Supplier '::text || string_agg(DISTINCT supplier_name, ', '::text)) || ' · '::text) || count(*)) || ' price(s)'::text) AS detail,
    string_agg(DISTINCT ((currency || ' '::text) || (trim_scale(price))::text), ' / '::text) AS amount_text,
    (array_agg(created_by ORDER BY created_at))[1] AS proposed_by,
    min(created_at) AS proposed_at,
    (array_agg(factory_id))[1] AS factory_id
   FROM v_price_pending p
  GROUP BY batch_id;

CREATE OR REPLACE VIEW v_material_price AS
 SELECT (mp.id)::text AS row_key,
    mp.id,
    m.id AS material_id,
    m.factory_id,
    v.id AS variant_id,
    v.code,
    v.color,
    v.thickness,
    fn_thickness_label(v.thickness) AS thickness_label,
    v.status AS variant_status,
    ms.id AS link_id,
    s.name AS supplier_name,
    ms.status AS link_status,
    mp.price,
    mp.currency,
    mp.valid_from,
    mp.valid_to,
    mp.reference,
    mp.status,
    x.state,
        CASE x.state
            WHEN 'PENDING APPROVAL'::text THEN 1
            WHEN 'ACTIVE'::text THEN 3
            WHEN 'UPCOMING'::text THEN 4
            WHEN 'REJECTED'::text THEN 5
            ELSE 6
        END AS state_order,
    mp.reject_reason,
    mp.batch_id,
    mp.created_by,
    mp.created_at,
    mp.decided_by,
    mp.decided_at
   FROM (((((material_price mp
     JOIN material_variant v ON ((v.id = mp.variant_id)))
     JOIN material_supplier ms ON ((ms.id = mp.material_supplier_id)))
     JOIN supplier s ON ((s.id = ms.supplier_id)))
     JOIN material m ON ((m.id = ms.material_id)))
     CROSS JOIN LATERAL ( SELECT fn_price_state(mp.status, mp.valid_from, mp.valid_to) AS state) x)
UNION ALL
 SELECT ((('gap:'::text || v.id) || ':'::text) || ms.id) AS row_key,
    NULL::uuid AS id,
    m.id AS material_id,
    m.factory_id,
    v.id AS variant_id,
    v.code,
    v.color,
    v.thickness,
    fn_thickness_label(v.thickness) AS thickness_label,
    v.status AS variant_status,
    ms.id AS link_id,
    s.name AS supplier_name,
    ms.status AS link_status,
    NULL::numeric AS price,
    NULL::text AS currency,
    NULL::date AS valid_from,
    NULL::date AS valid_to,
    NULL::text AS reference,
    NULL::text AS status,
    'NO PRICE'::text AS state,
    2 AS state_order,
    NULL::text AS reject_reason,
    NULL::uuid AS batch_id,
    NULL::text AS created_by,
    NULL::timestamp with time zone AS created_at,
    NULL::text AS decided_by,
    NULL::timestamp with time zone AS decided_at
   FROM (((material m
     JOIN material_variant v ON (((v.material_id = m.id) AND (v.status = 'ACTIVE'::text))))
     JOIN material_supplier ms ON (((ms.material_id = m.id) AND (ms.status = 'ACTIVE'::text))))
     JOIN supplier s ON (((s.id = ms.supplier_id) AND (s.status = 'ACTIVE'::text))))
  WHERE ((m.price_method = 'CATALOG'::text) AND (NOT (EXISTS ( SELECT 1
           FROM material_price mp
          WHERE ((mp.material_supplier_id = ms.id) AND (mp.variant_id = v.id) AND ((mp.status = 'PROPOSED'::text) OR ((mp.status = 'APPROVED'::text) AND ((mp.valid_to IS NULL) OR ((mp.valid_to > fn_today()) AND (mp.valid_to > mp.valid_from))))))))));

CREATE OR REPLACE VIEW v_cbd_line AS
 SELECT cl.id,
    cl.cbd_revision_id,
    cl.line_key,
    cl.status,
    cl.group_code,
    g.name AS group_name,
    g.sort_order AS group_sort,
    COALESCE(c.number, cl.local_component_no) AS comp_no,
        CASE
            WHEN (cl.sub_seq IS NOT NULL) THEN (COALESCE(((COALESCE(c.number, cl.local_component_no))::text || '-'::text), ''::text) || cl.sub_seq)
            ELSE (COALESCE(c.number, cl.local_component_no))::text
        END AS display_no,
        CASE
            WHEN (cl.sub_seq IS NOT NULL) THEN COALESCE(cl.sub_name, m.name)
            ELSE COALESCE(c.name, bl.local_component_name, ('Local '::text || cl.local_component_no), m.name)
        END AS display_name,
    (cl.sub_seq IS NOT NULL) AS is_sub,
    ((cl.component_id IS NULL) AND (cl.sub_seq IS NULL)) AS is_local,
    cl.material_id,
    v.code AS material_code,
    m.name AS material_name,
    cl.thickness,
    m.price_method,
    cl.color,
    cl.supplier_id,
    s.name AS supplier_name,
    cl.uom,
    bl.process AS remarks,
    cl.yield_value,
    cl.usage_value,
    cl.loss_pct,
    cl.price_original,
    cl.currency,
    cl.price_source,
    cl.material_price_id,
    NULL::text AS master_price_color,
    mp.valid_from AS master_price_valid_from,
    cl.price_override_reason,
    cl.price_reference,
    x.price_usd,
    x.price_idr,
        CASE
            WHEN cl.no_charge THEN (0)::numeric
            ELSE ((cl.usage_value * x.price_idr) * ((1)::numeric + (COALESCE(cl.loss_pct, (0)::numeric) / (100)::numeric)))
        END AS cost_per_pair,
    cl.value_origin,
    cl.value_source_ref,
    cl.sort_order,
    cl.variant_id,
    cl.no_charge,
    cl.no_charge_reason,
    cl.replaces_line_key
   FROM (((((((((cbd_line cl
     JOIN cbd_revision cr ON ((cr.id = cl.cbd_revision_id)))
     JOIN material m ON ((m.id = cl.material_id)))
     LEFT JOIN material_variant v ON ((v.id = cl.variant_id)))
     LEFT JOIN component c ON ((c.id = cl.component_id)))
     LEFT JOIN component_group g ON ((g.code = cl.group_code)))
     LEFT JOIN supplier s ON ((s.id = cl.supplier_id)))
     LEFT JOIN material_price mp ON ((mp.id = cl.material_price_id)))
     LEFT JOIN bom_line bl ON (((bl.revision_id = cr.specsheet_revision_id) AND (bl.line_key = cl.line_key))))
     CROSS JOIN LATERAL ( SELECT
                CASE cl.currency
                    WHEN 'IDR'::text THEN cl.price_original
                    WHEN 'USD'::text THEN (cl.price_original * cr.exchange_rate)
                    ELSE NULL::numeric
                END AS price_idr,
                CASE cl.currency
                    WHEN 'USD'::text THEN cl.price_original
                    WHEN 'IDR'::text THEN (cl.price_original / NULLIF(cr.exchange_rate, (0)::numeric))
                    ELSE NULL::numeric
                END AS price_usd) x);

CREATE OR REPLACE VIEW v_cbd_recap AS
 SELECT r.id AS cbd_revision_id,
    r.status,
    r.exchange_rate,
    r.target_fob,
    t.material_cost,
    ci.labour,
    ci.amortization,
    ci.adjustment,
    ci.other,
    ci.items_total,
    f.actual_fob,
    (f.actual_fob - r.target_fob) AS variance,
        CASE
            WHEN (r.target_fob IS NULL) THEN NULL::text
            WHEN (f.actual_fob > r.target_fob) THEN 'OVER'::text
            WHEN (f.actual_fob < r.target_fob) THEN 'UNDER'::text
            ELSE 'MATCH'::text
        END AS variance_label,
    t.line_count,
    t.unpriced_count,
    t.no_yield_count,
    t.usd_no_rate_count,
    t.missing_count,
    COALESCE(gc.group_costs, '{}'::jsonb) AS group_costs,
    r.stage,
    pf.po_factor,
    round((f.actual_fob * pf.po_factor), 2) AS po_price,
    t.no_charge_count,
    t.blank_count
   FROM (((((cbd_revision r
     CROSS JOIN LATERAL ( SELECT COALESCE(sum(v.cost_per_pair) FILTER (WHERE (v.status = 'ACTIVE'::text)), (0)::numeric) AS material_cost,
            (count(*) FILTER (WHERE (v.status = 'ACTIVE'::text)))::integer AS line_count,
            (count(*) FILTER (WHERE ((v.status = 'ACTIVE'::text) AND (v.price_original IS NULL) AND (NOT v.no_charge))))::integer AS unpriced_count,
            (count(*) FILTER (WHERE ((v.status = 'ACTIVE'::text) AND (v.price_original IS NOT NULL) AND (v.yield_value IS NULL) AND (NOT v.no_charge))))::integer AS no_yield_count,
            (count(*) FILTER (WHERE ((v.status = 'ACTIVE'::text) AND (v.currency = 'USD'::text) AND (v.price_idr IS NULL) AND (NOT v.no_charge))))::integer AS usd_no_rate_count,
            (count(*) FILTER (WHERE (v.status = 'MISSING_IN_SPEC'::text)))::integer AS missing_count,
            (count(*) FILTER (WHERE ((v.status = 'ACTIVE'::text) AND v.no_charge)))::integer AS no_charge_count,
            (count(*) FILTER (WHERE ((v.status = 'ACTIVE'::text) AND (v.price_original IS NULL) AND (v.yield_value IS NULL) AND (NOT v.no_charge))))::integer AS blank_count
           FROM v_cbd_line v
          WHERE (v.cbd_revision_id = r.id)) t)
     CROSS JOIN LATERAL ( SELECT COALESCE(sum(c.amount) FILTER (WHERE (c.item_type = 'LABOUR'::text)), (0)::numeric) AS labour,
            COALESCE(sum(c.amount) FILTER (WHERE (c.item_type = 'AMORTIZATION'::text)), (0)::numeric) AS amortization,
            COALESCE(sum(c.amount) FILTER (WHERE (c.item_type = 'ADJUSTMENT'::text)), (0)::numeric) AS adjustment,
            COALESCE(sum(c.amount) FILTER (WHERE (c.item_type = 'OTHER'::text)), (0)::numeric) AS other,
            COALESCE(sum(c.amount), (0)::numeric) AS items_total
           FROM cbd_cost_item c
          WHERE (c.cbd_revision_id = r.id)) ci)
     CROSS JOIN LATERAL ( SELECT jsonb_object_agg(x.group_code, x.cost) AS group_costs
           FROM ( SELECT v.group_code,
                    COALESCE(sum(v.cost_per_pair), (0)::numeric) AS cost
                   FROM v_cbd_line v
                  WHERE ((v.cbd_revision_id = r.id) AND (v.status = 'ACTIVE'::text))
                  GROUP BY v.group_code) x) gc)
     CROSS JOIN LATERAL ( SELECT (t.material_cost + ci.items_total) AS actual_fob) f)
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN (r.status = 'PUBLISHED'::text) THEN r.po_factor
                    ELSE ( SELECT s.po_factor
                       FROM stage_setting s
                      WHERE (s.stage = r.stage))
                END AS po_factor) pf);

-- ---------------------------------------------------------------- ringkasan
SELECT 'R15 terpasang' AS cek,
       concat_ws(' · ',
         'price states: ' || (SELECT string_agg(DISTINCT state, ',' ORDER BY state) FROM v_material_price),
         'stage label: ' || fn_stage_label('PROD'),
         'role: ' || fn_role_label('VENDOR_SPEC')) AS hasil;

COMMIT;
