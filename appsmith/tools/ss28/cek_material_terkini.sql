-- Daftar material terkini untuk pemetaan SS28 Batch 3 (hasil: satu kolom JSON, simpan sebagai master/material.json)
-- Jalankan di DB Tools. Hanya SELECT, tidak mengubah data.
SELECT coalesce(jsonb_pretty(jsonb_agg(x ORDER BY x.name, x.dimensions NULLS FIRST)), '[]') AS material_json
FROM (
  SELECT m.name,
         m.uom,
         m.category,
         m.is_process,
         m.status,
         m.thickness AS dimensions,      -- kolom DB 'thickness' = Dimension di aplikasi
         (SELECT string_agg(s.name, ' | ' ORDER BY s.name)
            FROM material_supplier ms JOIN supplier s ON s.id = ms.supplier_id
           WHERE ms.material_id = m.id AND ms.status <> 'INACTIVE') AS suppliers
    FROM material m
) x;
