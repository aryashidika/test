-- ============================================================================
-- Sisakan HANYA pabrik PT. UNIMITRA KHARISMA (14 Okt 2026)
-- ⚠️ MENGHAPUS DATA PERMANEN. Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Satu transaksi: kalau ada error, tidak ada yang terhapus.
--
-- Dihapus: pabrik lain (PT. PANATRADE CARAKA), user milik pabrik itu (sesi ikut terhapus lewat CASCADE),
--          pilihan LAST / OUTSOLE_MOLD milik pabrik itu di Master Options.
-- Pengaman: batal kalau masih ada model / material / varian yang memakai pabrik yang akan dihapus
--           (jalankan RESET_kecuali_master_options.sql dulu).
-- ============================================================================

DO $$
DECLARE
  v_keep uuid;
  v_n    integer;
BEGIN
  SELECT id INTO v_keep FROM factory WHERE upper(btrim(name)) = 'PT. UNIMITRA KHARISMA';
  IF v_keep IS NULL THEN
    RAISE EXCEPTION 'Pabrik PT. UNIMITRA KHARISMA tidak ditemukan. Dibatalkan.';
  END IF;

  SELECT (SELECT count(*) FROM product_model     WHERE factory_id <> v_keep)
       + (SELECT count(*) FROM material          WHERE factory_id IS NOT NULL AND factory_id <> v_keep)
       + (SELECT count(*) FROM material_variant  WHERE factory_id <> v_keep)
    INTO v_n;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'Masih ada % baris model/material/varian milik pabrik lain. Dibatalkan.', v_n;
  END IF;

  DELETE FROM app_user     WHERE factory_id IS NOT NULL AND factory_id <> v_keep;
  DELETE FROM model_option WHERE factory_id IS NOT NULL AND factory_id <> v_keep;
  DELETE FROM factory      WHERE id <> v_keep;
END;
$$;

SELECT name, status FROM factory;
