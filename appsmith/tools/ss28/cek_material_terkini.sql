-- Daftar material terkini untuk pemetaan SS28 Batch 3 (hasil: satu kolom JSON, simpan sebagai master/material.json)
-- Jalankan di DB Tools. Hanya SELECT, tidak mengubah data.
SELECT coalesce(jsonb_pretty(jsonb_agg(x ORDER BY x.name)), '[]') AS material_json
FROM (
  SELECT m.name,
         m.uom,
         m.category,
         m.is_process,
         m.status,
         (SELECT string_agg(DISTINCT v.thickness, ' | ' ORDER BY v.thickness)
            FROM material_variant v
           WHERE v.material_id = m.id AND v.thickness IS NOT NULL) AS dimensions,   -- Dimension ada di varian
         (SELECT string_agg(s.name, ' | ' ORDER BY s.name)
            FROM material_supplier ms JOIN supplier s ON s.id = ms.supplier_id
           WHERE ms.material_id = m.id AND ms.status <> 'INACTIVE') AS suppliers
    FROM material m
) x;
