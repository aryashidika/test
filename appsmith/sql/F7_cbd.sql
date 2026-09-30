-- ============================================================================
-- F7 — CBD: buat revisi & grid baris
-- Jalankan SETELAH F6, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
--
-- Aturan (= cbd_service.py, dengan penyederhanaan PLAN §2):
-- - CBD per ARTICLE. Acuan = revisi specsheet TERBIT terakhir season article itu (urut stage lalu nomor, P1).
--   Article harus ACTIVE di revisi itu (DROPPED / belum terbit -> CBD tidak bisa dibuat/diubah).
-- - Satu fungsi fn_cbd_create(mode):
--     NEW   article belum punya CBD -> baris dari specsheet, harga dari master
--     COPY  article belum punya CBD -> + Yield, Loss %, harga quotation/override, dan rekap dari CBD TERBIT
--           terakhir article lain MODEL YANG SAMA (season apa pun)
--     NEXT  article sudah punya CBD terbit -> + nilai dari CBD terbit terakhir article ini; baris sumber yang
--           tidak ada lagi di specsheet masuk sebagai MISSING_IN_SPEC
--   Stage CBD = stage specsheet acuan; nomor = terakhir di stage itu + 1 (atau 0).
-- - Baris CBD = baris BOM aktif yang dipakai article (sel berwarna), termasuk subkomponen (nomor & grup
--   ikut induknya). Pencocokan ke sumber: lineKey -> originLineKey -> identitas (komponen, no. lokal,
--   nama subkomponen, material); baris hasil "Ganti material" membawa Yield/Loss % baris yang diganti.
-- - Harga master (fn_price_lookup, hanya APPROVED) selalu diambil ulang; harga yang diinput di CBD
--   (OVERRIDE / QUOTATION, F8) ikut ter-copy bila material & metode harganya masih sama.
-- - Usage = 1 / Yield (kolom generated). Harga IDR/USD & cost/pair dihitung di view (v_cbd_line).
-- - Revisi CBD terbit terkunci (trigger); hanya sync_status / specsheet_revision_id yang boleh berubah (F8).
-- - Harga (quotation/override), rekap, refresh, terbit = F8.
-- ============================================================================

-- ---------------------------------------------------------------- Cek bentrok nama
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('cbd_revision', 'sync_status'), ('cbd_line', 'line_key')) AS t(tbl, col)
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
CREATE TABLE IF NOT EXISTS cbd_revision (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id             uuid NOT NULL REFERENCES article(id),
  stage                  text NOT NULL CHECK (stage IN ('PULL','SMS','GTM','PROD')),
  stage_order            smallint GENERATED ALWAYS AS
                         (CASE stage WHEN 'PULL' THEN 1 WHEN 'SMS' THEN 2 WHEN 'GTM' THEN 3 ELSE 4 END) STORED,
  revision_no            integer NOT NULL CHECK (revision_no >= 0),
  specsheet_revision_id  uuid NOT NULL REFERENCES specsheet_revision(id),
  exchange_rate          numeric(18,4) CHECK (exchange_rate > 0),
  amortization           numeric(18,4) NOT NULL DEFAULT 0,
  adjustment             numeric(18,4) NOT NULL DEFAULT 0,
  target_fob             numeric(18,4),
  selling_price          numeric(18,4),
  status                 text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','PUBLISHED')),
  sync_status            text NOT NULL DEFAULT 'IN_SYNC' CHECK (sync_status IN ('IN_SYNC','NEEDS_REVISION')),
  source_cbd_revision_id uuid REFERENCES cbd_revision(id) ON DELETE SET NULL,
  published_at           timestamptz,
  published_by           text,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_cbd_revision_no UNIQUE (article_id, stage, revision_no)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_one_cbd_draft ON cbd_revision (article_id) WHERE status = 'DRAFT';

CREATE TABLE IF NOT EXISTS cbd_line (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cbd_revision_id       uuid NOT NULL REFERENCES cbd_revision(id) ON DELETE CASCADE,
  line_key              uuid NOT NULL,
  component_id          uuid REFERENCES component(id),
  local_component_no    integer,
  sub_seq               integer,
  sub_name              text,
  material_id           uuid NOT NULL REFERENCES material(id),
  color                 text,
  supplier_id           uuid REFERENCES supplier(id),
  uom                   text NOT NULL,
  group_code            text NOT NULL REFERENCES component_group(code),
  yield_value           numeric(18,6) CHECK (yield_value > 0),
  usage_value           numeric GENERATED ALWAYS AS (1 / yield_value) STORED,   -- usage = 1 / yield
  loss_pct              numeric(9,4) NOT NULL DEFAULT 0 CHECK (loss_pct >= 0 AND loss_pct < 100),
  price_original        numeric(18,4) CHECK (price_original > 0),
  currency              text CHECK (currency IN ('IDR','USD')),
  price_source          text CHECK (price_source IN ('MASTER','OVERRIDE','QUOTATION')),
  material_price_id     uuid REFERENCES material_price(id),
  price_override_reason text,
  price_reference       text,
  status                text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','MISSING_IN_SPEC')),
  value_origin          text NOT NULL DEFAULT 'INPUT' CHECK (value_origin IN ('INPUT','COPIED','CARRIED_FROM_REPLACED')),
  value_source_ref      text,
  sort_order            integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_cbd_line_key UNIQUE (cbd_revision_id, line_key),
  CHECK ((price_original IS NULL) = (currency IS NULL)),
  CHECK (price_source <> 'OVERRIDE' OR btrim(coalesce(price_override_reason, '')) <> '')
);
CREATE INDEX IF NOT EXISTS idx_cbd_line_revision ON cbd_line (cbd_revision_id);

SELECT fn_setup_table('cbd_revision');
SELECT fn_setup_table('cbd_line');

-- ---------------------------------------------------------------- Kunci revisi terbit
-- Revisi CBD terbit: tidak bisa dihapus; yang boleh berubah hanya sync_status & specsheet_revision_id
-- (penandaan sinkron saat specsheet terbit, F8). Article tidak bisa dipindah.
CREATE OR REPLACE FUNCTION fn_cbd_revision_lock() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'PUBLISHED' THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'Revisi CBD % r% sudah diterbitkan dan tidak bisa dihapus.', OLD.stage, OLD.revision_no;
    END IF;
    IF (to_jsonb(NEW) - 'sync_status' - 'specsheet_revision_id' - 'updated_at' - 'updated_by')
       IS DISTINCT FROM (to_jsonb(OLD) - 'sync_status' - 'specsheet_revision_id' - 'updated_at' - 'updated_by') THEN
      RAISE EXCEPTION 'Revisi CBD % r% sudah diterbitkan dan tidak bisa diubah. Buat revisi baru untuk perubahan.',
        OLD.stage, OLD.revision_no;
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF NEW.article_id IS DISTINCT FROM OLD.article_id THEN
    RAISE EXCEPTION 'Article revisi CBD tidak bisa diubah.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cbd_revision_lock ON cbd_revision;
CREATE TRIGGER trg_cbd_revision_lock BEFORE UPDATE OR DELETE ON cbd_revision
  FOR EACH ROW EXECUTE FUNCTION fn_cbd_revision_lock();

-- Baris CBD revisi terbit tidak bisa diubah. Revisi yang sedang dihapus (hapus draft) tidak ditemukan lagi -> dibiarkan.
CREATE OR REPLACE FUNCTION fn_cbd_line_lock() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_status text;
BEGIN
  SELECT status INTO v_status FROM cbd_revision
   WHERE id = CASE WHEN TG_OP = 'DELETE' THEN OLD.cbd_revision_id ELSE NEW.cbd_revision_id END;
  IF v_status = 'PUBLISHED' THEN
    RAISE EXCEPTION 'Revisi CBD ini sudah diterbitkan dan tidak bisa diubah. Buat revisi baru untuk perubahan.';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lock_published ON cbd_line;
CREATE TRIGGER trg_lock_published BEFORE INSERT OR UPDATE OR DELETE ON cbd_line
  FOR EACH ROW EXECUTE FUNCTION fn_cbd_line_lock();

-- ---------------------------------------------------------------- Helper
-- Revisi specsheet TERBIT terakhir season ini (urut stage lalu nomor — P1), NULL bila belum ada.
CREATE OR REPLACE FUNCTION fn_spec_latest_pub(p_specsheet_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT id FROM specsheet_revision
   WHERE specsheet_id = p_specsheet_id AND status = 'PUBLISHED'
   ORDER BY stage_order DESC, revision_no DESC LIMIT 1
$$;

-- Status article di revisi specsheet terbit terakhir: ACTIVE / DROPPED / NOT_PUBLISHED.
CREATE OR REPLACE FUNCTION fn_cbd_article_spec_status(p_article_id uuid) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT ra.status FROM article a
                     JOIN revision_article ra ON ra.article_id = a.id AND ra.revision_id = fn_spec_latest_pub(a.specsheet_id)
                    WHERE a.id = p_article_id), 'NOT_PUBLISHED')
$$;

-- Revisi CBD DRAFT (dikunci untuk transaksi ini) yang article-nya masih ACTIVE di specsheet terbit, atau error.
CREATE OR REPLACE FUNCTION fn_cbd_draft(p_cbd_revision_id uuid) RETURNS cbd_revision
LANGUAGE plpgsql AS $$
DECLARE
  v_rev    cbd_revision%ROWTYPE;
  v_status text;
BEGIN
  SELECT * INTO v_rev FROM cbd_revision WHERE id = p_cbd_revision_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Revisi CBD tidak ditemukan.';
  END IF;
  IF v_rev.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'Revisi CBD ini sudah diterbitkan dan tidak bisa diubah. Buat revisi baru untuk perubahan.';
  END IF;
  v_status := fn_cbd_article_spec_status(v_rev.article_id);
  IF v_status = 'DROPPED' THEN
    RAISE EXCEPTION 'Article ini sudah di-drop di specsheet terbit terakhir — CBD-nya hanya bisa dilihat (draft boleh dihapus).';
  ELSIF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article ini belum ada di revisi specsheet yang terbit.';
  END IF;
  RETURN v_rev;
END;
$$;

-- Grup komponen (a/b/c/d): dari komponen master, atau dari rentang nomor untuk komponen lokal.
CREATE OR REPLACE FUNCTION fn_cbd_group_code(p_component_id uuid, p_local_no integer) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT group_code FROM component WHERE id = p_component_id),
                  (SELECT code FROM component_group WHERE p_local_no BETWEEN range_start AND range_end
                    ORDER BY sort_order LIMIT 1))
$$;

-- Kunci identitas (pencocokan terakhir setelah lineKey & originLineKey): komponen, no. lokal,
-- NAMA subkomponen (bukan nomor urut), material.
CREATE OR REPLACE FUNCTION fn_cbd_identity(p_component_id uuid, p_local_no integer, p_sub_seq integer,
                                           p_sub_name text, p_material_id uuid) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT concat_ws('|', coalesce(p_component_id::text, ''), coalesce(p_local_no::text, ''),
                   CASE WHEN p_sub_seq IS NOT NULL THEN fn_normalize(p_sub_name) ELSE '' END, p_material_id::text)
$$;

-- ---------------------------------------------------------------- Baris yang diharapkan
-- Baris BOM aktif revisi specsheet p_spec_rev_id yang dipakai article (sel berwarna). Kosong bila article
-- tidak ACTIVE di revisi itu. Subkomponen memakai komponen / no. lokal / grup induknya.
-- seq = urutan tampil: nomor komponen, urutan input, induk lalu subkomponennya.
CREATE OR REPLACE FUNCTION fn_cbd_expected_lines(p_article_id uuid, p_spec_rev_id uuid)
RETURNS TABLE (seq integer, line_key uuid, origin_line_key uuid, replaces_line_key uuid, component_id uuid,
               local_component_no integer, sub_seq integer, sub_name text, material_id uuid, color text,
               supplier_id uuid, uom text, group_code text)
LANGUAGE sql STABLE AS $$
  WITH lines AS (
    SELECT l.*, c.number AS comp_no
      FROM bom_line l LEFT JOIN component c ON c.id = l.component_id
     WHERE l.revision_id = p_spec_rev_id AND l.is_active
  ), x AS (
    SELECT l.line_key, l.origin_line_key, l.replaces_line_key,
           CASE WHEN l.parent_line_key IS NULL THEN l.component_id ELSE p.component_id END AS component_id,
           CASE WHEN l.parent_line_key IS NULL THEN l.local_component_no ELSE p.local_component_no END AS local_no,
           CASE WHEN l.parent_line_key IS NULL THEN coalesce(l.comp_no, l.local_component_no)
                ELSE coalesce(p.comp_no, p.local_component_no) END AS top_no,
           CASE WHEN l.parent_line_key IS NULL THEN l.sort_order ELSE coalesce(p.sort_order, l.sort_order) END AS top_sort,
           l.parent_line_key IS NOT NULL AS is_sub,
           l.sub_seq, l.sub_name, l.material_id, bc.color, l.supplier_id, m.uom
      FROM lines l
      LEFT JOIN lines p ON p.line_key = l.parent_line_key
      JOIN bom_cell bc ON bc.bom_line_id = l.id AND bc.article_id = p_article_id AND bc.is_used
      JOIN material m ON m.id = l.material_id
     WHERE EXISTS (SELECT 1 FROM revision_article ra
                    WHERE ra.revision_id = p_spec_rev_id AND ra.article_id = p_article_id AND ra.status = 'ACTIVE')
  )
  SELECT (row_number() OVER (ORDER BY x.top_no NULLS LAST, x.top_sort, x.is_sub, x.sub_seq))::integer,
         x.line_key, x.origin_line_key, x.replaces_line_key, x.component_id, x.local_no, x.sub_seq,
         CASE WHEN x.is_sub THEN x.sub_name END, x.material_id, x.color, x.supplier_id, x.uom,
         fn_cbd_group_code(x.component_id, x.local_no)
    FROM x
$$;

-- Isi baris revisi CBD p_revision_id dari specsheet p_spec_rev_id; nilai (Yield, Loss %, harga input CBD)
-- dari revisi CBD p_source_id bila ada. p_mark_missing: baris sumber yang tidak cocok -> MISSING_IN_SPEC
-- (hanya untuk revisi lanjutan article yang sama). Dipakai fn_cbd_create (F7) dan refresh dari specsheet (F8).
CREATE OR REPLACE FUNCTION fn_cbd_populate(p_revision_id uuid, p_article_id uuid, p_spec_rev_id uuid,
                                           p_source_id uuid, p_mark_missing boolean, p_ref text, p_email text)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  e         record;
  s         cbd_line%ROWTYPE;
  v_found   boolean;
  v_matched uuid[] := '{}';
  v_sort    integer := 0;
  v_yield   numeric;
  v_loss    numeric;
  v_origin  text;
  v_ref     text;
  v_carry   boolean;
  v_pid     uuid;
  v_price   numeric;
  v_cur     text;
BEGIN
  FOR e IN SELECT * FROM fn_cbd_expected_lines(p_article_id, p_spec_rev_id) ORDER BY seq LOOP
    v_found := false;
    v_yield := NULL; v_loss := 0; v_origin := 'INPUT'; v_ref := NULL; v_carry := false;
    IF p_source_id IS NOT NULL THEN
      SELECT * INTO s FROM cbd_line WHERE cbd_revision_id = p_source_id AND line_key = e.line_key;
      v_found := FOUND;
      IF NOT v_found AND e.origin_line_key IS NOT NULL THEN
        SELECT * INTO s FROM cbd_line WHERE cbd_revision_id = p_source_id AND line_key = e.origin_line_key;
        v_found := FOUND;
      END IF;
      IF NOT v_found THEN
        SELECT * INTO s FROM cbd_line
         WHERE cbd_revision_id = p_source_id
           AND fn_cbd_identity(component_id, local_component_no, sub_seq, sub_name, material_id)
             = fn_cbd_identity(e.component_id, e.local_component_no, e.sub_seq, e.sub_name, e.material_id)
         ORDER BY sort_order LIMIT 1;
        v_found := FOUND;
      END IF;
      IF v_found THEN
        v_matched := v_matched || s.line_key;
        v_yield := s.yield_value; v_loss := s.loss_pct; v_origin := 'COPIED'; v_ref := p_ref;
        -- harga input CBD ikut bila material sama dan metode harganya masih cocok
        v_carry := s.price_source IN ('OVERRIDE', 'QUOTATION') AND s.material_id = e.material_id
                   AND (s.price_source = 'QUOTATION') =
                       EXISTS (SELECT 1 FROM material WHERE id = e.material_id AND price_method = 'QUOTATION');
      ELSIF e.replaces_line_key IS NOT NULL THEN
        -- baris hasil "Ganti material": bawa Yield/Loss % baris lama, harga dari master material baru
        SELECT * INTO s FROM cbd_line WHERE cbd_revision_id = p_source_id AND line_key = e.replaces_line_key;
        IF FOUND THEN
          v_matched := v_matched || s.line_key;
          v_yield := s.yield_value; v_loss := s.loss_pct; v_origin := 'CARRIED_FROM_REPLACED';
        END IF;
      END IF;
    END IF;

    IF v_carry THEN
      INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                            material_id, color, supplier_id, uom, group_code, yield_value, loss_pct,
                            price_original, currency, price_source, material_price_id, price_override_reason,
                            price_reference, status, value_origin, value_source_ref, sort_order, updated_by)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.color, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              s.price_original, s.currency, s.price_source, NULL, s.price_override_reason,
              s.price_reference, 'ACTIVE', v_origin, v_ref, v_sort, p_email);
    ELSE
      v_pid := NULL; v_price := NULL; v_cur := NULL;
      IF e.supplier_id IS NOT NULL THEN
        SELECT price_id, price, currency INTO v_pid, v_price, v_cur
          FROM fn_price_lookup(e.material_id, e.supplier_id, e.color);
      END IF;
      INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                            material_id, color, supplier_id, uom, group_code, yield_value, loss_pct,
                            price_original, currency, price_source, material_price_id,
                            status, value_origin, value_source_ref, sort_order, updated_by)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.color, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              v_price, v_cur, CASE WHEN v_pid IS NOT NULL THEN 'MASTER' END, v_pid,
              'ACTIVE', v_origin, v_ref, v_sort, p_email);
    END IF;
    v_sort := v_sort + 1;
  END LOOP;

  IF p_mark_missing AND p_source_id IS NOT NULL THEN
    INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                          material_id, color, supplier_id, uom, group_code, yield_value, loss_pct,
                          price_original, currency, price_source, material_price_id, price_override_reason,
                          price_reference, status, value_origin, value_source_ref, sort_order, updated_by)
    SELECT p_revision_id, x.line_key, x.component_id, x.local_component_no, x.sub_seq, x.sub_name,
           x.material_id, x.color, x.supplier_id, x.uom, x.group_code, x.yield_value, x.loss_pct,
           x.price_original, x.currency, x.price_source, x.material_price_id, x.price_override_reason,
           x.price_reference, 'MISSING_IN_SPEC', x.value_origin, x.value_source_ref,
           v_sort + (row_number() OVER (ORDER BY x.sort_order))::integer, p_email
      FROM cbd_line x
     WHERE x.cbd_revision_id = p_source_id AND NOT (x.line_key = ANY (v_matched));
  END IF;
  RETURN v_sort;
END;
$$;

-- ---------------------------------------------------------------- Buat & hapus revisi CBD
CREATE OR REPLACE FUNCTION fn_cbd_create(p_token text, p_article_id uuid, p_mode text, p_source_article_id uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'edit_cbd');
  v_art    article%ROWTYPE;
  v_srcart article%ROWTYPE;
  v_spec   specsheet_revision%ROWTYPE;
  v_src    cbd_revision%ROWTYPE;
  v_status text;
  v_no     integer;
  v_ref    text;
  v_id     uuid;
BEGIN
  SELECT * INTO v_art FROM article WHERE id = p_article_id FOR UPDATE;   -- antre per article
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Article tidak ditemukan.';
  END IF;
  v_status := fn_cbd_article_spec_status(v_art.id);
  IF v_status = 'DROPPED' THEN
    RAISE EXCEPTION 'Article % sudah di-drop di specsheet terbit terakhir — CBD-nya tidak bisa dibuat lagi.', v_art.code;
  ELSIF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article % belum ada di revisi specsheet yang terbit. Terbitkan specsheet-nya dulu.', v_art.code;
  END IF;
  IF EXISTS (SELECT 1 FROM cbd_revision WHERE article_id = v_art.id AND status = 'DRAFT') THEN
    RAISE EXCEPTION 'Sudah ada CBD DRAFT untuk article %. Terbitkan atau hapus draft itu dulu.', v_art.code;
  END IF;
  SELECT * INTO v_spec FROM specsheet_revision WHERE id = fn_spec_latest_pub(v_art.specsheet_id);

  IF p_mode IN ('NEW', 'COPY') THEN
    IF EXISTS (SELECT 1 FROM cbd_revision WHERE article_id = v_art.id) THEN
      RAISE EXCEPTION 'Article % sudah punya CBD. Pakai Revisi berikutnya.', v_art.code;
    END IF;
    IF p_mode = 'COPY' THEN
      SELECT * INTO v_srcart FROM article WHERE id = p_source_article_id;
      IF NOT FOUND OR v_srcart.id = v_art.id THEN
        RAISE EXCEPTION 'Pilih article sumber.';
      END IF;
      IF (SELECT model_id FROM specsheet WHERE id = v_srcart.specsheet_id)
         IS DISTINCT FROM (SELECT model_id FROM specsheet WHERE id = v_art.specsheet_id) THEN
        RAISE EXCEPTION 'CBD hanya bisa di-copy dari article model yang sama.';
      END IF;
      SELECT * INTO v_src FROM cbd_revision
       WHERE article_id = v_srcart.id AND status = 'PUBLISHED'
       ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Article % belum punya CBD terbit untuk di-copy.', v_srcart.code;
      END IF;
    END IF;
  ELSIF p_mode = 'NEXT' THEN
    SELECT * INTO v_src FROM cbd_revision
     WHERE article_id = v_art.id AND status = 'PUBLISHED'
     ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Article % belum punya CBD terbit.', v_art.code;
    END IF;
  ELSE
    RAISE EXCEPTION 'Pilih cara membuat CBD.';
  END IF;

  SELECT coalesce(max(revision_no) + 1, 0) INTO v_no
    FROM cbd_revision WHERE article_id = v_art.id AND stage = v_spec.stage;

  -- Rekap (rate, amortisasi, adjustment, target FOB, selling price) ikut dari sumber
  INSERT INTO cbd_revision (article_id, stage, revision_no, specsheet_revision_id, exchange_rate, amortization,
                            adjustment, target_fob, selling_price, source_cbd_revision_id, updated_by)
  VALUES (v_art.id, v_spec.stage, v_no, v_spec.id, v_src.exchange_rate, coalesce(v_src.amortization, 0),
          coalesce(v_src.adjustment, 0), v_src.target_fob, v_src.selling_price, v_src.id, v_email)
  RETURNING id INTO v_id;

  IF v_src.id IS NOT NULL THEN
    SELECT sp.season || ' / ' || a.code || ' / ' || v_src.stage || ' r' || v_src.revision_no INTO v_ref
      FROM article a JOIN specsheet sp ON sp.id = a.specsheet_id WHERE a.id = v_src.article_id;
  END IF;
  PERFORM fn_cbd_populate(v_id, v_art.id, v_spec.id, v_src.id, p_mode = 'NEXT', v_ref, v_email);
  RETURN v_id;
END;
$$;

-- Hapus revisi CBD DRAFT beserta barisnya (boleh juga bila article sudah di-drop).
CREATE OR REPLACE FUNCTION fn_cbd_delete_draft(p_token text, p_cbd_revision_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_cbd');
  v_rev   cbd_revision%ROWTYPE;
BEGIN
  SELECT * INTO v_rev FROM cbd_revision WHERE id = p_cbd_revision_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Revisi CBD tidak ditemukan.';
  END IF;
  IF v_rev.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'Revisi CBD ini sudah diterbitkan dan tidak bisa dihapus.';
  END IF;
  DELETE FROM cbd_revision WHERE id = v_rev.id;
  RETURN v_rev.id;
END;
$$;

-- ---------------------------------------------------------------- Edit nilai baris
-- p_field: 'YIELD' (NULL = kosongkan) atau 'LOSS' (NULL = 0). Hanya baris ACTIVE di revisi DRAFT.
CREATE OR REPLACE FUNCTION fn_cbd_line_set(p_token text, p_line_id uuid, p_field text, p_value numeric)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_cbd');
  v_line  cbd_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM cbd_line WHERE id = p_line_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Baris CBD tidak ditemukan. Muat ulang halaman.';
  END IF;
  PERFORM fn_cbd_draft(v_line.cbd_revision_id);
  IF v_line.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Baris ini sudah tidak ada di specsheet (MISSING_IN_SPEC) dan tidak bisa diubah.';
  END IF;
  IF p_field = 'YIELD' THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION 'Yield harus lebih besar dari 0.';
    END IF;
    UPDATE cbd_line SET yield_value = p_value, value_origin = 'INPUT', updated_by = v_email WHERE id = v_line.id;
  ELSIF p_field = 'LOSS' THEN
    IF coalesce(p_value, 0) < 0 OR coalesce(p_value, 0) >= 100 THEN
      RAISE EXCEPTION 'Loss %% harus 0 sampai kurang dari 100.';
    END IF;
    UPDATE cbd_line SET loss_pct = coalesce(p_value, 0), value_origin = 'INPUT', updated_by = v_email WHERE id = v_line.id;
  ELSE
    RAISE EXCEPTION 'Kolom tidak valid.';
  END IF;
  RETURN v_line.id;
END;
$$;

-- ---------------------------------------------------------------- View
-- Baris CBD + tampilan + hitungan. Harga IDR = IDR apa adanya / USD x rate; USD = USD apa adanya / IDR : rate
-- (NULL bila rate kosong). cost_per_pair (Rp) = usage x harga IDR x (1 + loss %/100); NULL bila belum lengkap.
-- Remarks & thickness dibaca live (baris BOM acuan & Master Material).
-- Urutan tampil: ORDER BY status, group_sort, comp_no NULLS LAST, sort_order.
CREATE OR REPLACE VIEW v_cbd_line AS
SELECT cl.id, cl.cbd_revision_id, cl.line_key, cl.status, cl.group_code, g.name AS group_name, g.sort_order AS group_sort,
       coalesce(c.number, cl.local_component_no) AS comp_no,
       CASE WHEN cl.sub_seq IS NOT NULL
            THEN coalesce(coalesce(c.number, cl.local_component_no)::text || '-', '') || cl.sub_seq
            ELSE coalesce(c.number, cl.local_component_no)::text END AS display_no,
       CASE WHEN cl.sub_seq IS NOT NULL THEN coalesce(cl.sub_name, m.name)
            ELSE coalesce(c.name, bl.local_component_name, 'Lokal ' || cl.local_component_no, m.name) END AS display_name,
       (cl.sub_seq IS NOT NULL) AS is_sub,
       (cl.component_id IS NULL AND cl.sub_seq IS NULL) AS is_local,
       cl.material_id, m.material_code, m.name AS material_name, m.thickness, m.price_method,
       cl.color, cl.supplier_id, s.name AS supplier_name, cl.uom, bl.process AS remarks,
       cl.yield_value, cl.usage_value, cl.loss_pct,
       cl.price_original, cl.currency, cl.price_source, cl.material_price_id,
       mp.color AS master_price_color, mp.valid_from AS master_price_valid_from,
       cl.price_override_reason, cl.price_reference,
       x.price_usd, x.price_idr,
       cl.usage_value * x.price_idr * (1 + cl.loss_pct / 100) AS cost_per_pair,
       cl.value_origin, cl.value_source_ref, cl.sort_order
  FROM cbd_line cl
  JOIN cbd_revision cr ON cr.id = cl.cbd_revision_id
  JOIN material m ON m.id = cl.material_id
  LEFT JOIN component c ON c.id = cl.component_id
  LEFT JOIN component_group g ON g.code = cl.group_code
  LEFT JOIN supplier s ON s.id = cl.supplier_id
  LEFT JOIN material_price mp ON mp.id = cl.material_price_id
  LEFT JOIN bom_line bl ON bl.revision_id = cr.specsheet_revision_id AND bl.line_key = cl.line_key
  CROSS JOIN LATERAL (
    SELECT CASE cl.currency WHEN 'IDR' THEN cl.price_original
                            WHEN 'USD' THEN cl.price_original * cr.exchange_rate END AS price_idr,
           CASE cl.currency WHEN 'USD' THEN cl.price_original
                            WHEN 'IDR' THEN cl.price_original / nullif(cr.exchange_rate, 0) END AS price_usd
  ) x;

-- Status CBD per article (chip di page CBD). spec_status: ACTIVE / DROPPED / NOT_PUBLISHED.
-- draft_stale = draft masih mengacu ke revisi specsheet yang bukan terbit terakhir (refresh di F8).
CREATE OR REPLACE VIEW v_cbd_article AS
SELECT a.id, a.specsheet_id, sh.model_id, sh.season, a.code, a.colorway,
       sp.id AS spec_pub_id, sp.stage || ' r' || sp.revision_no AS spec_pub_label, sp.stage AS spec_pub_stage,
       fn_cbd_article_spec_status(a.id) AS spec_status,
       d.id AS draft_id, d.stage || ' r' || d.revision_no AS draft_label,
       (d.id IS NOT NULL AND d.specsheet_revision_id IS DISTINCT FROM sp.id) AS draft_stale,
       p.id AS pub_id, p.stage || ' r' || p.revision_no AS pub_label, p.sync_status AS pub_sync,
       (SELECT count(*)::int FROM cbd_revision x WHERE x.article_id = a.id) AS revision_count
  FROM article a
  JOIN specsheet sh ON sh.id = a.specsheet_id
  LEFT JOIN specsheet_revision sp ON sp.id = fn_spec_latest_pub(sh.id)
  LEFT JOIN cbd_revision d ON d.article_id = a.id AND d.status = 'DRAFT'
  LEFT JOIN LATERAL (
    SELECT r.id, r.stage, r.revision_no, r.sync_status FROM cbd_revision r
     WHERE r.article_id = a.id AND r.status = 'PUBLISHED'
     ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
  ) p ON true;

-- ---------------------------------------------------------------- View F5 diperluas (kolom baru di akhir)
-- Model Detail: status article di CBD (terbit terakhir + draft).
CREATE OR REPLACE VIEW v_article_status AS
SELECT a.id, a.specsheet_id, s.model_id, s.season, a.code, a.colorway, a.updated_at, a.updated_by,
       (SELECT count(*) FROM article_attachment t WHERE t.article_id = a.id) AS attachment_count,
       fn_article_is_used(a.id) AS is_used,
       rp.stage || ' r' || rp.revision_no AS pub_label,
       (SELECT x.status FROM revision_article x WHERE x.revision_id = rp.id AND x.article_id = a.id) AS pub_status,
       rd.stage || ' r' || rd.revision_no AS draft_label,
       (SELECT x.status FROM revision_article x WHERE x.revision_id = rd.id AND x.article_id = a.id) AS draft_status,
       cp.stage || ' r' || cp.revision_no AS cbd_pub_label,
       cp.sync_status AS cbd_pub_sync,
       cd.stage || ' r' || cd.revision_no AS cbd_draft_label
  FROM article a
  JOIN specsheet s ON s.id = a.specsheet_id
  LEFT JOIN LATERAL (
    SELECT r.id, r.stage, r.revision_no FROM specsheet_revision r
     WHERE r.specsheet_id = s.id AND r.status = 'PUBLISHED'
     ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
  ) rp ON true
  LEFT JOIN specsheet_revision rd ON rd.specsheet_id = s.id AND rd.status = 'DRAFT'
  LEFT JOIN LATERAL (
    SELECT r.stage, r.revision_no, r.sync_status FROM cbd_revision r
     WHERE r.article_id = a.id AND r.status = 'PUBLISHED'
     ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
  ) cp ON true
  LEFT JOIN cbd_revision cd ON cd.article_id = a.id AND cd.status = 'DRAFT';
