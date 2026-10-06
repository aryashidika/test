-- ============================================================================
-- F10c — Batalkan kolom Width material dari F10b (koreksi user 6 Okt 2026:
-- yang dimaksud di specsheet & CBD adalah THICKNESS, bukan width).
-- Jalankan SETELAH F10b, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
--
--  - Kolom material.width & width_key dihapus; identitas material kembali nama + thickness + UoM.
--  - fn_material_add / fn_material_update kembali ke parameter F3 (tanpa p_width).
--  - v_material_list, v_bom_grid, v_cbd_line dibuat ulang tanpa width (supplier_status di v_bom_grid tetap).
--    View lain yang bergantung pada ketiganya (v_cbd_recap, v_cbd_checklist, worklist, dst.) disimpan
--    definisinya lalu dibuat ulang otomatis apa adanya.
-- ============================================================================

SELECT set_config('app.user', 'migrasi F10c', true);

-- ---------------------------------------------------------------- 0. Cek
DO $$
DECLARE
  v_dup text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'material' AND column_name = 'width') THEN
    RAISE NOTICE 'Kolom material.width tidak ada (F10c sudah dijalankan / F10b versi baru). Lanjut tanpa perubahan kolom.';
  END IF;
  SELECT string_agg(x.items, ' | ') INTO v_dup
    FROM (SELECT string_agg(material_code, ', ' ORDER BY material_code) AS items
            FROM material GROUP BY name_key, thickness_key, uom HAVING count(*) > 1) x;
  IF v_dup IS NOT NULL THEN
    RAISE EXCEPTION 'Ada material yang hanya beda Width: %. Ubah nama/thickness salah satunya (atau INACTIVE + ganti nama) dulu.', v_dup;
  END IF;
END;
$$;

-- ---------------------------------------------------------------- 1. Simpan definisi view turunan
DROP TABLE IF EXISTS _f10c_views;
CREATE TEMP TABLE _f10c_views AS
WITH RECURSIVE dep(oid, lvl) AS (
  SELECT c.oid, 0
    FROM pg_class c
   WHERE c.oid IN (to_regclass('public.v_material_list'), to_regclass('public.v_bom_grid'), to_regclass('public.v_cbd_line'))
  UNION ALL
  SELECT rw.ev_class, dep.lvl + 1
    FROM dep
    JOIN pg_depend d ON d.refobjid = dep.oid AND d.refclassid = 'pg_class'::regclass AND d.classid = 'pg_rewrite'::regclass
    JOIN pg_rewrite rw ON rw.oid = d.objid
   WHERE rw.ev_class <> dep.oid
)
SELECT dep.oid::regclass::text AS view_name, max(dep.lvl) AS lvl, c.relkind,
       pg_get_viewdef(dep.oid, true) AS def
  FROM dep JOIN pg_class c ON c.oid = dep.oid
 GROUP BY dep.oid, c.relkind;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM _f10c_views WHERE relkind <> 'v') THEN
    RAISE EXCEPTION 'Ada objek non-view yang bergantung pada view material/BOM/CBD: %. Hentikan dan hubungi pengembang.',
      (SELECT string_agg(view_name, ', ') FROM _f10c_views WHERE relkind <> 'v');
  END IF;
END;
$$;

DROP VIEW IF EXISTS v_material_list, v_bom_grid, v_cbd_line CASCADE;

-- ---------------------------------------------------------------- 2. Kolom width dihapus
ALTER TABLE material DROP CONSTRAINT IF EXISTS uq_material_identity;
ALTER TABLE material DROP COLUMN IF EXISTS width_key;
ALTER TABLE material DROP COLUMN IF EXISTS width;
ALTER TABLE material ADD CONSTRAINT uq_material_identity UNIQUE (name_key, thickness_key, uom);

-- Normalisasi + identitas (huruf kapital nama & kategori dari F10b tetap)
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

-- ---------------------------------------------------------------- 3. Fungsi material kembali ke F3
DROP FUNCTION IF EXISTS fn_material_add(text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION fn_material_add(
  p_token text, p_code text, p_name text, p_category text, p_thickness text, p_uom text, p_price_method text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_any(p_token, ARRAY['manage_master', 'propose_master']);
  v_id    uuid;
BEGIN
  INSERT INTO material (material_code, name, category, thickness, uom, price_method, status, updated_by)
  VALUES (p_code, p_name, p_category, p_thickness, p_uom, coalesce(nullif(p_price_method, ''), 'CATALOG'),
          CASE WHEN fn_has_perm(v_email, 'manage_master') THEN 'APPROVED' ELSE 'PROPOSED' END, v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

DROP FUNCTION IF EXISTS fn_material_update(text, uuid, text, text, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION fn_material_update(
  p_token text, p_id uuid, p_code text, p_name text, p_category text, p_thickness text, p_uom text,
  p_status text, p_price_method text
) RETURNS uuid
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
  IF NOT v_master AND (
       fn_normalize(p_code) IS DISTINCT FROM fn_normalize(v_old.material_code)
    OR fn_normalize(p_name) IS DISTINCT FROM v_old.name_key
    OR fn_normalize(p_category) IS DISTINCT FROM fn_normalize(v_old.category)
    OR fn_normalize(p_thickness) IS DISTINCT FROM v_old.thickness_key
    OR fn_normalize(p_uom) IS DISTINCT FROM fn_normalize(v_old.uom)
    OR p_status IS DISTINCT FROM v_old.status) THEN
    RAISE EXCEPTION 'Hanya Master Admin yang bisa mengubah data dan status material.';
  END IF;
  IF NOT v_price AND p_price_method IS DISTINCT FROM v_old.price_method THEN
    RAISE EXCEPTION 'Metode harga hanya bisa diubah oleh tim CBD atau Master Admin.';
  END IF;
  UPDATE material
     SET material_code = CASE WHEN v_master THEN p_code      ELSE material_code END,
         name          = CASE WHEN v_master THEN p_name      ELSE name END,
         category      = CASE WHEN v_master THEN p_category  ELSE category END,
         thickness     = CASE WHEN v_master THEN p_thickness ELSE thickness END,
         uom           = CASE WHEN v_master THEN p_uom       ELSE uom END,
         status        = CASE WHEN v_master THEN p_status    ELSE status END,
         price_method  = CASE WHEN v_price  THEN p_price_method ELSE price_method END,
         updated_by    = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- ---------------------------------------------------------------- 4. View dasar tanpa width
CREATE VIEW v_material_list AS
SELECT m.id, m.material_code, m.name, m.name_key, m.category, m.thickness, m.uom, m.price_method, m.status,
       m.updated_at, m.updated_by,
       coalesce(s.suppliers, 0) AS supplier_count,
       coalesce(s.proposed, 0)  AS proposed_links,
       coalesce(s.priced, 0)    AS priced_links,
       s.preferred_supplier,
       (m.price_method = 'CATALOG' AND coalesce(s.suppliers, 0) > coalesce(s.priced, 0)) AS missing_price,
       (SELECT count(*) FROM material_price mp JOIN material_supplier ms ON ms.id = mp.material_supplier_id
         WHERE ms.material_id = m.id AND mp.status = 'PROPOSED') AS pending_prices
  FROM material m
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE ms.status <> 'INACTIVE') AS suppliers,
           count(*) FILTER (WHERE ms.status = 'PROPOSED')  AS proposed,
           count(*) FILTER (WHERE ms.status <> 'INACTIVE' AND EXISTS (
             SELECT 1 FROM material_price mp
              WHERE mp.material_supplier_id = ms.id AND mp.status = 'APPROVED'
                AND mp.valid_from <= fn_today() AND (mp.valid_to IS NULL OR mp.valid_to > fn_today()))) AS priced,
           max(sp.name) FILTER (WHERE ms.is_preferred) AS preferred_supplier
      FROM material_supplier ms JOIN supplier sp ON sp.id = ms.supplier_id
     WHERE ms.material_id = m.id
  ) s ON true;

-- Grid BOM: supplier_status (F10b) tetap
CREATE VIEW v_bom_grid AS
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

-- Baris CBD: loss kosong dihitung 0 % (F10b) tetap
CREATE VIEW v_cbd_line AS
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

-- ---------------------------------------------------------------- 5. View turunan dibuat ulang apa adanya
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT view_name, def FROM _f10c_views WHERE lvl > 0 ORDER BY lvl, view_name LOOP
    EXECUTE format('CREATE VIEW %s AS %s', r.view_name, r.def);
  END LOOP;
END;
$$;

DROP TABLE _f10c_views;

-- ---------------------------------------------------------------- Cek hasil (harus: 0 · 0 · semua view ada)
SELECT (SELECT count(*) FROM information_schema.columns
         WHERE table_name = 'material' AND column_name IN ('width', 'width_key')) AS kolom_width,
       (SELECT count(*) FROM pg_proc WHERE proname IN ('fn_material_add', 'fn_material_update')
           AND pronargs IN (8, 10)) AS fungsi_lama,
       (SELECT pronargs FROM pg_proc WHERE proname = 'fn_material_add') AS arg_add,
       (SELECT pronargs FROM pg_proc WHERE proname = 'fn_material_update') AS arg_update,
       to_regclass('v_cbd_recap') IS NOT NULL AND to_regclass('v_cbd_checklist') IS NOT NULL
         AND to_regclass('v_worklist_cbd') IS NOT NULL AND to_regclass('v_bom_grid') IS NOT NULL AS view_ok;
