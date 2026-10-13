-- ============================================================================
-- R11 — Skalabilitas, bug, dan kesesuaian alur (12 Okt 2026, PLAN.md §6 R11 + §9 T54–T59, A1–A9).
-- Jalankan SETELAH R10_hapus_varian.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF),
-- SEBELUM import build R11. Aman diulang. Satu transaksi. Tidak menghapus data.
--
-- Skalabilitas (diuji dengan data sintetis 5 tahun, tools/beban):
--   S1  v_worklist_cbd ditulis ulang (dulu timeout di ±3 tahun)       S3  index cbd_line(variant_id)
--   S2  v_worklist_price_gap: hanya 2 season terakhir per pabrik      S4  index ekspresi kolom::text (filter query app)
--   S7  audit_log ramping: UPDATE = kolom yang berubah saja, INSERT tanpa salinan isi, DELETE lengkap
--   S8  v_system_summary: jumlah audit perkiraan + ukuran audit_log   S10 v_cbd_checklist.pending_list per revisi
-- Bug: T54 akhiri harga AKAN BERLAKU membuka lagi harga sebelumnya · T55 proses usulan harga dikunci per baris
--      T57 nama/kategori/UoM material & nama model dikunci bila dipakai dokumen terbit · T58 hapus baris hasil
--      Ganti material = batalkan penggantian (baris lama aktif lagi; v_bom_grid.undo_replace untuk tombol grid)
-- Alur: A1/T56 baris CBD "Tanpa biaya" (alasan wajib) + peringatan (tidak memblokir) untuk baris ber-Yield yang
--       belum berharga; baris tanpa harga & tanpa Yield dianggap memang tanpa biaya (tidak didaftar)
--       A4 rincian perubahan CBD (cost bridge) dihitung otomatis saat terbit, disimpan di change_log.diff
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_variant_delete(text,uuid)') IS NULL THEN
    RAISE EXCEPTION 'R10 belum terpasang. Jalankan sql/R10_hapus_varian.sql dulu.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- S7: audit ramping
-- INSERT: tanpa salinan isi (barisnya ada di tabelnya sendiri) · UPDATE: hanya kolom yang berubah (before = nilai
-- lama, after = nilai baru) · DELETE: isi lengkap. Kolom teknis (updated_*, login) tidak dihitung sebagai perubahan.
CREATE OR REPLACE FUNCTION fn_audit_trigger() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_old    jsonb;
  v_new    jsonb;
  v_row    jsonb;
  v_before jsonb;
  v_after  jsonb;
  c_skip   text[] := ARRAY['updated_at', 'updated_by', 'failed_attempts', 'locked_until', 'last_login_at'];
BEGIN
  IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD) - 'content' - 'password_hash'; END IF;
  IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW) - 'content' - 'password_hash'; END IF;
  IF TG_OP = 'UPDATE' THEN
    SELECT jsonb_object_agg(o.key, o.value), jsonb_object_agg(o.key, v_new -> o.key)
      INTO v_before, v_after
      FROM jsonb_each(v_old) o
     WHERE NOT (o.key = ANY (c_skip)) AND o.value IS DISTINCT FROM v_new -> o.key;
    IF v_before IS NULL THEN
      RETURN NULL;                       -- UPDATE yang tidak mengubah apa pun tidak dicatat
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    v_before := v_old;
  END IF;
  v_row := coalesce(v_new, v_old);
  INSERT INTO audit_log (user_email, entity, entity_id, action, before_data, after_data)
  VALUES (
    coalesce(nullif(current_setting('app.user', true), ''), v_new ->> 'updated_by', v_old ->> 'updated_by'),
    TG_TABLE_NAME,
    coalesce(v_row ->> 'id', v_row ->> 'email', v_row ->> 'code',
             concat_ws(':', v_row ->> 'revision_id', v_row ->> 'bom_line_id', v_row ->> 'article_id')),
    TG_OP, v_before, v_after
  );
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------- S3 + S4: index
CREATE INDEX IF NOT EXISTS idx_cbd_line_variant ON cbd_line (variant_id);
-- Query app memfilter "kolom::text = '<id>'": index biasa tidak terpakai -> index ekspresi di tabel besar
CREATE INDEX IF NOT EXISTS idx_cbd_line_revision_txt ON cbd_line ((cbd_revision_id::text));
CREATE INDEX IF NOT EXISTS idx_bom_line_revision_txt ON bom_line ((revision_id::text));
CREATE INDEX IF NOT EXISTS idx_cbd_cost_item_revision_txt ON cbd_cost_item ((cbd_revision_id::text));
CREATE INDEX IF NOT EXISTS idx_revision_article_revision_txt ON revision_article ((revision_id::text));
CREATE INDEX IF NOT EXISTS idx_cbd_revision_article_txt ON cbd_revision ((article_id::text));

-- ---------------------------------------------------------------- A1: baris CBD tanpa biaya
ALTER TABLE cbd_line ADD COLUMN IF NOT EXISTS no_charge boolean NOT NULL DEFAULT false;
ALTER TABLE cbd_line ADD COLUMN IF NOT EXISTS no_charge_reason text;
ALTER TABLE cbd_line ADD COLUMN IF NOT EXISTS replaces_line_key uuid;      -- A4: baris specsheet yang diganti
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_cbd_line_no_charge') THEN
    ALTER TABLE cbd_line ADD CONSTRAINT chk_cbd_line_no_charge
      CHECK (NOT no_charge OR btrim(coalesce(no_charge_reason, '')) <> '');
  END IF;
END;
$$;

-- ---------------------------------------------------------------- view CBD
-- Baris tanpa biaya: cost/pair = 0 (harga tetap terlihat). Kolom baru di akhir.
CREATE OR REPLACE VIEW v_cbd_line AS
 SELECT cl.id,
    cl.cbd_revision_id,
    cl.line_key,
    cl.status,
    cl.group_code,
    g.name AS group_name,
    g.sort_order AS group_sort,
    COALESCE(c.number, cl.local_component_no) AS comp_no,
        CASE
            WHEN (cl.sub_seq IS NOT NULL) THEN (COALESCE(((COALESCE(c.number, cl.local_component_no))::text || '-'::text), ''::text) || cl.sub_seq)
            ELSE (COALESCE(c.number, cl.local_component_no))::text
        END AS display_no,
        CASE
            WHEN (cl.sub_seq IS NOT NULL) THEN COALESCE(cl.sub_name, m.name)
            ELSE COALESCE(c.name, bl.local_component_name, ('Lokal '::text || cl.local_component_no), m.name)
        END AS display_name,
    (cl.sub_seq IS NOT NULL) AS is_sub,
    ((cl.component_id IS NULL) AND (cl.sub_seq IS NULL)) AS is_local,
    cl.material_id,
    v.code AS material_code,
    m.name AS material_name,
    cl.thickness,
    m.price_method,
    cl.color,
    cl.supplier_id,
    s.name AS supplier_name,
    cl.uom,
    bl.process AS remarks,
    cl.yield_value,
    cl.usage_value,
    cl.loss_pct,
    cl.price_original,
    cl.currency,
    cl.price_source,
    cl.material_price_id,
    NULL::text AS master_price_color,
    mp.valid_from AS master_price_valid_from,
    cl.price_override_reason,
    cl.price_reference,
    x.price_usd,
    x.price_idr,
        CASE
            WHEN cl.no_charge THEN (0)::numeric
            ELSE ((cl.usage_value * x.price_idr) * ((1)::numeric + (COALESCE(cl.loss_pct, (0)::numeric) / (100)::numeric)))
        END AS cost_per_pair,
    cl.value_origin,
    cl.value_source_ref,
    cl.sort_order,
    cl.variant_id,
    cl.no_charge,
    cl.no_charge_reason,
    cl.replaces_line_key
   FROM (((((((((cbd_line cl
     JOIN cbd_revision cr ON ((cr.id = cl.cbd_revision_id)))
     JOIN material m ON ((m.id = cl.material_id)))
     LEFT JOIN material_variant v ON ((v.id = cl.variant_id)))
     LEFT JOIN component c ON ((c.id = cl.component_id)))
     LEFT JOIN component_group g ON ((g.code = cl.group_code)))
     LEFT JOIN supplier s ON ((s.id = cl.supplier_id)))
     LEFT JOIN material_price mp ON ((mp.id = cl.material_price_id)))
     LEFT JOIN bom_line bl ON (((bl.revision_id = cr.specsheet_revision_id) AND (bl.line_key = cl.line_key))))
     CROSS JOIN LATERAL ( SELECT
                CASE cl.currency
                    WHEN 'IDR'::text THEN cl.price_original
                    WHEN 'USD'::text THEN (cl.price_original * cr.exchange_rate)
                    ELSE NULL::numeric
                END AS price_idr,
                CASE cl.currency
                    WHEN 'USD'::text THEN cl.price_original
                    WHEN 'IDR'::text THEN (cl.price_original / NULLIF(cr.exchange_rate, (0)::numeric))
                    ELSE NULL::numeric
                END AS price_usd) x);

-- Baris tanpa biaya tidak ikut cek harga master (tidak basi / menunggu)
CREATE OR REPLACE VIEW v_cbd_price_check AS
SELECT l.id AS line_id, l.cbd_revision_id,
       cur.price_id AS master_price_id, cur.price AS master_price, cur.currency AS master_currency,
       CASE WHEN l.price_source = 'QUOTATION' THEN m.price_method = 'CATALOG'
            WHEN m.price_method = 'QUOTATION' THEN l.price_source = 'MASTER'
            ELSE cur.price_id IS DISTINCT FROM l.material_price_id END AS master_stale,
       CASE WHEN l.price_original IS NOT NULL THEN NULL
            WHEN m.price_method = 'QUOTATION' THEN 'QUOTATION'
            WHEN l.supplier_id IS NULL THEN 'NO_SUPPLIER'
            WHEN cur.price_id IS NOT NULL THEN 'AVAILABLE'
            WHEN pend.pending THEN 'PENDING'
            ELSE 'NO_PRICE' END AS price_gap,
       NULL::text AS other_colors,
       (m.price_method = 'CATALOG' AND pend.pending) AS pending
  FROM cbd_line l
  JOIN cbd_revision r ON r.id = l.cbd_revision_id
  JOIN material m ON m.id = l.material_id
  LEFT JOIN LATERAL fn_price_lookup(l.variant_id, l.supplier_id) cur ON true
  CROSS JOIN LATERAL (SELECT coalesce(fn_price_pending(l.variant_id, l.supplier_id), false) AS pending) pend
 WHERE r.status = 'DRAFT' AND l.status = 'ACTIVE' AND NOT l.no_charge;

-- Baris tanpa biaya tidak dihitung "belum berharga" / "tanpa yield". no_charge_count & blank_count (tanpa harga
-- dan tanpa Yield) di akhir.
CREATE OR REPLACE VIEW v_cbd_recap AS
 SELECT r.id AS cbd_revision_id,
    r.status,
    r.exchange_rate,
    r.target_fob,
    t.material_cost,
    ci.labour,
    ci.amortization,
    ci.adjustment,
    ci.other,
    ci.items_total,
    f.actual_fob,
    (f.actual_fob - r.target_fob) AS variance,
        CASE
            WHEN (r.target_fob IS NULL) THEN NULL::text
            WHEN (f.actual_fob > r.target_fob) THEN 'OVER'::text
            WHEN (f.actual_fob < r.target_fob) THEN 'UNDER'::text
            ELSE 'SESUAI'::text
        END AS variance_label,
    t.line_count,
    t.unpriced_count,
    t.no_yield_count,
    t.usd_no_rate_count,
    t.missing_count,
    COALESCE(gc.group_costs, '{}'::jsonb) AS group_costs,
    r.stage,
    pf.po_factor,
    round((f.actual_fob * pf.po_factor), 2) AS po_price,
    t.no_charge_count,
    t.blank_count
   FROM (((((cbd_revision r
     CROSS JOIN LATERAL ( SELECT COALESCE(sum(v.cost_per_pair) FILTER (WHERE (v.status = 'ACTIVE'::text)), (0)::numeric) AS material_cost,
            (count(*) FILTER (WHERE (v.status = 'ACTIVE'::text)))::integer AS line_count,
            (count(*) FILTER (WHERE ((v.status = 'ACTIVE'::text) AND (v.price_original IS NULL) AND NOT v.no_charge)))::integer AS unpriced_count,
            (count(*) FILTER (WHERE ((v.status = 'ACTIVE'::text) AND (v.price_original IS NOT NULL) AND (v.yield_value IS NULL) AND NOT v.no_charge)))::integer AS no_yield_count,
            (count(*) FILTER (WHERE ((v.status = 'ACTIVE'::text) AND (v.currency = 'USD'::text) AND (v.price_idr IS NULL) AND NOT v.no_charge)))::integer AS usd_no_rate_count,
            (count(*) FILTER (WHERE (v.status = 'MISSING_IN_SPEC'::text)))::integer AS missing_count,
            (count(*) FILTER (WHERE ((v.status = 'ACTIVE'::text) AND v.no_charge)))::integer AS no_charge_count,
            (count(*) FILTER (WHERE ((v.status = 'ACTIVE'::text) AND (v.price_original IS NULL) AND (v.yield_value IS NULL)
                                     AND NOT v.no_charge)))::integer AS blank_count
           FROM v_cbd_line v
          WHERE (v.cbd_revision_id = r.id)) t)
     CROSS JOIN LATERAL ( SELECT COALESCE(sum(c.amount) FILTER (WHERE (c.item_type = 'LABOUR'::text)), (0)::numeric) AS labour,
            COALESCE(sum(c.amount) FILTER (WHERE (c.item_type = 'AMORTIZATION'::text)), (0)::numeric) AS amortization,
            COALESCE(sum(c.amount) FILTER (WHERE (c.item_type = 'ADJUSTMENT'::text)), (0)::numeric) AS adjustment,
            COALESCE(sum(c.amount) FILTER (WHERE (c.item_type = 'OTHER'::text)), (0)::numeric) AS other,
            COALESCE(sum(c.amount), (0)::numeric) AS items_total
           FROM cbd_cost_item c
          WHERE (c.cbd_revision_id = r.id)) ci)
     CROSS JOIN LATERAL ( SELECT jsonb_object_agg(x.group_code, x.cost) AS group_costs
           FROM ( SELECT v.group_code,
                    COALESCE(sum(v.cost_per_pair), (0)::numeric) AS cost
                   FROM v_cbd_line v
                  WHERE ((v.cbd_revision_id = r.id) AND (v.status = 'ACTIVE'::text))
                  GROUP BY v.group_code) x) gc)
     CROSS JOIN LATERAL ( SELECT (t.material_cost + ci.items_total) AS actual_fob) f)
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN (r.status = 'PUBLISHED'::text) THEN r.po_factor
                    ELSE ( SELECT s.po_factor
                       FROM stage_setting s
                      WHERE (s.stage = r.stage))
                END AS po_factor) pf);

-- T56/A1 (keputusan user 13 Okt 2026: peringatan saja): unpriced_count / unpriced_list = baris ber-Yield yang belum
-- berharga (kemungkinan lupa) — TIDAK memblokir; blank_count = tanpa harga & tanpa Yield (tidak didaftar).
-- S10: pending_list hanya revisi ini. no_charge_count, unpriced_list, blank_count di akhir.
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
            fn_cbd_article_spec_status(r.article_id) AS spec_status,
            (r.specsheet_revision_id IS DISTINCT FROM fn_spec_latest_pub(a.specsheet_id)) AS spec_stale,
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

-- ---------------------------------------------------------------- S1: Tugas Saya Vendor CBD
-- Set article (aktif di specsheet terbit terakhir) dihitung sekali lewat join biasa. Dulu filter fungsi di WHERE
-- membuat planner salah perkiraan (28 baris) -> nested loop berulang -> timeout di data ±3 tahun.
CREATE OR REPLACE VIEW v_worklist_cbd AS
WITH art AS MATERIALIZED (
  SELECT a.id, a.code, a.colorway, a.specsheet_id, sh.season, sh.model_id, sp.id AS spec_pub_id
    FROM specsheet sh
    JOIN specsheet_revision sp ON sp.id = fn_spec_latest_pub(sh.id)
    JOIN revision_article ra ON ra.revision_id = sp.id AND ra.status = 'ACTIVE'
    JOIN article a ON a.id = ra.article_id
)
SELECT x.*
  FROM (
    SELECT CASE WHEN rc.n = 0 THEN 'TO_CREATE'
                WHEN d.id IS NOT NULL
                     THEN CASE WHEN d.specsheet_revision_id IS DISTINCT FROM art.spec_pub_id OR pr.stale_prices > 0
                               THEN 'TO_REFRESH' ELSE 'IN_PROGRESS' END
                WHEN p.sync_status = 'NEEDS_REVISION' THEN 'TO_REVISE' END AS kind,
           CASE WHEN d.id IS NULL THEN NULL
                WHEN d.specsheet_revision_id IS DISTINCT FROM art.spec_pub_id THEN 'SPEC'
                WHEN pr.stale_prices > 0 THEN 'PRICE' END AS refresh_reason,
           art.id AS article_id, art.code AS article_code, art.colorway,
           pm.id AS model_id, pm.name AS model_name, pm.factory_id,
           art.specsheet_id, art.season,
           coalesce(d.id, p.id) AS cbd_revision_id,
           coalesce((d.stage || ' r') || d.revision_no, (p.stage || ' r') || p.revision_no) AS rev_label,
           pr.pending_prices
      FROM art
      JOIN product_model pm ON pm.id = art.model_id
      LEFT JOIN cbd_revision d ON d.article_id = art.id AND d.status = 'DRAFT'
      LEFT JOIN LATERAL (
        SELECT r.id, r.stage, r.revision_no, r.sync_status
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

-- ---------------------------------------------------------------- S2: material belum ada harga (2 season terakhir)
-- Pemakaian varian dihitung dari specsheet terbit terakhir di 2 season terakhir (yang punya revisi terbit) per pabrik;
-- harga dicek sekali per varian × supplier.
CREATE OR REPLACE VIEW v_worklist_price_gap AS
WITH pub AS MATERIALIZED (
  SELECT sh.id, sh.season_sort, pm.factory_id, pm.name AS model_name, fn_spec_latest_pub(sh.id) AS rev_id
    FROM specsheet sh
    JOIN product_model pm ON pm.id = sh.model_id
), recent AS MATERIALIZED (
  SELECT p.*
    FROM (SELECT pub.*, dense_rank() OVER (PARTITION BY pub.factory_id ORDER BY pub.season_sort DESC) AS rk
            FROM pub WHERE pub.rev_id IS NOT NULL) p
   WHERE p.rk <= 2
), used AS MATERIALIZED (
  SELECT DISTINCT bl.material_id, bl.supplier_id, bc.variant_id, sh.model_name
    FROM recent sh
    JOIN bom_line bl ON bl.revision_id = sh.rev_id AND bl.is_active AND bl.supplier_id IS NOT NULL
    JOIN bom_cell bc ON bc.bom_line_id = bl.id AND bc.variant_id IS NOT NULL
    JOIN revision_article ra ON ra.revision_id = sh.rev_id AND ra.article_id = bc.article_id AND ra.status = 'ACTIVE'
), gap AS MATERIALIZED (
  SELECT p.material_id, p.supplier_id, p.variant_id
    FROM (SELECT DISTINCT used.material_id, used.supplier_id, used.variant_id FROM used) p
    JOIN material m ON m.id = p.material_id AND m.price_method = 'CATALOG'
   WHERE NOT EXISTS (SELECT 1 FROM fn_price_lookup(p.variant_id, p.supplier_id))
)
SELECT m.id AS material_id, m.name AS material_name, m.factory_id,
       s.id AS supplier_id, s.name AS supplier_name,
       count(DISTINCT g.variant_id)::integer AS variant_count,
       string_agg(DISTINCT v.code, ', ') AS codes,
       string_agg(DISTINCT u.model_name, ', ') AS models,
       bool_or(EXISTS (SELECT 1 FROM material_price mp
                        JOIN material_supplier ms ON ms.id = mp.material_supplier_id
                       WHERE ms.material_id = g.material_id AND ms.supplier_id = g.supplier_id
                         AND mp.variant_id = g.variant_id AND mp.status = 'PROPOSED')) AS has_pending
  FROM gap g
  JOIN used u ON u.material_id = g.material_id AND u.supplier_id = g.supplier_id AND u.variant_id = g.variant_id
  JOIN material m ON m.id = g.material_id
  JOIN supplier s ON s.id = g.supplier_id
  JOIN material_variant v ON v.id = g.variant_id
 GROUP BY m.id, m.name, m.factory_id, s.id, s.name;

-- ---------------------------------------------------------------- S8: ringkasan System Admin
-- Jumlah audit = perkiraan statistik (count(*) jutaan baris lambat); ukuran audit_log untuk peringatan di Beranda.
CREATE OR REPLACE VIEW v_system_summary AS
SELECT (SELECT count(*) FROM product_model)::integer AS models,
       (SELECT count(*) FROM specsheet)::integer AS specsheets,
       (SELECT count(*) FROM article)::integer AS articles,
       (SELECT count(*) FROM cbd_revision)::integer AS cbd_revisions,
       (SELECT count(*) FROM material)::integer AS materials,
       (SELECT count(*) FROM app_user WHERE is_active)::integer AS active_users,
       (SELECT CASE WHEN c.reltuples < 0 THEN (SELECT count(*) FROM audit_log)::bigint ELSE c.reltuples::bigint END
          FROM pg_class c WHERE c.oid = 'audit_log'::regclass)::integer AS audit_entries,
       (SELECT max(created_at) FROM audit_log) AS last_audit,
       pg_total_relation_size('audit_log'::regclass) AS audit_size_bytes;

-- ---------------------------------------------------------------- helper teks angka (format Indonesia)
-- 16300 -> '16.300' · 14.7 -> '14,7' (p_dec = digit desimal maksimal)
CREATE OR REPLACE FUNCTION fn_fmt_id(p numeric, p_dec integer DEFAULT 2) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p IS NULL THEN '-' ELSE
    translate(rtrim(to_char(round(p, p_dec),
                            'FM999,999,999,999,990' || CASE WHEN p_dec > 0 THEN '.' || repeat('9', p_dec) ELSE '' END), '.'),
              ',.', '.,') END
$$;

CREATE OR REPLACE FUNCTION fn_change_category_label(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p WHEN 'EX_RATE' THEN 'Exchange rate' WHEN 'LOP' THEN 'LOP' WHEN 'AMORTIZATION' THEN 'Amortisasi'
                WHEN 'MATERIAL' THEN 'Material' WHEN 'YIELD' THEN 'Yield / Loss %' WHEN 'COMPONENT' THEN 'Komponen'
                WHEN 'TREATMENT' THEN 'Treatment' WHEN 'OTHER' THEN 'Lainnya' ELSE p END
$$;

CREATE OR REPLACE FUNCTION fn_change_category_sort(p text) RETURNS integer
LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(array_position(ARRAY['EX_RATE', 'LOP', 'AMORTIZATION', 'MATERIAL', 'YIELD', 'COMPONENT', 'TREATMENT', 'OTHER'], p), 9)
$$;

-- ---------------------------------------------------------------- T57: material & model dikunci setelah terbit
CREATE OR REPLACE FUNCTION fn_material_used_published(p_material_id uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM bom_line l JOIN specsheet_revision r ON r.id = l.revision_id
                  WHERE l.material_id = p_material_id AND r.status = 'PUBLISHED')
      OR EXISTS (SELECT 1 FROM cbd_line cl JOIN cbd_revision c ON c.id = cl.cbd_revision_id
                  WHERE cl.material_id = p_material_id AND c.status = 'PUBLISHED')
$$;

CREATE OR REPLACE FUNCTION fn_material_update(p_token text, p_id uuid, p_name text, p_category text, p_uom text,
                                              p_status text, p_price_method text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_any(p_token, ARRAY['manage_master', 'manage_price']);
  v_master boolean := fn_has_perm(v_email, 'manage_master');
  v_price  boolean := fn_has_perm(v_email, 'manage_price');
  v_old    material%ROWTYPE;
BEGIN
  SELECT * INTO v_old FROM material WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Material tidak ditemukan.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_old.factory_id);
  IF NOT v_master AND (
       fn_normalize(p_name) IS DISTINCT FROM v_old.name_key
    OR fn_normalize(p_category) IS DISTINCT FROM fn_normalize(v_old.category)
    OR fn_normalize(p_uom) IS DISTINCT FROM fn_normalize(v_old.uom)
    OR p_status IS DISTINCT FROM v_old.status) THEN
    RAISE EXCEPTION 'Data dan status material hanya bisa diubah tim specsheet (Vendor Spec).';
  END IF;
  IF NOT v_price AND p_price_method IS DISTINCT FROM v_old.price_method THEN
    RAISE EXCEPTION 'Metode harga hanya bisa diubah tim CBD.';
  END IF;
  IF v_master AND coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Status material wajib dipilih (ACTIVE / INACTIVE).';
  END IF;
  IF v_price AND coalesce(p_price_method, '') NOT IN ('CATALOG', 'QUOTATION') THEN
    RAISE EXCEPTION 'Metode harga wajib dipilih.';
  END IF;
  -- T57: dokumen terbit membaca nama / kategori / UoM material langsung dari master
  IF v_master AND (fn_normalize(p_name) IS DISTINCT FROM v_old.name_key
                   OR fn_normalize(p_category) IS DISTINCT FROM fn_normalize(v_old.category)
                   OR fn_normalize(p_uom) IS DISTINCT FROM fn_normalize(v_old.uom))
     AND fn_material_used_published(p_id) THEN
    RAISE EXCEPTION 'Nama, kategori, dan UoM material % tidak bisa diubah: sudah dipakai di specsheet / CBD terbit. Tambahkan material baru bila perlu (status tetap bisa diubah).', v_old.name;
  END IF;
  UPDATE material
     SET name         = CASE WHEN v_master THEN p_name     ELSE name END,
         category     = CASE WHEN v_master THEN p_category ELSE category END,
         uom          = CASE WHEN v_master THEN p_uom      ELSE uom END,
         status       = CASE WHEN v_master THEN p_status   ELSE status END,
         price_method = CASE WHEN v_price  THEN p_price_method ELSE price_method END,
         updated_by   = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_model_save(p_token text, p_id uuid, p_name text, p_category_id uuid, p_construction_id uuid,
                                         p_gender_id uuid, p_last_id uuid, p_outsole_mold_id uuid, p_sizes jsonb,
                                         p_sample_size integer) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email   text := fn_auth(p_token, 'edit_model');
  v_old     product_model%ROWTYPE;
  v_factory uuid;
  v_sizes   integer[];
  v_id      uuid;
BEGIN
  IF p_id IS NULL THEN
    v_factory := fn_user_factory(v_email);
    IF v_factory IS NULL THEN
      RAISE EXCEPTION 'Akun Anda belum terhubung ke pabrik. Minta System Admin mengisi pabrik Anda.';
    END IF;
  ELSE
    SELECT * INTO v_old FROM product_model WHERE id = p_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Model tidak ditemukan.';
    END IF;
    PERFORM fn_assert_factory(v_email, v_old.factory_id);
    v_factory := v_old.factory_id;
    -- T57: nama model tampil di specsheet / CBD terbit
    IF fn_normalize(p_name) IS DISTINCT FROM v_old.name_key
       AND EXISTS (SELECT 1 FROM specsheet sh JOIN specsheet_revision r ON r.specsheet_id = sh.id
                    WHERE sh.model_id = p_id AND r.status = 'PUBLISHED') THEN
      RAISE EXCEPTION 'Nama model % tidak bisa diubah: sudah dipakai di specsheet terbit.', v_old.name;
    END IF;
  END IF;
  IF p_category_id IS NULL THEN
    RAISE EXCEPTION 'Kategori wajib dipilih.';
  END IF;
  PERFORM fn_model_option_ref(p_category_id, 'KATEGORI', v_factory, v_old.category_id);
  PERFORM fn_model_option_ref(p_construction_id, 'CONSTRUCTION', v_factory, v_old.construction_id);
  PERFORM fn_model_option_ref(p_gender_id, 'GENDER', v_factory, v_old.gender_id);
  PERFORM fn_model_option_ref(p_last_id, 'LAST', v_factory, v_old.last_id);
  PERFORM fn_model_option_ref(p_outsole_mold_id, 'OUTSOLE_MOLD', v_factory, v_old.outsole_mold_id);
  IF jsonb_typeof(coalesce(p_sizes, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'Daftar ukuran tidak valid.';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(coalesce(p_sizes, '[]'::jsonb)) AS e WHERE e !~ '^[0-9]{1,2}$') THEN
    RAISE EXCEPTION 'Ukuran harus angka bulat (tanpa setengah ukuran).';
  END IF;
  v_sizes := ARRAY(SELECT DISTINCT e::integer FROM jsonb_array_elements_text(coalesce(p_sizes, '[]'::jsonb)) AS e ORDER BY 1);

  IF p_id IS NULL THEN
    INSERT INTO product_model (factory_id, name, category_id, construction_id, gender_id, last_id, outsole_mold_id,
                               sizes, sample_size, updated_by)
    VALUES (v_factory, p_name, p_category_id, p_construction_id, p_gender_id, p_last_id, p_outsole_mold_id,
            v_sizes, p_sample_size, v_email)
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  UPDATE product_model
     SET name = p_name, category_id = p_category_id, construction_id = p_construction_id, gender_id = p_gender_id,
         last_id = p_last_id, outsole_mold_id = p_outsole_mold_id, sizes = v_sizes, sample_size = p_sample_size,
         updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- ---------------------------------------------------------------- T54 + T55: harga material
-- T54: mengakhiri harga yang AKAN BERLAKU = membatalkannya; harga sebelumnya (ditutup saat harga ini disetujui)
--      dibuka lagi. Harga BERLAKU diakhiri per hari ini seperti sebelumnya. Baris dikunci (T55).
CREATE OR REPLACE FUNCTION fn_price_end(p_token text, p_price_id uuid, p_valid_to date) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'approve_price');
  v_row   material_price%ROWTYPE;
  v_fac   uuid;
BEGIN
  SELECT * INTO v_row FROM material_price WHERE id = p_price_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Harga tidak ditemukan.';
  END IF;
  SELECT m.factory_id INTO v_fac FROM material_supplier ms JOIN material m ON m.id = ms.material_id
   WHERE ms.id = v_row.material_supplier_id;
  PERFORM fn_assert_factory(v_email, v_fac);
  IF v_row.status <> 'APPROVED' THEN
    RAISE EXCEPTION 'Hanya harga yang sudah disetujui yang bisa diakhiri. Untuk usulan, pakai Tolak.';
  END IF;
  IF v_row.valid_to IS NOT NULL THEN
    RAISE EXCEPTION 'Harga ini sudah ditutup.';
  END IF;
  IF v_row.valid_from > fn_today() THEN
    UPDATE material_price SET valid_to = NULL, updated_by = v_email
     WHERE material_supplier_id = v_row.material_supplier_id AND variant_id = v_row.variant_id
       AND status = 'APPROVED' AND id <> v_row.id AND valid_to = v_row.valid_from
       AND valid_from < v_row.valid_from;           -- R11b: bukan harga lain yang sudah dibatalkan (0 hari)
    UPDATE material_price SET valid_to = valid_from, updated_by = v_email WHERE id = p_price_id;
    RETURN p_price_id;
  END IF;
  UPDATE material_price
     SET valid_to = greatest(coalesce(p_valid_to, fn_today()), valid_from), updated_by = v_email
   WHERE id = p_price_id;
  RETURN p_price_id;
END;
$$;

-- T55: usulan dikunci dulu (urut id, cegah deadlock), status dibaca ulang setelah kunci didapat
CREATE OR REPLACE FUNCTION fn_price_decide(p_token text, p_price_ids jsonb, p_decision text, p_reason text) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'approve_price');
  v_ids    uuid[] := fn_uuid_list(p_price_ids);
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_n      integer := 0;
  r        record;
BEGIN
  IF coalesce(p_decision, '') NOT IN ('APPROVE', 'REJECT') THEN
    RAISE EXCEPTION 'Keputusan tidak dikenal.';
  END IF;
  IF cardinality(v_ids) = 0 THEN
    RAISE EXCEPTION 'Pilih minimal satu harga.';
  END IF;
  IF p_decision = 'REJECT' AND v_reason IS NULL THEN
    RAISE EXCEPTION 'Alasan penolakan wajib diisi.';
  END IF;
  PERFORM 1 FROM material_price WHERE id = ANY (v_ids) ORDER BY id FOR UPDATE;
  FOR r IN
    SELECT x.id AS req_id, mp.id, mp.status, mp.created_by, v.code, v.status AS variant_status,
           ms.status AS link_status, s.name AS supplier_name, s.status AS supplier_status,
           m.price_method, m.factory_id
      FROM unnest(v_ids) AS x(id)
      LEFT JOIN material_price mp ON mp.id = x.id
      LEFT JOIN material_variant v ON v.id = mp.variant_id
      LEFT JOIN material_supplier ms ON ms.id = mp.material_supplier_id
      LEFT JOIN supplier s ON s.id = ms.supplier_id
      LEFT JOIN material m ON m.id = ms.material_id
     ORDER BY v.code, s.name
  LOOP
    IF r.id IS NULL THEN
      RAISE EXCEPTION 'Ada usulan yang sudah tidak ada (mungkin dibatalkan pengaju). Muat ulang halaman.';
    END IF;
    PERFORM fn_assert_factory(v_email, r.factory_id);
    IF r.status <> 'PROPOSED' THEN
      RAISE EXCEPTION 'Usulan % · % sudah diproses (%). Muat ulang halaman.', r.code, r.supplier_name, r.status;
    END IF;
    IF r.created_by = v_email THEN
      RAISE EXCEPTION 'Anda tidak bisa memproses usulan Anda sendiri.';
    END IF;
    IF p_decision = 'APPROVE' THEN
      IF r.price_method <> 'CATALOG' THEN
        RAISE EXCEPTION 'Material sekarang memakai metode Quotation — tolak usulan %.', r.code;
      END IF;
      IF r.link_status = 'INACTIVE' OR r.supplier_status = 'INACTIVE' THEN
        RAISE EXCEPTION 'Supplier % sudah nonaktif — tolak usulan %.', r.supplier_name, r.code;
      END IF;
      IF r.variant_status = 'INACTIVE' THEN
        RAISE EXCEPTION 'Varian % sudah INACTIVE — tolak usulannya.', r.code;
      END IF;
      PERFORM fn_price_activate(r.id, v_email);
    ELSE
      UPDATE material_price
         SET status = 'REJECTED', reject_reason = v_reason, decided_by = v_email, decided_at = now(), updated_by = v_email
       WHERE id = r.id AND status = 'PROPOSED';
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION fn_price_cancel(p_token text, p_price_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_price');
  v_row   material_price%ROWTYPE;
  v_fac   uuid;
BEGIN
  SELECT * INTO v_row FROM material_price WHERE id = p_price_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Harga tidak ditemukan.';
  END IF;
  SELECT m.factory_id INTO v_fac FROM material_supplier ms JOIN material m ON m.id = ms.material_id
   WHERE ms.id = v_row.material_supplier_id;
  PERFORM fn_assert_factory(v_email, v_fac);
  IF v_row.status <> 'PROPOSED' THEN
    RAISE EXCEPTION 'Hanya usulan yang belum diproses yang bisa dibatalkan.';
  END IF;
  DELETE FROM material_price WHERE id = p_price_id AND status = 'PROPOSED';
  RETURN p_price_id;
END;
$$;

-- ---------------------------------------------------------------- T58: hapus baris hasil Ganti material
-- Baris lama yang akan aktif lagi bila baris pengganti p_line_id dihapus (NULL = hapus biasa). Dipakai fn_bom_delete_line
-- dan v_bom_grid (tombol "Batal ganti" di grid) supaya aturannya sama: baris lama nonaktif di revisi yang sama, dan
-- komponen + material + thickness-nya belum aktif lagi di baris lain.
CREATE OR REPLACE FUNCTION fn_bom_undo_target(p_line_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT o.id
    FROM bom_line l
    JOIN bom_line o ON o.revision_id = l.revision_id AND o.line_key = l.replaces_line_key AND NOT o.is_active
   WHERE l.id = p_line_id AND l.is_active
     AND NOT (o.parent_line_key IS NULL AND EXISTS (
           SELECT 1 FROM bom_line d
            WHERE d.revision_id = o.revision_id AND d.is_active AND d.parent_line_key IS NULL AND d.id <> l.id
              AND d.material_id = o.material_id AND d.thickness IS NOT DISTINCT FROM o.thickness
              AND d.component_id IS NOT DISTINCT FROM o.component_id
              AND d.local_component_no IS NOT DISTINCT FROM o.local_component_no))
   LIMIT 1
$$;

-- Baris pengganti dihapus -> baris lama aktif lagi beserta subkomponennya.
-- Mengembalikan 0 bila penggantian dibatalkan, selain itu jumlah baris yang dihapus.
CREATE OR REPLACE FUNCTION fn_bom_delete_line(p_token text, p_line_id uuid) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
  v_old   bom_line%ROWTYPE;
  v_subs  integer;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  SELECT * INTO v_old FROM bom_line WHERE id = fn_bom_undo_target(v_line.id);
  IF FOUND THEN
    UPDATE bom_line SET parent_line_key = v_old.line_key, updated_by = v_email
     WHERE revision_id = v_line.revision_id AND parent_line_key = v_line.line_key;
    DELETE FROM bom_line WHERE id = v_line.id;
    UPDATE bom_line SET is_active = true, updated_by = v_email WHERE id = v_old.id;
    UPDATE bom_cell SET color = color WHERE bom_line_id = v_old.id;     -- sambungkan ulang Material Code (trigger)
    PERFORM fn_bom_create_cells(v_old.id, v_email);                     -- article yang ditambah setelah penggantian
    RETURN 0;
  END IF;
  DELETE FROM bom_line WHERE revision_id = v_line.revision_id AND parent_line_key = v_line.line_key;
  GET DIAGNOSTICS v_subs = ROW_COUNT;
  DELETE FROM bom_line WHERE id = v_line.id;
  RETURN v_subs + 1;
END;
$$;

-- Grid BOM: kolom undo_replace + undo_material (baris pengganti -> tombol "Batal ganti"). Kolom baru di akhir.
CREATE OR REPLACE VIEW v_bom_grid AS
 SELECT l.id,
    l.revision_id,
    l.line_key,
    l.parent_line_key,
    (l.parent_line_key IS NOT NULL) AS is_sub,
    l.component_id,
    l.local_component_no,
    l.sub_seq,
        CASE
            WHEN (l.parent_line_key IS NULL) THEN COALESCE(c.number, l.local_component_no)
            ELSE COALESCE(pc.number, p.local_component_no)
        END AS group_no,
        CASE
            WHEN (l.parent_line_key IS NULL) THEN l.sort_order
            ELSE COALESCE(p.sort_order, l.sort_order)
        END AS group_sort,
        CASE
            WHEN (l.parent_line_key IS NULL) THEN (COALESCE(c.number, l.local_component_no))::text
            ELSE (COALESCE(((COALESCE(pc.number, p.local_component_no))::text || '-'::text), ''::text) || l.sub_seq)
        END AS display_no,
        CASE
            WHEN (l.parent_line_key IS NULL) THEN COALESCE(c.name, l.local_component_name)
            ELSE l.sub_name
        END AS display_name,
    ((l.component_id IS NULL) AND (l.parent_line_key IS NULL)) AS is_local,
    l.material_id,
    cc.codes AS material_code,
    m.name AS material_name,
    l.thickness,
    m.uom,
    m.status AS material_status,
    l.supplier_id,
    s.name AS supplier_name,
    ms.status AS link_status,
    l.process,
    l.origin_line_key,
    l.replaces_line_key,
    COALESCE(cc.cells, '{}'::jsonb) AS cells,
    s.status AS supplier_status,
    COALESCE(cc.cell_codes, '{}'::jsonb) AS cell_codes,
    COALESCE(cc.yellow, 0) AS yellow,
    (u.id IS NOT NULL) AS undo_replace,
    CASE WHEN u.id IS NOT NULL THEN um.name || COALESCE(' ' || u.thickness, '') END AS undo_material
   FROM (((((((bom_line l
     JOIN material m ON ((m.id = l.material_id)))
     LEFT JOIN component c ON ((c.id = l.component_id)))
     LEFT JOIN bom_line p ON (((p.revision_id = l.revision_id) AND (p.line_key = l.parent_line_key) AND p.is_active)))
     LEFT JOIN component pc ON ((pc.id = p.component_id)))
     LEFT JOIN supplier s ON ((s.id = l.supplier_id)))
     LEFT JOIN material_supplier ms ON (((ms.material_id = l.material_id) AND (ms.supplier_id = l.supplier_id))))
     LEFT JOIN LATERAL ( SELECT jsonb_object_agg((bc.article_id)::text, bc.color) FILTER (WHERE (bc.color IS NOT NULL)) AS cells,
            jsonb_object_agg((bc.article_id)::text, v.code) FILTER (WHERE (v.id IS NOT NULL)) AS cell_codes,
            string_agg(DISTINCT v.code, ', '::text) AS codes,
            (count(*) FILTER (WHERE (bc.is_used AND (bc.variant_id IS NULL) AND (ra.status = 'ACTIVE'::text))))::integer AS yellow
           FROM ((bom_cell bc
             LEFT JOIN material_variant v ON ((v.id = bc.variant_id)))
             LEFT JOIN revision_article ra ON (((ra.revision_id = l.revision_id) AND (ra.article_id = bc.article_id))))
          WHERE (bc.bom_line_id = l.id)) cc ON (true))
     LEFT JOIN bom_line u ON u.id = CASE WHEN l.replaces_line_key IS NOT NULL THEN fn_bom_undo_target(l.id) END
     LEFT JOIN material um ON um.id = u.material_id
  WHERE l.is_active;

-- ---------------------------------------------------------------- A1: tandai baris CBD tanpa biaya
CREATE OR REPLACE FUNCTION fn_cbd_set_no_charge(p_token text, p_line_id uuid, p_on boolean, p_reason text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_line_factory(p_line_id));
  v_line   cbd_line%ROWTYPE := fn_cbd_price_line(p_line_id);     -- draft + baris ACTIVE
  v_reason text := nullif(btrim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g')), '');
BEGIN
  IF coalesce(p_on, false) THEN
    IF v_reason IS NULL THEN
      RAISE EXCEPTION 'Isi alasan tanpa biaya (mis. "harga termasuk baris 10").';
    END IF;
    UPDATE cbd_line SET no_charge = true, no_charge_reason = left(v_reason, 200), updated_by = v_email WHERE id = v_line.id;
  ELSE
    UPDATE cbd_line SET no_charge = false, no_charge_reason = NULL, updated_by = v_email WHERE id = v_line.id;
  END IF;
  RETURN v_line.id;
END;
$$;

-- Isi harga quotation = baris dikenakan biaya lagi
CREATE OR REPLACE FUNCTION fn_cbd_set_quotation(p_token text, p_line_id uuid, p_price numeric, p_currency text,
                                                p_reference text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_line_factory(p_line_id));
  v_line  cbd_line%ROWTYPE := fn_cbd_price_line(p_line_id);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM material WHERE id = v_line.material_id AND price_method = 'QUOTATION') THEN
    RAISE EXCEPTION 'Harga quotation hanya untuk material dengan metode harga Quotation. Material katalog memakai harga master.';
  END IF;
  IF p_price IS NULL THEN
    UPDATE cbd_line SET price_original = NULL, currency = NULL, price_source = NULL, material_price_id = NULL,
                        price_override_reason = NULL, price_reference = NULL, updated_by = v_email
     WHERE id = v_line.id;
  ELSE
    PERFORM fn_cbd_check_price(p_price, p_currency);
    UPDATE cbd_line SET price_original = p_price, currency = p_currency, price_source = 'QUOTATION',
                        material_price_id = NULL, price_override_reason = NULL,
                        price_reference = nullif(btrim(coalesce(p_reference, '')), ''),
                        no_charge = false, no_charge_reason = NULL, updated_by = v_email
     WHERE id = v_line.id;
  END IF;
  RETURN v_line.id;
END;
$$;

-- Isi baris CBD dari specsheet (dipakai buat / revisi / copy / refresh). R11: tanda "tanpa biaya" ikut baris yang
-- cocok (bukan baris hasil Ganti material); replaces_line_key dicatat untuk rincian perubahan (A4).
CREATE OR REPLACE FUNCTION fn_cbd_populate(p_revision_id uuid, p_article_id uuid, p_spec_rev_id uuid, p_src cbd_line[],
                                           p_mark_missing boolean, p_ref text, p_email text, p_cross boolean DEFAULT false)
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
  v_nc      boolean;
  v_ncr     text;
  v_pid     uuid;
  v_price   numeric;
  v_cur     text;
BEGIN
  FOR e IN SELECT * FROM fn_cbd_expected_lines(p_article_id, p_spec_rev_id) ORDER BY seq LOOP
    v_found := false;
    v_yield := NULL; v_loss := NULL; v_origin := 'INPUT'; v_ref := NULL; v_carry := false; v_nc := false; v_ncr := NULL;
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
        v_nc := coalesce(s.no_charge, false); v_ncr := CASE WHEN v_nc THEN s.no_charge_reason END;
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
                            price_reference, status, value_origin, value_source_ref, sort_order, updated_by,
                            no_charge, no_charge_reason, replaces_line_key)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.thickness, e.color, e.variant_id, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              s.price_original, s.currency, s.price_source, NULL, NULL,
              s.price_reference, 'ACTIVE', v_origin, v_ref, v_sort, p_email,
              v_nc, v_ncr, e.replaces_line_key);
    ELSE
      v_pid := NULL; v_price := NULL; v_cur := NULL;
      IF e.supplier_id IS NOT NULL AND e.variant_id IS NOT NULL THEN
        SELECT price_id, price, currency INTO v_pid, v_price, v_cur
          FROM fn_price_lookup(e.variant_id, e.supplier_id);
      END IF;
      INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                            material_id, thickness, color, variant_id, supplier_id, uom, group_code, yield_value, loss_pct,
                            price_original, currency, price_source, material_price_id,
                            status, value_origin, value_source_ref, sort_order, updated_by,
                            no_charge, no_charge_reason, replaces_line_key)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.thickness, e.color, e.variant_id, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              v_price, v_cur, CASE WHEN v_pid IS NOT NULL THEN 'MASTER' END, v_pid,
              'ACTIVE', v_origin, v_ref, v_sort, p_email,
              v_nc, v_ncr, e.replaces_line_key);
    END IF;
    v_sort := v_sort + 1;
  END LOOP;

  IF p_mark_missing AND v_has_src THEN
    INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                          material_id, thickness, color, variant_id, supplier_id, uom, group_code, yield_value, loss_pct,
                          price_original, currency, price_source, material_price_id, price_override_reason,
                          price_reference, status, value_origin, value_source_ref, sort_order, updated_by,
                          no_charge, no_charge_reason, replaces_line_key)
    SELECT p_revision_id, x.line_key, x.component_id, x.local_component_no, x.sub_seq, x.sub_name,
           x.material_id, x.thickness, x.color, x.variant_id, x.supplier_id, x.uom, x.group_code, x.yield_value, x.loss_pct,
           x.price_original, x.currency, x.price_source, x.material_price_id, x.price_override_reason,
           x.price_reference, 'MISSING_IN_SPEC', x.value_origin, x.value_source_ref,
           v_sort + (row_number() OVER (ORDER BY x.sort_order))::integer, p_email,
           coalesce(x.no_charge, false), CASE WHEN x.no_charge THEN x.no_charge_reason END, x.replaces_line_key
      FROM unnest(p_src) x
     WHERE NOT (x.line_key = ANY (v_matched));
  END IF;
  RETURN v_sort;
END;
$$;

-- ---------------------------------------------------------------- A4: rincian perubahan CBD (cost bridge)
-- Revisi terbit sebelumnya dari article yang sama (untuk draft: terbit terakhir; untuk revisi terbit: sebelum dia).
-- Urutan = stage lalu nomor revisi (revisi CBD baru selalu lebih tinggi; sama dengan "terbit terakhir" di fn_cbd_create).
CREATE OR REPLACE FUNCTION fn_cbd_prev_published(p_rev uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT o.id
    FROM cbd_revision c
    JOIN cbd_revision o ON o.article_id = c.article_id AND o.status = 'PUBLISHED' AND o.id <> c.id
   WHERE c.id = p_rev
     AND (c.status = 'DRAFT' OR (o.stage_order, o.revision_no) < (c.stage_order, c.revision_no))
   ORDER BY o.stage_order DESC, o.revision_no DESC
   LIMIT 1
$$;

-- Selisih Actual FOB revisi p_rev vs revisi terbit sebelumnya, dipecah per pemicu. Untuk setiap baris yang cocok
-- (line_key sama, atau baris pengganti lewat replaces_line_key):
--   Exchange rate = Usage×(1+Loss) lama × harga USD lama × (kurs baru − kurs lama)   (digabung jadi satu baris)
--   Material      = Usage×(1+Loss) lama × (harga baru − harga lama) pada kurs baru  (atau ganti material / kode)
--   Yield / Loss  = (Usage×(1+Loss) baru − lama) × harga baru
-- Baris baru / hilang = Komponen; baris biaya: LABOUR = LOP, AMORTIZATION = Amortisasi, lainnya = Lainnya.
-- Jumlah semua baris = Actual FOB baru − Actual FOB lama (persis; dicek lagi di fn_cbd_publish).
CREATE OR REPLACE FUNCTION fn_cbd_bridge(p_rev uuid)
RETURNS TABLE (seq integer, key text, category text, description text, amount numeric)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
  v_prev  uuid := fn_cbd_prev_published(p_rev);
  v_rc    numeric;
  v_rp    numeric;
  v_rate  numeric := 0;
  v_n     integer := 0;
  v_used  uuid[] := '{}';
  c       record;
  p       record;
  it      record;
  v_okc   boolean;
  v_okp   boolean;
  v_ufc   numeric;
  v_ufp   numeric;
  v_costc numeric;
  v_costp numeric;
  v_pe    numeric;
  v_ye    numeric;
  v_re    numeric;
  v_lbl   text;
  v_parts text[];
  v_out   jsonb := '[]';
BEGIN
  IF v_prev IS NULL THEN
    RETURN;
  END IF;
  SELECT exchange_rate INTO v_rc FROM cbd_revision WHERE id = p_rev;
  SELECT exchange_rate INTO v_rp FROM cbd_revision WHERE id = v_prev;

  FOR c IN SELECT * FROM v_cbd_line WHERE cbd_revision_id = p_rev AND status = 'ACTIVE' ORDER BY group_sort, sort_order LOOP
    SELECT * INTO p FROM v_cbd_line
     WHERE cbd_revision_id = v_prev AND status = 'ACTIVE' AND NOT (id = ANY (v_used)) AND line_key = c.line_key LIMIT 1;
    IF NOT FOUND AND c.replaces_line_key IS NOT NULL THEN
      SELECT * INTO p FROM v_cbd_line
       WHERE cbd_revision_id = v_prev AND status = 'ACTIVE' AND NOT (id = ANY (v_used)) AND line_key = c.replaces_line_key LIMIT 1;
    END IF;
    IF p.id IS NULL THEN          -- sama dengan fn_cbd_populate: komponen + material + thickness (+ sub) sama
      SELECT v.* INTO p
        FROM v_cbd_line v
        JOIN cbd_line x ON x.id = v.id
        JOIN cbd_line y ON y.id = c.id
       WHERE v.cbd_revision_id = v_prev AND v.status = 'ACTIVE' AND NOT (v.id = ANY (v_used))
         AND fn_cbd_identity(x.component_id, x.local_component_no, x.sub_seq, x.sub_name, x.material_id, x.thickness)
           = fn_cbd_identity(y.component_id, y.local_component_no, y.sub_seq, y.sub_name, y.material_id, y.thickness)
       ORDER BY v.sort_order LIMIT 1;
    END IF;
    v_lbl := btrim(concat_ws(' ', c.display_no, c.display_name));
    v_costc := coalesce(c.cost_per_pair, 0);
    IF p.id IS NULL THEN
      IF v_costc <> 0 THEN
        v_out := v_out || jsonb_build_object('key', 'L:' || c.line_key || ':ADD', 'category', 'COMPONENT', 'amount', v_costc,
                   'description', '+ ' || v_lbl || ' · ' || c.material_name || coalesce(' ' || c.thickness, ''));
      END IF;
      CONTINUE;
    END IF;
    v_used := v_used || p.id;
    v_costp := coalesce(p.cost_per_pair, 0);
    v_okc := NOT c.no_charge AND c.usage_value IS NOT NULL AND c.price_original IS NOT NULL AND c.price_idr IS NOT NULL;
    v_okp := NOT p.no_charge AND p.usage_value IS NOT NULL AND p.price_original IS NOT NULL AND p.price_idr IS NOT NULL;
    v_re := 0;
    IF v_okc AND v_okp AND c.currency = 'USD' AND p.currency = 'USD' THEN
      v_ufp := p.usage_value * (1 + coalesce(p.loss_pct, 0) / 100);
      v_re := v_ufp * p.price_original * (v_rc - v_rp);
      v_rate := v_rate + v_re;
    END IF;
    IF v_okc AND v_okp AND c.material_id = p.material_id AND c.variant_id IS NOT DISTINCT FROM p.variant_id THEN
      v_ufc := c.usage_value * (1 + coalesce(c.loss_pct, 0) / 100);
      v_ufp := p.usage_value * (1 + coalesce(p.loss_pct, 0) / 100);
      v_pe := CASE WHEN c.currency = 'USD' AND p.currency = 'USD' THEN v_ufp * (c.price_original - p.price_original) * v_rc
                   ELSE v_ufp * (c.price_idr - p.price_idr) END;
      v_ye := (v_ufc - v_ufp) * c.price_idr;
      IF v_pe <> 0 THEN
        v_out := v_out || jsonb_build_object('key', 'L:' || c.line_key || ':PRICE', 'category', 'MATERIAL', 'amount', v_pe,
                   'description', v_lbl || ' · ' || c.material_name || ': harga ' || fn_fmt_id(p.price_original, 4) || ' '
                                  || p.currency || ' → ' || fn_fmt_id(c.price_original, 4) || ' ' || c.currency);
      END IF;
      IF v_ye <> 0 THEN
        v_parts := '{}';
        IF c.yield_value IS DISTINCT FROM p.yield_value THEN
          v_parts := v_parts || ('yield ' || fn_fmt_id(p.yield_value, 6) || ' → ' || fn_fmt_id(c.yield_value, 6));
        END IF;
        IF coalesce(c.loss_pct, 0) <> coalesce(p.loss_pct, 0) THEN
          v_parts := v_parts || ('loss ' || fn_fmt_id(coalesce(p.loss_pct, 0), 2) || '% → ' || fn_fmt_id(coalesce(c.loss_pct, 0), 2) || '%');
        END IF;
        v_out := v_out || jsonb_build_object('key', 'L:' || c.line_key || ':YIELD', 'category', 'YIELD', 'amount', v_ye,
                   'description', v_lbl || ' · ' || c.material_name || ': '
                                  || coalesce(nullif(array_to_string(v_parts, ', '), ''), 'usage berubah'));
      END IF;
    ELSIF v_costc - v_costp - v_re <> 0 THEN
      v_out := v_out || jsonb_build_object('key', 'L:' || c.line_key || ':MAT', 'category', 'MATERIAL',
                 'amount', v_costc - v_costp - v_re,
                 'description', v_lbl || ': ' ||
                   CASE WHEN c.no_charge AND NOT p.no_charge THEN 'dijadikan tanpa biaya (' || c.no_charge_reason || ')'
                        WHEN p.no_charge AND NOT c.no_charge THEN 'tidak lagi tanpa biaya'
                        WHEN c.material_id <> p.material_id OR c.variant_id IS DISTINCT FROM p.variant_id
                          THEN 'ganti material ' || p.material_name || coalesce(' [' || p.material_code || ']', '') || ' → '
                               || c.material_name || coalesce(' [' || c.material_code || ']', '')
                        ELSE 'biaya ' || fn_fmt_id(v_costp, 2) || ' → ' || fn_fmt_id(v_costc, 2) END);
    END IF;
  END LOOP;

  -- baris lama yang tidak ada lagi
  FOR p IN SELECT * FROM v_cbd_line WHERE cbd_revision_id = v_prev AND status = 'ACTIVE' AND NOT (id = ANY (v_used))
           ORDER BY group_sort, sort_order LOOP
    IF coalesce(p.cost_per_pair, 0) <> 0 THEN
      v_out := v_out || jsonb_build_object('key', 'L:' || p.line_key || ':DEL', 'category', 'COMPONENT', 'amount', -p.cost_per_pair,
                 'description', '− ' || btrim(concat_ws(' ', p.display_no, p.display_name)) || ' · ' || p.material_name
                                || coalesce(' ' || p.thickness, ''));
    END IF;
  END LOOP;

  IF v_rate <> 0 THEN
    v_out := jsonb_build_object('key', 'RATE', 'category', 'EX_RATE', 'amount', v_rate,
               'description', 'Exchange rate ' || fn_fmt_id(v_rp, 4) || ' → ' || fn_fmt_id(v_rc, 4)) || v_out;
  END IF;

  -- baris biaya (cocok per jenis + nama)
  FOR it IN
    SELECT coalesce(a.item_type, b.item_type) AS item_type, coalesce(a.name, b.name) AS name,
           coalesce(a.amount, 0) AS amt_c, coalesce(b.amount, 0) AS amt_p, a.name IS NOT NULL AS in_c, b.name IS NOT NULL AS in_p
      FROM (SELECT item_type, fn_normalize(name) AS k, min(name) AS name, sum(amount) AS amount, min(sort_order) AS so
              FROM cbd_cost_item WHERE cbd_revision_id = p_rev GROUP BY 1, 2) a
      FULL JOIN (SELECT item_type, fn_normalize(name) AS k, min(name) AS name, sum(amount) AS amount, min(sort_order) AS so
                   FROM cbd_cost_item WHERE cbd_revision_id = v_prev GROUP BY 1, 2) b
        ON b.item_type = a.item_type AND b.k = a.k
     ORDER BY fn_change_category_sort(CASE coalesce(a.item_type, b.item_type) WHEN 'LABOUR' THEN 'LOP'
                                       WHEN 'AMORTIZATION' THEN 'AMORTIZATION' ELSE 'OTHER' END),
              coalesce(a.so, b.so), coalesce(a.name, b.name)
  LOOP
    IF it.amt_c - it.amt_p <> 0 THEN
      v_out := v_out || jsonb_build_object('key', 'I:' || it.item_type || ':' || fn_normalize(it.name),
                 'category', CASE it.item_type WHEN 'LABOUR' THEN 'LOP' WHEN 'AMORTIZATION' THEN 'AMORTIZATION' ELSE 'OTHER' END,
                 'amount', it.amt_c - it.amt_p,
                 'description', CASE WHEN NOT it.in_p THEN '+ ' || it.name || ' ' || fn_fmt_id(it.amt_c, 2)
                                     WHEN NOT it.in_c THEN '− ' || it.name || ' ' || fn_fmt_id(it.amt_p, 2)
                                     ELSE it.name || ' ' || fn_fmt_id(it.amt_p, 2) || ' → ' || fn_fmt_id(it.amt_c, 2) END);
    END IF;
  END LOOP;

  RETURN QUERY
    SELECT (row_number() OVER (ORDER BY fn_change_category_sort(x ->> 'category'), o.ord))::integer,
           x ->> 'key', x ->> 'category', x ->> 'description', (x ->> 'amount')::numeric
      FROM jsonb_array_elements(v_out) WITH ORDINALITY AS o(x, ord)
     ORDER BY 1;
END;
$$;

-- Rincian perubahan untuk app (form terbit, riwayat, export). Revisi terbit: dari change_log.diff (yang tersimpan saat
-- terbit, termasuk kategori / uraian yang diubah vendor). Draft: dihitung langsung.
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
           v_prev.stage || ' r' || v_prev.revision_no,
           (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = v_prev.id),
           (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = p_rev)
      FROM fn_cbd_bridge(p_rev) b
     ORDER BY b.seq;
END;
$$;

-- ---------------------------------------------------------------- terbit CBD (T56/A1 + A4)
-- p_bridge (opsional): [{key, category, description}] — kategori & uraian yang diubah vendor di form terbit;
-- nilai selalu dihitung ulang di sini. Ada rincian -> kategori change log = kategori nilai terbesar, alasan opsional
-- (kosong = ringkasan per kategori). Tanpa rincian (revisi awal / tidak ada selisih) -> kategori & alasan seperti dulu.
DROP FUNCTION IF EXISTS fn_cbd_publish(text, uuid, text, text);
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
  c_cats     text[] := ARRAY['EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER'];
BEGIN
  SELECT * INTO v_chk FROM v_cbd_checklist WHERE cbd_revision_id = v_rev.id;
  IF v_chk.spec_stale THEN
    RAISE EXCEPTION 'Specsheet acuan CBD ini sudah diterbitkan revisi baru. Klik "Refresh dari Specsheet" dulu.';
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

COMMIT;

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'R11 terpasang' AS cek,
       'tanpa biaya: ' || (to_regprocedure('fn_cbd_set_no_charge(text,uuid,boolean,text)') IS NOT NULL)::text
       || ' · rincian perubahan: ' || (to_regprocedure('fn_cbd_bridge_view(text,uuid)') IS NOT NULL)::text
       || ' · terbit CBD 5 argumen: ' || (to_regprocedure('fn_cbd_publish(text,uuid,text,text,jsonb)') IS NOT NULL)::text
       || ' · index varian CBD: ' || (to_regclass('idx_cbd_line_variant') IS NOT NULL)::text AS hasil;
