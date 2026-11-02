-- ============================================================================
-- RESET data bisnis KECUALI Master Options (14 Okt 2026)
-- ⚠️ MENGHAPUS DATA PERMANEN. Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Satu transaksi: kalau ada error, tidak ada yang terhapus.
--
-- Yang DIHAPUS : supplier, komponen, material (+ varian, supplier material, harga), model, specsheet,
--                article + lampiran, revisi specsheet + BOM, change log, CBD + baris + biaya, audit log.
-- Yang DISIMPAN: model_option (Master Options: KATEGORI, CONSTRUCTION, GENDER, UKURAN, LAST, OUTSOLE_MOLD),
--                semua user + password, sesi login, pabrik, role_permission, component_group,
--                stage_setting (faktor PO), semua struktur tabel / view / function / trigger.
-- Beda dengan RESET_data_bisnis.sql: file itu juga mengosongkan model_option.
-- Tabel aplikasi lain di database ini TIDAK disentuh (TRUNCATE tanpa CASCADE: kalau ada tabel lain yang
-- terhubung ke tabel proyek, skrip gagal dan tidak ada yang terhapus; hentikan dan hubungi pengembang).
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
      'material_price', 'material_supplier', 'material_variant', 'material',
      'component', 'supplier',
      'audit_log']) AS t
   WHERE to_regclass('public.' || t) IS NOT NULL;
  EXECUTE 'TRUNCATE TABLE ' || v_tables || ' RESTART IDENTITY';
END;
$$;

SELECT 'product_model' AS tabel, count(*) AS baris FROM product_model
UNION ALL SELECT 'material', count(*) FROM material
UNION ALL SELECT 'supplier', count(*) FROM supplier
UNION ALL SELECT 'cbd_revision', count(*) FROM cbd_revision
UNION ALL SELECT 'model_option (disimpan)', count(*) FROM model_option
UNION ALL SELECT 'app_user (disimpan)', count(*) FROM app_user
UNION ALL SELECT 'factory (disimpan)', count(*) FROM factory;
