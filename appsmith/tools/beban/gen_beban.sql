-- Generator data sintetis untuk uji beban (JANGAN dijalankan di DB produksi/uji user).
-- Dipakai oleh ukur_beban.py di DB kosong yang sudah berisi skema F1 → R10.
-- Insert langsung ke tabel (trigger & FK dimatikan lewat session_replication_role = replica),
-- lalu audit_log diisi massal supaya ukurannya mirip pemakaian nyata.
--
-- Asumsi volume (satu pabrik):
--   master : 150 supplier, 110 komponen, 450 material induk, 3–12 varian per material (~3.400 varian),
--            1–3 supplier per material, 1 harga APPROVED per varian × supplier per tahun (3% sengaja tanpa harga)
--   season : 2 per tahun (SS, FH); 200 model per season (150 lanjut dari season sebelumnya + 50 baru)
--            4 article per specsheet; revisi terbit PULL r0, SMS r0, SMS r1, GTM r0, PROD r0
--            BOM 60 baris (55 utama + 5 sub) × 4 sel article
--            CBD per article: PULL, SMS, GTM, PROD terbit; 60 baris + 3 biaya default
--   aktivitas season terakhir : 20% specsheet punya draft, 30% article punya draft CBD,
--            5% varian dapat harga baru (draft CBD jadi TO_REFRESH), 1% harga PROPOSED, 3 article belum masuk revisi
--   audit  : 1 baris per insert + ±0,5 per sel/baris CBD (anggap diedit sekali)

SET session_replication_role = replica;

CREATE OR REPLACE FUNCTION beban_setup() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  f uuid := '00000000-0000-0000-0000-0000000000f1';
BEGIN
  SET LOCAL session_replication_role = replica;
  PERFORM setseed(0.42);
  INSERT INTO factory (id, name, created_by, updated_by) VALUES (f, 'PABRIK BEBAN', 'gen', 'gen');

  INSERT INTO app_user (email, full_name, role, factory_id, must_change_password, created_by, updated_by) VALUES
    ('spec@beban.test', 'Spec', 'VENDOR_SPEC', f, false, 'gen', 'gen'),
    ('cbd@beban.test', 'Cbd', 'VENDOR_CBD', f, false, 'gen', 'gen'),
    ('mc@beban.test', 'Manager Costing', 'MANAGER_COSTING', f, false, 'gen', 'gen'),
    ('brand@beban.test', 'Brand', 'BRAND_VIEWER', NULL, false, 'gen', 'gen'),
    ('admin@beban.test', 'Admin', 'SYSTEM_ADMIN', NULL, false, 'gen', 'gen');
  -- token = 'tok-' || bagian depan email
  INSERT INTO app_session (token_hash, email, expires_at)
  SELECT fn_token_hash('tok-' || split_part(email, '@', 1)), email, now() + interval '30 days'
    FROM app_user WHERE email LIKE '%@beban.test';

  INSERT INTO model_option (kind, factory_id, value, sort_order, created_by, updated_by)
  SELECT k, CASE WHEN k IN ('LAST', 'OUTSOLE_MOLD') THEN f END, k || ' ' || i, i, 'gen', 'gen'
    FROM (VALUES ('KATEGORI', 10), ('CONSTRUCTION', 5), ('GENDER', 3), ('LAST', 50), ('OUTSOLE_MOLD', 80)) o(k, n),
         generate_series(1, n) i;

  INSERT INTO supplier (name, created_by, updated_by)
  SELECT 'SUPPLIER ' || lpad(i::text, 3, '0'), 'gen', 'gen' FROM generate_series(1, 150) i;

  INSERT INTO component (number, name, group_code, created_by, updated_by)
  SELECT g.range_start + i * 10, 'KOMPONEN ' || g.code || i, g.code, 'gen', 'gen'
    FROM component_group g
    JOIN (VALUES ('a', 60), ('b', 25), ('c', 15), ('d', 10)) n(code, cnt) ON n.code = g.code
    CROSS JOIN LATERAL generate_series(1, n.cnt) i;

  INSERT INTO material (name, category, uom, price_method, factory_id, created_by, updated_by)
  SELECT 'MATERIAL ' || lpad(i::text, 3, '0'),
         (ARRAY['LEATHER','SYNTHETIC','MESH','FOAM','RUBBER','THREAD','LACE','PACKAGING'])[1 + i % 8],
         (ARRAY['M','YD','PRS','PCS','KG'])[1 + i % 5],
         CASE WHEN i % 10 = 0 THEN 'QUOTATION' ELSE 'CATALOG' END, f, 'gen', 'gen'
    FROM generate_series(1, 450) i;

  -- tabel bantu (UNLOGGED, dipakai fungsi season)
  CREATE UNLOGGED TABLE g_mat AS
  SELECT row_number() OVER (ORDER BY name) - 1 AS rn, id, uom FROM material;
  CREATE UNLOGGED TABLE g_sup AS
  SELECT row_number() OVER (ORDER BY name) - 1 AS rn, id FROM supplier;
  CREATE UNLOGGED TABLE g_comp AS
  SELECT row_number() OVER (ORDER BY number) - 1 AS rn, id, group_code FROM component;

  INSERT INTO material_variant (material_id, factory_id, color, code, thickness, created_by, updated_by)
  SELECT m.id, f, 'COLOR ' || j,
         'M' || lpad(upper(to_hex(m.rn::int)), 3, '0') || t.code || 'C' || lpad(j::text, 2, '0'),
         t.label, 'gen', 'gen'
    FROM g_mat m
    CROSS JOIN LATERAL generate_series(1, 3 + (m.rn * 7 % 10)::int) j
    CROSS JOIN LATERAL (SELECT (ARRAY['000','008','010','012'])[1 + (m.rn % 4)::int] AS code,
                               (ARRAY[NULL,'0.8MM','1.0MM','1.2MM'])[1 + (m.rn % 4)::int] AS label) t;

  INSERT INTO material_supplier (material_id, supplier_id, is_preferred, created_by, updated_by)
  SELECT m.id, s.id, k = 0, 'gen', 'gen'
    FROM g_mat m
    CROSS JOIN LATERAL generate_series(0, (m.rn % 3)::int) k
    JOIN g_sup s ON s.rn = (m.rn * 11 + k * 37) % 150;

  CREATE UNLOGGED TABLE g_var AS
  SELECT v.material_id, row_number() OVER (PARTITION BY v.material_id ORDER BY v.code) - 1 AS rn,
         count(*) OVER (PARTITION BY v.material_id) AS cnt, v.id, v.color, v.thickness
    FROM material_variant v;
  CREATE INDEX g_var_idx ON g_var (material_id, rn);
  ANALYZE g_mat; ANALYZE g_sup; ANALYZE g_comp; ANALYZE g_var;
END $$;

-- Harga tahunan: tutup harga terbuka, buka harga baru per varian × supplier (3% tanpa harga sama sekali)
CREATE OR REPLACE FUNCTION beban_prices(p_year int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE d date := make_date(p_year, 1, 1);
BEGIN
  SET LOCAL session_replication_role = replica;
  -- harga aktivitas (beban_activity) bertanggal hari ini: buang dulu supaya tahun lama bisa digulirkan
  DELETE FROM material_price WHERE status = 'PROPOSED' OR reference = 'BARU';
  UPDATE material_price SET valid_to = NULL WHERE valid_to = fn_today() - 10;
  UPDATE material_price SET valid_to = d WHERE status = 'APPROVED' AND valid_to IS NULL;
  INSERT INTO material_price (material_supplier_id, variant_id, price, currency, valid_from, status, reference,
                              created_at, created_by, updated_by, decided_by, decided_at)
  SELECT ms.id, v.id, round((1 + random() * 20)::numeric, 2), 'USD', d, 'APPROVED', 'Q' || p_year,
         d, 'cbd@beban.test', 'cbd@beban.test', 'mc@beban.test', d
    FROM material_supplier ms
    JOIN material m ON m.id = ms.material_id AND m.price_method = 'CATALOG'
    JOIN material_variant v ON v.material_id = ms.material_id
   WHERE abs(hashtext(v.id::text || ms.id::text)) % 100 >= 3;
END $$;

-- Satu season penuh (semua terbit). p_k = urutan season (0, 1, 2, ...)
CREATE OR REPLACE FUNCTION beban_season(p_season text, p_k int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  f   uuid := '00000000-0000-0000-0000-0000000000f1';
  ts  timestamptz := make_date(2000 + substr(p_season, 3, 2)::int, CASE WHEN p_season LIKE 'SS%' THEN 2 ELSE 8 END, 1);
  ncomp int := (SELECT count(*) FROM component);
BEGIN
  SET LOCAL session_replication_role = replica;
  -- model: nomor 50k+1 .. 50k+200 (150 lanjut + 50 baru)
  INSERT INTO product_model (name, factory_id, category_id, construction_id, gender_id, last_id, outsole_mold_id,
                             sizes, sample_size, created_at, created_by, updated_by)
  SELECT 'MODEL ' || lpad(n::text, 4, '0'), f,
         (SELECT id FROM model_option WHERE kind = 'KATEGORI' ORDER BY value LIMIT 1 OFFSET n % 10),
         (SELECT id FROM model_option WHERE kind = 'CONSTRUCTION' ORDER BY value LIMIT 1 OFFSET n % 5),
         (SELECT id FROM model_option WHERE kind = 'GENDER' ORDER BY value LIMIT 1 OFFSET n % 3),
         (SELECT id FROM model_option WHERE kind = 'LAST' ORDER BY value LIMIT 1 OFFSET n % 50),
         (SELECT id FROM model_option WHERE kind = 'OUTSOLE_MOLD' ORDER BY value LIMIT 1 OFFSET n % 80),
         '{36,37,38,39,40,41,42,43,44,45}', 40, ts, 'spec@beban.test', 'spec@beban.test'
    FROM generate_series(50 * p_k + 1, 50 * p_k + 200) n
   WHERE NOT EXISTS (SELECT 1 FROM product_model WHERE name = 'MODEL ' || lpad(n::text, 4, '0'));

  CREATE TEMP TABLE s_sh ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, pm.id AS model_id, substr(pm.name, 7)::int AS n
    FROM product_model pm
   WHERE substr(pm.name, 7)::int BETWEEN 50 * p_k + 1 AND 50 * p_k + 200;
  INSERT INTO specsheet (id, model_id, season, created_at, created_by, updated_by)
  SELECT id, model_id, p_season, ts, 'spec@beban.test', 'spec@beban.test' FROM s_sh;

  CREATE TEMP TABLE s_art ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, s.id AS specsheet_id, s.n, j AS aj
    FROM s_sh s CROSS JOIN generate_series(0, 3) j;
  INSERT INTO article (id, specsheet_id, code, colorway, created_at, created_by, updated_by)
  SELECT a.id, a.specsheet_id, p_season || '-' || lpad(a.n::text, 4, '0') || '-' || (a.aj + 1), 'COLORWAY ' || (a.aj + 1),
         ts, 'spec@beban.test', 'spec@beban.test'
    FROM s_art a;

  CREATE TEMP TABLE s_rev ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, s.id AS specsheet_id, s.n, st.stage, st.no, st.ord
    FROM s_sh s
    CROSS JOIN (VALUES ('PULL', 0, 1), ('SMS', 0, 2), ('SMS', 1, 3), ('GTM', 0, 4), ('PROD', 0, 5)) st(stage, no, ord);
  INSERT INTO specsheet_revision (id, specsheet_id, stage, revision_no, status, published_at, published_by,
                                  created_at, created_by, updated_by)
  SELECT id, specsheet_id, stage, no, 'PUBLISHED', ts + ord * interval '10 days', 'spec@beban.test',
         ts + ord * interval '10 days', 'spec@beban.test', 'spec@beban.test'
    FROM s_rev;
  INSERT INTO revision_article (revision_id, article_id, status, created_at, created_by, updated_by)
  SELECT r.id, a.id, 'ACTIVE', ts, 'spec@beban.test', 'spec@beban.test'
    FROM s_rev r JOIN s_art a ON a.specsheet_id = r.specsheet_id;

  -- BOM: 55 baris utama + 5 sub; line_key sama di semua revisi satu specsheet
  CREATE TEMP TABLE s_line ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, r.id AS revision_id, r.specsheet_id, r.n, i,
         md5(r.specsheet_id::text || i)::uuid AS line_key,
         CASE WHEN i > 55 THEN md5(r.specsheet_id::text || (i - 55))::uuid END AS parent_line_key,
         m.id AS material_id, m.uom
    FROM s_rev r
    CROSS JOIN generate_series(1, 60) i
    JOIN g_mat m ON m.rn = (r.n * 13 + i * 7) % 450;
  INSERT INTO bom_line (id, revision_id, line_key, component_id, parent_line_key, sub_seq, sub_name, material_id,
                        supplier_id, thickness, is_active, sort_order, created_at, created_by, updated_by)
  SELECT l.id, l.revision_id, l.line_key,
         CASE WHEN l.i <= 55 THEN (SELECT c.id FROM g_comp c WHERE c.rn = (l.n * 7 + l.i) % ncomp) END,
         l.parent_line_key, CASE WHEN l.i > 55 THEN 1 END, CASE WHEN l.i > 55 THEN 'SUB ' || l.i END,
         l.material_id,
         (SELECT ms.supplier_id FROM material_supplier ms WHERE ms.material_id = l.material_id AND ms.is_preferred),
         (SELECT v.thickness FROM g_var v WHERE v.material_id = l.material_id AND v.rn = 0),
         true, l.i, ts, 'spec@beban.test', 'spec@beban.test'
    FROM s_line l;

  CREATE TEMP TABLE s_cell ON COMMIT DROP AS
  SELECT l.id AS bom_line_id, l.revision_id, l.i, a.id AS article_id, v.id AS variant_id, v.color
    FROM s_line l
    JOIN s_art a ON a.specsheet_id = l.specsheet_id
    JOIN g_var v ON v.material_id = l.material_id
                AND v.rn = (a.aj + l.n) % v.cnt;
  INSERT INTO bom_cell (bom_line_id, article_id, color, variant_id, created_at, created_by, updated_by)
  SELECT bom_line_id, article_id, color, variant_id, ts, 'spec@beban.test', 'spec@beban.test' FROM s_cell;

  -- CBD per article: PULL, SMS (→ spec SMS r1), GTM, PROD
  CREATE TEMP TABLE s_cbd ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, a.id AS article_id, r.id AS spec_rev_id, r.stage, r.ord
    FROM s_art a
    JOIN s_rev r ON r.specsheet_id = a.specsheet_id AND (r.stage, r.no) IN (('PULL', 0), ('SMS', 1), ('GTM', 0), ('PROD', 0));
  INSERT INTO cbd_revision (id, article_id, stage, revision_no, specsheet_revision_id, exchange_rate, target_fob, status,
                            sync_status, po_factor, published_at, published_by, created_at, created_by, updated_by)
  SELECT id, article_id, stage, 0, spec_rev_id, 16000, 20, 'PUBLISHED', 'IN_SYNC', CASE WHEN stage = 'SMS' THEN 1.25 END,
         ts + (ord + 1) * interval '10 days', 'cbd@beban.test', ts + (ord + 1) * interval '10 days', 'cbd@beban.test', 'cbd@beban.test'
    FROM s_cbd;
  INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, sub_seq, sub_name, material_id, color, supplier_id, uom,
                        group_code, yield_value, loss_pct, price_original, currency, price_source, material_price_id,
                        status, sort_order, variant_id, thickness, created_at, created_by, updated_by)
  SELECT c.id, bl.line_key, bl.component_id, bl.sub_seq, bl.sub_name, bl.material_id, sc.color, bl.supplier_id, m.uom,
         coalesce(comp.group_code, 'a'), 1 + (bl.sort_order % 5), 3,
         CASE WHEN m.price_method = 'QUOTATION' THEN 5 ELSE mp.price END,
         CASE WHEN m.price_method = 'QUOTATION' OR mp.id IS NOT NULL THEN 'USD' END,
         CASE WHEN m.price_method = 'QUOTATION' THEN 'QUOTATION' WHEN mp.id IS NOT NULL THEN 'MASTER' END,
         mp.id, 'ACTIVE', bl.sort_order, sc.variant_id, bl.thickness, ts, 'cbd@beban.test', 'cbd@beban.test'
    FROM s_cbd c
    JOIN bom_line bl ON bl.revision_id = c.spec_rev_id
    JOIN s_cell sc ON sc.bom_line_id = bl.id AND sc.article_id = c.article_id
    JOIN material m ON m.id = bl.material_id
    LEFT JOIN component comp ON comp.id = bl.component_id
    LEFT JOIN material_supplier ms ON ms.material_id = bl.material_id AND ms.supplier_id = bl.supplier_id
    LEFT JOIN LATERAL (SELECT mp.id, mp.price FROM material_price mp
                        WHERE mp.material_supplier_id = ms.id AND mp.variant_id = sc.variant_id
                          AND mp.status = 'APPROVED' AND mp.valid_to IS NULL LIMIT 1) mp ON true;
  INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, is_default, sort_order, created_at, created_by, updated_by)
  SELECT c.id, t, initcap(t), 1, true, 0, ts, 'cbd@beban.test', 'cbd@beban.test'
    FROM s_cbd c CROSS JOIN unnest(ARRAY['LABOUR', 'AMORTIZATION', 'ADJUSTMENT']) t;

  INSERT INTO change_log (doc_type, revision_id, category, reason, created_at, created_by)
  SELECT 'SPECSHEET', id, 'MATERIAL', 'Ganti material', ts + ord * interval '10 days', 'spec@beban.test'
    FROM s_rev WHERE ord > 1
  UNION ALL
  SELECT 'CBD', id, 'YIELD', 'Ubah yield', ts + (ord + 1) * interval '10 days', 'cbd@beban.test'
    FROM s_cbd WHERE stage <> 'PULL';

  -- audit_log massal
  INSERT INTO audit_log (created_at, user_email, entity, entity_id, action, after_data)
  SELECT ts, 'spec@beban.test', 'specsheet_revision', r.id::text, 'INSERT', to_jsonb(r) FROM specsheet_revision r JOIN s_rev s ON s.id = r.id
  UNION ALL
  SELECT ts, 'spec@beban.test', 'bom_line', l.id::text, 'INSERT', to_jsonb(l) FROM bom_line l JOIN s_line s ON s.id = l.id
  UNION ALL
  SELECT ts, 'spec@beban.test', 'bom_cell', concat_ws(':', c.bom_line_id, c.article_id), a.op, to_jsonb(c)
    FROM bom_cell c JOIN s_line s ON s.id = c.bom_line_id
    CROSS JOIN LATERAL (VALUES ('INSERT'), ('UPDATE')) a(op)
   WHERE a.op = 'INSERT' OR s.i % 2 = 0
  UNION ALL
  SELECT ts, 'cbd@beban.test', 'cbd_line', l.id::text, a.op, to_jsonb(l)
    FROM cbd_line l JOIN s_cbd s ON s.id = l.cbd_revision_id
    CROSS JOIN LATERAL (VALUES ('INSERT'), ('UPDATE')) a(op)
   WHERE a.op = 'INSERT' OR l.sort_order % 2 = 0;
END $$;

-- Aktivitas berjalan di season terakhir (dibuang & dibuat ulang tiap checkpoint)
CREATE OR REPLACE FUNCTION beban_activity(p_season text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  SET LOCAL session_replication_role = replica;
  -- buang aktivitas lama
  DELETE FROM cbd_line WHERE cbd_revision_id IN (SELECT id FROM cbd_revision WHERE status = 'DRAFT');
  DELETE FROM cbd_cost_item WHERE cbd_revision_id IN (SELECT id FROM cbd_revision WHERE status = 'DRAFT');
  DELETE FROM cbd_revision WHERE status = 'DRAFT';
  DELETE FROM bom_cell WHERE bom_line_id IN (SELECT l.id FROM bom_line l JOIN specsheet_revision r ON r.id = l.revision_id WHERE r.status = 'DRAFT');
  DELETE FROM bom_line WHERE revision_id IN (SELECT id FROM specsheet_revision WHERE status = 'DRAFT');
  DELETE FROM revision_article WHERE revision_id IN (SELECT id FROM specsheet_revision WHERE status = 'DRAFT');
  DELETE FROM specsheet_revision WHERE status = 'DRAFT';
  DELETE FROM material_price WHERE status = 'PROPOSED' OR reference = 'BARU';
  UPDATE material_price SET valid_to = NULL WHERE valid_to = fn_today() - 10;

  -- 20% specsheet season terakhir: draft PROD r1 (salinan PROD r0)
  CREATE TEMP TABLE a_rev ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, r.id AS src_id, r.specsheet_id
    FROM specsheet sh
    JOIN specsheet_revision r ON r.specsheet_id = sh.id AND r.stage = 'PROD' AND r.revision_no = 0
   WHERE sh.season = p_season AND abs(hashtext(sh.id::text)) % 5 = 0;
  INSERT INTO specsheet_revision (id, specsheet_id, stage, revision_no, status, source_revision_id, created_by, updated_by)
  SELECT id, specsheet_id, 'PROD', 1, 'DRAFT', src_id, 'spec@beban.test', 'spec@beban.test' FROM a_rev;
  INSERT INTO revision_article (revision_id, article_id, status, created_by, updated_by)
  SELECT a.id, ra.article_id, ra.status, 'spec@beban.test', 'spec@beban.test'
    FROM a_rev a JOIN revision_article ra ON ra.revision_id = a.src_id;
  CREATE TEMP TABLE a_line ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, l.id AS src_id, a.id AS revision_id FROM a_rev a JOIN bom_line l ON l.revision_id = a.src_id;
  INSERT INTO bom_line (id, revision_id, line_key, origin_line_key, component_id, parent_line_key, sub_seq, sub_name, material_id,
                        supplier_id, thickness, is_active, sort_order, created_by, updated_by)
  SELECT n.id, n.revision_id, l.line_key, l.line_key, l.component_id, l.parent_line_key, l.sub_seq, l.sub_name, l.material_id,
         l.supplier_id, l.thickness, true, l.sort_order, 'spec@beban.test', 'spec@beban.test'
    FROM a_line n JOIN bom_line l ON l.id = n.src_id;
  INSERT INTO bom_cell (bom_line_id, article_id, color, variant_id, created_by, updated_by)
  SELECT n.id, c.article_id, c.color,
         CASE WHEN abs(hashtext(n.id::text || c.article_id::text)) % 50 = 0 THEN NULL ELSE c.variant_id END,
         'spec@beban.test', 'spec@beban.test'
    FROM a_line n JOIN bom_cell c ON c.bom_line_id = n.src_id;

  -- 3 article baru belum masuk revisi
  INSERT INTO article (specsheet_id, code, colorway, created_by, updated_by)
  SELECT sh.id, p_season || '-BARU-' || row_number() OVER (), 'COLORWAY BARU', 'spec@beban.test', 'spec@beban.test'
    FROM specsheet sh WHERE sh.season = p_season ORDER BY sh.id LIMIT 3
  ON CONFLICT DO NOTHING;

  -- 5% varian × supplier: harga baru 10 hari lalu (draft CBD yang memakai harga lama jadi basi)
  UPDATE material_price SET valid_to = fn_today() - 10
   WHERE status = 'APPROVED' AND valid_to IS NULL AND abs(hashtext(id::text)) % 20 = 0;
  INSERT INTO material_price (material_supplier_id, variant_id, price, currency, valid_from, status, reference,
                              created_by, updated_by, decided_by, decided_at)
  SELECT material_supplier_id, variant_id, price * 1.05, currency, fn_today() - 10, 'APPROVED', 'BARU',
         'cbd@beban.test', 'cbd@beban.test', 'mc@beban.test', now()
    FROM material_price WHERE valid_to = fn_today() - 10;
  -- 1% PROPOSED
  INSERT INTO material_price (material_supplier_id, variant_id, price, currency, valid_from, status, reference, created_by, updated_by)
  SELECT DISTINCT ON (material_supplier_id, variant_id) material_supplier_id, variant_id, price * 1.1, currency, fn_today(), 'PROPOSED', 'USULAN',
         'cbd@beban.test', 'cbd@beban.test'
    FROM material_price WHERE status = 'APPROVED' AND valid_to IS NULL AND abs(hashtext(id::text)) % 100 = 1;

  -- 30% article season terakhir: draft CBD PROD r1 (salinan PROD r0)
  CREATE TEMP TABLE a_cbd ON COMMIT DROP AS
  SELECT gen_random_uuid() AS id, c.id AS src_id, c.article_id, c.specsheet_revision_id
    FROM cbd_revision c
    JOIN article a ON a.id = c.article_id
    JOIN specsheet sh ON sh.id = a.specsheet_id AND sh.season = p_season
   WHERE c.stage = 'PROD' AND c.status = 'PUBLISHED' AND abs(hashtext(a.id::text)) % 10 < 3;
  INSERT INTO cbd_revision (id, article_id, stage, revision_no, specsheet_revision_id, exchange_rate, target_fob, status,
                            source_cbd_revision_id, created_by, updated_by)
  SELECT id, article_id, 'PROD', 1, specsheet_revision_id, 16000, 20, 'DRAFT', src_id, 'cbd@beban.test', 'cbd@beban.test' FROM a_cbd;
  INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, sub_seq, sub_name, material_id, color, supplier_id, uom,
                        group_code, yield_value, loss_pct, price_original, currency, price_source, material_price_id,
                        status, sort_order, variant_id, thickness, value_origin, created_by, updated_by)
  SELECT a.id, l.line_key, l.component_id, l.sub_seq, l.sub_name, l.material_id, l.color, l.supplier_id, l.uom,
         l.group_code, l.yield_value, l.loss_pct, l.price_original, l.currency, l.price_source, l.material_price_id,
         l.status, l.sort_order, l.variant_id, l.thickness, 'COPIED', 'cbd@beban.test', 'cbd@beban.test'
    FROM a_cbd a JOIN cbd_line l ON l.cbd_revision_id = a.src_id;
  INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, is_default, sort_order, created_by, updated_by)
  SELECT a.id, c.item_type, c.name, c.amount, c.is_default, c.sort_order, 'cbd@beban.test', 'cbd@beban.test'
    FROM a_cbd a JOIN cbd_cost_item c ON c.cbd_revision_id = a.src_id;
END $$;
