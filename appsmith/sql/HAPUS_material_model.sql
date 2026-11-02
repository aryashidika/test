-- ============================================================================
-- HAPUS semua material dan model (20 Okt 2026, persiapan uji R16 langkah 0.1: mat = 0, model = 0)
-- ⚠️ MENGHAPUS DATA PERMANEN. Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Satu transaksi: kalau ada error, tidak ada yang terhapus.
--
-- Yang DIHAPUS : material (+ varian, supplier material, harga), model, season (specsheet), article + lampiran,
--                revisi specsheet + BOM, change log + gambar, CBD + baris + biaya.
-- Yang DISIMPAN: supplier, komponen (+ kelompok), Master Options (model_option), user + password + sesi, pabrik,
--                role_permission, stage_setting, audit log (riwayat lama tetap), semua struktur tabel / view / function.
-- Beda dengan RESET_kecuali_master_options.sql: file itu juga menghapus supplier, komponen, dan audit log.
-- Tabel aplikasi lain di database ini TIDAK disentuh (TRUNCATE tanpa CASCADE: kalau ada tabel lain yang terhubung,
-- skrip gagal dan tidak ada yang terhapus; hentikan dan hubungi pengembang).
-- ============================================================================

DO $$
DECLARE
  v_tables text;
BEGIN
  SELECT string_agg(t, ', ') INTO v_tables
    FROM unnest(ARRAY[
      'cbd_cost_item', 'cbd_line', 'cbd_revision',
      'change_log_attachment', 'change_log',
      'bom_cell', 'bom_line', 'revision_article', 'specsheet_revision',
      'article_attachment', 'article', 'specsheet', 'product_model',
      'material_price', 'material_supplier', 'material_variant', 'material']) AS t
   WHERE to_regclass('public.' || t) IS NOT NULL;
  EXECUTE 'TRUNCATE TABLE ' || v_tables;
END;
$$;

SELECT (SELECT count(*) FROM material) AS mat, (SELECT count(*) FROM product_model) AS model,
       (SELECT count(*) FROM supplier) AS sup, (SELECT count(*) FROM component) AS komp,
       (SELECT count(*) FROM model_option) AS opt;
