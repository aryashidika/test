-- ============================================================================
-- R6 — Tugas Saya per role baru, Brand lintas pabrik, sapu bersih pabrik (PLAN.md §6 R6)
-- Bagian dari sql/R_revisi_semua.sql (urutan R3 -> R7). Aman diulang. Satu transaksi.
--
-- - Sapu bersih: semua fungsi tulis dokumen sudah dicek pabriknya di R3–R5; yang tersisa fn_change_log_attach.
--   Fungsi master bersama (supplier, komponen), admin (user, pabrik) dan login memang lintas pabrik.
-- - Tugas Saya Vendor CBD: usulan harga yang DITOLAK Manager Costing (30 hari terakhir) — v_worklist_price_rejected.
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('public.stage_setting') IS NULL THEN
    RAISE EXCEPTION 'Bagian R5 belum dijalankan. Jalankan file revisi dari awal.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Gambar change log: + cek pabrik dokumen
CREATE OR REPLACE FUNCTION fn_change_log_attach(p_token text, p_change_log_id uuid, p_file_name text, p_data text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_log   change_log%ROWTYPE;
  v_email text;
  v_bytes bytea;
  v_mime  text;
  v_id    uuid;
BEGIN
  SELECT * INTO v_log FROM change_log WHERE id = p_change_log_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Change log tidak ditemukan.';
  END IF;
  v_email := fn_auth_in(p_token, CASE v_log.doc_type WHEN 'CBD' THEN 'edit_cbd' ELSE 'edit_specsheet' END,
                        CASE v_log.doc_type WHEN 'CBD' THEN fn_cbd_factory(v_log.revision_id)
                                            ELSE fn_rev_factory(v_log.revision_id) END);
  IF v_log.created_by IS DISTINCT FROM v_email OR v_log.created_at < now() - interval '1 hour' THEN
    RAISE EXCEPTION 'Gambar hanya bisa dilampirkan oleh penerbit, saat terbit.';
  END IF;
  IF (SELECT count(*) FROM change_log_attachment WHERE change_log_id = v_log.id) >= 5 THEN
    RAISE EXCEPTION 'Maksimal 5 gambar per terbit.';
  END IF;
  BEGIN
    v_bytes := decode(regexp_replace(coalesce(p_data, ''), '^data:[^,]*,', ''), 'base64');
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'Isi gambar tidak valid.';
  END;
  IF length(v_bytes) = 0 THEN
    RAISE EXCEPTION 'Gambar kosong.';
  END IF;
  IF length(v_bytes) > 5242880 THEN
    RAISE EXCEPTION 'Ukuran gambar maksimal 5 MB.';
  END IF;
  IF substring(v_bytes FROM 1 FOR 8) = '\x89504e470d0a1a0a'::bytea THEN
    v_mime := 'image/png';
  ELSIF substring(v_bytes FROM 1 FOR 3) = '\xffd8ff'::bytea THEN
    v_mime := 'image/jpeg';
  ELSE
    RAISE EXCEPTION 'Hanya gambar PNG atau JPG.';
  END IF;
  INSERT INTO change_log_attachment (change_log_id, file_name, mime_type, size_bytes, content, updated_by)
  VALUES (v_log.id, coalesce(nullif(btrim(coalesce(p_file_name, '')), ''), 'gambar'), v_mime, length(v_bytes), v_bytes, v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------- Tugas Saya Vendor CBD: usulan harga ditolak
-- Ditolak dalam 30 hari terakhir dan belum diajukan ulang (tidak ada usulan / harga baru setelahnya untuk
-- varian + supplier yang sama).
DROP VIEW IF EXISTS v_worklist_price_rejected;
CREATE VIEW v_worklist_price_rejected AS
SELECT mp.id, m.id AS material_id, m.factory_id, m.name AS material_name, v.code, v.color,
       fn_thickness_label(v.thickness) AS thickness_label, s.name AS supplier_name,
       mp.price, mp.currency, mp.reject_reason, mp.decided_by, mp.decided_at, mp.created_by
  FROM material_price mp
  JOIN material_variant v ON v.id = mp.variant_id
  JOIN material_supplier ms ON ms.id = mp.material_supplier_id
  JOIN material m ON m.id = ms.material_id
  JOIN supplier s ON s.id = ms.supplier_id
 WHERE mp.status = 'REJECTED' AND mp.decided_at > now() - interval '30 days'
   AND NOT EXISTS (SELECT 1 FROM material_price n
                    WHERE n.material_supplier_id = mp.material_supplier_id AND n.variant_id = mp.variant_id
                      AND n.id <> mp.id AND n.created_at >= mp.decided_at);

SELECT 'v_worklist_price_rejected' AS cek, coalesce(to_regclass('public.v_worklist_price_rejected')::text, 'TIDAK ADA') AS hasil
UNION ALL SELECT 'fn_change_log_attach cek pabrik',
       (position('fn_auth_in' IN pg_get_functiondef('fn_change_log_attach(text,uuid,text,text)'::regprocedure)) > 0)::text;
