-- ============================================================================
-- RESET data bisnis — kosongkan data uji, TETAPI simpan user & pabrik (dipakai mulai R2, 8 Okt 2026)
-- ⚠️ MENGHAPUS DATA PERMANEN. Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Satu transaksi: kalau ada error, tidak ada yang terhapus.
--
-- Yang DIHAPUS : supplier, komponen, material (+ varian, supplier material, harga), pilihan model,
--                model, season, article + lampiran, revisi specsheet + BOM, change log, CBD + baris + biaya,
--                audit log.
-- Yang DISIMPAN: semua user + password, sesi login, pabrik, role_permission, component_group,
--                semua struktur tabel / view / function / trigger.
-- Beda dengan RESET_data_uji.sql: file itu juga menghapus semua user selain System Admin.
-- Tabel aplikasi lain di database ini TIDAK disentuh (TRUNCATE tanpa CASCADE: kalau ada tabel lain yang
-- terhubung ke tabel proyek, skrip gagal dan tidak ada yang terhapus — hentikan dan hubungi pengembang).
-- ============================================================================

DO $$
DECLARE
  v_tables text;
BEGIN
  -- Tabel R2+ hanya ikut dikosongkan kalau sudah ada (skrip ini juga dipakai sebelum R2 dijalankan)
  SELECT string_agg(t, ', ') INTO v_tables
    FROM unnest(ARRAY[
      'cbd_cost_item', 'cbd_line', 'cbd_revision',
      'change_log_attachment', 'change_log',
      'bom_cell', 'bom_line', 'revision_article', 'specsheet_revision',
      'article_attachment', 'article', 'specsheet', 'product_model',
      'material_price', 'material_supplier', 'material_variant', 'material',
      'model_option', 'component', 'supplier',
      'audit_log']) AS t
   WHERE to_regclass('public.' || t) IS NOT NULL;
  EXECUTE 'TRUNCATE TABLE ' || v_tables || ' RESTART IDENTITY';
END;
$$;

-- Pilihan model bawaan (GENDER, UKURAN) diisi lagi oleh R2_master.sql — jalankan ulang R2 bila perlu.
SELECT 'material' AS tabel, count(*) AS baris FROM material
UNION ALL SELECT 'supplier', count(*) FROM supplier
UNION ALL SELECT 'app_user (disimpan)', count(*) FROM app_user
UNION ALL SELECT 'factory (disimpan)', count(*) FROM factory;
