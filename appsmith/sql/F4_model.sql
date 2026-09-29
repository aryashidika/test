-- ============================================================================
-- F4 — Model, Season, Article, lampiran article
-- Jalankan SETELAH F3/F3b, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
--
-- Aturan (= model_service.py / specsheet_service.py / article_service.py):
-- - Kode model unik (tidak peka huruf besar/kecil). Model, season, article, lampiran: izin edit_model
--   (Master Admin, Vendor – Specsheet). Lihat: view_model.
-- - Season = satu baris "specsheet" per model + season, format SS26 / FH26 (disimpan huruf besar).
-- - Article: kode unik per season (tidak peka huruf besar/kecil), maksimal 5 article per season.
--   Colorway selalu bisa diubah; kode hanya selama article belum dipakai di specsheet/CBD.
--   Article yang sudah dipakai tidak bisa dihapus (hentikan lewat drop di specsheet, F5).
-- - Lampiran per article: jpg / png / pdf (dicek dari isi file), maks 5 MB, disimpan bytea.
--   Isi file tidak dicatat di audit_log (fn_audit_trigger membuang kolom "content").
-- ============================================================================

-- ---------------------------------------------------------------- Cek bentrok nama
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('product_model', 'outsole_mold'), ('specsheet', 'season_sort'),
                                 ('article', 'colorway'), ('article_attachment', 'size_bytes')) AS t(tbl, col)
  LOOP
    IF to_regclass('public.' || r.tbl) IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = r.tbl AND column_name = r.col) THEN
      RAISE EXCEPTION 'Tabel "%" sudah ada di database dan bukan milik proyek ini. Hentikan dan hubungi pengembang.', r.tbl;
    END IF;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------- Tabel
CREATE TABLE IF NOT EXISTS product_model (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code         text NOT NULL CHECK (btrim(code) <> ''),
  name         text NOT NULL CHECK (btrim(name) <> ''),
  factory      text, category text, outsole_mold text, last_no text,
  construction text, size_range text, sample_size text,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_model_code UNIQUE (code)
);

-- Satu baris per model + season (= "specsheet" di Python)
CREATE TABLE IF NOT EXISTS specsheet (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id    uuid NOT NULL REFERENCES product_model(id),
  season      text NOT NULL CHECK (season ~ '^(SS|FH)[0-9]{2}$'),
  season_sort integer GENERATED ALWAYS AS
              (substr(season, 3, 2)::integer * 10 + CASE WHEN left(season, 2) = 'FH' THEN 1 ELSE 0 END) STORED,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_specsheet_season UNIQUE (model_id, season)
);

CREATE TABLE IF NOT EXISTS article (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  specsheet_id uuid NOT NULL REFERENCES specsheet(id),
  code         text NOT NULL CHECK (btrim(code) <> ''),
  colorway     text NOT NULL CHECK (btrim(colorway) <> ''),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_article_code UNIQUE (specsheet_id, code)
);
CREATE INDEX IF NOT EXISTS idx_article_specsheet ON article (specsheet_id);

CREATE TABLE IF NOT EXISTS article_attachment (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id uuid NOT NULL REFERENCES article(id) ON DELETE CASCADE,
  file_name  text NOT NULL,
  mime_type  text NOT NULL CHECK (mime_type IN ('image/jpeg','image/png','application/pdf')),
  size_bytes integer NOT NULL CHECK (size_bytes <= 5242880),
  content    bytea NOT NULL,
  note       text,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text
);
CREATE INDEX IF NOT EXISTS idx_attachment_article ON article_attachment (article_id);

-- ---------------------------------------------------------------- Trigger model
-- Isian dirapikan (field opsional kosong -> NULL); kode yang sama beda huruf besar/kecil ditolak.
CREATE OR REPLACE FUNCTION fn_model_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other text;
BEGIN
  NEW.code         := btrim(regexp_replace(coalesce(NEW.code, ''), '\s+', ' ', 'g'));
  NEW.name         := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  NEW.factory      := nullif(btrim(coalesce(NEW.factory, '')), '');
  NEW.category     := nullif(btrim(coalesce(NEW.category, '')), '');
  NEW.outsole_mold := nullif(btrim(coalesce(NEW.outsole_mold, '')), '');
  NEW.last_no      := nullif(btrim(coalesce(NEW.last_no, '')), '');
  NEW.construction := nullif(btrim(coalesce(NEW.construction, '')), '');
  NEW.size_range   := nullif(btrim(coalesce(NEW.size_range, '')), '');
  NEW.sample_size  := nullif(btrim(coalesce(NEW.sample_size, '')), '');
  IF NEW.code = '' THEN RAISE EXCEPTION 'Kode model wajib diisi.'; END IF;
  IF NEW.name = '' THEN RAISE EXCEPTION 'Nama model wajib diisi.'; END IF;
  SELECT name INTO v_other FROM product_model WHERE upper(code) = upper(NEW.code) AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Kode model % sudah dipakai model "%".', NEW.code, v_other;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_model_check ON product_model;
CREATE TRIGGER trg_model_check BEFORE INSERT OR UPDATE ON product_model
  FOR EACH ROW EXECUTE FUNCTION fn_model_check();
SELECT fn_setup_table('product_model');

-- ---------------------------------------------------------------- Trigger season
CREATE OR REPLACE FUNCTION fn_specsheet_check() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.season := upper(regexp_replace(coalesce(NEW.season, ''), '\s+', '', 'g'));
  IF NEW.season !~ '^(SS|FH)[0-9]{2}$' THEN
    RAISE EXCEPTION 'Season harus berformat SS[tahun] atau FH[tahun], mis. SS26 atau FH26.';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.model_id IS DISTINCT FROM OLD.model_id THEN
    RAISE EXCEPTION 'Season tidak bisa dipindah ke model lain.';
  END IF;
  IF EXISTS (SELECT 1 FROM specsheet WHERE model_id = NEW.model_id AND season = NEW.season AND id <> NEW.id) THEN
    RAISE EXCEPTION 'Season % sudah ada untuk model ini.', NEW.season;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_specsheet_check ON specsheet;
CREATE TRIGGER trg_specsheet_check BEFORE INSERT OR UPDATE ON specsheet
  FOR EACH ROW EXECUTE FUNCTION fn_specsheet_check();
SELECT fn_setup_table('specsheet');

-- ---------------------------------------------------------------- Article
-- Sudah dipakai = masuk revisi specsheet, sel BOM, atau CBD. Tabel itu baru dibuat di F5/F7,
-- jadi dicek hanya kalau tabelnya sudah ada (function ini tidak perlu diubah lagi nanti).
CREATE OR REPLACE FUNCTION fn_article_is_used(p_article_id uuid) RETURNS boolean
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_tbl  text;
  v_used boolean;
BEGIN
  FOREACH v_tbl IN ARRAY ARRAY['revision_article', 'bom_cell', 'cbd_revision'] LOOP
    IF to_regclass('public.' || v_tbl) IS NOT NULL THEN
      EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I WHERE article_id = $1)', v_tbl)
        INTO v_used USING p_article_id;
      IF v_used THEN
        RETURN true;
      END IF;
    END IF;
  END LOOP;
  RETURN false;
END;
$$;

-- Rapikan isian, kode unik per season (tidak peka huruf besar/kecil), maks. 5 article per season,
-- kode article yang sudah dipakai tidak bisa diubah.
CREATE OR REPLACE FUNCTION fn_article_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_count integer;
BEGIN
  NEW.code     := btrim(regexp_replace(coalesce(NEW.code, ''), '\s+', ' ', 'g'));
  NEW.colorway := btrim(regexp_replace(coalesce(NEW.colorway, ''), '\s+', ' ', 'g'));
  IF NEW.code = ''     THEN RAISE EXCEPTION 'Kode article wajib diisi.'; END IF;
  IF NEW.colorway = '' THEN RAISE EXCEPTION 'Colorway wajib diisi.'; END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.specsheet_id IS DISTINCT FROM OLD.specsheet_id THEN
      RAISE EXCEPTION 'Article tidak bisa dipindah ke season lain.';
    END IF;
    IF NEW.code IS DISTINCT FROM OLD.code AND fn_article_is_used(OLD.id) THEN
      RAISE EXCEPTION 'Kode article % tidak bisa diubah karena sudah dipakai di specsheet/CBD.', OLD.code;
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM article WHERE specsheet_id = NEW.specsheet_id AND upper(code) = upper(NEW.code)
                                     AND id <> NEW.id) THEN
    RAISE EXCEPTION 'Kode article % sudah ada di season ini.', NEW.code;
  END IF;

  IF TG_OP = 'INSERT' THEN
    PERFORM 1 FROM specsheet WHERE id = NEW.specsheet_id FOR UPDATE;   -- antre per season
    SELECT count(*) INTO v_count FROM article WHERE specsheet_id = NEW.specsheet_id;
    IF v_count >= 5 THEN
      RAISE EXCEPTION 'Maksimal 5 article per season. Season ini sudah punya % article.', v_count;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_article_check ON article;
CREATE TRIGGER trg_article_check BEFORE INSERT OR UPDATE ON article
  FOR EACH ROW EXECUTE FUNCTION fn_article_check();

CREATE OR REPLACE FUNCTION fn_article_delete_check() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF fn_article_is_used(OLD.id) THEN
    RAISE EXCEPTION 'Article % sudah dipakai di specsheet/CBD dan tidak bisa dihapus. Hentikan pemakaiannya dengan drop di specsheet.', OLD.code;
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_article_delete_check ON article;
CREATE TRIGGER trg_article_delete_check BEFORE DELETE ON article
  FOR EACH ROW EXECUTE FUNCTION fn_article_delete_check();
SELECT fn_setup_table('article');

-- Copy Article antar season TIDAK dipakai (keputusan user 30 Sep 2026: article diisi per season;
-- yang di-copy hanya struktur specsheet, lihat F5). Hapus kalau versi awal F4 sudah telanjur dijalankan.
DROP FUNCTION IF EXISTS fn_article_copy(text, uuid, uuid);

-- ---------------------------------------------------------------- Lampiran
SELECT fn_setup_table('article_attachment');

-- p_base64: isi file dalam Base64 (awalan "data:...;base64," boleh ikut, dibuang di sini).
-- Jenis file ditentukan dari isi file (bukan dari nama/ekstensi): JPEG, PNG, atau PDF.
CREATE OR REPLACE FUNCTION fn_attachment_add(
  p_token text, p_article_id uuid, p_file_name text, p_base64 text, p_note text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email   text := fn_auth(p_token, 'edit_model');
  v_content bytea;
  v_mime    text;
  v_name    text := btrim(coalesce(p_file_name, ''));
  v_id      uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM article WHERE id = p_article_id) THEN
    RAISE EXCEPTION 'Article tidak ditemukan.';
  END IF;
  IF coalesce(p_base64, '') = '' THEN
    RAISE EXCEPTION 'Pilih file yang akan diunggah.';
  END IF;
  BEGIN
    v_content := decode(regexp_replace(regexp_replace(p_base64, '^data:[^,]*,', ''), '\s', '', 'g'), 'base64');
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'File tidak terbaca (format Base64 tidak valid).';
  END;
  IF length(v_content) > 5242880 THEN
    RAISE EXCEPTION 'Ukuran file % MB, maksimal 5 MB.', round(length(v_content) / 1048576.0, 1);
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

-- ---------------------------------------------------------------- View
-- Satu baris per model + season (model tanpa season: satu baris dengan specsheet_id NULL).
-- Ringkasan specsheet terakhir (P2) & jumlah article aktif di revisi ditambahkan di F5
-- (CREATE OR REPLACE VIEW boleh menambah kolom di akhir).
CREATE OR REPLACE VIEW v_model_list AS
SELECT m.id, m.code, m.name, m.category, m.factory, m.outsole_mold, m.last_no, m.construction,
       m.size_range, m.sample_size, m.updated_at, m.updated_by,
       (SELECT count(*) FROM specsheet x WHERE x.model_id = m.id) AS season_count,
       s.id AS specsheet_id, s.season, s.season_sort,
       (SELECT count(*) FROM article a WHERE a.specsheet_id = s.id) AS article_count,
       coalesce(s.season_sort = max(s.season_sort) OVER (PARTITION BY m.id), true) AS is_latest_season
  FROM product_model m
  LEFT JOIN specsheet s ON s.model_id = m.id;

-- Article + jumlah lampiran + boleh dihapus/diubah kodenya.
-- Status di specsheet & CBD ditambahkan di F5 / F7.
CREATE OR REPLACE VIEW v_article_status AS
SELECT a.id, a.specsheet_id, s.model_id, s.season, a.code, a.colorway, a.updated_at, a.updated_by,
       (SELECT count(*) FROM article_attachment t WHERE t.article_id = a.id) AS attachment_count,
       fn_article_is_used(a.id) AS is_used
  FROM article a
  JOIN specsheet s ON s.id = a.specsheet_id;
