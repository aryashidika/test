-- Koreksi data Excel Batch 3 (2 Nov 2026), jalankan lewat DB Tools (z_run_sql, prepared statements OFF).
-- 1. ACC LS SPYDER FG JR: Process Strobel Thread ("BLACK / NEON VOLT") dan Heel Counter ("BROWN/BLACK") dikosongkan
--    (itu warna baris lain, sudah ada di sel Isolatape / Inner Box / Carton Box).
-- 2. ALPHA FORCE PRO IN: warna "NATIRAL" (Tissue Paper, Wrapping Paper) jadi "NATURAL".
-- 3. (opsional, v_silica) ALPHA FORCE PRO IN: warna Silica Gel article PINK / FUSCHIA / GREEN yang kosong diisi NATURAL.
-- v_simpan = false: dijalankan lalu DIBATALKAN, pesan "UJI SAJA" menampilkan jumlahnya.
DO $$
DECLARE
  v_simpan boolean := false;   -- false = uji saja (dibatalkan), true = simpan
  v_silica boolean := false;   -- true = isi warna Silica Gel yang kosong dengan NATURAL
  n_proc int; n_nat int; n_sil int := 0;
BEGIN
  UPDATE bom_line bl SET process = NULL, updated_by = 'Migrasi data', updated_at = now()
    FROM specsheet_revision r JOIN specsheet s ON s.id = r.specsheet_id JOIN product_model pm ON pm.id = s.model_id
   WHERE bl.revision_id = r.id AND pm.name = 'ACC LS SPYDER FG JR' AND pm.created_by = 'Migrasi data' AND r.status = 'DRAFT'
     AND upper(btrim(bl.process)) IN ('BLACK / NEON VOLT', 'BROWN/BLACK');
  GET DIAGNOSTICS n_proc = ROW_COUNT;

  UPDATE bom_cell bc SET color = 'NATURAL', updated_by = 'Migrasi data', updated_at = now()
    FROM bom_line bl JOIN specsheet_revision r ON r.id = bl.revision_id JOIN specsheet s ON s.id = r.specsheet_id
         JOIN product_model pm ON pm.id = s.model_id
   WHERE bc.bom_line_id = bl.id AND pm.name = 'ALPHA FORCE PRO IN' AND pm.created_by = 'Migrasi data' AND r.status = 'DRAFT'
     AND upper(btrim(bc.color)) = 'NATIRAL';
  GET DIAGNOSTICS n_nat = ROW_COUNT;

  IF v_silica THEN
    INSERT INTO bom_cell (bom_line_id, article_id, color, created_by, updated_by)
    SELECT bl.id, a.id, 'NATURAL', 'Migrasi data', 'Migrasi data'
      FROM bom_line bl JOIN material mt ON mt.id = bl.material_id AND mt.name = 'SILICAGEL'
           JOIN specsheet_revision r ON r.id = bl.revision_id JOIN specsheet s ON s.id = r.specsheet_id
           JOIN product_model pm ON pm.id = s.model_id
           JOIN article a ON a.specsheet_id = s.id AND a.colorway = 'PINK / FUSCHIA / GREEN'
     WHERE pm.name = 'ALPHA FORCE PRO IN' AND pm.created_by = 'Migrasi data' AND r.status = 'DRAFT'
    ON CONFLICT (bom_line_id, article_id) DO UPDATE SET color = 'NATURAL', updated_by = 'Migrasi data', updated_at = now()
      WHERE bom_cell.color IS NULL OR btrim(bom_cell.color) = '';
    GET DIAGNOSTICS n_sil = ROW_COUNT;
  END IF;

  -- harus tepat: 2 baris Process, 6 sel NATIRAL (2 baris x 3 article); Silica Gel 1 sel bila dipilih
  IF n_proc <> 2 OR n_nat <> 6 OR (v_silica AND n_sil <> 1) THEN
    RAISE EXCEPTION 'BERHENTI, jumlah tidak sesuai: Process % (harus 2), NATIRAL % (harus 6), Silica Gel % (harus 1 bila dipilih).',
      n_proc, n_nat, n_sil;
  END IF;
  IF NOT v_simpan THEN
    RAISE EXCEPTION 'UJI SAJA, tidak ada yang tersimpan. Process dikosongkan %, NATIRAL jadi NATURAL %, Silica Gel diisi %.', n_proc, n_nat, n_sil;
  END IF;
  RAISE NOTICE 'TERSIMPAN. Process dikosongkan %, NATIRAL jadi NATURAL %, Silica Gel diisi %.', n_proc, n_nat, n_sil;
END;
$$;
