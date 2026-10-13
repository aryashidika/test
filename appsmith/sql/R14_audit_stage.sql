-- ============================================================================
-- R14: stage Preview + label stage (13 Okt 2026, keputusan user).
-- Jalankan SETELAH R13_cbd_stage.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi.
--
-- 1. Stage jadi 5: PULL, PREV (baru), SMS, GTM, PROD. Kode pendek tetap di DB; tampilan memakai label
--    Pullover, Preview, SMS, GTM, Production (fn_stage_label / fn_rev_label). Data lama tidak diubah kodenya.
-- 2. stage_order bukan lagi kolom generated (PostgreSQL 16 tidak bisa mengubah rumusnya): jadi kolom biasa yang
--    diisi trigger dari fn_stage_order(); nilai lama dinomori ulang 1..5 tanpa memicu audit / kunci revisi.
-- 3. Stage berikutnya boleh melompat: fn_revision_create mode NEXT_STAGE menerima p_stage (lebih tinggi dari
--    stage terbit terakhir); kosong = stage berikutnya (Pullover -> Preview).
-- 4. CBD bisa dibuat di kelima stage (fn_cbd_stage_options / fn_cbd_create memakai fn_stages()).
-- Detail audit (R14 bagian app) tidak butuh perubahan DB: q_audit membuang kunci rahasia di query.
-- Pesan baru dalam bahasa Inggris; pesan lama diterjemahkan di R15.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_cbd_stage_options(text,uuid)') IS NULL
     OR to_regprocedure('fn_spec_latest_pub_stage(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'R13 is not installed. Run sql/R13_cbd_stage.sql first.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- helper stage (satu sumber urutan & label)
CREATE OR REPLACE FUNCTION fn_stages() RETURNS text[]
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT ARRAY['PULL', 'PREV', 'SMS', 'GTM', 'PROD']
$$;

CREATE OR REPLACE FUNCTION fn_stage_order(p_stage text) RETURNS smallint
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT array_position(fn_stages(), p_stage)::smallint
$$;

CREATE OR REPLACE FUNCTION fn_stage_label(p_stage text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE p_stage WHEN 'PULL' THEN 'Pullover' WHEN 'PREV' THEN 'Preview' WHEN 'PROD' THEN 'Production'
                      ELSE p_stage END
$$;

-- 'Pullover r0'. NULL bila stage atau nomor kosong (dipakai di LEFT JOIN).
CREATE OR REPLACE FUNCTION fn_rev_label(p_stage text, p_no integer) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT fn_stage_label(p_stage) || ' r' || p_no
$$;

-- ---------------------------------------------------------------- tabel: CHECK stage + stage_order
CREATE OR REPLACE FUNCTION fn_stage_order_set() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.stage_order := fn_stage_order(NEW.stage);
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['specsheet_revision', 'cbd_revision', 'stage_setting'] LOOP
    EXECUTE format('ALTER TABLE %I DROP CONSTRAINT IF EXISTS %I', t, t || '_stage_check');
    EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I CHECK (stage IN (''PULL'', ''PREV'', ''SMS'', ''GTM'', ''PROD''))',
                   t, t || '_stage_check');
  END LOOP;

  FOREACH t IN ARRAY ARRAY['specsheet_revision', 'cbd_revision'] LOOP
    IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = t::regclass AND attname = 'stage_order'
                                            AND attgenerated = 's') THEN
      EXECUTE format('ALTER TABLE %I ALTER COLUMN stage_order DROP EXPRESSION', t);
    END IF;
    -- nomor ulang tanpa trigger (audit, updated_at, kunci revisi terbit): bukan perubahan oleh user
    EXECUTE format('ALTER TABLE %I DISABLE TRIGGER USER', t);
    EXECUTE format('UPDATE %I SET stage_order = fn_stage_order(stage)
                     WHERE stage_order IS DISTINCT FROM fn_stage_order(stage)', t);
    EXECUTE format('ALTER TABLE %I ENABLE TRIGGER USER', t);
    EXECUTE format('ALTER TABLE %I ALTER COLUMN stage_order SET NOT NULL', t);
    EXECUTE format('CREATE OR REPLACE TRIGGER trg_stage_order BEFORE INSERT OR UPDATE ON %I
                    FOR EACH ROW EXECUTE FUNCTION fn_stage_order_set()', t);
  END LOOP;
END;
$$;

-- Preview tanpa faktor PO (hanya SMS yang punya PO)
INSERT INTO stage_setting (stage, po_factor) VALUES ('PREV', NULL) ON CONFLICT (stage) DO NOTHING;

-- ---------------------------------------------------------------- label stage di view (kolom sama, hanya label)
CREATE OR REPLACE VIEW v_article_status AS
SELECT a.id, a.specsheet_id, s.model_id, s.season, a.code, a.colorway, a.updated_at, a.updated_by,
       (SELECT count(*) FROM article_attachment t WHERE t.article_id = a.id) AS attachment_count,
       fn_article_is_used(a.id) AS is_used,
       fn_rev_label(rp.stage, rp.revision_no) AS pub_label,
       (SELECT x.status FROM revision_article x WHERE x.revision_id = rp.id AND x.article_id = a.id) AS pub_status,
       fn_rev_label(rd.stage, rd.revision_no) AS draft_label,
       (SELECT x.status FROM revision_article x WHERE x.revision_id = rd.id AND x.article_id = a.id) AS draft_status,
       fn_rev_label(cp.stage, cp.revision_no) AS cbd_pub_label,
       cp.sync_status AS cbd_pub_sync,
       fn_rev_label(cd.stage, cd.revision_no) AS cbd_draft_label
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

CREATE OR REPLACE VIEW v_model_list AS
SELECT m.id, m.factory_id, m.factory_name, m.name, m.category, m.construction, m.gender, m.last_no, m.outsole_mold,
       m.size_range, m.sample_size, m.updated_at, m.updated_by,
       (SELECT count(*) FROM specsheet x WHERE x.model_id = m.id) AS season_count,
       s.id AS specsheet_id, s.season, s.season_sort,
       (SELECT count(*) FROM article a WHERE a.specsheet_id = s.id) AS article_count,
       coalesce(s.season_sort = max(s.season_sort) OVER (PARTITION BY m.id), true) AS is_latest_season,
       ra.label AS spec_label, ra.active_articles AS spec_active_articles,
       rp.label AS spec_label_pub, rp.active_articles AS spec_active_articles_pub
  FROM v_model m
  LEFT JOIN specsheet s ON s.model_id = m.id
  LEFT JOIN LATERAL (
    SELECT fn_rev_label(r.stage, r.revision_no) || ' · ' || r.status AS label,
           (SELECT count(*) FROM revision_article x WHERE x.revision_id = r.id AND x.status = 'ACTIVE') AS active_articles
      FROM specsheet_revision r WHERE r.specsheet_id = s.id
     ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
  ) ra ON true
  LEFT JOIN LATERAL (
    SELECT fn_rev_label(r.stage, r.revision_no) || ' · ' || r.status AS label,
           (SELECT count(*) FROM revision_article x WHERE x.revision_id = r.id AND x.status = 'ACTIVE') AS active_articles
      FROM specsheet_revision r WHERE r.specsheet_id = s.id AND r.status = 'PUBLISHED'
     ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
  ) rp ON true;

CREATE OR REPLACE VIEW v_cbd_article AS
SELECT a.id, a.specsheet_id, sh.model_id, sh.season, a.code, a.colorway,
       sp.id AS spec_pub_id, fn_rev_label(sp.stage, sp.revision_no) AS spec_pub_label, sp.stage AS spec_pub_stage,
       fn_cbd_article_spec_status(a.id) AS spec_status,
       d.id AS draft_id, fn_rev_label(d.stage, d.revision_no) AS draft_label,
       (d.id IS NOT NULL AND d.specsheet_revision_id IS DISTINCT FROM ds.id) AS draft_stale,
       p.id AS pub_id, fn_rev_label(p.stage, p.revision_no) AS pub_label, p.sync_status AS pub_sync,
       (SELECT count(*)::int FROM cbd_revision x WHERE x.article_id = a.id) AS revision_count,
       fn_rev_label(ds.stage, ds.revision_no) AS draft_spec_label,
       coalesce(p.stage_order < sp.stage_order, false) AS pub_behind
  FROM article a
  JOIN specsheet sh ON sh.id = a.specsheet_id
  LEFT JOIN specsheet_revision sp ON sp.id = fn_spec_latest_pub(sh.id)
  LEFT JOIN cbd_revision d ON d.article_id = a.id AND d.status = 'DRAFT'
  LEFT JOIN specsheet_revision ds ON ds.id = fn_spec_latest_pub_stage(sh.id, d.stage)
  LEFT JOIN LATERAL (
    SELECT r.id, r.stage, r.revision_no, r.sync_status, r.stage_order FROM cbd_revision r
     WHERE r.article_id = a.id AND r.status = 'PUBLISHED'
     ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
  ) p ON true;

CREATE OR REPLACE VIEW v_worklist_cbd AS
WITH art AS MATERIALIZED (
  SELECT a.id, a.code, a.colorway, a.specsheet_id, sh.season, sh.model_id, sp.id AS spec_pub_id,
         sp.stage_order AS spec_stage_order
    FROM specsheet sh
    JOIN specsheet_revision sp ON sp.id = fn_spec_latest_pub(sh.id)
    JOIN revision_article ra ON ra.revision_id = sp.id AND ra.status = 'ACTIVE'
    JOIN article a ON a.id = ra.article_id
)
SELECT x.kind, x.refresh_reason, x.article_id, x.article_code, x.colorway, x.model_id, x.model_name, x.factory_id,
       x.specsheet_id, x.season, x.cbd_revision_id, x.rev_label, x.pending_prices
  FROM (
    SELECT CASE WHEN rc.n = 0 THEN 'TO_CREATE'
                WHEN d.id IS NOT NULL
                     THEN CASE WHEN d.specsheet_revision_id IS DISTINCT FROM ds.spec_id OR pr.stale_prices > 0
                               THEN 'TO_REFRESH' ELSE 'IN_PROGRESS' END
                WHEN p.stage_order < art.spec_stage_order OR p.sync_status = 'NEEDS_REVISION' THEN 'TO_REVISE' END AS kind,
           CASE WHEN d.id IS NOT NULL
                THEN CASE WHEN d.specsheet_revision_id IS DISTINCT FROM ds.spec_id THEN 'SPEC'
                          WHEN pr.stale_prices > 0 THEN 'PRICE' END
                WHEN p.stage_order < art.spec_stage_order THEN 'STAGE' END AS refresh_reason,
           art.id AS article_id, art.code AS article_code, art.colorway,
           pm.id AS model_id, pm.name AS model_name, pm.factory_id,
           art.specsheet_id, art.season,
           coalesce(d.id, p.id) AS cbd_revision_id,
           coalesce(fn_rev_label(d.stage, d.revision_no), fn_rev_label(p.stage, p.revision_no)) AS rev_label,
           pr.pending_prices
      FROM art
      JOIN product_model pm ON pm.id = art.model_id
      LEFT JOIN cbd_revision d ON d.article_id = art.id AND d.status = 'DRAFT'
      LEFT JOIN LATERAL (SELECT fn_spec_latest_pub_stage(art.specsheet_id, d.stage) AS spec_id) ds ON d.id IS NOT NULL
      LEFT JOIN LATERAL (
        SELECT r.id, r.stage, r.revision_no, r.sync_status, r.stage_order
          FROM cbd_revision r
         WHERE r.article_id = art.id AND r.status = 'PUBLISHED'
         ORDER BY r.stage_order DESC, r.revision_no DESC
         LIMIT 1
      ) p ON true
      CROSS JOIN LATERAL (SELECT count(*)::integer AS n FROM cbd_revision c WHERE c.article_id = art.id) rc
      CROSS JOIN LATERAL (
        SELECT (count(*) FILTER (WHERE pc.master_stale))::integer AS stale_prices,
               (count(*) FILTER (WHERE pc.pending))::integer AS pending_prices
          FROM v_cbd_price_check pc
         WHERE pc.cbd_revision_id = d.id
      ) pr
  ) x
 WHERE x.kind IS NOT NULL;

-- ---------------------------------------------------------------- label stage di fungsi
-- Sama dengan R11, hanya label revisi sebelumnya.
CREATE OR REPLACE FUNCTION fn_cbd_bridge_view(p_token text, p_rev uuid)
RETURNS TABLE (seq integer, key text, category text, category_label text, description text, amount numeric,
               prev_label text, prev_fob numeric, fob numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
  v_email text := fn_auth_in(p_token, 'view_cbd', fn_cbd_factory(p_rev));
  v_rev   cbd_revision%ROWTYPE;
  v_prev  cbd_revision%ROWTYPE;
  v_diff  jsonb;
BEGIN
  SELECT * INTO v_rev FROM cbd_revision WHERE id = p_rev;
  IF v_rev.status = 'DRAFT' AND NOT fn_has_perm(v_email, 'view_drafts') THEN
    RETURN;
  END IF;
  IF v_rev.status = 'PUBLISHED' THEN
    SELECT cl.diff INTO v_diff FROM change_log cl
     WHERE cl.doc_type = 'CBD' AND cl.revision_id = p_rev ORDER BY cl.created_at DESC LIMIT 1;
    IF v_diff IS NULL OR jsonb_typeof(v_diff -> 'rows') <> 'array' THEN
      RETURN;
    END IF;
    RETURN QUERY
      SELECT (r ->> 'seq')::integer, r ->> 'key', r ->> 'category', fn_change_category_label(r ->> 'category'),
             r ->> 'description', (r ->> 'amount')::numeric,
             v_diff ->> 'prev_label', (v_diff ->> 'prev_fob')::numeric, (v_diff ->> 'fob')::numeric
        FROM jsonb_array_elements(v_diff -> 'rows') r
       ORDER BY (r ->> 'seq')::integer;
    RETURN;
  END IF;
  SELECT * INTO v_prev FROM cbd_revision WHERE id = fn_cbd_prev_published(p_rev);
  IF NOT FOUND THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT b.seq, b.key, b.category, fn_change_category_label(b.category), b.description, b.amount,
           fn_rev_label(v_prev.stage, v_prev.revision_no),
           (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = v_prev.id),
           (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = p_rev)
      FROM fn_cbd_bridge(p_rev) b
     ORDER BY b.seq;
END;
$$;

-- Sama dengan R13: 5 stage (fn_stages) + label.
CREATE OR REPLACE FUNCTION fn_cbd_stage_options(p_token text, p_article_id uuid)
RETURNS TABLE (stage text, stage_order integer, spec_revision_id uuid, spec_label text, next_no integer,
               next_label text, available boolean, note text, is_default boolean)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_article_factory(p_article_id));
BEGIN
  RETURN QUERY
  WITH a AS (SELECT * FROM article WHERE id = p_article_id),
  maxpub AS (SELECT max(r.stage_order) AS o,
                    (array_agg(r.stage ORDER BY r.stage_order DESC))[1] AS s
               FROM cbd_revision r WHERE r.article_id = p_article_id AND r.status = 'PUBLISHED'),
  st AS (
    SELECT s.stage, s.ord::integer AS ord, sr.id AS sid, fn_rev_label(sr.stage, sr.revision_no) AS slabel,
           coalesce(ra.status, 'NOT_PUBLISHED') AS art_status,
           (SELECT coalesce(max(c.revision_no) + 1, 0)::integer FROM cbd_revision c
             WHERE c.article_id = p_article_id AND c.stage = s.stage) AS nno
      FROM unnest(fn_stages()) WITH ORDINALITY s(stage, ord)
      CROSS JOIN a
      JOIN specsheet_revision sr ON sr.id = fn_spec_latest_pub_stage(a.specsheet_id, s.stage)
      LEFT JOIN revision_article ra ON ra.revision_id = sr.id AND ra.article_id = a.id
  ),
  ev AS (
    SELECT st.*, (ov.s = 'ACTIVE' AND st.art_status = 'ACTIVE' AND (m.o IS NULL OR st.ord >= m.o)) AS ok,
           CASE WHEN ov.s = 'DROPPED' THEN 'Article di-drop di specsheet terbit terakhir'
                WHEN ov.s <> 'ACTIVE' THEN 'Article tidak ada di specsheet terbit terakhir'
                WHEN st.art_status = 'DROPPED' THEN 'Article di-drop di specsheet ' || st.slabel
                WHEN st.art_status <> 'ACTIVE' THEN 'Article tidak ada di specsheet ' || st.slabel
                WHEN m.o IS NOT NULL AND st.ord < m.o THEN 'Sudah ada CBD ' || fn_stage_label(m.s) || ' terbit'
           END AS why
      FROM st CROSS JOIN maxpub m
      CROSS JOIN (SELECT fn_cbd_article_spec_status(p_article_id) AS s) ov
  )
  SELECT ev.stage, ev.ord, ev.sid, ev.slabel, ev.nno, fn_rev_label(ev.stage, ev.nno), ev.ok, ev.why,
         ev.ok AND ev.ord = (SELECT max(e2.ord) FROM ev e2 WHERE e2.ok)
    FROM ev
   ORDER BY ev.ord;
END;
$$;

-- Sama dengan R13: 5 stage (fn_stages) + label sumber.
CREATE OR REPLACE FUNCTION fn_cbd_create(p_token text, p_article_id uuid, p_mode text, p_source_article_id uuid,
                                         p_stage text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_article_factory(p_article_id));
  v_art    article%ROWTYPE;
  v_srcart article%ROWTYPE;
  v_spec   specsheet_revision%ROWTYPE;
  v_src    cbd_revision%ROWTYPE;
  v_lines  cbd_line[];
  v_status text;
  v_stage  text;
  v_maxpub cbd_revision%ROWTYPE;
  v_no     integer;
  v_ref    text;
  v_cross  boolean := false;
  v_model  uuid;
  v_smodel uuid;
  v_origin uuid;
  v_id     uuid;
BEGIN
  SELECT * INTO v_art FROM article WHERE id = p_article_id FOR UPDATE;   -- antre per article
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Article tidak ditemukan.';
  END IF;
  v_status := fn_cbd_article_spec_status(v_art.id);
  IF v_status = 'DROPPED' THEN
    RAISE EXCEPTION 'Article % sudah di-drop di specsheet terbit terakhir. CBD-nya tidak bisa dibuat lagi.', v_art.code;
  ELSIF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article % belum ada di revisi specsheet yang terbit. Terbitkan specsheet-nya dulu.', v_art.code;
  END IF;
  IF EXISTS (SELECT 1 FROM cbd_revision WHERE article_id = v_art.id AND status = 'DRAFT') THEN
    RAISE EXCEPTION 'Sudah ada CBD DRAFT untuk article %. Terbitkan atau hapus draft itu dulu.', v_art.code;
  END IF;

  -- R13: stage dipilih (default stage specsheet terbit terbaru); acuan = specsheet terbit terakhir di stage itu
  v_stage := coalesce(nullif(btrim(coalesce(p_stage, '')), ''),
                      (SELECT stage FROM specsheet_revision WHERE id = fn_spec_latest_pub(v_art.specsheet_id)));
  IF NOT (v_stage = ANY (fn_stages())) THEN
    RAISE EXCEPTION 'Stage % tidak dikenal.', v_stage;
  END IF;
  SELECT * INTO v_spec FROM specsheet_revision WHERE id = fn_spec_latest_pub_stage(v_art.specsheet_id, v_stage);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Specsheet % untuk article % belum ada yang terbit.', v_stage, v_art.code;
  END IF;
  IF fn_cbd_stage_spec_status(v_art.id, v_stage) <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article % tidak aktif di specsheet % r%. CBD % tidak bisa dibuat.',
      v_art.code, v_spec.stage, v_spec.revision_no, v_stage;
  END IF;
  SELECT * INTO v_maxpub FROM cbd_revision
   WHERE article_id = v_art.id AND status = 'PUBLISHED'
   ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
  IF FOUND AND v_maxpub.stage_order > v_spec.stage_order THEN
    RAISE EXCEPTION 'Article % sudah punya CBD % terbit. CBD stage sebelumnya (%) tidak bisa dibuat lagi.',
      v_art.code, v_maxpub.stage, v_stage;
  END IF;

  IF p_mode IN ('NEW', 'COPY') THEN
    IF EXISTS (SELECT 1 FROM cbd_revision WHERE article_id = v_art.id) THEN
      RAISE EXCEPTION 'Article % sudah punya CBD. Pakai Revisi berikutnya.', v_art.code;
    END IF;
    IF p_mode = 'COPY' THEN
      SELECT * INTO v_srcart FROM article WHERE id = p_source_article_id;
      IF NOT FOUND OR v_srcart.id = v_art.id THEN
        RAISE EXCEPTION 'Pilih article sumber.';
      END IF;
      v_model  := (SELECT model_id FROM specsheet WHERE id = v_art.specsheet_id);
      v_smodel := (SELECT model_id FROM specsheet WHERE id = v_srcart.specsheet_id);
      IF v_smodel IS DISTINCT FROM v_model THEN
        v_origin := fn_sheet_origin_model(v_art.specsheet_id);
        IF v_origin IS NULL OR v_smodel IS DISTINCT FROM v_origin THEN
          RAISE EXCEPTION 'CBD hanya bisa di-copy dari article model yang sama, atau dari model asal specsheet ini (copy lintas model).';
        END IF;
        v_cross := true;
      END IF;
      SELECT * INTO v_src FROM cbd_revision
       WHERE article_id = v_srcart.id AND status = 'PUBLISHED'
       ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Article % belum punya CBD terbit untuk di-copy.', v_srcart.code;
      END IF;
    END IF;
  ELSIF p_mode = 'NEXT' THEN
    IF v_maxpub.id IS NULL THEN
      RAISE EXCEPTION 'Article % belum punya CBD terbit.', v_art.code;
    END IF;
    v_src := v_maxpub;
  ELSE
    RAISE EXCEPTION 'Pilih cara membuat CBD.';
  END IF;

  SELECT coalesce(max(revision_no) + 1, 0) INTO v_no
    FROM cbd_revision WHERE article_id = v_art.id AND stage = v_spec.stage;

  -- Rekap ikut dari sumber; lintas model: Target FOB kosong
  INSERT INTO cbd_revision (article_id, stage, revision_no, specsheet_revision_id, exchange_rate,
                            target_fob, source_cbd_revision_id, updated_by)
  VALUES (v_art.id, v_spec.stage, v_no, v_spec.id, v_src.exchange_rate,
          CASE WHEN v_cross THEN NULL ELSE v_src.target_fob END, v_src.id, v_email)
  RETURNING id INTO v_id;

  IF v_src.id IS NOT NULL THEN
    SELECT pm.name || ' / ' || sp.season || ' / ' || a.code || ' / ' || fn_rev_label(v_src.stage, v_src.revision_no) INTO v_ref
      FROM article a JOIN specsheet sp ON sp.id = a.specsheet_id JOIN product_model pm ON pm.id = sp.model_id
     WHERE a.id = v_src.article_id;
    SELECT array_agg(l ORDER BY l.sort_order) INTO v_lines FROM cbd_line l WHERE l.cbd_revision_id = v_src.id;
    -- baris biaya ikut; lintas model: hanya Direct Labour (LOP), lainnya default 0
    INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, remarks, is_default, sort_order, updated_by)
    SELECT v_id, c.item_type, c.name, c.amount, c.remarks, c.is_default, c.sort_order, v_email
      FROM cbd_cost_item c WHERE c.cbd_revision_id = v_src.id AND (NOT v_cross OR c.item_type = 'LABOUR');
  END IF;
  PERFORM fn_cbd_cost_defaults(v_id, v_email);
  PERFORM fn_cbd_populate(v_id, v_art.id, v_spec.id, v_lines, p_mode = 'NEXT', v_ref, v_email, v_cross);
  RETURN v_id;
END;
$$;

-- Sama dengan R13, hanya label revisi.
CREATE OR REPLACE FUNCTION fn_cbd_publish(p_token text, p_cbd_revision_id uuid, p_category text, p_reason text,
                                          p_bridge jsonb DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email    text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev      cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
  v_chk      v_cbd_checklist%ROWTYPE;
  v_reason   text := nullif(btrim(coalesce(p_reason, '')), '');
  v_category text := p_category;
  v_prev     cbd_revision%ROWTYPE;
  v_rows     jsonb := '[]';
  v_edits    jsonb := CASE WHEN jsonb_typeof(p_bridge) = 'array' THEN p_bridge ELSE '[]'::jsonb END;
  v_fob      numeric;
  v_pfob     numeric;
  v_diff     jsonb;
  v_id       uuid;
  v_higher   text;
  c_cats     text[] := ARRAY['EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER'];
BEGIN
  SELECT * INTO v_chk FROM v_cbd_checklist WHERE cbd_revision_id = v_rev.id;
  IF v_chk.spec_stale THEN
    RAISE EXCEPTION 'Specsheet % acuan CBD ini sudah diterbitkan revisi baru. Klik "Refresh dari Specsheet" dulu.', v_rev.stage;
  END IF;
  SELECT fn_rev_label(o.stage, o.revision_no) INTO v_higher FROM cbd_revision o
   WHERE o.article_id = v_rev.article_id AND o.status = 'PUBLISHED' AND o.stage_order > v_rev.stage_order
   ORDER BY o.stage_order DESC, o.revision_no DESC LIMIT 1;
  IF v_higher IS NOT NULL THEN
    RAISE EXCEPTION 'Sudah ada CBD % terbit. CBD % tidak bisa diterbitkan lagi. Hapus draft ini.', v_higher, v_rev.stage;
  END IF;
  IF NOT v_chk.rate_ok THEN
    RAISE EXCEPTION 'Isi exchange rate (lebih besar dari 0) di rekap dulu.';
  END IF;
  IF v_chk.pending_prices > 0 THEN
    RAISE EXCEPTION 'Ada % baris yang harganya menunggu persetujuan Manager Costing (%). Tunggu sampai diproses, lalu Refresh Harga.',
      v_chk.pending_prices, v_chk.pending_list;
  END IF;
  IF v_chk.stale_prices > 0 THEN
    RAISE EXCEPTION 'Harga master untuk % baris sudah berubah. Klik "Refresh Harga dari Master" dulu.', v_chk.stale_prices;
  END IF;
  IF v_chk.no_yield_count > 0 THEN
    RAISE EXCEPTION 'Ada % baris berharga yang belum diisi Yield.', v_chk.no_yield_count;
  END IF;

  -- A4: rincian perubahan vs revisi terbit sebelumnya
  SELECT * INTO v_prev FROM cbd_revision WHERE id = fn_cbd_prev_published(v_rev.id);
  IF v_prev.id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_edits) x
                WHERE nullif(btrim(x ->> 'category'), '') IS NOT NULL AND NOT (btrim(x ->> 'category') = ANY (c_cats))) THEN
      RAISE EXCEPTION 'Kategori rincian perubahan tidak valid.';
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'seq', b.seq, 'key', b.key, 'amount', b.amount, 'auto_category', b.category,
             'category', coalesce(e.cat, b.category),
             'description', left(coalesce(e.descr, b.description), 300)) ORDER BY b.seq), '[]'::jsonb)
      INTO v_rows
      FROM fn_cbd_bridge(v_rev.id) b
      LEFT JOIN LATERAL (SELECT nullif(btrim(x ->> 'category'), '') AS cat,
                                nullif(btrim(regexp_replace(coalesce(x ->> 'description', ''), '\s+', ' ', 'g')), '') AS descr
                           FROM jsonb_array_elements(v_edits) x
                          WHERE x ->> 'key' = b.key LIMIT 1) e ON true;
    v_fob  := (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = v_rev.id);
    v_pfob := (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = v_prev.id);
    IF abs(coalesce((SELECT sum((r ->> 'amount')::numeric) FROM jsonb_array_elements(v_rows) r), 0) - (v_fob - v_pfob)) > 0.000001 THEN
      RAISE EXCEPTION 'Rincian perubahan tidak sama dengan selisih Actual FOB. Hubungi pengembang (revisi %).', v_rev.id;
    END IF;
    v_diff := jsonb_build_object('prev_revision_id', v_prev.id, 'prev_label', fn_rev_label(v_prev.stage, v_prev.revision_no),
                                 'prev_fob', v_pfob, 'fob', v_fob, 'rows', v_rows);
  END IF;

  IF jsonb_array_length(v_rows) > 0 THEN
    SELECT r ->> 'category' INTO v_category FROM jsonb_array_elements(v_rows) r
     ORDER BY abs((r ->> 'amount')::numeric) DESC, (r ->> 'seq')::integer LIMIT 1;
    IF v_reason IS NULL THEN
      SELECT string_agg(fn_change_category_label(g.cat) || ' ' || CASE WHEN g.amt >= 0 THEN '+' ELSE '−' END
                        || fn_fmt_id(abs(g.amt), 2), '; ' ORDER BY fn_change_category_sort(g.cat))
        INTO v_reason
        FROM (SELECT r ->> 'category' AS cat, sum((r ->> 'amount')::numeric) AS amt
                FROM jsonb_array_elements(v_rows) r GROUP BY 1) g;
    END IF;
  ELSE
    IF coalesce(v_category, '') NOT IN ('EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER') THEN
      RAISE EXCEPTION 'Pilih kategori perubahan.';
    END IF;
    IF v_chk.requires_reason AND v_reason IS NULL THEN
      RAISE EXCEPTION 'Alasan perubahan wajib diisi untuk revisi ini.';
    END IF;
  END IF;

  UPDATE cbd_revision
     SET status = 'PUBLISHED', sync_status = 'IN_SYNC', published_at = now(), published_by = v_email,
         po_factor = (SELECT s.po_factor FROM stage_setting s WHERE s.stage = v_rev.stage),   -- dibekukan
         updated_by = v_email
   WHERE id = v_rev.id;

  INSERT INTO change_log (doc_type, revision_id, category, reason, diff, created_by)
  VALUES ('CBD', v_rev.id, v_category, coalesce(v_reason, 'Revisi awal.'), v_diff, v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Sama dengan R7, kecuali stage dari fn_stages() dan NEXT_STAGE boleh memilih stage lebih tinggi (p_stage).
CREATE OR REPLACE FUNCTION fn_revision_create(
  p_token text, p_specsheet_id uuid, p_mode text, p_stage text, p_source_specsheet_id uuid
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_specsheet', fn_sheet_factory(p_specsheet_id));
  v_stages text[] := fn_stages();
  v_sheet  specsheet%ROWTYPE;
  v_srcsp  specsheet%ROWTYPE;
  v_src    specsheet_revision%ROWTYPE;
  v_tgtm   product_model%ROWTYPE;
  v_srcm   product_model%ROWTYPE;
  v_cross  boolean := false;
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
        SELECT * INTO v_tgtm FROM product_model WHERE id = v_sheet.model_id;
        SELECT * INTO v_srcm FROM product_model WHERE id = v_srcsp.model_id;
        IF v_srcm.factory_id IS DISTINCT FROM v_tgtm.factory_id THEN
          RAISE EXCEPTION 'Specsheet hanya bisa di-copy dari model pabrik yang sama.';
        END IF;
        IF v_srcm.category_id IS DISTINCT FROM v_tgtm.category_id THEN
          RAISE EXCEPTION 'Copy dari model lain hanya untuk model dengan kategori yang sama.';
        END IF;
        v_cross := true;
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
      WITH src AS MATERIALIZED (
        SELECT l.*, gen_random_uuid() AS new_key FROM bom_line l WHERE l.revision_id = v_src.id AND l.is_active
      )
      INSERT INTO bom_line (revision_id, line_key, origin_line_key, component_id, local_component_no,
                            local_component_name, parent_line_key, sub_seq, sub_name, material_id, thickness,
                            supplier_id, process, sort_order, updated_by)
      SELECT v_id, s.new_key, s.line_key, s.component_id, s.local_component_no, s.local_component_name,
             p.new_key, s.sub_seq, s.sub_name, s.material_id, s.thickness, s.supplier_id, s.process, s.sort_order, v_email
        FROM src s LEFT JOIN src p ON p.line_key = s.parent_line_key
       WHERE s.parent_line_key IS NULL OR p.line_key IS NOT NULL;
      IF v_cross AND v_tgtm.parent_model_id IS NULL THEN
        UPDATE product_model SET parent_model_id = v_srcm.id, updated_by = v_email WHERE id = v_tgtm.id;
      END IF;
    END IF;

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
      -- R14: stage tujuan boleh melompat (mis. Pullover -> SMS); kosong = stage berikutnya
      v_stage := nullif(btrim(coalesce(p_stage, '')), '');
      IF v_stage IS NULL THEN
        IF v_src.stage = v_stages[array_length(v_stages, 1)] THEN
          RAISE EXCEPTION 'Already at the last stage (%). Use Next revision.', fn_stage_label(v_src.stage);
        END IF;
        v_stage := v_stages[fn_stage_order(v_src.stage) + 1];
      ELSIF NOT v_stage = ANY (v_stages) THEN
        RAISE EXCEPTION 'Unknown stage %.', v_stage;
      ELSIF fn_stage_order(v_stage) <= v_src.stage_order THEN
        RAISE EXCEPTION 'Stage must be higher than the latest published stage (%).', fn_stage_label(v_src.stage);
      END IF;
      v_no := 0;
    END IF;

    INSERT INTO specsheet_revision (specsheet_id, stage, revision_no, source_revision_id, updated_by)
    VALUES (p_specsheet_id, v_stage, v_no, v_src.id, v_email)
    RETURNING id INTO v_id;

    INSERT INTO bom_line (revision_id, line_key, origin_line_key, replaces_line_key, component_id,
                          local_component_no, local_component_name, parent_line_key, sub_seq, sub_name,
                          material_id, thickness, supplier_id, process, sort_order, updated_by)
    SELECT v_id, l.line_key, l.origin_line_key, l.replaces_line_key, l.component_id, l.local_component_no,
           l.local_component_name, l.parent_line_key, l.sub_seq, l.sub_name, l.material_id, l.thickness, l.supplier_id,
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

-- ---------------------------------------------------------------- ringkasan
SELECT 'R14 terpasang' AS cek,
       concat_ws(' · ',
         'stages: ' || array_to_string(fn_stages(), ','),
         'labels: ' || (SELECT string_agg(fn_stage_label(s), ',' ORDER BY o) FROM unnest(fn_stages()) WITH ORDINALITY u(s, o)),
         'stage_order generated: ' || (SELECT count(*) FROM pg_attribute
                                        WHERE attname = 'stage_order' AND attgenerated = 's'
                                          AND attrelid IN ('specsheet_revision'::regclass, 'cbd_revision'::regclass)),
         'stage_order wrong: ' || ((SELECT count(*) FROM specsheet_revision WHERE stage_order <> fn_stage_order(stage))
                                 + (SELECT count(*) FROM cbd_revision WHERE stage_order <> fn_stage_order(stage)))) AS hasil;

COMMIT;
