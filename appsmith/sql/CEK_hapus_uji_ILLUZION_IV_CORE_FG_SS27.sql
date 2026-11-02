-- =====================================================================
-- DIAGNOSA SEBELUM HAPUS: data uji mandiri di ILLUZION IV CORE FG SS27
-- Hanya SELECT. Batas uji = 2026-10-28 03:37:04 UTC (lihat
-- steps/BASELINE_ILLUZION_IV_CORE_FG_SS27.md). Revisi: PROD rev 0 DRAFT
-- e9a655b7-8dfe-4e7d-8806-744d7e865eaf (draft firman, dipertahankan).
-- Jalankan per blok dan kirim hasilnya. Skrip hapus/kembalikan dibuat
-- sesudah ini, karena sesudah batas juga ada uji R20 bagian 4 (kode
-- otomatis, material UJI R20E) yang tidak boleh ikut terhapus sembarangan.
-- =====================================================================

-- D1. Ringkasan semua perubahan sesudah batas (per tabel, aksi, user)
SELECT entity, action, user_email, count(*) AS jumlah,
       min(created_at) AS pertama, max(created_at) AS terakhir
FROM audit_log
WHERE created_at >= timestamptz '2026-10-28 03:37:04+00'
GROUP BY entity, action, user_email
ORDER BY entity, action, user_email;

-- D2. Baris BOM revisi ini yang baru dibuat atau diubah sesudah batas
SELECT l.id AS bom_line_id, l.is_active,
       l.created_at >= timestamptz '2026-10-28 03:37:04+00' AS baru,
       coalesce(c.number, l.local_component_no) AS no_komponen,
       coalesce(c.name, l.local_component_name, l.sub_name) AS komponen,
       m.name AS material, l.thickness AS dimension, l.replaces_line_key,
       l.created_by, l.updated_by, l.updated_at
FROM bom_line l
JOIN material m ON m.id = l.material_id
LEFT JOIN component c ON c.id = l.component_id
WHERE l.revision_id = 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf'
  AND (l.created_at >= timestamptz '2026-10-28 03:37:04+00'
       OR l.updated_at >= timestamptz '2026-10-28 03:37:04+00')
ORDER BY l.sort_order, l.created_at;

-- D3. Master yang DIBUAT sesudah batas, dan di mana dipakai
--     dipakai_di_sini = revisi ILLUZION ini, dipakai_lain = revisi lain
SELECT 'material' AS jenis, m.id::text AS id, m.name AS nama, m.uom AS info,
       m.created_by, m.created_at,
       (SELECT count(*) FROM bom_line l WHERE l.material_id = m.id
          AND l.revision_id = 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf') AS dipakai_di_sini,
       (SELECT count(*) FROM bom_line l WHERE l.material_id = m.id
          AND l.revision_id <> 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf') AS dipakai_lain
FROM material m
WHERE m.created_at >= timestamptz '2026-10-28 03:37:04+00'
UNION ALL
SELECT 'variant', v.id::text, v.code, m.name || ' | ' || coalesce(v.thickness, '-') || ' | ' || v.color,
       v.created_by, v.created_at,
       (SELECT count(*) FROM bom_cell bc JOIN bom_line l ON l.id = bc.bom_line_id
         WHERE bc.variant_id = v.id AND l.revision_id = 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf'),
       (SELECT count(*) FROM bom_cell bc JOIN bom_line l ON l.id = bc.bom_line_id
         WHERE bc.variant_id = v.id AND l.revision_id <> 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf')
FROM material_variant v
JOIN material m ON m.id = v.material_id
WHERE v.created_at >= timestamptz '2026-10-28 03:37:04+00'
UNION ALL
SELECT 'component', c.id::text, c.number || ' ' || c.name, c.group_code || ' | ' || c.status,
       c.created_by, c.created_at,
       (SELECT count(*) FROM bom_line l WHERE l.component_id = c.id
          AND l.revision_id = 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf'),
       (SELECT count(*) FROM bom_line l WHERE l.component_id = c.id
          AND l.revision_id <> 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf')
FROM component c
WHERE c.created_at >= timestamptz '2026-10-28 03:37:04+00'
UNION ALL
SELECT 'material_supplier', ms.material_id || ':' || ms.supplier_id, m.name, s.name || ' | ' || ms.status,
       ms.created_by, ms.created_at,
       (SELECT count(*) FROM bom_line l WHERE l.material_id = ms.material_id AND l.supplier_id = ms.supplier_id
          AND l.revision_id = 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf'),
       (SELECT count(*) FROM bom_line l WHERE l.material_id = ms.material_id AND l.supplier_id = ms.supplier_id
          AND l.revision_id <> 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf')
FROM material_supplier ms
JOIN material m ON m.id = ms.material_id
JOIN supplier s ON s.id = ms.supplier_id
WHERE ms.created_at >= timestamptz '2026-10-28 03:37:04+00'
ORDER BY jenis, created_at;

-- D4. Master yang DIUBAH (bukan dibuat) sesudah batas: kolom apa yang berubah
--     (contoh: nomor komponen TOE BOX 290 -> 340, nama material)
SELECT a.created_at, a.user_email, a.entity, a.entity_id, k.key AS kolom,
       a.before_data -> k.key AS sebelum, a.after_data -> k.key AS sesudah
FROM audit_log a
CROSS JOIN LATERAL jsonb_object_keys(a.after_data) AS k(key)
WHERE a.created_at >= timestamptz '2026-10-28 03:37:04+00'
  AND a.action = 'UPDATE'
  AND a.entity IN ('material', 'material_variant', 'component', 'material_supplier', 'supplier', 'model_option')
  AND k.key NOT IN ('updated_at', 'updated_by')
  AND a.after_data -> k.key IS DISTINCT FROM a.before_data -> k.key
ORDER BY a.created_at, a.entity, a.entity_id;

-- D5. Revisi LAIN yang ikut berubah sesudah batas (bom_line bertambah 82 -> 125)
SELECT pm.name AS model, s.season, r.stage, r.revision_no, r.status,
       count(*) FILTER (WHERE l.created_at >= timestamptz '2026-10-28 03:37:04+00') AS baris_baru,
       count(*) FILTER (WHERE l.created_at < timestamptz '2026-10-28 03:37:04+00'
                          AND l.updated_at >= timestamptz '2026-10-28 03:37:04+00') AS baris_diubah,
       string_agg(DISTINCT coalesce(l.updated_by, l.created_by), ', ') AS oleh
FROM bom_line l
JOIN specsheet_revision r ON r.id = l.revision_id
JOIN specsheet s ON s.id = r.specsheet_id
JOIN product_model pm ON pm.id = s.model_id
WHERE l.updated_at >= timestamptz '2026-10-28 03:37:04+00'
   OR l.created_at >= timestamptz '2026-10-28 03:37:04+00'
GROUP BY pm.name, s.season, r.stage, r.revision_no, r.status
ORDER BY pm.name, s.season, r.stage;
