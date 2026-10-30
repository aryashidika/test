-- ============================================================================
-- CEK beda tulisan warna / Dimension aplikasi vs kamus kode ERP (R21, U2) + material A1
-- 29 Okt 2026. Hanya membaca, tidak mengubah apa pun.
-- Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Jalankan BAGIAN 1, 2, 3 satu per satu, kirim hasil ketiganya.
--
-- Dasar: hasil CEK_kamus_sambungan.sql (29 Okt). Dari 327 pasangan kode warna + tulisan
-- di aplikasi, 278 sama dengan kamus; dari 97 kode Dimension, 93 sama. Sisanya di bawah.
--
-- Kolom "tindakan":
--   APP  = tulisan aplikasi diganti ke "tulisan_baku" (aturan yang sudah Anda setujui:
--          ASKER/DC -> ACCENT/DECO, METALIC -> METALLIC, kata menempel dipisah,
--          LEBAR= -> WIDTH, spasi Pantone)
--   KAMUS = aplikasi sudah benar, kamus yang ikut tulisan aplikasi (aplikasi tidak berubah)
--   TANYA = isinya beda (bukan hanya tulisan), perlu keputusan Anda
-- ============================================================================

-- ---------------------------------------------------------------- BAGIAN 1: warna
WITH f AS (SELECT id FROM factory WHERE name ILIKE '%UNIMITRA%'),
k(kode_warna, tulisan_baku, tindakan, catatan) AS (VALUES
  ('C49','CASHEW (17-1137 TP)','APP','spasi Pantone'),
  ('E04','ELEPHANT SKIN (17-0205 TP)','APP','spasi Pantone'),
  ('P0V','PINECONE (19-1116 TP)','APP','spasi Pantone'),
  ('R0Y','RAVEN (19-0608 TP)','APP','spasi Pantone'),
  ('C1D','CHIPMUNK (17-1044 TP)','APP','spasi Pantone'),
  ('M0E','MOON MIST (P 18-4105 TP)','APP','spasi Pantone (seperti P0E)'),
  ('V0C','VERDENT GREEN (19-6026 TP)','APP','spasi Pantone'),
  ('RJK','RED 185 C/WHITE','APP','sticker tertulis 185C, hangtag sudah 185 C'),
  ('892','BASE+ACCENT:WHITE A','APP','ASKER -> ACCENT'),
  ('IM2','BASE+ACCENT:ICE FLOW (13-4404 TPG)','APP','ASKER -> ACCENT'),
  ('XDN','BASE+ACCENT:BLACK','APP','ASKER -> ACCENT'),
  ('WT6','BASE:WHITE C/ACCENT:WHITE C','APP','ASKER -> ACCENT'),
  ('EGE','BASE:EGRET (11-0103 TPG)/ACCENT:PURPLE ROSE','APP','ASKER -> ACCENT, PURPLEROSE dipisah'),
  ('87L','BASE:WHITE C/ACCENT:METALLIC GOLD','APP','ASKER -> ACCENT, METALIC -> METALLIC'),
  ('JEM','BASE:JET BLACK/ACCENT:METALLIC RICH GOLD','APP','ASKER -> ACCENT, METALIC -> METALLIC'),
  ('MSF','BASE:MATTE SILVER/ACCENT:NEON GREEN GECKO','APP','ASKER -> ACCENT'),
  ('SUW','BASE:SNOW WHITE/ACCENT:CARMINE ROSE','APP','ASKER -> ACCENT'),
  ('X1L','BASE:BLACK/ACCENT:MAGNET (19-3901 TPG)','APP','ASKER -> ACCENT'),
  ('87O','BASE:WHITE C/DECO:TRUE RED (19-1664 TPG)','APP','DC -> DECO'),
  ('81K','BASE:WHITE/DECO:RED 3546 C','APP','DC -> DECO'),
  ('ILZ','BASE:ICICLE (12-5201 TPG)/DECO:BEACH GLASS','APP','BEACHGLASS dipisah (seperti X8N)'),
  ('MSD','METALLIC SILVER (14-5002 TPG)/WHITE','APP','METALIC -> METALLIC'),
  ('MSG','BASE+STUD:METALLIC RICH GOLD (16-0836 TPG)','APP','METALIC -> METALLIC'),
  ('TX9','LINE:TEAL GREEN/CENTER:METALLIC SILVER','APP','kata menempel dipisah, METALLIC'),
  ('NP9','BASE:NEON LIME CREAM (12-0312 TPG)/STUD:WHITE C','APP','NEONLIMECREAM dipisah (seperti N6S)'),
  ('D6K','DARK DENIM (19-4118 TPG)','APP','DK -> DARK'),
  ('C1L','COOL GREY 6 C','KAMUS','master 6C'),
  ('C2S','COOL GREY 3 C','KAMUS','master 3C'),
  ('C0V','COOL GREY 7 C','KAMUS','master 7C'),
  ('C7Z','CLOUD DANCER (11-4201 TPG)','KAMUS','master tanpa kurung'),
  ('V1C','VANILLA ICE (11-0104 TPG)','KAMUS','master tanpa kurung'),
  ('GNE','GREEN BUG (14-6330 TPG)/ATLANTIS GREEN','KAMUS','master menempel'),
  ('CZ5','CRYSTAL PINK (12-1605 TPG)/WHITE','KAMUS','master tanpa kurung'),
  ('POZ','PRINCESS BLUE (19-4150 TPG) ANODIZED/WHITE','KAMUS','master PRNCSS ANDZD'),
  ('WXJ','WHITE SAND (13-0002 TPG) ANODIZED/WHITE','KAMUS','master ANODZED'),
  ('IL4','INDIA INK (19-4019 TPG) ANODIZED/BLACK','KAMUS','master ANODZED'),
  ('NLR','NEON FIERY CORAL (15-1456 TN)/LAYER WHITE','KAMUS','master WHT'),
  ('FQW','BASE:FLAME SCARLET (18-1662 TPG)/STUD:FLAME','KAMUS','master B:/S:'),
  ('81N','BASE:WHITE C/STUD:AQUA SPLASH (14-4812 TPG)','KAMUS','master BS:/STD:'),
  ('CZ7','BASE:CLEAR/STUD:N.GREEN GECKO (13-0340 TN)','KAMUS','master BS:/STD:'),
  ('DQ3','BASE+STUD+LOGO:DESERT FLOWER (15-1435 TPG)','KAMUS','master BS+STUD+LG'),
  ('SQS','BASE+STUD+LOGO:SHULPUR SPRING (13-0650 TPG)','KAMUS','master BS+STD+LG'),
  ('X8N','BASE+STUD+LOGO:BEACH GLASS (13-5412 TPG)','KAMUS','master BS+STD+LG'),
  ('A5W','AUTUMN GLORY (15-1263 TPG)','KAMUS','master ada /3M=6MM (ukuran, bukan warna)'),
  ('S7U','SEEDPEARL (12-0703 TPG)','KAMUS','nama Pantone memang satu kata'),
  ('W7N','?','TANYA','aplikasi WHITE/WHITE, master WHITE C/WHT (= WHITE C/WHITE)'),
  ('D88','?','TANYA','aplikasi DRESS BLUE, master DRESS BLUES (nama Pantone 19-4024 = Dress Blues); DEA tertulis DRESS BLUE di keduanya'),
  ('W38','?','TANYA','aplikasi dan master WHITE ASSYLUM; nama Pantone 11-1001 = White Alyssum'),
  ('I2H','?','TANYA','aplikasi SPRAY:ICICLE+ANODIZED; aturan + jadi / -> SPRAY:ICICLE/ANODIZED, atau SPRAY:ICICLE ANODIZED?')
)
SELECT k.tindakan, m.name AS material, v.code AS material_code, v.status,
       v.color AS tulisan_aplikasi, k.tulisan_baku, k.catatan,
       (upper(v.color) = k.tulisan_baku) AS sudah_sama,
       (fn_normalize(v.color) <> fn_normalize(k.tulisan_baku)) AS kunci_warna_berubah,
       fn_variant_used_published(v.id) AS dipakai_dokumen_terbit,
       (SELECT count(*) FROM bom_cell bc JOIN bom_line l ON l.id = bc.bom_line_id
          JOIN specsheet_revision r ON r.id = l.revision_id
         WHERE bc.variant_id = v.id AND r.status = 'DRAFT') AS sel_bom_draft,
       (SELECT count(*) FROM cbd_line c JOIN cbd_revision cr ON cr.id = c.cbd_revision_id
         WHERE c.material_id = v.material_id AND fn_normalize(c.color) = fn_normalize(v.color)
           AND cr.status <> 'PUBLISHED') AS baris_cbd_belum_terbit,
       (SELECT string_agg(DISTINCT cr.status, ', ') FROM cbd_line c JOIN cbd_revision cr ON cr.id = c.cbd_revision_id
         WHERE c.material_id = v.material_id AND fn_normalize(c.color) = fn_normalize(v.color)) AS status_cbd,
       (SELECT x.code FROM material_variant x
         WHERE x.material_id = v.material_id AND x.id <> v.id AND x.thickness_key = v.thickness_key
           AND k.tindakan = 'APP' AND x.color_key = fn_normalize(k.tulisan_baku) LIMIT 1) AS bentrok_dengan
  FROM material_variant v
  JOIN material m ON m.id = v.material_id AND m.factory_id IN (SELECT id FROM f)
  JOIN k ON k.kode_warna = substr(v.code, 8, 3)
 WHERE k.tindakan <> 'APP' OR upper(v.color) <> k.tulisan_baku
 ORDER BY k.tindakan, k.kode_warna, m.name, v.code;

-- ---------------------------------------------------------------- BAGIAN 2: Dimension
WITH f AS (SELECT id FROM factory WHERE name ILIKE '%UNIMITRA%'),
k(kode_dimension, tulisan_baku, tindakan, catatan) AS (VALUES
  ('109','WIDTH 135 CM','APP','LEBAR= -> WIDTH'),
  ('108','WIDTH 140 CM','APP','LEBAR= -> WIDTH'),
  ('99J','SIZE 10-11T','KAMUS','master 10-11T tanpa SIZE'),
  ('B28','?','TANYA','aplikasi B8 (695 X 540 X 345 MM), master B8 (700 X 540 X 345 MM)')
)
SELECT k.tindakan, m.name AS material, v.code AS material_code, v.status,
       v.thickness AS tulisan_aplikasi, k.tulisan_baku, k.catatan,
       CASE WHEN k.tindakan = 'APP' THEN fn_clean_thickness(k.tulisan_baku) END AS baku_setelah_fn_clean,
       fn_variant_used_published(v.id) AS dipakai_dokumen_terbit,
       (SELECT count(*) FROM bom_line l JOIN specsheet_revision r ON r.id = l.revision_id
         WHERE l.material_id = v.material_id AND r.status = 'DRAFT'
           AND fn_normalize(coalesce(l.thickness, '')) = v.thickness_key) AS baris_bom_draft,
       (SELECT count(*) FROM bom_line l JOIN specsheet_revision r ON r.id = l.revision_id
         WHERE l.material_id = v.material_id AND r.status = 'PUBLISHED'
           AND fn_normalize(coalesce(l.thickness, '')) = v.thickness_key) AS baris_bom_terbit
  FROM material_variant v
  JOIN material m ON m.id = v.material_id AND m.factory_id IN (SELECT id FROM f)
  JOIN k ON k.kode_dimension = substr(v.code, 5, 3)
 ORDER BY k.tindakan, k.kode_dimension, m.name, v.code;

-- ---------------------------------------------------------------- BAGIAN 3: material A1
-- 6 prefix yang dipakai aplikasi tetapi di kamus tertanda TIDAK MASUK karena nama ADF
-- mengandung "+" atau "PRINTING". A1: yang dipakai aplikasi selalu masuk, kecuali
-- material gabungan dan material process. Kolom ini untuk memutuskan per material.
WITH f AS (SELECT id FROM factory WHERE name ILIKE '%UNIMITRA%'),
k(prefix, nama_adf) AS (VALUES
  ('4038','10MMFOAMSHL+COATFA7300/50MC+ST'),
  ('938L','OSTPU INJ B+S+LG HD98A PRM-091'),
  ('938N','OSTPUINJ B+S+LG HD98APRM-091JR'),
  ('960I','PRINTING OS PRM 105 (CLEAR)'),
  ('20CZ','ST RIPSTOP + WPN'),
  ('504A','WOVEL LABEL 104B+104T')
)
SELECT k.prefix, m.name AS material, k.nama_adf, m.category, m.is_process, m.status,
       count(DISTINCT v.id) FILTER (WHERE v.status = 'ACTIVE') AS varian_aktif,
       count(DISTINCT l.revision_id) FILTER (WHERE r.status = 'DRAFT') AS specsheet_draft,
       count(DISTINCT l.revision_id) FILTER (WHERE r.status = 'PUBLISHED') AS specsheet_terbit
  FROM k
  JOIN material_variant v ON left(v.code, 4) = k.prefix
  JOIN material m ON m.id = v.material_id AND m.factory_id IN (SELECT id FROM f)
  LEFT JOIN bom_line l ON l.material_id = m.id AND l.is_active
  LEFT JOIN specsheet_revision r ON r.id = l.revision_id
 GROUP BY k.prefix, m.name, k.nama_adf, m.category, m.is_process, m.status
 ORDER BY k.prefix;
