-- CEK sebelum impor (hanya SELECT). Baris bermasalah tampil paling atas.
-- pabrik_unimitra harus 1. status: ada = sudah di database; baru = dibuat oleh impor; TIDAK ADA / SUDAH ADA / INACTIVE / UOM BEDA = impor akan ditolak.
-- kamus ERP (R22): baru = awalan disambung ke material baru; DIPAKAI MATERIAL LAIN / TIDAK ADA = awalan tidak disambung, kirim hasilnya.
WITH d AS (SELECT $j$__DATA__$j$::jsonb AS j),
f AS (SELECT id FROM factory WHERE status = 'ACTIVE' AND upper(name) LIKE '%UNIMITRA%'),
mdl AS (SELECT x FROM d, jsonb_array_elements(j->'models') x),
ln AS (SELECT m.x->>'name' AS model, l FROM mdl m, jsonb_array_elements(m.x->'lines') l),
newmat AS (SELECT fn_normalize(x->>'name') AS k, upper(x->>'uom') AS uom FROM d, jsonb_array_elements(j->'materials') x),
newcomp AS (SELECT upper(x->>'name') AS k FROM d, jsonb_array_elements(coalesce(j->'components', '[]'::jsonb)) x),
newopt AS (SELECT x->>'kind' AS kind, fn_normalize(x->>'value') AS k FROM d, jsonb_array_elements(j->'options') x),
need AS (
  SELECT DISTINCT 'model' AS jenis, x->>'name' AS nama, NULL::text AS info FROM mdl
  UNION SELECT DISTINCT 'material', l->>'m', l->>'u' FROM ln
  UNION SELECT DISTINCT 'supplier', l->>'p', NULL FROM ln
  UNION SELECT DISTINCT 'komponen', l->>'c', NULL FROM ln WHERE l->>'k' = 'MAIN'
  UNION SELECT DISTINCT 'link supplier', l->>'m' || ' + ' || (l->>'p'), l->>'u' FROM ln
  UNION SELECT DISTINCT 'kamus ERP', x->>'name', x->>'dict' FROM d, jsonb_array_elements(j->'materials') x WHERE x ? 'dict'
  UNION SELECT DISTINCT 'option ' || t.kind, x->>t.field, NULL
          FROM mdl, (VALUES ('KATEGORI', 'category'), ('CONSTRUCTION', 'construction'), ('GENDER', 'gender'),
                            ('LAST', 'last'), ('OUTSOLE_MOLD', 'outsole_mold')) t(kind, field)
),
st AS (
  SELECT n.*,
    CASE n.jenis
      WHEN 'model' THEN CASE WHEN EXISTS (SELECT 1 FROM product_model p WHERE p.name_key = fn_normalize(n.nama)
                                                AND p.factory_id IN (SELECT id FROM f))
                             THEN 'SUDAH ADA' ELSE 'baru' END
      WHEN 'material' THEN CASE
             WHEN EXISTS (SELECT 1 FROM material x WHERE x.name_key = fn_normalize(n.nama) AND x.uom = upper(n.info)
                             AND x.factory_id IN (SELECT id FROM f) AND x.status = 'ACTIVE') THEN 'ada'
             WHEN EXISTS (SELECT 1 FROM material x WHERE x.name_key = fn_normalize(n.nama) AND x.uom = upper(n.info)
                             AND x.factory_id IN (SELECT id FROM f)) THEN 'INACTIVE'
             WHEN EXISTS (SELECT 1 FROM material x WHERE x.name_key = fn_normalize(n.nama)
                             AND x.factory_id IN (SELECT id FROM f)) THEN 'UOM BEDA'
             WHEN EXISTS (SELECT 1 FROM newmat x WHERE x.k = fn_normalize(n.nama) AND x.uom = upper(n.info)) THEN 'baru'
             ELSE 'TIDAK ADA' END
      WHEN 'supplier' THEN CASE
             WHEN EXISTS (SELECT 1 FROM supplier s WHERE s.name_key = fn_normalize(n.nama) AND s.status = 'ACTIVE') THEN 'ada'
             WHEN EXISTS (SELECT 1 FROM supplier s WHERE s.name_key = fn_normalize(n.nama)) THEN 'INACTIVE'
             ELSE 'TIDAK ADA' END
      WHEN 'komponen' THEN CASE
             WHEN EXISTS (SELECT 1 FROM component c WHERE upper(c.name) = upper(n.nama) AND c.status = 'ACTIVE') THEN 'ada'
             WHEN EXISTS (SELECT 1 FROM newcomp c WHERE c.k = upper(n.nama)) THEN 'baru'
             ELSE 'TIDAK ADA' END
      WHEN 'link supplier' THEN CASE
             WHEN EXISTS (SELECT 1 FROM material_supplier ms JOIN material x ON x.id = ms.material_id
                            JOIN supplier s ON s.id = ms.supplier_id
                           WHERE x.name_key || ' + ' || s.name_key = fn_normalize(n.nama) AND x.uom = upper(n.info)
                             AND x.factory_id IN (SELECT id FROM f) AND ms.status = 'INACTIVE') THEN 'INACTIVE'
             WHEN EXISTS (SELECT 1 FROM material_supplier ms JOIN material x ON x.id = ms.material_id
                            JOIN supplier s ON s.id = ms.supplier_id
                           WHERE x.name_key || ' + ' || s.name_key = fn_normalize(n.nama) AND x.uom = upper(n.info)
                             AND x.factory_id IN (SELECT id FROM f)) THEN 'ada'
             ELSE 'baru' END
      WHEN 'kamus ERP' THEN CASE    -- R22: awalan kamus yang akan disambung ke material baru (kolom uom = kode awalan)
             WHEN NOT EXISTS (SELECT 1 FROM code_dict_material k WHERE k.code = n.info AND k.factory_id IN (SELECT id FROM f))
               THEN 'TIDAK ADA'
             WHEN EXISTS (SELECT 1 FROM code_dict_material k JOIN material x ON x.id = k.material_id
                           WHERE k.code = n.info AND k.factory_id IN (SELECT id FROM f) AND x.name_key = fn_normalize(n.nama))
               THEN 'ada'
             WHEN EXISTS (SELECT 1 FROM code_dict_material k WHERE k.code = n.info AND k.factory_id IN (SELECT id FROM f)
                             AND k.material_id IS NOT NULL) THEN 'DIPAKAI MATERIAL LAIN'
             ELSE 'baru' END
      ELSE CASE
             WHEN EXISTS (SELECT 1 FROM model_option o WHERE o.kind = substr(n.jenis, 8)
                             AND o.value_key = fn_normalize(n.nama) AND o.status = 'ACTIVE'
                             AND (o.factory_id IS NULL OR o.factory_id IN (SELECT id FROM f))) THEN 'ada'
             WHEN EXISTS (SELECT 1 FROM model_option o WHERE o.kind = substr(n.jenis, 8)
                             AND o.value_key = fn_normalize(n.nama)
                             AND (o.factory_id IS NULL OR o.factory_id IN (SELECT id FROM f))) THEN 'INACTIVE'
             WHEN EXISTS (SELECT 1 FROM newopt o WHERE o.kind = substr(n.jenis, 8) AND o.k = fn_normalize(n.nama)) THEN 'baru'
             ELSE 'TIDAK ADA' END
    END AS status
  FROM need n
)
SELECT status, jenis, nama, info AS uom,
       (SELECT count(*) FROM f) AS pabrik_unimitra
  FROM st
 ORDER BY CASE WHEN status IN ('TIDAK ADA', 'SUDAH ADA', 'INACTIVE', 'UOM BEDA', 'DIPAKAI MATERIAL LAIN') THEN 0 WHEN status = 'baru' THEN 1 ELSE 2 END,
          jenis, nama;
