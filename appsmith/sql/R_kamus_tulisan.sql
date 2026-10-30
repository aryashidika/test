-- ============================================================================
-- Perbaikan tulisan warna / Dimension varian ke bentuk baku kamus (R21, U2), 29 Okt 2026
-- Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF). Satu transaksi.
--
-- Hanya baris tindakan APP dari CEK_kamus_beda_tulisan.sql:
--   65 varian warna (ASKER -> ACCENT, DC -> DECO, METALIC -> METALLIC, kata menempel dipisah,
--   DK -> DARK, spasi Pantone, RED 185C -> RED 185 C) dan 5 varian Dimension (LEBAR= -> WIDTH).
-- Baris KAMUS tidak mengubah aplikasi. Baris TANYA (W7N, D88, W38, I2H, B28) belum disentuh.
--
-- Pengaman (hasil CEK 29 Okt: semuanya 0):
--   - batal kalau varian sasaran sudah dipakai di sel BOM mana pun (DRAFT atau terbit)
--     atau di baris CBD dengan warna lama
--   - batal kalau jumlah varian yang cocok tidak 65 warna / 5 Dimension
--     (artinya data berubah sejak CEK: jalankan CEK lagi dulu)
--   - batal kalau sesudah diubah ada varian yang melanggar aturan arti kode R20
--     (trigger pemeriksa dimatikan hanya selama UPDATE, lalu dinyalakan lagi dalam transaksi yang sama)
-- Kode Material Code tidak berubah; hanya tulisan warna / Dimension.
-- ============================================================================

DO $$
DECLARE
  v_factory uuid;
  v_n integer;
BEGIN
  SELECT id INTO v_factory FROM factory WHERE name ILIKE '%UNIMITRA%';

  CREATE TEMP TABLE t_warna (kode_warna text, lama text, baru text) ON COMMIT DROP;
  INSERT INTO t_warna VALUES
    ('81K','BASE:WHITE/DC:RED 3546 C','BASE:WHITE/DECO:RED 3546 C'),
    ('87O','BASE:WHITE C/DC:TRUE RED (19-1664 TPG)','BASE:WHITE C/DECO:TRUE RED (19-1664 TPG)'),
    ('87L','BASE:WHITE C/ASKER:METALIC GOLD','BASE:WHITE C/ACCENT:METALLIC GOLD'),
    ('892','BASE+ASKER:WHITE A','BASE+ACCENT:WHITE A'),
    ('IM2','BASE+ASKER:ICE FLOW (13-4404 TPG)','BASE+ACCENT:ICE FLOW (13-4404 TPG)'),
    ('XDN','BASE+ASKER:BLACK','BASE+ACCENT:BLACK'),
    ('WT6','BASE:WHITE C/ASKER:WHITE C','BASE:WHITE C/ACCENT:WHITE C'),
    ('EGE','BASE:EGRET (11-0103 TPG)/ASKER:PURPLEROSE','BASE:EGRET (11-0103 TPG)/ACCENT:PURPLE ROSE'),
    ('JEM','BASE:JET BLACK/ASKER:METALIC RICH GOLD','BASE:JET BLACK/ACCENT:METALLIC RICH GOLD'),
    ('MSF','BASE:MATTE SILVER/ASKER:NEON GREEN GECKO','BASE:MATTE SILVER/ACCENT:NEON GREEN GECKO'),
    ('SUW','BASE:SNOW WHITE/ASKER:CARMINE ROSE','BASE:SNOW WHITE/ACCENT:CARMINE ROSE'),
    ('X1L','BASE:BLACK/ASKER:MAGNET (19-3901 TPG)','BASE:BLACK/ACCENT:MAGNET (19-3901 TPG)'),
    ('ILZ','BASE:ICICLE (12-5201 TPG)/DECO:BEACHGLASS','BASE:ICICLE (12-5201 TPG)/DECO:BEACH GLASS'),
    ('MSD','METALIC SILVER (14-5002 TPG)/WHITE','METALLIC SILVER (14-5002 TPG)/WHITE'),
    ('MSG','BASE+STUD:METALIC RICH GOLD (16-0836 TPG)','BASE+STUD:METALLIC RICH GOLD (16-0836 TPG)'),
    ('TX9','LINE:TEALGREEN/CENTER:METALICSILVER','LINE:TEAL GREEN/CENTER:METALLIC SILVER'),
    ('NP9','BASE:NEONLIMECREAM (12-0312 TPG)/STUD:WHITE C','BASE:NEON LIME CREAM (12-0312 TPG)/STUD:WHITE C'),
    ('D6K','DK DENIM (19-4118 TPG)','DARK DENIM (19-4118 TPG)'),
    ('C1D','CHIPMUNK(17-1044TP)','CHIPMUNK (17-1044 TP)'),
    ('C49','CASHEW(17-1137TP)','CASHEW (17-1137 TP)'),
    ('E04','ELEPHANT SKIN(17-0205TP)','ELEPHANT SKIN (17-0205 TP)'),
    ('M0E','MOON MIST(P18-4105TP)','MOON MIST (P 18-4105 TP)'),
    ('P0V','PINECONE(19-1116TP)','PINECONE (19-1116 TP)'),
    ('R0Y','RAVEN(19-0608 TP)','RAVEN (19-0608 TP)'),
    ('V0C','VERDENT GREEN(19-6026TP)','VERDENT GREEN (19-6026 TP)'),
    ('RJK','RED 185C/WHITE','RED 185 C/WHITE');

  CREATE TEMP TABLE t_dim (kode_dimension text, lama text, baru text) ON COMMIT DROP;
  INSERT INTO t_dim VALUES
    ('108','LEBAR=140 CM','WIDTH 140 CM'),
    ('109','LEBAR=135 CM','WIDTH 135 CM');

  CREATE TEMP TABLE t_sasaran ON COMMIT DROP AS
  SELECT v.id, v.material_id, v.color, 'W' AS jenis, w.baru
    FROM material_variant v JOIN t_warna w ON w.kode_warna = substr(v.code, 8, 3) AND v.color = w.lama
   WHERE v.factory_id = v_factory
  UNION ALL
  SELECT v.id, v.material_id, v.color, 'D', d.baru
    FROM material_variant v JOIN t_dim d ON d.kode_dimension = substr(v.code, 5, 3) AND v.thickness = d.lama
   WHERE v.factory_id = v_factory;

  SELECT count(*) INTO v_n FROM t_sasaran WHERE jenis = 'W';
  IF v_n <> 65 THEN RAISE EXCEPTION 'Varian warna yang cocok % (harus 65). Data berubah sejak CEK. Dibatalkan.', v_n; END IF;
  SELECT count(*) INTO v_n FROM t_sasaran WHERE jenis = 'D';
  IF v_n <> 5 THEN RAISE EXCEPTION 'Varian Dimension yang cocok % (harus 5). Data berubah sejak CEK. Dibatalkan.', v_n; END IF;

  SELECT count(*) INTO v_n FROM bom_cell bc WHERE bc.variant_id IN (SELECT id FROM t_sasaran);
  IF v_n > 0 THEN RAISE EXCEPTION 'Ada % sel BOM yang memakai varian sasaran. Dibatalkan.', v_n; END IF;
  SELECT count(*) INTO v_n FROM cbd_line c JOIN t_sasaran s
    ON s.jenis = 'W' AND c.material_id = s.material_id AND fn_normalize(c.color) = fn_normalize(s.color);
  IF v_n > 0 THEN RAISE EXCEPTION 'Ada % baris CBD dengan warna lama. Dibatalkan.', v_n; END IF;

  -- Pemeriksaan arti kode (R20) berjalan per baris: varian kedua dengan kode warna sama masih bertulisan
  -- lama saat varian pertama diubah, jadi pasti ditolak. Trigger pemeriksa dimatikan sebentar; tulisan
  -- dirapikan dengan fungsi yang sama, lalu semua varian sasaran diperiksa ulang setelah semuanya berubah.
  ALTER TABLE material_variant DISABLE TRIGGER trg_material_variant_check;
  UPDATE material_variant v SET color = fn_clean_color(s.baru), updated_by = 'R21 kamus'
    FROM t_sasaran s WHERE s.id = v.id AND s.jenis = 'W';
  UPDATE material_variant v SET thickness = fn_clean_thickness(s.baru), updated_by = 'R21 kamus'
    FROM t_sasaran s WHERE s.id = v.id AND s.jenis = 'D';
  ALTER TABLE material_variant ENABLE TRIGGER trg_material_variant_check;

  SELECT count(*) INTO v_n
    FROM material_variant v JOIN t_sasaran s ON s.id = v.id
   WHERE cardinality(fn_variant_code_problems(v.factory_id, v.material_id, v.code, v.color, v.thickness, v.id)) > 0;
  IF v_n > 0 THEN
    RAISE EXCEPTION '% varian melanggar aturan arti kode setelah diubah. Dibatalkan, tidak ada yang berubah.', v_n;
  END IF;
END;
$$;

-- Hasil: harus 65 baris warna + 5 baris Dimension dengan tulisan baru
SELECT v.code, m.name AS material, v.color, v.thickness, v.updated_by
  FROM material_variant v JOIN material m ON m.id = v.material_id
 WHERE v.updated_by = 'R21 kamus'
 ORDER BY m.name, v.code;
