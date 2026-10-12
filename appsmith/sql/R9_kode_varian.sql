-- ============================================================================
-- R9 — Material Code: isi otomatis + "kamus kode" tiga tingkat (12 Okt 2026, PLAN.md §6 R9). Jalankan SETELAH
-- R8_catatan_uji.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF). Aman diulang. Satu transaksi.
--
-- Tiga tingkat (keputusan user):
--   TOLAK      : Material Code lengkap dobel di pabrik · material + thickness + warna dobel (sel specsheet harus
--                menunjuk satu kode).
--   KONFIRMASI : bagian kode sudah punya ARTI LAIN di pabrik ini — kode thickness (karakter 5–7) tercatat untuk
--                thickness lain, kode warna (8–10) tercatat untuk warna lain (mis. W01 = WHITE, diketik untuk CREAM).
--                Ditolak kecuali fn_variant_save(..., p_confirm = true) ("Sudah saya cek, kode ini benar sesuai ERP").
--   INFO       : (hanya di form) warna/thickness sudah memakai kode lain (WHITE = W01, sekarang W10), awalan beda dari
--                varian lain material ini (CANVAS 6 OZ 209B / 2100), kode bukan 10 karakter.
-- - Trigger R8 trg_material_variant_prefix dihapus (awalan = info saja).
-- - fn_variant_code_suggest: usulan bagian kode (paling sering dipakai, seri = paling awal dicatat) untuk isi otomatis.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_cbd_price_propose(text,uuid,numeric,text,date,text)') IS NULL THEN
    RAISE EXCEPTION 'R8 belum terpasang. Jalankan sql/R8_catatan_uji.sql dulu.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Awalan: info saja
DROP TRIGGER IF EXISTS trg_material_variant_prefix ON material_variant;
DROP FUNCTION IF EXISTS fn_material_variant_prefix();

-- ---------------------------------------------------------------- Trigger varian: arti bagian kode = konfirmasi
-- Sama dengan R2b, kecuali bentrok arti kode thickness / warna: ditolak hanya bila tidak dikonfirmasi
-- (setelan transaksi app.variant_confirm = 'on', diisi fn_variant_save). Pesan diawali "Perlu konfirmasi:".
-- Catatan: kolom generated (color_key, thickness_key) masih NULL di BEFORE trigger -> hitung sendiri.
CREATE OR REPLACE FUNCTION fn_material_variant_check() RETURNS trigger
LANGUAGE plpgsql AS $$
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

  -- TOLAK: kode unik per pabrik
  SELECT v.code, m.name, v.color, v.thickness INTO v_other
    FROM material_variant v JOIN material m ON m.id = v.material_id
   WHERE v.factory_id = NEW.factory_id AND v.code = NEW.code AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material Code % sudah dipakai: % · % · %.',
      NEW.code, v_other.name, v_other.color, fn_thickness_label(v_other.thickness);
  END IF;

  -- TOLAK: satu kode per material + thickness + warna
  SELECT v.code INTO v_other
    FROM material_variant v
   WHERE v.material_id = NEW.material_id AND v.thickness_key = v_tkey AND v.color_key = v_ckey AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Varian % · % sudah ada di material ini (kode %). Bila ERP memang punya kode lain, bedakan nama warnanya sesuai ERP (mis. WHITE C).',
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
      RAISE EXCEPTION 'Perlu konfirmasi: kode thickness % sudah tercatat sebagai "%" (kode %), bukan "%". Periksa Material Code; bila memang sesuai ERP, centang konfirmasi lalu simpan.',
        substr(NEW.code, 5, 3), fn_thickness_label(v_other.thickness), v_other.code, fn_thickness_label(NEW.thickness);
    END IF;
    SELECT v.code, v.color INTO v_other
      FROM material_variant v
     WHERE v.factory_id = NEW.factory_id AND length(v.code) = 10 AND v.id <> NEW.id
       AND substr(v.code, 8, 3) = substr(NEW.code, 8, 3) AND v.color_key <> v_ckey
     ORDER BY v.created_at LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'Perlu konfirmasi: kode warna % sudah tercatat sebagai "%" (kode %), bukan "%". Periksa Material Code; bila memang sesuai ERP, centang konfirmasi lalu simpan.',
        substr(NEW.code, 8, 3), v_other.color, v_other.code, NEW.color;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------- Simpan varian: + p_confirm
-- Sama dengan R4 (kode/warna/thickness dikunci bila dipakai dokumen terbit) + p_confirm (konfirmasi arti kode).
DROP FUNCTION IF EXISTS fn_variant_save(text, uuid, uuid, text, text, text, text);
CREATE OR REPLACE FUNCTION fn_variant_save(
  p_token text, p_id uuid, p_material_id uuid, p_code text, p_color text, p_thickness text, p_status text,
  p_confirm boolean DEFAULT false
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
  PERFORM set_config('app.variant_confirm', CASE WHEN coalesce(p_confirm, false) THEN 'on' ELSE 'off' END, true);
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
    PERFORM set_config('app.variant_confirm', 'off', true);
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
  PERFORM set_config('app.variant_confirm', 'off', true);
  RETURN p_id;
END;
$$;

-- ---------------------------------------------------------------- Usulan Material Code
-- Daftar dipisah koma: paling sering dipakai lebih dulu, seri = paling awal dicatat. Isi otomatis memakai yang pertama.
DROP FUNCTION IF EXISTS fn_variant_code_suggest(text, uuid, text, text);
CREATE FUNCTION fn_variant_code_suggest(p_token text, p_material_id uuid, p_color text, p_thickness text)
RETURNS TABLE (prefixes text, thickness_codes text, color_codes text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_email   text := fn_auth(p_token, 'view_master');
  v_factory uuid;
  v_tkey    text := fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''));
  v_ckey    text := fn_normalize(upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g'))));
BEGIN
  SELECT factory_id INTO v_factory FROM material WHERE id = p_material_id;
  IF NOT FOUND OR NOT fn_can_see_factory(v_email, v_factory) THEN
    RETURN;
  END IF;
  RETURN QUERY SELECT
    (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
       SELECT left(v.code, 4) AS part, count(*) AS n, min(v.created_at) AS first_at FROM material_variant v
        WHERE v.material_id = p_material_id AND length(v.code) = 10 GROUP BY 1) x),
    (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
       SELECT substr(v.code, 5, 3) AS part, count(*) AS n, min(v.created_at) AS first_at FROM material_variant v
        WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v.thickness_key = v_tkey GROUP BY 1) x),
    (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
       SELECT substr(v.code, 8, 3) AS part, count(*) AS n, min(v.created_at) AS first_at FROM material_variant v
        WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v_ckey <> '' AND v.color_key = v_ckey GROUP BY 1) x);
END;
$$;

COMMIT;

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'R9 terpasang' AS cek,
       'awalan ditolak: ' || EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_material_variant_prefix')::text
       || ' · simpan varian + konfirmasi: ' || (to_regprocedure('fn_variant_save(text,uuid,uuid,text,text,text,text,boolean)') IS NOT NULL)::text
       || ' · usulan kode: ' || (to_regprocedure('fn_variant_code_suggest(text,uuid,text,text)') IS NOT NULL)::text
       AS hasil;
