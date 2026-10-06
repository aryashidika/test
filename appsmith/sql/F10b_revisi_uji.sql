-- ============================================================================
-- F10b — Revisi dari uji end-to-end (laporan user 5 Okt 2026, uji sampai G8)
-- Jalankan SETELAH F10, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
--
--  1. BUG terbit GTM: "Revisi CBD SMS r0 sudah diterbitkan dan tidak bisa diubah" — trigger kunci CBD terbit
--     membandingkan seluruh baris, termasuk kolom generated stage_order yang di BEFORE trigger belum terisi (NULL)
--     -> penandaan sinkron (fn_cbd_sync_spec) selalu ditolak. stage_order dikecualikan.
--  2. Exchange rate boleh dikosongkan (sebelumnya ditolak di DB tetapi layar sudah kosong -> tetap bisa terbit
--     dengan rate lama). Kosong -> checklist memblokir terbit.
--  3. Revisi awal per ARTICLE (CBD) / per SEASON (specsheet): alasan tidak wajib selama belum ada revisi terbit
--     lain di article / season itu — juga untuk CBD hasil copy dari article lain dan specsheet hasil copy season.
--  4. Override harga CBD untuk material katalog DIHAPUS (keputusan user): fn_cbd_override_price ditolak, override
--     tidak ikut ter-copy ke revisi berikutnya. "Hapus override" tetap ada untuk draft lama.
--  5. Loss % CBD default kosong (dihitung 0 %, tidak memblokir terbit — keputusan user).
--  6. Specsheet tidak bisa terbit bila ada baris tanpa supplier, atau BOM memakai usulan yang belum di-approve
--     (material / komponen / supplier / supplier material berstatus PROPOSED) — keputusan user.
--  7. (Dibatalkan di F10c — yang dimaksud user adalah Thickness, sudah ada di master material.)
--     Tersisa: huruf kapital nama & kategori material; v_bom_grid + supplier_status.
--  8. Huruf kapital otomatis (keputusan user, "lebih luas"): nama & kategori material, nama komponen, nama
--     supplier, kode & nama model, kode article & colorway, nama komponen lokal & subkomponen di BOM.
--     Data lama ikut diubah (kecuali baris BOM revisi terbit dan kode article yang sudah dipakai).
--  9. Supplier usulan: Vendor (propose_master) boleh menambah supplier -> PROPOSED; antrian Master Admin.
-- 10. Lampiran gambar di change log (paste / pilih saat Terbitkan specsheet & CBD): tabel change_log_attachment
--     + fn_change_log_attach (png / jpg, maks. 5 MB per gambar, maks. 5 gambar per terbit).
-- ============================================================================

SELECT set_config('app.user', 'migrasi F10b', true);

-- ---------------------------------------------------------------- 1. Kunci CBD terbit
CREATE OR REPLACE FUNCTION fn_cbd_revision_lock() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'PUBLISHED' THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'Revisi CBD % r% sudah diterbitkan dan tidak bisa dihapus.', OLD.stage, OLD.revision_no;
    END IF;
    -- stage_order = kolom generated: di BEFORE trigger nilai NEW-nya belum dihitung -> tidak ikut dibandingkan
    IF (to_jsonb(NEW) - 'sync_status' - 'specsheet_revision_id' - 'updated_at' - 'updated_by' - 'stage_order')
       IS DISTINCT FROM (to_jsonb(OLD) - 'sync_status' - 'specsheet_revision_id' - 'updated_at' - 'updated_by' - 'stage_order') THEN
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

-- ---------------------------------------------------------------- 7. Material (tanpa Width — lihat F10c)
-- Normalisasi + identitas (nama, kategori huruf kapital — poin 8)
CREATE OR REPLACE FUNCTION fn_material_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other record;
BEGIN
  NEW.material_code := upper(btrim(coalesce(NEW.material_code, '')));
  NEW.name          := upper(btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g')));
  NEW.category      := upper(btrim(regexp_replace(coalesce(NEW.category, ''), '\s+', ' ', 'g')));
  NEW.thickness     := nullif(btrim(coalesce(NEW.thickness, '')), '');
  NEW.uom           := upper(btrim(coalesce(NEW.uom, '')));
  IF NEW.material_code = '' THEN RAISE EXCEPTION 'Material Code wajib diisi.'; END IF;
  IF NEW.name = ''          THEN RAISE EXCEPTION 'Nama material wajib diisi.'; END IF;
  IF NEW.category = ''      THEN RAISE EXCEPTION 'Kategori material wajib diisi.'; END IF;
  IF NEW.uom = ''           THEN RAISE EXCEPTION 'UoM wajib diisi.'; END IF;

  SELECT material_code, name INTO v_other FROM material
   WHERE material_code = NEW.material_code AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material Code % sudah dipakai material "%".', NEW.material_code, v_other.name;
  END IF;

  SELECT material_code, name INTO v_other FROM material
   WHERE name_key = fn_normalize(NEW.name) AND thickness_key = fn_normalize(NEW.thickness)
     AND uom = NEW.uom AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material dengan nama, thickness, dan UoM yang sama sudah ada: % — %.',
      v_other.material_code, v_other.name;
  END IF;
  RETURN NEW;
END;
$$;

-- Grid BOM: + supplier_status (kolom baru di akhir)
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
                   FROM bom_cell bc WHERE bc.bom_line_id = l.id AND bc.color IS NOT NULL), '{}'::jsonb) AS cells,
       s.status AS supplier_status
  FROM bom_line l
  JOIN material m ON m.id = l.material_id
  LEFT JOIN component c ON c.id = l.component_id
  LEFT JOIN bom_line p ON p.revision_id = l.revision_id AND p.line_key = l.parent_line_key AND p.is_active
  LEFT JOIN component pc ON pc.id = p.component_id
  LEFT JOIN supplier s ON s.id = l.supplier_id
  LEFT JOIN material_supplier ms ON ms.material_id = l.material_id AND ms.supplier_id = l.supplier_id
 WHERE l.is_active;

-- ---------------------------------------------------------------- 5. Loss % kosong
ALTER TABLE cbd_line ALTER COLUMN loss_pct DROP NOT NULL;
ALTER TABLE cbd_line ALTER COLUMN loss_pct DROP DEFAULT;

-- Baris CBD: loss kosong dihitung 0 %
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
       cl.usage_value * x.price_idr * (1 + coalesce(cl.loss_pct, 0) / 100) AS cost_per_pair,
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
    IF p_value < 0 OR p_value >= 100 THEN
      RAISE EXCEPTION 'Loss %% harus 0 sampai kurang dari 100 (kosong = 0).';
    END IF;
    UPDATE cbd_line SET loss_pct = p_value, value_origin = 'INPUT', updated_by = v_email WHERE id = v_line.id;
  ELSE
    RAISE EXCEPTION 'Kolom tidak valid.';
  END IF;
  RETURN v_line.id;
END;
$$;

-- fn_cbd_populate (F8): Loss default kosong; hanya harga QUOTATION yang ikut ter-copy (override dihapus — poin 4)
CREATE OR REPLACE FUNCTION fn_cbd_populate(p_revision_id uuid, p_article_id uuid, p_spec_rev_id uuid,
                                           p_src cbd_line[], p_mark_missing boolean, p_ref text, p_email text)
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
      SELECT * INTO s FROM unnest(p_src) x WHERE x.line_key = e.line_key
         AND NOT (x.line_key = ANY (v_matched)) LIMIT 1;
      v_found := FOUND;
      IF NOT v_found AND e.origin_line_key IS NOT NULL THEN
        SELECT * INTO s FROM unnest(p_src) x WHERE x.line_key = e.origin_line_key
           AND NOT (x.line_key = ANY (v_matched)) LIMIT 1;
        v_found := FOUND;
      END IF;
      IF NOT v_found THEN
        SELECT * INTO s FROM unnest(p_src) x
         WHERE NOT (x.line_key = ANY (v_matched))
           AND fn_cbd_identity(x.component_id, x.local_component_no, x.sub_seq, x.sub_name, x.material_id)
             = fn_cbd_identity(e.component_id, e.local_component_no, e.sub_seq, e.sub_name, e.material_id)
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
        -- harga quotation ikut bila material sama dan masih bermetode Quotation
        v_carry := s.price_source = 'QUOTATION' AND s.material_id = e.material_id
                   AND EXISTS (SELECT 1 FROM material WHERE id = e.material_id AND price_method = 'QUOTATION');
      ELSIF e.replaces_line_key IS NOT NULL THEN
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
                            material_id, color, supplier_id, uom, group_code, yield_value, loss_pct,
                            price_original, currency, price_source, material_price_id, price_override_reason,
                            price_reference, status, value_origin, value_source_ref, sort_order, updated_by)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.color, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              s.price_original, s.currency, s.price_source, NULL, NULL,
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

  IF p_mark_missing AND v_has_src THEN
    INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                          material_id, color, supplier_id, uom, group_code, yield_value, loss_pct,
                          price_original, currency, price_source, material_price_id, price_override_reason,
                          price_reference, status, value_origin, value_source_ref, sort_order, updated_by)
    SELECT p_revision_id, x.line_key, x.component_id, x.local_component_no, x.sub_seq, x.sub_name,
           x.material_id, x.color, x.supplier_id, x.uom, x.group_code, x.yield_value, x.loss_pct,
           x.price_original, x.currency, x.price_source, x.material_price_id, x.price_override_reason,
           x.price_reference, 'MISSING_IN_SPEC', x.value_origin, x.value_source_ref,
           v_sort + (row_number() OVER (ORDER BY x.sort_order))::integer, p_email
      FROM unnest(p_src) x
     WHERE NOT (x.line_key = ANY (v_matched));
  END IF;
  RETURN v_sort;
END;
$$;

-- ---------------------------------------------------------------- 4. Override dihapus
CREATE OR REPLACE FUNCTION fn_cbd_override_price(p_token text, p_line_id uuid, p_price numeric,
                                                 p_currency text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Override harga tidak dipakai lagi. Harga material katalog diisi di Master Material.';
END;
$$;

-- ---------------------------------------------------------------- 2. Rate boleh dikosongkan
CREATE OR REPLACE FUNCTION fn_cbd_header_set(p_token text, p_cbd_revision_id uuid, p_field text, p_value numeric)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_cbd');
  v_rev   cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
  v_fob   numeric;
BEGIN
  IF p_field = 'RATE' THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION 'Exchange rate harus lebih besar dari 0 (kosongkan kalau belum ada).';
    END IF;
    UPDATE cbd_revision SET exchange_rate = p_value, updated_by = v_email WHERE id = v_rev.id;
  ELSIF p_field IN ('TARGET_FOB', 'SELLING_PRICE') THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION '% harus lebih besar dari 0 (kosongkan kalau belum ada).',
        CASE p_field WHEN 'TARGET_FOB' THEN 'Target FOB' ELSE 'Selling price' END;
    END IF;
    IF p_field = 'TARGET_FOB' THEN
      UPDATE cbd_revision SET target_fob = p_value, updated_by = v_email WHERE id = v_rev.id;
    ELSE
      UPDATE cbd_revision SET selling_price = p_value, updated_by = v_email WHERE id = v_rev.id;
    END IF;
  ELSIF p_field = 'MARGIN' THEN
    IF p_value IS NULL THEN
      UPDATE cbd_revision SET selling_price = NULL, updated_by = v_email WHERE id = v_rev.id;
    ELSE
      IF p_value >= 100 THEN
        RAISE EXCEPTION 'Margin harus kurang dari 100%%.';
      END IF;
      SELECT actual_fob INTO v_fob FROM v_cbd_recap WHERE cbd_revision_id = v_rev.id;
      IF coalesce(v_fob, 0) <= 0 THEN
        RAISE EXCEPTION 'Actual FOB masih 0 — isi harga & Yield dulu, atau isi Selling price langsung.';
      END IF;
      UPDATE cbd_revision SET selling_price = round(v_fob / (1 - p_value / 100), 2), updated_by = v_email
       WHERE id = v_rev.id;
    END IF;
  ELSE
    RAISE EXCEPTION 'Kolom tidak valid.';
  END IF;
  RETURN v_rev.id;
END;
$$;

-- ---------------------------------------------------------------- 3. Checklist CBD: revisi awal per article
-- Kolom sama dengan F8b; hanya requires_reason yang berubah.
CREATE OR REPLACE VIEW v_cbd_checklist AS
SELECT x.*,
       (x.spec_status <> 'ACTIVE' OR x.spec_stale OR NOT x.rate_ok OR x.stale_prices > 0 OR x.no_yield_count > 0) AS blocked
  FROM (
    SELECT r.id AS cbd_revision_id, r.article_id, r.stage, r.revision_no, r.status,
           EXISTS (SELECT 1 FROM cbd_revision o
                    WHERE o.article_id = r.article_id AND o.status = 'PUBLISHED' AND o.id <> r.id) AS requires_reason,
           fn_cbd_article_spec_status(r.article_id) AS spec_status,
           (r.specsheet_revision_id IS DISTINCT FROM fn_spec_latest_pub(a.specsheet_id)) AS spec_stale,
           (r.exchange_rate IS NOT NULL) AS rate_ok,
           (SELECT count(*)::int FROM v_cbd_price_check pc
             WHERE pc.cbd_revision_id = r.id AND pc.master_stale) AS stale_prices,
           rc.no_yield_count, rc.unpriced_count, rc.line_count, rc.missing_count
      FROM cbd_revision r
      JOIN article a ON a.id = r.article_id
      JOIN v_cbd_recap rc ON rc.cbd_revision_id = r.id
  ) x;

-- ---------------------------------------------------------------- 3 + 6. Checklist specsheet
-- Kolom baru proposed_items -> view dibuat ulang (v_worklist_spec ikut dibuat ulang di bawah).
DROP VIEW IF EXISTS v_worklist_spec;
DROP VIEW IF EXISTS v_revision_checklist;
CREATE VIEW v_revision_checklist AS
SELECT x.*,
       (x.active_articles = 0 OR x.unused_articles IS NOT NULL OR x.inactive_materials IS NOT NULL
        OR x.no_supplier_lines > 0 OR x.proposed_items IS NOT NULL) AS blocked
  FROM (
    SELECT r.id AS revision_id, r.specsheet_id, r.stage, r.revision_no, r.status,
           EXISTS (SELECT 1 FROM specsheet_revision o
                    WHERE o.specsheet_id = r.specsheet_id AND o.status = 'PUBLISHED' AND o.id <> r.id) AS requires_reason,
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
             WHERE l.revision_id = r.id AND l.is_active AND l.supplier_id IS NULL) AS no_supplier_lines,
           (SELECT string_agg(DISTINCT p.item, ', ')
              FROM bom_line l
              JOIN material m ON m.id = l.material_id
              LEFT JOIN component c ON c.id = l.component_id
              LEFT JOIN supplier s ON s.id = l.supplier_id
              LEFT JOIN material_supplier ms ON ms.material_id = l.material_id AND ms.supplier_id = l.supplier_id
              CROSS JOIN LATERAL (VALUES
                (CASE WHEN m.status = 'PROPOSED' THEN 'material ' || m.material_code END),
                (CASE WHEN c.status = 'PROPOSED' THEN 'komponen ' || c.number END),
                (CASE WHEN s.status = 'PROPOSED' THEN 'supplier ' || s.name END),
                (CASE WHEN ms.status = 'PROPOSED' THEN 'supplier material ' || m.material_code || ' / ' || s.name END)
              ) AS p(item)
             WHERE l.revision_id = r.id AND l.is_active AND p.item IS NOT NULL) AS proposed_items
      FROM specsheet_revision r
  ) x;

CREATE VIEW v_worklist_spec AS
SELECT 'DRAFT'::text AS kind,
       pm.id AS model_id, pm.code AS model_code, pm.name AS model_name,
       sh.id AS specsheet_id, sh.season,
       r.id AS revision_id, r.stage, r.revision_no,
       ck.line_count, ck.no_supplier_lines AS no_supplier, ck.active_articles AS article_count,
       ck.unused_articles, ck.inactive_materials,
       NULL::text AS article_codes, NULL::boolean AS has_revision,
       ck.proposed_items
  FROM specsheet_revision r
  JOIN specsheet sh ON sh.id = r.specsheet_id
  JOIN product_model pm ON pm.id = sh.model_id
  JOIN v_revision_checklist ck ON ck.revision_id = r.id
 WHERE r.status = 'DRAFT'
UNION ALL
SELECT 'UNASSIGNED',
       pm.id, pm.code, pm.name,
       sh.id, sh.season,
       NULL::uuid, NULL::text, NULL::integer,
       NULL::integer, NULL::integer, u.n,
       NULL::text, NULL::text,
       u.codes, EXISTS (SELECT 1 FROM specsheet_revision x WHERE x.specsheet_id = sh.id),
       NULL::text
  FROM specsheet sh
  JOIN product_model pm ON pm.id = sh.model_id
  CROSS JOIN LATERAL (
    SELECT count(*)::integer AS n, string_agg(a.code, ', ' ORDER BY a.code) AS codes
      FROM article a
     WHERE a.specsheet_id = sh.id
       AND NOT EXISTS (SELECT 1 FROM revision_article ra WHERE ra.article_id = a.id)
  ) u
 WHERE u.n > 0;

-- fn_revision_publish (F8) + blokir baris tanpa supplier & usulan belum di-approve
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
  IF v_chk.no_supplier_lines > 0 THEN
    RAISE EXCEPTION 'Ada % baris BOM tanpa supplier. Isi supplier semua baris dulu.', v_chk.no_supplier_lines;
  END IF;
  IF v_chk.proposed_items IS NOT NULL THEN
    RAISE EXCEPTION 'Masih ada usulan yang belum di-approve Master Admin: %.', v_chk.proposed_items;
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

  PERFORM fn_cbd_sync_spec(v_rev.id, v_email);   -- F8
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------- 9. Antrian admin + supplier usulan
CREATE OR REPLACE VIEW v_worklist_admin AS
SELECT 'MATERIAL'::text AS kind, m.id AS ref_id, m.id AS material_id,
       m.material_code || ' · ' || m.name AS title,
       m.category AS detail, NULL::text AS amount_text,
       m.created_by AS proposed_by, m.created_at AS proposed_at
  FROM material m
 WHERE m.status = 'PROPOSED'
UNION ALL
SELECT 'COMPONENT', c.id, NULL::uuid,
       c.number || ' · ' || c.name,
       'Kelompok ' || c.group_code, NULL::text,
       c.created_by, c.created_at
  FROM component c
 WHERE c.status = 'PROPOSED'
UNION ALL
SELECT 'LINK', ms.id, ms.material_id,
       m.material_code || ' · ' || m.name,
       'Supplier ' || s.name, NULL::text,
       ms.created_by, ms.created_at
  FROM material_supplier ms
  JOIN material m ON m.id = ms.material_id
  JOIN supplier s ON s.id = ms.supplier_id
 WHERE ms.status = 'PROPOSED'
UNION ALL
SELECT 'PRICE', mp.id, ms.material_id,
       m.material_code || ' · ' || m.name,
       'Supplier ' || s.name || coalesce(' · warna ' || nullif(btrim(mp.color), ''), ''),
       mp.currency || ' ' || trim_scale(mp.price)::text,
       mp.created_by, mp.created_at
  FROM material_price mp
  JOIN material_supplier ms ON ms.id = mp.material_supplier_id
  JOIN material m ON m.id = ms.material_id
  JOIN supplier s ON s.id = ms.supplier_id
 WHERE mp.status = 'PROPOSED'
UNION ALL
SELECT 'SUPPLIER', s.id, NULL::uuid,
       s.name,
       'Supplier baru', NULL::text,
       s.created_by, s.created_at
  FROM supplier s
 WHERE s.status = 'PROPOSED';

-- ---------------------------------------------------------------- 8. Huruf kapital otomatis
-- Dipasang sebagai trigger "trg_aa_upper" supaya jalan PALING AWAL (urutan nama) sebelum trigger cek/normalisasi.
-- Kode article hanya diubah saat dibuat / diganti (kode article terpakai tidak boleh berubah).
CREATE OR REPLACE FUNCTION fn_upper_names() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME IN ('supplier', 'component') THEN
    NEW.name := upper(NEW.name);
  ELSIF TG_TABLE_NAME = 'material' THEN
    NEW.name := upper(NEW.name);
    NEW.category := upper(NEW.category);
  ELSIF TG_TABLE_NAME = 'product_model' THEN
    NEW.code := upper(NEW.code);
    NEW.name := upper(NEW.name);
  ELSIF TG_TABLE_NAME = 'article' THEN
    NEW.colorway := upper(NEW.colorway);
    IF TG_OP = 'INSERT' OR NEW.code IS DISTINCT FROM OLD.code THEN
      NEW.code := upper(NEW.code);
    END IF;
  ELSIF TG_TABLE_NAME = 'bom_line' THEN
    NEW.local_component_name := upper(NEW.local_component_name);
    NEW.sub_name := upper(NEW.sub_name);
  END IF;
  RETURN NEW;
END;
$$;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['supplier', 'component', 'material', 'product_model', 'article', 'bom_line'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_aa_upper ON %I', t);
    EXECUTE format('CREATE TRIGGER trg_aa_upper BEFORE INSERT OR UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION fn_upper_names()', t);
  END LOOP;
END;
$$;

-- Data lama
UPDATE supplier SET name = upper(name) WHERE name <> upper(name);
UPDATE component SET name = upper(name) WHERE name <> upper(name);
UPDATE material SET name = upper(name), category = upper(category)
 WHERE name <> upper(name) OR category <> upper(category);
UPDATE product_model SET code = upper(code), name = upper(name) WHERE code <> upper(code) OR name <> upper(name);
UPDATE article SET colorway = upper(colorway) WHERE colorway <> upper(colorway);
UPDATE article SET code = upper(code) WHERE code <> upper(code) AND NOT fn_article_is_used(id);
UPDATE bom_line l
   SET local_component_name = upper(l.local_component_name), sub_name = upper(l.sub_name)
  FROM specsheet_revision r
 WHERE r.id = l.revision_id AND r.status = 'DRAFT'
   AND (l.local_component_name <> upper(l.local_component_name) OR l.sub_name <> upper(l.sub_name));

-- ---------------------------------------------------------------- 10. Gambar di change log
DO $$
BEGIN
  IF to_regclass('public.change_log_attachment') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'change_log_attachment' AND column_name = 'change_log_id') THEN
    RAISE EXCEPTION 'Tabel "change_log_attachment" sudah ada di database dan bukan milik proyek ini. Hentikan dan hubungi pengembang.';
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS change_log_attachment (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  change_log_id uuid NOT NULL REFERENCES change_log(id) ON DELETE CASCADE,
  file_name     text NOT NULL,
  mime_type     text NOT NULL CHECK (mime_type IN ('image/png', 'image/jpeg')),
  size_bytes    integer NOT NULL CHECK (size_bytes <= 5242880),
  content       bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text
);
CREATE INDEX IF NOT EXISTS idx_change_log_attachment_log ON change_log_attachment (change_log_id);
SELECT fn_setup_table('change_log_attachment');

-- Lampirkan satu gambar ke change log yang BARU dibuat user ini (≤ 1 jam), maks. 5 gambar per change log.
-- Jenis file dicek dari isi (PNG / JPEG). p_data = base64 tanpa awalan "data:".
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
  v_email := fn_auth(p_token, CASE v_log.doc_type WHEN 'CBD' THEN 'edit_cbd' ELSE 'edit_specsheet' END);
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
