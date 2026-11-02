-- ============================================================================
-- Ganti pilihan Master Options LAST dan OUTSOLE_MOLD dengan data dari
-- "Daftar_Unik_Outsole_Mold_dan_Laste.xlsx" (14 Okt 2026): 26 Outsole Mold (PRM), 10 Last (PRL).
-- Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF). Satu transaksi.
-- Pilihan dibuat untuk pabrik PT. UNIMITRA KHARISMA (LAST / OUTSOLE_MOLD diisi per pabrik).
-- Yang dihapus: semua LAST dan OUTSOLE_MOLD yang ada (semua pabrik). Kind lain tidak disentuh.
-- Pengaman: batal kalau masih ada model yang memakai Last / Outsole Mold lama
--           (jalankan RESET_kecuali_master_options.sql dulu, atau ganti pilihan di model tersebut).
-- ============================================================================

DO $$
DECLARE
  v_factory uuid;
  v_n       integer;
BEGIN
  SELECT id INTO v_factory FROM factory WHERE upper(name) LIKE '%UNIMITRA%';
  IF v_factory IS NULL THEN
    RAISE EXCEPTION 'Pabrik PT. UNIMITRA KHARISMA tidak ditemukan. Dibatalkan.';
  END IF;

  SELECT count(*) INTO v_n FROM product_model
   WHERE last_id IN (SELECT id FROM model_option WHERE kind IN ('LAST', 'OUTSOLE_MOLD'))
      OR outsole_mold_id IN (SELECT id FROM model_option WHERE kind IN ('LAST', 'OUTSOLE_MOLD'));
  IF v_n > 0 THEN
    RAISE EXCEPTION 'Masih ada % model yang memakai Last / Outsole Mold lama. Dibatalkan.', v_n;
  END IF;

  DELETE FROM model_option WHERE kind IN ('LAST', 'OUTSOLE_MOLD');

  INSERT INTO model_option (kind, factory_id, value, sort_order, status)
  SELECT v.kind, v_factory, v.value, v.sort_order, 'ACTIVE'
    FROM (VALUES
    ('OUTSOLE_MOLD', 'PRM-072', 1),
    ('OUTSOLE_MOLD', 'PRM-074', 2),
    ('OUTSOLE_MOLD', 'PRM-080', 3),
    ('OUTSOLE_MOLD', 'PRM-081', 4),
    ('OUTSOLE_MOLD', 'PRM-081 JR', 5),
    ('OUTSOLE_MOLD', 'PRM-091', 6),
    ('OUTSOLE_MOLD', 'PRM-091 JR', 7),
    ('OUTSOLE_MOLD', 'PRM-092', 8),
    ('OUTSOLE_MOLD', 'PRM-093', 9),
    ('OUTSOLE_MOLD', 'PRM-097', 10),
    ('OUTSOLE_MOLD', 'PRM-099', 11),
    ('OUTSOLE_MOLD', 'PRM-099 JR', 12),
    ('OUTSOLE_MOLD', 'PRM-100', 13),
    ('OUTSOLE_MOLD', 'PRM-100 TR', 14),
    ('OUTSOLE_MOLD', 'PRM-101', 15),
    ('OUTSOLE_MOLD', 'PRM-102', 16),
    ('OUTSOLE_MOLD', 'PRM-104', 17),
    ('OUTSOLE_MOLD', 'PRM-105', 18),
    ('OUTSOLE_MOLD', 'PRM-106', 19),
    ('OUTSOLE_MOLD', 'PRM-106 TF', 20),
    ('OUTSOLE_MOLD', 'PRM-107', 21),
    ('OUTSOLE_MOLD', 'PRM-108', 22),
    ('OUTSOLE_MOLD', 'PRM-109', 23),
    ('OUTSOLE_MOLD', 'PRM-110', 24),
    ('OUTSOLE_MOLD', 'PRM-111', 25),
    ('OUTSOLE_MOLD', 'PRM-112', 26),
    ('LAST', 'PRL-014', 1),
    ('LAST', 'PRL-014 JR', 2),
    ('LAST', 'PRL-015', 3),
    ('LAST', 'PRL-024', 4),
    ('LAST', 'PRL-024 JR', 5),
    ('LAST', 'PRL-024R', 6),
    ('LAST', 'PRL-025', 7),
    ('LAST', 'PRL-035', 8),
    ('LAST', 'PRL-035N', 9),
    ('LAST', 'PRL-037', 10)
    ) AS v(kind, value, sort_order);
END;
$$;

SELECT kind, count(*) AS jumlah FROM model_option GROUP BY kind ORDER BY kind;
