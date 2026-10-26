-- ============================================================================
-- R17 (22 Okt 2026, PLAN.md R17). Jalankan SETELAH R16_baku_thickness.sql, lewat z_run_sql di app "DB Tools"
-- (Use prepared statements = OFF). Aman diulang. Satu transaksi. Tanpa reset data. Dua bagian:
--   1. Remember me di halaman Login.
--   2. Material Code wajib mulai SMS + harga ESTIMATE untuk baris CBD tanpa kode di Pullover / Preview (lihat "R17 bagian 2").
--
-- Bagian 1. Mengapa: app hanya bisa dibuka lewat VPN, jadi user sudah login VPN setiap kali. Login app tiap 12 jam menambah ketikan.
-- Aturan (keputusan user 22 Okt 2026):
--   - Remember me TIDAK dicentang (default) = sesi 12 jam tetap, seperti sebelumnya.
--   - Remember me dicentang = sesi habis bila app tidak dibuka 7 hari; setiap kali app dibuka (fn_me, dipanggil di setiap
--     page) masa berlaku mundur lagi menjadi 7 hari, tetapi PALING LAMA 30 hari sejak login. Setelah itu wajib login ulang.
--   - Sesi tetap diputus seperti sebelumnya: Log out, ganti password (perangkat lain), reset password / ubah role, pabrik,
--     atau nonaktifkan user oleh admin.
-- Email terakhir diingat di browser (LoginCtrl, appsmith.store.lastEmail), bukan di DB.
--
-- fn_login mendapat parameter ke-3 p_remember (DEFAULT false), jadi app lama yang memanggil fn_login(email, password)
-- tetap jalan sampai build R17 diimport.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_clean_thickness(text)') IS NULL THEN
    RAISE EXCEPTION 'R16 belum terpasang. Jalankan sql/R16_baku_thickness.sql dulu.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Kolom sesi
-- remember = dicentang saat login; max_expires_at = batas akhir sesi remember (login + 30 hari), NULL untuk sesi 12 jam
ALTER TABLE app_session
  ADD COLUMN IF NOT EXISTS remember       boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS max_expires_at timestamptz;

-- ---------------------------------------------------------------- Login
DROP FUNCTION IF EXISTS fn_login(text, text);
CREATE OR REPLACE FUNCTION fn_login(p_email text, p_password text, p_remember boolean DEFAULT false)
 RETURNS TABLE(ok boolean, message text, token text, must_change_password boolean)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  v_email    text := lower(btrim(coalesce(p_email, '')));
  v_remember boolean := coalesce(p_remember, false);
  v_user     app_user%ROWTYPE;
  v_token    text;
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
  INSERT INTO app_session (token_hash, email, expires_at, remember, max_expires_at)
  VALUES (fn_token_hash(v_token), v_email,
          now() + CASE WHEN v_remember THEN interval '7 days' ELSE interval '12 hours' END,
          v_remember,
          CASE WHEN v_remember THEN now() + interval '30 days' END);
  UPDATE app_user SET failed_attempts = 0, locked_until = NULL, last_login_at = now()
   WHERE app_user.email = v_email;
  PERFORM fn_audit(v_email, 'app_user', v_email, 'LOGIN');
  RETURN QUERY SELECT true, NULL::text, v_token, v_user.must_change_password;
END;
$function$;

-- ---------------------------------------------------------------- Profil login (+ perpanjang sesi remember)
-- Sama dengan R1 (kolom & isi), sekarang plpgsql VOLATILE karena memperpanjang sesi remember: masa berlaku = 7 hari dari
-- sekarang, tidak melewati max_expires_at. Diperbarui paling sering sekali per jam (tidak menulis di setiap page).
CREATE OR REPLACE FUNCTION fn_me(p_token text)
RETURNS TABLE (email text, full_name text, role text, role_label text,
               must_change_password boolean, expires_at timestamptz, permissions text,
               factory_id uuid, factory_name text)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  v_hash text := fn_token_hash(p_token);
BEGIN
  UPDATE app_session s
     SET expires_at = least(now() + interval '7 days', s.max_expires_at)
   WHERE s.token_hash = v_hash AND s.remember AND s.expires_at > now()
     AND s.expires_at < least(now() + interval '7 days', s.max_expires_at) - interval '1 hour';

  RETURN QUERY
  SELECT u.email, u.full_name, u.role, fn_role_label(u.role), u.must_change_password, s.expires_at,
         coalesce((SELECT string_agg(rp.permission, ',' ORDER BY rp.permission)
                     FROM role_permission rp WHERE rp.role = u.role), ''),
         u.factory_id, f.name
    FROM app_session s
    JOIN app_user u ON u.email = s.email
    LEFT JOIN factory f ON f.id = u.factory_id
   WHERE s.token_hash = v_hash AND s.expires_at > now() AND u.is_active;
END;
$$;

-- ============================================================================ R17 bagian 2
-- Material Code wajib mulai SMS + harga ESTIMATE untuk baris CBD tanpa kode (keputusan user 22 Okt 2026, PLAN.md R17).
-- Latar: di Pullover / Preview purchasing belum membuat Material Code (barang belum dibeli), tetapi specsheet dan CBD
-- harus tetap terbit. Aturan:
--   - Specsheet: sel kuning (tanpa kode) memblokir terbit hanya di SMS, GTM, Production (urutan stage, jadi stage yang
--     melompat juga terkunci). Pullover / Preview = peringatan.
--   - CBD baris tanpa kode di Pullover / Preview: harga ESTIMATE diketik (harga, currency, referensi), tanpa approval,
--     ikut terbawa ke revisi berikutnya selama barisnya masih tanpa kode. Saran = estimasi terakhir material + thickness
--     + supplier yang sama (fn_cbd_estimate_hint), juga dipakai sebagai isian awal saat mengajukan harga master.
--   - Baris yang punya kode: harga master seperti biasa (tidak ada estimasi). Pending tetap memblokir.
--   - Baris ber-Yield tanpa harga: Pullover / Preview tetap peringatan (T56); mulai SMS memblokir (kecuali No charge).

-- ---------------------------------------------------------------- Aturan stage
CREATE OR REPLACE FUNCTION fn_stage_code_required(p_stage text) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT fn_stage_order(p_stage) >= fn_stage_order('SMS')
$$;

-- ---------------------------------------------------------------- Sumber harga ESTIMATE
ALTER TABLE cbd_line DROP CONSTRAINT IF EXISTS cbd_line_price_source_check;
ALTER TABLE cbd_line ADD CONSTRAINT cbd_line_price_source_check
  CHECK (price_source = ANY (ARRAY['MASTER', 'OVERRIDE', 'QUOTATION', 'ESTIMATE']));

-- saran estimasi terakhir (fn_cbd_estimate_hint)
CREATE INDEX IF NOT EXISTS ix_cbd_line_estimate ON cbd_line (material_id, supplier_id, updated_at DESC)
  WHERE price_source = 'ESTIMATE';

-- ---------------------------------------------------------------- v_revision_checklist (R17: diganti utuh dari definisi R16)
CREATE OR REPLACE VIEW v_revision_checklist AS
 SELECT revision_id,
    specsheet_id,
    stage,
    revision_no,
    status,
    requires_reason,
    line_count,
    active_articles,
    unused_articles,
    inactive_materials,
    no_supplier_lines,
    yellow_cells,
    yellow_list,
    inactive_suppliers,
    ((active_articles = 0) OR (unused_articles IS NOT NULL) OR (inactive_materials IS NOT NULL) OR (no_supplier_lines > 0) OR ((yellow_cells > 0) AND code_required) OR (inactive_suppliers IS NOT NULL)) AS blocked,
    code_required
   FROM ( SELECT r.id AS revision_id,
            r.specsheet_id,
            r.stage,
            r.revision_no,
            r.status,
            (EXISTS ( SELECT 1
                   FROM specsheet_revision o
                  WHERE ((o.specsheet_id = r.specsheet_id) AND (o.status = 'PUBLISHED'::text) AND (o.id <> r.id)))) AS requires_reason,
            ( SELECT (count(*))::integer AS count
                   FROM bom_line l
                  WHERE ((l.revision_id = r.id) AND l.is_active)) AS line_count,
            ( SELECT (count(*))::integer AS count
                   FROM revision_article ra
                  WHERE ((ra.revision_id = r.id) AND (ra.status = 'ACTIVE'::text))) AS active_articles,
            ( SELECT string_agg(a.code, ', '::text ORDER BY a.code) AS string_agg
                   FROM (revision_article ra
                     JOIN article a ON ((a.id = ra.article_id)))
                  WHERE ((ra.revision_id = r.id) AND (ra.status = 'ACTIVE'::text) AND (NOT (EXISTS ( SELECT 1
                           FROM (bom_cell c
                             JOIN bom_line l ON ((l.id = c.bom_line_id)))
                          WHERE ((l.revision_id = r.id) AND l.is_active AND (c.article_id = a.id) AND c.is_used)))))) AS unused_articles,
            ( SELECT string_agg(DISTINCT m.name, ', '::text) AS string_agg
                   FROM (bom_line l
                     JOIN material m ON ((m.id = l.material_id)))
                  WHERE ((l.revision_id = r.id) AND l.is_active AND (m.status = 'INACTIVE'::text))) AS inactive_materials,
            ( SELECT (count(*))::integer AS count
                   FROM bom_line l
                  WHERE ((l.revision_id = r.id) AND l.is_active AND (l.supplier_id IS NULL))) AS no_supplier_lines,
            ( SELECT (count(*))::integer AS count
                   FROM ((bom_cell c
                     JOIN bom_line l ON (((l.id = c.bom_line_id) AND (l.revision_id = r.id) AND l.is_active)))
                     JOIN revision_article ra ON (((ra.revision_id = r.id) AND (ra.article_id = c.article_id) AND (ra.status = 'ACTIVE'::text))))
                  WHERE (c.is_used AND (c.variant_id IS NULL))) AS yellow_cells,
            ( SELECT "left"(string_agg(DISTINCT (((m.name || COALESCE((' '::text || l.thickness), ''::text)) || ' · '::text) || c.color), ', '::text), 300) AS "left"
                   FROM (((bom_cell c
                     JOIN bom_line l ON (((l.id = c.bom_line_id) AND (l.revision_id = r.id) AND l.is_active)))
                     JOIN material m ON ((m.id = l.material_id)))
                     JOIN revision_article ra ON (((ra.revision_id = r.id) AND (ra.article_id = c.article_id) AND (ra.status = 'ACTIVE'::text))))
                  WHERE (c.is_used AND (c.variant_id IS NULL))) AS yellow_list,
            ( SELECT string_agg(DISTINCT (((s.name || ' ('::text) || m.name) || ')'::text), ', '::text) AS string_agg
                   FROM (((bom_line l
                     JOIN supplier s ON ((s.id = l.supplier_id)))
                     JOIN material m ON ((m.id = l.material_id)))
                     LEFT JOIN material_supplier ms ON (((ms.material_id = l.material_id) AND (ms.supplier_id = l.supplier_id))))
                  WHERE ((l.revision_id = r.id) AND l.is_active AND ((s.status = 'INACTIVE'::text) OR (ms.status = 'INACTIVE'::text)))) AS inactive_suppliers,
            fn_stage_code_required(r.stage) AS code_required
           FROM specsheet_revision r) x;

-- ---------------------------------------------------------------- fn_revision_publish (R17: diganti utuh dari definisi R16)
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
  IF v_chk.yellow_cells > 0 AND v_chk.code_required THEN       -- R17: Pullover / Preview boleh tanpa kode
    RAISE EXCEPTION 'From SMS every color needs a Material Code. % color cell(s) have no Material Code (yellow cells): %. Register the variants first.',
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

-- ---------------------------------------------------------------- v_cbd_price_check (R17: diganti utuh dari definisi R16)
CREATE OR REPLACE VIEW v_cbd_price_check AS
 SELECT l.id AS line_id,
    l.cbd_revision_id,
    cur.price_id AS master_price_id,
    cur.price AS master_price,
    cur.currency AS master_currency,
        CASE
            WHEN (l.price_source = 'QUOTATION'::text) THEN (m.price_method = 'CATALOG'::text)
            WHEN (m.price_method = 'QUOTATION'::text) THEN (l.price_source = 'MASTER'::text)
            ELSE (cur.price_id IS DISTINCT FROM l.material_price_id)
        END AS master_stale,
        CASE
            WHEN (l.price_original IS NOT NULL) THEN NULL::text
            WHEN (m.price_method = 'QUOTATION'::text) THEN 'QUOTATION'::text
            WHEN (l.supplier_id IS NULL) THEN 'NO_SUPPLIER'::text
            WHEN (l.variant_id IS NULL) THEN 'NO_CODE'::text
            WHEN (cur.price_id IS NOT NULL) THEN 'AVAILABLE'::text
            WHEN pend.pending THEN 'PENDING'::text
            ELSE 'NO_PRICE'::text
        END AS price_gap,
    NULL::text AS other_colors,
    ((m.price_method = 'CATALOG'::text) AND pend.pending) AS pending,
    ((m.price_method = 'CATALOG'::text) AND (l.variant_id IS NULL) AND (NOT fn_stage_code_required(r.stage))) AS can_estimate
   FROM ((((cbd_line l
     JOIN cbd_revision r ON ((r.id = l.cbd_revision_id)))
     JOIN material m ON ((m.id = l.material_id)))
     LEFT JOIN LATERAL fn_price_lookup(l.variant_id, l.supplier_id) cur(price_id, price, currency, valid_from) ON (true))
     CROSS JOIN LATERAL ( SELECT COALESCE(fn_price_pending(l.variant_id, l.supplier_id), false) AS pending) pend)
  WHERE ((r.status = 'DRAFT'::text) AND (l.status = 'ACTIVE'::text) AND (NOT l.no_charge));

-- ---------------------------------------------------------------- v_cbd_checklist (R17: diganti utuh dari definisi R16)
CREATE OR REPLACE VIEW v_cbd_checklist AS
 SELECT cbd_revision_id,
    article_id,
    stage,
    revision_no,
    status,
    requires_reason,
    spec_status,
    spec_stale,
    rate_ok,
    stale_prices,
    no_yield_count,
    unpriced_count,
    line_count,
    missing_count,
    pending_prices,
    pending_list,
    ((spec_status <> 'ACTIVE'::text) OR spec_stale OR (NOT rate_ok) OR (stale_prices > 0) OR (no_yield_count > 0) OR (pending_prices > 0) OR (price_required AND ((unpriced_count > 0) OR (estimate_count > 0)))) AS blocked,
    no_charge_count,
    unpriced_list,
    blank_count,
    price_required,
    estimate_count
   FROM ( SELECT r.id AS cbd_revision_id,
            r.article_id,
            r.stage,
            r.revision_no,
            r.status,
            (EXISTS ( SELECT 1
                   FROM cbd_revision o
                  WHERE ((o.article_id = r.article_id) AND (o.status = 'PUBLISHED'::text) AND (o.id <> r.id)))) AS requires_reason,
                CASE
                    WHEN (fn_cbd_article_spec_status(r.article_id) <> 'ACTIVE'::text) THEN fn_cbd_article_spec_status(r.article_id)
                    ELSE fn_cbd_stage_spec_status(r.article_id, r.stage)
                END AS spec_status,
            (r.specsheet_revision_id IS DISTINCT FROM fn_spec_latest_pub_stage(a.specsheet_id, r.stage)) AS spec_stale,
            (r.exchange_rate IS NOT NULL) AS rate_ok,
            ( SELECT (count(*))::integer AS count
                   FROM v_cbd_price_check pc
                  WHERE ((pc.cbd_revision_id = r.id) AND pc.master_stale)) AS stale_prices,
            rc.no_yield_count,
            (rc.unpriced_count - rc.blank_count) AS unpriced_count,
            rc.line_count,
            rc.missing_count,
            ( SELECT (count(*))::integer AS count
                   FROM v_cbd_price_check pc
                  WHERE ((pc.cbd_revision_id = r.id) AND pc.pending)) AS pending_prices,
            ( SELECT "left"(string_agg(DISTINCT ((v.material_code || ' · '::text) || v.supplier_name), ', '::text), 300) AS "left"
                   FROM (v_cbd_price_check pc
                     JOIN v_cbd_line v ON (((v.id = pc.line_id) AND (v.cbd_revision_id = r.id))))
                  WHERE ((pc.cbd_revision_id = r.id) AND pc.pending)) AS pending_list,
            rc.no_charge_count,
            ( SELECT "left"(string_agg((((btrim(concat_ws(' '::text, v.display_no, v.display_name)) || ' ('::text) || v.material_name) || ')'::text), ', '::text ORDER BY v.group_sort, v.sort_order), 300) AS "left"
                   FROM v_cbd_line v
                  WHERE ((v.cbd_revision_id = r.id) AND (v.status = 'ACTIVE'::text) AND (v.price_original IS NULL) AND (v.yield_value IS NOT NULL) AND (NOT v.no_charge))) AS unpriced_list,
            rc.blank_count,
            fn_stage_code_required(r.stage) AS price_required,
            ( SELECT (count(*))::integer AS count
                   FROM cbd_line l
                  WHERE ((l.cbd_revision_id = r.id) AND (l.status = 'ACTIVE'::text) AND (l.price_source = 'ESTIMATE'::text) AND (NOT l.no_charge))) AS estimate_count
           FROM ((cbd_revision r
             JOIN article a ON ((a.id = r.article_id)))
             JOIN v_cbd_recap rc ON ((rc.cbd_revision_id = r.id)))) x;

-- ---------------------------------------------------------------- fn_cbd_publish (R17: diganti utuh dari definisi R16)
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
  -- R17: mulai SMS harga wajib (Pullover / Preview tetap peringatan, T56); estimasi hanya Pullover / Preview
  IF v_chk.price_required AND v_chk.estimate_count > 0 THEN
    RAISE EXCEPTION 'From SMS estimate prices are not allowed. % line(s) still use an estimate.', v_chk.estimate_count;
  END IF;
  IF v_chk.price_required AND v_chk.unpriced_count > 0 THEN
    RAISE EXCEPTION 'From SMS every line with a Yield needs a price. % line(s) have no price: %. Propose the master price (or mark the line No charge).',
      v_chk.unpriced_count, v_chk.unpriced_list;
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

-- ---------------------------------------------------------------- fn_cbd_populate (R17: diganti utuh dari definisi R16)
CREATE OR REPLACE FUNCTION public.fn_cbd_populate(p_revision_id uuid, p_article_id uuid, p_spec_rev_id uuid, p_src cbd_line[], p_mark_missing boolean, p_ref text, p_email text, p_cross boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  e         record;
  s         cbd_line%ROWTYPE;
  v_has_src boolean := coalesce(cardinality(p_src), 0) > 0;
  v_found   boolean;
  v_matched uuid[] := '{}';
  v_sort    integer := 0;
  v_yield   numeric;
  v_loss    numeric;
  v_origin  text;
  v_ref     text;
  v_carry   boolean;
  v_nc      boolean;
  v_ncr     text;
  v_pid     uuid;
  v_price   numeric;
  v_cur     text;
  v_early   boolean := NOT fn_stage_code_required((SELECT stage FROM cbd_revision WHERE id = p_revision_id));
BEGIN
  FOR e IN SELECT * FROM fn_cbd_expected_lines(p_article_id, p_spec_rev_id) ORDER BY seq LOOP
    v_found := false;
    v_yield := NULL; v_loss := NULL; v_origin := 'INPUT'; v_ref := NULL; v_carry := false; v_nc := false; v_ncr := NULL;
    IF v_has_src THEN
      IF NOT p_cross THEN
        SELECT * INTO s FROM unnest(p_src) x WHERE x.line_key = e.line_key
           AND NOT (x.line_key = ANY (v_matched)) LIMIT 1;
        v_found := FOUND;
      END IF;
      IF NOT v_found AND e.origin_line_key IS NOT NULL THEN
        SELECT * INTO s FROM unnest(p_src) x WHERE x.line_key = e.origin_line_key
           AND NOT (x.line_key = ANY (v_matched)) LIMIT 1;
        v_found := FOUND;
        -- lintas model: hanya bila induk + thickness sama (baris hasil Ganti material -> kosong)
        IF v_found AND p_cross AND (s.material_id <> e.material_id
                                    OR fn_normalize(coalesce(s.thickness, '')) <> fn_normalize(coalesce(e.thickness, ''))) THEN
          v_found := false;
        END IF;
      END IF;
      IF NOT v_found AND NOT p_cross THEN
        SELECT * INTO s FROM unnest(p_src) x
         WHERE NOT (x.line_key = ANY (v_matched))
           AND fn_cbd_identity(x.component_id, x.local_component_no, x.sub_seq, x.sub_name, x.material_id, x.thickness)
             = fn_cbd_identity(e.component_id, e.local_component_no, e.sub_seq, e.sub_name, e.material_id, e.thickness)
         ORDER BY x.sort_order LIMIT 1;
        v_found := FOUND;
      END IF;
      IF v_found THEN
        v_matched := v_matched || s.line_key;
        v_yield := s.yield_value; v_loss := s.loss_pct;
        IF p_ref IS NULL THEN
          v_origin := s.value_origin; v_ref := s.value_source_ref;
        ELSE
          v_origin := 'COPIED'; v_ref := p_ref;
        END IF;
        v_carry := s.price_source = 'QUOTATION' AND s.variant_id IS NOT DISTINCT FROM e.variant_id
                   AND EXISTS (SELECT 1 FROM material WHERE id = e.material_id AND price_method = 'QUOTATION');
        -- R17: estimasi (baris tanpa Material Code) ikut selama barisnya masih tanpa kode, supplier & material sama,
        -- dan CBD tujuan masih Pullover / Preview
        v_carry := v_carry OR (s.price_source = 'ESTIMATE' AND v_early AND s.variant_id IS NULL AND e.variant_id IS NULL
                   AND s.material_id = e.material_id AND s.supplier_id IS NOT DISTINCT FROM e.supplier_id
                   AND fn_normalize(coalesce(s.thickness, '')) = fn_normalize(coalesce(e.thickness, ''))
                   AND EXISTS (SELECT 1 FROM material WHERE id = e.material_id AND price_method = 'CATALOG'));
        v_nc := coalesce(s.no_charge, false); v_ncr := CASE WHEN v_nc THEN s.no_charge_reason END;
      ELSIF e.replaces_line_key IS NOT NULL AND NOT p_cross THEN
        SELECT * INTO s FROM unnest(p_src) x WHERE x.line_key = e.replaces_line_key
           AND NOT (x.line_key = ANY (v_matched)) LIMIT 1;
        IF FOUND THEN
          v_matched := v_matched || s.line_key;
          v_yield := s.yield_value; v_loss := s.loss_pct; v_origin := 'CARRIED_FROM_REPLACED';
          v_ref := coalesce(p_ref, s.value_source_ref);
        END IF;
      END IF;
    END IF;

    IF v_carry THEN
      INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                            material_id, thickness, color, variant_id, supplier_id, uom, group_code, yield_value, loss_pct,
                            price_original, currency, price_source, material_price_id, price_override_reason,
                            price_reference, status, value_origin, value_source_ref, sort_order, updated_by,
                            no_charge, no_charge_reason, replaces_line_key)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.thickness, e.color, e.variant_id, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              s.price_original, s.currency, s.price_source, NULL, NULL,
              s.price_reference, 'ACTIVE', v_origin, v_ref, v_sort, p_email,
              v_nc, v_ncr, e.replaces_line_key);
    ELSE
      v_pid := NULL; v_price := NULL; v_cur := NULL;
      IF e.supplier_id IS NOT NULL AND e.variant_id IS NOT NULL THEN
        SELECT price_id, price, currency INTO v_pid, v_price, v_cur
          FROM fn_price_lookup(e.variant_id, e.supplier_id);
      END IF;
      INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                            material_id, thickness, color, variant_id, supplier_id, uom, group_code, yield_value, loss_pct,
                            price_original, currency, price_source, material_price_id,
                            status, value_origin, value_source_ref, sort_order, updated_by,
                            no_charge, no_charge_reason, replaces_line_key)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.thickness, e.color, e.variant_id, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              v_price, v_cur, CASE WHEN v_pid IS NOT NULL THEN 'MASTER' END, v_pid,
              'ACTIVE', v_origin, v_ref, v_sort, p_email,
              v_nc, v_ncr, e.replaces_line_key);
    END IF;
    v_sort := v_sort + 1;
  END LOOP;

  IF p_mark_missing AND v_has_src THEN
    INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                          material_id, thickness, color, variant_id, supplier_id, uom, group_code, yield_value, loss_pct,
                          price_original, currency, price_source, material_price_id, price_override_reason,
                          price_reference, status, value_origin, value_source_ref, sort_order, updated_by,
                          no_charge, no_charge_reason, replaces_line_key)
    SELECT p_revision_id, x.line_key, x.component_id, x.local_component_no, x.sub_seq, x.sub_name,
           x.material_id, x.thickness, x.color, x.variant_id, x.supplier_id, x.uom, x.group_code, x.yield_value, x.loss_pct,
           x.price_original, x.currency, x.price_source, x.material_price_id, x.price_override_reason,
           x.price_reference, 'MISSING_IN_SPEC', x.value_origin, x.value_source_ref,
           v_sort + (row_number() OVER (ORDER BY x.sort_order))::integer, p_email,
           coalesce(x.no_charge, false), CASE WHEN x.no_charge THEN x.no_charge_reason END, x.replaces_line_key
      FROM unnest(p_src) x
     WHERE NOT (x.line_key = ANY (v_matched));
  END IF;
  RETURN v_sort;
END;
$function$;

-- ---------------------------------------------------------------- Isi harga baris CBD (quotation / estimasi)
-- Satu pintu untuk tombol harga di grid: material Quotation = harga quotation (seperti sebelumnya); baris Catalog tanpa
-- Material Code di Pullover / Preview = ESTIMATE. Kosong = hapus harga.
CREATE OR REPLACE FUNCTION fn_cbd_set_quotation(p_token text, p_line_id uuid, p_price numeric,
                                                p_currency text, p_reference text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_line_factory(p_line_id));
  v_line   cbd_line%ROWTYPE := fn_cbd_price_line(p_line_id);
  v_method text := (SELECT price_method FROM material WHERE id = v_line.material_id);
  v_stage  text := (SELECT stage FROM cbd_revision WHERE id = v_line.cbd_revision_id);
  v_src    text;
BEGIN
  IF v_method = 'QUOTATION' THEN
    v_src := 'QUOTATION';
  ELSIF v_line.variant_id IS NULL AND NOT fn_stage_code_required(v_stage) THEN
    v_src := 'ESTIMATE';
  ELSIF v_line.variant_id IS NULL THEN
    RAISE EXCEPTION 'From SMS every line needs a Material Code and a master price. Estimates are only for Pullover and Preview.';
  ELSE
    RAISE EXCEPTION 'This line has a Material Code: it uses the master price. Propose the master price instead.';
  END IF;
  IF p_price IS NULL THEN
    UPDATE cbd_line SET price_original = NULL, currency = NULL, price_source = NULL, material_price_id = NULL,
                        price_override_reason = NULL, price_reference = NULL, updated_by = v_email
     WHERE id = v_line.id;
  ELSE
    PERFORM fn_cbd_check_price(p_price, p_currency);
    UPDATE cbd_line SET price_original = p_price, currency = p_currency, price_source = v_src,
                        material_price_id = NULL, price_override_reason = NULL,
                        price_reference = nullif(btrim(coalesce(p_reference, '')), ''),
                        no_charge = false, no_charge_reason = NULL, updated_by = v_email
     WHERE id = v_line.id;
  END IF;
  RETURN v_line.id;
END;
$$;

-- ---------------------------------------------------------------- Saran estimasi terakhir
-- Estimasi terakhir (CBD lain, draft atau terbit) untuk material + thickness + supplier baris ini; warna sama didahulukan.
-- Dipakai di form Estimate (tombol Use) dan sebagai isian awal Propose master price.
CREATE OR REPLACE FUNCTION fn_cbd_estimate_hint(p_token text, p_line_id uuid)
RETURNS TABLE (price numeric, currency text, reference text, source_label text, entered_on text)
LANGUAGE plpgsql AS $$
DECLARE
  v_line cbd_line%ROWTYPE;
BEGIN
  PERFORM fn_auth_in(p_token, 'view_cbd', fn_cbd_line_factory(p_line_id));
  SELECT * INTO v_line FROM cbd_line WHERE id = p_line_id;
  IF NOT FOUND OR v_line.supplier_id IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT x.price_original, x.currency, x.price_reference,
         pm.name || ' · ' || a.code || ' · ' || fn_rev_label(cr.stage, cr.revision_no)
           || CASE WHEN cr.status = 'DRAFT' THEN ' (draft)' ELSE '' END,
         to_char(x.updated_at AT TIME ZONE 'Asia/Jakarta', 'DD Mon YYYY')
    FROM cbd_line x
    JOIN cbd_revision cr ON cr.id = x.cbd_revision_id
    JOIN article a ON a.id = cr.article_id
    JOIN specsheet sh ON sh.id = a.specsheet_id
    JOIN product_model pm ON pm.id = sh.model_id
   WHERE x.price_source = 'ESTIMATE' AND x.id <> v_line.id AND x.status = 'ACTIVE'
     AND x.material_id = v_line.material_id AND x.supplier_id = v_line.supplier_id
     AND fn_normalize(coalesce(x.thickness, '')) = fn_normalize(coalesce(v_line.thickness, ''))
   ORDER BY (fn_normalize(coalesce(x.color, '')) = fn_normalize(coalesce(v_line.color, ''))) DESC, x.updated_at DESC
   LIMIT 1;
END;
$$;

-- ---------------------------------------------------------------- Cek
SELECT 'fn_login 3 parameter: ' || (to_regprocedure('fn_login(text,text,boolean)') IS NOT NULL)::text AS cek
UNION ALL SELECT 'fn_login lama (2 parameter) sudah hilang: ' || (to_regprocedure('fn_login(text,text)') IS NULL)::text
UNION ALL SELECT 'sesi aktif: ' || count(*)::text || ', remember: ' || count(*) FILTER (WHERE remember)::text
  FROM app_session WHERE expires_at > now()
UNION ALL SELECT 'kode wajib mulai SMS: ' || string_agg(stage || '=' || fn_stage_code_required(stage), ' ' ORDER BY fn_stage_order(stage))
  FROM unnest(fn_stages()) stage
UNION ALL SELECT 'sumber harga ESTIMATE diterima: '
       || (pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname = 'cbd_line_price_source_check')) LIKE '%ESTIMATE%')::text
UNION ALL SELECT 'specsheet terbit dengan sel kuning (Pullover / Preview): ' || count(*)::text
  FROM v_revision_checklist WHERE status = 'PUBLISHED' AND yellow_cells > 0;

COMMIT;
