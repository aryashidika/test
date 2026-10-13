-- ============================================================================
-- R12 — Perbaikan pra-UAT dari review go-live (13 Okt 2026), lihat PLAN.md §9 T60–T67.
-- Jalankan SETELAH R11b_harga_batal.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi. Tidak mengubah data.
--
--   T60  Lampiran article & gambar change log maks. 3,5 MB (sebelumnya 5 MB): file dikirim ke browser sebagai base64
--        (+33%) dan Appsmith membatasi ukuran respons query — 3,5 MB ≈ 4,7 MB base64. Gambar terbit diperkecil
--        otomatis di browser (cwPublishForm), jadi batas ini jarang tercapai. File lama > 3,5 MB tetap tersimpan.
--   T61  Index cbd_line(material_price_id): Batal usulan / Hapus varian menghapus baris harga, dan Postgres mengecek
--        relasi ke cbd_line. Tanpa index = baca seluruh cbd_line (data 5 tahun: 1,1 detik per harga).
--   T65  fn_cbd_override_price & fn_cbd_clear_override dihapus (sejak F10b/R5 hanya menolak; query & tombolnya
--        ikut dihapus di build R12).
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_cbd_bridge_view(text,uuid)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_price_state' AND prosrc LIKE '%DIBATALKAN%') THEN
    RAISE EXCEPTION 'R11 / R11b belum terpasang. Jalankan sql/R11_perbaikan.sql lalu sql/R11b_harga_batal.sql dulu.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- T61: index relasi harga di baris CBD
CREATE INDEX IF NOT EXISTS ix_cbd_line_material_price ON cbd_line (material_price_id);

-- ---------------------------------------------------------------- T60: lampiran article maks. 3,5 MB
-- Sama dengan R4, kecuali batas ukuran.
CREATE OR REPLACE FUNCTION fn_attachment_add(
  p_token text, p_article_id uuid, p_file_name text, p_base64 text, p_note text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email   text := fn_auth_in(p_token, 'edit_model', fn_article_factory(p_article_id));
  v_content bytea;
  v_mime    text;
  v_name    text := btrim(coalesce(p_file_name, ''));
  v_id      uuid;
BEGIN
  IF coalesce(p_base64, '') = '' THEN
    RAISE EXCEPTION 'Pilih file yang akan diunggah.';
  END IF;
  BEGIN
    v_content := decode(regexp_replace(regexp_replace(p_base64, '^data:[^,]*,', ''), '\s', '', 'g'), 'base64');
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'File tidak terbaca (format Base64 tidak valid).';
  END;
  IF length(v_content) > 3670016 THEN
    RAISE EXCEPTION 'Ukuran file % MB, maksimal 3,5 MB.', replace((ceil(length(v_content) / 104857.6) / 10)::numeric(6,1)::text, '.', ',');
  END IF;
  v_mime := CASE
    WHEN substring(v_content FROM 1 FOR 3) = '\xffd8ff'::bytea           THEN 'image/jpeg'
    WHEN substring(v_content FROM 1 FOR 8) = '\x89504e470d0a1a0a'::bytea THEN 'image/png'
    WHEN substring(v_content FROM 1 FOR 5) = '\x255044462d'::bytea       THEN 'application/pdf'
  END;
  IF v_mime IS NULL THEN
    RAISE EXCEPTION 'Jenis file tidak didukung. Hanya JPG, PNG, atau PDF.';
  END IF;
  IF v_name = '' THEN
    v_name := 'lampiran' || CASE v_mime WHEN 'image/jpeg' THEN '.jpg' WHEN 'image/png' THEN '.png' ELSE '.pdf' END;
  END IF;
  INSERT INTO article_attachment (article_id, file_name, mime_type, size_bytes, content, note, updated_by)
  VALUES (p_article_id, v_name, v_mime, length(v_content), v_content,
          nullif(btrim(coalesce(p_note, '')), ''), v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------- T60: gambar change log maks. 3,5 MB
-- Sama dengan R6, kecuali batas ukuran.
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
  IF length(v_bytes) > 3670016 THEN
    RAISE EXCEPTION 'Ukuran gambar maksimal 3,5 MB.';
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

-- ---------------------------------------------------------------- T65: fungsi override yang tidak dipakai lagi
DROP FUNCTION IF EXISTS fn_cbd_override_price(text, uuid, numeric, text, text);
DROP FUNCTION IF EXISTS fn_cbd_clear_override(text, uuid);

-- ---------------------------------------------------------------- info: file lama di atas batas baru
DO $$
DECLARE
  n_att int := (SELECT count(*) FROM article_attachment WHERE size_bytes > 3670016);
  n_img int := (SELECT count(*) FROM change_log_attachment WHERE size_bytes > 3670016);
BEGIN
  IF n_att + n_img > 0 THEN
    RAISE NOTICE 'Info: % lampiran article dan % gambar change log berukuran > 3,5 MB (tersimpan sebelum R12). '
                 'Coba buka sekali saat UAT; bila gagal dimuat, unggah ulang versi yang lebih kecil.', n_att, n_img;
  END IF;
END;
$$;

SELECT 'R12 terpasang' AS hasil;
COMMIT;
