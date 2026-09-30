-- ============================================================================
-- F5b — Hapus baris BOM di revisi DRAFT (tambahan, permintaan user 30 Sep 2026; tidak ada di Python)
-- Jalankan SETELAH F5, lewat z_run_sql di app "DB Tools". Aman diulang.
--
-- - Hanya revisi DRAFT (revisi terbit dikunci trg_lock_published).
-- - Baris induk dihapus -> subkomponennya ikut terhapus. Sel warna ikut terhapus (ON DELETE CASCADE).
-- - Baris dihapus permanen dari draft (bukan dinonaktifkan), jadi tidak tercampur dengan baris lama
--   hasil "Ganti material". Perbandingan dengan revisi sebelumnya (F6/F7) tetap melihatnya sebagai baris hilang.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_bom_delete_line(p_token text, p_line_id uuid) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_specsheet');
  v_line  bom_line%ROWTYPE;
  v_subs  integer;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  DELETE FROM bom_line WHERE revision_id = v_line.revision_id AND parent_line_key = v_line.line_key;
  GET DIAGNOSTICS v_subs = ROW_COUNT;
  DELETE FROM bom_line WHERE id = v_line.id;
  RETURN v_subs + 1;
END;
$$;
