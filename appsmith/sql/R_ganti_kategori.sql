-- ============================================================================
-- Ganti pilihan Master Options KATEGORI (14 Okt 2026):
-- Football, Futsal, Running, Lifestyle, Street Soccer, Classic
-- Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF). Satu transaksi.
-- Yang dihapus: semua KATEGORI yang ada. Kind lain tidak disentuh.
-- Kategori bersifat bersama semua pabrik (factory_id kosong). Nilai otomatis jadi huruf kapital oleh trigger.
-- Pengaman: batal kalau masih ada model yang memakai kategori lama
--           (jalankan RESET_kecuali_master_options.sql dulu, atau ganti kategori di model tersebut).
-- ============================================================================

DO $$
DECLARE
  v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM product_model
   WHERE category_id IN (SELECT id FROM model_option WHERE kind = 'KATEGORI');
  IF v_n > 0 THEN
    RAISE EXCEPTION 'Masih ada % model yang memakai kategori lama. Dibatalkan.', v_n;
  END IF;

  DELETE FROM model_option WHERE kind = 'KATEGORI';

  INSERT INTO model_option (kind, factory_id, value, sort_order, status)
  SELECT 'KATEGORI', NULL, v.value, v.sort_order, 'ACTIVE'
    FROM (VALUES
      ('Football', 1),
      ('Futsal', 2),
      ('Running', 3),
      ('Lifestyle', 4),
      ('Street Soccer', 5),
      ('Classic', 6)
    ) AS v(value, sort_order);
END;
$$;

SELECT kind, value, sort_order FROM model_option WHERE kind = 'KATEGORI' ORDER BY sort_order;
