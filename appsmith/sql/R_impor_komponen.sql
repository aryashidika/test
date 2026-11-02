-- ============================================================================
-- Impor Master Komponen standar (60 komponen), status ACTIVE (14 Okt 2026)
-- Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF). Satu transaksi.
-- Kelompok: a = Upper (10-3990), b = Bottom unit (4000-5990), c = Packaging (6000-7990), d = Miscellaneous (8000-9990).
-- Nomor mengikuti Konfirmasi_Master_Komponen_v2.xlsx; komponen baru (usulan) mulai 300, 4120, 6090, 8080.
-- Tidak dimasukkan (jadi subkomponen / digabung): Coating Film (200, 220), Heel Seam Sealing (250),
--   Collar Foam 2, Collar Reinf IN / OUT, Eyestay Reinf IN / OUT, Vamp + Quarter Backer,
--   Sockliner Cover + Die Cut, Counter (= Heel Counter), Sank Insole Fore Foot.
-- Aman dijalankan ulang: nomor yang sudah ada dilewati. Kelompok a/b/c/d harus sudah ada (dari F2_master.sql).
-- ============================================================================

INSERT INTO component (number, name, group_code, status)
SELECT v.number, v.name, v.group_code, 'ACTIVE'
  FROM (VALUES
    (10, 'UPPER', 'a'),
    (20, 'UPPER OVERLAY', 'a'),
    (30, 'UPPER UNDERLAY', 'a'),
    (40, 'UPPER LINING', 'a'),
    (50, 'UPPER FOAM', 'a'),
    (60, 'TONGUE', 'a'),
    (70, 'TONGUE BACKER', 'a'),
    (80, 'TONGUE COLLAR', 'a'),
    (90, 'TONGUE LOGO', 'a'),
    (100, 'COLLAR LINING', 'a'),
    (110, 'COLLAR FOAM', 'a'),
    (130, 'COLLAR FOAM BACKER', 'a'),
    (140, 'COLLAR REINF IN', 'a'),
    (150, 'COLLAR REINF OUT', 'a'),
    (170, 'EYESTAY REINF', 'a'),
    (210, 'VAMP LINING', 'a'),
    (240, 'HEEL PATCH', 'a'),
    (260, 'TOE BOX', 'a'),
    (270, 'NO SEW', 'a'),
    (280, 'PLASTIC PADDING', 'a'),
    (290, 'PUNCH HOLE', 'a'),
    (300, 'VAMP', 'a'),
    (310, 'QUARTER', 'a'),
    (320, 'EYELET', 'a'),
    (330, 'HEEL TAB', 'a'),
    (4000, 'SOCKLINER COVER', 'b'),
    (4010, 'SOCKLINER DIE CUT', 'b'),
    (4030, 'SOCKLINER LOGO', 'b'),
    (4040, 'CUP INSOLE', 'b'),
    (4050, 'INSOLE', 'b'),
    (4060, 'HEEL COUNTER', 'b'),
    (4080, 'MIDSOLE', 'b'),
    (4090, 'MIDSOLE INSERT', 'b'),
    (4110, 'OUTSOLE', 'b'),
    (4120, 'INSOLE BOARD', 'b'),
    (4130, 'STROBEL BOARD', 'b'),
    (4140, 'SHANK', 'b'),
    (4150, 'CLEAT', 'b'),
    (6000, 'INNER BOX', 'c'),
    (6010, 'CARTON BOX', 'c'),
    (6020, 'STICKER INNER BOX', 'c'),
    (6030, 'ISOLATAPE', 'c'),
    (6040, 'WRAPPING PAPER', 'c'),
    (6050, 'TISSUE PAPER', 'c'),
    (6060, 'SILICA GEL', 'c'),
    (6070, 'STRING PIN', 'c'),
    (6080, 'HANG TAG PRICE', 'c'),
    (6090, 'SHOE BAG', 'c'),
    (6100, 'BARCODE STICKER', 'c'),
    (6110, 'CARTON STICKER', 'c'),
    (8000, 'CEMENT UPPER', 'd'),
    (8010, 'CEMENT ASSEMBLING', 'd'),
    (8020, 'CEMENT STOCKFIT', 'd'),
    (8030, 'SHOE LACE', 'd'),
    (8040, 'SEWING THREAD', 'd'),
    (8050, 'STROBEL THREAD', 'd'),
    (8060, 'THREAD VARIANCE', 'd'),
    (8070, 'SIZE LABEL', 'd'),
    (8080, 'PRIMER', 'd'),
    (8090, 'CARE LABEL', 'd')
  ) AS v(number, name, group_code)
 WHERE NOT EXISTS (SELECT 1 FROM component c WHERE c.number = v.number);

SELECT group_code, count(*) AS jumlah FROM component GROUP BY group_code ORDER BY group_code;
