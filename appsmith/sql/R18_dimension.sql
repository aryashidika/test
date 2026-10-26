-- R18 (2026-10-26): kata "thickness" di pesan yang terlihat user -> "dimension". Nama kolom / fungsi tetap.
-- Isi fungsi = definisi R17 (pg_get_functiondef dari DB uji R17), hanya teks pesan yang diganti.
-- Jalankan sekali setelah R17_remember_estimate.sql. Aman diulang. Tidak mengubah data.

BEGIN;

-- fn_thickness_label
CREATE OR REPLACE FUNCTION public.fn_thickness_label(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT coalesce(nullif(btrim(coalesce(p, '')), ''), 'no dimension')
$function$;

-- fn_bom_add_line
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
      RAISE EXCEPTION 'Component % with this material (same dimension) is already in this revision.', v_comp.number;
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

-- fn_bom_cell_set
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
        RAISE EXCEPTION 'Code % is % · % · %. It does not match the material / dimension of this line.',
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

-- fn_bom_replace_material
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
    RAISE EXCEPTION 'The new material and dimension are the same as the current ones.';
  END IF;
  PERFORM fn_bom_check_material(p_material_id, v_factory);
  IF v_old.parent_line_key IS NULL AND EXISTS (
       SELECT 1 FROM bom_line WHERE revision_id = v_old.revision_id AND is_active AND parent_line_key IS NULL
          AND id <> v_old.id AND material_id = p_material_id AND thickness IS NOT DISTINCT FROM v_thick
          AND component_id IS NOT DISTINCT FROM v_old.component_id
          AND local_component_no IS NOT DISTINCT FROM v_old.local_component_no) THEN
    RAISE EXCEPTION 'This component with that material + dimension is already in this revision.';
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

-- fn_variant_save
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
    RAISE EXCEPTION 'Variant % is used in published documents. Its Material Code, color, and dimension cannot be changed. Set it INACTIVE and register a new variant.', v_old.code;
  END IF;
  UPDATE material_variant
     SET code = p_code, color = p_color, thickness = p_thickness, status = p_status, updated_by = v_email
   WHERE id = p_id;
  PERFORM set_config('app.variant_confirm', 'off', true);
  RETURN p_id;
END;
$function$;

-- fn_material_variant_check
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
    -- R16 (review): arti bagian kode = thickness yang PALING BANYAK memakainya (seri: yang tercatat paling awal), sama dengan
    -- fn_variant_code_hint / form. Dulu dicari varian pertama yang BERBEDA, sehingga setelah satu pengecualian dikonfirmasi
    -- (404 = 58") semua varian normal (404 = 44") ikut diminta konfirmasi.
    SELECT x.code, x.thickness, x.tkey INTO v_other
      FROM (SELECT v.thickness_key AS tkey, count(*) AS n, min(v.created_at) AS first_at,
                   (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                   (array_agg(v.thickness ORDER BY v.created_at, v.code))[1] AS thickness
              FROM material_variant v
             WHERE v.factory_id = NEW.factory_id AND length(v.code) = 10 AND v.id <> NEW.id
               AND substr(v.code, 5, 3) = substr(NEW.code, 5, 3)
             GROUP BY v.thickness_key) x
     ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
    IF FOUND AND v_other.tkey <> v_tkey THEN
      RAISE EXCEPTION 'Confirmation needed: dimension code % is recorded as "%" (code %), not "%". Check the Material Code; if it matches ERP, tick the confirmation and save.',
        substr(NEW.code, 5, 3), fn_thickness_label(v_other.thickness), v_other.code, fn_thickness_label(NEW.thickness);
    END IF;
    SELECT x.code, x.color, x.ckey INTO v_other
      FROM (SELECT v.color_key AS ckey, count(*) AS n, min(v.created_at) AS first_at,
                   (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                   (array_agg(v.color ORDER BY v.created_at, v.code))[1] AS color
              FROM material_variant v
             WHERE v.factory_id = NEW.factory_id AND length(v.code) = 10 AND v.id <> NEW.id
               AND substr(v.code, 8, 3) = substr(NEW.code, 8, 3)
             GROUP BY v.color_key) x
     ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
    IF FOUND AND v_other.ckey <> v_ckey THEN
      RAISE EXCEPTION 'Confirmation needed: color code % is recorded as "%" (code %), not "%". Check the Material Code; if it matches ERP, tick the confirmation and save.',
        substr(NEW.code, 8, 3), v_other.color, v_other.code, NEW.color;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

SELECT 'teks kosong: ' || fn_thickness_label(NULL) AS cek_r18;

COMMIT;
