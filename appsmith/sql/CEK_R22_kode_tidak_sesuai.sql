-- R22: varian app yang kodenya BUKAN kode kamus untuk teksnya (kode kedua yang dibuang dari kamus). Hanya membaca.
-- Varian ini tidak diubah; hasil kosong = semua varian sama dengan kamus. Jalankan lewat z_run_sql di app "DB Tools".
SELECT 'Dimension' AS jenis, m.name AS material, v.code, v.thickness AS teks, d.code AS kode_kamus
  FROM material_variant v JOIN material m ON m.id = v.material_id
  JOIN code_dict_dimension d ON d.factory_id = v.factory_id AND d.thickness_key = v.thickness_key AND v.thickness_key <> ''
 WHERE length(v.code) = 10 AND substr(v.code, 5, 3) <> d.code
UNION ALL
SELECT 'Color', m.name, v.code, v.color, d.code
  FROM material_variant v JOIN material m ON m.id = v.material_id
  JOIN code_dict_color d ON d.factory_id = v.factory_id AND d.color_key = v.color_key
 WHERE length(v.code) = 10 AND substr(v.code, 8, 3) <> d.code
UNION ALL
SELECT 'Material', m.name, v.code, m.name, d.code
  FROM material_variant v JOIN material m ON m.id = v.material_id
  JOIN code_dict_material d ON d.factory_id = v.factory_id AND d.name_key = fn_tight_key(m.name)
 WHERE length(v.code) = 10 AND left(v.code, 4) <> d.code
 ORDER BY 1, 2, 3;
