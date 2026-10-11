-- ============================================================================
-- R5 — CBD per varian, PO SMS, selling price keluar dari CBD (keputusan user 8 Okt 2026, PLAN.md §6 R5)
-- Bagian dari sql/R_revisi_semua.sql (urutan R3 -> R7). Aman diulang. Satu transaksi.
--
-- Aturan:
-- - Baris CBD membawa varian (Material Code) + thickness dari sel specsheet. Harga master dicari per
--   VARIAN + SUPPLIER (fn_price_lookup R3: hanya APPROVED dari supplier & link ACTIVE).
-- - Status harga baris: Belum ada harga / Menunggu persetujuan. CBD TIDAK BISA TERBIT selama ada baris yang
--   varian + suppliernya masih punya usulan harga menunggu persetujuan Manager Costing.
-- - Harga quotation ikut copy / revisi berikutnya / refresh bila VARIAN SAMA. Sinkron specsheet membandingkan
--   (baris, supplier, varian).
-- - PO SMS = Actual FOB × faktor stage (stage_setting, seed SMS = 1,25); faktor dibekukan di cbd_revision.po_factor
--   saat terbit. Target FOB tetap dibanding Actual FOB TANPA faktor.
-- - Selling price & Margin DIHAPUS dari CBD (Brand memakai kalkulator simulasi di layar, tidak disimpan).
-- - Semua tulis CBD dicek pabriknya (fn_auth_in). Manager Costing hanya membaca (tidak punya edit_cbd).
-- - Kolom lama dihapus: material.material_code, material.thickness, material_price.color/color_key,
--   fn_price_lookup versi warna.
-- ============================================================================

-- ---------------------------------------------------------------- Pengaman
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'bom_cell' AND column_name = 'variant_id') THEN
    RAISE EXCEPTION 'Bagian R4 belum dijalankan. Jalankan file revisi dari awal.';
  END IF;
  IF to_regclass('public.stage_setting') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'stage_setting' AND column_name = 'po_factor') THEN
    RAISE EXCEPTION 'Tabel "stage_setting" sudah ada di database dan bukan milik proyek ini. Hentikan dan hubungi pengembang.';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'cbd_revision' AND column_name = 'selling_price')
     AND EXISTS (SELECT 1 FROM cbd_revision) THEN
    RAISE EXCEPTION 'Masih ada CBD uji dari sebelum R5. Jalankan RESET_data_bisnis.sql dulu (user & pabrik tetap tersimpan).';
  END IF;
END;
$$;

-- View CBD yang dibuat ulang di bawah (urutan: yang bergantung dulu)
DROP VIEW IF EXISTS v_worklist_cbd, v_cbd_checklist, v_cbd_recap, v_cbd_price_check, v_cbd_line;

-- ---------------------------------------------------------------- Kolom
ALTER TABLE cbd_line
  ADD COLUMN IF NOT EXISTS variant_id uuid REFERENCES material_variant(id),
  ADD COLUMN IF NOT EXISTS thickness  text;
ALTER TABLE cbd_revision DROP COLUMN IF EXISTS selling_price;
ALTER TABLE cbd_revision ADD COLUMN IF NOT EXISTS po_factor numeric(6,4);    -- dibekukan saat terbit

CREATE TABLE IF NOT EXISTS stage_setting (
  stage     text PRIMARY KEY CHECK (stage IN ('PULL', 'SMS', 'GTM', 'PROD')),
  po_factor numeric(6,4) CHECK (po_factor IS NULL OR po_factor > 0),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text
);
SELECT fn_setup_table('stage_setting');
INSERT INTO stage_setting (stage, po_factor) VALUES ('PULL', NULL), ('SMS', 1.25), ('GTM', NULL), ('PROD', NULL)
ON CONFLICT (stage) DO NOTHING;

-- Kolom material lama (kode & thickness pindah ke varian sejak R2)
ALTER TABLE material DROP COLUMN IF EXISTS thickness_key;
ALTER TABLE material DROP COLUMN IF EXISTS thickness;
ALTER TABLE material DROP COLUMN IF EXISTS material_code;
CREATE OR REPLACE FUNCTION fn_material_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other record;
BEGIN
  NEW.name     := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  NEW.category := btrim(regexp_replace(coalesce(NEW.category, ''), '\s+', ' ', 'g'));
  NEW.uom      := upper(btrim(coalesce(NEW.uom, '')));
  IF NEW.factory_id IS NULL THEN RAISE EXCEPTION 'Pabrik material wajib diisi.'; END IF;
  IF NEW.name = ''          THEN RAISE EXCEPTION 'Nama material wajib diisi.'; END IF;
  IF NEW.category = ''      THEN RAISE EXCEPTION 'Kategori material wajib diisi.'; END IF;
  IF NEW.uom = ''           THEN RAISE EXCEPTION 'UoM wajib diisi.'; END IF;
  IF TG_OP = 'UPDATE' AND NEW.factory_id IS DISTINCT FROM OLD.factory_id THEN
    RAISE EXCEPTION 'Pabrik material tidak bisa diubah.';
  END IF;
  SELECT name, uom INTO v_other FROM material
   WHERE factory_id = NEW.factory_id AND name_key = fn_normalize(NEW.name) AND uom = NEW.uom AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material "%" (%) sudah ada di pabrik ini. Tambahkan varian di material itu.', v_other.name, v_other.uom;
  END IF;
  RETURN NEW;
END;
$$;

-- Harga per warna (F3) sudah tidak dipakai
DROP FUNCTION IF EXISTS fn_price_lookup(uuid, uuid, text, date);
ALTER TABLE material_price DROP COLUMN IF EXISTS color_key;
ALTER TABLE material_price DROP COLUMN IF EXISTS color;

-- ---------------------------------------------------------------- Helper
CREATE OR REPLACE FUNCTION fn_cbd_factory(p_cbd_revision_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT fn_article_factory(article_id) FROM cbd_revision WHERE id = p_cbd_revision_id $$;

CREATE OR REPLACE FUNCTION fn_cbd_line_factory(p_line_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT fn_cbd_factory(cbd_revision_id) FROM cbd_line WHERE id = p_line_id $$;

CREATE OR REPLACE FUNCTION fn_cbd_item_factory(p_item_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT fn_cbd_factory(cbd_revision_id) FROM cbd_cost_item WHERE id = p_item_id $$;

-- true = varian + supplier masih punya usulan harga menunggu persetujuan
CREATE OR REPLACE FUNCTION fn_price_pending(p_variant_id uuid, p_supplier_id uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM material_price mp JOIN material_supplier ms ON ms.id = mp.material_supplier_id
                  WHERE mp.variant_id = p_variant_id AND ms.supplier_id = p_supplier_id AND mp.status = 'PROPOSED')
$$;

-- Identitas baris untuk pencocokan copy/refresh: komponen + sub + material induk + thickness
DROP FUNCTION IF EXISTS fn_cbd_identity(uuid, integer, integer, text, uuid);
CREATE OR REPLACE FUNCTION fn_cbd_identity(p_component_id uuid, p_local_no integer, p_sub_seq integer,
                                           p_sub_name text, p_material_id uuid, p_thickness text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT concat_ws('|', coalesce(p_component_id::text, ''), coalesce(p_local_no::text, ''),
                   CASE WHEN p_sub_seq IS NOT NULL THEN fn_normalize(p_sub_name) ELSE '' END, p_material_id::text,
                   fn_normalize(coalesce(p_thickness, '')))
$$;

-- Varian dipakai dokumen terbit: specsheet (R4) atau CBD
CREATE OR REPLACE FUNCTION fn_variant_used_published(p_variant_id uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM bom_cell bc
                   JOIN bom_line l ON l.id = bc.bom_line_id
                   JOIN specsheet_revision r ON r.id = l.revision_id
                  WHERE bc.variant_id = p_variant_id AND r.status = 'PUBLISHED')
      OR EXISTS (SELECT 1 FROM cbd_line cl JOIN cbd_revision c ON c.id = cl.cbd_revision_id
                  WHERE cl.variant_id = p_variant_id AND c.status = 'PUBLISHED')
$$;

-- ---------------------------------------------------------------- Baris yang diharapkan (+ thickness, varian)
DROP FUNCTION IF EXISTS fn_cbd_expected_lines(uuid, uuid);
CREATE FUNCTION fn_cbd_expected_lines(p_article_id uuid, p_spec_rev_id uuid)
RETURNS TABLE (seq integer, line_key uuid, origin_line_key uuid, replaces_line_key uuid, component_id uuid,
               local_component_no integer, sub_seq integer, sub_name text, material_id uuid, thickness text,
               color text, variant_id uuid, supplier_id uuid, uom text, group_code text)
LANGUAGE sql STABLE AS $$
  WITH lines AS (
    SELECT l.*, c.number AS comp_no
      FROM bom_line l LEFT JOIN component c ON c.id = l.component_id
     WHERE l.revision_id = p_spec_rev_id AND l.is_active
  ), x AS (
    SELECT l.line_key, l.origin_line_key, l.replaces_line_key,
           CASE WHEN l.parent_line_key IS NULL THEN l.component_id ELSE p.component_id END AS component_id,
           CASE WHEN l.parent_line_key IS NULL THEN l.local_component_no ELSE p.local_component_no END AS local_no,
           CASE WHEN l.parent_line_key IS NULL THEN coalesce(l.comp_no, l.local_component_no)
                ELSE coalesce(p.comp_no, p.local_component_no) END AS top_no,
           CASE WHEN l.parent_line_key IS NULL THEN l.sort_order ELSE coalesce(p.sort_order, l.sort_order) END AS top_sort,
           l.parent_line_key IS NOT NULL AS is_sub,
           l.sub_seq, l.sub_name, l.material_id, l.thickness, bc.color, bc.variant_id, l.supplier_id, m.uom
      FROM lines l
      LEFT JOIN lines p ON p.line_key = l.parent_line_key
      JOIN bom_cell bc ON bc.bom_line_id = l.id AND bc.article_id = p_article_id AND bc.is_used
      JOIN material m ON m.id = l.material_id
     WHERE EXISTS (SELECT 1 FROM revision_article ra
                    WHERE ra.revision_id = p_spec_rev_id AND ra.article_id = p_article_id AND ra.status = 'ACTIVE')
  )
  SELECT (row_number() OVER (ORDER BY x.top_no NULLS LAST, x.top_sort, x.is_sub, x.sub_seq))::integer,
         x.line_key, x.origin_line_key, x.replaces_line_key, x.component_id, x.local_no, x.sub_seq,
         CASE WHEN x.is_sub THEN x.sub_name END, x.material_id, x.thickness, x.color, x.variant_id, x.supplier_id,
         x.uom, fn_cbd_group_code(x.component_id, x.local_no)
    FROM x
$$;

-- ---------------------------------------------------------------- Isi baris CBD dari specsheet (+ sumber)
CREATE OR REPLACE FUNCTION fn_cbd_populate(p_revision_id uuid, p_article_id uuid, p_spec_rev_id uuid,
                                           p_src cbd_line[], p_mark_missing boolean, p_ref text, p_email text)
RETURNS integer
LANGUAGE plpgsql AS $$
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
  v_pid     uuid;
  v_price   numeric;
  v_cur     text;
BEGIN
  FOR e IN SELECT * FROM fn_cbd_expected_lines(p_article_id, p_spec_rev_id) ORDER BY seq LOOP
    v_found := false;
    v_yield := NULL; v_loss := NULL; v_origin := 'INPUT'; v_ref := NULL; v_carry := false;
    IF v_has_src THEN
      SELECT * INTO s FROM unnest(p_src) x WHERE x.line_key = e.line_key
         AND NOT (x.line_key = ANY (v_matched)) LIMIT 1;
      v_found := FOUND;
      IF NOT v_found AND e.origin_line_key IS NOT NULL THEN
        SELECT * INTO s FROM unnest(p_src) x WHERE x.line_key = e.origin_line_key
           AND NOT (x.line_key = ANY (v_matched)) LIMIT 1;
        v_found := FOUND;
      END IF;
      IF NOT v_found THEN
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
        -- harga quotation ikut bila VARIAN sama dan materialnya masih bermetode Quotation
        v_carry := s.price_source = 'QUOTATION' AND s.variant_id IS NOT DISTINCT FROM e.variant_id
                   AND EXISTS (SELECT 1 FROM material WHERE id = e.material_id AND price_method = 'QUOTATION');
      ELSIF e.replaces_line_key IS NOT NULL THEN
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
                            price_reference, status, value_origin, value_source_ref, sort_order, updated_by)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.thickness, e.color, e.variant_id, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              s.price_original, s.currency, s.price_source, NULL, NULL,
              s.price_reference, 'ACTIVE', v_origin, v_ref, v_sort, p_email);
    ELSE
      v_pid := NULL; v_price := NULL; v_cur := NULL;
      IF e.supplier_id IS NOT NULL AND e.variant_id IS NOT NULL THEN
        SELECT price_id, price, currency INTO v_pid, v_price, v_cur
          FROM fn_price_lookup(e.variant_id, e.supplier_id);
      END IF;
      INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                            material_id, thickness, color, variant_id, supplier_id, uom, group_code, yield_value, loss_pct,
                            price_original, currency, price_source, material_price_id,
                            status, value_origin, value_source_ref, sort_order, updated_by)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.thickness, e.color, e.variant_id, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              v_price, v_cur, CASE WHEN v_pid IS NOT NULL THEN 'MASTER' END, v_pid,
              'ACTIVE', v_origin, v_ref, v_sort, p_email);
    END IF;
    v_sort := v_sort + 1;
  END LOOP;

  IF p_mark_missing AND v_has_src THEN
    INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                          material_id, thickness, color, variant_id, supplier_id, uom, group_code, yield_value, loss_pct,
                          price_original, currency, price_source, material_price_id, price_override_reason,
                          price_reference, status, value_origin, value_source_ref, sort_order, updated_by)
    SELECT p_revision_id, x.line_key, x.component_id, x.local_component_no, x.sub_seq, x.sub_name,
           x.material_id, x.thickness, x.color, x.variant_id, x.supplier_id, x.uom, x.group_code, x.yield_value, x.loss_pct,
           x.price_original, x.currency, x.price_source, x.material_price_id, x.price_override_reason,
           x.price_reference, 'MISSING_IN_SPEC', x.value_origin, x.value_source_ref,
           v_sort + (row_number() OVER (ORDER BY x.sort_order))::integer, p_email
      FROM unnest(p_src) x
     WHERE NOT (x.line_key = ANY (v_matched));
  END IF;
  RETURN v_sort;
END;
$$;

-- ---------------------------------------------------------------- Buat / hapus revisi CBD
CREATE OR REPLACE FUNCTION fn_cbd_create(p_token text, p_article_id uuid, p_mode text, p_source_article_id uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_article_factory(p_article_id));
  v_art    article%ROWTYPE;
  v_srcart article%ROWTYPE;
  v_spec   specsheet_revision%ROWTYPE;
  v_src    cbd_revision%ROWTYPE;
  v_lines  cbd_line[];
  v_status text;
  v_no     integer;
  v_ref    text;
  v_id     uuid;
BEGIN
  SELECT * INTO v_art FROM article WHERE id = p_article_id FOR UPDATE;   -- antre per article
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Article tidak ditemukan.';
  END IF;
  v_status := fn_cbd_article_spec_status(v_art.id);
  IF v_status = 'DROPPED' THEN
    RAISE EXCEPTION 'Article % sudah di-drop di specsheet terbit terakhir — CBD-nya tidak bisa dibuat lagi.', v_art.code;
  ELSIF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article % belum ada di revisi specsheet yang terbit. Terbitkan specsheet-nya dulu.', v_art.code;
  END IF;
  IF EXISTS (SELECT 1 FROM cbd_revision WHERE article_id = v_art.id AND status = 'DRAFT') THEN
    RAISE EXCEPTION 'Sudah ada CBD DRAFT untuk article %. Terbitkan atau hapus draft itu dulu.', v_art.code;
  END IF;
  SELECT * INTO v_spec FROM specsheet_revision WHERE id = fn_spec_latest_pub(v_art.specsheet_id);

  IF p_mode IN ('NEW', 'COPY') THEN
    IF EXISTS (SELECT 1 FROM cbd_revision WHERE article_id = v_art.id) THEN
      RAISE EXCEPTION 'Article % sudah punya CBD. Pakai Revisi berikutnya.', v_art.code;
    END IF;
    IF p_mode = 'COPY' THEN
      SELECT * INTO v_srcart FROM article WHERE id = p_source_article_id;
      IF NOT FOUND OR v_srcart.id = v_art.id THEN
        RAISE EXCEPTION 'Pilih article sumber.';
      END IF;
      IF (SELECT model_id FROM specsheet WHERE id = v_srcart.specsheet_id)
         IS DISTINCT FROM (SELECT model_id FROM specsheet WHERE id = v_art.specsheet_id) THEN
        RAISE EXCEPTION 'CBD hanya bisa di-copy dari article model yang sama.';
      END IF;
      SELECT * INTO v_src FROM cbd_revision
       WHERE article_id = v_srcart.id AND status = 'PUBLISHED'
       ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Article % belum punya CBD terbit untuk di-copy.', v_srcart.code;
      END IF;
    END IF;
  ELSIF p_mode = 'NEXT' THEN
    SELECT * INTO v_src FROM cbd_revision
     WHERE article_id = v_art.id AND status = 'PUBLISHED'
     ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Article % belum punya CBD terbit.', v_art.code;
    END IF;
  ELSE
    RAISE EXCEPTION 'Pilih cara membuat CBD.';
  END IF;

  SELECT coalesce(max(revision_no) + 1, 0) INTO v_no
    FROM cbd_revision WHERE article_id = v_art.id AND stage = v_spec.stage;

  -- Rekap (rate, target FOB) ikut dari sumber
  INSERT INTO cbd_revision (article_id, stage, revision_no, specsheet_revision_id, exchange_rate,
                            target_fob, source_cbd_revision_id, updated_by)
  VALUES (v_art.id, v_spec.stage, v_no, v_spec.id, v_src.exchange_rate,
          v_src.target_fob, v_src.id, v_email)
  RETURNING id INTO v_id;

  IF v_src.id IS NOT NULL THEN
    SELECT sp.season || ' / ' || a.code || ' / ' || v_src.stage || ' r' || v_src.revision_no INTO v_ref
      FROM article a JOIN specsheet sp ON sp.id = a.specsheet_id WHERE a.id = v_src.article_id;
    SELECT array_agg(l ORDER BY l.sort_order) INTO v_lines FROM cbd_line l WHERE l.cbd_revision_id = v_src.id;
    INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, remarks, is_default, sort_order, updated_by)
    SELECT v_id, c.item_type, c.name, c.amount, c.remarks, c.is_default, c.sort_order, v_email
      FROM cbd_cost_item c WHERE c.cbd_revision_id = v_src.id;
  END IF;
  PERFORM fn_cbd_cost_defaults(v_id, v_email);
  PERFORM fn_cbd_populate(v_id, v_art.id, v_spec.id, v_lines, p_mode = 'NEXT', v_ref, v_email);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_delete_draft(p_token text, p_cbd_revision_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev   cbd_revision%ROWTYPE;
BEGIN
  SELECT * INTO v_rev FROM cbd_revision WHERE id = p_cbd_revision_id FOR UPDATE;
  IF v_rev.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'Revisi CBD ini sudah diterbitkan dan tidak bisa dihapus.';
  END IF;
  DELETE FROM cbd_revision WHERE id = v_rev.id;
  RETURN v_rev.id;
END;
$$;

-- ---------------------------------------------------------------- Ubah baris / harga / biaya / rekap
CREATE OR REPLACE FUNCTION fn_cbd_line_set(p_token text, p_line_id uuid, p_field text, p_value numeric)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_line_factory(p_line_id));
  v_line  cbd_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM cbd_line WHERE id = p_line_id;
  PERFORM fn_cbd_draft(v_line.cbd_revision_id);
  IF v_line.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Baris ini sudah tidak ada di specsheet (MISSING_IN_SPEC) dan tidak bisa diubah.';
  END IF;
  IF p_field = 'YIELD' THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION 'Yield harus lebih besar dari 0.';
    END IF;
    UPDATE cbd_line SET yield_value = p_value, value_origin = 'INPUT', updated_by = v_email WHERE id = v_line.id;
  ELSIF p_field = 'LOSS' THEN
    IF p_value < 0 OR p_value >= 100 THEN
      RAISE EXCEPTION 'Loss %% harus 0 sampai kurang dari 100 (kosong = 0).';
    END IF;
    UPDATE cbd_line SET loss_pct = p_value, value_origin = 'INPUT', updated_by = v_email WHERE id = v_line.id;
  ELSE
    RAISE EXCEPTION 'Kolom tidak valid.';
  END IF;
  RETURN v_line.id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_set_quotation(p_token text, p_line_id uuid, p_price numeric,
                                                p_currency text, p_reference text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_line_factory(p_line_id));
  v_line  cbd_line%ROWTYPE := fn_cbd_price_line(p_line_id);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM material WHERE id = v_line.material_id AND price_method = 'QUOTATION') THEN
    RAISE EXCEPTION 'Harga quotation hanya untuk material dengan metode harga Quotation. Material katalog memakai harga master.';
  END IF;
  IF p_price IS NULL THEN
    UPDATE cbd_line SET price_original = NULL, currency = NULL, price_source = NULL, material_price_id = NULL,
                        price_override_reason = NULL, price_reference = NULL, updated_by = v_email
     WHERE id = v_line.id;
  ELSE
    PERFORM fn_cbd_check_price(p_price, p_currency);
    UPDATE cbd_line SET price_original = p_price, currency = p_currency, price_source = 'QUOTATION',
                        material_price_id = NULL, price_override_reason = NULL,
                        price_reference = nullif(btrim(coalesce(p_reference, '')), ''), updated_by = v_email
     WHERE id = v_line.id;
  END IF;
  RETURN v_line.id;
END;
$$;

-- Override CATALOG sudah dihapus (F10b) — fungsi lama dipertahankan agar query lama memberi pesan jelas
CREATE OR REPLACE FUNCTION fn_cbd_clear_override(p_token text, p_line_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Override harga tidak dipakai lagi. Harga material katalog diisi lewat Master Material.';
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_header_set(p_token text, p_cbd_revision_id uuid, p_field text, p_value numeric)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev   cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
BEGIN
  IF p_field = 'RATE' THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION 'Exchange rate harus lebih besar dari 0 (kosongkan kalau belum ada).';
    END IF;
    UPDATE cbd_revision SET exchange_rate = p_value, updated_by = v_email WHERE id = v_rev.id;
  ELSIF p_field = 'TARGET_FOB' THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION 'Target FOB harus lebih besar dari 0 (kosongkan kalau belum ada).';
    END IF;
    UPDATE cbd_revision SET target_fob = p_value, updated_by = v_email WHERE id = v_rev.id;
  ELSE
    RAISE EXCEPTION 'Kolom tidak valid (selling price & margin tidak disimpan di CBD).';
  END IF;
  RETURN v_rev.id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_cost_add(p_token text, p_cbd_revision_id uuid, p_type text, p_name text,
                                           p_amount numeric, p_remarks text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev   cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
  v_id    uuid;
BEGIN
  IF coalesce(p_type, '') NOT IN ('LABOUR', 'AMORTIZATION', 'ADJUSTMENT', 'OTHER') THEN
    RAISE EXCEPTION 'Pilih jenis biaya.';
  END IF;
  PERFORM fn_cbd_check_cost(p_type, p_amount);
  INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, remarks, is_default, sort_order, updated_by)
  VALUES (v_rev.id, p_type, coalesce(nullif(btrim(coalesce(p_name, '')), ''), fn_cbd_cost_label(p_type)),
          coalesce(p_amount, 0), nullif(btrim(coalesce(p_remarks, '')), ''), false,
          (SELECT coalesce(max(sort_order), 0) + 1 FROM cbd_cost_item WHERE cbd_revision_id = v_rev.id), v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_cost_set(p_token text, p_item_id uuid, p_field text, p_value text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_item_factory(p_item_id));
  v_item  cbd_cost_item%ROWTYPE := fn_cbd_cost_item(p_item_id);
  v_text  text := nullif(btrim(coalesce(p_value, '')), '');
  v_num   numeric;
BEGIN
  IF p_field = 'NAME' THEN
    IF v_text IS NULL THEN
      RAISE EXCEPTION 'Uraian biaya wajib diisi.';
    END IF;
    UPDATE cbd_cost_item SET name = v_text, updated_by = v_email WHERE id = v_item.id;
  ELSIF p_field = 'AMOUNT' THEN
    IF v_text IS NOT NULL AND v_text !~ '^-?[0-9]+(\.[0-9]+)?$' THEN
      RAISE EXCEPTION 'Nilai biaya harus angka.';
    END IF;
    v_num := coalesce(v_text::numeric, 0);
    PERFORM fn_cbd_check_cost(v_item.item_type, v_num);
    UPDATE cbd_cost_item SET amount = v_num, updated_by = v_email WHERE id = v_item.id;
  ELSIF p_field = 'REMARKS' THEN
    UPDATE cbd_cost_item SET remarks = v_text, updated_by = v_email WHERE id = v_item.id;
  ELSE
    RAISE EXCEPTION 'Kolom tidak valid.';
  END IF;
  RETURN v_item.id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_cost_delete(p_token text, p_item_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_item_factory(p_item_id));
  v_item  cbd_cost_item%ROWTYPE := fn_cbd_cost_item(p_item_id);
BEGIN
  IF v_item.is_default THEN
    RAISE EXCEPTION 'Baris % selalu ada dan tidak bisa dihapus (isi 0 bila tidak dipakai).', v_item.name;
  END IF;
  DELETE FROM cbd_cost_item WHERE id = v_item.id;
  RETURN v_item.id;
END;
$$;

-- ---------------------------------------------------------------- View baris, cek harga, rekap, checklist
CREATE VIEW v_cbd_line AS
SELECT cl.id, cl.cbd_revision_id, cl.line_key, cl.status, cl.group_code, g.name AS group_name, g.sort_order AS group_sort,
       coalesce(c.number, cl.local_component_no) AS comp_no,
       CASE WHEN cl.sub_seq IS NOT NULL
            THEN coalesce(coalesce(c.number, cl.local_component_no)::text || '-', '') || cl.sub_seq
            ELSE coalesce(c.number, cl.local_component_no)::text END AS display_no,
       CASE WHEN cl.sub_seq IS NOT NULL THEN coalesce(cl.sub_name, m.name)
            ELSE coalesce(c.name, bl.local_component_name, 'Lokal ' || cl.local_component_no, m.name) END AS display_name,
       (cl.sub_seq IS NOT NULL) AS is_sub,
       (cl.component_id IS NULL AND cl.sub_seq IS NULL) AS is_local,
       cl.material_id, v.code AS material_code, m.name AS material_name, cl.thickness, m.price_method,
       cl.color, cl.supplier_id, s.name AS supplier_name, cl.uom, bl.process AS remarks,
       cl.yield_value, cl.usage_value, cl.loss_pct,
       cl.price_original, cl.currency, cl.price_source, cl.material_price_id,
       NULL::text AS master_price_color, mp.valid_from AS master_price_valid_from,
       cl.price_override_reason, cl.price_reference,
       x.price_usd, x.price_idr,
       cl.usage_value * x.price_idr * (1 + coalesce(cl.loss_pct, 0) / 100) AS cost_per_pair,
       cl.value_origin, cl.value_source_ref, cl.sort_order,
       cl.variant_id
  FROM cbd_line cl
  JOIN cbd_revision cr ON cr.id = cl.cbd_revision_id
  JOIN material m ON m.id = cl.material_id
  LEFT JOIN material_variant v ON v.id = cl.variant_id
  LEFT JOIN component c ON c.id = cl.component_id
  LEFT JOIN component_group g ON g.code = cl.group_code
  LEFT JOIN supplier s ON s.id = cl.supplier_id
  LEFT JOIN material_price mp ON mp.id = cl.material_price_id
  LEFT JOIN bom_line bl ON bl.revision_id = cr.specsheet_revision_id AND bl.line_key = cl.line_key
  CROSS JOIN LATERAL (
    SELECT CASE cl.currency WHEN 'IDR' THEN cl.price_original
                            WHEN 'USD' THEN cl.price_original * cr.exchange_rate END AS price_idr,
           CASE cl.currency WHEN 'USD' THEN cl.price_original
                            WHEN 'IDR' THEN cl.price_original / nullif(cr.exchange_rate, 0) END AS price_usd
  ) x;

-- Hanya revisi DRAFT, baris ACTIVE. price_gap = kenapa harga kosong; pending = ada usulan harga menunggu
-- untuk varian + supplier baris ini (memblokir terbit).
CREATE VIEW v_cbd_price_check AS
SELECT l.id AS line_id, l.cbd_revision_id,
       cur.price_id AS master_price_id, cur.price AS master_price, cur.currency AS master_currency,
       CASE WHEN l.price_source = 'QUOTATION' THEN m.price_method = 'CATALOG'
            WHEN m.price_method = 'QUOTATION' THEN l.price_source = 'MASTER'
            ELSE cur.price_id IS DISTINCT FROM l.material_price_id END AS master_stale,
       CASE WHEN l.price_original IS NOT NULL THEN NULL
            WHEN m.price_method = 'QUOTATION' THEN 'QUOTATION'
            WHEN l.supplier_id IS NULL THEN 'NO_SUPPLIER'
            WHEN cur.price_id IS NOT NULL THEN 'AVAILABLE'
            WHEN pend.pending THEN 'PENDING'
            ELSE 'NO_PRICE' END AS price_gap,
       NULL::text AS other_colors,
       (m.price_method = 'CATALOG' AND pend.pending) AS pending
  FROM cbd_line l
  JOIN cbd_revision r ON r.id = l.cbd_revision_id
  JOIN material m ON m.id = l.material_id
  LEFT JOIN LATERAL fn_price_lookup(l.variant_id, l.supplier_id) cur ON true
  CROSS JOIN LATERAL (SELECT coalesce(fn_price_pending(l.variant_id, l.supplier_id), false) AS pending) pend
 WHERE r.status = 'DRAFT' AND l.status = 'ACTIVE';

-- po_factor: revisi terbit = faktor yang dibekukan; draft = faktor stage sekarang (stage_setting)
CREATE VIEW v_cbd_recap AS
SELECT r.id AS cbd_revision_id, r.status, r.exchange_rate, r.target_fob,
       t.material_cost, ci.labour, ci.amortization, ci.adjustment, ci.other, ci.items_total,
       f.actual_fob,
       f.actual_fob - r.target_fob AS variance,
       CASE WHEN r.target_fob IS NULL THEN NULL
            WHEN f.actual_fob > r.target_fob THEN 'OVER'
            WHEN f.actual_fob < r.target_fob THEN 'UNDER'
            ELSE 'SESUAI' END AS variance_label,
       t.line_count, t.unpriced_count, t.no_yield_count, t.usd_no_rate_count, t.missing_count,
       coalesce(gc.group_costs, '{}'::jsonb) AS group_costs,
       r.stage, pf.po_factor, round(f.actual_fob * pf.po_factor, 2) AS po_price
  FROM cbd_revision r
  CROSS JOIN LATERAL (
    SELECT coalesce(sum(v.cost_per_pair) FILTER (WHERE v.status = 'ACTIVE'), 0) AS material_cost,
           count(*) FILTER (WHERE v.status = 'ACTIVE')::int AS line_count,
           count(*) FILTER (WHERE v.status = 'ACTIVE' AND v.price_original IS NULL)::int AS unpriced_count,
           count(*) FILTER (WHERE v.status = 'ACTIVE' AND v.price_original IS NOT NULL
                              AND v.yield_value IS NULL)::int AS no_yield_count,
           count(*) FILTER (WHERE v.status = 'ACTIVE' AND v.currency = 'USD' AND v.price_idr IS NULL)::int AS usd_no_rate_count,
           count(*) FILTER (WHERE v.status = 'MISSING_IN_SPEC')::int AS missing_count
      FROM v_cbd_line v WHERE v.cbd_revision_id = r.id
  ) t
  CROSS JOIN LATERAL (
    SELECT coalesce(sum(c.amount) FILTER (WHERE c.item_type = 'LABOUR'), 0) AS labour,
           coalesce(sum(c.amount) FILTER (WHERE c.item_type = 'AMORTIZATION'), 0) AS amortization,
           coalesce(sum(c.amount) FILTER (WHERE c.item_type = 'ADJUSTMENT'), 0) AS adjustment,
           coalesce(sum(c.amount) FILTER (WHERE c.item_type = 'OTHER'), 0) AS other,
           coalesce(sum(c.amount), 0) AS items_total
      FROM cbd_cost_item c WHERE c.cbd_revision_id = r.id
  ) ci
  CROSS JOIN LATERAL (
    SELECT jsonb_object_agg(x.group_code, x.cost) AS group_costs
      FROM (SELECT v.group_code, coalesce(sum(v.cost_per_pair), 0) AS cost
              FROM v_cbd_line v WHERE v.cbd_revision_id = r.id AND v.status = 'ACTIVE'
             GROUP BY v.group_code) x
  ) gc
  CROSS JOIN LATERAL (SELECT t.material_cost + ci.items_total AS actual_fob) f
  CROSS JOIN LATERAL (
    SELECT CASE WHEN r.status = 'PUBLISHED' THEN r.po_factor
                ELSE (SELECT s.po_factor FROM stage_setting s WHERE s.stage = r.stage) END AS po_factor
  ) pf;

CREATE VIEW v_cbd_checklist AS
SELECT x.*,
       (x.spec_status <> 'ACTIVE' OR x.spec_stale OR NOT x.rate_ok OR x.stale_prices > 0 OR x.no_yield_count > 0
        OR x.pending_prices > 0) AS blocked
  FROM (
    SELECT r.id AS cbd_revision_id, r.article_id, r.stage, r.revision_no, r.status,
           EXISTS (SELECT 1 FROM cbd_revision o
                    WHERE o.article_id = r.article_id AND o.status = 'PUBLISHED' AND o.id <> r.id) AS requires_reason,
           fn_cbd_article_spec_status(r.article_id) AS spec_status,
           (r.specsheet_revision_id IS DISTINCT FROM fn_spec_latest_pub(a.specsheet_id)) AS spec_stale,
           (r.exchange_rate IS NOT NULL) AS rate_ok,
           (SELECT count(*)::int FROM v_cbd_price_check pc
             WHERE pc.cbd_revision_id = r.id AND pc.master_stale) AS stale_prices,
           rc.no_yield_count, rc.unpriced_count, rc.line_count, rc.missing_count,
           (SELECT count(*)::int FROM v_cbd_price_check pc
             WHERE pc.cbd_revision_id = r.id AND pc.pending) AS pending_prices,
           (SELECT left(string_agg(DISTINCT v.material_code || ' · ' || v.supplier_name, ', '), 300)
              FROM v_cbd_price_check pc JOIN v_cbd_line v ON v.id = pc.line_id
             WHERE pc.cbd_revision_id = r.id AND pc.pending) AS pending_list
      FROM cbd_revision r
      JOIN article a ON a.id = r.article_id
      JOIN v_cbd_recap rc ON rc.cbd_revision_id = r.id
  ) x;

-- ---------------------------------------------------------------- Refresh, terbit, sinkron
CREATE OR REPLACE FUNCTION fn_cbd_refresh_prices(p_token text, p_cbd_revision_id uuid) RETURNS integer
LANGUAGE plpgsql AS $$
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
    RAISE EXCEPTION 'Harga semua baris sudah sama dengan master.';
  END IF;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_refresh_from_spec(p_token text, p_cbd_revision_id uuid) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev    cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);   -- dikunci, article ACTIVE
  v_spec   specsheet_revision%ROWTYPE;
  v_lines  cbd_line[];
  v_no     integer := v_rev.revision_no;
  v_n      integer;
BEGIN
  SELECT sr.* INTO v_spec FROM specsheet_revision sr
   WHERE sr.id = fn_spec_latest_pub((SELECT specsheet_id FROM article WHERE id = v_rev.article_id));
  IF v_spec.id = v_rev.specsheet_revision_id THEN
    RAISE EXCEPTION 'CBD ini sudah memakai specsheet terbit terakhir (% r%).', v_spec.stage, v_spec.revision_no;
  END IF;
  IF v_spec.stage <> v_rev.stage THEN
    SELECT coalesce(max(revision_no) + 1, 0) INTO v_no
      FROM cbd_revision WHERE article_id = v_rev.article_id AND stage = v_spec.stage;
  END IF;

  SELECT array_agg(l ORDER BY l.sort_order) INTO v_lines FROM cbd_line l WHERE l.cbd_revision_id = v_rev.id;
  DELETE FROM cbd_line WHERE cbd_revision_id = v_rev.id;
  UPDATE cbd_revision SET specsheet_revision_id = v_spec.id, stage = v_spec.stage, revision_no = v_no,
                          updated_by = v_email
   WHERE id = v_rev.id;
  v_n := fn_cbd_populate(v_rev.id, v_rev.article_id, v_spec.id, v_lines, true, NULL, v_email);
  PERFORM fn_audit(v_email, 'cbd_revision', v_rev.id::text, 'REFRESH_FROM_SPEC');
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_publish(p_token text, p_cbd_revision_id uuid, p_category text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev    cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
  v_chk    v_cbd_checklist%ROWTYPE;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_id     uuid;
BEGIN
  SELECT * INTO v_chk FROM v_cbd_checklist WHERE cbd_revision_id = v_rev.id;
  IF v_chk.spec_stale THEN
    RAISE EXCEPTION 'Specsheet acuan CBD ini sudah diterbitkan revisi baru. Klik "Refresh dari Specsheet" dulu.';
  END IF;
  IF NOT v_chk.rate_ok THEN
    RAISE EXCEPTION 'Isi exchange rate (lebih besar dari 0) di rekap dulu.';
  END IF;
  IF v_chk.pending_prices > 0 THEN
    RAISE EXCEPTION 'Ada % baris yang harganya menunggu persetujuan Manager Costing (%). Tunggu sampai diproses, lalu Refresh Harga.',
      v_chk.pending_prices, v_chk.pending_list;
  END IF;
  IF v_chk.stale_prices > 0 THEN
    RAISE EXCEPTION 'Harga master untuk % baris sudah berubah. Klik "Refresh Harga dari Master" dulu.', v_chk.stale_prices;
  END IF;
  IF v_chk.no_yield_count > 0 THEN
    RAISE EXCEPTION 'Ada % baris berharga yang belum diisi Yield.', v_chk.no_yield_count;
  END IF;
  IF coalesce(p_category, '') NOT IN ('EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER') THEN
    RAISE EXCEPTION 'Pilih kategori perubahan.';
  END IF;
  IF v_chk.requires_reason AND v_reason IS NULL THEN
    RAISE EXCEPTION 'Alasan perubahan wajib diisi untuk revisi ini.';
  END IF;

  UPDATE cbd_revision
     SET status = 'PUBLISHED', sync_status = 'IN_SYNC', published_at = now(), published_by = v_email,
         po_factor = (SELECT s.po_factor FROM stage_setting s WHERE s.stage = v_rev.stage),   -- dibekukan
         updated_by = v_email
   WHERE id = v_rev.id;

  INSERT INTO change_log (doc_type, revision_id, category, reason, created_by)
  VALUES ('CBD', v_rev.id, p_category, coalesce(v_reason, 'Revisi awal.'), v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Specsheet terbit: CBD terbit terakhir tiap article ditandai PERLU REVISI bila (baris, supplier, varian) berubah
CREATE OR REPLACE FUNCTION fn_cbd_sync_spec(p_spec_rev_id uuid, p_email text) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  c      record;
  v_same boolean;
  v_n    integer := 0;
BEGIN
  FOR c IN
    SELECT DISTINCT ON (cr.article_id) cr.id, cr.article_id, cr.specsheet_revision_id, cr.sync_status
      FROM cbd_revision cr
      JOIN revision_article ra ON ra.article_id = cr.article_id AND ra.revision_id = p_spec_rev_id
                              AND ra.status = 'ACTIVE'
     WHERE cr.status = 'PUBLISHED'
     ORDER BY cr.article_id, cr.stage_order DESC, cr.revision_no DESC
  LOOP
    CONTINUE WHEN c.specsheet_revision_id = p_spec_rev_id;
    SELECT NOT EXISTS (
             (SELECT line_key, supplier_id, variant_id FROM fn_cbd_expected_lines(c.article_id, c.specsheet_revision_id)
              EXCEPT
              SELECT line_key, supplier_id, variant_id FROM fn_cbd_expected_lines(c.article_id, p_spec_rev_id))
             UNION ALL
             (SELECT line_key, supplier_id, variant_id FROM fn_cbd_expected_lines(c.article_id, p_spec_rev_id)
              EXCEPT
              SELECT line_key, supplier_id, variant_id FROM fn_cbd_expected_lines(c.article_id, c.specsheet_revision_id)))
      INTO v_same;
    IF v_same THEN
      UPDATE cbd_revision SET specsheet_revision_id = p_spec_rev_id, sync_status = 'IN_SYNC', updated_by = p_email
       WHERE id = c.id;
    ELSIF c.sync_status <> 'NEEDS_REVISION' THEN
      UPDATE cbd_revision SET sync_status = 'NEEDS_REVISION', updated_by = p_email WHERE id = c.id;
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------- Worklist CBD (sama dengan R4, view dibuat ulang)
CREATE VIEW v_worklist_cbd AS
SELECT x.*
  FROM (
    SELECT CASE WHEN a.revision_count = 0 THEN 'TO_CREATE'
                WHEN a.draft_id IS NOT NULL
                     THEN CASE WHEN a.draft_stale OR pr.stale_prices > 0 THEN 'TO_REFRESH' ELSE 'IN_PROGRESS' END
                WHEN a.pub_sync = 'NEEDS_REVISION' THEN 'TO_REVISE' END AS kind,
           CASE WHEN a.draft_id IS NULL THEN NULL
                WHEN a.draft_stale THEN 'SPEC'
                WHEN pr.stale_prices > 0 THEN 'PRICE' END AS refresh_reason,
           a.id AS article_id, a.code AS article_code, a.colorway,
           pm.id AS model_id, pm.name AS model_name, pm.factory_id,
           a.specsheet_id, a.season,
           coalesce(a.draft_id, a.pub_id) AS cbd_revision_id,
           coalesce(a.draft_label, a.pub_label) AS rev_label,
           pr.pending_prices
      FROM v_cbd_article a
      JOIN product_model pm ON pm.id = a.model_id
      CROSS JOIN LATERAL (
        SELECT (count(*) FILTER (WHERE pc.master_stale))::integer AS stale_prices,
               (count(*) FILTER (WHERE pc.pending))::integer AS pending_prices
          FROM v_cbd_price_check pc
         WHERE pc.cbd_revision_id = a.draft_id
      ) pr
     WHERE a.spec_status = 'ACTIVE'
  ) x
 WHERE x.kind IS NOT NULL;

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'cbd_line.variant_id / thickness' AS cek,
       (SELECT count(*) FROM information_schema.columns WHERE table_name = 'cbd_line' AND column_name IN ('variant_id', 'thickness'))::text AS hasil
UNION ALL SELECT 'kolom lama dihapus (harus 0)', (SELECT count(*) FROM information_schema.columns
       WHERE (table_name = 'cbd_revision' AND column_name = 'selling_price')
          OR (table_name = 'material' AND column_name IN ('material_code', 'thickness'))
          OR (table_name = 'material_price' AND column_name IN ('color', 'color_key')))::text
UNION ALL SELECT 'stage_setting SMS', (SELECT po_factor::text FROM stage_setting WHERE stage = 'SMS')
UNION ALL SELECT 'fn_price_lookup (harus 1 versi)', count(*)::text FROM pg_proc WHERE proname = 'fn_price_lookup';
