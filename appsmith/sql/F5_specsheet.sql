-- ============================================================================
-- F5 — Specsheet: revisi & grid BOM
-- Jalankan SETELAH F4, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
--
-- Aturan (= revision_service.py / bom_service.py / article_service.py):
-- - Maks. satu revisi DRAFT per season. Revisi terbit terkunci (trigger), hanya DRAFT yang bisa dihapus.
-- - Buat revisi (fn_revision_create):
--     EMPTY          season belum punya revisi -> r0 kosong di stage pilihan, semua article season dimuat
--     COPY           season belum punya revisi -> r0 berisi baris BOM revisi TERBIT terakhir season lain
--                    MODEL YANG SAMA (keputusan user 30 Sep 2026; lintas model tidak dibawa). line_key baru,
--                    origin_line_key = line_key sumber. Article = article season tujuan, warna kosong.
--     NEXT_REVISION  revisi terbit terakhir -> stage sama, nomor + 1 (baris, line_key, article, warna disalin)
--     NEXT_STAGE     revisi terbit terakhir -> stage berikutnya r0 (disalin seperti NEXT_REVISION)
--   "Terakhir" = urut stage lalu nomor revisi (P1).
-- - Baris BOM: komponen master APPROVED atau komponen lokal (nomor bukan kelipatan 10, unik per revisi);
--   material tidak boleh INACTIVE; komponen + material yang sama tidak boleh dobel.
--   Supplier dipilih -> link material-supplier dibuat otomatis (PROPOSED) lewat fn_ensure_link;
--   link INACTIVE ditolak.
-- - Ganti material: baris lama nonaktif, baris baru (replaces_line_key = baris lama) mewarisi komponen,
--   supplier, remarks, dan warna. Subkomponen ikut pindah ke baris baru (P4 — di Python subkomponen
--   hilang dari grid setelah material induknya diganti).
-- - Sel warna: kosong / none / - / n/a / na = tidak dipakai (is_used, kolom generated).
-- ============================================================================

-- ---------------------------------------------------------------- Cek bentrok nama
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('specsheet_revision', 'stage_order'), ('revision_article', 'revision_id'),
                                 ('bom_line', 'line_key'), ('bom_cell', 'bom_line_id')) AS t(tbl, col)
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
CREATE TABLE IF NOT EXISTS specsheet_revision (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  specsheet_id       uuid NOT NULL REFERENCES specsheet(id),
  stage              text NOT NULL CHECK (stage IN ('PULL','SMS','GTM','PROD')),
  stage_order        smallint GENERATED ALWAYS AS
                     (CASE stage WHEN 'PULL' THEN 1 WHEN 'SMS' THEN 2 WHEN 'GTM' THEN 3 ELSE 4 END) STORED,
  revision_no        integer NOT NULL CHECK (revision_no >= 0),
  status             text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','PUBLISHED')),
  source_revision_id uuid REFERENCES specsheet_revision(id),
  published_at       timestamptz,
  published_by       text,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_revision_no UNIQUE (specsheet_id, stage, revision_no)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_one_draft_per_specsheet ON specsheet_revision (specsheet_id) WHERE status = 'DRAFT';

CREATE TABLE IF NOT EXISTS revision_article (
  revision_id uuid NOT NULL REFERENCES specsheet_revision(id) ON DELETE CASCADE,
  article_id  uuid NOT NULL REFERENCES article(id),
  status      text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DROPPED')),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  PRIMARY KEY (revision_id, article_id)
);
CREATE INDEX IF NOT EXISTS idx_revision_article_article ON revision_article (article_id);

CREATE TABLE IF NOT EXISTS bom_line (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  revision_id          uuid NOT NULL REFERENCES specsheet_revision(id) ON DELETE CASCADE,
  line_key             uuid NOT NULL,          -- identitas baris lintas revisi
  origin_line_key      uuid,                   -- line_key sumber saat copy dari season lain
  replaces_line_key    uuid,                   -- baris yang diganti ("Ganti material")
  component_id         uuid REFERENCES component(id),
  local_component_no   integer CHECK (local_component_no % 10 <> 0),
  local_component_name text,
  parent_line_key      uuid,                   -- terisi = subkomponen
  sub_seq              integer,
  sub_name             text,
  material_id          uuid NOT NULL REFERENCES material(id),
  supplier_id          uuid REFERENCES supplier(id),
  process              text,                   -- "Remarks"
  is_active            boolean NOT NULL DEFAULT true,
  sort_order           integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_bom_line_key UNIQUE (revision_id, line_key),
  CHECK (parent_line_key IS NOT NULL OR component_id IS NOT NULL OR local_component_no IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS idx_bom_line_revision ON bom_line (revision_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_bom_local_no ON bom_line (revision_id, local_component_no)
  WHERE is_active AND parent_line_key IS NULL AND local_component_no IS NOT NULL;

-- is_used otomatis: kosong / none / - / n/a / na = tidak dipakai
CREATE TABLE IF NOT EXISTS bom_cell (
  bom_line_id uuid NOT NULL REFERENCES bom_line(id) ON DELETE CASCADE,
  article_id  uuid NOT NULL REFERENCES article(id),
  color       text,
  is_used     boolean GENERATED ALWAYS AS
              (fn_normalize(color) NOT IN ('', 'none', '-', 'n/a', 'na')) STORED,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  PRIMARY KEY (bom_line_id, article_id)
);
CREATE INDEX IF NOT EXISTS idx_bom_cell_article ON bom_cell (article_id);

SELECT fn_setup_table('specsheet_revision');
SELECT fn_setup_table('revision_article');
SELECT fn_setup_table('bom_line');
SELECT fn_setup_table('bom_cell');

-- ---------------------------------------------------------------- Kunci revisi terbit
-- Isi revisi (article revisi, baris BOM, sel) tidak bisa diubah kalau revisinya PUBLISHED.
-- Revisi yang induknya sedang dihapus (hapus draft) tidak ditemukan lagi -> dibiarkan.
CREATE OR REPLACE FUNCTION fn_lock_published() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_row    jsonb;
  v_rev    uuid;
  v_status text;
BEGIN
  IF TG_OP = 'DELETE' THEN v_row := to_jsonb(OLD); ELSE v_row := to_jsonb(NEW); END IF;
  IF TG_TABLE_NAME = 'bom_cell' THEN
    SELECT revision_id INTO v_rev FROM bom_line WHERE id = (v_row ->> 'bom_line_id')::uuid;
  ELSE
    v_rev := (v_row ->> 'revision_id')::uuid;
  END IF;
  SELECT status INTO v_status FROM specsheet_revision WHERE id = v_rev;
  IF v_status = 'PUBLISHED' THEN
    RAISE EXCEPTION 'Revisi ini sudah diterbitkan dan tidak bisa diubah. Buat revisi baru untuk perubahan.';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lock_published ON revision_article;
CREATE TRIGGER trg_lock_published BEFORE INSERT OR UPDATE OR DELETE ON revision_article
  FOR EACH ROW EXECUTE FUNCTION fn_lock_published();
DROP TRIGGER IF EXISTS trg_lock_published ON bom_line;
CREATE TRIGGER trg_lock_published BEFORE INSERT OR UPDATE OR DELETE ON bom_line
  FOR EACH ROW EXECUTE FUNCTION fn_lock_published();
DROP TRIGGER IF EXISTS trg_lock_published ON bom_cell;
CREATE TRIGGER trg_lock_published BEFORE INSERT OR UPDATE OR DELETE ON bom_cell
  FOR EACH ROW EXECUTE FUNCTION fn_lock_published();

-- Revisi terbit sendiri juga tidak bisa diubah / dihapus (terbit = DRAFT -> PUBLISHED tetap boleh).
CREATE OR REPLACE FUNCTION fn_revision_lock() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'PUBLISHED' THEN
    RAISE EXCEPTION 'Revisi % r% sudah diterbitkan dan tidak bisa diubah atau dihapus.', OLD.stage, OLD.revision_no;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF NEW.specsheet_id IS DISTINCT FROM OLD.specsheet_id OR NEW.stage IS DISTINCT FROM OLD.stage
     OR NEW.revision_no IS DISTINCT FROM OLD.revision_no THEN
    RAISE EXCEPTION 'Season, stage, dan nomor revisi tidak bisa diubah.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_revision_lock ON specsheet_revision;
CREATE TRIGGER trg_revision_lock BEFORE UPDATE OR DELETE ON specsheet_revision
  FOR EACH ROW EXECUTE FUNCTION fn_revision_lock();

-- ---------------------------------------------------------------- Helper
-- Revisi DRAFT (dikunci untuk transaksi ini) atau error.
CREATE OR REPLACE FUNCTION fn_revision_draft(p_revision_id uuid) RETURNS specsheet_revision
LANGUAGE plpgsql AS $$
DECLARE
  v_rev specsheet_revision%ROWTYPE;
BEGIN
  SELECT * INTO v_rev FROM specsheet_revision WHERE id = p_revision_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Revisi tidak ditemukan.';
  END IF;
  IF v_rev.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'Revisi ini sudah diterbitkan dan tidak bisa diubah. Buat revisi baru untuk perubahan.';
  END IF;
  RETURN v_rev;
END;
$$;

-- Material untuk baris BOM: harus ada dan tidak INACTIVE.
CREATE OR REPLACE FUNCTION fn_bom_check_material(p_material_id uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_mat material%ROWTYPE;
BEGIN
  SELECT * INTO v_mat FROM material WHERE id = p_material_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Material wajib dipilih dari Master Material.';
  END IF;
  IF v_mat.status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Material % — % sudah INACTIVE. Pilih material lain.', v_mat.material_code, v_mat.name;
  END IF;
END;
$$;

-- Sel kosong untuk semua article ACTIVE revisi ini di satu baris (sel yang sudah ada dibiarkan).
CREATE OR REPLACE FUNCTION fn_bom_create_cells(p_line_id uuid, p_email text) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO bom_cell (bom_line_id, article_id, updated_by)
  SELECT l.id, ra.article_id, p_email
    FROM bom_line l JOIN revision_article ra ON ra.revision_id = l.revision_id AND ra.status = 'ACTIVE'
   WHERE l.id = p_line_id
  ON CONFLICT DO NOTHING
$$;

-- ---------------------------------------------------------------- Buat & hapus revisi
CREATE OR REPLACE FUNCTION fn_revision_create(
  p_token text, p_specsheet_id uuid, p_mode text, p_stage text, p_source_specsheet_id uuid
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'edit_specsheet');
  v_stages text[] := ARRAY['PULL', 'SMS', 'GTM', 'PROD'];
  v_sheet  specsheet%ROWTYPE;
  v_srcsp  specsheet%ROWTYPE;
  v_src    specsheet_revision%ROWTYPE;
  v_stage  text;
  v_no     integer := 0;
  v_id     uuid;
BEGIN
  SELECT * INTO v_sheet FROM specsheet WHERE id = p_specsheet_id FOR UPDATE;   -- antre per season
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Season tidak ditemukan.';
  END IF;
  IF EXISTS (SELECT 1 FROM specsheet_revision WHERE specsheet_id = p_specsheet_id AND status = 'DRAFT') THEN
    RAISE EXCEPTION 'Sudah ada revisi DRAFT untuk season %. Terbitkan atau hapus draft itu dulu.', v_sheet.season;
  END IF;

  IF p_mode IN ('EMPTY', 'COPY') THEN
    IF EXISTS (SELECT 1 FROM specsheet_revision WHERE specsheet_id = p_specsheet_id) THEN
      RAISE EXCEPTION 'Season % sudah punya revisi. Pakai Revisi berikutnya atau Stage berikutnya.', v_sheet.season;
    END IF;
    v_stage := coalesce(nullif(p_stage, ''), 'PULL');
    IF NOT v_stage = ANY (v_stages) THEN
      RAISE EXCEPTION 'Stage tidak valid.';
    END IF;
    IF p_mode = 'COPY' THEN
      SELECT * INTO v_srcsp FROM specsheet WHERE id = p_source_specsheet_id;
      IF NOT FOUND OR v_srcsp.id = v_sheet.id THEN
        RAISE EXCEPTION 'Pilih season sumber.';
      END IF;
      IF v_srcsp.model_id <> v_sheet.model_id THEN
        RAISE EXCEPTION 'Specsheet hanya bisa di-copy dari season lain model yang sama.';
      END IF;
      SELECT * INTO v_src FROM specsheet_revision
       WHERE specsheet_id = v_srcsp.id AND status = 'PUBLISHED'
       ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Season % belum punya revisi terbit untuk di-copy.', v_srcsp.season;
      END IF;
    END IF;

    INSERT INTO specsheet_revision (specsheet_id, stage, revision_no, source_revision_id, updated_by)
    VALUES (p_specsheet_id, v_stage, 0, v_src.id, v_email)
    RETURNING id INTO v_id;

    IF p_mode = 'COPY' THEN
      -- line_key baru; subkomponen menunjuk ke line_key baru induknya
      WITH src AS MATERIALIZED (
        SELECT l.*, gen_random_uuid() AS new_key FROM bom_line l WHERE l.revision_id = v_src.id AND l.is_active
      )
      INSERT INTO bom_line (revision_id, line_key, origin_line_key, component_id, local_component_no,
                            local_component_name, parent_line_key, sub_seq, sub_name, material_id, supplier_id,
                            process, sort_order, updated_by)
      SELECT v_id, s.new_key, s.line_key, s.component_id, s.local_component_no, s.local_component_name,
             p.new_key, s.sub_seq, s.sub_name, s.material_id, s.supplier_id, s.process, s.sort_order, v_email
        FROM src s LEFT JOIN src p ON p.line_key = s.parent_line_key
       WHERE s.parent_line_key IS NULL OR p.line_key IS NOT NULL;
    END IF;

    -- Semua article season ini masuk revisi, sel kosong
    INSERT INTO revision_article (revision_id, article_id, updated_by)
    SELECT v_id, a.id, v_email FROM article a WHERE a.specsheet_id = p_specsheet_id;
    INSERT INTO bom_cell (bom_line_id, article_id, updated_by)
    SELECT l.id, a.id, v_email
      FROM bom_line l CROSS JOIN article a
     WHERE l.revision_id = v_id AND a.specsheet_id = p_specsheet_id;

  ELSIF p_mode IN ('NEXT_REVISION', 'NEXT_STAGE') THEN
    SELECT * INTO v_src FROM specsheet_revision
     WHERE specsheet_id = p_specsheet_id AND status = 'PUBLISHED'
     ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Season % belum punya revisi terbit.', v_sheet.season;
    END IF;
    IF p_mode = 'NEXT_REVISION' THEN
      v_stage := v_src.stage;
      SELECT max(revision_no) + 1 INTO v_no FROM specsheet_revision
       WHERE specsheet_id = p_specsheet_id AND stage = v_stage;
    ELSE
      IF v_src.stage = 'PROD' THEN
        RAISE EXCEPTION 'Sudah berada di stage terakhir (PROD). Pakai Revisi berikutnya.';
      END IF;
      v_stage := v_stages[array_position(v_stages, v_src.stage) + 1];
      v_no := 0;
    END IF;

    INSERT INTO specsheet_revision (specsheet_id, stage, revision_no, source_revision_id, updated_by)
    VALUES (p_specsheet_id, v_stage, v_no, v_src.id, v_email)
    RETURNING id INTO v_id;

    -- Salin apa adanya (line_key tetap), hanya baris aktif
    INSERT INTO bom_line (revision_id, line_key, origin_line_key, replaces_line_key, component_id,
                          local_component_no, local_component_name, parent_line_key, sub_seq, sub_name,
                          material_id, supplier_id, process, sort_order, updated_by)
    SELECT v_id, l.line_key, l.origin_line_key, l.replaces_line_key, l.component_id, l.local_component_no,
           l.local_component_name, l.parent_line_key, l.sub_seq, l.sub_name, l.material_id, l.supplier_id,
           l.process, l.sort_order, v_email
      FROM bom_line l WHERE l.revision_id = v_src.id AND l.is_active;
    INSERT INTO revision_article (revision_id, article_id, status, updated_by)
    SELECT v_id, ra.article_id, ra.status, v_email FROM revision_article ra WHERE ra.revision_id = v_src.id;
    INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
    SELECT n.id, c.article_id, c.color, v_email
      FROM bom_cell c
      JOIN bom_line o ON o.id = c.bom_line_id AND o.revision_id = v_src.id AND o.is_active
      JOIN bom_line n ON n.revision_id = v_id AND n.line_key = o.line_key;
  ELSE
    RAISE EXCEPTION 'Pilih cara membuat revisi.';
  END IF;
  RETURN v_id;
END;
$$;

-- Hapus revisi DRAFT beserta isinya (article-nya sendiri tetap ada di season).
CREATE OR REPLACE FUNCTION fn_revision_delete_draft(p_token text, p_revision_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_specsheet');
  v_rev   specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
BEGIN
  DELETE FROM specsheet_revision WHERE id = v_rev.id;
  RETURN v_rev.id;
END;
$$;

-- ---------------------------------------------------------------- Baris BOM
-- Komponen master (p_component_id) atau komponen lokal (p_local_no + p_local_name).
CREATE OR REPLACE FUNCTION fn_bom_add_line(
  p_token text, p_revision_id uuid, p_component_id uuid, p_local_no integer, p_local_name text,
  p_material_id uuid, p_supplier_id uuid, p_process text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_specsheet');
  v_rev   specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
  v_comp  component%ROWTYPE;
  v_name  text := nullif(btrim(regexp_replace(coalesce(p_local_name, ''), '\s+', ' ', 'g')), '');
  v_id    uuid;
BEGIN
  PERFORM fn_bom_check_material(p_material_id);
  IF p_component_id IS NOT NULL THEN
    SELECT * INTO v_comp FROM component WHERE id = p_component_id;
    IF NOT FOUND OR v_comp.status <> 'APPROVED' THEN
      RAISE EXCEPTION 'Komponen master harus berstatus APPROVED. Untuk komponen baru, pakai komponen lokal.';
    END IF;
    IF EXISTS (SELECT 1 FROM bom_line WHERE revision_id = v_rev.id AND is_active AND parent_line_key IS NULL
                                        AND component_id = p_component_id AND material_id = p_material_id) THEN
      RAISE EXCEPTION 'Komponen % + material ini sudah ada di revisi ini.', v_comp.number;
    END IF;
  ELSE
    IF p_local_no IS NULL THEN
      RAISE EXCEPTION 'Komponen tidak ada di master — isi No. untuk komponen lokal.';
    END IF;
    IF p_local_no % 10 = 0 THEN
      RAISE EXCEPTION 'No. komponen lokal tidak boleh kelipatan 10 (kelipatan 10 untuk komponen master).';
    END IF;
    IF v_name IS NULL THEN
      RAISE EXCEPTION 'Nama komponen lokal wajib diisi.';
    END IF;
    IF EXISTS (SELECT 1 FROM bom_line WHERE revision_id = v_rev.id AND is_active AND parent_line_key IS NULL
                                        AND local_component_no = p_local_no) THEN
      RAISE EXCEPTION 'No. lokal % sudah dipakai di revisi ini.', p_local_no;
    END IF;
  END IF;
  PERFORM fn_ensure_link(p_material_id, p_supplier_id);

  INSERT INTO bom_line (revision_id, line_key, component_id, local_component_no, local_component_name,
                        material_id, supplier_id, process, sort_order, updated_by)
  VALUES (v_rev.id, gen_random_uuid(), p_component_id,
          CASE WHEN p_component_id IS NULL THEN p_local_no END,
          CASE WHEN p_component_id IS NULL THEN v_name END,
          p_material_id, p_supplier_id, nullif(btrim(coalesce(p_process, '')), ''),
          coalesce((SELECT max(sort_order) FROM bom_line WHERE revision_id = v_rev.id), 0) + 1, v_email)
  RETURNING id INTO v_id;
  PERFORM fn_bom_create_cells(v_id, v_email);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_bom_add_sub(
  p_token text, p_parent_line_id uuid, p_sub_name text, p_material_id uuid, p_supplier_id uuid, p_process text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'edit_specsheet');
  v_parent bom_line%ROWTYPE;
  v_name   text := nullif(btrim(regexp_replace(coalesce(p_sub_name, ''), '\s+', ' ', 'g')), '');
  v_id     uuid;
BEGIN
  SELECT * INTO v_parent FROM bom_line WHERE id = p_parent_line_id;
  IF NOT FOUND OR NOT v_parent.is_active THEN
    RAISE EXCEPTION 'Baris induk tidak ditemukan atau sudah tidak aktif.';
  END IF;
  PERFORM fn_revision_draft(v_parent.revision_id);
  IF v_parent.parent_line_key IS NOT NULL THEN
    RAISE EXCEPTION 'Subkomponen tidak bisa dibuat di bawah subkomponen lain.';
  END IF;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Nama subkomponen wajib diisi.';
  END IF;
  PERFORM fn_bom_check_material(p_material_id);
  PERFORM fn_ensure_link(p_material_id, p_supplier_id);

  INSERT INTO bom_line (revision_id, line_key, parent_line_key, sub_seq, sub_name, material_id, supplier_id,
                        process, sort_order, updated_by)
  VALUES (v_parent.revision_id, gen_random_uuid(), v_parent.line_key,
          coalesce((SELECT max(sub_seq) FROM bom_line
                     WHERE revision_id = v_parent.revision_id AND parent_line_key = v_parent.line_key), 0) + 1,
          v_name, p_material_id, p_supplier_id, nullif(btrim(coalesce(p_process, '')), ''),
          v_parent.sort_order, v_email)
  RETURNING id INTO v_id;
  PERFORM fn_bom_create_cells(v_id, v_email);
  RETURN v_id;
END;
$$;

-- Ganti material: baris lama nonaktif, baris baru mewarisi komponen/supplier/remarks/warna.
CREATE OR REPLACE FUNCTION fn_bom_replace_material(p_token text, p_line_id uuid, p_material_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_specsheet');
  v_old   bom_line%ROWTYPE;
  v_key   uuid := gen_random_uuid();
  v_id    uuid;
BEGIN
  SELECT * INTO v_old FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_old.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_old.revision_id);
  IF v_old.material_id = p_material_id THEN
    RAISE EXCEPTION 'Material baru sama dengan material saat ini.';
  END IF;
  PERFORM fn_bom_check_material(p_material_id);
  IF v_old.parent_line_key IS NULL AND EXISTS (
       SELECT 1 FROM bom_line WHERE revision_id = v_old.revision_id AND is_active AND parent_line_key IS NULL
          AND id <> v_old.id AND material_id = p_material_id
          AND component_id IS NOT DISTINCT FROM v_old.component_id
          AND local_component_no IS NOT DISTINCT FROM v_old.local_component_no) THEN
    RAISE EXCEPTION 'Komponen ini dengan material tersebut sudah ada di revisi ini.';
  END IF;
  PERFORM fn_ensure_link(p_material_id, v_old.supplier_id);

  UPDATE bom_line SET is_active = false, updated_by = v_email WHERE id = v_old.id;
  INSERT INTO bom_line (revision_id, line_key, origin_line_key, replaces_line_key, component_id,
                        local_component_no, local_component_name, parent_line_key, sub_seq, sub_name,
                        material_id, supplier_id, process, sort_order, updated_by)
  VALUES (v_old.revision_id, v_key, v_old.origin_line_key, v_old.line_key, v_old.component_id,
          v_old.local_component_no, v_old.local_component_name, v_old.parent_line_key, v_old.sub_seq,
          v_old.sub_name, p_material_id, v_old.supplier_id, v_old.process, v_old.sort_order, v_email)
  RETURNING id INTO v_id;
  INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
  SELECT v_id, article_id, color, v_email FROM bom_cell WHERE bom_line_id = v_old.id;
  PERFORM fn_bom_create_cells(v_id, v_email);
  -- Subkomponen pindah ke baris induk baru (P4)
  UPDATE bom_line SET parent_line_key = v_key, updated_by = v_email
   WHERE revision_id = v_old.revision_id AND parent_line_key = v_old.line_key AND is_active;
  RETURN v_id;
END;
$$;

-- Supplier baris (NULL = kosongkan). Link material-supplier dibuat otomatis (PROPOSED) kalau belum ada.
CREATE OR REPLACE FUNCTION fn_bom_set_supplier(p_token text, p_line_id uuid, p_supplier_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_specsheet');
  v_line  bom_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  IF p_supplier_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM supplier WHERE id = p_supplier_id) THEN
    RAISE EXCEPTION 'Supplier tidak ada di Master Supplier.';
  END IF;
  PERFORM fn_ensure_link(v_line.material_id, p_supplier_id);
  UPDATE bom_line SET supplier_id = p_supplier_id, updated_by = v_email WHERE id = v_line.id;
  RETURN v_line.id;
END;
$$;

-- Warna satu sel (baris x article). Teks dirapikan; kosong = tidak dipakai.
CREATE OR REPLACE FUNCTION fn_bom_cell_set(p_token text, p_line_id uuid, p_article_id uuid, p_color text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_specsheet');
  v_line  bom_line%ROWTYPE;
  v_color text := nullif(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g')), '');
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  IF NOT EXISTS (SELECT 1 FROM revision_article
                  WHERE revision_id = v_line.revision_id AND article_id = p_article_id AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'Article ini tidak aktif di revisi ini.';
  END IF;
  INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
  VALUES (v_line.id, p_article_id, v_color, v_email)
  ON CONFLICT (bom_line_id, article_id) DO UPDATE SET color = EXCLUDED.color, updated_by = EXCLUDED.updated_by;
  RETURN v_line.id;
END;
$$;

-- Article di revisi: masukkan / aktifkan lagi (ACTIVE) atau drop (DROPPED).
CREATE OR REPLACE FUNCTION fn_rev_article_set(p_token text, p_revision_id uuid, p_article_id uuid, p_status text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_specsheet');
  v_rev   specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'DROPPED') THEN
    RAISE EXCEPTION 'Status article tidak valid.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM article WHERE id = p_article_id AND specsheet_id = v_rev.specsheet_id) THEN
    RAISE EXCEPTION 'Article bukan milik season revisi ini.';
  END IF;
  INSERT INTO revision_article (revision_id, article_id, status, updated_by)
  VALUES (v_rev.id, p_article_id, p_status, v_email)
  ON CONFLICT (revision_id, article_id) DO UPDATE SET status = EXCLUDED.status, updated_by = EXCLUDED.updated_by;
  IF p_status = 'ACTIVE' THEN
    INSERT INTO bom_cell (bom_line_id, article_id, updated_by)
    SELECT l.id, p_article_id, v_email FROM bom_line l WHERE l.revision_id = v_rev.id AND l.is_active
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN p_article_id;
END;
$$;

-- ---------------------------------------------------------------- View grid BOM
-- Satu baris per baris BOM aktif. Urutan tampil: ORDER BY group_no NULLS LAST, group_sort, is_sub, sub_seq
-- (nomor komponen master/lokal, lalu urutan input; subkomponen tepat di bawah induknya).
-- cells = {"<article_id>": "<warna>"} (hanya sel yang terisi).
CREATE OR REPLACE VIEW v_bom_grid AS
SELECT l.id, l.revision_id, l.line_key, l.parent_line_key, (l.parent_line_key IS NOT NULL) AS is_sub,
       l.component_id, l.local_component_no, l.sub_seq,
       CASE WHEN l.parent_line_key IS NULL THEN coalesce(c.number, l.local_component_no)
            ELSE coalesce(pc.number, p.local_component_no) END AS group_no,
       CASE WHEN l.parent_line_key IS NULL THEN l.sort_order ELSE coalesce(p.sort_order, l.sort_order) END AS group_sort,
       CASE WHEN l.parent_line_key IS NULL THEN coalesce(c.number, l.local_component_no)::text
            ELSE coalesce(coalesce(pc.number, p.local_component_no)::text || '-', '') || l.sub_seq END AS display_no,
       CASE WHEN l.parent_line_key IS NULL THEN coalesce(c.name, l.local_component_name) ELSE l.sub_name END AS display_name,
       (l.component_id IS NULL AND l.parent_line_key IS NULL) AS is_local,
       l.material_id, m.material_code, m.name AS material_name, m.thickness, m.uom, m.status AS material_status,
       l.supplier_id, s.name AS supplier_name, ms.status AS link_status,
       l.process, l.origin_line_key, l.replaces_line_key,
       coalesce((SELECT jsonb_object_agg(bc.article_id::text, bc.color)
                   FROM bom_cell bc WHERE bc.bom_line_id = l.id AND bc.color IS NOT NULL), '{}'::jsonb) AS cells
  FROM bom_line l
  JOIN material m ON m.id = l.material_id
  LEFT JOIN component c ON c.id = l.component_id
  LEFT JOIN bom_line p ON p.revision_id = l.revision_id AND p.line_key = l.parent_line_key AND p.is_active
  LEFT JOIN component pc ON pc.id = p.component_id
  LEFT JOIN supplier s ON s.id = l.supplier_id
  LEFT JOIN material_supplier ms ON ms.material_id = l.material_id AND ms.supplier_id = l.supplier_id
 WHERE l.is_active;

-- ---------------------------------------------------------------- View F4 diperluas (kolom baru di akhir)
-- Ringkasan specsheet terakhir per season (P2: urut stage lalu nomor revisi).
-- *_pub = hanya revisi terbit (untuk role tanpa view_drafts, mis. Brand).
CREATE OR REPLACE VIEW v_model_list AS
SELECT m.id, m.code, m.name, m.category, m.factory, m.outsole_mold, m.last_no, m.construction,
       m.size_range, m.sample_size, m.updated_at, m.updated_by,
       (SELECT count(*) FROM specsheet x WHERE x.model_id = m.id) AS season_count,
       s.id AS specsheet_id, s.season, s.season_sort,
       (SELECT count(*) FROM article a WHERE a.specsheet_id = s.id) AS article_count,
       coalesce(s.season_sort = max(s.season_sort) OVER (PARTITION BY m.id), true) AS is_latest_season,
       ra.label AS spec_label, ra.active_articles AS spec_active_articles,
       rp.label AS spec_label_pub, rp.active_articles AS spec_active_articles_pub
  FROM product_model m
  LEFT JOIN specsheet s ON s.model_id = m.id
  LEFT JOIN LATERAL (
    SELECT r.stage || ' r' || r.revision_no || ' · ' || r.status AS label,
           (SELECT count(*) FROM revision_article x WHERE x.revision_id = r.id AND x.status = 'ACTIVE') AS active_articles
      FROM specsheet_revision r WHERE r.specsheet_id = s.id
     ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
  ) ra ON true
  LEFT JOIN LATERAL (
    SELECT r.stage || ' r' || r.revision_no || ' · ' || r.status AS label,
           (SELECT count(*) FROM revision_article x WHERE x.revision_id = r.id AND x.status = 'ACTIVE') AS active_articles
      FROM specsheet_revision r WHERE r.specsheet_id = s.id AND r.status = 'PUBLISHED'
     ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
  ) rp ON true;

-- Status article di specsheet: di revisi terbit terakhir (pub_*) dan di draft (draft_*).
CREATE OR REPLACE VIEW v_article_status AS
SELECT a.id, a.specsheet_id, s.model_id, s.season, a.code, a.colorway, a.updated_at, a.updated_by,
       (SELECT count(*) FROM article_attachment t WHERE t.article_id = a.id) AS attachment_count,
       fn_article_is_used(a.id) AS is_used,
       rp.stage || ' r' || rp.revision_no AS pub_label,
       (SELECT x.status FROM revision_article x WHERE x.revision_id = rp.id AND x.article_id = a.id) AS pub_status,
       rd.stage || ' r' || rd.revision_no AS draft_label,
       (SELECT x.status FROM revision_article x WHERE x.revision_id = rd.id AND x.article_id = a.id) AS draft_status
  FROM article a
  JOIN specsheet s ON s.id = a.specsheet_id
  LEFT JOIN LATERAL (
    SELECT r.id, r.stage, r.revision_no FROM specsheet_revision r
     WHERE r.specsheet_id = s.id AND r.status = 'PUBLISHED'
     ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
  ) rp ON true
  LEFT JOIN specsheet_revision rd ON rd.specsheet_id = s.id AND rd.status = 'DRAFT';
