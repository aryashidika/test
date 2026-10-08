-- ============================================================================
-- R2b — Revisi varian material setelah melihat data ERP (MATERIAL CODE.xlsx, keputusan user 8 Okt 2026)
-- Jalankan SETELAH R2_master.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan. Data varian uji tetap disimpan
-- (thickness angka lama diubah jadi teks, mis. 1.2 -> "1.2MM").
--
-- Aturan:
-- - Varian ditambah SATU per satu (Material Code, warna, thickness) — tidak ada lagi kombinasi.
-- - Thickness = TEKS persis ERP (44", 1.2MMX54", SIZE 37-39); kosong atau "." = tanpa thickness.
-- - Material Code 10 karakter (ERP): 4 depan = jenis material, 3 tengah = thickness, 3 akhir = warna.
--   Di satu pabrik, 3 tengah yang sama harus berarti thickness yang sama dan 3 akhir yang sama harus
--   berarti warna yang sama (bentrok ditolak). 4 depan tidak dicek (hanya peringatan di form).
--   Kode yang panjangnya bukan 10 tidak dicek per bagian.
-- - Material + thickness + warna yang sama dengan kode lain ditolak (kasus T-160 WHITE 44").
-- ============================================================================

-- ---------------------------------------------------------------- Pengaman
DO $$
BEGIN
  IF to_regclass('public.material_variant') IS NULL THEN
    RAISE EXCEPTION 'Tabel material_variant belum ada. Jalankan R2_master.sql dulu.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Thickness angka -> teks
DROP VIEW IF EXISTS v_material_list;                 -- dibuat ulang di bawah (memakai fn_thickness_label)
ALTER TABLE material_variant ADD COLUMN IF NOT EXISTS thickness text;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_name = 'material_variant' AND column_name = 'thickness_mm') THEN
    UPDATE material_variant SET thickness = trim_scale(thickness_mm)::text || 'MM'
     WHERE thickness_mm IS NOT NULL AND thickness IS NULL;
    ALTER TABLE material_variant DROP CONSTRAINT IF EXISTS uq_variant_identity;
    ALTER TABLE material_variant DROP COLUMN thickness_mm;
  END IF;
END;
$$;
ALTER TABLE material_variant ADD COLUMN IF NOT EXISTS
  thickness_key text GENERATED ALWAYS AS (fn_normalize(coalesce(thickness, ''))) STORED;
ALTER TABLE material_variant DROP CONSTRAINT IF EXISTS uq_variant_identity;
ALTER TABLE material_variant ADD CONSTRAINT uq_variant_identity UNIQUE (material_id, thickness_key, color_key);
CREATE INDEX IF NOT EXISTS idx_variant_code_parts ON material_variant (factory_id, substr(code, 5, 3), substr(code, 8, 3));

DROP FUNCTION IF EXISTS fn_thickness_label(numeric);
CREATE OR REPLACE FUNCTION fn_thickness_label(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT coalesce(nullif(btrim(coalesce(p, '')), ''), 'tanpa thickness')
$$;

-- "." / "-" / kosong = tanpa thickness
CREATE OR REPLACE FUNCTION fn_clean_thickness(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN btrim(coalesce(p, '')) IN ('', '.', '-') THEN NULL
              ELSE upper(btrim(regexp_replace(p, '\s+', ' ', 'g'))) END
$$;

-- ---------------------------------------------------------------- Trigger varian
-- Catatan: kolom generated (color_key, thickness_key) masih NULL di BEFORE trigger -> hitung sendiri.
CREATE OR REPLACE FUNCTION fn_material_variant_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_factory uuid;
  v_other   record;
  v_tkey    text;
  v_ckey    text;
BEGIN
  NEW.code      := upper(btrim(regexp_replace(coalesce(NEW.code, ''), '\s+', ' ', 'g')));
  NEW.color     := upper(btrim(regexp_replace(coalesce(NEW.color, ''), '\s+', ' ', 'g')));
  NEW.thickness := fn_clean_thickness(NEW.thickness);
  v_tkey := fn_normalize(coalesce(NEW.thickness, ''));
  v_ckey := fn_normalize(NEW.color);
  IF NEW.code = '' THEN
    RAISE EXCEPTION 'Material Code wajib diisi.';
  END IF;
  IF NEW.color = '' THEN
    RAISE EXCEPTION 'Warna wajib diisi.';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.material_id IS DISTINCT FROM OLD.material_id THEN
    RAISE EXCEPTION 'Varian tidak bisa dipindah ke material lain.';
  END IF;
  SELECT factory_id INTO v_factory FROM material WHERE id = NEW.material_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Material induk tidak ditemukan.';
  END IF;
  NEW.factory_id := v_factory;

  -- kode unik per pabrik
  SELECT v.code, m.name, v.color, v.thickness INTO v_other
    FROM material_variant v JOIN material m ON m.id = v.material_id
   WHERE v.factory_id = NEW.factory_id AND v.code = NEW.code AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material Code % sudah dipakai: % · % · %.',
      NEW.code, v_other.name, v_other.color, fn_thickness_label(v_other.thickness);
  END IF;

  -- satu kode per material + thickness + warna
  SELECT v.code INTO v_other
    FROM material_variant v
   WHERE v.material_id = NEW.material_id AND v.thickness_key = v_tkey AND v.color_key = v_ckey AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Varian % · % sudah ada di material ini (kode %).', NEW.color, fn_thickness_label(NEW.thickness), v_other.code;
  END IF;

  -- bagian kode ERP (10 karakter): 3 tengah = thickness, 3 akhir = warna, konsisten di satu pabrik
  IF length(NEW.code) = 10 THEN
    SELECT v.code, v.thickness INTO v_other
      FROM material_variant v
     WHERE v.factory_id = NEW.factory_id AND length(v.code) = 10 AND v.id <> NEW.id
       AND substr(v.code, 5, 3) = substr(NEW.code, 5, 3) AND v.thickness_key <> v_tkey
     LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'Kode thickness % sudah tercatat sebagai "%" (kode %). Thickness yang diisi: "%".',
        substr(NEW.code, 5, 3), fn_thickness_label(v_other.thickness), v_other.code, fn_thickness_label(NEW.thickness);
    END IF;
    SELECT v.code, v.color INTO v_other
      FROM material_variant v
     WHERE v.factory_id = NEW.factory_id AND length(v.code) = 10 AND v.id <> NEW.id
       AND substr(v.code, 8, 3) = substr(NEW.code, 8, 3) AND v.color_key <> v_ckey
     LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'Kode warna % sudah tercatat sebagai "%" (kode %). Warna yang diisi: "%".',
        substr(NEW.code, 8, 3), v_other.color, v_other.code, NEW.color;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------- Simpan varian (satu baris)
DROP FUNCTION IF EXISTS fn_variant_add(text, uuid, jsonb);
DROP FUNCTION IF EXISTS fn_variant_update(text, uuid, text, text, text, text);
-- p_id NULL = tambah ke p_material_id; selain itu ubah. R4: kode/warna/thickness dikunci bila dipakai dokumen terbit.
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
  UPDATE material_variant
     SET code = p_code, color = p_color, thickness = p_thickness, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- Bantuan form: arti 3 tengah / 3 akhir kode yang sudah tercatat di pabrik material ini, dan awalan
-- (4 depan) varian lain di material yang sama (untuk peringatan, tidak memblokir).
DROP FUNCTION IF EXISTS fn_variant_code_hint(text, uuid, text, uuid);
CREATE FUNCTION fn_variant_code_hint(p_token text, p_material_id uuid, p_code text, p_exclude uuid)
RETURNS TABLE (code text, thickness_known boolean, thickness text, thickness_ref text,
               color_known boolean, color text, color_ref text, other_prefixes text)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  v_email   text := fn_auth(p_token, 'view_master');
  v_factory uuid;
  v_code    text := upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g')));
  v_t       record;
  v_c       record;
BEGIN
  SELECT factory_id INTO v_factory FROM material WHERE id = p_material_id;
  IF NOT FOUND OR NOT fn_can_see_factory(v_email, v_factory) OR length(v_code) <> 10 THEN
    RETURN;
  END IF;
  SELECT mv.code, mv.thickness INTO v_t FROM material_variant mv
   WHERE mv.factory_id = v_factory AND length(mv.code) = 10 AND mv.id IS DISTINCT FROM p_exclude
     AND substr(mv.code, 5, 3) = substr(v_code, 5, 3)
   ORDER BY mv.created_at LIMIT 1;
  SELECT mv.code, mv.color INTO v_c FROM material_variant mv
   WHERE mv.factory_id = v_factory AND length(mv.code) = 10 AND mv.id IS DISTINCT FROM p_exclude
     AND substr(mv.code, 8, 3) = substr(v_code, 8, 3)
   ORDER BY mv.created_at LIMIT 1;
  RETURN QUERY SELECT
    v_code,
    v_t.code IS NOT NULL, v_t.thickness, v_t.code,
    v_c.code IS NOT NULL, v_c.color, v_c.code,
    (SELECT string_agg(DISTINCT left(mv.code, 4), ', ') FROM material_variant mv
      WHERE mv.material_id = p_material_id AND mv.id IS DISTINCT FROM p_exclude
        AND length(mv.code) = 10 AND left(mv.code, 4) <> left(v_code, 4));
END;
$$;

-- ---------------------------------------------------------------- Daftar material (induk) — sama dengan R2, thickness teks
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
           string_agg(DISTINCT fn_thickness_label(mv.thickness), ', ') AS thicknesses,
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

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'kolom thickness (teks)' AS cek, data_type AS hasil FROM information_schema.columns
 WHERE table_name = 'material_variant' AND column_name = 'thickness'
UNION ALL SELECT 'kolom thickness_mm (harus 0)', count(*)::text FROM information_schema.columns
 WHERE table_name = 'material_variant' AND column_name = 'thickness_mm'
UNION ALL SELECT 'fn_variant_save', count(*)::text FROM pg_proc WHERE proname = 'fn_variant_save'
UNION ALL SELECT 'fn_variant_add (harus 0)', count(*)::text FROM pg_proc WHERE proname IN ('fn_variant_add', 'fn_variant_update')
UNION ALL SELECT 'uji thickness "."', coalesce(fn_clean_thickness('.'), '(kosong)');
