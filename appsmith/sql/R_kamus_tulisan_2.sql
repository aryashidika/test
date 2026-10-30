-- ============================================================================
-- Perbaikan tulisan warna I2H (R21, U2, jawaban TANYA 4: "tanpa /"), 29 Okt 2026
-- SPRAY:ICICLE+ANODIZED -> SPRAY:ICICLE ANODIZED (satu varian: 960I800I2H)
-- Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF). Satu transaksi.
-- Pengaman: batal kalau varian tidak ditemukan dengan tulisan lama, atau sudah dipakai di sel BOM / baris CBD.
-- Hanya satu varian dengan kode warna I2H, jadi pemeriksaan arti kode R20 (trigger) tetap berjalan biasa.
-- ============================================================================

DO $$
DECLARE
  v_id  uuid;
  v_mat uuid;
  v_n   integer;
BEGIN
  SELECT v.id, v.material_id INTO v_id, v_mat
    FROM material_variant v JOIN factory f ON f.id = v.factory_id AND f.name ILIKE '%UNIMITRA%'
   WHERE v.code = '960I800I2H' AND v.color = 'SPRAY:ICICLE+ANODIZED';
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'Varian 960I800I2H dengan tulisan SPRAY:ICICLE+ANODIZED tidak ditemukan. Dibatalkan.';
  END IF;

  SELECT count(*) INTO v_n FROM bom_cell WHERE variant_id = v_id;
  IF v_n > 0 THEN RAISE EXCEPTION 'Ada % sel BOM yang memakai varian ini. Dibatalkan.', v_n; END IF;
  SELECT count(*) INTO v_n FROM cbd_line
   WHERE material_id = v_mat AND fn_color_key(color) = fn_color_key('SPRAY:ICICLE+ANODIZED');
  IF v_n > 0 THEN RAISE EXCEPTION 'Ada % baris CBD dengan warna lama. Dibatalkan.', v_n; END IF;

  UPDATE material_variant SET color = 'SPRAY:ICICLE ANODIZED', updated_by = 'R21 kamus' WHERE id = v_id;
END;
$$;

SELECT v.code, m.name AS material, v.color, v.updated_by
  FROM material_variant v JOIN material m ON m.id = v.material_id
 WHERE v.code = '960I800I2H';
