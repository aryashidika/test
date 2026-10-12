-- ============================================================================
-- R10 — Hapus varian yang tidak dipakai (12 Okt 2026, PLAN.md §6 R10). Jalankan SETELAH R9_kode_varian.sql, lewat
-- z_run_sql di app "DB Tools" (Use prepared statements = OFF). Aman diulang. Satu transaksi.
--
-- Varian boleh dihapus bila TIDAK dipakai:
--   - sel specsheet mana pun (draft maupun terbit) — bom_cell.variant_id
--   - baris CBD mana pun (draft maupun terbit)     — cbd_line.variant_id
--   - harga yang masih hidup: MENUNGGU APPROVAL, BERLAKU, AKAN BERLAKU
-- Harga yang sudah berakhir (RIWAYAT) / DITOLAK ikut terhapus. Penghapusan tercatat di audit_log (trg_audit).
-- Izin: manage_master (Vendor Spec), pabrik dicek.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_variant_code_suggest(text,uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'R9 belum terpasang. Jalankan sql/R9_kode_varian.sql dulu.';
  END IF;
END;
$$;

-- Alasan varian TIDAK bisa dihapus (NULL = boleh dihapus). Dipakai q_variants (kolom delete_block) & fn_variant_delete.
CREATE OR REPLACE FUNCTION fn_variant_delete_block(p_variant_id uuid) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT nullif(concat_ws('; ',
    (SELECT 'dipakai di ' || count(DISTINCT l.revision_id) || ' revisi specsheet'
       FROM bom_cell bc JOIN bom_line l ON l.id = bc.bom_line_id
      WHERE bc.variant_id = p_variant_id HAVING count(*) > 0),
    (SELECT 'dipakai di ' || count(DISTINCT cl.cbd_revision_id) || ' revisi CBD'
       FROM cbd_line cl WHERE cl.variant_id = p_variant_id HAVING count(*) > 0),
    (SELECT 'masih punya ' || string_agg(DISTINCT x.state, ' / ') || ' (' || count(*) || ' harga)'
       FROM material_price mp
       CROSS JOIN LATERAL (SELECT fn_price_state(mp.status, mp.valid_from, mp.valid_to) AS state) x
      WHERE mp.variant_id = p_variant_id AND x.state IN ('MENUNGGU APPROVAL', 'BERLAKU', 'AKAN BERLAKU')
      HAVING count(*) > 0)
  ), '')
$$;

CREATE OR REPLACE FUNCTION fn_variant_delete(p_token text, p_id uuid) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_row   material_variant%ROWTYPE;
  v_block text;
BEGIN
  SELECT * INTO v_row FROM material_variant WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Varian tidak ditemukan (mungkin sudah dihapus). Muat ulang halaman.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_row.factory_id);
  v_block := fn_variant_delete_block(p_id);
  IF v_block IS NOT NULL THEN
    RAISE EXCEPTION 'Varian % tidak bisa dihapus: %. Jadikan INACTIVE bila tidak dipakai lagi.', v_row.code, v_block;
  END IF;
  DELETE FROM material_price WHERE variant_id = p_id;     -- tinggal harga berakhir / ditolak
  DELETE FROM material_variant WHERE id = p_id;
  RETURN v_row.code;
END;
$$;

COMMIT;

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'R10 terpasang' AS cek,
       'hapus varian: ' || (to_regprocedure('fn_variant_delete(text,uuid)') IS NOT NULL)::text
       || ' · cek pemakaian: ' || (to_regprocedure('fn_variant_delete_block(uuid)') IS NOT NULL)::text AS hasil;
