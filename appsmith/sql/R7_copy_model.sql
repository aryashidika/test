-- ============================================================================
-- R7 — Copy lintas model (specsheet & CBD, pabrik + kategori sama) (PLAN.md §6 R7, diskusi 7 Okt 2026)
-- Bagian dari sql/R_revisi_semua.sql (urutan R3 -> R7). Aman diulang. Satu transaksi.
--
-- Specsheet (mode COPY di wizard Buat Revisi): sumber boleh season model LAIN asal pabrik sama + kategori sama.
--   Aturan COPY tetap: season tujuan belum punya revisi -> r0, sumber = revisi terbit terakhir, origin_line_key =
--   line_key sumber, article season tujuan, warna kosong. Copy lintas model pertama mengisi
--   product_model.parent_model_id (model induk) otomatis. Tanpa sinkron otomatis.
-- CBD (mode COPY): selain article model yang sama, boleh article MODEL ASAL specsheet ini (model sumber copy
--   lintas model). Lintas model: Yield / Loss % ikut hanya bila cocok lewat origin_line_key DAN induk + thickness
--   sama; quotation ikut bila varian sama; pencocokan identitas dimatikan. Rekap: hanya exchange rate & LOP
--   (Direct Labour) yang ikut; Amortisasi / Adjustment / Lainnya kembali 0; Target FOB kosong.
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('public.v_worklist_price_rejected') IS NULL THEN
    RAISE EXCEPTION 'Bagian R6 belum dijalankan. Jalankan file revisi dari awal.';
  END IF;
END;
$$;

ALTER TABLE product_model ADD COLUMN IF NOT EXISTS parent_model_id uuid REFERENCES product_model(id);

-- Model sumber copy lintas model untuk season ini (NULL = tidak berasal dari model lain)
CREATE OR REPLACE FUNCTION fn_sheet_origin_model(p_specsheet_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT ssp.model_id
    FROM specsheet_revision r
    JOIN specsheet sh ON sh.id = r.specsheet_id
    JOIN specsheet_revision src ON src.id = r.source_revision_id
    JOIN specsheet ssp ON ssp.id = src.specsheet_id
   WHERE r.specsheet_id = p_specsheet_id AND ssp.model_id <> sh.model_id
   ORDER BY r.stage_order, r.revision_no
   LIMIT 1
$$;

-- ---------------------------------------------------------------- Specsheet: COPY dari model lain
CREATE OR REPLACE FUNCTION fn_revision_create(
  p_token text, p_specsheet_id uuid, p_mode text, p_stage text, p_source_specsheet_id uuid
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_specsheet', fn_sheet_factory(p_specsheet_id));
  v_stages text[] := ARRAY['PULL', 'SMS', 'GTM', 'PROD'];
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
      IF v_src.stage = 'PROD' THEN
        RAISE EXCEPTION 'Sudah berada di stage terakhir (PROD). Pakai Revisi berikutnya.';
      END IF;
      v_stage := v_stages[array_position(v_stages, v_src.stage) + 1];
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

-- ---------------------------------------------------------------- CBD: isi baris (+ mode lintas model)
DROP FUNCTION IF EXISTS fn_cbd_populate(uuid, uuid, uuid, cbd_line[], boolean, text, text);
CREATE OR REPLACE FUNCTION fn_cbd_populate(p_revision_id uuid, p_article_id uuid, p_spec_rev_id uuid,
                                           p_src cbd_line[], p_mark_missing boolean, p_ref text, p_email text,
                                           p_cross boolean DEFAULT false)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  e         record;
  s         cbd_line%ROWTYPE;
  v_has_src boolean := coalesce(cardinality(p_src), 0) > 0;
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
    v_yield := NULL; v_loss := NULL; v_origin := 'INPUT'; v_ref := NULL; v_carry := false;
    IF v_has_src THEN
      IF NOT p_cross THEN
        SELECT * INTO s FROM unnest(p_src) x WHERE x.line_key = e.line_key
           AND NOT (x.line_key = ANY (v_matched)) LIMIT 1;
        v_found := FOUND;
      END IF;
      IF NOT v_found AND e.origin_line_key IS NOT NULL THEN
        SELECT * INTO s FROM unnest(p_src) x WHERE x.line_key = e.origin_line_key
           AND NOT (x.line_key = ANY (v_matched)) LIMIT 1;
        v_found := FOUND;
        -- lintas model: hanya bila induk + thickness sama (baris hasil Ganti material -> kosong)
        IF v_found AND p_cross AND (s.material_id <> e.material_id
                                    OR fn_normalize(coalesce(s.thickness, '')) <> fn_normalize(coalesce(e.thickness, ''))) THEN
          v_found := false;
        END IF;
      END IF;
      IF NOT v_found AND NOT p_cross THEN
        SELECT * INTO s FROM unnest(p_src) x
         WHERE NOT (x.line_key = ANY (v_matched))
           AND fn_cbd_identity(x.component_id, x.local_component_no, x.sub_seq, x.sub_name, x.material_id, x.thickness)
             = fn_cbd_identity(e.component_id, e.local_component_no, e.sub_seq, e.sub_name, e.material_id, e.thickness)
         ORDER BY x.sort_order LIMIT 1;
        v_found := FOUND;
      END IF;
      IF v_found THEN
        v_matched := v_matched || s.line_key;
        v_yield := s.yield_value; v_loss := s.loss_pct;
        IF p_ref IS NULL THEN
          v_origin := s.value_origin; v_ref := s.value_source_ref;
        ELSE
          v_origin := 'COPIED'; v_ref := p_ref;
        END IF;
        v_carry := s.price_source = 'QUOTATION' AND s.variant_id IS NOT DISTINCT FROM e.variant_id
                   AND EXISTS (SELECT 1 FROM material WHERE id = e.material_id AND price_method = 'QUOTATION');
      ELSIF e.replaces_line_key IS NOT NULL AND NOT p_cross THEN
        SELECT * INTO s FROM unnest(p_src) x WHERE x.line_key = e.replaces_line_key
           AND NOT (x.line_key = ANY (v_matched)) LIMIT 1;
        IF FOUND THEN
          v_matched := v_matched || s.line_key;
          v_yield := s.yield_value; v_loss := s.loss_pct; v_origin := 'CARRIED_FROM_REPLACED';
          v_ref := coalesce(p_ref, s.value_source_ref);
        END IF;
      END IF;
    END IF;

    IF v_carry THEN
      INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                            material_id, thickness, color, variant_id, supplier_id, uom, group_code, yield_value, loss_pct,
                            price_original, currency, price_source, material_price_id, price_override_reason,
                            price_reference, status, value_origin, value_source_ref, sort_order, updated_by)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.thickness, e.color, e.variant_id, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              s.price_original, s.currency, s.price_source, NULL, NULL,
              s.price_reference, 'ACTIVE', v_origin, v_ref, v_sort, p_email);
    ELSE
      v_pid := NULL; v_price := NULL; v_cur := NULL;
      IF e.supplier_id IS NOT NULL AND e.variant_id IS NOT NULL THEN
        SELECT price_id, price, currency INTO v_pid, v_price, v_cur
          FROM fn_price_lookup(e.variant_id, e.supplier_id);
      END IF;
      INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                            material_id, thickness, color, variant_id, supplier_id, uom, group_code, yield_value, loss_pct,
                            price_original, currency, price_source, material_price_id,
                            status, value_origin, value_source_ref, sort_order, updated_by)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.thickness, e.color, e.variant_id, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              v_price, v_cur, CASE WHEN v_pid IS NOT NULL THEN 'MASTER' END, v_pid,
              'ACTIVE', v_origin, v_ref, v_sort, p_email);
    END IF;
    v_sort := v_sort + 1;
  END LOOP;

  IF p_mark_missing AND v_has_src THEN
    INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                          material_id, thickness, color, variant_id, supplier_id, uom, group_code, yield_value, loss_pct,
                          price_original, currency, price_source, material_price_id, price_override_reason,
                          price_reference, status, value_origin, value_source_ref, sort_order, updated_by)
    SELECT p_revision_id, x.line_key, x.component_id, x.local_component_no, x.sub_seq, x.sub_name,
           x.material_id, x.thickness, x.color, x.variant_id, x.supplier_id, x.uom, x.group_code, x.yield_value, x.loss_pct,
           x.price_original, x.currency, x.price_source, x.material_price_id, x.price_override_reason,
           x.price_reference, 'MISSING_IN_SPEC', x.value_origin, x.value_source_ref,
           v_sort + (row_number() OVER (ORDER BY x.sort_order))::integer, p_email
      FROM unnest(p_src) x
     WHERE NOT (x.line_key = ANY (v_matched));
  END IF;
  RETURN v_sort;
END;
$$;

-- ---------------------------------------------------------------- CBD: buat (COPY lintas model)
CREATE OR REPLACE FUNCTION fn_cbd_create(p_token text, p_article_id uuid, p_mode text, p_source_article_id uuid)
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

SELECT 'product_model.parent_model_id' AS cek, count(*)::text AS hasil FROM information_schema.columns
 WHERE table_name = 'product_model' AND column_name = 'parent_model_id'
UNION ALL SELECT 'fn_cbd_populate (harus 1 versi, 8 argumen)',
       string_agg(pg_get_function_identity_arguments(oid), ' | ') FROM pg_proc WHERE proname = 'fn_cbd_populate';
