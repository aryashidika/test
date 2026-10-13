-- ============================================================================
-- R13 — CBD per stage (13 Okt 2026, keputusan user): CBD tidak lagi "ikut" specsheet ke stage berikutnya.
-- Jalankan SETELAH R12_golive.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi.
--
-- Pemicu: draft CBD SMS r0 di-"Refresh dari Specsheet" setelah specsheet GTM r0 terbit -> draft pindah jadi GTM r0,
-- CBD SMS (dan PO SMS) tidak pernah ada. Aturan baru:
--   1. Acuan CBD = specsheet terbit terakhir DI STAGE CBD ITU. Draft SMS hanya perlu refresh bila ada specsheet SMS
--      yang lebih baru (mis. SMS r1); terbitnya GTM tidak memblokir CBD SMS. Refresh tidak memindahkan stage.
--   2. Buat CBD bisa memilih stage (stage yang specsheet-nya sudah terbit & article aktif di sana); default = stage
--      specsheet terbaru.
--   3. Tidak boleh mundur: setelah CBD GTM terbit, CBD SMS tidak bisa dibuat / diterbitkan lagi.
--   4. Satu draft per article (tetap).
--   5. CBD terbit terakhir yang stage-nya tertinggal dari specsheet -> "perlu CBD <stage>" (chip & Tugas Saya).
--      Penandaan sinkron (fn_cbd_sync_spec) hanya membandingkan specsheet di stage yang sama; CBD tidak lagi
--      dipindah acuannya ke specsheet stage lain.
-- Data: CBD terbit yang acuannya sempat dipindah ke specsheet stage lain (aturan lama) dikembalikan ke specsheet
-- terbit terakhir di stage-nya sendiri.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_cbd_publish(text,uuid,text,text,jsonb)') IS NULL
     OR to_regclass('ix_cbd_line_material_price') IS NULL THEN
    RAISE EXCEPTION 'R12 belum terpasang. Jalankan sql/R12_golive.sql dulu.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- helper stage
-- Revisi specsheet terbit terakhir di satu stage.
CREATE OR REPLACE FUNCTION fn_spec_latest_pub_stage(p_specsheet_id uuid, p_stage text) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT id FROM specsheet_revision
   WHERE specsheet_id = p_specsheet_id AND stage = p_stage AND status = 'PUBLISHED'
   ORDER BY revision_no DESC LIMIT 1
$$;

-- Status article di specsheet terbit terakhir stage itu: ACTIVE / DROPPED / NOT_PUBLISHED.
CREATE OR REPLACE FUNCTION fn_cbd_stage_spec_status(p_article_id uuid, p_stage text) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT ra.status FROM article a
                     JOIN revision_article ra ON ra.article_id = a.id
                                             AND ra.revision_id = fn_spec_latest_pub_stage(a.specsheet_id, p_stage)
                    WHERE a.id = p_article_id), 'NOT_PUBLISHED')
$$;

-- ---------------------------------------------------------------- draft: article juga harus aktif di stage-nya
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
  -- R13: acuan = specsheet terbit terakhir di stage draft ini
  IF fn_cbd_stage_spec_status(v_rev.article_id, v_rev.stage) <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article ini tidak aktif di specsheet % terbit terakhir — draft CBD % hanya bisa dihapus.',
      v_rev.stage, v_rev.stage;
  END IF;
  RETURN v_rev;
END;
$$;

-- ---------------------------------------------------------------- pilihan stage untuk form Buat CBD
-- Satu baris per stage yang specsheet-nya sudah terbit. available = article aktif di specsheet terbit terakhir DAN
-- di specsheet stage itu, dan stage tidak lebih rendah dari CBD terbit terakhir. is_default = stage tersedia tertinggi.
-- Aturan sama dengan fn_cbd_create (yang tetap jadi penjaga terakhir).
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
    SELECT s.stage, s.ord::integer AS ord, sr.id AS sid, sr.stage || ' r' || sr.revision_no AS slabel,
           coalesce(ra.status, 'NOT_PUBLISHED') AS art_status,
           (SELECT coalesce(max(c.revision_no) + 1, 0)::integer FROM cbd_revision c
             WHERE c.article_id = p_article_id AND c.stage = s.stage) AS nno
      FROM unnest(ARRAY['PULL','SMS','GTM','PROD']) WITH ORDINALITY s(stage, ord)
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
                WHEN m.o IS NOT NULL AND st.ord < m.o THEN 'Sudah ada CBD ' || m.s || ' terbit'
           END AS why
      FROM st CROSS JOIN maxpub m
      CROSS JOIN (SELECT fn_cbd_article_spec_status(p_article_id) AS s) ov
  )
  SELECT ev.stage, ev.ord, ev.sid, ev.slabel, ev.nno, ev.stage || ' r' || ev.nno, ev.ok, ev.why,
         ev.ok AND ev.ord = (SELECT max(e2.ord) FROM ev e2 WHERE e2.ok)
    FROM ev
   ORDER BY ev.ord;
END;
$$;

-- ---------------------------------------------------------------- CBD: buat (R13: stage bisa dipilih)
-- p_stage kosong = stage specsheet terbit terbaru (perilaku lama).
DROP FUNCTION IF EXISTS fn_cbd_create(text, uuid, text, uuid);
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
    RAISE EXCEPTION 'Article % sudah di-drop di specsheet terbit terakhir — CBD-nya tidak bisa dibuat lagi.', v_art.code;
  ELSIF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article % belum ada di revisi specsheet yang terbit. Terbitkan specsheet-nya dulu.', v_art.code;
  END IF;
  IF EXISTS (SELECT 1 FROM cbd_revision WHERE article_id = v_art.id AND status = 'DRAFT') THEN
    RAISE EXCEPTION 'Sudah ada CBD DRAFT untuk article %. Terbitkan atau hapus draft itu dulu.', v_art.code;
  END IF;

  -- R13: stage dipilih (default stage specsheet terbit terbaru); acuan = specsheet terbit terakhir di stage itu
  v_stage := coalesce(nullif(btrim(coalesce(p_stage, '')), ''),
                      (SELECT stage FROM specsheet_revision WHERE id = fn_spec_latest_pub(v_art.specsheet_id)));
  IF NOT (v_stage = ANY (ARRAY['PULL','SMS','GTM','PROD'])) THEN
    RAISE EXCEPTION 'Stage % tidak dikenal.', v_stage;
  END IF;
  SELECT * INTO v_spec FROM specsheet_revision WHERE id = fn_spec_latest_pub_stage(v_art.specsheet_id, v_stage);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Specsheet % untuk article % belum ada yang terbit.', v_stage, v_art.code;
  END IF;
  IF fn_cbd_stage_spec_status(v_art.id, v_stage) <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Article % tidak aktif di specsheet % r% — CBD % tidak bisa dibuat.',
      v_art.code, v_spec.stage, v_spec.revision_no, v_stage;
  END IF;
  SELECT * INTO v_maxpub FROM cbd_revision
   WHERE article_id = v_art.id AND status = 'PUBLISHED'
   ORDER BY stage_order DESC, revision_no DESC LIMIT 1;
  IF FOUND AND v_maxpub.stage_order > v_spec.stage_order THEN
    RAISE EXCEPTION 'Article % sudah punya CBD % terbit — CBD stage sebelumnya (%) tidak bisa dibuat lagi.',
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
    SELECT pm.name || ' / ' || sp.season || ' / ' || a.code || ' / ' || v_src.stage || ' r' || v_src.revision_no INTO v_ref
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

-- ---------------------------------------------------------------- Refresh dari Specsheet (R13: stage tetap)
CREATE OR REPLACE FUNCTION fn_cbd_refresh_from_spec(p_token text, p_cbd_revision_id uuid) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev    cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);   -- dikunci, article ACTIVE di stage-nya
  v_spec   specsheet_revision%ROWTYPE;
  v_lines  cbd_line[];
  v_n      integer;
BEGIN
  SELECT sr.* INTO v_spec FROM specsheet_revision sr
   WHERE sr.id = fn_spec_latest_pub_stage((SELECT specsheet_id FROM article WHERE id = v_rev.article_id), v_rev.stage);
  IF v_spec.id = v_rev.specsheet_revision_id THEN
    RAISE EXCEPTION 'CBD ini sudah memakai specsheet % terbit terakhir (% r%).', v_rev.stage, v_spec.stage, v_spec.revision_no;
  END IF;

  SELECT array_agg(l ORDER BY l.sort_order) INTO v_lines FROM cbd_line l WHERE l.cbd_revision_id = v_rev.id;
  DELETE FROM cbd_line WHERE cbd_revision_id = v_rev.id;
  UPDATE cbd_revision SET specsheet_revision_id = v_spec.id, updated_by = v_email WHERE id = v_rev.id;
  v_n := fn_cbd_populate(v_rev.id, v_rev.article_id, v_spec.id, v_lines, true, NULL, v_email);
  PERFORM fn_audit(v_email, 'cbd_revision', v_rev.id::text, 'REFRESH_FROM_SPEC');
  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------- sinkron: hanya specsheet stage yang sama
CREATE OR REPLACE FUNCTION fn_cbd_sync_spec(p_spec_rev_id uuid, p_email text) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  c       record;
  v_same  boolean;
  v_n     integer := 0;
  v_stage text := (SELECT stage FROM specsheet_revision WHERE id = p_spec_rev_id);
BEGIN
  FOR c IN
    SELECT DISTINCT ON (cr.article_id) cr.id, cr.article_id, cr.specsheet_revision_id, cr.sync_status, cr.stage
      FROM cbd_revision cr
      JOIN revision_article ra ON ra.article_id = cr.article_id AND ra.revision_id = p_spec_rev_id
                              AND ra.status = 'ACTIVE'
     WHERE cr.status = 'PUBLISHED'
     ORDER BY cr.article_id, cr.stage_order DESC, cr.revision_no DESC
  LOOP
    CONTINUE WHEN c.specsheet_revision_id = p_spec_rev_id;
    -- R13: specsheet stage lain tidak mengubah CBD ini (tampil sebagai "perlu CBD <stage>" di view)
    CONTINUE WHEN c.stage <> v_stage;
    SELECT NOT EXISTS (
             (SELECT line_key, supplier_id, variant_id FROM fn_cbd_expected_lines(c.article_id, c.specsheet_revision_id)
              EXCEPT
              SELECT line_key, supplier_id, variant_id FROM fn_cbd_expected_lines(c.article_id, p_spec_rev_id))
             UNION ALL
             (SELECT line_key, supplier_id, variant_id FROM fn_cbd_expected_lines(c.article_id, p_spec_rev_id)
              EXCEPT
              SELECT line_key, supplier_id, variant_id FROM fn_cbd_expected_lines(c.article_id, c.specsheet_revision_id)))
      INTO v_same;
    IF v_same THEN
      UPDATE cbd_revision SET specsheet_revision_id = p_spec_rev_id, sync_status = 'IN_SYNC', updated_by = p_email
       WHERE id = c.id;
    ELSIF c.sync_status <> 'NEEDS_REVISION' THEN
      UPDATE cbd_revision SET sync_status = 'NEEDS_REVISION', updated_by = p_email WHERE id = c.id;
      v_n := v_n + 1;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------- checklist terbit (kolom sama dengan R11)
-- spec_status: status article di specsheet terbaru (DROPPED tetap memblokir), lalu di specsheet stage CBD ini.
-- spec_stale: dibanding specsheet terbit terakhir DI STAGE CBD ini.
CREATE OR REPLACE VIEW v_cbd_checklist AS
 SELECT cbd_revision_id,
    article_id,
    stage,
    revision_no,
    status,
    requires_reason,
    spec_status,
    spec_stale,
    rate_ok,
    stale_prices,
    no_yield_count,
    unpriced_count,
    line_count,
    missing_count,
    pending_prices,
    pending_list,
    ((spec_status <> 'ACTIVE'::text) OR spec_stale OR (NOT rate_ok) OR (stale_prices > 0) OR (no_yield_count > 0)
     OR (pending_prices > 0)) AS blocked,
    no_charge_count,
    unpriced_list,
    blank_count
   FROM ( SELECT r.id AS cbd_revision_id,
            r.article_id,
            r.stage,
            r.revision_no,
            r.status,
            (EXISTS ( SELECT 1
                   FROM cbd_revision o
                  WHERE ((o.article_id = r.article_id) AND (o.status = 'PUBLISHED'::text) AND (o.id <> r.id)))) AS requires_reason,
            CASE WHEN fn_cbd_article_spec_status(r.article_id) <> 'ACTIVE' THEN fn_cbd_article_spec_status(r.article_id)
                 ELSE fn_cbd_stage_spec_status(r.article_id, r.stage) END AS spec_status,
            (r.specsheet_revision_id IS DISTINCT FROM fn_spec_latest_pub_stage(a.specsheet_id, r.stage)) AS spec_stale,
            (r.exchange_rate IS NOT NULL) AS rate_ok,
            ( SELECT (count(*))::integer AS count
                   FROM v_cbd_price_check pc
                  WHERE ((pc.cbd_revision_id = r.id) AND pc.master_stale)) AS stale_prices,
            rc.no_yield_count,
            (rc.unpriced_count - rc.blank_count) AS unpriced_count,
            rc.line_count,
            rc.missing_count,
            ( SELECT (count(*))::integer AS count
                   FROM v_cbd_price_check pc
                  WHERE ((pc.cbd_revision_id = r.id) AND pc.pending)) AS pending_prices,
            ( SELECT "left"(string_agg(DISTINCT ((v.material_code || ' · '::text) || v.supplier_name), ', '::text), 300) AS "left"
                   FROM (v_cbd_price_check pc
                     JOIN v_cbd_line v ON (((v.id = pc.line_id) AND (v.cbd_revision_id = r.id))))
                  WHERE ((pc.cbd_revision_id = r.id) AND pc.pending)) AS pending_list,
            rc.no_charge_count,
            ( SELECT "left"(string_agg(btrim(concat_ws(' ', v.display_no, v.display_name)) || ' (' || v.material_name || ')',
                                       ', '::text ORDER BY v.group_sort, v.sort_order), 300)
                   FROM v_cbd_line v
                  WHERE v.cbd_revision_id = r.id AND v.status = 'ACTIVE' AND v.price_original IS NULL AND v.yield_value IS NOT NULL
                    AND NOT v.no_charge) AS unpriced_list,
            rc.blank_count
           FROM ((cbd_revision r
             JOIN article a ON ((a.id = r.article_id)))
             JOIN v_cbd_recap rc ON ((rc.cbd_revision_id = r.id)))) x;

-- ---------------------------------------------------------------- status CBD per article (chip)
-- draft_stale per stage draft. Kolom baru di akhir: draft_spec_label (specsheet terbit terakhir di stage draft),
-- pub_behind (CBD terbit terakhir di stage lebih rendah dari specsheet terbaru).
CREATE OR REPLACE VIEW v_cbd_article AS
SELECT a.id, a.specsheet_id, sh.model_id, sh.season, a.code, a.colorway,
       sp.id AS spec_pub_id, sp.stage || ' r' || sp.revision_no AS spec_pub_label, sp.stage AS spec_pub_stage,
       fn_cbd_article_spec_status(a.id) AS spec_status,
       d.id AS draft_id, d.stage || ' r' || d.revision_no AS draft_label,
       (d.id IS NOT NULL AND d.specsheet_revision_id IS DISTINCT FROM ds.id) AS draft_stale,
       p.id AS pub_id, p.stage || ' r' || p.revision_no AS pub_label, p.sync_status AS pub_sync,
       (SELECT count(*)::int FROM cbd_revision x WHERE x.article_id = a.id) AS revision_count,
       ds.stage || ' r' || ds.revision_no AS draft_spec_label,
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

-- ---------------------------------------------------------------- Tugas Saya Vendor CBD (kolom sama dengan R11)
-- TO_REFRESH (SPEC) dibanding specsheet stage draft. TO_REVISE juga bila CBD terbit terakhir tertinggal stage
-- (refresh_reason = 'STAGE', mis. CBD SMS terbit, specsheet sudah GTM).
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
           coalesce((d.stage || ' r') || d.revision_no, (p.stage || ' r') || p.revision_no) AS rev_label,
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

-- ---------------------------------------------------------------- terbit CBD (R13: + cek stage tidak mundur)
-- Sama dengan R11, kecuali pesan spec_stale (per stage) dan blokir bila sudah ada CBD terbit di stage lebih tinggi.
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
  SELECT o.stage || ' r' || o.revision_no INTO v_higher FROM cbd_revision o
   WHERE o.article_id = v_rev.article_id AND o.status = 'PUBLISHED' AND o.stage_order > v_rev.stage_order
   ORDER BY o.stage_order DESC, o.revision_no DESC LIMIT 1;
  IF v_higher IS NOT NULL THEN
    RAISE EXCEPTION 'Sudah ada CBD % terbit — CBD % tidak bisa diterbitkan lagi. Hapus draft ini.', v_higher, v_rev.stage;
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
      RAISE EXCEPTION 'Rincian perubahan tidak sama dengan selisih Actual FOB — hubungi pengembang (revisi %).', v_rev.id;
    END IF;
    v_diff := jsonb_build_object('prev_revision_id', v_prev.id, 'prev_label', v_prev.stage || ' r' || v_prev.revision_no,
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

-- ---------------------------------------------------------------- data: acuan CBD terbit kembali ke stage-nya
-- Aturan lama memindah acuan CBD terbit ke specsheet stage berikutnya bila barisnya sama (tetap IN_SYNC).
-- Dikembalikan ke specsheet terbit terakhir di stage CBD itu (trigger kunci mengizinkan specsheet_revision_id).
UPDATE cbd_revision r
   SET specsheet_revision_id = fn_spec_latest_pub_stage(a.specsheet_id, r.stage), updated_by = 'system:R13'
  FROM article a, specsheet_revision sr
 WHERE a.id = r.article_id AND sr.id = r.specsheet_revision_id
   AND r.status = 'PUBLISHED' AND sr.stage <> r.stage
   AND fn_spec_latest_pub_stage(a.specsheet_id, r.stage) IS NOT NULL;

-- ---------------------------------------------------------------- ringkasan
SELECT 'R13 terpasang' AS cek,
       concat_ws(' · ',
         'fn_cbd_create: ' || (SELECT string_agg(pg_get_function_identity_arguments(oid), ' | ') FROM pg_proc WHERE proname = 'fn_cbd_create'),
         'acuan beda stage: ' || (SELECT count(*) FROM cbd_revision r JOIN specsheet_revision sr ON sr.id = r.specsheet_revision_id
                                    WHERE sr.stage <> r.stage)) AS hasil;

COMMIT;
