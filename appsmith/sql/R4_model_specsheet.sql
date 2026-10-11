-- ============================================================================
-- R4 — Model tanpa kode + Specsheet per varian (keputusan user 8 Okt 2026, PLAN.md §2 "Revisi besar" & §6 R4)
-- Bagian dari sql/R_revisi_semua.sql (urutan R3 -> R7). Jalankan lewat z_run_sql di app "DB Tools"
-- (Use prepared statements = OFF) SETELAH RESET_data_bisnis.sql. Aman diulang. Satu transaksi.
--
-- Aturan:
-- - Model: kode DIHAPUS, nama = identitas (unik per pabrik, boleh diubah). Pabrik model = pabrik user pembuat.
--   Kategori (wajib), Construction, Gender = pilihan bersama; Last, Outsole mold = pilihan pabrik model.
--   Ukuran = daftar angka bulat (grid ala kalender), sample size salah satu ukuran itu.
-- - Semua tulis model / season / article / lampiran / specsheet dicek pabriknya (fn_auth_in).
-- - Baris BOM = material INDUK + thickness. Sel per article = WARNA; varian (Material Code) dicari otomatis dari
--   induk + thickness + warna (hanya varian ACTIVE). Sel berwarna tanpa varian = SEL KUNING.
--   Varian baru / berubah -> sel draft yang cocok tersambung otomatis. Sel kosong = tidak dipakai
--   ('none', '-', 'n/a' tidak istimewa lagi). Kode varian boleh diketik di sel (diganti warnanya).
-- - Terbit specsheet ditolak bila: tidak ada article aktif, article tanpa baris, material INACTIVE, baris tanpa
--   supplier, SEL KUNING, supplier / supplier material INACTIVE (F10d). Usulan master tidak ada lagi.
-- - Varian yang sudah dipakai specsheet terbit: Material Code / warna / thickness dikunci (INACTIVE + varian baru).
-- - Pilihan model: nilai yang dipakai model ber-specsheet terbit tidak bisa diubah; ukuran yang dipakai model
--   tidak bisa diubah. INACTIVE selalu boleh (model lama tetap memakainya).
-- - Masa transisi: CBD (R5) masih membaca warna; material.material_code/thickness lama dihapus di R5.
-- ============================================================================

-- ---------------------------------------------------------------- Pengaman
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'material_price' AND column_name = 'variant_id') THEN
    RAISE EXCEPTION 'Bagian R3 belum dijalankan. Jalankan file revisi dari awal.';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'product_model' AND column_name = 'code')
     AND EXISTS (SELECT 1 FROM product_model) THEN
    RAISE EXCEPTION 'Masih ada model uji dari sebelum R4 (berkode). Jalankan RESET_data_bisnis.sql dulu (user & pabrik tetap tersimpan).';
  END IF;
END;
$$;

-- View yang membaca kolom yang diubah — semuanya dibuat ulang di bawah
DROP VIEW IF EXISTS v_worklist_spec, v_revision_checklist, v_worklist_cbd, v_worklist_price_gap,
                    v_recent_published, v_model_list, v_bom_grid;

-- ---------------------------------------------------------------- Model: struktur baru
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'product_model' AND column_name = 'code') THEN
    ALTER TABLE product_model DROP CONSTRAINT IF EXISTS uq_model_code;
    ALTER TABLE product_model
      DROP COLUMN code, DROP COLUMN factory, DROP COLUMN category, DROP COLUMN outsole_mold, DROP COLUMN last_no,
      DROP COLUMN construction, DROP COLUMN size_range, DROP COLUMN sample_size;
    ALTER TABLE product_model
      ADD COLUMN factory_id      uuid NOT NULL REFERENCES factory(id),
      ADD COLUMN name_key        text GENERATED ALWAYS AS (fn_normalize(name)) STORED,
      ADD COLUMN category_id     uuid REFERENCES model_option(id),
      ADD COLUMN construction_id uuid REFERENCES model_option(id),
      ADD COLUMN gender_id       uuid REFERENCES model_option(id),
      ADD COLUMN last_id         uuid REFERENCES model_option(id),
      ADD COLUMN outsole_mold_id uuid REFERENCES model_option(id),
      ADD COLUMN sizes           integer[],
      ADD COLUMN sample_size     integer;
    ALTER TABLE product_model ADD CONSTRAINT uq_model_name UNIQUE (factory_id, name_key);
  END IF;
END;
$$;
CREATE INDEX IF NOT EXISTS idx_model_factory ON product_model (factory_id);

-- Kolom generated (name_key) masih NULL di BEFORE trigger -> dihitung sendiri.
CREATE OR REPLACE FUNCTION fn_model_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other text;
BEGIN
  NEW.name := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  IF NEW.name = '' THEN
    RAISE EXCEPTION 'Nama model wajib diisi.';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.factory_id IS DISTINCT FROM OLD.factory_id THEN
    RAISE EXCEPTION 'Pabrik model tidak bisa diubah.';
  END IF;
  SELECT name INTO v_other FROM product_model
   WHERE factory_id = NEW.factory_id AND name_key = fn_normalize(NEW.name) AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Model "%" sudah ada di pabrik ini.', v_other;
  END IF;
  NEW.sizes := nullif(ARRAY(SELECT DISTINCT x FROM unnest(coalesce(NEW.sizes, ARRAY[]::integer[])) AS x
                             WHERE x IS NOT NULL ORDER BY x), ARRAY[]::integer[]);
  IF EXISTS (SELECT 1 FROM unnest(coalesce(NEW.sizes, ARRAY[]::integer[])) AS x WHERE x < 1 OR x > 99) THEN
    RAISE EXCEPTION 'Ukuran harus angka bulat 1–99.';
  END IF;
  IF NEW.sample_size IS NOT NULL AND NOT (NEW.sample_size = ANY (coalesce(NEW.sizes, ARRAY[]::integer[]))) THEN
    RAISE EXCEPTION 'Sample size % harus salah satu ukuran model.', NEW.sample_size;
  END IF;
  RETURN NEW;
END;
$$;

-- Huruf kapital otomatis (F10b) tanpa kode model
CREATE OR REPLACE FUNCTION fn_upper_names() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME IN ('supplier', 'component') THEN
    NEW.name := upper(NEW.name);
  ELSIF TG_TABLE_NAME = 'material' THEN
    NEW.name := upper(NEW.name);
    NEW.category := upper(NEW.category);
  ELSIF TG_TABLE_NAME = 'product_model' THEN
    NEW.name := upper(NEW.name);
  ELSIF TG_TABLE_NAME = 'article' THEN
    NEW.colorway := upper(NEW.colorway);
    IF TG_OP = 'INSERT' OR NEW.code IS DISTINCT FROM OLD.code THEN
      NEW.code := upper(NEW.code);
    END IF;
  ELSIF TG_TABLE_NAME = 'bom_line' THEN
    NEW.local_component_name := upper(NEW.local_component_name);
    NEW.sub_name := upper(NEW.sub_name);
  END IF;
  RETURN NEW;
END;
$$;

-- "35, 36, 37, 38, 40, 41" -> "35–38, 40–41"
CREATE OR REPLACE FUNCTION fn_size_label(p integer[]) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v     integer[] := ARRAY(SELECT DISTINCT x FROM unnest(coalesce(p, ARRAY[]::integer[])) AS x WHERE x IS NOT NULL ORDER BY x);
  parts text[] := ARRAY[]::text[];
  s     integer;
  e     integer;
  i     integer;
BEGIN
  IF cardinality(v) = 0 THEN
    RETURN NULL;
  END IF;
  s := v[1];
  e := v[1];
  FOR i IN 2 .. cardinality(v) LOOP
    IF v[i] = e + 1 THEN
      e := v[i];
    ELSE
      parts := parts || CASE WHEN s = e THEN s::text ELSE s::text || '–' || e::text END;
      s := v[i];
      e := v[i];
    END IF;
  END LOOP;
  parts := parts || CASE WHEN s = e THEN s::text ELSE s::text || '–' || e::text END;
  RETURN array_to_string(parts, ', ');
END;
$$;

-- ---------------------------------------------------------------- Pabrik objek & penjaga tulis
CREATE OR REPLACE FUNCTION fn_model_factory(p_model_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT factory_id FROM product_model WHERE id = p_model_id $$;

CREATE OR REPLACE FUNCTION fn_sheet_factory(p_specsheet_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT pm.factory_id FROM specsheet sh JOIN product_model pm ON pm.id = sh.model_id WHERE sh.id = p_specsheet_id
$$;

CREATE OR REPLACE FUNCTION fn_article_factory(p_article_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT pm.factory_id FROM article a JOIN specsheet sh ON sh.id = a.specsheet_id
    JOIN product_model pm ON pm.id = sh.model_id WHERE a.id = p_article_id
$$;

CREATE OR REPLACE FUNCTION fn_rev_factory(p_revision_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT pm.factory_id FROM specsheet_revision r JOIN specsheet sh ON sh.id = r.specsheet_id
    JOIN product_model pm ON pm.id = sh.model_id WHERE r.id = p_revision_id
$$;

CREATE OR REPLACE FUNCTION fn_line_factory(p_line_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT fn_rev_factory(revision_id) FROM bom_line WHERE id = p_line_id $$;

-- Login + izin + data milik pabrik user. p_factory NULL = data tidak ditemukan.
CREATE OR REPLACE FUNCTION fn_auth_in(p_token text, p_perm text, p_factory uuid) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, p_perm);
BEGIN
  IF p_factory IS NULL THEN
    RAISE EXCEPTION 'Data tidak ditemukan. Muat ulang halaman.';
  END IF;
  PERFORM fn_assert_factory(v_email, p_factory);
  RETURN v_email;
END;
$$;

-- ---------------------------------------------------------------- Simpan model
-- Pilihan model untuk field p_kind: harus jenis itu, milik pabrik model (LAST/OUTSOLE_MOLD), dan ACTIVE
-- (kecuali nilai lama yang tidak diubah).
CREATE OR REPLACE FUNCTION fn_model_option_ref(p_id uuid, p_kind text, p_factory uuid, p_old uuid) RETURNS void
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_opt model_option%ROWTYPE;
BEGIN
  IF p_id IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO v_opt FROM model_option WHERE id = p_id;
  IF NOT FOUND OR v_opt.kind <> p_kind THEN
    RAISE EXCEPTION 'Pilihan % tidak valid. Muat ulang halaman.', fn_option_kind_label(p_kind);
  END IF;
  IF v_opt.factory_id IS NOT NULL AND v_opt.factory_id IS DISTINCT FROM p_factory THEN
    RAISE EXCEPTION '% "%" milik pabrik lain.', fn_option_kind_label(p_kind), v_opt.value;
  END IF;
  IF v_opt.status = 'INACTIVE' AND p_id IS DISTINCT FROM p_old THEN
    RAISE EXCEPTION '% "%" sudah INACTIVE.', fn_option_kind_label(p_kind), v_opt.value;
  END IF;
END;
$$;

-- p_id NULL = tambah (pabrik = pabrik user). p_sizes = '[37, 38, 39]'.
CREATE OR REPLACE FUNCTION fn_model_save(
  p_token text, p_id uuid, p_name text, p_category_id uuid, p_construction_id uuid, p_gender_id uuid,
  p_last_id uuid, p_outsole_mold_id uuid, p_sizes jsonb, p_sample_size integer
) RETURNS uuid
LANGUAGE plpgsql AS $$
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
      RAISE EXCEPTION 'Akun Anda belum terhubung ke pabrik. Minta System Admin mengisi pabrik Anda.';
    END IF;
  ELSE
    SELECT * INTO v_old FROM product_model WHERE id = p_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Model tidak ditemukan.';
    END IF;
    PERFORM fn_assert_factory(v_email, v_old.factory_id);
    v_factory := v_old.factory_id;
  END IF;
  IF p_category_id IS NULL THEN
    RAISE EXCEPTION 'Kategori wajib dipilih.';
  END IF;
  PERFORM fn_model_option_ref(p_category_id, 'KATEGORI', v_factory, v_old.category_id);
  PERFORM fn_model_option_ref(p_construction_id, 'CONSTRUCTION', v_factory, v_old.construction_id);
  PERFORM fn_model_option_ref(p_gender_id, 'GENDER', v_factory, v_old.gender_id);
  PERFORM fn_model_option_ref(p_last_id, 'LAST', v_factory, v_old.last_id);
  PERFORM fn_model_option_ref(p_outsole_mold_id, 'OUTSOLE_MOLD', v_factory, v_old.outsole_mold_id);
  IF jsonb_typeof(coalesce(p_sizes, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'Daftar ukuran tidak valid.';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(coalesce(p_sizes, '[]'::jsonb)) AS e WHERE e !~ '^[0-9]{1,2}$') THEN
    RAISE EXCEPTION 'Ukuran harus angka bulat (tanpa setengah ukuran).';
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
$$;

-- Model + nama pilihan. Kolom lama (factory, category, construction, last_no, outsole_mold, size_range, sample_size)
-- dipertahankan sebagai teks supaya page Specsheet / CBD / export tetap membaca nama yang sama.
DROP VIEW IF EXISTS v_model;
CREATE VIEW v_model AS
SELECT pm.id, pm.factory_id, f.name AS factory_name, f.name AS factory, pm.name, pm.name_key,
       oc.value AS category, ok.value AS construction, og.value AS gender, ol.value AS last_no, oo.value AS outsole_mold,
       pm.sizes, fn_size_label(pm.sizes) AS size_range, pm.sample_size::text AS sample_size,
       pm.category_id, pm.construction_id, pm.gender_id, pm.last_id, pm.outsole_mold_id,
       pm.created_at, pm.created_by, pm.updated_at, pm.updated_by
  FROM product_model pm
  JOIN factory f ON f.id = pm.factory_id
  LEFT JOIN model_option oc ON oc.id = pm.category_id
  LEFT JOIN model_option ok ON ok.id = pm.construction_id
  LEFT JOIN model_option og ON og.id = pm.gender_id
  LEFT JOIN model_option ol ON ol.id = pm.last_id
  LEFT JOIN model_option oo ON oo.id = pm.outsole_mold_id;

-- ---------------------------------------------------------------- Season, article, lampiran (dengan cek pabrik)
CREATE OR REPLACE FUNCTION fn_season_add(p_token text, p_model_id uuid, p_season text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_model', fn_model_factory(p_model_id));
  v_id    uuid;
BEGIN
  INSERT INTO specsheet (model_id, season, updated_by) VALUES (p_model_id, p_season, v_email) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- p_id NULL = tambah ke p_specsheet_id
CREATE OR REPLACE FUNCTION fn_article_save(p_token text, p_id uuid, p_specsheet_id uuid, p_code text, p_colorway text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text;
  v_id    uuid;
BEGIN
  IF p_id IS NULL THEN
    v_email := fn_auth_in(p_token, 'edit_model', fn_sheet_factory(p_specsheet_id));
    INSERT INTO article (specsheet_id, code, colorway, updated_by)
    VALUES (p_specsheet_id, p_code, p_colorway, v_email) RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  v_email := fn_auth_in(p_token, 'edit_model', fn_article_factory(p_id));
  UPDATE article SET code = p_code, colorway = p_colorway, updated_by = v_email WHERE id = p_id;
  RETURN p_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_article_delete(p_token text, p_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_model', fn_article_factory(p_id));
BEGIN
  DELETE FROM article WHERE id = p_id;
  RETURN p_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_attachment_add(
  p_token text, p_article_id uuid, p_file_name text, p_base64 text, p_note text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email   text := fn_auth_in(p_token, 'edit_model', fn_article_factory(p_article_id));
  v_content bytea;
  v_mime    text;
  v_name    text := btrim(coalesce(p_file_name, ''));
  v_id      uuid;
BEGIN
  IF coalesce(p_base64, '') = '' THEN
    RAISE EXCEPTION 'Pilih file yang akan diunggah.';
  END IF;
  BEGIN
    v_content := decode(regexp_replace(regexp_replace(p_base64, '^data:[^,]*,', ''), '\s', '', 'g'), 'base64');
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'File tidak terbaca (format Base64 tidak valid).';
  END;
  IF length(v_content) > 5242880 THEN
    RAISE EXCEPTION 'Ukuran file % MB, maksimal 5 MB.', round(length(v_content) / 1048576.0, 1);
  END IF;
  v_mime := CASE
    WHEN substring(v_content FROM 1 FOR 3) = '\xffd8ff'::bytea           THEN 'image/jpeg'
    WHEN substring(v_content FROM 1 FOR 8) = '\x89504e470d0a1a0a'::bytea THEN 'image/png'
    WHEN substring(v_content FROM 1 FOR 5) = '\x255044462d'::bytea       THEN 'application/pdf'
  END;
  IF v_mime IS NULL THEN
    RAISE EXCEPTION 'Jenis file tidak didukung. Hanya JPG, PNG, atau PDF.';
  END IF;
  IF v_name = '' THEN
    v_name := 'lampiran' || CASE v_mime WHEN 'image/jpeg' THEN '.jpg' WHEN 'image/png' THEN '.png' ELSE '.pdf' END;
  END IF;
  INSERT INTO article_attachment (article_id, file_name, mime_type, size_bytes, content, note, updated_by)
  VALUES (p_article_id, v_name, v_mime, length(v_content), v_content,
          nullif(btrim(coalesce(p_note, '')), ''), v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_attachment_delete(p_token text, p_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_model',
                             fn_article_factory((SELECT article_id FROM article_attachment WHERE id = p_id)));
BEGIN
  DELETE FROM article_attachment WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- ---------------------------------------------------------------- BOM: thickness di baris, varian di sel
ALTER TABLE bom_line ADD COLUMN IF NOT EXISTS thickness text;     -- teks ERP (fn_clean_thickness), NULL = tanpa

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'bom_cell' AND column_name = 'variant_id') THEN
    -- is_used lama menganggap none / - / n/a = kosong; sekarang hanya sel kosong = tidak dipakai
    ALTER TABLE bom_cell DROP COLUMN is_used;
    ALTER TABLE bom_cell ADD COLUMN is_used boolean GENERATED ALWAYS AS (btrim(coalesce(color, '')) <> '') STORED;
    ALTER TABLE bom_cell ADD COLUMN variant_id uuid REFERENCES material_variant(id);
  END IF;
END;
$$;
CREATE INDEX IF NOT EXISTS idx_bom_cell_variant ON bom_cell (variant_id);

-- Varian ACTIVE untuk induk + thickness + warna (NULL = belum terdaftar -> sel kuning)
CREATE OR REPLACE FUNCTION fn_bom_variant_for(p_material_id uuid, p_thickness text, p_color text) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT v.id FROM material_variant v
   WHERE v.material_id = p_material_id
     AND v.thickness_key = fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''))
     AND v.color_key = fn_normalize(p_color)
     AND v.status = 'ACTIVE'
   LIMIT 1
$$;

-- Sel: warna dirapikan (huruf besar) + varian dicari ulang setiap ditulis
CREATE OR REPLACE FUNCTION fn_bom_cell_variant() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_line record;
BEGIN
  NEW.color := nullif(upper(btrim(regexp_replace(coalesce(NEW.color, ''), '\s+', ' ', 'g'))), '');
  IF NEW.color IS NULL THEN
    NEW.variant_id := NULL;
    RETURN NEW;
  END IF;
  SELECT material_id, thickness INTO v_line FROM bom_line WHERE id = NEW.bom_line_id;
  NEW.variant_id := fn_bom_variant_for(v_line.material_id, v_line.thickness, NEW.color);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_bom_cell_variant ON bom_cell;
CREATE TRIGGER trg_bom_cell_variant BEFORE INSERT OR UPDATE ON bom_cell
  FOR EACH ROW EXECUTE FUNCTION fn_bom_cell_variant();

-- Varian baru / berubah -> sel DRAFT induk ini yang belum tersambung (atau tersambung ke varian ini) dicari ulang
CREATE OR REPLACE FUNCTION fn_variant_relink() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE bom_cell bc
     SET color = bc.color
    FROM bom_line l
    JOIN specsheet_revision r ON r.id = l.revision_id AND r.status = 'DRAFT'
   WHERE bc.bom_line_id = l.id AND l.material_id = NEW.material_id AND l.is_active
     AND bc.color IS NOT NULL
     AND (bc.variant_id IS NULL OR bc.variant_id = NEW.id);
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_variant_relink ON material_variant;
CREATE TRIGGER trg_variant_relink AFTER INSERT OR UPDATE ON material_variant
  FOR EACH ROW EXECUTE FUNCTION fn_variant_relink();

-- ---------------------------------------------------------------- BOM: pemeriksaan
-- Material untuk baris BOM: ada, milik pabrik revisi, tidak INACTIVE.
DROP FUNCTION IF EXISTS fn_bom_check_material(uuid);
CREATE OR REPLACE FUNCTION fn_bom_check_material(p_material_id uuid, p_factory uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_mat material%ROWTYPE;
BEGIN
  SELECT * INTO v_mat FROM material WHERE id = p_material_id;
  IF NOT FOUND OR v_mat.factory_id IS DISTINCT FROM p_factory THEN
    RAISE EXCEPTION 'Material wajib dipilih dari Master Material pabrik ini.';
  END IF;
  IF v_mat.status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Material % sudah INACTIVE. Pilih material lain.', v_mat.name;
  END IF;
END;
$$;

-- Supplier baris: harus ACTIVE; link material-supplier dibuat otomatis (fn_ensure_link menolak link INACTIVE).
CREATE OR REPLACE FUNCTION fn_bom_check_supplier(p_material_id uuid, p_supplier_id uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_sup supplier%ROWTYPE;
BEGIN
  IF p_supplier_id IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO v_sup FROM supplier WHERE id = p_supplier_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Supplier tidak ada di Master Supplier.';
  END IF;
  IF v_sup.status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Supplier % sudah nonaktif. Pilih supplier lain.', v_sup.name;
  END IF;
  PERFORM fn_ensure_link(p_material_id, p_supplier_id);
END;
$$;

CREATE OR REPLACE FUNCTION fn_bom_create_cells(p_line_id uuid, p_email text) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO bom_cell (bom_line_id, article_id, updated_by)
  SELECT l.id, ra.article_id, p_email
    FROM bom_line l JOIN revision_article ra ON ra.revision_id = l.revision_id AND ra.status = 'ACTIVE'
   WHERE l.id = p_line_id
  ON CONFLICT DO NOTHING
$$;

-- ---------------------------------------------------------------- Buat & hapus revisi
CREATE OR REPLACE FUNCTION fn_revision_create(
  p_token text, p_specsheet_id uuid, p_mode text, p_stage text, p_source_specsheet_id uuid
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_specsheet', fn_sheet_factory(p_specsheet_id));
  v_stages text[] := ARRAY['PULL', 'SMS', 'GTM', 'PROD'];
  v_sheet  specsheet%ROWTYPE;
  v_srcsp  specsheet%ROWTYPE;
  v_src    specsheet_revision%ROWTYPE;
  v_stage  text;
  v_no     integer := 0;
  v_id     uuid;
BEGIN
  SELECT * INTO v_sheet FROM specsheet WHERE id = p_specsheet_id FOR UPDATE;   -- antre per season
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Season tidak ditemukan.';
  END IF;
  IF EXISTS (SELECT 1 FROM specsheet_revision WHERE specsheet_id = p_specsheet_id AND status = 'DRAFT') THEN
    RAISE EXCEPTION 'Sudah ada revisi DRAFT untuk season %. Terbitkan atau hapus draft itu dulu.', v_sheet.season;
  END IF;

  IF p_mode IN ('EMPTY', 'COPY') THEN
    IF EXISTS (SELECT 1 FROM specsheet_revision WHERE specsheet_id = p_specsheet_id) THEN
      RAISE EXCEPTION 'Season % sudah punya revisi. Pakai Revisi berikutnya atau Stage berikutnya.', v_sheet.season;
    END IF;
    v_stage := coalesce(nullif(p_stage, ''), 'PULL');
    IF NOT v_stage = ANY (v_stages) THEN
      RAISE EXCEPTION 'Stage tidak valid.';
    END IF;
    IF p_mode = 'COPY' THEN
      SELECT * INTO v_srcsp FROM specsheet WHERE id = p_source_specsheet_id;
      IF NOT FOUND OR v_srcsp.id = v_sheet.id THEN
        RAISE EXCEPTION 'Pilih season sumber.';
      END IF;
      IF v_srcsp.model_id <> v_sheet.model_id THEN
        RAISE EXCEPTION 'Specsheet hanya bisa di-copy dari season lain model yang sama.';
      END IF;
      SELECT * INTO v_src FROM specsheet_revision
       WHERE specsheet_id = v_srcsp.id AND status = 'PUBLISHED'
       ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Season % belum punya revisi terbit untuk di-copy.', v_srcsp.season;
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
      RAISE EXCEPTION 'Season % belum punya revisi terbit.', v_sheet.season;
    END IF;
    IF p_mode = 'NEXT_REVISION' THEN
      v_stage := v_src.stage;
      SELECT max(revision_no) + 1 INTO v_no FROM specsheet_revision
       WHERE specsheet_id = p_specsheet_id AND stage = v_stage;
    ELSE
      IF v_src.stage = 'PROD' THEN
        RAISE EXCEPTION 'Sudah berada di stage terakhir (PROD). Pakai Revisi berikutnya.';
      END IF;
      v_stage := v_stages[array_position(v_stages, v_src.stage) + 1];
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
    -- warna disalin; varian dicari ulang dari master sekarang (trigger) -> varian yang sudah INACTIVE jadi kuning
    INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
    SELECT n.id, c.article_id, c.color, v_email
      FROM bom_cell c
      JOIN bom_line o ON o.id = c.bom_line_id AND o.revision_id = v_src.id AND o.is_active
      JOIN bom_line n ON n.revision_id = v_id AND n.line_key = o.line_key;
  ELSE
    RAISE EXCEPTION 'Pilih cara membuat revisi.';
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_revision_delete_draft(p_token text, p_revision_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_rev_factory(p_revision_id));
  v_rev   specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
BEGIN
  DELETE FROM specsheet_revision WHERE id = v_rev.id;
  RETURN v_rev.id;
END;
$$;

-- ---------------------------------------------------------------- Baris BOM
-- Komponen master ACTIVE (p_component_id) atau lokal (p_local_no + p_local_name). Material = induk + thickness.
-- p_fill_color: isi warna ini ke semua article aktif (dipakai saat Material Code diketik di baris tambah).
DROP FUNCTION IF EXISTS fn_bom_add_line(text, uuid, uuid, integer, text, uuid, uuid, text);
CREATE OR REPLACE FUNCTION fn_bom_add_line(
  p_token text, p_revision_id uuid, p_component_id uuid, p_local_no integer, p_local_name text,
  p_material_id uuid, p_thickness text, p_supplier_id uuid, p_process text, p_fill_color text
) RETURNS uuid
LANGUAGE plpgsql AS $$
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
      RAISE EXCEPTION 'Komponen master tidak ditemukan atau INACTIVE. Untuk komponen baru, pakai komponen lokal.';
    END IF;
    IF EXISTS (SELECT 1 FROM bom_line WHERE revision_id = v_rev.id AND is_active AND parent_line_key IS NULL
                                        AND component_id = p_component_id AND material_id = p_material_id
                                        AND thickness IS NOT DISTINCT FROM v_thick) THEN
      RAISE EXCEPTION 'Komponen % + material ini (thickness sama) sudah ada di revisi ini.', v_comp.number;
    END IF;
  ELSE
    IF p_local_no IS NULL THEN
      RAISE EXCEPTION 'Komponen tidak ada di master — isi No. untuk komponen lokal.';
    END IF;
    IF p_local_no % 10 = 0 THEN
      RAISE EXCEPTION 'No. komponen lokal tidak boleh kelipatan 10 (kelipatan 10 untuk komponen master).';
    END IF;
    IF v_name IS NULL THEN
      RAISE EXCEPTION 'Nama komponen lokal wajib diisi.';
    END IF;
    IF EXISTS (SELECT 1 FROM bom_line WHERE revision_id = v_rev.id AND is_active AND parent_line_key IS NULL
                                        AND local_component_no = p_local_no) THEN
      RAISE EXCEPTION 'No. lokal % sudah dipakai di revisi ini.', p_local_no;
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
$$;

DROP FUNCTION IF EXISTS fn_bom_add_sub(text, uuid, text, uuid, uuid, text);
CREATE OR REPLACE FUNCTION fn_bom_add_sub(
  p_token text, p_parent_line_id uuid, p_sub_name text, p_material_id uuid, p_thickness text, p_supplier_id uuid,
  p_process text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_factory uuid := fn_line_factory(p_parent_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_parent  bom_line%ROWTYPE;
  v_name    text := nullif(btrim(regexp_replace(coalesce(p_sub_name, ''), '\s+', ' ', 'g')), '');
  v_id      uuid;
BEGIN
  SELECT * INTO v_parent FROM bom_line WHERE id = p_parent_line_id;
  IF NOT FOUND OR NOT v_parent.is_active THEN
    RAISE EXCEPTION 'Baris induk tidak ditemukan atau sudah tidak aktif.';
  END IF;
  PERFORM fn_revision_draft(v_parent.revision_id);
  IF v_parent.parent_line_key IS NOT NULL THEN
    RAISE EXCEPTION 'Subkomponen tidak bisa dibuat di bawah subkomponen lain.';
  END IF;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Nama subkomponen wajib diisi.';
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
$$;

-- Ganti material (induk dan/atau thickness): baris lama nonaktif, baris baru mewarisi komponen/supplier/remarks/warna.
DROP FUNCTION IF EXISTS fn_bom_replace_material(text, uuid, uuid);
CREATE OR REPLACE FUNCTION fn_bom_replace_material(p_token text, p_line_id uuid, p_material_id uuid, p_thickness text)
RETURNS uuid
LANGUAGE plpgsql AS $$
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
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_old.revision_id);
  IF v_old.material_id = p_material_id AND v_old.thickness IS NOT DISTINCT FROM v_thick THEN
    RAISE EXCEPTION 'Material dan thickness baru sama dengan yang sekarang.';
  END IF;
  PERFORM fn_bom_check_material(p_material_id, v_factory);
  IF v_old.parent_line_key IS NULL AND EXISTS (
       SELECT 1 FROM bom_line WHERE revision_id = v_old.revision_id AND is_active AND parent_line_key IS NULL
          AND id <> v_old.id AND material_id = p_material_id AND thickness IS NOT DISTINCT FROM v_thick
          AND component_id IS NOT DISTINCT FROM v_old.component_id
          AND local_component_no IS NOT DISTINCT FROM v_old.local_component_no) THEN
    RAISE EXCEPTION 'Komponen ini dengan material + thickness tersebut sudah ada di revisi ini.';
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
$$;

CREATE OR REPLACE FUNCTION fn_bom_set_supplier(p_token text, p_line_id uuid, p_supplier_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  PERFORM fn_bom_check_supplier(v_line.material_id, p_supplier_id);
  UPDATE bom_line SET supplier_id = p_supplier_id, updated_by = v_email WHERE id = v_line.id;
  RETURN v_line.id;
END;
$$;

-- Remarks (dulu UPDATE langsung dari query a_bom_set_process)
CREATE OR REPLACE FUNCTION fn_bom_set_process(p_token text, p_line_id uuid, p_process text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  UPDATE bom_line SET process = nullif(btrim(coalesce(p_process, '')), ''), updated_by = v_email WHERE id = v_line.id;
  RETURN v_line.id;
END;
$$;

-- Sel: warna, atau Material Code varian (harus induk + thickness baris ini -> diganti warnanya). Kosong = tidak dipakai.
CREATE OR REPLACE FUNCTION fn_bom_cell_set(p_token text, p_line_id uuid, p_article_id uuid, p_color text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_factory uuid := fn_line_factory(p_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_line    bom_line%ROWTYPE;
  v_color   text := nullif(upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g'))), '');
  v_var     record;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  IF NOT EXISTS (SELECT 1 FROM revision_article
                  WHERE revision_id = v_line.revision_id AND article_id = p_article_id AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'Article ini tidak aktif di revisi ini.';
  END IF;
  IF v_color IS NOT NULL THEN
    SELECT v.material_id, v.thickness, v.thickness_key, v.color, v.status, m.name INTO v_var
      FROM material_variant v JOIN material m ON m.id = v.material_id
     WHERE v.factory_id = v_factory AND v.code = v_color;
    IF FOUND THEN
      IF v_var.material_id <> v_line.material_id
         OR v_var.thickness_key <> fn_normalize(coalesce(v_line.thickness, '')) THEN
        RAISE EXCEPTION 'Kode % adalah % · % · % — tidak cocok dengan material / thickness baris ini.',
          v_color, v_var.name, fn_thickness_label(v_var.thickness), v_var.color;
      END IF;
      IF v_var.status = 'INACTIVE' THEN
        RAISE EXCEPTION 'Kode % sudah INACTIVE.', v_color;
      END IF;
      v_color := v_var.color;
    END IF;
  END IF;
  INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
  VALUES (v_line.id, p_article_id, v_color, v_email)
  ON CONFLICT (bom_line_id, article_id) DO UPDATE SET color = EXCLUDED.color, updated_by = EXCLUDED.updated_by;
  RETURN v_line.id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_bom_delete_line(p_token text, p_line_id uuid) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
  v_subs  integer;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  DELETE FROM bom_line WHERE revision_id = v_line.revision_id AND parent_line_key = v_line.line_key;
  GET DIAGNOSTICS v_subs = ROW_COUNT;
  DELETE FROM bom_line WHERE id = v_line.id;
  RETURN v_subs + 1;
END;
$$;

CREATE OR REPLACE FUNCTION fn_rev_article_set(p_token text, p_revision_id uuid, p_article_id uuid, p_status text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_rev_factory(p_revision_id));
  v_rev   specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'DROPPED') THEN
    RAISE EXCEPTION 'Status article tidak valid.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM article WHERE id = p_article_id AND specsheet_id = v_rev.specsheet_id) THEN
    RAISE EXCEPTION 'Article bukan milik season revisi ini.';
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
$$;

-- ---------------------------------------------------------------- Varian & pilihan: kunci setelah dipakai
-- true = varian dipakai dokumen terbit (specsheet; R5 menambah CBD)
CREATE OR REPLACE FUNCTION fn_variant_used_published(p_variant_id uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM bom_cell bc
                   JOIN bom_line l ON l.id = bc.bom_line_id
                   JOIN specsheet_revision r ON r.id = l.revision_id
                  WHERE bc.variant_id = p_variant_id AND r.status = 'PUBLISHED')
$$;

CREATE OR REPLACE FUNCTION fn_variant_save(
  p_token text, p_id uuid, p_material_id uuid, p_code text, p_color text, p_thickness text, p_status text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_mat   material%ROWTYPE;
  v_old   material_variant%ROWTYPE;
  v_id    uuid;
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Status varian wajib dipilih (ACTIVE / INACTIVE).';
  END IF;
  IF p_id IS NULL THEN
    SELECT * INTO v_mat FROM material WHERE id = p_material_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Material tidak ditemukan.';
    END IF;
    PERFORM fn_assert_factory(v_email, v_mat.factory_id);
    IF v_mat.status = 'INACTIVE' THEN
      RAISE EXCEPTION 'Material % sudah INACTIVE — aktifkan dulu sebelum menambah varian.', v_mat.name;
    END IF;
    INSERT INTO material_variant (material_id, factory_id, code, color, thickness, status, updated_by)
    VALUES (p_material_id, v_mat.factory_id, p_code, p_color, p_thickness, p_status, v_email)
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  SELECT * INTO v_old FROM material_variant WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Varian tidak ditemukan.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_old.factory_id);
  IF (upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g'))) IS DISTINCT FROM v_old.code
      OR upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g'))) IS DISTINCT FROM v_old.color
      OR fn_clean_thickness(p_thickness) IS DISTINCT FROM v_old.thickness)
     AND fn_variant_used_published(p_id) THEN
    RAISE EXCEPTION 'Varian % sudah dipakai di dokumen terbit — Material Code, warna, dan thickness tidak bisa diubah. Jadikan INACTIVE lalu daftarkan varian baru.', v_old.code;
  END IF;
  UPDATE material_variant
     SET code = p_code, color = p_color, thickness = p_thickness, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- Pilihan model: ubah nilai ditolak bila dipakai model ber-specsheet terbit (UKURAN: bila dipakai model mana pun).
CREATE OR REPLACE FUNCTION fn_option_save(
  p_token text, p_id uuid, p_kind text, p_value text, p_sort_order integer, p_status text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email   text := fn_auth(p_token, 'manage_master');
  v_factory uuid := fn_user_factory(v_email);
  v_old     model_option%ROWTYPE;
  v_used    text;
  v_id      uuid;
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Status pilihan wajib dipilih (ACTIVE / INACTIVE).';
  END IF;
  IF p_id IS NULL THEN
    IF p_kind IS NULL OR p_kind NOT IN ('KATEGORI', 'CONSTRUCTION', 'GENDER', 'UKURAN', 'LAST', 'OUTSOLE_MOLD') THEN
      RAISE EXCEPTION 'Pilih jenis pilihan.';
    END IF;
    IF fn_option_is_factory_kind(p_kind) AND v_factory IS NULL THEN
      RAISE EXCEPTION '% diisi per pabrik — akun Anda belum terhubung ke pabrik.', fn_option_kind_label(p_kind);
    END IF;
    INSERT INTO model_option (kind, factory_id, value, sort_order, status, updated_by)
    VALUES (p_kind, CASE WHEN fn_option_is_factory_kind(p_kind) THEN v_factory END, p_value, p_sort_order, p_status, v_email)
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  SELECT * INTO v_old FROM model_option WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pilihan tidak ditemukan.';
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
      RAISE EXCEPTION '% "%" sudah dipakai model %, nilainya tidak bisa diubah. Jadikan INACTIVE lalu tambah nilai baru.',
        fn_option_kind_label(v_old.kind), v_old.value, left(v_used, 200);
    END IF;
  END IF;
  UPDATE model_option SET value = p_value, sort_order = p_sort_order, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- ---------------------------------------------------------------- View grid BOM
-- cells = {"<article_id>": "WARNA"}, cell_codes = {"<article_id>": "MATERIAL CODE"} (sel tersambung),
-- yellow = sel berwarna tanpa varian di article aktif, material_code = kode-kode varian baris ini (export).
CREATE VIEW v_bom_grid AS
SELECT l.id, l.revision_id, l.line_key, l.parent_line_key, (l.parent_line_key IS NOT NULL) AS is_sub,
       l.component_id, l.local_component_no, l.sub_seq,
       CASE WHEN l.parent_line_key IS NULL THEN coalesce(c.number, l.local_component_no)
            ELSE coalesce(pc.number, p.local_component_no) END AS group_no,
       CASE WHEN l.parent_line_key IS NULL THEN l.sort_order ELSE coalesce(p.sort_order, l.sort_order) END AS group_sort,
       CASE WHEN l.parent_line_key IS NULL THEN coalesce(c.number, l.local_component_no)::text
            ELSE coalesce(coalesce(pc.number, p.local_component_no)::text || '-', '') || l.sub_seq END AS display_no,
       CASE WHEN l.parent_line_key IS NULL THEN coalesce(c.name, l.local_component_name) ELSE l.sub_name END AS display_name,
       (l.component_id IS NULL AND l.parent_line_key IS NULL) AS is_local,
       l.material_id, cc.codes AS material_code, m.name AS material_name, l.thickness, m.uom, m.status AS material_status,
       l.supplier_id, s.name AS supplier_name, ms.status AS link_status,
       l.process, l.origin_line_key, l.replaces_line_key,
       coalesce(cc.cells, '{}'::jsonb) AS cells,
       s.status AS supplier_status,
       coalesce(cc.cell_codes, '{}'::jsonb) AS cell_codes,
       coalesce(cc.yellow, 0) AS yellow
  FROM bom_line l
  JOIN material m ON m.id = l.material_id
  LEFT JOIN component c ON c.id = l.component_id
  LEFT JOIN bom_line p ON p.revision_id = l.revision_id AND p.line_key = l.parent_line_key AND p.is_active
  LEFT JOIN component pc ON pc.id = p.component_id
  LEFT JOIN supplier s ON s.id = l.supplier_id
  LEFT JOIN material_supplier ms ON ms.material_id = l.material_id AND ms.supplier_id = l.supplier_id
  LEFT JOIN LATERAL (
    SELECT jsonb_object_agg(bc.article_id::text, bc.color) FILTER (WHERE bc.color IS NOT NULL) AS cells,
           jsonb_object_agg(bc.article_id::text, v.code) FILTER (WHERE v.id IS NOT NULL) AS cell_codes,
           string_agg(DISTINCT v.code, ', ') AS codes,
           (count(*) FILTER (WHERE bc.is_used AND bc.variant_id IS NULL AND ra.status = 'ACTIVE'))::integer AS yellow
      FROM bom_cell bc
      LEFT JOIN material_variant v ON v.id = bc.variant_id
      LEFT JOIN revision_article ra ON ra.revision_id = l.revision_id AND ra.article_id = bc.article_id
     WHERE bc.bom_line_id = l.id
  ) cc ON true
 WHERE l.is_active;

-- ---------------------------------------------------------------- Checklist & terbit specsheet
CREATE VIEW v_revision_checklist AS
SELECT x.*,
       (x.active_articles = 0 OR x.unused_articles IS NOT NULL OR x.inactive_materials IS NOT NULL
        OR x.no_supplier_lines > 0 OR x.yellow_cells > 0 OR x.inactive_suppliers IS NOT NULL) AS blocked
  FROM (
    SELECT r.id AS revision_id, r.specsheet_id, r.stage, r.revision_no, r.status,
           EXISTS (SELECT 1 FROM specsheet_revision o
                    WHERE o.specsheet_id = r.specsheet_id AND o.status = 'PUBLISHED' AND o.id <> r.id) AS requires_reason,
           (SELECT count(*)::int FROM bom_line l WHERE l.revision_id = r.id AND l.is_active) AS line_count,
           (SELECT count(*)::int FROM revision_article ra
             WHERE ra.revision_id = r.id AND ra.status = 'ACTIVE') AS active_articles,
           (SELECT string_agg(a.code, ', ' ORDER BY a.code)
              FROM revision_article ra JOIN article a ON a.id = ra.article_id
             WHERE ra.revision_id = r.id AND ra.status = 'ACTIVE'
               AND NOT EXISTS (SELECT 1 FROM bom_cell c JOIN bom_line l ON l.id = c.bom_line_id
                                WHERE l.revision_id = r.id AND l.is_active
                                  AND c.article_id = a.id AND c.is_used)) AS unused_articles,
           (SELECT string_agg(DISTINCT m.name, ', ')
              FROM bom_line l JOIN material m ON m.id = l.material_id
             WHERE l.revision_id = r.id AND l.is_active AND m.status = 'INACTIVE') AS inactive_materials,
           (SELECT count(*)::int FROM bom_line l
             WHERE l.revision_id = r.id AND l.is_active AND l.supplier_id IS NULL) AS no_supplier_lines,
           (SELECT count(*)::int
              FROM bom_cell c
              JOIN bom_line l ON l.id = c.bom_line_id AND l.revision_id = r.id AND l.is_active
              JOIN revision_article ra ON ra.revision_id = r.id AND ra.article_id = c.article_id AND ra.status = 'ACTIVE'
             WHERE c.is_used AND c.variant_id IS NULL) AS yellow_cells,
           (SELECT left(string_agg(DISTINCT m.name || coalesce(' ' || l.thickness, '') || ' · ' || c.color, ', '), 300)
              FROM bom_cell c
              JOIN bom_line l ON l.id = c.bom_line_id AND l.revision_id = r.id AND l.is_active
              JOIN material m ON m.id = l.material_id
              JOIN revision_article ra ON ra.revision_id = r.id AND ra.article_id = c.article_id AND ra.status = 'ACTIVE'
             WHERE c.is_used AND c.variant_id IS NULL) AS yellow_list,
           (SELECT string_agg(DISTINCT s.name || ' (' || m.name || ')', ', ')
              FROM bom_line l
              JOIN supplier s ON s.id = l.supplier_id
              JOIN material m ON m.id = l.material_id
              LEFT JOIN material_supplier ms ON ms.material_id = l.material_id AND ms.supplier_id = l.supplier_id
             WHERE l.revision_id = r.id AND l.is_active
               AND (s.status = 'INACTIVE' OR ms.status = 'INACTIVE')) AS inactive_suppliers
      FROM specsheet_revision r
  ) x;

CREATE OR REPLACE FUNCTION fn_revision_publish(p_token text, p_revision_id uuid, p_category text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_specsheet', fn_rev_factory(p_revision_id));
  v_rev    specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
  v_chk    v_revision_checklist%ROWTYPE;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_id     uuid;
BEGIN
  SELECT * INTO v_chk FROM v_revision_checklist WHERE revision_id = v_rev.id;
  IF v_chk.active_articles = 0 THEN
    RAISE EXCEPTION 'Specsheet harus punya minimal satu article aktif sebelum diterbitkan.';
  END IF;
  IF v_chk.unused_articles IS NOT NULL THEN
    RAISE EXCEPTION 'Article % belum memakai baris BOM mana pun (isi warna minimal di satu baris).', v_chk.unused_articles;
  END IF;
  IF v_chk.inactive_materials IS NOT NULL THEN
    RAISE EXCEPTION 'Ada baris memakai material INACTIVE: %. Ganti materialnya dulu.', v_chk.inactive_materials;
  END IF;
  IF v_chk.no_supplier_lines > 0 THEN
    RAISE EXCEPTION 'Ada % baris BOM tanpa supplier. Isi supplier semua baris dulu.', v_chk.no_supplier_lines;
  END IF;
  IF v_chk.yellow_cells > 0 THEN
    RAISE EXCEPTION 'Ada % sel warna yang belum punya Material Code (sel kuning): %. Daftarkan variannya dulu.',
      v_chk.yellow_cells, v_chk.yellow_list;
  END IF;
  IF v_chk.inactive_suppliers IS NOT NULL THEN
    RAISE EXCEPTION 'Ada supplier nonaktif: %. Ganti suppliernya dulu.', v_chk.inactive_suppliers;
  END IF;
  IF coalesce(p_category, '') NOT IN ('EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER') THEN
    RAISE EXCEPTION 'Pilih kategori perubahan.';
  END IF;
  IF v_chk.requires_reason AND v_reason IS NULL THEN
    RAISE EXCEPTION 'Alasan perubahan wajib diisi untuk revisi ini.';
  END IF;

  UPDATE specsheet_revision
     SET status = 'PUBLISHED', published_at = now(), published_by = v_email, updated_by = v_email
   WHERE id = v_rev.id;

  INSERT INTO change_log (doc_type, revision_id, category, reason, created_by)
  VALUES ('SPECSHEET', v_rev.id, p_category, coalesce(v_reason, 'Revisi awal.'), v_email)
  RETURNING id INTO v_id;

  PERFORM fn_cbd_sync_spec(v_rev.id, v_email);   -- F8
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------- View model & worklist (tanpa kode model)
CREATE VIEW v_model_list AS
SELECT m.id, m.factory_id, m.factory_name, m.name, m.category, m.construction, m.gender, m.last_no, m.outsole_mold,
       m.size_range, m.sample_size, m.updated_at, m.updated_by,
       (SELECT count(*) FROM specsheet x WHERE x.model_id = m.id) AS season_count,
       s.id AS specsheet_id, s.season, s.season_sort,
       (SELECT count(*) FROM article a WHERE a.specsheet_id = s.id) AS article_count,
       coalesce(s.season_sort = max(s.season_sort) OVER (PARTITION BY m.id), true) AS is_latest_season,
       ra.label AS spec_label, ra.active_articles AS spec_active_articles,
       rp.label AS spec_label_pub, rp.active_articles AS spec_active_articles_pub
  FROM v_model m
  LEFT JOIN specsheet s ON s.model_id = m.id
  LEFT JOIN LATERAL (
    SELECT r.stage || ' r' || r.revision_no || ' · ' || r.status AS label,
           (SELECT count(*) FROM revision_article x WHERE x.revision_id = r.id AND x.status = 'ACTIVE') AS active_articles
      FROM specsheet_revision r WHERE r.specsheet_id = s.id
     ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
  ) ra ON true
  LEFT JOIN LATERAL (
    SELECT r.stage || ' r' || r.revision_no || ' · ' || r.status AS label,
           (SELECT count(*) FROM revision_article x WHERE x.revision_id = r.id AND x.status = 'ACTIVE') AS active_articles
      FROM specsheet_revision r WHERE r.specsheet_id = s.id AND r.status = 'PUBLISHED'
     ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
  ) rp ON true;

CREATE VIEW v_worklist_spec AS
SELECT 'DRAFT'::text AS kind,
       pm.id AS model_id, pm.name AS model_name, pm.factory_id,
       sh.id AS specsheet_id, sh.season,
       r.id AS revision_id, r.stage, r.revision_no,
       ck.line_count, ck.no_supplier_lines AS no_supplier, ck.active_articles AS article_count,
       ck.unused_articles, ck.inactive_materials,
       NULL::text AS article_codes, NULL::boolean AS has_revision,
       ck.yellow_cells, ck.inactive_suppliers
  FROM specsheet_revision r
  JOIN specsheet sh ON sh.id = r.specsheet_id
  JOIN product_model pm ON pm.id = sh.model_id
  JOIN v_revision_checklist ck ON ck.revision_id = r.id
 WHERE r.status = 'DRAFT'
UNION ALL
SELECT 'UNASSIGNED',
       pm.id, pm.name, pm.factory_id,
       sh.id, sh.season,
       NULL::uuid, NULL::text, NULL::integer,
       NULL::integer, NULL::integer, u.n,
       NULL::text, NULL::text,
       u.codes, EXISTS (SELECT 1 FROM specsheet_revision x WHERE x.specsheet_id = sh.id),
       NULL::integer, NULL::text
  FROM specsheet sh
  JOIN product_model pm ON pm.id = sh.model_id
  CROSS JOIN LATERAL (
    SELECT count(*)::integer AS n, string_agg(a.code, ', ' ORDER BY a.code) AS codes
      FROM article a
     WHERE a.specsheet_id = sh.id
       AND NOT EXISTS (SELECT 1 FROM revision_article ra WHERE ra.article_id = a.id)
  ) u
 WHERE u.n > 0;

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
           coalesce(a.draft_label, a.pub_label) AS rev_label
      FROM v_cbd_article a
      JOIN product_model pm ON pm.id = a.model_id
      CROSS JOIN LATERAL (
        SELECT count(*)::integer AS stale_prices
          FROM v_cbd_price_check pc
         WHERE pc.cbd_revision_id = a.draft_id AND pc.master_stale
      ) pr
     WHERE a.spec_status = 'ACTIVE'
  ) x
 WHERE x.kind IS NOT NULL;

-- Varian CATALOG + supplier yang dipakai (sel tersambung, article aktif) di specsheet terbit terakhir tiap season
-- tetapi belum punya harga berlaku (fn_price_lookup per varian). Dikelompokkan per material + supplier.
CREATE VIEW v_worklist_price_gap AS
SELECT m.id AS material_id, m.name AS material_name, m.factory_id,
       s.id AS supplier_id, s.name AS supplier_name,
       count(DISTINCT g.variant_id)::integer AS variant_count,
       string_agg(DISTINCT v.code, ', ') AS codes,
       string_agg(DISTINCT g.model_name, ', ') AS models,
       bool_or(EXISTS (SELECT 1 FROM material_price mp
                        JOIN material_supplier ms ON ms.id = mp.material_supplier_id
                       WHERE ms.material_id = g.material_id AND ms.supplier_id = g.supplier_id
                         AND mp.variant_id = g.variant_id AND mp.status = 'PROPOSED')) AS has_pending
  FROM (
    SELECT DISTINCT bl.material_id, bl.supplier_id, bc.variant_id, pm.name AS model_name
      FROM specsheet sh
      JOIN product_model pm ON pm.id = sh.model_id
      JOIN specsheet_revision r ON r.id = fn_spec_latest_pub(sh.id)
      JOIN bom_line bl ON bl.revision_id = r.id AND bl.is_active AND bl.supplier_id IS NOT NULL
      JOIN bom_cell bc ON bc.bom_line_id = bl.id AND bc.variant_id IS NOT NULL
      JOIN revision_article ra ON ra.revision_id = r.id AND ra.article_id = bc.article_id AND ra.status = 'ACTIVE'
  ) g
  JOIN material m ON m.id = g.material_id AND m.price_method = 'CATALOG'
  JOIN supplier s ON s.id = g.supplier_id
  JOIN material_variant v ON v.id = g.variant_id
 WHERE NOT EXISTS (SELECT 1 FROM fn_price_lookup(g.variant_id, g.supplier_id))
 GROUP BY m.id, m.name, m.factory_id, s.id, s.name;

CREATE VIEW v_recent_published AS
SELECT 'SPECSHEET'::text AS doc_type, r.id AS revision_id,
       pm.id AS model_id, pm.name AS model_name, pm.factory_id, f.name AS factory_name,
       sh.id AS specsheet_id, sh.season,
       NULL::uuid AS article_id, NULL::text AS article_code, NULL::text AS colorway,
       r.stage, r.revision_no, r.published_at, r.published_by, NULL::text AS sync_status
  FROM specsheet sh
  JOIN product_model pm ON pm.id = sh.model_id
  JOIN factory f ON f.id = pm.factory_id
  JOIN specsheet_revision r ON r.id = fn_spec_latest_pub(sh.id)
UNION ALL
SELECT 'CBD', c.id,
       pm.id, pm.name, pm.factory_id, f.name,
       sh.id, sh.season,
       a.id, a.code, a.colorway,
       c.stage, c.revision_no, c.published_at, c.published_by, c.sync_status
  FROM article a
  JOIN specsheet sh ON sh.id = a.specsheet_id
  JOIN product_model pm ON pm.id = sh.model_id
  JOIN factory f ON f.id = pm.factory_id
  JOIN LATERAL (
    SELECT x.id, x.stage, x.revision_no, x.published_at, x.published_by, x.sync_status
      FROM cbd_revision x
     WHERE x.article_id = a.id AND x.status = 'PUBLISHED'
     ORDER BY x.stage_order DESC, x.revision_no DESC LIMIT 1
  ) c ON true;

-- ---------------------------------------------------------------- Pilihan bawaan (RESET_data_bisnis ikut mengosongkan)
INSERT INTO model_option (kind, value, sort_order)
SELECT 'GENDER', v.value, v.ord
  FROM (VALUES ('LAKI-LAKI', 1), ('PEREMPUAN', 2), ('UNISEX', 3)) AS v(value, ord)
 WHERE NOT EXISTS (SELECT 1 FROM model_option o WHERE o.kind = 'GENDER' AND o.value_key = fn_normalize(v.value));
INSERT INTO model_option (kind, value)
SELECT 'UKURAN', g::text
  FROM generate_series(35, 47) AS g
 WHERE NOT EXISTS (SELECT 1 FROM model_option o WHERE o.kind = 'UKURAN' AND o.value_key = g::text);

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'kolom product_model.code (harus 0)' AS cek, count(*)::text AS hasil FROM information_schema.columns
 WHERE table_name = 'product_model' AND column_name = 'code'
UNION ALL SELECT 'kolom baru model', string_agg(column_name, ', ' ORDER BY column_name) FROM information_schema.columns
 WHERE table_name = 'product_model' AND column_name IN ('factory_id', 'category_id', 'sizes', 'sample_size', 'name_key')
UNION ALL SELECT 'bom_line.thickness / bom_cell.variant_id',
       (SELECT count(*) FROM information_schema.columns WHERE table_name = 'bom_line' AND column_name = 'thickness') || ' / '
       || (SELECT count(*) FROM information_schema.columns WHERE table_name = 'bom_cell' AND column_name = 'variant_id')
UNION ALL SELECT 'uji label ukuran', fn_size_label(ARRAY[44, 37, 38, 39, 40, 42, 43])
UNION ALL SELECT 'view', string_agg(table_name, ', ' ORDER BY table_name) FROM information_schema.views
 WHERE table_name IN ('v_model', 'v_model_list', 'v_bom_grid', 'v_revision_checklist', 'v_worklist_spec',
                      'v_worklist_cbd', 'v_worklist_price_gap', 'v_recent_published');
