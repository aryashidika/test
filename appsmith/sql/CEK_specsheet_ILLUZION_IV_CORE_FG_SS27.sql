-- =====================================================================
-- CEK SEBELUM UJI: specsheet ILLUZION IV CORE FG, season SS27
-- Hanya SELECT (tidak mengubah data). Jalankan per blok, simpan hasilnya
-- (Download CSV) untuk dibandingkan sesudah uji dan untuk skrip hapus.
-- =====================================================================

-- 0. Waktu snapshot (catat, dipakai sebagai batas "data dibuat sesudah ini")
SELECT now() AS waktu_snapshot;

-- 1. Model, specsheet, dan semua revisi per stage
SELECT pm.name AS model, pm.id AS model_id, s.season, s.id AS specsheet_id,
       r.stage, r.revision_no, r.status, r.id AS revision_id,
       r.created_at, r.created_by, r.published_at, r.published_by,
       (SELECT count(*) FROM bom_line l WHERE l.revision_id = r.id AND l.is_active) AS jml_baris_aktif
FROM product_model pm
JOIN specsheet s ON s.model_id = pm.id AND s.season = 'SS27'
LEFT JOIN specsheet_revision r ON r.specsheet_id = s.id
WHERE fn_normalize(pm.name) = fn_normalize('ILLUZION IV CORE FG')
ORDER BY r.stage_order, r.revision_no;

-- 2. Article per revisi (status ACTIVE / tidak)
SELECT r.stage, r.revision_no, a.code AS article_no, a.colorway, ra.status AS status_article,
       a.id AS article_id, a.created_at, a.created_by
FROM product_model pm
JOIN specsheet s ON s.model_id = pm.id AND s.season = 'SS27'
JOIN specsheet_revision r ON r.specsheet_id = s.id
JOIN revision_article ra ON ra.revision_id = r.id
JOIN article a ON a.id = ra.article_id
WHERE fn_normalize(pm.name) = fn_normalize('ILLUZION IV CORE FG')
ORDER BY r.stage_order, r.revision_no, a.code NULLS LAST, a.colorway;

-- 3. Isi BOM per revisi (seperti grid), satu baris per komponen
SELECT r.stage, r.revision_no, g.display_no AS no, g.display_name AS komponen,
       g.material_name AS material, g.thickness AS dimension, g.uom,
       g.material_code, g.supplier_name AS supplier, g.process,
       g.yellow AS sel_tanpa_kode, g.id AS bom_line_id
FROM product_model pm
JOIN specsheet s ON s.model_id = pm.id AND s.season = 'SS27'
JOIN specsheet_revision r ON r.specsheet_id = s.id
JOIN v_bom_grid g ON g.revision_id = r.id
WHERE fn_normalize(pm.name) = fn_normalize('ILLUZION IV CORE FG')
ORDER BY r.stage_order, r.revision_no, g.group_sort, g.group_no, g.is_sub, g.sub_seq;

-- 4. Warna dan kode per sel (komponen x article)
SELECT r.stage, r.revision_no, g.display_no AS no, g.display_name AS komponen,
       g.material_name AS material, a.code AS article_no, a.colorway,
       bc.color AS warna, v.code AS kode_varian
FROM product_model pm
JOIN specsheet s ON s.model_id = pm.id AND s.season = 'SS27'
JOIN specsheet_revision r ON r.specsheet_id = s.id
JOIN v_bom_grid g ON g.revision_id = r.id
JOIN bom_cell bc ON bc.bom_line_id = g.id
JOIN article a ON a.id = bc.article_id
LEFT JOIN material_variant v ON v.id = bc.variant_id
WHERE fn_normalize(pm.name) = fn_normalize('ILLUZION IV CORE FG')
ORDER BY r.stage_order, r.revision_no, g.group_sort, g.group_no, g.is_sub, g.sub_seq, a.code;

-- 5. Jumlah data master (untuk lihat apa yang bertambah sesudah uji)
SELECT 'material' AS tabel, count(*) AS jumlah, max(created_at) AS terakhir_dibuat FROM material
UNION ALL SELECT 'material_variant', count(*), max(created_at) FROM material_variant
UNION ALL SELECT 'material_supplier', count(*), max(created_at) FROM material_supplier
UNION ALL SELECT 'material_price', count(*), max(created_at) FROM material_price
UNION ALL SELECT 'supplier', count(*), max(created_at) FROM supplier
UNION ALL SELECT 'component', count(*), max(created_at) FROM component
UNION ALL SELECT 'product_model', count(*), max(created_at) FROM product_model
UNION ALL SELECT 'specsheet', count(*), max(created_at) FROM specsheet
UNION ALL SELECT 'specsheet_revision', count(*), max(created_at) FROM specsheet_revision
UNION ALL SELECT 'article', count(*), max(created_at) FROM article
UNION ALL SELECT 'bom_line', count(*), max(created_at) FROM bom_line
UNION ALL SELECT 'cbd_revision', count(*), max(created_at) FROM cbd_revision;
