-- Cek data (hanya baca, tidak mengubah apa pun). Jalankan di DB Tools, satu blok per kali.

-- 1. Jumlah baris per tabel utama (harus sama seperti sebelum R15 dipasang)
SELECT 'factory' AS tabel, count(*) AS jumlah FROM factory
UNION ALL SELECT 'app_user', count(*) FROM app_user
UNION ALL SELECT 'supplier', count(*) FROM supplier
UNION ALL SELECT 'component', count(*) FROM component
UNION ALL SELECT 'material', count(*) FROM material
UNION ALL SELECT 'material_variant', count(*) FROM material_variant
UNION ALL SELECT 'material_supplier', count(*) FROM material_supplier
UNION ALL SELECT 'material_price', count(*) FROM material_price
UNION ALL SELECT 'model_option', count(*) FROM model_option
UNION ALL SELECT 'product_model', count(*) FROM product_model
UNION ALL SELECT 'article', count(*) FROM article
UNION ALL SELECT 'specsheet', count(*) FROM specsheet
UNION ALL SELECT 'specsheet_revision', count(*) FROM specsheet_revision
UNION ALL SELECT 'bom_line', count(*) FROM bom_line
UNION ALL SELECT 'cbd_revision', count(*) FROM cbd_revision
UNION ALL SELECT 'cbd_line', count(*) FROM cbd_line
UNION ALL SELECT 'change_log', count(*) FROM change_log
UNION ALL SELECT 'audit_log', count(*) FROM audit_log;

-- 2. R15 sudah terpasang? (harus: Production / ACTIVE,... dalam bahasa Inggris)
SELECT fn_stage_label('PROD') AS stage_label,
       (SELECT string_agg(DISTINCT state, ', ' ORDER BY state) FROM v_material_price) AS price_states;

-- 3. Login terakhir per user (user yang dipakai uji harus punya jam login hari ini)
SELECT email, role, is_active, last_login_at FROM app_user ORDER BY last_login_at DESC NULLS LAST;

-- 4. Contoh isi: 10 model terbaru
SELECT id, name, updated_at FROM product_model ORDER BY updated_at DESC LIMIT 10;
