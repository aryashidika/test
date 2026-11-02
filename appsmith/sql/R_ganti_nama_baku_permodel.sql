-- ============================================================================
-- Ganti nama material per model ke nama baku (hasil CEK_nama_baku_permodel.sql, 29 Okt 2026)
-- Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF). Satu transaksi.
-- Hanya nama yang berubah; kategori, UoM, kode, dan specsheet tetap. Aman diulang (nama yang sudah baku dilewati).
-- HEAT SEAL SIZE LABEL SPECS = material umum (bukan per model), tidak ikut. Buang tanda -- di barisnya bila ingin ikut.
-- ============================================================================

UPDATE material m
   SET name = v.nama_baku, updated_by = 'nama baku per model'
  FROM (VALUES
    ('HANGTAG ELEVATION TWO JR FG', 'HANGTAG ELEVATION TWO FG JR'),
    ('HANGTAG ELEVATION TWO JR IN', 'HANGTAG ELEVATION TWO IN JR'),
    ('HANGTAG LIGHTSPEED REBORN FG', 'HANGTAG LIGHT SPEED REBORN FG'),
    ('HANGTAG LIGHTSPEED REBORN IN', 'HANGTAG LIGHT SPEED REBORN IN'),
    ('HEATSEAL SIZE LABEL ILLUZION IV CORE FG', 'SIZE LABEL ILLUZION IV CORE FG')
    -- , ('HEAT SEAL SIZE LABEL SPECS', 'SIZE LABEL SPECS')
  ) AS v (nama_sekarang, nama_baku)
 WHERE m.factory_id = (SELECT id FROM factory WHERE name ILIKE '%UNIMITRA%')
   AND m.name = v.nama_sekarang
RETURNING v.nama_sekarang, m.name AS nama_baru, m.uom;
