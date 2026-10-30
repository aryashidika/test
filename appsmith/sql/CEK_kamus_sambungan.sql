-- ============================================================================
-- CEK sambungan material aplikasi ke kamus kode ERP (29 Okt 2026)
-- Hanya membaca, tidak mengubah apa pun.
-- Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF),
-- lalu kirim hasilnya (semua baris) sebagai Excel / CSV.
--
-- Satu baris per varian. Material tanpa varian tetap muncul (kolom kode kosong).
-- Dipakai untuk:
--   - prefix material diambil dari 4 huruf pertama kode varian (pertanyaan A2, A3, K-7)
--   - tulisan Dimension dan warna di aplikasi dibandingkan dengan kamus (U2)
-- ============================================================================
WITH f AS (SELECT id FROM factory WHERE name ILIKE '%UNIMITRA%')
SELECT m.name                                   AS material,
       m.uom,
       m.category,
       m.is_process,
       m.status                                 AS status_material,
       v.code                                   AS material_code,
       left(v.code, 4)                          AS prefix,
       substr(v.code, 5, 3)                     AS kode_dimension,
       substr(v.code, 8, 3)                     AS kode_warna,
       coalesce(v.thickness, '')                AS dimension,
       v.color                                  AS warna,
       v.status                                 AS status_varian,
       (SELECT count(*) FROM material_variant x
         WHERE x.material_id = m.id AND x.status = 'ACTIVE') AS jumlah_varian_aktif
  FROM material m
  LEFT JOIN material_variant v ON v.material_id = m.id
 WHERE m.factory_id IN (SELECT id FROM f)
 ORDER BY m.name, v.code;
