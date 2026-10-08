-- ============================================================================
-- R2 — Master tanpa approval, Material Induk + Varian per pabrik, pilihan model
-- (keputusan user 8 Okt 2026, PLAN.md §2 "Revisi besar" & §6 R2)
-- Jalankan SETELAH R1_fondasi.sql dan RESET_data_bisnis.sql, lewat z_run_sql di app "DB Tools"
-- (Use prepared statements = OFF). Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
--
-- Aturan:
-- - Status master (supplier, komponen, material, varian, supplier material, pilihan) hanya ACTIVE / INACTIVE.
--   Tidak ada usulan/approval master lagi. Semua master diisi Vendor Spec (manage_master).
-- - Supplier & komponen BERSAMA semua pabrik: tambah bebas; ubah nama (komponen: nama/nomor/kelompok) ditolak
--   bila sudah dipakai di dokumen terbit pabrik mana pun; INACTIVE ditolak bila masih dipakai di draft.
-- - Material = INDUK milik satu pabrik (nama + kategori + UoM, unik per pabrik + UoM). Material Code, thickness,
--   dan warna pindah ke VARIAN (material_variant): kode diketik dari ERP pabrik (tanpa saran), unik per pabrik.
--   Kolom lama material.material_code & material.thickness dibiarkan kosong sampai R4 (masih dibaca view
--   specsheet/CBD lama), lalu dihapus di R4.
-- - Metode harga default CATALOG; hanya manage_price (Vendor CBD) yang mengubah.
-- - Supplier material (induk × supplier) tanpa approval; kolom supplier_material_code dihapus.
-- - Pilihan model (model_option): KATEGORI, CONSTRUCTION, GENDER, UKURAN bersama; LAST, OUTSOLE_MOLD per pabrik.
-- - "Cari dulu, baru buat": fn_similar_names (abaikan PT/CV/Tbk/UD, tanda baca, spasi).
-- - Masa transisi: Specsheet & CBD belum memakai varian (R4/R5) — jangan diuji di R2. Harga (R3) disembunyikan.
-- ============================================================================

-- ---------------------------------------------------------------- Pengaman
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('material_variant', 'color_key'), ('model_option', 'value_key')) AS t(tbl, col)
  LOOP
    IF to_regclass('public.' || r.tbl) IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = r.tbl AND column_name = r.col) THEN
      RAISE EXCEPTION 'Tabel "%" sudah ada di database dan bukan milik proyek ini. Hentikan dan hubungi pengembang.', r.tbl;
    END IF;
  END LOOP;
  IF to_regclass('public.factory') IS NULL THEN
    RAISE EXCEPTION 'Tabel factory belum ada. Jalankan R1_fondasi.sql dulu.';
  END IF;
  -- Material lama (tanpa pabrik) tidak bisa dipindah otomatis ke struktur induk + varian
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'material' AND column_name = 'factory_id')
     AND (EXISTS (SELECT 1 FROM material) OR EXISTS (SELECT 1 FROM supplier) OR EXISTS (SELECT 1 FROM component)) THEN
    RAISE EXCEPTION 'Masih ada data master uji dari sebelum R2. Jalankan RESET_data_bisnis.sql dulu (user & pabrik tetap tersimpan).';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Status master → ACTIVE / INACTIVE
-- CHECK lama (tanpa nama, berisi PROPOSED/APPROVED) diganti constraint bernama ck_<tabel>_status.
DO $$
DECLARE
  t text;
  r record;
BEGIN
  FOREACH t IN ARRAY ARRAY['supplier', 'component', 'material', 'material_supplier'] LOOP
    FOR r IN SELECT conname FROM pg_constraint
              WHERE conrelid = t::regclass AND contype = 'c'
                AND pg_get_constraintdef(oid) LIKE '%PROPOSED%'
    LOOP
      EXECUTE format('ALTER TABLE %I DROP CONSTRAINT %I', t, r.conname);
    END LOOP;
    EXECUTE format('UPDATE %I SET status = ''ACTIVE'' WHERE status IN (''PROPOSED'', ''APPROVED'')', t);
    EXECUTE format('ALTER TABLE %I DROP CONSTRAINT IF EXISTS %I', t, 'ck_' || t || '_status');
    EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I CHECK (status IN (''ACTIVE'', ''INACTIVE''))', t, 'ck_' || t || '_status');
    EXECUTE format('ALTER TABLE %I ALTER COLUMN status SET DEFAULT ''ACTIVE''', t);
  END LOOP;
END;
$$;

-- Izin lama yang sudah tidak dipakai
DELETE FROM role_permission WHERE permission IN ('manage_material_supplier', 'propose_master');

-- ---------------------------------------------------------------- "Cari dulu, baru buat"
-- Kunci pembanding nama: huruf kecil, tanpa PT/CV/Tbk/UD/Persero, tanpa tanda baca & spasi.
CREATE OR REPLACE FUNCTION fn_similar_key(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT regexp_replace(
           regexp_replace(lower(coalesce(p, '')), '\m(pt|cv|tbk|ud|persero)\M', ' ', 'g'),
           '[^a-z0-9]', '', 'g')
$$;

CREATE OR REPLACE FUNCTION fn_similar_match(p_key text, p_query text) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT p_key = p_query
      OR (length(p_query) >= 3 AND position(p_query IN p_key) > 0)
      OR (length(p_key) >= 3 AND position(p_key IN p_query) > 0)
$$;

-- Daftar nama mirip yang sudah ada (maks. 8). p_kind: SUPPLIER, COMPONENT, MATERIAL (pabrik user),
-- OPTION:<jenis> (mis. OPTION:LAST — per pabrik untuk LAST/OUTSOLE_MOLD). p_exclude = baris yang sedang diubah.
DROP FUNCTION IF EXISTS fn_similar_names(text, text, text, uuid);
CREATE FUNCTION fn_similar_names(p_token text, p_kind text, p_text text, p_exclude uuid)
RETURNS TABLE (ref_id uuid, label text, info text)
LANGUAGE plpgsql AS $$
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
    RAISE EXCEPTION 'Jenis pencarian % tidak dikenal.', p_kind;
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Pemakaian supplier / komponen di dokumen
-- Teks daftar dokumen (model season) yang memakai supplier/komponen; NULL = tidak dipakai.
-- p_published true = revisi terbit, false = draft. Semua pabrik (data bersama).
CREATE OR REPLACE FUNCTION fn_master_usage(p_kind text, p_id uuid, p_published boolean) RETURNS text
LANGUAGE sql STABLE AS $$
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
      SELECT pm.name || ' ' || sp.season || ' · ' || a.code || ' (CBD)'
        FROM cbd_line cl
        JOIN cbd_revision c ON c.id = cl.cbd_revision_id
        JOIN article a ON a.id = c.article_id
        JOIN specsheet sp ON sp.id = a.specsheet_id
        JOIN product_model pm ON pm.id = sp.model_id
       WHERE (c.status = 'PUBLISHED') = p_published
         AND CASE p_kind WHEN 'SUPPLIER' THEN cl.supplier_id WHEN 'COMPONENT' THEN cl.component_id END = p_id
    ) x
$$;

-- ---------------------------------------------------------------- Supplier (bersama)
CREATE OR REPLACE FUNCTION fn_supplier_save(p_token text, p_id uuid, p_name text, p_status text) RETURNS uuid
LANGUAGE plpgsql AS $$
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
    RAISE EXCEPTION 'Supplier tidak ditemukan.';
  END IF;
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Status supplier wajib dipilih (ACTIVE / INACTIVE).';
  END IF;
  IF fn_normalize(p_name) IS DISTINCT FROM v_old.name_key THEN
    v_used := fn_master_usage('SUPPLIER', p_id, true);
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION 'Nama supplier % tidak bisa diubah: sudah dipakai di dokumen terbit (%). Tambahkan supplier baru bila perlu.', v_old.name, v_used;
    END IF;
  END IF;
  IF p_status = 'INACTIVE' AND v_old.status <> 'INACTIVE' THEN
    v_used := fn_master_usage('SUPPLIER', p_id, false);
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION 'Supplier % masih dipakai di draft: %. Ganti supplier di draft itu dulu.', v_old.name, v_used;
    END IF;
  END IF;
  UPDATE supplier SET name = p_name, status = p_status, updated_by = v_email WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- ---------------------------------------------------------------- Komponen (bersama)
CREATE OR REPLACE FUNCTION fn_component_add(p_token text, p_group_code text, p_number integer, p_name text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_id    uuid;
BEGIN
  INSERT INTO component (number, name, group_code, status, updated_by)
  VALUES (p_number, p_name, p_group_code, 'ACTIVE', v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_component_save(
  p_token text, p_id uuid, p_group_code text, p_number integer, p_name text, p_status text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_old   component%ROWTYPE;
  v_used  text;
BEGIN
  SELECT * INTO v_old FROM component WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Komponen tidak ditemukan.';
  END IF;
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Status komponen wajib dipilih (ACTIVE / INACTIVE).';
  END IF;
  IF fn_normalize(p_name) IS DISTINCT FROM fn_normalize(v_old.name)
     OR p_number IS DISTINCT FROM v_old.number OR p_group_code IS DISTINCT FROM v_old.group_code THEN
    v_used := fn_master_usage('COMPONENT', p_id, true);
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION 'Nama, nomor, dan kelompok komponen % tidak bisa diubah: sudah dipakai di dokumen terbit (%).', v_old.number, v_used;
    END IF;
  END IF;
  IF p_status = 'INACTIVE' AND v_old.status <> 'INACTIVE' THEN
    v_used := fn_master_usage('COMPONENT', p_id, false);
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION 'Komponen % masih dipakai di draft: %. Ganti komponen di draft itu dulu.', v_old.number, v_used;
    END IF;
  END IF;
  UPDATE component
     SET group_code = p_group_code, number = p_number, name = p_name, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- ---------------------------------------------------------------- Material induk (per pabrik)
ALTER TABLE material ADD COLUMN IF NOT EXISTS factory_id uuid REFERENCES factory(id);
ALTER TABLE material ALTER COLUMN factory_id SET NOT NULL;            -- tabel kosong (dicek di atas)
ALTER TABLE material ALTER COLUMN material_code DROP NOT NULL;        -- kode pindah ke varian (kolom dihapus di R4)
ALTER TABLE material DROP CONSTRAINT IF EXISTS uq_material_code;
ALTER TABLE material DROP CONSTRAINT IF EXISTS uq_material_identity;
ALTER TABLE material ADD CONSTRAINT uq_material_identity UNIQUE (factory_id, name_key, uom);
CREATE INDEX IF NOT EXISTS idx_material_factory ON material (factory_id);

CREATE OR REPLACE FUNCTION fn_material_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other record;
BEGIN
  NEW.name     := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  NEW.category := btrim(regexp_replace(coalesce(NEW.category, ''), '\s+', ' ', 'g'));
  NEW.uom      := upper(btrim(coalesce(NEW.uom, '')));
  NEW.material_code := NULL;            -- kolom lama: kode ada di varian
  NEW.thickness     := NULL;            -- kolom lama: thickness ada di varian
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

DROP FUNCTION IF EXISTS fn_material_add(text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION fn_material_add(p_token text, p_name text, p_category text, p_uom text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email   text := fn_auth(p_token, 'manage_master');
  v_factory uuid := fn_user_factory(v_email);
  v_id      uuid;
BEGIN
  IF v_factory IS NULL THEN
    RAISE EXCEPTION 'Akun Anda belum terhubung ke pabrik. Minta System Admin mengisi pabrik Anda.';
  END IF;
  INSERT INTO material (factory_id, name, category, uom, price_method, status, updated_by)
  VALUES (v_factory, p_name, p_category, p_uom, 'CATALOG', 'ACTIVE', v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Satu form "Ubah Material": nama/kategori/UoM/status = manage_master (Vendor Spec),
-- metode harga = manage_price (Vendor CBD). Field yang tidak berubah boleh dikirim apa adanya.
DROP FUNCTION IF EXISTS fn_material_update(text, uuid, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION fn_material_update(
  p_token text, p_id uuid, p_name text, p_category text, p_uom text, p_status text, p_price_method text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_any(p_token, ARRAY['manage_master', 'manage_price']);
  v_master boolean := fn_has_perm(v_email, 'manage_master');
  v_price  boolean := fn_has_perm(v_email, 'manage_price');
  v_old    material%ROWTYPE;
BEGIN
  SELECT * INTO v_old FROM material WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Material tidak ditemukan.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_old.factory_id);
  IF NOT v_master AND (
       fn_normalize(p_name) IS DISTINCT FROM v_old.name_key
    OR fn_normalize(p_category) IS DISTINCT FROM fn_normalize(v_old.category)
    OR fn_normalize(p_uom) IS DISTINCT FROM fn_normalize(v_old.uom)
    OR p_status IS DISTINCT FROM v_old.status) THEN
    RAISE EXCEPTION 'Data dan status material hanya bisa diubah tim specsheet (Vendor Spec).';
  END IF;
  IF NOT v_price AND p_price_method IS DISTINCT FROM v_old.price_method THEN
    RAISE EXCEPTION 'Metode harga hanya bisa diubah tim CBD.';
  END IF;
  IF v_master AND coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Status material wajib dipilih (ACTIVE / INACTIVE).';
  END IF;
  IF v_price AND coalesce(p_price_method, '') NOT IN ('CATALOG', 'QUOTATION') THEN
    RAISE EXCEPTION 'Metode harga wajib dipilih.';
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
$$;

-- ---------------------------------------------------------------- Varian (thickness + warna + Material Code)
CREATE TABLE IF NOT EXISTS material_variant (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  material_id  uuid NOT NULL REFERENCES material(id),
  factory_id   uuid NOT NULL REFERENCES factory(id),      -- salinan dari induk (trigger), untuk kode unik per pabrik
  thickness_mm numeric(6,2) CHECK (thickness_mm IS NULL OR thickness_mm > 0),
  color        text NOT NULL CHECK (btrim(color) <> ''),
  color_key    text GENERATED ALWAYS AS (fn_normalize(color)) STORED,
  code         text NOT NULL CHECK (btrim(code) <> ''),
  status       text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_variant_code UNIQUE (factory_id, code),
  CONSTRAINT uq_variant_identity UNIQUE NULLS NOT DISTINCT (material_id, thickness_mm, color_key)
);
CREATE INDEX IF NOT EXISTS idx_variant_material ON material_variant (material_id);

-- "1.2 mm" / "tanpa thickness"
CREATE OR REPLACE FUNCTION fn_thickness_label(p numeric) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN p IS NULL THEN 'tanpa thickness' ELSE trim_scale(p)::text || ' mm' END
$$;

CREATE OR REPLACE FUNCTION fn_material_variant_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_factory uuid;
  v_other   record;
BEGIN
  NEW.code  := upper(btrim(regexp_replace(coalesce(NEW.code, ''), '\s+', ' ', 'g')));
  NEW.color := upper(btrim(regexp_replace(coalesce(NEW.color, ''), '\s+', ' ', 'g')));
  IF NEW.code = '' THEN
    RAISE EXCEPTION 'Material Code wajib diisi.';
  END IF;
  IF NEW.color = '' THEN
    RAISE EXCEPTION 'Warna wajib diisi.';
  END IF;
  IF NEW.thickness_mm IS NOT NULL AND NEW.thickness_mm <= 0 THEN
    RAISE EXCEPTION 'Thickness harus lebih besar dari 0 mm (kosongkan bila tidak ada).';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.material_id IS DISTINCT FROM OLD.material_id THEN
    RAISE EXCEPTION 'Varian tidak bisa dipindah ke material lain.';
  END IF;
  SELECT factory_id INTO v_factory FROM material WHERE id = NEW.material_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Material induk tidak ditemukan.';
  END IF;
  NEW.factory_id := v_factory;

  SELECT v.code, m.name, v.color, v.thickness_mm INTO v_other
    FROM material_variant v JOIN material m ON m.id = v.material_id
   WHERE v.factory_id = NEW.factory_id AND v.code = NEW.code AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material Code % sudah dipakai: % · % · %.',
      NEW.code, v_other.name, fn_thickness_label(v_other.thickness_mm), v_other.color;
  END IF;
  SELECT v.code INTO v_other
    FROM material_variant v
   WHERE v.material_id = NEW.material_id AND v.thickness_mm IS NOT DISTINCT FROM NEW.thickness_mm
     AND v.color_key = fn_normalize(NEW.color) AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Varian % · % sudah ada (kode %).', fn_thickness_label(NEW.thickness_mm), NEW.color, v_other.code;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_material_variant_check ON material_variant;
CREATE TRIGGER trg_material_variant_check BEFORE INSERT OR UPDATE ON material_variant
  FOR EACH ROW EXECUTE FUNCTION fn_material_variant_check();
SELECT fn_setup_table('material_variant');

-- Tambah banyak varian sekaligus: p_items = [{"thickness_mm": "1.2" | null, "color": "BLACK", "code": "..."}].
-- Semua atau tidak sama sekali (error di satu baris membatalkan semuanya).
CREATE OR REPLACE FUNCTION fn_variant_add(p_token text, p_material_id uuid, p_items jsonb) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_mat   material%ROWTYPE;
  v_item  jsonb;
  v_thick text;
  v_n     integer := 0;
BEGIN
  SELECT * INTO v_mat FROM material WHERE id = p_material_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Material tidak ditemukan.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_mat.factory_id);
  IF v_mat.status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Material % sudah INACTIVE — aktifkan dulu sebelum menambah varian.', v_mat.name;
  END IF;
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Tidak ada varian untuk disimpan.';
  END IF;
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_thick := nullif(btrim(replace(coalesce(v_item->>'thickness_mm', ''), ',', '.')), '');
    IF v_thick IS NOT NULL AND v_thick !~ '^[0-9]+(\.[0-9]+)?$' THEN
      RAISE EXCEPTION 'Thickness "%" bukan angka mm.', v_thick;
    END IF;
    INSERT INTO material_variant (material_id, factory_id, thickness_mm, color, code, updated_by)
    VALUES (p_material_id, v_mat.factory_id, v_thick::numeric, v_item->>'color', v_item->>'code', v_email);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- Ubah satu varian. R4: kode/warna/thickness dikunci bila varian sudah dipakai dokumen terbit.
CREATE OR REPLACE FUNCTION fn_variant_update(
  p_token text, p_id uuid, p_thickness_mm text, p_color text, p_code text, p_status text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_old   material_variant%ROWTYPE;
  v_thick text := nullif(btrim(replace(coalesce(p_thickness_mm, ''), ',', '.')), '');
BEGIN
  SELECT * INTO v_old FROM material_variant WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Varian tidak ditemukan.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_old.factory_id);
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Status varian wajib dipilih (ACTIVE / INACTIVE).';
  END IF;
  IF v_thick IS NOT NULL AND v_thick !~ '^[0-9]+(\.[0-9]+)?$' THEN
    RAISE EXCEPTION 'Thickness "%" bukan angka mm.', v_thick;
  END IF;
  UPDATE material_variant
     SET thickness_mm = v_thick::numeric, color = p_color, code = p_code, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- ---------------------------------------------------------------- Supplier material (induk × supplier)
CREATE OR REPLACE FUNCTION fn_material_supplier_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_sup supplier%ROWTYPE;
BEGIN
  IF NEW.status = 'INACTIVE' THEN
    NEW.is_preferred := false;          -- supplier nonaktif tidak bisa jadi supplier utama
  END IF;
  IF TG_OP = 'INSERT' OR NEW.supplier_id IS DISTINCT FROM OLD.supplier_id THEN
    SELECT * INTO v_sup FROM supplier WHERE id = NEW.supplier_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Supplier tidak ditemukan di Master Supplier.';
    END IF;
    IF v_sup.status = 'INACTIVE' THEN
      RAISE EXCEPTION 'Supplier % sudah dinonaktifkan di Master Supplier.', v_sup.name;
    END IF;
    IF EXISTS (SELECT 1 FROM material_supplier
                WHERE material_id = NEW.material_id AND supplier_id = NEW.supplier_id AND id <> NEW.id) THEN
      RAISE EXCEPTION 'Supplier % sudah terdaftar untuk material ini.', v_sup.name;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

ALTER TABLE material_supplier DROP COLUMN IF EXISTS supplier_material_code;   -- catatan user 8 Okt 2026

DROP FUNCTION IF EXISTS fn_link_save(text, uuid, uuid, uuid, text, boolean, text);
CREATE OR REPLACE FUNCTION fn_link_save(
  p_token text, p_link_id uuid, p_material_id uuid, p_supplier_id uuid, p_is_preferred boolean, p_status text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_old   material_supplier%ROWTYPE;
  v_mat   uuid;
  v_id    uuid;
  v_pref  boolean := coalesce(p_is_preferred, false);
BEGIN
  IF p_link_id IS NULL THEN
    IF p_supplier_id IS NULL THEN
      RAISE EXCEPTION 'Pilih supplier.';
    END IF;
    SELECT factory_id INTO v_mat FROM material WHERE id = p_material_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Material tidak ditemukan.';
    END IF;
    PERFORM fn_assert_factory(v_email, v_mat);
    INSERT INTO material_supplier (material_id, supplier_id, status, updated_by)
    VALUES (p_material_id, p_supplier_id, 'ACTIVE', v_email)
    RETURNING * INTO v_old;
  ELSE
    SELECT * INTO v_old FROM material_supplier WHERE id = p_link_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Supplier material tidak ditemukan.';
    END IF;
    PERFORM fn_assert_factory(v_email, (SELECT factory_id FROM material WHERE id = v_old.material_id));
    IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
      RAISE EXCEPTION 'Status supplier material wajib dipilih (ACTIVE / INACTIVE).';
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
$$;

-- Dipakai fungsi BOM: supplier dipilih di BOM -> link otomatis (ACTIVE) kalau belum ada.
CREATE OR REPLACE FUNCTION fn_ensure_link(p_material_id uuid, p_supplier_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
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
      RAISE EXCEPTION 'Supplier % sudah dinonaktifkan untuk material %. Pilih supplier lain.',
        (SELECT name FROM supplier WHERE id = p_supplier_id), (SELECT name FROM material WHERE id = p_material_id);
    END IF;
    RETURN v_link.id;
  END IF;
  INSERT INTO material_supplier (material_id, supplier_id, status, updated_by)
  VALUES (p_material_id, p_supplier_id, 'ACTIVE', nullif(current_setting('app.user', true), ''))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------- Daftar material (induk)
DROP VIEW IF EXISTS v_material_list;
CREATE VIEW v_material_list AS
SELECT m.id, m.factory_id, f.name AS factory_name, m.name, m.name_key, m.category, m.uom, m.price_method, m.status,
       m.updated_at, m.updated_by,
       coalesce(v.variants, 0)        AS variant_count,
       coalesce(v.active_variants, 0) AS active_variant_count,
       v.thicknesses,
       v.codes,
       coalesce(s.suppliers, 0)       AS supplier_count,
       s.preferred_supplier
  FROM material m
  JOIN factory f ON f.id = m.factory_id
  LEFT JOIN LATERAL (
    SELECT count(*) AS variants,
           count(*) FILTER (WHERE mv.status = 'ACTIVE') AS active_variants,
           string_agg(DISTINCT fn_thickness_label(mv.thickness_mm), ', ') AS thicknesses,
           string_agg(mv.code, ' ' ORDER BY mv.code) AS codes          -- untuk pencarian per kode
      FROM material_variant mv
     WHERE mv.material_id = m.id
  ) v ON true
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE ms.status = 'ACTIVE') AS suppliers,
           max(sp.name) FILTER (WHERE ms.is_preferred) AS preferred_supplier
      FROM material_supplier ms JOIN supplier sp ON sp.id = ms.supplier_id
     WHERE ms.material_id = m.id
  ) s ON true;

-- ---------------------------------------------------------------- Beranda Manager Costing: antrian harga saja
CREATE OR REPLACE VIEW v_worklist_admin AS
SELECT 'PRICE'::text AS kind, mp.id AS ref_id, ms.material_id,
       m.name AS title,
       'Supplier ' || s.name || coalesce(' · warna ' || nullif(btrim(mp.color), ''), '') AS detail,
       mp.currency || ' ' || trim_scale(mp.price)::text AS amount_text,
       mp.created_by AS proposed_by, mp.created_at AS proposed_at
  FROM material_price mp
  JOIN material_supplier ms ON ms.id = mp.material_supplier_id
  JOIN material m ON m.id = ms.material_id
  JOIN supplier s ON s.id = ms.supplier_id
 WHERE mp.status = 'PROPOSED';

-- ---------------------------------------------------------------- Pilihan model
CREATE TABLE IF NOT EXISTS model_option (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind       text NOT NULL CHECK (kind IN ('KATEGORI', 'CONSTRUCTION', 'GENDER', 'UKURAN', 'LAST', 'OUTSOLE_MOLD')),
  factory_id uuid REFERENCES factory(id),                  -- NULL = bersama semua pabrik
  value      text NOT NULL CHECK (btrim(value) <> ''),
  value_key  text GENERATED ALWAYS AS (fn_normalize(value)) STORED,
  sort_order integer,
  status     text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_model_option UNIQUE NULLS NOT DISTINCT (kind, factory_id, value_key),
  CONSTRAINT ck_model_option_scope CHECK ((kind IN ('LAST', 'OUTSOLE_MOLD')) = (factory_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_model_option_kind ON model_option (kind, factory_id);

-- true = pilihan per pabrik (LAST, OUTSOLE_MOLD); false = bersama
CREATE OR REPLACE FUNCTION fn_option_is_factory_kind(p_kind text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(p_kind, '') IN ('LAST', 'OUTSOLE_MOLD')
$$;

CREATE OR REPLACE FUNCTION fn_option_kind_label(p_kind text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_kind
    WHEN 'KATEGORI' THEN 'Kategori' WHEN 'CONSTRUCTION' THEN 'Construction' WHEN 'GENDER' THEN 'Gender'
    WHEN 'UKURAN' THEN 'Ukuran' WHEN 'LAST' THEN 'Last' WHEN 'OUTSOLE_MOLD' THEN 'Outsole mold'
    ELSE p_kind END
$$;

CREATE OR REPLACE FUNCTION fn_model_option_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other text;
BEGIN
  NEW.value := upper(btrim(regexp_replace(coalesce(NEW.value, ''), '\s+', ' ', 'g')));
  IF NEW.value = '' THEN
    RAISE EXCEPTION 'Nilai pilihan wajib diisi.';
  END IF;
  IF TG_OP = 'UPDATE' AND (NEW.kind IS DISTINCT FROM OLD.kind OR NEW.factory_id IS DISTINCT FROM OLD.factory_id) THEN
    RAISE EXCEPTION 'Jenis dan pabrik pilihan tidak bisa diubah.';
  END IF;
  IF NEW.kind = 'UKURAN' THEN
    IF NEW.value !~ '^[0-9]{1,2}$' OR NEW.value::integer < 1 THEN
      RAISE EXCEPTION 'Ukuran harus angka bulat (mis. 40), tanpa setengah ukuran.';
    END IF;
    NEW.value := NEW.value::integer::text;          -- "040" -> "40"
    NEW.sort_order := NEW.value::integer;           -- ukuran selalu urut angka
  END IF;
  SELECT value INTO v_other FROM model_option
   WHERE kind = NEW.kind AND factory_id IS NOT DISTINCT FROM NEW.factory_id
     AND value_key = fn_normalize(NEW.value) AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION '% "%" sudah ada.', fn_option_kind_label(NEW.kind), v_other;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_model_option_check ON model_option;
CREATE TRIGGER trg_model_option_check BEFORE INSERT OR UPDATE ON model_option
  FOR EACH ROW EXECUTE FUNCTION fn_model_option_check();
SELECT fn_setup_table('model_option');

-- Tambah (p_id NULL) / ubah pilihan. LAST & OUTSOLE_MOLD otomatis milik pabrik user.
-- R4: INACTIVE / ubah nilai dicek terhadap model yang memakainya.
CREATE OR REPLACE FUNCTION fn_option_save(
  p_token text, p_id uuid, p_kind text, p_value text, p_sort_order integer, p_status text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email   text := fn_auth(p_token, 'manage_master');
  v_factory uuid := fn_user_factory(v_email);
  v_old     model_option%ROWTYPE;
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
  UPDATE model_option SET value = p_value, sort_order = p_sort_order, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- Isi awal (hanya yang belum ada; aman diulang)
INSERT INTO model_option (kind, value, sort_order)
SELECT 'GENDER', v.value, v.ord
  FROM (VALUES ('LAKI-LAKI', 1), ('PEREMPUAN', 2), ('UNISEX', 3)) AS v(value, ord)
 WHERE NOT EXISTS (SELECT 1 FROM model_option o WHERE o.kind = 'GENDER' AND o.value_key = fn_normalize(v.value));
INSERT INTO model_option (kind, value)
SELECT 'UKURAN', g::text
  FROM generate_series(35, 47) AS g
 WHERE NOT EXISTS (SELECT 1 FROM model_option o WHERE o.kind = 'UKURAN' AND o.value_key = g::text);

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'status supplier/komponen/material/link' AS cek,
       (SELECT string_agg(DISTINCT pg_get_constraintdef(oid), ' | ') FROM pg_constraint
         WHERE conname IN ('ck_supplier_status', 'ck_component_status', 'ck_material_status', 'ck_material_supplier_status')) AS hasil
UNION ALL SELECT 'izin lama (harus 0)', count(*)::text FROM role_permission
           WHERE permission IN ('manage_material_supplier', 'propose_master')
UNION ALL SELECT 'kolom supplier_material_code (harus 0)', count(*)::text FROM information_schema.columns
           WHERE table_name = 'material_supplier' AND column_name = 'supplier_material_code'
UNION ALL SELECT 'kolom material.factory_id', count(*)::text FROM information_schema.columns
           WHERE table_name = 'material' AND column_name = 'factory_id'
UNION ALL SELECT 'tabel material_variant', coalesce(to_regclass('public.material_variant')::text, 'TIDAK ADA')
UNION ALL SELECT 'pilihan GENDER / UKURAN', (SELECT count(*) FROM model_option WHERE kind = 'GENDER') || ' / '
                                           || (SELECT count(*) FROM model_option WHERE kind = 'UKURAN')
UNION ALL SELECT 'uji nama mirip', fn_similar_key('PT. Maju-Jaya Tbk');
