-- ============================================================================
-- F6 — Specsheet: checklist & terbit
-- Jalankan SETELAH F5 + F5b, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
--
-- Aturan (= revision_service.publish_checklist / publish_revision):
-- - Hanya revisi DRAFT yang bisa diterbitkan; setelah terbit revisi terkunci (trigger F5).
-- - Checklist penolak (blocking): minimal satu article aktif · setiap article aktif dipakai minimal
--   satu baris BOM (sel berwarna) · tidak ada baris dengan material INACTIVE.
--   Peringatan (boleh terbit): baris tanpa supplier (harga CBD-nya tidak bisa diambil).
-- - Kategori change log wajib; alasan wajib kecuali revisi awal (r0 tanpa sumber) -> "Revisi awal.".
-- - Terbit tercatat di audit_log lewat trigger specsheet_revision (DRAFT -> PUBLISHED) dan di change_log.
-- - Penandaan CBD NEEDS_REVISION ditambahkan ke fn_revision_publish di F8.
-- ============================================================================

-- ---------------------------------------------------------------- Cek bentrok nama
DO $$
BEGIN
  IF to_regclass('public.change_log') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'change_log' AND column_name = 'doc_type') THEN
    RAISE EXCEPTION 'Tabel "change_log" sudah ada di database dan bukan milik proyek ini. Hentikan dan hubungi pengembang.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Tabel
-- Satu baris per terbit (specsheet di F6, CBD di F8). revision_id tanpa FK karena bisa revisi specsheet
-- atau CBD. Hanya ditulis oleh fn_revision_publish / fn_cbd_publish (tidak ada query ubah/hapus di app).
CREATE TABLE IF NOT EXISTS change_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_type    text NOT NULL CHECK (doc_type IN ('SPECSHEET','CBD')),
  revision_id uuid NOT NULL,
  category    text NOT NULL CHECK (category IN
              ('EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER')),
  reason      text NOT NULL,
  diff        jsonb,                            -- diisi di fase Opsional
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  text NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_change_log_revision ON change_log (revision_id);

-- ---------------------------------------------------------------- Checklist terbit
-- Satu baris per revisi. unused_articles / inactive_materials = daftar teks (NULL = lolos).
CREATE OR REPLACE VIEW v_revision_checklist AS
SELECT x.*,
       (x.active_articles = 0 OR x.unused_articles IS NOT NULL OR x.inactive_materials IS NOT NULL) AS blocked
  FROM (
    SELECT r.id AS revision_id, r.specsheet_id, r.stage, r.revision_no, r.status,
           (r.source_revision_id IS NOT NULL OR r.revision_no <> 0) AS requires_reason,
           (SELECT count(*)::int FROM bom_line l WHERE l.revision_id = r.id AND l.is_active) AS line_count,
           (SELECT count(*)::int FROM revision_article ra
             WHERE ra.revision_id = r.id AND ra.status = 'ACTIVE') AS active_articles,
           (SELECT string_agg(a.code, ', ' ORDER BY a.code)
              FROM revision_article ra JOIN article a ON a.id = ra.article_id
             WHERE ra.revision_id = r.id AND ra.status = 'ACTIVE'
               AND NOT EXISTS (SELECT 1 FROM bom_cell c JOIN bom_line l ON l.id = c.bom_line_id
                                WHERE l.revision_id = r.id AND l.is_active
                                  AND c.article_id = a.id AND c.is_used)) AS unused_articles,
           (SELECT string_agg(DISTINCT m.material_code || ' — ' || m.name, ', ')
              FROM bom_line l JOIN material m ON m.id = l.material_id
             WHERE l.revision_id = r.id AND l.is_active AND m.status = 'INACTIVE') AS inactive_materials,
           (SELECT count(*)::int FROM bom_line l
             WHERE l.revision_id = r.id AND l.is_active AND l.supplier_id IS NULL) AS no_supplier_lines
      FROM specsheet_revision r
  ) x;

-- ---------------------------------------------------------------- Terbitkan
-- Mengembalikan id change_log. Checklist dihitung ulang setelah revisi dikunci (FOR UPDATE di
-- fn_revision_draft), jadi edit grid yang bersamaan menunggu dan tidak lolos tanpa dicek.
CREATE OR REPLACE FUNCTION fn_revision_publish(p_token text, p_revision_id uuid, p_category text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'edit_specsheet');
  v_rev    specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
  v_chk    v_revision_checklist%ROWTYPE;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_id     uuid;
BEGIN
  SELECT * INTO v_chk FROM v_revision_checklist WHERE revision_id = v_rev.id;
  IF v_chk.active_articles = 0 THEN
    RAISE EXCEPTION 'Specsheet harus punya minimal satu article aktif sebelum diterbitkan.';
  END IF;
  IF v_chk.unused_articles IS NOT NULL THEN
    RAISE EXCEPTION 'Article % belum memakai baris BOM mana pun (isi warna minimal di satu baris).', v_chk.unused_articles;
  END IF;
  IF v_chk.inactive_materials IS NOT NULL THEN
    RAISE EXCEPTION 'Ada baris memakai material INACTIVE: %. Ganti materialnya dulu.', v_chk.inactive_materials;
  END IF;
  IF coalesce(p_category, '') NOT IN ('EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER') THEN
    RAISE EXCEPTION 'Pilih kategori perubahan.';
  END IF;
  IF v_chk.requires_reason AND v_reason IS NULL THEN
    RAISE EXCEPTION 'Alasan perubahan wajib diisi untuk revisi ini.';
  END IF;

  UPDATE specsheet_revision
     SET status = 'PUBLISHED', published_at = now(), published_by = v_email, updated_by = v_email
   WHERE id = v_rev.id;

  INSERT INTO change_log (doc_type, revision_id, category, reason, created_by)
  VALUES ('SPECSHEET', v_rev.id, p_category, coalesce(v_reason, 'Revisi awal.'), v_email)
  RETURNING id INTO v_id;
  -- F8: tandai CBD terbit article terkait NEEDS_REVISION bila baris/supplier/warna berubah.
  RETURN v_id;
END;
$$;
