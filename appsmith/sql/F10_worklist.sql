-- ============================================================================
-- F10 — Beranda "Tugas Saya": daftar pekerjaan per role
-- Jalankan SETELAH F8b, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
-- Tidak ada tabel baru, hanya view. View TIDAK memeriksa izin — query di Appsmith yang membungkusnya
-- dengan fn_auth(token, izin) (pola sama dengan view lain), jadi jangan dipanggil tanpa fn_auth.
--
-- Isi (= worklist_service.py, dengan penyesuaian PLAN §2):
--   v_worklist_spec       Vendor Spec  — draft specsheet terbuka (+ hal yang menghambat terbit) dan
--                         season yang punya article belum masuk revisi mana pun
--   v_worklist_cbd        Vendor CBD   — per article aktif di specsheet terbit terakhir: belum ada CBD (TO_CREATE),
--                         draft tertinggal dari specsheet / harga master (TO_REFRESH), CBD terbit perlu revisi
--                         (TO_REVISE), draft berjalan (IN_PROGRESS)
--   v_worklist_price_gap  Vendor CBD   — material katalog + supplier di specsheet terbit yang belum punya harga
--                         master berlaku (hanya harga APPROVED yang dihitung, F3b); has_pending = ada usulan
--                         harga yang menunggu approval
--   v_worklist_admin      Master Admin — antrian PROPOSED: material, komponen, supplier material, + usulan
--                         harga (F3b). Baris PRICE memuat angka harga → jangan dibuka untuk role tanpa view_price
--   v_recent_published    Brand        — revisi terbit terakhir tiap season (SPECSHEET) dan tiap article (CBD)
--   v_system_summary      System Admin — satu baris ringkasan jumlah data & aktivitas terakhir
--
-- Perbedaan dari Python:
-- - P6: "terbit terbaru" (v_recent_published) memakai urutan stage + nomor revisi, bukan waktu terbit (sama dengan
--   P1/P2); daftar akhirnya tetap diurutkan terbaru dulu oleh query.
-- - Antrian admin ditambah usulan harga (F3b); price gap ditambah penanda usulan harga yang menunggu approval.
-- ============================================================================

-- ---------------------------------------------------------------- Cek bentrok nama
-- Nama view milik proyek ini tidak boleh sudah dipakai objek lain (database dipakai bersama aplikasi lain).
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('v_worklist_spec', 'kind'), ('v_worklist_cbd', 'kind'),
                                 ('v_worklist_price_gap', 'material_id'), ('v_worklist_admin', 'kind'),
                                 ('v_recent_published', 'doc_type'), ('v_system_summary', 'audit_entries'))
                  AS t(rel, col)
  LOOP
    IF to_regclass('public.' || r.rel) IS NOT NULL AND (
         (SELECT c.relkind FROM pg_class c WHERE c.oid = to_regclass('public.' || r.rel)) <> 'v'
         OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_schema = 'public' AND table_name = r.rel AND column_name = r.col)) THEN
      RAISE EXCEPTION '"%" sudah ada di database dan bukan milik proyek ini. Hentikan dan hubungi pengembang.', r.rel;
    END IF;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------- Vendor Spec
-- kind DRAFT      : satu baris per revisi DRAFT. Penghambat terbit diambil dari v_revision_checklist (F6):
--                   article_count = article aktif · unused_articles = article aktif yang belum dipakai di BOM mana pun ·
--                   inactive_materials = material INACTIVE di BOM · no_supplier = baris BOM tanpa supplier (peringatan)
-- kind UNASSIGNED : satu baris per season yang punya article yang belum masuk revisi mana pun
--                   (article_count, article_codes; has_revision = season sudah punya revisi — pilih di revisi,
--                   kalau belum: buat revisi dulu)
CREATE OR REPLACE VIEW v_worklist_spec AS
SELECT 'DRAFT'::text AS kind,
       pm.id AS model_id, pm.code AS model_code, pm.name AS model_name,
       sh.id AS specsheet_id, sh.season,
       r.id AS revision_id, r.stage, r.revision_no,
       ck.line_count, ck.no_supplier_lines AS no_supplier, ck.active_articles AS article_count,
       ck.unused_articles, ck.inactive_materials,
       NULL::text AS article_codes, NULL::boolean AS has_revision
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
       u.codes, EXISTS (SELECT 1 FROM specsheet_revision x WHERE x.specsheet_id = sh.id)
  FROM specsheet sh
  JOIN product_model pm ON pm.id = sh.model_id
  CROSS JOIN LATERAL (
    SELECT count(*)::integer AS n, string_agg(a.code, ', ' ORDER BY a.code) AS codes
      FROM article a
     WHERE a.specsheet_id = sh.id
       AND NOT EXISTS (SELECT 1 FROM revision_article ra WHERE ra.article_id = a.id)
  ) u
 WHERE u.n > 0;

-- ---------------------------------------------------------------- Vendor CBD
-- Hanya article yang ACTIVE di revisi specsheet terbit terakhir (v_cbd_article.spec_status).
--   TO_CREATE   : article belum punya revisi CBD sama sekali
--   TO_REFRESH  : ada draft, dan specsheet acuannya sudah direvisi (refresh_reason SPEC) atau harga master untuk
--                 satu baris atau lebih sudah berubah (PRICE) — sama dengan banner "Refresh" di page CBD
--   IN_PROGRESS : ada draft, tidak tertinggal
--   TO_REVISE   : tidak ada draft, CBD terbit terakhir NEEDS_REVISION
-- cbd_revision_id / rev_label = draft, atau (TO_REVISE) CBD terbit terakhir; NULL untuk TO_CREATE.
CREATE OR REPLACE VIEW v_worklist_cbd AS
SELECT x.*
  FROM (
    SELECT CASE WHEN a.revision_count = 0 THEN 'TO_CREATE'
                WHEN a.draft_id IS NOT NULL
                     THEN CASE WHEN a.draft_stale OR pr.stale_prices > 0 THEN 'TO_REFRESH' ELSE 'IN_PROGRESS' END
                WHEN a.pub_sync = 'NEEDS_REVISION' THEN 'TO_REVISE' END AS kind,
           CASE WHEN a.draft_id IS NULL THEN NULL
                WHEN a.draft_stale THEN 'SPEC'
                WHEN pr.stale_prices > 0 THEN 'PRICE' END AS refresh_reason,
           a.id AS article_id, a.code AS article_code, a.colorway,
           pm.id AS model_id, pm.code AS model_code, pm.name AS model_name,
           a.specsheet_id, a.season,
           coalesce(a.draft_id, a.pub_id) AS cbd_revision_id,
           coalesce(a.draft_label, a.pub_label) AS rev_label
      FROM v_cbd_article a
      JOIN product_model pm ON pm.id = a.model_id
      CROSS JOIN LATERAL (
        SELECT count(*)::integer AS stale_prices
          FROM v_cbd_price_check pc
         WHERE pc.cbd_revision_id = a.draft_id AND pc.master_stale
      ) pr
     WHERE a.spec_status = 'ACTIVE'
  ) x
 WHERE x.kind IS NOT NULL;

-- Material CATALOG + supplier yang dipakai (sel berwarna, article aktif) di specsheet terbit terakhir tiap season
-- tetapi belum punya harga master berlaku untuk warna itu (fn_price_lookup: harga warna dulu, lalu semua warna;
-- hanya APPROVED). Dikelompokkan per material + supplier. Baris BOM tanpa supplier tidak ikut (itu peringatan
-- di worklist spec). color_count = jumlah warna yang belum berharga, models = kode model yang memakainya.
CREATE OR REPLACE VIEW v_worklist_price_gap AS
SELECT m.id AS material_id, m.material_code, m.name AS material_name,
       s.id AS supplier_id, s.name AS supplier_name,
       count(DISTINCT g.color_key)::integer AS color_count,
       string_agg(DISTINCT g.color, ', ' ORDER BY g.color) AS colors,
       string_agg(DISTINCT g.model_code, ', ' ORDER BY g.model_code) AS models,
       bool_or(EXISTS (SELECT 1 FROM material_price mp JOIN material_supplier ms ON ms.id = mp.material_supplier_id
                        WHERE ms.material_id = g.material_id AND ms.supplier_id = g.supplier_id
                          AND mp.status = 'PROPOSED')) AS has_pending
  FROM (
    SELECT DISTINCT bl.material_id, bl.supplier_id, bc.color, fn_normalize(bc.color) AS color_key, pm.code AS model_code
      FROM specsheet sh
      JOIN product_model pm ON pm.id = sh.model_id
      JOIN specsheet_revision r ON r.id = fn_spec_latest_pub(sh.id)
      JOIN bom_line bl ON bl.revision_id = r.id AND bl.is_active AND bl.supplier_id IS NOT NULL
      JOIN bom_cell bc ON bc.bom_line_id = bl.id AND bc.is_used
      JOIN revision_article ra ON ra.revision_id = r.id AND ra.article_id = bc.article_id AND ra.status = 'ACTIVE'
  ) g
  JOIN material m ON m.id = g.material_id AND m.price_method = 'CATALOG'
  JOIN supplier s ON s.id = g.supplier_id
 WHERE NOT EXISTS (SELECT 1 FROM fn_price_lookup(g.material_id, g.supplier_id, g.color))
 GROUP BY m.id, m.material_code, m.name, s.id, s.name;

-- ---------------------------------------------------------------- Master Admin
-- Antrian persetujuan (status PROPOSED), terbaru dulu diurutkan oleh query.
--   MATERIAL  : material usulan (detail = kategori)
--   COMPONENT : komponen usulan (detail = kelompok)             · material_id NULL (buka Master Komponen)
--   LINK      : supplier material usulan (detail = supplier)
--   PRICE     : usulan harga (F3b) — detail = supplier [· warna], amount_text = "USD 12.5" (tanpa nol di belakang)
-- ref_id = id baris yang diusulkan. amount_text hanya terisi untuk PRICE (data harga: batasi dengan izin).
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
 WHERE mp.status = 'PROPOSED';

-- ---------------------------------------------------------------- Brand
-- Revisi terbit terakhir tiap season (SPECSHEET) dan tiap article (CBD) — urut stage lalu nomor (P6).
-- Hanya revisi PUBLISHED, jadi aman untuk Brand. sync_status hanya untuk CBD.
CREATE OR REPLACE VIEW v_recent_published AS
SELECT 'SPECSHEET'::text AS doc_type, r.id AS revision_id,
       pm.id AS model_id, pm.code AS model_code, pm.name AS model_name,
       sh.id AS specsheet_id, sh.season,
       NULL::uuid AS article_id, NULL::text AS article_code, NULL::text AS colorway,
       r.stage, r.revision_no, r.published_at, r.published_by, NULL::text AS sync_status
  FROM specsheet sh
  JOIN product_model pm ON pm.id = sh.model_id
  JOIN specsheet_revision r ON r.id = fn_spec_latest_pub(sh.id)
UNION ALL
SELECT 'CBD', c.id,
       pm.id, pm.code, pm.name,
       sh.id, sh.season,
       a.id, a.code, a.colorway,
       c.stage, c.revision_no, c.published_at, c.published_by, c.sync_status
  FROM article a
  JOIN specsheet sh ON sh.id = a.specsheet_id
  JOIN product_model pm ON pm.id = sh.model_id
  JOIN LATERAL (
    SELECT x.id, x.stage, x.revision_no, x.published_at, x.published_by, x.sync_status
      FROM cbd_revision x
     WHERE x.article_id = a.id AND x.status = 'PUBLISHED'
     ORDER BY x.stage_order DESC, x.revision_no DESC LIMIT 1
  ) c ON true;

-- ---------------------------------------------------------------- System Admin
-- Satu baris. Hanya jumlah (tanpa isi data bisnis).
CREATE OR REPLACE VIEW v_system_summary AS
SELECT (SELECT count(*) FROM product_model)::integer AS models,
       (SELECT count(*) FROM specsheet)::integer AS specsheets,
       (SELECT count(*) FROM article)::integer AS articles,
       (SELECT count(*) FROM cbd_revision)::integer AS cbd_revisions,
       (SELECT count(*) FROM material)::integer AS materials,
       (SELECT count(*) FROM app_user WHERE is_active)::integer AS active_users,
       (SELECT count(*) FROM audit_log)::integer AS audit_entries,
       (SELECT max(created_at) FROM audit_log) AS last_audit;
