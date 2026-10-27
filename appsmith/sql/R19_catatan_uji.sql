-- ============================================================================
-- R19 (26 Okt 2026, PLAN.md R19): catatan uji user. Jalankan SETELAH R18_dimension.sql, lewat z_run_sql di app "DB Tools"
-- (Use prepared statements = OFF). Aman diulang. Satu transaksi. Tanpa reset data.
--   1. Nomor komponen = posisi: nomor yang sudah dipakai di kelompok yang sama -> komponen itu dan yang menempel di bawahnya
--      bergeser +10 (sampai ada celah). Nomor di dokumen lama ikut berubah (dibaca dari master, disetujui user).
--   2. Nomor artikel boleh kosong: Pullover / Preview bebas, SMS / GTM peringatan (app), Production terbit diblokir.
--   4. Material Process: tanpa Material Code, sel tidak kuning, harga QUOTATION per baris CBD tanpa approval.
--   5. Ganti komponen di specsheet draft: semua baris komponen itu pindah ke komponen master lain (tujuan sudah ada = ditolak).
--   8. Semua field model wajib.
-- (Poin 3, 6, 7 hanya di app.)
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_login(text, text, boolean)') IS NULL OR to_regprocedure('fn_stage_code_required(text)') IS NULL THEN
    RAISE EXCEPTION 'R17 belum terpasang. Jalankan sql/R17_remember_estimate.sql dan sql/R18_dimension.sql dulu.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Kolom
-- R19 (2): nomor artikel boleh kosong (NULL); colorway tetap wajib
ALTER TABLE article ALTER COLUMN code DROP NOT NULL;
ALTER TABLE article DROP CONSTRAINT IF EXISTS article_code_check;
UPDATE article SET code = NULL WHERE btrim(code) = '';
-- R19 (4): material Process = biaya proses (printing, emboss, ...), tanpa Material Code, harga dari quotation per model
ALTER TABLE material ADD COLUMN IF NOT EXISTS is_process boolean NOT NULL DEFAULT false;

-- fn_component_check: R16 + bypass saat menggeser (R19)
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

  -- R19: fn_component_make_room / fn_component_save sedang menggeser nomor (urutan dijaga fungsinya; unik dijaga constraint)
  IF current_setting('app.component_shift', true) = 'on' THEN

    RETURN NEW;

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

-- ---------------------------------------------------------------- 1. Nomor komponen = posisi
-- Nomor p_number dipakai komponen lain (selain p_self) -> komponen itu dan yang menempel di bawahnya (p_number + 10, + 20, ...)
-- bergeser +10 sampai ada celah. Hanya di dalam kelompok p_group; lewat batas rentang kelompok = ditolak. Celah tidak dirapatkan.
-- Dipakai saat TAMBAH dan saat edit pindah kelompok. p_self (edit) yang berada di dalam blok dipindah dulu ke nomor sementara.
CREATE OR REPLACE FUNCTION fn_component_make_room(p_group text, p_number integer, p_self uuid, p_email text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_group component_group%ROWTYPE;
  v_end   integer;
  v_n     integer := 0;
  r       record;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('component-number'));
  SELECT * INTO v_group FROM component_group WHERE code = p_group;
  IF NOT FOUND OR p_number IS NULL OR p_number % 10 <> 0
     OR p_number NOT BETWEEN v_group.range_start AND v_group.range_end THEN
    RETURN 0;                                  -- pesan aturan nomor dari trg_component_check
  END IF;
  IF NOT EXISTS (SELECT 1 FROM component WHERE number = p_number AND id IS DISTINCT FROM p_self) THEN
    RETURN 0;
  END IF;
  v_end := p_number;
  WHILE EXISTS (SELECT 1 FROM component WHERE number = v_end AND id IS DISTINCT FROM p_self) LOOP
    v_end := v_end + 10;
  END LOOP;
  IF v_end > v_group.range_end THEN
    RAISE EXCEPTION 'Number % is taken and the components after it cannot move down: group % (%–%) has no free number after %. Choose another number.',
      p_number, v_group.name, v_group.range_start, v_group.range_end, p_number;
  END IF;
  PERFORM set_config('app.component_shift', 'on', true);
  IF p_self IS NOT NULL THEN
    UPDATE component SET number = -10 WHERE id = p_self AND number BETWEEN p_number AND v_end;   -- sementara
  END IF;
  FOR r IN SELECT id FROM component
            WHERE number >= p_number AND number < v_end AND id IS DISTINCT FROM p_self
            ORDER BY number DESC LOOP                -- dari bawah dulu: nomor unik tidak bentrok
    UPDATE component SET number = number + 10, updated_by = p_email WHERE id = r.id;
    v_n := v_n + 1;
  END LOOP;
  PERFORM set_config('app.component_shift', 'off', true);
  RETURN v_n;
END;
$function$;

-- R19 (koreksi user 26 Okt 2026, seperti Master Options): EDIT nomor di kelompok yang sama = pindah posisi. Nomor tujuan terpakai:
--   pindah ke bawah (nomor lebih besar)  -> komponen di antara (lama, baru] naik 10   (50 -> 60: yang di 60 jadi 50)
--   pindah ke atas  (nomor lebih kecil)  -> komponen di antara [baru, lama) turun 10  (80 -> 50: 50/60/70 jadi 60/70/80)
-- Nomor tujuan kosong = hanya komponen ini yang pindah. Tidak ada yang keluar rentang (nomor lama yang kosong dipakai).
CREATE OR REPLACE FUNCTION fn_component_move(p_group text, p_old integer, p_new integer, p_self uuid, p_email text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_group component_group%ROWTYPE;
  v_n     integer := 0;
  r       record;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('component-number'));
  SELECT * INTO v_group FROM component_group WHERE code = p_group;
  IF NOT FOUND OR p_new IS NULL OR p_new % 10 <> 0 OR p_new NOT BETWEEN v_group.range_start AND v_group.range_end
     OR p_old IS NULL OR p_new = p_old THEN
    RETURN 0;                                  -- pesan aturan nomor dari trg_component_check
  END IF;
  IF NOT EXISTS (SELECT 1 FROM component WHERE number = p_new AND id <> p_self) THEN
    RETURN 0;
  END IF;
  PERFORM set_config('app.component_shift', 'on', true);
  UPDATE component SET number = -10 WHERE id = p_self;                 -- sementara: nomor lama jadi kosong
  IF p_new > p_old THEN
    FOR r IN SELECT id FROM component WHERE number > p_old AND number <= p_new AND id <> p_self ORDER BY number LOOP
      UPDATE component SET number = number - 10, updated_by = p_email WHERE id = r.id;
      v_n := v_n + 1;
    END LOOP;
  ELSE
    FOR r IN SELECT id FROM component WHERE number >= p_new AND number < p_old AND id <> p_self ORDER BY number DESC LOOP
      UPDATE component SET number = number + 10, updated_by = p_email WHERE id = r.id;
      v_n := v_n + 1;
    END LOOP;
  END IF;
  PERFORM set_config('app.component_shift', 'off', true);
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION fn_component_add(p_token text, p_group_code text, p_number integer, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_id    uuid;
BEGIN
  IF nullif(btrim(coalesce(p_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Component name is required.';
  END IF;
  PERFORM fn_component_make_room(p_group_code, p_number, NULL, v_email);   -- R19
  INSERT INTO component (number, name, group_code, status, updated_by)
  VALUES (p_number, p_name, p_group_code, 'ACTIVE', v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- R19: nomor boleh dipindah walau komponen dipakai di dokumen terbit (nomor = posisi); nama & kelompok tetap terkunci
CREATE OR REPLACE FUNCTION fn_component_save(p_token text, p_id uuid, p_group_code text, p_number integer, p_name text, p_status text)
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
  IF fn_normalize(p_name) IS DISTINCT FROM fn_normalize(v_old.name) OR p_group_code IS DISTINCT FROM v_old.group_code THEN
    v_used := fn_master_usage('COMPONENT', p_id, true);
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION 'Name and group of component % cannot be changed: it is used in published documents (%). The number can still be changed.', v_old.number, v_used;
    END IF;
  END IF;
  IF p_status = 'INACTIVE' AND v_old.status <> 'INACTIVE' THEN
    v_used := fn_master_usage('COMPONENT', p_id, false);
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION 'Component % is still used in drafts: %. Replace it in those drafts first.', v_old.number, v_used;
    END IF;
  END IF;
  IF p_group_code IS DISTINCT FROM v_old.group_code THEN
    PERFORM fn_component_make_room(p_group_code, p_number, p_id, v_email);   -- R19: kelompok lain = seperti tambah baru
  ELSIF p_number IS DISTINCT FROM v_old.number THEN
    PERFORM fn_component_move(p_group_code, v_old.number, p_number, p_id, v_email);   -- R19: pindah posisi (Master Options)
  END IF;
  UPDATE component
     SET group_code = p_group_code, number = p_number, name = p_name, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$function$;

-- ---------------------------------------------------------------- 2. Nomor artikel boleh kosong
-- Teks tampilan: nomor, atau "(no article no.)" (kolom yang tampil bersama colorway) / "(no article no.) <colorway>" (pesan)
CREATE OR REPLACE FUNCTION fn_article_code_label(p_code text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT coalesce(nullif(btrim(coalesce(p_code, '')), ''), '(no article no.)')
$function$;

CREATE OR REPLACE FUNCTION fn_article_label(p_code text, p_colorway text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT coalesce(nullif(btrim(coalesce(p_code, '')), ''), '(no article no.) ' || coalesce(p_colorway, ''))
$function$;

-- Nomor artikel wajib mulai stage ini (keputusan user 26 Okt 2026: Production). SMS / GTM = peringatan di checklist app.
CREATE OR REPLACE FUNCTION fn_stage_article_required(p_stage text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  SELECT fn_stage_order(p_stage) >= fn_stage_order('PROD')
$function$;

-- R19 (keputusan user 27 Okt 2026, opsi B): nomor boleh dikoreksi (salah ketik) selama article belum ada di specsheet / CBD
-- PRODUCTION yang terbit; sesudah itu terkunci. Dokumen terbit stage awal ikut menampilkan nomor baru (dibaca dari master).
CREATE OR REPLACE FUNCTION fn_article_prod_published(p_article_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM revision_article ra JOIN specsheet_revision r ON r.id = ra.revision_id
                  WHERE ra.article_id = p_article_id AND r.status = 'PUBLISHED' AND r.stage = 'PROD')
      OR EXISTS (SELECT 1 FROM cbd_revision c WHERE c.article_id = p_article_id AND c.status = 'PUBLISHED' AND c.stage = 'PROD')
$function$;

-- R19: kosong = NULL (boleh). Nomor boleh DIISI belakangan walau article sudah dipakai; nomor yang sudah ada boleh DIGANTI selama
-- belum ada di Production terbit; nomor yang sudah dipakai tidak bisa DIKOSONGKAN lagi. Article tanpa nomor dikenali dari colorway.
CREATE OR REPLACE FUNCTION fn_article_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.code     := nullif(btrim(regexp_replace(coalesce(NEW.code, ''), '\s+', ' ', 'g')), '');
  NEW.colorway := btrim(regexp_replace(coalesce(NEW.colorway, ''), '\s+', ' ', 'g'));
  IF NEW.colorway = '' THEN RAISE EXCEPTION 'Colorway is required.'; END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.specsheet_id IS DISTINCT FROM OLD.specsheet_id THEN
      RAISE EXCEPTION 'An article cannot be moved to another season.';
    END IF;
    IF OLD.code IS NOT NULL AND NEW.code IS DISTINCT FROM OLD.code AND fn_article_prod_published(OLD.id) THEN
      RAISE EXCEPTION 'Article no. % cannot be changed because it is in a published Production specsheet/CBD.', OLD.code;
    END IF;
    IF OLD.code IS NOT NULL AND NEW.code IS NULL AND fn_article_is_used(OLD.id) THEN
      RAISE EXCEPTION 'Article no. % cannot be cleared because the article is used in a specsheet/CBD. Type the correct number instead.', OLD.code;
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    PERFORM 1 FROM specsheet WHERE id = NEW.specsheet_id FOR UPDATE;   -- antre per season (cek kode unik)
  END IF;
  IF NEW.code IS NOT NULL AND EXISTS (SELECT 1 FROM article WHERE specsheet_id = NEW.specsheet_id AND upper(code) = upper(NEW.code)
                                                               AND id <> NEW.id) THEN
    RAISE EXCEPTION 'Article no. % already exists in this season.', NEW.code;
  END IF;
  IF NEW.code IS NULL AND EXISTS (SELECT 1 FROM article WHERE specsheet_id = NEW.specsheet_id AND code IS NULL
                                                          AND upper(colorway) = upper(NEW.colorway) AND id <> NEW.id) THEN
    RAISE EXCEPTION 'An article without article no. with colorway % already exists in this season. Fill in the article no. of one of them.', NEW.colorway;
  END IF;
  RETURN NEW;
END;
$function$;

-- v_revision_checklist: R17 + nomor artikel (R19) + material Process tidak kuning (R19)
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
    active_articles = 0 OR unused_articles IS NOT NULL OR inactive_materials IS NOT NULL OR no_supplier_lines > 0 OR yellow_cells > 0 AND code_required OR inactive_suppliers IS NOT NULL OR no_code_articles > 0 AND article_required AS blocked,
    code_required,
    no_code_articles,
    no_code_list,
    article_required
   FROM ( SELECT r.id AS revision_id,
            r.specsheet_id,
            r.stage,
            r.revision_no,
            r.status,
            (EXISTS ( SELECT 1
                   FROM specsheet_revision o
                  WHERE o.specsheet_id = r.specsheet_id AND o.status = 'PUBLISHED'::text AND o.id <> r.id)) AS requires_reason,
            ( SELECT count(*)::integer AS count
                   FROM bom_line l
                  WHERE l.revision_id = r.id AND l.is_active) AS line_count,
            ( SELECT count(*)::integer AS count
                   FROM revision_article ra
                  WHERE ra.revision_id = r.id AND ra.status = 'ACTIVE'::text) AS active_articles,
            ( SELECT string_agg(fn_article_label(a.code, a.colorway), ', '::text ORDER BY a.code, a.colorway) AS string_agg
                   FROM revision_article ra
                     JOIN article a ON a.id = ra.article_id
                  WHERE ra.revision_id = r.id AND ra.status = 'ACTIVE'::text AND NOT (EXISTS ( SELECT 1
                           FROM bom_cell c
                             JOIN bom_line l ON l.id = c.bom_line_id
                          WHERE l.revision_id = r.id AND l.is_active AND c.article_id = a.id AND c.is_used))) AS unused_articles,
            ( SELECT string_agg(DISTINCT m.name, ', '::text) AS string_agg
                   FROM bom_line l
                     JOIN material m ON m.id = l.material_id
                  WHERE l.revision_id = r.id AND l.is_active AND m.status = 'INACTIVE'::text) AS inactive_materials,
            ( SELECT count(*)::integer AS count
                   FROM bom_line l
                  WHERE l.revision_id = r.id AND l.is_active AND l.supplier_id IS NULL) AS no_supplier_lines,
            ( SELECT count(*)::integer AS count
                   FROM bom_cell c
                     JOIN bom_line l ON l.id = c.bom_line_id AND l.revision_id = r.id AND l.is_active
                     JOIN material m ON m.id = l.material_id AND NOT m.is_process
                     JOIN revision_article ra ON ra.revision_id = r.id AND ra.article_id = c.article_id AND ra.status = 'ACTIVE'::text
                  WHERE c.is_used AND c.variant_id IS NULL) AS yellow_cells,
            ( SELECT "left"(string_agg(DISTINCT ((m.name || COALESCE(' '::text || l.thickness, ''::text)) || ' · '::text) || c.color, ', '::text), 300) AS "left"
                   FROM bom_cell c
                     JOIN bom_line l ON l.id = c.bom_line_id AND l.revision_id = r.id AND l.is_active
                     JOIN material m ON m.id = l.material_id
                     JOIN revision_article ra ON ra.revision_id = r.id AND ra.article_id = c.article_id AND ra.status = 'ACTIVE'::text
                  WHERE c.is_used AND c.variant_id IS NULL AND NOT m.is_process) AS yellow_list,
            ( SELECT string_agg(DISTINCT ((s.name || ' ('::text) || m.name) || ')'::text, ', '::text) AS string_agg
                   FROM bom_line l
                     JOIN supplier s ON s.id = l.supplier_id
                     JOIN material m ON m.id = l.material_id
                     LEFT JOIN material_supplier ms ON ms.material_id = l.material_id AND ms.supplier_id = l.supplier_id
                  WHERE l.revision_id = r.id AND l.is_active AND (s.status = 'INACTIVE'::text OR ms.status = 'INACTIVE'::text)) AS inactive_suppliers,
            fn_stage_code_required(r.stage) AS code_required,
            ( SELECT count(*)::integer AS count
                   FROM revision_article ra
                     JOIN article a ON a.id = ra.article_id
                  WHERE ra.revision_id = r.id AND ra.status = 'ACTIVE'::text AND a.code IS NULL) AS no_code_articles,
            ( SELECT "left"(string_agg(a.colorway, ', '::text ORDER BY a.colorway), 300) AS "left"
                   FROM revision_article ra
                     JOIN article a ON a.id = ra.article_id
                  WHERE ra.revision_id = r.id AND ra.status = 'ACTIVE'::text AND a.code IS NULL) AS no_code_list,
            fn_stage_article_required(r.stage) AS article_required
           FROM specsheet_revision r) x;;

-- fn_revision_publish: R17 + nomor artikel wajib di Production (R19)
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
  IF v_chk.no_code_articles > 0 AND v_chk.article_required THEN   -- R19: nomor artikel wajib di Production
    RAISE EXCEPTION 'In Production every article needs an article no. % article(s) have none (colorway: %). Fill it in Model Detail first.',
      v_chk.no_code_articles, v_chk.no_code_list;
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

-- v_worklist_cbd: nomor artikel kosong tampil "(no article no.)" (R19)
CREATE OR REPLACE VIEW v_worklist_cbd AS
 WITH art AS MATERIALIZED (
         SELECT a.id,
            a.code,
            a.colorway,
            a.specsheet_id,
            sh.season,
            sh.model_id,
            sp.id AS spec_pub_id,
            sp.stage_order AS spec_stage_order
           FROM specsheet sh
             JOIN specsheet_revision sp ON sp.id = fn_spec_latest_pub(sh.id)
             JOIN revision_article ra ON ra.revision_id = sp.id AND ra.status = 'ACTIVE'::text
             JOIN article a ON a.id = ra.article_id
        )
 SELECT kind,
    refresh_reason,
    article_id,
    article_code,
    colorway,
    model_id,
    model_name,
    factory_id,
    specsheet_id,
    season,
    cbd_revision_id,
    rev_label,
    pending_prices
   FROM ( SELECT
                CASE
                    WHEN rc.n = 0 THEN 'TO_CREATE'::text
                    WHEN d.id IS NOT NULL THEN
                    CASE
                        WHEN d.specsheet_revision_id IS DISTINCT FROM ds.spec_id OR pr.stale_prices > 0 THEN 'TO_REFRESH'::text
                        ELSE 'IN_PROGRESS'::text
                    END
                    WHEN p.stage_order < art.spec_stage_order OR p.sync_status = 'NEEDS_REVISION'::text THEN 'TO_REVISE'::text
                    ELSE NULL::text
                END AS kind,
                CASE
                    WHEN d.id IS NOT NULL THEN
                    CASE
                        WHEN d.specsheet_revision_id IS DISTINCT FROM ds.spec_id THEN 'SPEC'::text
                        WHEN pr.stale_prices > 0 THEN 'PRICE'::text
                        ELSE NULL::text
                    END
                    WHEN p.stage_order < art.spec_stage_order THEN 'STAGE'::text
                    ELSE NULL::text
                END AS refresh_reason,
            art.id AS article_id,
            fn_article_code_label(art.code) AS article_code,
            art.colorway,
            pm.id AS model_id,
            pm.name AS model_name,
            pm.factory_id,
            art.specsheet_id,
            art.season,
            COALESCE(d.id, p.id) AS cbd_revision_id,
            COALESCE(fn_rev_label(d.stage, d.revision_no), fn_rev_label(p.stage, p.revision_no)) AS rev_label,
            pr.pending_prices
           FROM art
             JOIN product_model pm ON pm.id = art.model_id
             LEFT JOIN cbd_revision d ON d.article_id = art.id AND d.status = 'DRAFT'::text
             LEFT JOIN LATERAL ( SELECT fn_spec_latest_pub_stage(art.specsheet_id, d.stage) AS spec_id) ds ON d.id IS NOT NULL
             LEFT JOIN LATERAL ( SELECT r.id,
                    r.stage,
                    r.revision_no,
                    r.sync_status,
                    r.stage_order
                   FROM cbd_revision r
                  WHERE r.article_id = art.id AND r.status = 'PUBLISHED'::text
                  ORDER BY r.stage_order DESC, r.revision_no DESC
                 LIMIT 1) p ON true
             CROSS JOIN LATERAL ( SELECT count(*)::integer AS n
                   FROM cbd_revision c
                  WHERE c.article_id = art.id) rc
             CROSS JOIN LATERAL ( SELECT count(*) FILTER (WHERE pc.master_stale)::integer AS stale_prices,
                    count(*) FILTER (WHERE pc.pending)::integer AS pending_prices
                   FROM v_cbd_price_check pc
                  WHERE pc.cbd_revision_id = d.id) pr) x
  WHERE kind IS NOT NULL;;

-- v_recent_published: idem
CREATE OR REPLACE VIEW v_recent_published AS
 SELECT 'SPECSHEET'::text AS doc_type,
    r.id AS revision_id,
    pm.id AS model_id,
    pm.name AS model_name,
    pm.factory_id,
    f.name AS factory_name,
    sh.id AS specsheet_id,
    sh.season,
    NULL::uuid AS article_id,
    NULL::text AS article_code,
    NULL::text AS colorway,
    r.stage,
    r.revision_no,
    r.published_at,
    r.published_by,
    NULL::text AS sync_status
   FROM specsheet sh
     JOIN product_model pm ON pm.id = sh.model_id
     JOIN factory f ON f.id = pm.factory_id
     JOIN specsheet_revision r ON r.id = fn_spec_latest_pub(sh.id)
UNION ALL
 SELECT 'CBD'::text AS doc_type,
    c.id AS revision_id,
    pm.id AS model_id,
    pm.name AS model_name,
    pm.factory_id,
    f.name AS factory_name,
    sh.id AS specsheet_id,
    sh.season,
    a.id AS article_id,
    fn_article_code_label(a.code) AS article_code,
    a.colorway,
    c.stage,
    c.revision_no,
    c.published_at,
    c.published_by,
    c.sync_status
   FROM article a
     JOIN specsheet sh ON sh.id = a.specsheet_id
     JOIN product_model pm ON pm.id = sh.model_id
     JOIN factory f ON f.id = pm.factory_id
     JOIN LATERAL ( SELECT x.id,
            x.stage,
            x.revision_no,
            x.published_at,
            x.published_by,
            x.sync_status
           FROM cbd_revision x
          WHERE x.article_id = a.id AND x.status = 'PUBLISHED'::text
          ORDER BY x.stage_order DESC, x.revision_no DESC
         LIMIT 1) c ON true;;

-- fn_master_usage: idem
CREATE OR REPLACE FUNCTION public.fn_master_usage(p_kind text, p_id uuid, p_published boolean)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT left(string_agg(x.label, ', ' ORDER BY x.label), 300)
    FROM (
      SELECT pm.name || ' ' || sp.season || ' (specsheet)' AS label
        FROM bom_line l
        JOIN specsheet_revision r ON r.id = l.revision_id
        JOIN specsheet sp ON sp.id = r.specsheet_id
        JOIN product_model pm ON pm.id = sp.model_id
       WHERE (r.status = 'PUBLISHED') = p_published
         AND CASE p_kind WHEN 'SUPPLIER' THEN l.supplier_id WHEN 'COMPONENT' THEN l.component_id END = p_id
      UNION
      SELECT pm.name || ' ' || sp.season || ' · ' || fn_article_label(a.code, a.colorway) || ' (CBD)'
        FROM cbd_line cl
        JOIN cbd_revision c ON c.id = cl.cbd_revision_id
        JOIN article a ON a.id = c.article_id
        JOIN specsheet sp ON sp.id = a.specsheet_id
        JOIN product_model pm ON pm.id = sp.model_id
       WHERE (c.status = 'PUBLISHED') = p_published
         AND CASE p_kind WHEN 'SUPPLIER' THEN cl.supplier_id WHEN 'COMPONENT' THEN cl.component_id END = p_id
    ) x
$function$;

-- fn_cbd_create: pesan dengan label artikel (R19)
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
    RAISE EXCEPTION 'Article % is dropped in the latest published specsheet. Its CBD cannot be created anymore.', fn_article_label(v_art.code, v_art.colorway);
  ELSIF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article % is not in a published specsheet revision. Publish the specsheet first.', fn_article_label(v_art.code, v_art.colorway);
  END IF;
  IF EXISTS (SELECT 1 FROM cbd_revision WHERE article_id = v_art.id AND status = 'DRAFT') THEN
    RAISE EXCEPTION 'Article % already has a CBD DRAFT. Publish or delete that draft first.', fn_article_label(v_art.code, v_art.colorway);
  END IF;

  -- R13: stage dipilih (default stage specsheet terbit terbaru); acuan = specsheet terbit terakhir di stage itu
  v_stage := coalesce(nullif(btrim(coalesce(p_stage, '')), ''),
                      (SELECT stage FROM specsheet_revision WHERE id = fn_spec_latest_pub(v_art.specsheet_id)));
  IF NOT (v_stage = ANY (fn_stages())) THEN
    RAISE EXCEPTION 'Unknown stage %.', fn_stage_label(v_stage);
  END IF;
  SELECT * INTO v_spec FROM specsheet_revision WHERE id = fn_spec_latest_pub_stage(v_art.specsheet_id, v_stage);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No published % specsheet for article % yet.', fn_stage_label(v_stage), fn_article_label(v_art.code, v_art.colorway);
  END IF;
  IF fn_cbd_stage_spec_status(v_art.id, v_stage) <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article % is not active in specsheet % r%. The % CBD cannot be created.',
      fn_article_label(v_art.code, v_art.colorway), fn_stage_label(v_spec.stage), v_spec.revision_no, fn_stage_label(v_stage);
  END IF;
  SELECT * INTO v_maxpub FROM cbd_revision
   WHERE article_id = v_art.id AND status = 'PUBLISHED'
   ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
  IF FOUND AND v_maxpub.stage_order > v_spec.stage_order THEN
    RAISE EXCEPTION 'Article % already has a published % CBD. A CBD for an earlier stage (%) cannot be created anymore.',
      fn_article_label(v_art.code, v_art.colorway), fn_stage_label(v_maxpub.stage), fn_stage_label(v_stage);
  END IF;

  IF p_mode IN ('NEW', 'COPY') THEN
    IF EXISTS (SELECT 1 FROM cbd_revision WHERE article_id = v_art.id) THEN
      RAISE EXCEPTION 'Article % already has a CBD. Use Next revision.', fn_article_label(v_art.code, v_art.colorway);
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
        RAISE EXCEPTION 'Article % has no published CBD to copy.', fn_article_label(v_srcart.code, v_srcart.colorway);
      END IF;
    END IF;
  ELSIF p_mode = 'NEXT' THEN
    IF v_maxpub.id IS NULL THEN
      RAISE EXCEPTION 'Article % has no published CBD yet.', fn_article_label(v_art.code, v_art.colorway);
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
    SELECT pm.name || ' / ' || sp.season || ' / ' || fn_article_label(a.code, a.colorway) || ' / ' || fn_rev_label(v_src.stage, v_src.revision_no) INTO v_ref
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

-- v_worklist_spec: R11 + kolom no_code_articles (draft) + jenis NO_ARTICLE_NO (article tanpa nomor per season, Tugas Saya Vendor Spec)
CREATE OR REPLACE VIEW v_worklist_spec AS
 SELECT 'DRAFT'::text AS kind,
    pm.id AS model_id,
    pm.name AS model_name,
    pm.factory_id,
    sh.id AS specsheet_id,
    sh.season,
    r.id AS revision_id,
    r.stage,
    r.revision_no,
    ck.line_count,
    ck.no_supplier_lines AS no_supplier,
    ck.active_articles AS article_count,
    ck.unused_articles,
    ck.inactive_materials,
    NULL::text AS article_codes,
    NULL::boolean AS has_revision,
    ck.yellow_cells,
    ck.inactive_suppliers,
    ck.no_code_articles
   FROM specsheet_revision r
     JOIN specsheet sh ON sh.id = r.specsheet_id
     JOIN product_model pm ON pm.id = sh.model_id
     JOIN v_revision_checklist ck ON ck.revision_id = r.id
  WHERE r.status = 'DRAFT'::text
UNION ALL
 SELECT 'UNASSIGNED'::text AS kind,
    pm.id AS model_id,
    pm.name AS model_name,
    pm.factory_id,
    sh.id AS specsheet_id,
    sh.season,
    NULL::uuid AS revision_id,
    NULL::text AS stage,
    NULL::integer AS revision_no,
    NULL::integer AS line_count,
    NULL::integer AS no_supplier,
    u.n AS article_count,
    NULL::text AS unused_articles,
    NULL::text AS inactive_materials,
    u.codes AS article_codes,
    (EXISTS ( SELECT 1
           FROM specsheet_revision x
          WHERE x.specsheet_id = sh.id)) AS has_revision,
    NULL::integer AS yellow_cells,
    NULL::text AS inactive_suppliers,
    NULL::integer AS no_code_articles
   FROM specsheet sh
     JOIN product_model pm ON pm.id = sh.model_id
     CROSS JOIN LATERAL ( SELECT count(*)::integer AS n,
            string_agg(fn_article_label(a.code, a.colorway), ', '::text ORDER BY a.code, a.colorway) AS codes
           FROM article a
          WHERE a.specsheet_id = sh.id AND NOT (EXISTS ( SELECT 1
                   FROM revision_article ra
                  WHERE ra.article_id = a.id))) u
  WHERE u.n > 0
UNION ALL
 SELECT 'NO_ARTICLE_NO'::text AS kind,
    pm.id AS model_id,
    pm.name AS model_name,
    pm.factory_id,
    sh.id AS specsheet_id,
    sh.season,
    NULL::uuid AS revision_id,
    NULL::text AS stage,
    NULL::integer AS revision_no,
    NULL::integer AS line_count,
    NULL::integer AS no_supplier,
    u.n AS article_count,
    NULL::text AS unused_articles,
    NULL::text AS inactive_materials,
    u.colorways AS article_codes,
    NULL::boolean AS has_revision,
    NULL::integer AS yellow_cells,
    NULL::text AS inactive_suppliers,
    u.n AS no_code_articles
   FROM specsheet sh
     JOIN product_model pm ON pm.id = sh.model_id
     CROSS JOIN LATERAL ( SELECT count(*)::integer AS n,
            "left"(string_agg(a.colorway, ', '::text ORDER BY a.colorway), 300) AS colorways
           FROM article a
          WHERE a.specsheet_id = sh.id AND a.code IS NULL
            -- article yang DROPPED di revisi terakhirnya (draft dulu, lalu stage / nomor tertinggi) tidak perlu nomor lagi
            AND COALESCE(( SELECT ra.status
                   FROM revision_article ra
                     JOIN specsheet_revision r ON r.id = ra.revision_id
                  WHERE ra.article_id = a.id
                  ORDER BY (r.status = 'DRAFT'::text) DESC, r.stage_order DESC, r.revision_no DESC
                 LIMIT 1), 'ACTIVE'::text) <> 'DROPPED'::text) u
  WHERE u.n > 0;

-- ---------------------------------------------------------------- 4. Material Process
-- Tanda Process diisi Vendor Spec (manage_master) atau tim CBD (manage_price, yang juga mengatur metode harga; user 27 Okt 2026). Material Process: tanpa varian / Material Code, sel specsheet tidak kuning,
-- metode harga dikunci QUOTATION (harga per baris CBD, tanpa approval, ikut ke revisi CBD berikutnya: aturan Quotation F8).
-- Tanda hanya bisa diubah selama material belum dipakai di dokumen terbit; dipasang hanya bila material belum punya varian.
DROP FUNCTION IF EXISTS fn_material_add(text, text, text, text);
CREATE OR REPLACE FUNCTION fn_material_add(p_token text, p_name text, p_category text, p_uom text, p_is_process boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email   text := fn_auth(p_token, 'manage_master');
  v_factory uuid := fn_user_factory(v_email);
  v_proc    boolean := coalesce(p_is_process, false);
  v_id      uuid;
BEGIN
  IF v_factory IS NULL THEN
    RAISE EXCEPTION 'Your account has no factory yet. Ask the System Admin to set your factory.';
  END IF;
  INSERT INTO material (factory_id, name, category, uom, price_method, is_process, status, updated_by)
  VALUES (v_factory, p_name, p_category, p_uom, CASE WHEN v_proc THEN 'QUOTATION' ELSE 'CATALOG' END, v_proc, 'ACTIVE', v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

DROP FUNCTION IF EXISTS fn_material_update(text, uuid, text, text, text, text, text);
CREATE OR REPLACE FUNCTION fn_material_update(p_token text, p_id uuid, p_name text, p_category text, p_uom text, p_status text,
                                              p_price_method text, p_is_process boolean DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email  text := fn_auth_any(p_token, ARRAY['manage_master', 'manage_price']);
  v_master boolean := fn_has_perm(v_email, 'manage_master');
  v_price  boolean := fn_has_perm(v_email, 'manage_price');
  v_old    material%ROWTYPE;
  v_proc   boolean;
  v_method text;
BEGIN
  SELECT * INTO v_old FROM material WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Material not found.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_old.factory_id);
  v_proc := coalesce(p_is_process, v_old.is_process);      -- NULL = tidak diubah (app lama)
  IF NOT v_master AND (
       fn_normalize(p_name) IS DISTINCT FROM v_old.name_key
    OR fn_normalize(p_category) IS DISTINCT FROM fn_normalize(v_old.category)
    OR fn_normalize(p_uom) IS DISTINCT FROM fn_normalize(v_old.uom)
    OR p_status IS DISTINCT FROM v_old.status) THEN
    RAISE EXCEPTION 'Material data and status can only be changed by the specsheet team (Vendor Spec).';
  END IF;
  IF v_proc AND v_price AND coalesce(p_price_method, 'QUOTATION') <> 'QUOTATION' AND v_old.is_process THEN
    RAISE EXCEPTION 'A Process material always uses the Quotation price method (its price is entered per CBD line).';
  END IF;
  -- tanda Process berubah = metode harga ikut (Quotation / kembali Catalog), bukan perubahan metode oleh user
  IF NOT v_price AND p_price_method IS DISTINCT FROM v_old.price_method AND v_proc IS NOT DISTINCT FROM v_old.is_process THEN
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
  -- R19: tanda Process
  IF v_proc IS DISTINCT FROM v_old.is_process THEN
    IF fn_material_used_published(p_id) THEN
      RAISE EXCEPTION 'Process cannot be changed for material %: it is used in a published specsheet / CBD. Add a new material if needed.', v_old.name;
    END IF;
    IF v_proc AND EXISTS (SELECT 1 FROM material_variant WHERE material_id = p_id) THEN
      RAISE EXCEPTION 'Material % already has variants (Material Codes). A Process material has no Material Code: delete its variants first, or add a new Process material.', v_old.name;
    END IF;
  END IF;
  v_method := CASE WHEN v_proc THEN 'QUOTATION'
                   WHEN v_old.is_process AND v_price AND p_price_method = 'QUOTATION' THEN 'QUOTATION'   -- tim CBD: tetap Quotation
                   WHEN v_old.is_process THEN 'CATALOG'                  -- Process dilepas: kembali Catalog
                   WHEN v_price THEN p_price_method
                   ELSE v_old.price_method END;
  UPDATE material
     SET name         = CASE WHEN v_master THEN p_name     ELSE name END,
         category     = CASE WHEN v_master THEN p_category ELSE category END,
         uom          = CASE WHEN v_master THEN p_uom      ELSE uom END,
         status       = CASE WHEN v_master THEN p_status   ELSE status END,
         is_process   = v_proc,
         price_method = v_method,
         updated_by   = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$function$;

-- Material Process tidak punya varian (Material Code). Semua jalur (form, Register di specsheet, impor) lewat trigger ini.
CREATE OR REPLACE FUNCTION fn_variant_not_process()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_name text;
BEGIN
  SELECT name INTO v_name FROM material WHERE id = NEW.material_id AND is_process;
  IF FOUND THEN
    RAISE EXCEPTION 'Material % is a Process material: it has no Material Code (variants). Its price is entered per CBD line as a quotation.', v_name;
  END IF;
  RETURN NEW;
END;
$function$;

-- nama berawalan trg_a: jalan sebelum trg_material_variant_check (pesan kamus kode tidak relevan untuk Process)
DROP TRIGGER IF EXISTS trg_a_variant_not_process ON material_variant;
CREATE TRIGGER trg_a_variant_not_process BEFORE INSERT ON material_variant
  FOR EACH ROW EXECUTE FUNCTION fn_variant_not_process();

-- v_material_list: + is_process (R19)
CREATE OR REPLACE VIEW v_material_list AS
 SELECT m.id,
    m.factory_id,
    f.name AS factory_name,
    m.name,
    m.name_key,
    m.category,
    m.uom,
    m.price_method,
    m.status,
    m.updated_at,
    m.updated_by,
    COALESCE(v.variants, 0::bigint) AS variant_count,
    COALESCE(v.active_variants, 0::bigint) AS active_variant_count,
    v.thicknesses,
    v.codes,
    COALESCE(s.suppliers, 0::bigint) AS supplier_count,
    s.preferred_supplier,
    m.is_process
   FROM material m
     JOIN factory f ON f.id = m.factory_id
     LEFT JOIN LATERAL ( SELECT count(*) AS variants,
            count(*) FILTER (WHERE mv.status = 'ACTIVE'::text) AS active_variants,
            string_agg(DISTINCT fn_thickness_label(mv.thickness), ', '::text) AS thicknesses,
            string_agg(mv.code, ' '::text ORDER BY mv.code) AS codes
           FROM material_variant mv
          WHERE mv.material_id = m.id) v ON true
     LEFT JOIN LATERAL ( SELECT count(*) FILTER (WHERE ms.status = 'ACTIVE'::text) AS suppliers,
            max(sp.name) FILTER (WHERE ms.is_preferred) AS preferred_supplier
           FROM material_supplier ms
             JOIN supplier sp ON sp.id = ms.supplier_id
          WHERE ms.material_id = m.id) s ON true;;

-- v_bom_grid: material Process tidak kuning + is_process (R19)
CREATE OR REPLACE VIEW v_bom_grid AS
 SELECT l.id,
    l.revision_id,
    l.line_key,
    l.parent_line_key,
    l.parent_line_key IS NOT NULL AS is_sub,
    l.component_id,
    l.local_component_no,
    l.sub_seq,
        CASE
            WHEN l.parent_line_key IS NULL THEN COALESCE(c.number, l.local_component_no)
            ELSE COALESCE(pc.number, p.local_component_no)
        END AS group_no,
        CASE
            WHEN l.parent_line_key IS NULL THEN l.sort_order
            ELSE COALESCE(p.sort_order, l.sort_order)
        END AS group_sort,
        CASE
            WHEN l.parent_line_key IS NULL THEN COALESCE(c.number, l.local_component_no)::text
            ELSE COALESCE(COALESCE(pc.number, p.local_component_no)::text || '-'::text, ''::text) || l.sub_seq
        END AS display_no,
        CASE
            WHEN l.parent_line_key IS NULL THEN COALESCE(c.name, l.local_component_name)
            ELSE l.sub_name
        END AS display_name,
    l.component_id IS NULL AND l.parent_line_key IS NULL AS is_local,
    l.material_id,
    cc.codes AS material_code,
    m.name AS material_name,
    l.thickness,
    m.uom,
    m.status AS material_status,
    l.supplier_id,
    s.name AS supplier_name,
    ms.status AS link_status,
    l.process,
    l.origin_line_key,
    l.replaces_line_key,
    COALESCE(cc.cells, '{}'::jsonb) AS cells,
    s.status AS supplier_status,
    COALESCE(cc.cell_codes, '{}'::jsonb) AS cell_codes,
    COALESCE(cc.yellow, 0) AS yellow,
    u.id IS NOT NULL AS undo_replace,
        CASE
            WHEN u.id IS NOT NULL THEN um.name || COALESCE(' '::text || u.thickness, ''::text)
            ELSE NULL::text
        END AS undo_material,
    m.is_process
   FROM bom_line l
     JOIN material m ON m.id = l.material_id
     LEFT JOIN component c ON c.id = l.component_id
     LEFT JOIN bom_line p ON p.revision_id = l.revision_id AND p.line_key = l.parent_line_key AND p.is_active
     LEFT JOIN component pc ON pc.id = p.component_id
     LEFT JOIN supplier s ON s.id = l.supplier_id
     LEFT JOIN material_supplier ms ON ms.material_id = l.material_id AND ms.supplier_id = l.supplier_id
     LEFT JOIN LATERAL ( SELECT jsonb_object_agg(bc.article_id::text, bc.color) FILTER (WHERE bc.color IS NOT NULL) AS cells,
            jsonb_object_agg(bc.article_id::text, v.code) FILTER (WHERE v.id IS NOT NULL) AS cell_codes,
            string_agg(DISTINCT v.code, ', '::text) AS codes,
            count(*) FILTER (WHERE bc.is_used AND bc.variant_id IS NULL AND ra.status = 'ACTIVE'::text AND NOT m.is_process)::integer AS yellow
           FROM bom_cell bc
             LEFT JOIN material_variant v ON v.id = bc.variant_id
             LEFT JOIN revision_article ra ON ra.revision_id = l.revision_id AND ra.article_id = bc.article_id
          WHERE bc.bom_line_id = l.id) cc ON true
     LEFT JOIN bom_line u ON u.id =
        CASE
            WHEN l.replaces_line_key IS NOT NULL THEN fn_bom_undo_target(l.id)
            ELSE NULL::uuid
        END
     LEFT JOIN material um ON um.id = u.material_id
  WHERE l.is_active;;

-- ---------------------------------------------------------------- 5. Ganti komponen di specsheet draft
-- R19 (koreksi user 27 Okt 2026): yang diganti HANYA baris induk p_line_id (satu komponen bisa punya beberapa baris material,
-- mis. dua baris UPPER), subkomponennya ikut (menempel lewat parent_line_key). Baris nonaktif di rantai "Ganti material" baris itu
-- ikut, supaya "Undo replace" tidak mengembalikan komponen lama. line_key tetap = CBD tetap tersambung.
-- Ditolak bila komponen tujuan sudah punya material + dimension yang sama di revisi itu (aturan sama dengan tambah baris).
CREATE OR REPLACE FUNCTION fn_bom_change_component(p_token text, p_line_id uuid, p_component_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
  v_comp  component%ROWTYPE;
  v_n     integer;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Line not found or no longer active. Please reload the page.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  IF v_line.parent_line_key IS NOT NULL THEN
    RAISE EXCEPTION 'A subcomponent moves together with its main line. Change the component of the main line.';
  END IF;
  SELECT * INTO v_comp FROM component WHERE id = p_component_id;
  IF NOT FOUND OR v_comp.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Master component not found or INACTIVE.';
  END IF;
  IF v_line.component_id = p_component_id THEN
    RAISE EXCEPTION 'This line already uses component %.', v_comp.number;
  END IF;
  IF EXISTS (SELECT 1 FROM bom_line WHERE revision_id = v_line.revision_id AND is_active AND parent_line_key IS NULL
                                      AND id <> v_line.id AND component_id = p_component_id
                                      AND material_id = v_line.material_id AND thickness IS NOT DISTINCT FROM v_line.thickness) THEN
    RAISE EXCEPTION 'Component % - % already has this material with the same dimension in this revision.', v_comp.number, v_comp.name;
  END IF;
  WITH RECURSIVE chain AS (
    SELECT id, replaces_line_key FROM bom_line WHERE id = v_line.id
    UNION ALL
    SELECT b.id, b.replaces_line_key
      FROM bom_line b JOIN chain c ON b.revision_id = v_line.revision_id AND b.line_key = c.replaces_line_key AND NOT b.is_active
  )
  UPDATE bom_line
     SET component_id = p_component_id, local_component_no = NULL, local_component_name = NULL, updated_by = v_email
   WHERE id IN (SELECT id FROM chain);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- fn_model_save: R16 + semua field wajib (R19)
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
  -- R19 (keputusan user 26 Okt 2026): semua field model wajib (model lama yang belum lengkap dilengkapi saat Edit)
  IF p_gender_id IS NULL THEN
    RAISE EXCEPTION 'Gender is required.';
  END IF;
  IF p_construction_id IS NULL THEN
    RAISE EXCEPTION 'Construction is required.';
  END IF;
  IF p_last_id IS NULL THEN
    RAISE EXCEPTION 'Last No. is required.';
  END IF;
  IF p_outsole_mold_id IS NULL THEN
    RAISE EXCEPTION 'Outsole Mould is required.';
  END IF;
  IF (CASE WHEN jsonb_typeof(p_sizes) = 'array' THEN jsonb_array_length(p_sizes) = 0 ELSE true END) THEN
    RAISE EXCEPTION 'Select at least one size.';
  END IF;
  IF p_sample_size IS NULL THEN
    RAISE EXCEPTION 'Sample Size is required.';
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

SELECT 'R19: article tanpa nomor ' || (SELECT count(*) FROM article WHERE code IS NULL)
       || ', material Process ' || (SELECT count(*) FROM material WHERE is_process) AS cek_r19;

COMMIT;
