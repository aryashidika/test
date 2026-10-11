-- ============================================================================
-- R_revisi_semua — gabungan revisi R3 + R4 + R5 + R6 + R7 (dibuat otomatis oleh tools/make_revisi_sql.py;
-- JANGAN diedit langsung — ubah file sql/R3_…–R7_… lalu jalankan ulang skripnya).
--
-- Urutan menjalankan (DB Tools, z_run_sql, Use prepared statements = OFF):
--   1. sql/RESET_data_bisnis.sql   (hapus data uji; user & pabrik tetap)
--   2. file ini                    (satu transaksi: kalau ada error, TIDAK ADA yang tersimpan; aman diulang)
--   3. sql/R_selftest.sql          (uji alur inti lalu dibatalkan; hasil harus "SELFTEST LOLOS")
-- Baris terakhir hasil query ini = ringkasan cek. Kalau error, pesan menyebut bagian (R3…R7) yang gagal.
-- ============================================================================


-- #################################################################### R3_harga
DO $$ BEGIN RAISE NOTICE 'mulai R3_harga'; END $$;

-- ============================================================================
-- R3 — Harga Varian × Supplier, pengajuan banyak varian, salin harga, approval Manager Costing
-- (keputusan user 8 Okt 2026, PLAN.md §2 "Revisi besar" & §6 R3)
-- Jalankan SETELAH R2_master.sql + R2b_varian.sql, lewat z_run_sql di app "DB Tools"
-- (Use prepared statements = OFF). Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
--
-- Aturan:
-- - Harga = VARIAN (Material Code) × SUPPLIER material. Hanya material CATALOG; QUOTATION diisi per CBD.
-- - Vendor CBD (manage_price) MENGAJUKAN: satu supplier, centang banyak varian, satu harga + currency +
--   berlaku mulai + referensi -> satu pengajuan (batch_id), semua PROPOSED. "Salin harga dari varian lain":
--   harga berlaku varian sumber (semua supplier aktif) disalin ke varian tujuan -> juga PROPOSED.
-- - Maks. satu usulan PROPOSED per varian + supplier. Usulan bisa dibatalkan tim CBD selama belum diproses.
-- - Manager Costing (approve_price) MENYETUJUI / MENOLAK per baris (banyak baris sekaligus; tolak = alasan
--   wajib) dan MENGAKHIRI harga. Tidak bisa mengajukan; tidak bisa memproses usulan sendiri.
-- - Harga lama tetap berlaku sampai usulan disetujui; saat disetujui harga lama ditutup per tanggal berlaku
--   harga baru (tanggal tidak boleh lebih awal dari harga yang sedang berlaku).
-- - Lookup harga (dipakai CBD mulai R5): hanya APPROVED dari supplier & supplier material ACTIVE (F10d).
-- - Semua data harga mengikuti pabrik material (fn_assert_factory / fn_can_see_factory).
-- - Masa transisi: kolom material_price.color/color_key dibiarkan (selalu kosong) sampai R5 karena masih
--   dibaca view CBD lama; fn_price_lookup versi warna lama tidak mengembalikan harga (CBD per varian di R5).
-- ============================================================================

-- ---------------------------------------------------------------- Pengaman
DO $$
BEGIN
  IF to_regclass('public.material_variant') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'material_variant' AND column_name = 'thickness') THEN
    RAISE EXCEPTION 'Struktur varian R2/R2b belum lengkap. Jalankan R2_master.sql dan R2b_varian.sql dulu.';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'material_price' AND column_name = 'variant_id') THEN
    RETURN;                                                       -- sudah pernah dijalankan
  END IF;
  IF EXISTS (SELECT 1 FROM material_price) THEN
    RAISE EXCEPTION 'Masih ada harga lama (per warna). Jalankan RESET_data_bisnis.sql dulu (user & pabrik tetap tersimpan).';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Kolom
ALTER TABLE material_price
  ADD COLUMN IF NOT EXISTS variant_id uuid REFERENCES material_variant(id),
  ADD COLUMN IF NOT EXISTS batch_id   uuid;                         -- satu pengajuan (form Ajukan / Salin)
ALTER TABLE material_price ALTER COLUMN variant_id SET NOT NULL;

DROP INDEX IF EXISTS uq_price_one_proposed;                          -- versi F3b: per supplier + warna
CREATE UNIQUE INDEX uq_price_one_proposed ON material_price (material_supplier_id, variant_id) WHERE status = 'PROPOSED';
CREATE INDEX IF NOT EXISTS idx_material_price_variant ON material_price (variant_id, material_supplier_id);
CREATE INDEX IF NOT EXISTS idx_material_price_batch ON material_price (batch_id);

-- ---------------------------------------------------------------- Fungsi lama per warna
DROP FUNCTION IF EXISTS fn_price_add(text, uuid, text, numeric, text, date, text);
DROP FUNCTION IF EXISTS fn_price_approve(text, uuid);
DROP FUNCTION IF EXISTS fn_price_reject(text, uuid, text);

-- Versi warna (F3) masih dipanggil CBD lama (fn_cbd_populate, v_cbd_price_check, v_worklist_price_gap).
-- Transisi sampai R5: tidak mengembalikan harga apa pun (harga sekarang per varian).
CREATE OR REPLACE FUNCTION fn_price_lookup(p_material_id uuid, p_supplier_id uuid, p_color text, p_on date DEFAULT NULL)
RETURNS TABLE (price_id uuid, price numeric, currency text, tier text)
LANGUAGE sql STABLE AS $$
  SELECT NULL::uuid, NULL::numeric, NULL::text, NULL::text WHERE false
$$;

-- ---------------------------------------------------------------- Helper
-- jsonb array id ('["uuid", ...]') -> uuid[] tanpa duplikat
CREATE OR REPLACE FUNCTION fn_uuid_list(p jsonb) RETURNS uuid[]
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN jsonb_typeof(p) = 'array'
              THEN ARRAY(SELECT DISTINCT e::uuid FROM jsonb_array_elements_text(p) AS e WHERE btrim(e) <> '')
              ELSE ARRAY[]::uuid[] END
$$;

-- Keterangan harga untuk tabel: MENUNGGU APPROVAL / DITOLAK / RIWAYAT / AKAN BERLAKU / BERLAKU
CREATE OR REPLACE FUNCTION fn_price_state(p_status text, p_valid_from date, p_valid_to date) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN p_status = 'PROPOSED' THEN 'MENUNGGU APPROVAL'
              WHEN p_status = 'REJECTED' THEN 'DITOLAK'
              WHEN p_valid_to IS NOT NULL AND p_valid_to <= fn_today() THEN 'RIWAYAT'
              WHEN p_valid_from > fn_today() THEN 'AKAN BERLAKU'
              ELSE 'BERLAKU' END
$$;

-- ---------------------------------------------------------------- Lookup harga per varian (dipakai CBD mulai R5)
-- Hanya APPROVED, material CATALOG, supplier & supplier material ACTIVE (F10d), berlaku pada tanggal p_on.
CREATE OR REPLACE FUNCTION fn_price_lookup(p_variant_id uuid, p_supplier_id uuid, p_on date DEFAULT NULL)
RETURNS TABLE (price_id uuid, price numeric, currency text, valid_from date)
LANGUAGE sql STABLE AS $$
  SELECT mp.id, mp.price, mp.currency, mp.valid_from
    FROM material_price mp
    JOIN material_variant v ON v.id = mp.variant_id
    JOIN material_supplier ms ON ms.id = mp.material_supplier_id AND ms.material_id = v.material_id
    JOIN supplier s ON s.id = ms.supplier_id
    JOIN material m ON m.id = v.material_id
   WHERE mp.variant_id = p_variant_id AND ms.supplier_id = p_supplier_id
     AND m.price_method = 'CATALOG' AND mp.status = 'APPROVED'
     AND ms.status = 'ACTIVE' AND s.status = 'ACTIVE'
     AND mp.valid_from <= coalesce(p_on, fn_today())
     AND (mp.valid_to IS NULL OR mp.valid_to > coalesce(p_on, fn_today()))
   ORDER BY mp.valid_from DESC, mp.created_at DESC
   LIMIT 1
$$;

-- ---------------------------------------------------------------- Aktifkan harga (dipakai saat approve)
-- Menutup harga APPROVED yang masih terbuka untuk varian + supplier yang sama, lalu set APPROVED.
CREATE OR REPLACE FUNCTION fn_price_activate(p_price_id uuid, p_actor text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_row  material_price%ROWTYPE;
  v_open material_price%ROWTYPE;
  v_code text;
BEGIN
  SELECT * INTO v_row FROM material_price WHERE id = p_price_id;
  SELECT * INTO v_open FROM material_price
   WHERE material_supplier_id = v_row.material_supplier_id AND variant_id = v_row.variant_id
     AND status = 'APPROVED' AND valid_to IS NULL AND id <> v_row.id
   ORDER BY valid_from DESC LIMIT 1;
  IF FOUND THEN
    IF v_row.valid_from < v_open.valid_from THEN
      SELECT code INTO v_code FROM material_variant WHERE id = v_row.variant_id;
      RAISE EXCEPTION 'Varian %: sudah ada harga yang berlaku mulai %. Usulan berlaku mulai % (lebih awal) — tolak usulan ini.',
        v_code, to_char(v_open.valid_from, 'DD-MM-YYYY'), to_char(v_row.valid_from, 'DD-MM-YYYY');
    END IF;
    UPDATE material_price SET valid_to = v_row.valid_from, updated_by = p_actor WHERE id = v_open.id;
  END IF;
  UPDATE material_price
     SET status = 'APPROVED', decided_by = p_actor, decided_at = now(), reject_reason = NULL, updated_by = p_actor
   WHERE id = p_price_id;
END;
$$;

-- ---------------------------------------------------------------- Ajukan harga (Vendor CBD)
-- Satu supplier material + banyak varian (p_variant_ids = '["uuid", ...]') + satu harga -> satu pengajuan.
-- Semua atau tidak sama sekali. Mengembalikan batch_id.
CREATE OR REPLACE FUNCTION fn_price_propose(
  p_token text, p_link_id uuid, p_variant_ids jsonb, p_price numeric, p_currency text,
  p_valid_from date, p_reference text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_price');
  v_link  record;
  v_ids   uuid[] := fn_uuid_list(p_variant_ids);
  v_from  date := coalesce(p_valid_from, fn_today());
  v_ref   text := nullif(btrim(coalesce(p_reference, '')), '');
  v_batch uuid := gen_random_uuid();
  v_bad   text;
BEGIN
  SELECT ms.id, ms.status, ms.material_id, s.name AS supplier_name, s.status AS supplier_status,
         m.factory_id, m.name AS material_name, m.status AS material_status, m.price_method
    INTO v_link
    FROM material_supplier ms
    JOIN supplier s ON s.id = ms.supplier_id
    JOIN material m ON m.id = ms.material_id
   WHERE ms.id = p_link_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pilih supplier.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_link.factory_id);
  IF v_link.material_status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Material % sudah INACTIVE — tidak bisa diberi harga baru.', v_link.material_name;
  END IF;
  IF v_link.price_method = 'QUOTATION' THEN
    RAISE EXCEPTION 'Material ini memakai metode harga Quotation — harganya diisi per CBD, bukan di master.';
  END IF;
  IF v_link.status = 'INACTIVE' OR v_link.supplier_status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Supplier % sudah nonaktif untuk material ini — tidak bisa diberi harga baru.', v_link.supplier_name;
  END IF;
  IF p_price IS NULL OR p_price <= 0 THEN
    RAISE EXCEPTION 'Harga harus lebih besar dari 0.';
  END IF;
  IF coalesce(p_currency, '') NOT IN ('IDR', 'USD') THEN
    RAISE EXCEPTION 'Currency wajib dipilih (IDR atau USD).';
  END IF;
  IF cardinality(v_ids) = 0 THEN
    RAISE EXCEPTION 'Centang minimal satu varian.';
  END IF;

  IF EXISTS (SELECT 1 FROM unnest(v_ids) AS x(id)
              WHERE NOT EXISTS (SELECT 1 FROM material_variant v WHERE v.id = x.id AND v.material_id = v_link.material_id)) THEN
    RAISE EXCEPTION 'Ada varian yang bukan milik material ini. Muat ulang halaman.';
  END IF;
  SELECT string_agg(v.code, ', ' ORDER BY v.code) INTO v_bad
    FROM material_variant v WHERE v.id = ANY (v_ids) AND v.status = 'INACTIVE';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Varian INACTIVE tidak bisa diberi harga: %.', v_bad;
  END IF;
  SELECT string_agg(v.code || ' (' || trim_scale(mp.price)::text || ' ' || mp.currency || ')', ', ' ORDER BY v.code) INTO v_bad
    FROM material_price mp JOIN material_variant v ON v.id = mp.variant_id
   WHERE mp.material_supplier_id = p_link_id AND mp.variant_id = ANY (v_ids) AND mp.status = 'PROPOSED';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Masih ada usulan harga dari % yang menunggu approval untuk: %. Batalkan usulan itu dulu atau tunggu Manager Costing memprosesnya.',
      v_link.supplier_name, v_bad;
  END IF;
  SELECT string_agg(v.code || ' (berlaku ' || to_char(mp.valid_from, 'DD-MM-YYYY') || ')', ', ' ORDER BY v.code) INTO v_bad
    FROM material_price mp JOIN material_variant v ON v.id = mp.variant_id
   WHERE mp.material_supplier_id = p_link_id AND mp.variant_id = ANY (v_ids)
     AND mp.status = 'APPROVED' AND mp.valid_to IS NULL AND mp.valid_from > v_from;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Tanggal berlaku tidak boleh lebih awal dari harga yang sudah ada: %.', v_bad;
  END IF;

  INSERT INTO material_price (material_supplier_id, variant_id, batch_id, price, currency, valid_from, reference,
                              status, updated_by)
  SELECT p_link_id, x.id, v_batch, p_price, p_currency, v_from, v_ref, 'PROPOSED', v_email
    FROM unnest(v_ids) AS x(id);
  RETURN v_batch;
END;
$$;

-- ---------------------------------------------------------------- Salin harga dari varian lain (Vendor CBD)
-- Harga BERLAKU varian sumber dari setiap supplier aktif disalin ke varian tujuan (material yang sama) sebagai
-- usulan PROPOSED dalam satu pengajuan. Pasangan yang masih punya usulan menunggu, atau yang harganya berlaku
-- mulai setelah p_valid_from, dilewati (dilaporkan di kolom skipped). Tidak ada yang tersalin -> error.
DROP FUNCTION IF EXISTS fn_price_copy(text, uuid, jsonb, date, text);
CREATE FUNCTION fn_price_copy(p_token text, p_source_id uuid, p_target_ids jsonb, p_valid_from date, p_reference text)
RETURNS TABLE (batch_id uuid, created integer, skipped text)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  v_email   text := fn_auth(p_token, 'manage_price');
  v_src     record;
  v_ids     uuid[];
  v_from    date := coalesce(p_valid_from, fn_today());
  v_ref     text;
  v_batch   uuid := gen_random_uuid();
  v_n       integer := 0;
  v_sources integer := 0;
  v_skip    text[] := ARRAY[]::text[];
  r         record;
  t         record;
  v_date    date;
BEGIN
  SELECT v.id, v.code, v.material_id, v.status, m.factory_id, m.name AS material_name,
         m.status AS material_status, m.price_method
    INTO v_src
    FROM material_variant v JOIN material m ON m.id = v.material_id
   WHERE v.id = p_source_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pilih varian sumber.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_src.factory_id);
  IF v_src.material_status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Material % sudah INACTIVE — tidak bisa diberi harga baru.', v_src.material_name;
  END IF;
  IF v_src.price_method = 'QUOTATION' THEN
    RAISE EXCEPTION 'Material ini memakai metode harga Quotation — harganya diisi per CBD, bukan di master.';
  END IF;
  v_ids := array_remove(fn_uuid_list(p_target_ids), p_source_id);
  IF cardinality(v_ids) = 0 THEN
    RAISE EXCEPTION 'Centang minimal satu varian tujuan.';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_ids) AS x(id)
              WHERE NOT EXISTS (SELECT 1 FROM material_variant v WHERE v.id = x.id AND v.material_id = v_src.material_id)) THEN
    RAISE EXCEPTION 'Varian tujuan harus dari material yang sama. Muat ulang halaman.';
  END IF;
  IF EXISTS (SELECT 1 FROM material_variant v WHERE v.id = ANY (v_ids) AND v.status = 'INACTIVE') THEN
    RAISE EXCEPTION 'Varian INACTIVE tidak bisa diberi harga: %.',
      (SELECT string_agg(v.code, ', ' ORDER BY v.code) FROM material_variant v WHERE v.id = ANY (v_ids) AND v.status = 'INACTIVE');
  END IF;
  v_ref := coalesce(nullif(btrim(coalesce(p_reference, '')), ''), 'Salin dari ' || v_src.code);

  FOR r IN
    SELECT ms.id AS link_id, s.name AS supplier_name, lp.price, lp.currency
      FROM material_supplier ms
      JOIN supplier s ON s.id = ms.supplier_id
      CROSS JOIN LATERAL fn_price_lookup(p_source_id, ms.supplier_id) AS lp
     WHERE ms.material_id = v_src.material_id
     ORDER BY s.name
  LOOP
    v_sources := v_sources + 1;
    FOR t IN SELECT v.id, v.code FROM material_variant v WHERE v.id = ANY (v_ids) ORDER BY v.code LOOP
      IF EXISTS (SELECT 1 FROM material_price mp
                  WHERE mp.material_supplier_id = r.link_id AND mp.variant_id = t.id AND mp.status = 'PROPOSED') THEN
        v_skip := v_skip || (t.code || ' · ' || r.supplier_name || ': masih ada usulan menunggu');
        CONTINUE;
      END IF;
      SELECT max(mp.valid_from) INTO v_date FROM material_price mp
       WHERE mp.material_supplier_id = r.link_id AND mp.variant_id = t.id
         AND mp.status = 'APPROVED' AND mp.valid_to IS NULL AND mp.valid_from > v_from;
      IF v_date IS NOT NULL THEN
        v_skip := v_skip || (t.code || ' · ' || r.supplier_name || ': sudah ada harga mulai ' || to_char(v_date, 'DD-MM-YYYY'));
        CONTINUE;
      END IF;
      INSERT INTO material_price (material_supplier_id, variant_id, batch_id, price, currency, valid_from, reference,
                                  status, updated_by)
      VALUES (r.link_id, t.id, v_batch, r.price, r.currency, v_from, v_ref, 'PROPOSED', v_email);
      v_n := v_n + 1;
    END LOOP;
  END LOOP;

  IF v_sources = 0 THEN
    RAISE EXCEPTION 'Varian sumber % belum punya harga berlaku (sudah disetujui) dari supplier aktif.', v_src.code;
  END IF;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'Tidak ada harga yang disalin: %.', array_to_string(v_skip, '; ');
  END IF;
  RETURN QUERY SELECT v_batch, v_n, nullif(array_to_string(v_skip, '; '), '');
END;
$$;

-- ---------------------------------------------------------------- Batalkan usulan (Vendor CBD)
CREATE OR REPLACE FUNCTION fn_price_cancel(p_token text, p_price_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_price');
  v_row   record;
BEGIN
  SELECT mp.status, m.factory_id INTO v_row
    FROM material_price mp
    JOIN material_supplier ms ON ms.id = mp.material_supplier_id
    JOIN material m ON m.id = ms.material_id
   WHERE mp.id = p_price_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Harga tidak ditemukan.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_row.factory_id);
  IF v_row.status <> 'PROPOSED' THEN
    RAISE EXCEPTION 'Hanya usulan yang belum diproses yang bisa dibatalkan.';
  END IF;
  DELETE FROM material_price WHERE id = p_price_id;
  RETURN p_price_id;
END;
$$;

-- ---------------------------------------------------------------- Setujui / tolak (Manager Costing)
-- p_price_ids = '["uuid", ...]', p_decision = APPROVE | REJECT (alasan wajib). Semua atau tidak sama sekali.
CREATE OR REPLACE FUNCTION fn_price_decide(p_token text, p_price_ids jsonb, p_decision text, p_reason text)
RETURNS integer
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
       WHERE id = r.id;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------- Akhiri harga (Manager Costing)
CREATE OR REPLACE FUNCTION fn_price_end(p_token text, p_price_id uuid, p_valid_to date) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'approve_price');
  v_row   record;
BEGIN
  SELECT mp.status, mp.valid_to, m.factory_id INTO v_row
    FROM material_price mp
    JOIN material_supplier ms ON ms.id = mp.material_supplier_id
    JOIN material m ON m.id = ms.material_id
   WHERE mp.id = p_price_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Harga tidak ditemukan.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_row.factory_id);
  IF v_row.status <> 'APPROVED' THEN
    RAISE EXCEPTION 'Hanya harga yang sudah disetujui yang bisa diakhiri. Untuk usulan, pakai Tolak.';
  END IF;
  IF v_row.valid_to IS NOT NULL THEN
    RAISE EXCEPTION 'Harga ini sudah ditutup.';
  END IF;
  UPDATE material_price
     SET valid_to = greatest(coalesce(p_valid_to, fn_today()), valid_from), updated_by = v_email
   WHERE id = p_price_id;
  RETURN p_price_id;
END;
$$;

-- ---------------------------------------------------------------- Tabel harga Material Detail
-- Semua baris harga + baris "BELUM ADA HARGA" untuk setiap varian ACTIVE × supplier material ACTIVE
-- (material CATALOG) yang belum punya harga berlaku / akan berlaku dan tidak punya usulan menunggu.
-- row_key unik untuk tabel. state_order untuk urutan tampil.
DROP VIEW IF EXISTS v_material_price;
CREATE VIEW v_material_price AS
SELECT mp.id::text AS row_key, mp.id, m.id AS material_id, m.factory_id,
       v.id AS variant_id, v.code, v.color, v.thickness, fn_thickness_label(v.thickness) AS thickness_label,
       v.status AS variant_status,
       ms.id AS link_id, s.name AS supplier_name, ms.status AS link_status,
       mp.price, mp.currency, mp.valid_from, mp.valid_to, mp.reference, mp.status,
       x.state,
       CASE x.state WHEN 'MENUNGGU APPROVAL' THEN 1 WHEN 'BERLAKU' THEN 3 WHEN 'AKAN BERLAKU' THEN 4
                    WHEN 'DITOLAK' THEN 5 ELSE 6 END AS state_order,
       mp.reject_reason, mp.batch_id, mp.created_by, mp.created_at, mp.decided_by, mp.decided_at
  FROM material_price mp
  JOIN material_variant v ON v.id = mp.variant_id
  JOIN material_supplier ms ON ms.id = mp.material_supplier_id
  JOIN supplier s ON s.id = ms.supplier_id
  JOIN material m ON m.id = ms.material_id
  CROSS JOIN LATERAL (SELECT fn_price_state(mp.status, mp.valid_from, mp.valid_to) AS state) x
UNION ALL
SELECT 'gap:' || v.id || ':' || ms.id, NULL::uuid, m.id, m.factory_id,
       v.id, v.code, v.color, v.thickness, fn_thickness_label(v.thickness), v.status,
       ms.id, s.name, ms.status,
       NULL::numeric, NULL::text, NULL::date, NULL::date, NULL::text, NULL::text,
       'BELUM ADA HARGA', 2,
       NULL::text, NULL::uuid, NULL::text, NULL::timestamptz, NULL::text, NULL::timestamptz
  FROM material m
  JOIN material_variant v ON v.material_id = m.id AND v.status = 'ACTIVE'
  JOIN material_supplier ms ON ms.material_id = m.id AND ms.status = 'ACTIVE'
  JOIN supplier s ON s.id = ms.supplier_id AND s.status = 'ACTIVE'
 WHERE m.price_method = 'CATALOG'
   AND NOT EXISTS (SELECT 1 FROM material_price mp
                    WHERE mp.material_supplier_id = ms.id AND mp.variant_id = v.id
                      AND (mp.status = 'PROPOSED'
                           OR (mp.status = 'APPROVED' AND (mp.valid_to IS NULL OR mp.valid_to > fn_today()))));

-- ---------------------------------------------------------------- Usulan menunggu (page Persetujuan Harga)
-- cur_* = harga APPROVED yang masih terbuka untuk varian + supplier yang sama (akan ditutup bila disetujui).
-- problem = alasan usulan tidak bisa disetujui (harus ditolak); NULL = bisa disetujui.
DROP VIEW IF EXISTS v_worklist_admin;                 -- bergantung pada v_price_pending (dibuat ulang di bawah)
DROP VIEW IF EXISTS v_price_pending;
CREATE VIEW v_price_pending AS
SELECT mp.id, coalesce(mp.batch_id, mp.id) AS batch_id, m.id AS material_id, m.factory_id,
       m.name AS material_name, m.uom,
       v.id AS variant_id, v.code, v.color, fn_thickness_label(v.thickness) AS thickness_label,
       s.name AS supplier_name,
       mp.price, mp.currency, mp.valid_from, mp.reference, mp.created_by, mp.created_at,
       cur.price AS cur_price, cur.currency AS cur_currency, cur.valid_from AS cur_valid_from,
       CASE WHEN m.price_method <> 'CATALOG' THEN 'Material sekarang Quotation'
            WHEN ms.status = 'INACTIVE' OR s.status = 'INACTIVE' THEN 'Supplier nonaktif'
            WHEN v.status = 'INACTIVE' THEN 'Varian INACTIVE'
            WHEN cur.valid_from > mp.valid_from THEN 'Lebih awal dari harga berlaku (' || to_char(cur.valid_from, 'DD-MM-YYYY') || ')'
       END AS problem
  FROM material_price mp
  JOIN material_variant v ON v.id = mp.variant_id
  JOIN material_supplier ms ON ms.id = mp.material_supplier_id
  JOIN supplier s ON s.id = ms.supplier_id
  JOIN material m ON m.id = ms.material_id
  LEFT JOIN LATERAL (
    SELECT o.price, o.currency, o.valid_from FROM material_price o
     WHERE o.material_supplier_id = mp.material_supplier_id AND o.variant_id = mp.variant_id
       AND o.status = 'APPROVED' AND o.valid_to IS NULL
     ORDER BY o.valid_from DESC LIMIT 1
  ) cur ON true
 WHERE mp.status = 'PROPOSED';

-- ---------------------------------------------------------------- Beranda Manager Costing: satu baris per pengajuan
-- ref_id = batch_id (dibuka di page Persetujuan Harga). factory_id untuk filter pabrik.
DROP VIEW IF EXISTS v_worklist_admin;
CREATE VIEW v_worklist_admin AS
SELECT 'PRICE'::text AS kind, p.batch_id AS ref_id,
       (array_agg(p.material_id))[1] AS material_id,
       string_agg(DISTINCT p.material_name, ', ') AS title,
       'Supplier ' || string_agg(DISTINCT p.supplier_name, ', ') || ' · ' || count(*) || ' harga' AS detail,
       string_agg(DISTINCT p.currency || ' ' || trim_scale(p.price)::text, ' / ') AS amount_text,
       (array_agg(p.created_by ORDER BY p.created_at))[1] AS proposed_by,
       min(p.created_at) AS proposed_at,
       (array_agg(p.factory_id))[1] AS factory_id
  FROM v_price_pending p
 GROUP BY p.batch_id;

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'kolom variant_id / batch_id' AS cek,
       (SELECT string_agg(column_name || ':' || is_nullable, ', ' ORDER BY column_name) FROM information_schema.columns
         WHERE table_name = 'material_price' AND column_name IN ('variant_id', 'batch_id')) AS hasil
UNION ALL SELECT 'uq_price_one_proposed', (SELECT indexdef FROM pg_indexes WHERE indexname = 'uq_price_one_proposed')
UNION ALL SELECT 'fungsi lama (harus 0)', count(*)::text FROM pg_proc
           WHERE proname IN ('fn_price_add', 'fn_price_approve', 'fn_price_reject')
UNION ALL SELECT 'fungsi baru', string_agg(proname, ', ' ORDER BY proname) FROM pg_proc
           WHERE proname IN ('fn_price_propose', 'fn_price_copy', 'fn_price_decide', 'fn_price_cancel', 'fn_price_end',
                             'fn_price_activate', 'fn_price_state', 'fn_uuid_list')
UNION ALL SELECT 'fn_price_lookup (harus 2 versi)', count(*)::text FROM pg_proc WHERE proname = 'fn_price_lookup'
UNION ALL SELECT 'view', string_agg(table_name, ', ' ORDER BY table_name) FROM information_schema.views
           WHERE table_name IN ('v_material_price', 'v_price_pending', 'v_worklist_admin')
UNION ALL SELECT 'uji fn_uuid_list', array_length(fn_uuid_list('["00000000-0000-0000-0000-000000000001","00000000-0000-0000-0000-000000000001"]'), 1)::text;


-- #################################################################### R4_model_specsheet
DO $$ BEGIN RAISE NOTICE 'mulai R4_model_specsheet'; END $$;

-- ============================================================================
-- R4 — Model tanpa kode + Specsheet per varian (keputusan user 8 Okt 2026, PLAN.md §2 "Revisi besar" & §6 R4)
-- Bagian dari sql/R_revisi_semua.sql (urutan R3 -> R7). Jalankan lewat z_run_sql di app "DB Tools"
-- (Use prepared statements = OFF) SETELAH RESET_data_bisnis.sql. Aman diulang. Satu transaksi.
--
-- Aturan:
-- - Model: kode DIHAPUS, nama = identitas (unik per pabrik, boleh diubah). Pabrik model = pabrik user pembuat.
--   Kategori (wajib), Construction, Gender = pilihan bersama; Last, Outsole mold = pilihan pabrik model.
--   Ukuran = daftar angka bulat (grid ala kalender), sample size salah satu ukuran itu.
-- - Semua tulis model / season / article / lampiran / specsheet dicek pabriknya (fn_auth_in).
-- - Baris BOM = material INDUK + thickness. Sel per article = WARNA; varian (Material Code) dicari otomatis dari
--   induk + thickness + warna (hanya varian ACTIVE). Sel berwarna tanpa varian = SEL KUNING.
--   Varian baru / berubah -> sel draft yang cocok tersambung otomatis. Sel kosong = tidak dipakai
--   ('none', '-', 'n/a' tidak istimewa lagi). Kode varian boleh diketik di sel (diganti warnanya).
-- - Terbit specsheet ditolak bila: tidak ada article aktif, article tanpa baris, material INACTIVE, baris tanpa
--   supplier, SEL KUNING, supplier / supplier material INACTIVE (F10d). Usulan master tidak ada lagi.
-- - Varian yang sudah dipakai specsheet terbit: Material Code / warna / thickness dikunci (INACTIVE + varian baru).
-- - Pilihan model: nilai yang dipakai model ber-specsheet terbit tidak bisa diubah; ukuran yang dipakai model
--   tidak bisa diubah. INACTIVE selalu boleh (model lama tetap memakainya).
-- - Masa transisi: CBD (R5) masih membaca warna; material.material_code/thickness lama dihapus di R5.
-- ============================================================================

-- ---------------------------------------------------------------- Pengaman
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'material_price' AND column_name = 'variant_id') THEN
    RAISE EXCEPTION 'Bagian R3 belum dijalankan. Jalankan file revisi dari awal.';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'product_model' AND column_name = 'code')
     AND EXISTS (SELECT 1 FROM product_model) THEN
    RAISE EXCEPTION 'Masih ada model uji dari sebelum R4 (berkode). Jalankan RESET_data_bisnis.sql dulu (user & pabrik tetap tersimpan).';
  END IF;
END;
$$;

-- View yang membaca kolom yang diubah — semuanya dibuat ulang di bawah
DROP VIEW IF EXISTS v_worklist_spec, v_revision_checklist, v_worklist_cbd, v_worklist_price_gap,
                    v_recent_published, v_model_list, v_bom_grid;

-- ---------------------------------------------------------------- Model: struktur baru
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'product_model' AND column_name = 'code') THEN
    ALTER TABLE product_model DROP CONSTRAINT IF EXISTS uq_model_code;
    ALTER TABLE product_model
      DROP COLUMN code, DROP COLUMN factory, DROP COLUMN category, DROP COLUMN outsole_mold, DROP COLUMN last_no,
      DROP COLUMN construction, DROP COLUMN size_range, DROP COLUMN sample_size;
    ALTER TABLE product_model
      ADD COLUMN factory_id      uuid NOT NULL REFERENCES factory(id),
      ADD COLUMN name_key        text GENERATED ALWAYS AS (fn_normalize(name)) STORED,
      ADD COLUMN category_id     uuid REFERENCES model_option(id),
      ADD COLUMN construction_id uuid REFERENCES model_option(id),
      ADD COLUMN gender_id       uuid REFERENCES model_option(id),
      ADD COLUMN last_id         uuid REFERENCES model_option(id),
      ADD COLUMN outsole_mold_id uuid REFERENCES model_option(id),
      ADD COLUMN sizes           integer[],
      ADD COLUMN sample_size     integer;
    ALTER TABLE product_model ADD CONSTRAINT uq_model_name UNIQUE (factory_id, name_key);
  END IF;
END;
$$;
CREATE INDEX IF NOT EXISTS idx_model_factory ON product_model (factory_id);

-- Kolom generated (name_key) masih NULL di BEFORE trigger -> dihitung sendiri.
CREATE OR REPLACE FUNCTION fn_model_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other text;
BEGIN
  NEW.name := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  IF NEW.name = '' THEN
    RAISE EXCEPTION 'Nama model wajib diisi.';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.factory_id IS DISTINCT FROM OLD.factory_id THEN
    RAISE EXCEPTION 'Pabrik model tidak bisa diubah.';
  END IF;
  SELECT name INTO v_other FROM product_model
   WHERE factory_id = NEW.factory_id AND name_key = fn_normalize(NEW.name) AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Model "%" sudah ada di pabrik ini.', v_other;
  END IF;
  NEW.sizes := nullif(ARRAY(SELECT DISTINCT x FROM unnest(coalesce(NEW.sizes, ARRAY[]::integer[])) AS x
                             WHERE x IS NOT NULL ORDER BY x), ARRAY[]::integer[]);
  IF EXISTS (SELECT 1 FROM unnest(coalesce(NEW.sizes, ARRAY[]::integer[])) AS x WHERE x < 1 OR x > 99) THEN
    RAISE EXCEPTION 'Ukuran harus angka bulat 1–99.';
  END IF;
  IF NEW.sample_size IS NOT NULL AND NOT (NEW.sample_size = ANY (coalesce(NEW.sizes, ARRAY[]::integer[]))) THEN
    RAISE EXCEPTION 'Sample size % harus salah satu ukuran model.', NEW.sample_size;
  END IF;
  RETURN NEW;
END;
$$;

-- Huruf kapital otomatis (F10b) tanpa kode model
CREATE OR REPLACE FUNCTION fn_upper_names() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_TABLE_NAME IN ('supplier', 'component') THEN
    NEW.name := upper(NEW.name);
  ELSIF TG_TABLE_NAME = 'material' THEN
    NEW.name := upper(NEW.name);
    NEW.category := upper(NEW.category);
  ELSIF TG_TABLE_NAME = 'product_model' THEN
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

-- "35, 36, 37, 38, 40, 41" -> "35–38, 40–41"
CREATE OR REPLACE FUNCTION fn_size_label(p integer[]) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v     integer[] := ARRAY(SELECT DISTINCT x FROM unnest(coalesce(p, ARRAY[]::integer[])) AS x WHERE x IS NOT NULL ORDER BY x);
  parts text[] := ARRAY[]::text[];
  s     integer;
  e     integer;
  i     integer;
BEGIN
  IF cardinality(v) = 0 THEN
    RETURN NULL;
  END IF;
  s := v[1];
  e := v[1];
  FOR i IN 2 .. cardinality(v) LOOP
    IF v[i] = e + 1 THEN
      e := v[i];
    ELSE
      parts := parts || CASE WHEN s = e THEN s::text ELSE s::text || '–' || e::text END;
      s := v[i];
      e := v[i];
    END IF;
  END LOOP;
  parts := parts || CASE WHEN s = e THEN s::text ELSE s::text || '–' || e::text END;
  RETURN array_to_string(parts, ', ');
END;
$$;

-- ---------------------------------------------------------------- Pabrik objek & penjaga tulis
CREATE OR REPLACE FUNCTION fn_model_factory(p_model_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT factory_id FROM product_model WHERE id = p_model_id $$;

CREATE OR REPLACE FUNCTION fn_sheet_factory(p_specsheet_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT pm.factory_id FROM specsheet sh JOIN product_model pm ON pm.id = sh.model_id WHERE sh.id = p_specsheet_id
$$;

CREATE OR REPLACE FUNCTION fn_article_factory(p_article_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT pm.factory_id FROM article a JOIN specsheet sh ON sh.id = a.specsheet_id
    JOIN product_model pm ON pm.id = sh.model_id WHERE a.id = p_article_id
$$;

CREATE OR REPLACE FUNCTION fn_rev_factory(p_revision_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT pm.factory_id FROM specsheet_revision r JOIN specsheet sh ON sh.id = r.specsheet_id
    JOIN product_model pm ON pm.id = sh.model_id WHERE r.id = p_revision_id
$$;

CREATE OR REPLACE FUNCTION fn_line_factory(p_line_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT fn_rev_factory(revision_id) FROM bom_line WHERE id = p_line_id $$;

-- Login + izin + data milik pabrik user. p_factory NULL = data tidak ditemukan.
CREATE OR REPLACE FUNCTION fn_auth_in(p_token text, p_perm text, p_factory uuid) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, p_perm);
BEGIN
  IF p_factory IS NULL THEN
    RAISE EXCEPTION 'Data tidak ditemukan. Muat ulang halaman.';
  END IF;
  PERFORM fn_assert_factory(v_email, p_factory);
  RETURN v_email;
END;
$$;

-- ---------------------------------------------------------------- Simpan model
-- Pilihan model untuk field p_kind: harus jenis itu, milik pabrik model (LAST/OUTSOLE_MOLD), dan ACTIVE
-- (kecuali nilai lama yang tidak diubah).
CREATE OR REPLACE FUNCTION fn_model_option_ref(p_id uuid, p_kind text, p_factory uuid, p_old uuid) RETURNS void
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_opt model_option%ROWTYPE;
BEGIN
  IF p_id IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO v_opt FROM model_option WHERE id = p_id;
  IF NOT FOUND OR v_opt.kind <> p_kind THEN
    RAISE EXCEPTION 'Pilihan % tidak valid. Muat ulang halaman.', fn_option_kind_label(p_kind);
  END IF;
  IF v_opt.factory_id IS NOT NULL AND v_opt.factory_id IS DISTINCT FROM p_factory THEN
    RAISE EXCEPTION '% "%" milik pabrik lain.', fn_option_kind_label(p_kind), v_opt.value;
  END IF;
  IF v_opt.status = 'INACTIVE' AND p_id IS DISTINCT FROM p_old THEN
    RAISE EXCEPTION '% "%" sudah INACTIVE.', fn_option_kind_label(p_kind), v_opt.value;
  END IF;
END;
$$;

-- p_id NULL = tambah (pabrik = pabrik user). p_sizes = '[37, 38, 39]'.
CREATE OR REPLACE FUNCTION fn_model_save(
  p_token text, p_id uuid, p_name text, p_category_id uuid, p_construction_id uuid, p_gender_id uuid,
  p_last_id uuid, p_outsole_mold_id uuid, p_sizes jsonb, p_sample_size integer
) RETURNS uuid
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

-- Model + nama pilihan. Kolom lama (factory, category, construction, last_no, outsole_mold, size_range, sample_size)
-- dipertahankan sebagai teks supaya page Specsheet / CBD / export tetap membaca nama yang sama.
DROP VIEW IF EXISTS v_model;
CREATE VIEW v_model AS
SELECT pm.id, pm.factory_id, f.name AS factory_name, f.name AS factory, pm.name, pm.name_key,
       oc.value AS category, ok.value AS construction, og.value AS gender, ol.value AS last_no, oo.value AS outsole_mold,
       pm.sizes, fn_size_label(pm.sizes) AS size_range, pm.sample_size::text AS sample_size,
       pm.category_id, pm.construction_id, pm.gender_id, pm.last_id, pm.outsole_mold_id,
       pm.created_at, pm.created_by, pm.updated_at, pm.updated_by
  FROM product_model pm
  JOIN factory f ON f.id = pm.factory_id
  LEFT JOIN model_option oc ON oc.id = pm.category_id
  LEFT JOIN model_option ok ON ok.id = pm.construction_id
  LEFT JOIN model_option og ON og.id = pm.gender_id
  LEFT JOIN model_option ol ON ol.id = pm.last_id
  LEFT JOIN model_option oo ON oo.id = pm.outsole_mold_id;

-- ---------------------------------------------------------------- Season, article, lampiran (dengan cek pabrik)
CREATE OR REPLACE FUNCTION fn_season_add(p_token text, p_model_id uuid, p_season text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_model', fn_model_factory(p_model_id));
  v_id    uuid;
BEGIN
  INSERT INTO specsheet (model_id, season, updated_by) VALUES (p_model_id, p_season, v_email) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- p_id NULL = tambah ke p_specsheet_id
CREATE OR REPLACE FUNCTION fn_article_save(p_token text, p_id uuid, p_specsheet_id uuid, p_code text, p_colorway text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text;
  v_id    uuid;
BEGIN
  IF p_id IS NULL THEN
    v_email := fn_auth_in(p_token, 'edit_model', fn_sheet_factory(p_specsheet_id));
    INSERT INTO article (specsheet_id, code, colorway, updated_by)
    VALUES (p_specsheet_id, p_code, p_colorway, v_email) RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  v_email := fn_auth_in(p_token, 'edit_model', fn_article_factory(p_id));
  UPDATE article SET code = p_code, colorway = p_colorway, updated_by = v_email WHERE id = p_id;
  RETURN p_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_article_delete(p_token text, p_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_model', fn_article_factory(p_id));
BEGIN
  DELETE FROM article WHERE id = p_id;
  RETURN p_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_attachment_add(
  p_token text, p_article_id uuid, p_file_name text, p_base64 text, p_note text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email   text := fn_auth_in(p_token, 'edit_model', fn_article_factory(p_article_id));
  v_content bytea;
  v_mime    text;
  v_name    text := btrim(coalesce(p_file_name, ''));
  v_id      uuid;
BEGIN
  IF coalesce(p_base64, '') = '' THEN
    RAISE EXCEPTION 'Pilih file yang akan diunggah.';
  END IF;
  BEGIN
    v_content := decode(regexp_replace(regexp_replace(p_base64, '^data:[^,]*,', ''), '\s', '', 'g'), 'base64');
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'File tidak terbaca (format Base64 tidak valid).';
  END;
  IF length(v_content) > 5242880 THEN
    RAISE EXCEPTION 'Ukuran file % MB, maksimal 5 MB.', round(length(v_content) / 1048576.0, 1);
  END IF;
  v_mime := CASE
    WHEN substring(v_content FROM 1 FOR 3) = '\xffd8ff'::bytea           THEN 'image/jpeg'
    WHEN substring(v_content FROM 1 FOR 8) = '\x89504e470d0a1a0a'::bytea THEN 'image/png'
    WHEN substring(v_content FROM 1 FOR 5) = '\x255044462d'::bytea       THEN 'application/pdf'
  END;
  IF v_mime IS NULL THEN
    RAISE EXCEPTION 'Jenis file tidak didukung. Hanya JPG, PNG, atau PDF.';
  END IF;
  IF v_name = '' THEN
    v_name := 'lampiran' || CASE v_mime WHEN 'image/jpeg' THEN '.jpg' WHEN 'image/png' THEN '.png' ELSE '.pdf' END;
  END IF;
  INSERT INTO article_attachment (article_id, file_name, mime_type, size_bytes, content, note, updated_by)
  VALUES (p_article_id, v_name, v_mime, length(v_content), v_content,
          nullif(btrim(coalesce(p_note, '')), ''), v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_attachment_delete(p_token text, p_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_model',
                             fn_article_factory((SELECT article_id FROM article_attachment WHERE id = p_id)));
BEGIN
  DELETE FROM article_attachment WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- ---------------------------------------------------------------- BOM: thickness di baris, varian di sel
ALTER TABLE bom_line ADD COLUMN IF NOT EXISTS thickness text;     -- teks ERP (fn_clean_thickness), NULL = tanpa

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'bom_cell' AND column_name = 'variant_id') THEN
    -- is_used lama menganggap none / - / n/a = kosong; sekarang hanya sel kosong = tidak dipakai
    ALTER TABLE bom_cell DROP COLUMN is_used;
    ALTER TABLE bom_cell ADD COLUMN is_used boolean GENERATED ALWAYS AS (btrim(coalesce(color, '')) <> '') STORED;
    ALTER TABLE bom_cell ADD COLUMN variant_id uuid REFERENCES material_variant(id);
  END IF;
END;
$$;
CREATE INDEX IF NOT EXISTS idx_bom_cell_variant ON bom_cell (variant_id);

-- Varian ACTIVE untuk induk + thickness + warna (NULL = belum terdaftar -> sel kuning)
CREATE OR REPLACE FUNCTION fn_bom_variant_for(p_material_id uuid, p_thickness text, p_color text) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT v.id FROM material_variant v
   WHERE v.material_id = p_material_id
     AND v.thickness_key = fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''))
     AND v.color_key = fn_normalize(p_color)
     AND v.status = 'ACTIVE'
   LIMIT 1
$$;

-- Sel: warna dirapikan (huruf besar) + varian dicari ulang setiap ditulis
CREATE OR REPLACE FUNCTION fn_bom_cell_variant() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_line record;
BEGIN
  NEW.color := nullif(upper(btrim(regexp_replace(coalesce(NEW.color, ''), '\s+', ' ', 'g'))), '');
  IF NEW.color IS NULL THEN
    NEW.variant_id := NULL;
    RETURN NEW;
  END IF;
  SELECT material_id, thickness INTO v_line FROM bom_line WHERE id = NEW.bom_line_id;
  NEW.variant_id := fn_bom_variant_for(v_line.material_id, v_line.thickness, NEW.color);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_bom_cell_variant ON bom_cell;
CREATE TRIGGER trg_bom_cell_variant BEFORE INSERT OR UPDATE ON bom_cell
  FOR EACH ROW EXECUTE FUNCTION fn_bom_cell_variant();

-- Varian baru / berubah -> sel DRAFT induk ini yang belum tersambung (atau tersambung ke varian ini) dicari ulang
CREATE OR REPLACE FUNCTION fn_variant_relink() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  UPDATE bom_cell bc
     SET color = bc.color
    FROM bom_line l
    JOIN specsheet_revision r ON r.id = l.revision_id AND r.status = 'DRAFT'
   WHERE bc.bom_line_id = l.id AND l.material_id = NEW.material_id AND l.is_active
     AND bc.color IS NOT NULL
     AND (bc.variant_id IS NULL OR bc.variant_id = NEW.id);
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_variant_relink ON material_variant;
CREATE TRIGGER trg_variant_relink AFTER INSERT OR UPDATE ON material_variant
  FOR EACH ROW EXECUTE FUNCTION fn_variant_relink();

-- ---------------------------------------------------------------- BOM: pemeriksaan
-- Material untuk baris BOM: ada, milik pabrik revisi, tidak INACTIVE.
DROP FUNCTION IF EXISTS fn_bom_check_material(uuid);
CREATE OR REPLACE FUNCTION fn_bom_check_material(p_material_id uuid, p_factory uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_mat material%ROWTYPE;
BEGIN
  SELECT * INTO v_mat FROM material WHERE id = p_material_id;
  IF NOT FOUND OR v_mat.factory_id IS DISTINCT FROM p_factory THEN
    RAISE EXCEPTION 'Material wajib dipilih dari Master Material pabrik ini.';
  END IF;
  IF v_mat.status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Material % sudah INACTIVE. Pilih material lain.', v_mat.name;
  END IF;
END;
$$;

-- Supplier baris: harus ACTIVE; link material-supplier dibuat otomatis (fn_ensure_link menolak link INACTIVE).
CREATE OR REPLACE FUNCTION fn_bom_check_supplier(p_material_id uuid, p_supplier_id uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_sup supplier%ROWTYPE;
BEGIN
  IF p_supplier_id IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO v_sup FROM supplier WHERE id = p_supplier_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Supplier tidak ada di Master Supplier.';
  END IF;
  IF v_sup.status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Supplier % sudah nonaktif. Pilih supplier lain.', v_sup.name;
  END IF;
  PERFORM fn_ensure_link(p_material_id, p_supplier_id);
END;
$$;

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
  v_email  text := fn_auth_in(p_token, 'edit_specsheet', fn_sheet_factory(p_specsheet_id));
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
    -- warna disalin; varian dicari ulang dari master sekarang (trigger) -> varian yang sudah INACTIVE jadi kuning
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

CREATE OR REPLACE FUNCTION fn_revision_delete_draft(p_token text, p_revision_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_rev_factory(p_revision_id));
  v_rev   specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
BEGIN
  DELETE FROM specsheet_revision WHERE id = v_rev.id;
  RETURN v_rev.id;
END;
$$;

-- ---------------------------------------------------------------- Baris BOM
-- Komponen master ACTIVE (p_component_id) atau lokal (p_local_no + p_local_name). Material = induk + thickness.
-- p_fill_color: isi warna ini ke semua article aktif (dipakai saat Material Code diketik di baris tambah).
DROP FUNCTION IF EXISTS fn_bom_add_line(text, uuid, uuid, integer, text, uuid, uuid, text);
CREATE OR REPLACE FUNCTION fn_bom_add_line(
  p_token text, p_revision_id uuid, p_component_id uuid, p_local_no integer, p_local_name text,
  p_material_id uuid, p_thickness text, p_supplier_id uuid, p_process text, p_fill_color text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_factory uuid := fn_rev_factory(p_revision_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_rev     specsheet_revision%ROWTYPE := fn_revision_draft(p_revision_id);
  v_comp    component%ROWTYPE;
  v_name    text := nullif(btrim(regexp_replace(coalesce(p_local_name, ''), '\s+', ' ', 'g')), '');
  v_thick   text := fn_clean_thickness(p_thickness);
  v_fill    text := nullif(btrim(coalesce(p_fill_color, '')), '');
  v_id      uuid;
BEGIN
  PERFORM fn_bom_check_material(p_material_id, v_factory);
  IF p_component_id IS NOT NULL THEN
    SELECT * INTO v_comp FROM component WHERE id = p_component_id;
    IF NOT FOUND OR v_comp.status <> 'ACTIVE' THEN
      RAISE EXCEPTION 'Komponen master tidak ditemukan atau INACTIVE. Untuk komponen baru, pakai komponen lokal.';
    END IF;
    IF EXISTS (SELECT 1 FROM bom_line WHERE revision_id = v_rev.id AND is_active AND parent_line_key IS NULL
                                        AND component_id = p_component_id AND material_id = p_material_id
                                        AND thickness IS NOT DISTINCT FROM v_thick) THEN
      RAISE EXCEPTION 'Komponen % + material ini (thickness sama) sudah ada di revisi ini.', v_comp.number;
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
  PERFORM fn_bom_check_supplier(p_material_id, p_supplier_id);

  INSERT INTO bom_line (revision_id, line_key, component_id, local_component_no, local_component_name,
                        material_id, thickness, supplier_id, process, sort_order, updated_by)
  VALUES (v_rev.id, gen_random_uuid(), p_component_id,
          CASE WHEN p_component_id IS NULL THEN p_local_no END,
          CASE WHEN p_component_id IS NULL THEN v_name END,
          p_material_id, v_thick, p_supplier_id, nullif(btrim(coalesce(p_process, '')), ''),
          coalesce((SELECT max(sort_order) FROM bom_line WHERE revision_id = v_rev.id), 0) + 1, v_email)
  RETURNING id INTO v_id;
  PERFORM fn_bom_create_cells(v_id, v_email);
  IF v_fill IS NOT NULL THEN
    UPDATE bom_cell SET color = v_fill, updated_by = v_email WHERE bom_line_id = v_id;
  END IF;
  RETURN v_id;
END;
$$;

DROP FUNCTION IF EXISTS fn_bom_add_sub(text, uuid, text, uuid, uuid, text);
CREATE OR REPLACE FUNCTION fn_bom_add_sub(
  p_token text, p_parent_line_id uuid, p_sub_name text, p_material_id uuid, p_thickness text, p_supplier_id uuid,
  p_process text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_factory uuid := fn_line_factory(p_parent_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_parent  bom_line%ROWTYPE;
  v_name    text := nullif(btrim(regexp_replace(coalesce(p_sub_name, ''), '\s+', ' ', 'g')), '');
  v_id      uuid;
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
  PERFORM fn_bom_check_material(p_material_id, v_factory);
  PERFORM fn_bom_check_supplier(p_material_id, p_supplier_id);

  INSERT INTO bom_line (revision_id, line_key, parent_line_key, sub_seq, sub_name, material_id, thickness, supplier_id,
                        process, sort_order, updated_by)
  VALUES (v_parent.revision_id, gen_random_uuid(), v_parent.line_key,
          coalesce((SELECT max(sub_seq) FROM bom_line
                     WHERE revision_id = v_parent.revision_id AND parent_line_key = v_parent.line_key), 0) + 1,
          v_name, p_material_id, fn_clean_thickness(p_thickness), p_supplier_id, nullif(btrim(coalesce(p_process, '')), ''),
          v_parent.sort_order, v_email)
  RETURNING id INTO v_id;
  PERFORM fn_bom_create_cells(v_id, v_email);
  RETURN v_id;
END;
$$;

-- Ganti material (induk dan/atau thickness): baris lama nonaktif, baris baru mewarisi komponen/supplier/remarks/warna.
DROP FUNCTION IF EXISTS fn_bom_replace_material(text, uuid, uuid);
CREATE OR REPLACE FUNCTION fn_bom_replace_material(p_token text, p_line_id uuid, p_material_id uuid, p_thickness text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_factory uuid := fn_line_factory(p_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_old     bom_line%ROWTYPE;
  v_thick   text := fn_clean_thickness(p_thickness);
  v_key     uuid := gen_random_uuid();
  v_id      uuid;
BEGIN
  SELECT * INTO v_old FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_old.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_old.revision_id);
  IF v_old.material_id = p_material_id AND v_old.thickness IS NOT DISTINCT FROM v_thick THEN
    RAISE EXCEPTION 'Material dan thickness baru sama dengan yang sekarang.';
  END IF;
  PERFORM fn_bom_check_material(p_material_id, v_factory);
  IF v_old.parent_line_key IS NULL AND EXISTS (
       SELECT 1 FROM bom_line WHERE revision_id = v_old.revision_id AND is_active AND parent_line_key IS NULL
          AND id <> v_old.id AND material_id = p_material_id AND thickness IS NOT DISTINCT FROM v_thick
          AND component_id IS NOT DISTINCT FROM v_old.component_id
          AND local_component_no IS NOT DISTINCT FROM v_old.local_component_no) THEN
    RAISE EXCEPTION 'Komponen ini dengan material + thickness tersebut sudah ada di revisi ini.';
  END IF;
  IF v_old.material_id <> p_material_id THEN
    PERFORM fn_bom_check_supplier(p_material_id, v_old.supplier_id);
  END IF;

  UPDATE bom_line SET is_active = false, updated_by = v_email WHERE id = v_old.id;
  INSERT INTO bom_line (revision_id, line_key, origin_line_key, replaces_line_key, component_id,
                        local_component_no, local_component_name, parent_line_key, sub_seq, sub_name,
                        material_id, thickness, supplier_id, process, sort_order, updated_by)
  VALUES (v_old.revision_id, v_key, v_old.origin_line_key, v_old.line_key, v_old.component_id,
          v_old.local_component_no, v_old.local_component_name, v_old.parent_line_key, v_old.sub_seq,
          v_old.sub_name, p_material_id, v_thick, v_old.supplier_id, v_old.process, v_old.sort_order, v_email)
  RETURNING id INTO v_id;
  INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
  SELECT v_id, article_id, color, v_email FROM bom_cell WHERE bom_line_id = v_old.id;
  PERFORM fn_bom_create_cells(v_id, v_email);
  UPDATE bom_line SET parent_line_key = v_key, updated_by = v_email
   WHERE revision_id = v_old.revision_id AND parent_line_key = v_old.line_key AND is_active;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_bom_set_supplier(p_token text, p_line_id uuid, p_supplier_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  PERFORM fn_bom_check_supplier(v_line.material_id, p_supplier_id);
  UPDATE bom_line SET supplier_id = p_supplier_id, updated_by = v_email WHERE id = v_line.id;
  RETURN v_line.id;
END;
$$;

-- Remarks (dulu UPDATE langsung dari query a_bom_set_process)
CREATE OR REPLACE FUNCTION fn_bom_set_process(p_token text, p_line_id uuid, p_process text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  UPDATE bom_line SET process = nullif(btrim(coalesce(p_process, '')), ''), updated_by = v_email WHERE id = v_line.id;
  RETURN v_line.id;
END;
$$;

-- Sel: warna, atau Material Code varian (harus induk + thickness baris ini -> diganti warnanya). Kosong = tidak dipakai.
CREATE OR REPLACE FUNCTION fn_bom_cell_set(p_token text, p_line_id uuid, p_article_id uuid, p_color text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_factory uuid := fn_line_factory(p_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_line    bom_line%ROWTYPE;
  v_color   text := nullif(upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g'))), '');
  v_var     record;
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
  IF v_color IS NOT NULL THEN
    SELECT v.material_id, v.thickness, v.thickness_key, v.color, v.status, m.name INTO v_var
      FROM material_variant v JOIN material m ON m.id = v.material_id
     WHERE v.factory_id = v_factory AND v.code = v_color;
    IF FOUND THEN
      IF v_var.material_id <> v_line.material_id
         OR v_var.thickness_key <> fn_normalize(coalesce(v_line.thickness, '')) THEN
        RAISE EXCEPTION 'Kode % adalah % · % · % — tidak cocok dengan material / thickness baris ini.',
          v_color, v_var.name, fn_thickness_label(v_var.thickness), v_var.color;
      END IF;
      IF v_var.status = 'INACTIVE' THEN
        RAISE EXCEPTION 'Kode % sudah INACTIVE.', v_color;
      END IF;
      v_color := v_var.color;
    END IF;
  END IF;
  INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
  VALUES (v_line.id, p_article_id, v_color, v_email)
  ON CONFLICT (bom_line_id, article_id) DO UPDATE SET color = EXCLUDED.color, updated_by = EXCLUDED.updated_by;
  RETURN v_line.id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_bom_delete_line(p_token text, p_line_id uuid) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
  v_subs  integer;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Baris tidak ditemukan atau sudah tidak aktif. Muat ulang halaman.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  DELETE FROM bom_line WHERE revision_id = v_line.revision_id AND parent_line_key = v_line.line_key;
  GET DIAGNOSTICS v_subs = ROW_COUNT;
  DELETE FROM bom_line WHERE id = v_line.id;
  RETURN v_subs + 1;
END;
$$;

CREATE OR REPLACE FUNCTION fn_rev_article_set(p_token text, p_revision_id uuid, p_article_id uuid, p_status text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_rev_factory(p_revision_id));
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

-- ---------------------------------------------------------------- Varian & pilihan: kunci setelah dipakai
-- true = varian dipakai dokumen terbit (specsheet; R5 menambah CBD)
CREATE OR REPLACE FUNCTION fn_variant_used_published(p_variant_id uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM bom_cell bc
                   JOIN bom_line l ON l.id = bc.bom_line_id
                   JOIN specsheet_revision r ON r.id = l.revision_id
                  WHERE bc.variant_id = p_variant_id AND r.status = 'PUBLISHED')
$$;

CREATE OR REPLACE FUNCTION fn_variant_save(
  p_token text, p_id uuid, p_material_id uuid, p_code text, p_color text, p_thickness text, p_status text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_mat   material%ROWTYPE;
  v_old   material_variant%ROWTYPE;
  v_id    uuid;
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Status varian wajib dipilih (ACTIVE / INACTIVE).';
  END IF;
  IF p_id IS NULL THEN
    SELECT * INTO v_mat FROM material WHERE id = p_material_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Material tidak ditemukan.';
    END IF;
    PERFORM fn_assert_factory(v_email, v_mat.factory_id);
    IF v_mat.status = 'INACTIVE' THEN
      RAISE EXCEPTION 'Material % sudah INACTIVE — aktifkan dulu sebelum menambah varian.', v_mat.name;
    END IF;
    INSERT INTO material_variant (material_id, factory_id, code, color, thickness, status, updated_by)
    VALUES (p_material_id, v_mat.factory_id, p_code, p_color, p_thickness, p_status, v_email)
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  SELECT * INTO v_old FROM material_variant WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Varian tidak ditemukan.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_old.factory_id);
  IF (upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g'))) IS DISTINCT FROM v_old.code
      OR upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g'))) IS DISTINCT FROM v_old.color
      OR fn_clean_thickness(p_thickness) IS DISTINCT FROM v_old.thickness)
     AND fn_variant_used_published(p_id) THEN
    RAISE EXCEPTION 'Varian % sudah dipakai di dokumen terbit — Material Code, warna, dan thickness tidak bisa diubah. Jadikan INACTIVE lalu daftarkan varian baru.', v_old.code;
  END IF;
  UPDATE material_variant
     SET code = p_code, color = p_color, thickness = p_thickness, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- Pilihan model: ubah nilai ditolak bila dipakai model ber-specsheet terbit (UKURAN: bila dipakai model mana pun).
CREATE OR REPLACE FUNCTION fn_option_save(
  p_token text, p_id uuid, p_kind text, p_value text, p_sort_order integer, p_status text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email   text := fn_auth(p_token, 'manage_master');
  v_factory uuid := fn_user_factory(v_email);
  v_old     model_option%ROWTYPE;
  v_used    text;
  v_id      uuid;
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Status pilihan wajib dipilih (ACTIVE / INACTIVE).';
  END IF;
  IF p_id IS NULL THEN
    IF p_kind IS NULL OR p_kind NOT IN ('KATEGORI', 'CONSTRUCTION', 'GENDER', 'UKURAN', 'LAST', 'OUTSOLE_MOLD') THEN
      RAISE EXCEPTION 'Pilih jenis pilihan.';
    END IF;
    IF fn_option_is_factory_kind(p_kind) AND v_factory IS NULL THEN
      RAISE EXCEPTION '% diisi per pabrik — akun Anda belum terhubung ke pabrik.', fn_option_kind_label(p_kind);
    END IF;
    INSERT INTO model_option (kind, factory_id, value, sort_order, status, updated_by)
    VALUES (p_kind, CASE WHEN fn_option_is_factory_kind(p_kind) THEN v_factory END, p_value, p_sort_order, p_status, v_email)
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  SELECT * INTO v_old FROM model_option WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pilihan tidak ditemukan.';
  END IF;
  IF v_old.factory_id IS NOT NULL THEN
    PERFORM fn_assert_factory(v_email, v_old.factory_id);
  END IF;
  IF fn_normalize(p_value) IS DISTINCT FROM v_old.value_key THEN
    IF v_old.kind = 'UKURAN' THEN
      SELECT string_agg(pm.name, ', ' ORDER BY pm.name) INTO v_used
        FROM product_model pm WHERE v_old.value ~ '^[0-9]+$' AND v_old.value::integer = ANY (pm.sizes);
    ELSE
      SELECT string_agg(DISTINCT pm.name, ', ') INTO v_used
        FROM product_model pm
       WHERE p_id IN (pm.category_id, pm.construction_id, pm.gender_id, pm.last_id, pm.outsole_mold_id)
         AND EXISTS (SELECT 1 FROM specsheet sh JOIN specsheet_revision r ON r.specsheet_id = sh.id
                      WHERE sh.model_id = pm.id AND r.status = 'PUBLISHED');
    END IF;
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION '% "%" sudah dipakai model %, nilainya tidak bisa diubah. Jadikan INACTIVE lalu tambah nilai baru.',
        fn_option_kind_label(v_old.kind), v_old.value, left(v_used, 200);
    END IF;
  END IF;
  UPDATE model_option SET value = p_value, sort_order = p_sort_order, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- ---------------------------------------------------------------- View grid BOM
-- cells = {"<article_id>": "WARNA"}, cell_codes = {"<article_id>": "MATERIAL CODE"} (sel tersambung),
-- yellow = sel berwarna tanpa varian di article aktif, material_code = kode-kode varian baris ini (export).
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
       l.material_id, cc.codes AS material_code, m.name AS material_name, l.thickness, m.uom, m.status AS material_status,
       l.supplier_id, s.name AS supplier_name, ms.status AS link_status,
       l.process, l.origin_line_key, l.replaces_line_key,
       coalesce(cc.cells, '{}'::jsonb) AS cells,
       s.status AS supplier_status,
       coalesce(cc.cell_codes, '{}'::jsonb) AS cell_codes,
       coalesce(cc.yellow, 0) AS yellow
  FROM bom_line l
  JOIN material m ON m.id = l.material_id
  LEFT JOIN component c ON c.id = l.component_id
  LEFT JOIN bom_line p ON p.revision_id = l.revision_id AND p.line_key = l.parent_line_key AND p.is_active
  LEFT JOIN component pc ON pc.id = p.component_id
  LEFT JOIN supplier s ON s.id = l.supplier_id
  LEFT JOIN material_supplier ms ON ms.material_id = l.material_id AND ms.supplier_id = l.supplier_id
  LEFT JOIN LATERAL (
    SELECT jsonb_object_agg(bc.article_id::text, bc.color) FILTER (WHERE bc.color IS NOT NULL) AS cells,
           jsonb_object_agg(bc.article_id::text, v.code) FILTER (WHERE v.id IS NOT NULL) AS cell_codes,
           string_agg(DISTINCT v.code, ', ') AS codes,
           (count(*) FILTER (WHERE bc.is_used AND bc.variant_id IS NULL AND ra.status = 'ACTIVE'))::integer AS yellow
      FROM bom_cell bc
      LEFT JOIN material_variant v ON v.id = bc.variant_id
      LEFT JOIN revision_article ra ON ra.revision_id = l.revision_id AND ra.article_id = bc.article_id
     WHERE bc.bom_line_id = l.id
  ) cc ON true
 WHERE l.is_active;

-- ---------------------------------------------------------------- Checklist & terbit specsheet
CREATE VIEW v_revision_checklist AS
SELECT x.*,
       (x.active_articles = 0 OR x.unused_articles IS NOT NULL OR x.inactive_materials IS NOT NULL
        OR x.no_supplier_lines > 0 OR x.yellow_cells > 0 OR x.inactive_suppliers IS NOT NULL) AS blocked
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
           (SELECT string_agg(DISTINCT m.name, ', ')
              FROM bom_line l JOIN material m ON m.id = l.material_id
             WHERE l.revision_id = r.id AND l.is_active AND m.status = 'INACTIVE') AS inactive_materials,
           (SELECT count(*)::int FROM bom_line l
             WHERE l.revision_id = r.id AND l.is_active AND l.supplier_id IS NULL) AS no_supplier_lines,
           (SELECT count(*)::int
              FROM bom_cell c
              JOIN bom_line l ON l.id = c.bom_line_id AND l.revision_id = r.id AND l.is_active
              JOIN revision_article ra ON ra.revision_id = r.id AND ra.article_id = c.article_id AND ra.status = 'ACTIVE'
             WHERE c.is_used AND c.variant_id IS NULL) AS yellow_cells,
           (SELECT left(string_agg(DISTINCT m.name || coalesce(' ' || l.thickness, '') || ' · ' || c.color, ', '), 300)
              FROM bom_cell c
              JOIN bom_line l ON l.id = c.bom_line_id AND l.revision_id = r.id AND l.is_active
              JOIN material m ON m.id = l.material_id
              JOIN revision_article ra ON ra.revision_id = r.id AND ra.article_id = c.article_id AND ra.status = 'ACTIVE'
             WHERE c.is_used AND c.variant_id IS NULL) AS yellow_list,
           (SELECT string_agg(DISTINCT s.name || ' (' || m.name || ')', ', ')
              FROM bom_line l
              JOIN supplier s ON s.id = l.supplier_id
              JOIN material m ON m.id = l.material_id
              LEFT JOIN material_supplier ms ON ms.material_id = l.material_id AND ms.supplier_id = l.supplier_id
             WHERE l.revision_id = r.id AND l.is_active
               AND (s.status = 'INACTIVE' OR ms.status = 'INACTIVE')) AS inactive_suppliers
      FROM specsheet_revision r
  ) x;

CREATE OR REPLACE FUNCTION fn_revision_publish(p_token text, p_revision_id uuid, p_category text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_specsheet', fn_rev_factory(p_revision_id));
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
  IF v_chk.yellow_cells > 0 THEN
    RAISE EXCEPTION 'Ada % sel warna yang belum punya Material Code (sel kuning): %. Daftarkan variannya dulu.',
      v_chk.yellow_cells, v_chk.yellow_list;
  END IF;
  IF v_chk.inactive_suppliers IS NOT NULL THEN
    RAISE EXCEPTION 'Ada supplier nonaktif: %. Ganti suppliernya dulu.', v_chk.inactive_suppliers;
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

-- ---------------------------------------------------------------- View model & worklist (tanpa kode model)
CREATE VIEW v_model_list AS
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

CREATE VIEW v_worklist_spec AS
SELECT 'DRAFT'::text AS kind,
       pm.id AS model_id, pm.name AS model_name, pm.factory_id,
       sh.id AS specsheet_id, sh.season,
       r.id AS revision_id, r.stage, r.revision_no,
       ck.line_count, ck.no_supplier_lines AS no_supplier, ck.active_articles AS article_count,
       ck.unused_articles, ck.inactive_materials,
       NULL::text AS article_codes, NULL::boolean AS has_revision,
       ck.yellow_cells, ck.inactive_suppliers
  FROM specsheet_revision r
  JOIN specsheet sh ON sh.id = r.specsheet_id
  JOIN product_model pm ON pm.id = sh.model_id
  JOIN v_revision_checklist ck ON ck.revision_id = r.id
 WHERE r.status = 'DRAFT'
UNION ALL
SELECT 'UNASSIGNED',
       pm.id, pm.name, pm.factory_id,
       sh.id, sh.season,
       NULL::uuid, NULL::text, NULL::integer,
       NULL::integer, NULL::integer, u.n,
       NULL::text, NULL::text,
       u.codes, EXISTS (SELECT 1 FROM specsheet_revision x WHERE x.specsheet_id = sh.id),
       NULL::integer, NULL::text
  FROM specsheet sh
  JOIN product_model pm ON pm.id = sh.model_id
  CROSS JOIN LATERAL (
    SELECT count(*)::integer AS n, string_agg(a.code, ', ' ORDER BY a.code) AS codes
      FROM article a
     WHERE a.specsheet_id = sh.id
       AND NOT EXISTS (SELECT 1 FROM revision_article ra WHERE ra.article_id = a.id)
  ) u
 WHERE u.n > 0;

CREATE VIEW v_worklist_cbd AS
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
           pm.id AS model_id, pm.name AS model_name, pm.factory_id,
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

-- Varian CATALOG + supplier yang dipakai (sel tersambung, article aktif) di specsheet terbit terakhir tiap season
-- tetapi belum punya harga berlaku (fn_price_lookup per varian). Dikelompokkan per material + supplier.
CREATE VIEW v_worklist_price_gap AS
SELECT m.id AS material_id, m.name AS material_name, m.factory_id,
       s.id AS supplier_id, s.name AS supplier_name,
       count(DISTINCT g.variant_id)::integer AS variant_count,
       string_agg(DISTINCT v.code, ', ') AS codes,
       string_agg(DISTINCT g.model_name, ', ') AS models,
       bool_or(EXISTS (SELECT 1 FROM material_price mp
                        JOIN material_supplier ms ON ms.id = mp.material_supplier_id
                       WHERE ms.material_id = g.material_id AND ms.supplier_id = g.supplier_id
                         AND mp.variant_id = g.variant_id AND mp.status = 'PROPOSED')) AS has_pending
  FROM (
    SELECT DISTINCT bl.material_id, bl.supplier_id, bc.variant_id, pm.name AS model_name
      FROM specsheet sh
      JOIN product_model pm ON pm.id = sh.model_id
      JOIN specsheet_revision r ON r.id = fn_spec_latest_pub(sh.id)
      JOIN bom_line bl ON bl.revision_id = r.id AND bl.is_active AND bl.supplier_id IS NOT NULL
      JOIN bom_cell bc ON bc.bom_line_id = bl.id AND bc.variant_id IS NOT NULL
      JOIN revision_article ra ON ra.revision_id = r.id AND ra.article_id = bc.article_id AND ra.status = 'ACTIVE'
  ) g
  JOIN material m ON m.id = g.material_id AND m.price_method = 'CATALOG'
  JOIN supplier s ON s.id = g.supplier_id
  JOIN material_variant v ON v.id = g.variant_id
 WHERE NOT EXISTS (SELECT 1 FROM fn_price_lookup(g.variant_id, g.supplier_id))
 GROUP BY m.id, m.name, m.factory_id, s.id, s.name;

CREATE VIEW v_recent_published AS
SELECT 'SPECSHEET'::text AS doc_type, r.id AS revision_id,
       pm.id AS model_id, pm.name AS model_name, pm.factory_id, f.name AS factory_name,
       sh.id AS specsheet_id, sh.season,
       NULL::uuid AS article_id, NULL::text AS article_code, NULL::text AS colorway,
       r.stage, r.revision_no, r.published_at, r.published_by, NULL::text AS sync_status
  FROM specsheet sh
  JOIN product_model pm ON pm.id = sh.model_id
  JOIN factory f ON f.id = pm.factory_id
  JOIN specsheet_revision r ON r.id = fn_spec_latest_pub(sh.id)
UNION ALL
SELECT 'CBD', c.id,
       pm.id, pm.name, pm.factory_id, f.name,
       sh.id, sh.season,
       a.id, a.code, a.colorway,
       c.stage, c.revision_no, c.published_at, c.published_by, c.sync_status
  FROM article a
  JOIN specsheet sh ON sh.id = a.specsheet_id
  JOIN product_model pm ON pm.id = sh.model_id
  JOIN factory f ON f.id = pm.factory_id
  JOIN LATERAL (
    SELECT x.id, x.stage, x.revision_no, x.published_at, x.published_by, x.sync_status
      FROM cbd_revision x
     WHERE x.article_id = a.id AND x.status = 'PUBLISHED'
     ORDER BY x.stage_order DESC, x.revision_no DESC LIMIT 1
  ) c ON true;

-- ---------------------------------------------------------------- Pilihan bawaan (RESET_data_bisnis ikut mengosongkan)
INSERT INTO model_option (kind, value, sort_order)
SELECT 'GENDER', v.value, v.ord
  FROM (VALUES ('LAKI-LAKI', 1), ('PEREMPUAN', 2), ('UNISEX', 3)) AS v(value, ord)
 WHERE NOT EXISTS (SELECT 1 FROM model_option o WHERE o.kind = 'GENDER' AND o.value_key = fn_normalize(v.value));
INSERT INTO model_option (kind, value)
SELECT 'UKURAN', g::text
  FROM generate_series(35, 47) AS g
 WHERE NOT EXISTS (SELECT 1 FROM model_option o WHERE o.kind = 'UKURAN' AND o.value_key = g::text);

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'kolom product_model.code (harus 0)' AS cek, count(*)::text AS hasil FROM information_schema.columns
 WHERE table_name = 'product_model' AND column_name = 'code'
UNION ALL SELECT 'kolom baru model', string_agg(column_name, ', ' ORDER BY column_name) FROM information_schema.columns
 WHERE table_name = 'product_model' AND column_name IN ('factory_id', 'category_id', 'sizes', 'sample_size', 'name_key')
UNION ALL SELECT 'bom_line.thickness / bom_cell.variant_id',
       (SELECT count(*) FROM information_schema.columns WHERE table_name = 'bom_line' AND column_name = 'thickness') || ' / '
       || (SELECT count(*) FROM information_schema.columns WHERE table_name = 'bom_cell' AND column_name = 'variant_id')
UNION ALL SELECT 'uji label ukuran', fn_size_label(ARRAY[44, 37, 38, 39, 40, 42, 43])
UNION ALL SELECT 'view', string_agg(table_name, ', ' ORDER BY table_name) FROM information_schema.views
 WHERE table_name IN ('v_model', 'v_model_list', 'v_bom_grid', 'v_revision_checklist', 'v_worklist_spec',
                      'v_worklist_cbd', 'v_worklist_price_gap', 'v_recent_published');


-- #################################################################### R5_cbd
DO $$ BEGIN RAISE NOTICE 'mulai R5_cbd'; END $$;

-- ============================================================================
-- R5 — CBD per varian, PO SMS, selling price keluar dari CBD (keputusan user 8 Okt 2026, PLAN.md §6 R5)
-- Bagian dari sql/R_revisi_semua.sql (urutan R3 -> R7). Aman diulang. Satu transaksi.
--
-- Aturan:
-- - Baris CBD membawa varian (Material Code) + thickness dari sel specsheet. Harga master dicari per
--   VARIAN + SUPPLIER (fn_price_lookup R3: hanya APPROVED dari supplier & link ACTIVE).
-- - Status harga baris: Belum ada harga / Menunggu persetujuan. CBD TIDAK BISA TERBIT selama ada baris yang
--   varian + suppliernya masih punya usulan harga menunggu persetujuan Manager Costing.
-- - Harga quotation ikut copy / revisi berikutnya / refresh bila VARIAN SAMA. Sinkron specsheet membandingkan
--   (baris, supplier, varian).
-- - PO SMS = Actual FOB × faktor stage (stage_setting, seed SMS = 1,25); faktor dibekukan di cbd_revision.po_factor
--   saat terbit. Target FOB tetap dibanding Actual FOB TANPA faktor.
-- - Selling price & Margin DIHAPUS dari CBD (Brand memakai kalkulator simulasi di layar, tidak disimpan).
-- - Semua tulis CBD dicek pabriknya (fn_auth_in). Manager Costing hanya membaca (tidak punya edit_cbd).
-- - Kolom lama dihapus: material.material_code, material.thickness, material_price.color/color_key,
--   fn_price_lookup versi warna.
-- ============================================================================

-- ---------------------------------------------------------------- Pengaman
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'bom_cell' AND column_name = 'variant_id') THEN
    RAISE EXCEPTION 'Bagian R4 belum dijalankan. Jalankan file revisi dari awal.';
  END IF;
  IF to_regclass('public.stage_setting') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'stage_setting' AND column_name = 'po_factor') THEN
    RAISE EXCEPTION 'Tabel "stage_setting" sudah ada di database dan bukan milik proyek ini. Hentikan dan hubungi pengembang.';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'cbd_revision' AND column_name = 'selling_price')
     AND EXISTS (SELECT 1 FROM cbd_revision) THEN
    RAISE EXCEPTION 'Masih ada CBD uji dari sebelum R5. Jalankan RESET_data_bisnis.sql dulu (user & pabrik tetap tersimpan).';
  END IF;
END;
$$;

-- View CBD yang dibuat ulang di bawah (urutan: yang bergantung dulu)
DROP VIEW IF EXISTS v_worklist_cbd, v_cbd_checklist, v_cbd_recap, v_cbd_price_check, v_cbd_line;

-- ---------------------------------------------------------------- Kolom
ALTER TABLE cbd_line
  ADD COLUMN IF NOT EXISTS variant_id uuid REFERENCES material_variant(id),
  ADD COLUMN IF NOT EXISTS thickness  text;
ALTER TABLE cbd_revision DROP COLUMN IF EXISTS selling_price;
ALTER TABLE cbd_revision ADD COLUMN IF NOT EXISTS po_factor numeric(6,4);    -- dibekukan saat terbit

CREATE TABLE IF NOT EXISTS stage_setting (
  stage     text PRIMARY KEY CHECK (stage IN ('PULL', 'SMS', 'GTM', 'PROD')),
  po_factor numeric(6,4) CHECK (po_factor IS NULL OR po_factor > 0),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text
);
SELECT fn_setup_table('stage_setting');
INSERT INTO stage_setting (stage, po_factor) VALUES ('PULL', NULL), ('SMS', 1.25), ('GTM', NULL), ('PROD', NULL)
ON CONFLICT (stage) DO NOTHING;

-- Kolom material lama (kode & thickness pindah ke varian sejak R2)
ALTER TABLE material DROP COLUMN IF EXISTS thickness_key;
ALTER TABLE material DROP COLUMN IF EXISTS thickness;
ALTER TABLE material DROP COLUMN IF EXISTS material_code;
CREATE OR REPLACE FUNCTION fn_material_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other record;
BEGIN
  NEW.name     := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  NEW.category := btrim(regexp_replace(coalesce(NEW.category, ''), '\s+', ' ', 'g'));
  NEW.uom      := upper(btrim(coalesce(NEW.uom, '')));
  IF NEW.factory_id IS NULL THEN RAISE EXCEPTION 'Pabrik material wajib diisi.'; END IF;
  IF NEW.name = ''          THEN RAISE EXCEPTION 'Nama material wajib diisi.'; END IF;
  IF NEW.category = ''      THEN RAISE EXCEPTION 'Kategori material wajib diisi.'; END IF;
  IF NEW.uom = ''           THEN RAISE EXCEPTION 'UoM wajib diisi.'; END IF;
  IF TG_OP = 'UPDATE' AND NEW.factory_id IS DISTINCT FROM OLD.factory_id THEN
    RAISE EXCEPTION 'Pabrik material tidak bisa diubah.';
  END IF;
  SELECT name, uom INTO v_other FROM material
   WHERE factory_id = NEW.factory_id AND name_key = fn_normalize(NEW.name) AND uom = NEW.uom AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material "%" (%) sudah ada di pabrik ini. Tambahkan varian di material itu.', v_other.name, v_other.uom;
  END IF;
  RETURN NEW;
END;
$$;

-- Harga per warna (F3) sudah tidak dipakai
DROP FUNCTION IF EXISTS fn_price_lookup(uuid, uuid, text, date);
ALTER TABLE material_price DROP COLUMN IF EXISTS color_key;
ALTER TABLE material_price DROP COLUMN IF EXISTS color;

-- ---------------------------------------------------------------- Helper
CREATE OR REPLACE FUNCTION fn_cbd_factory(p_cbd_revision_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT fn_article_factory(article_id) FROM cbd_revision WHERE id = p_cbd_revision_id $$;

CREATE OR REPLACE FUNCTION fn_cbd_line_factory(p_line_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT fn_cbd_factory(cbd_revision_id) FROM cbd_line WHERE id = p_line_id $$;

CREATE OR REPLACE FUNCTION fn_cbd_item_factory(p_item_id uuid) RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT fn_cbd_factory(cbd_revision_id) FROM cbd_cost_item WHERE id = p_item_id $$;

-- true = varian + supplier masih punya usulan harga menunggu persetujuan
CREATE OR REPLACE FUNCTION fn_price_pending(p_variant_id uuid, p_supplier_id uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM material_price mp JOIN material_supplier ms ON ms.id = mp.material_supplier_id
                  WHERE mp.variant_id = p_variant_id AND ms.supplier_id = p_supplier_id AND mp.status = 'PROPOSED')
$$;

-- Identitas baris untuk pencocokan copy/refresh: komponen + sub + material induk + thickness
DROP FUNCTION IF EXISTS fn_cbd_identity(uuid, integer, integer, text, uuid);
CREATE OR REPLACE FUNCTION fn_cbd_identity(p_component_id uuid, p_local_no integer, p_sub_seq integer,
                                           p_sub_name text, p_material_id uuid, p_thickness text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT concat_ws('|', coalesce(p_component_id::text, ''), coalesce(p_local_no::text, ''),
                   CASE WHEN p_sub_seq IS NOT NULL THEN fn_normalize(p_sub_name) ELSE '' END, p_material_id::text,
                   fn_normalize(coalesce(p_thickness, '')))
$$;

-- Varian dipakai dokumen terbit: specsheet (R4) atau CBD
CREATE OR REPLACE FUNCTION fn_variant_used_published(p_variant_id uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM bom_cell bc
                   JOIN bom_line l ON l.id = bc.bom_line_id
                   JOIN specsheet_revision r ON r.id = l.revision_id
                  WHERE bc.variant_id = p_variant_id AND r.status = 'PUBLISHED')
      OR EXISTS (SELECT 1 FROM cbd_line cl JOIN cbd_revision c ON c.id = cl.cbd_revision_id
                  WHERE cl.variant_id = p_variant_id AND c.status = 'PUBLISHED')
$$;

-- ---------------------------------------------------------------- Baris yang diharapkan (+ thickness, varian)
DROP FUNCTION IF EXISTS fn_cbd_expected_lines(uuid, uuid);
CREATE FUNCTION fn_cbd_expected_lines(p_article_id uuid, p_spec_rev_id uuid)
RETURNS TABLE (seq integer, line_key uuid, origin_line_key uuid, replaces_line_key uuid, component_id uuid,
               local_component_no integer, sub_seq integer, sub_name text, material_id uuid, thickness text,
               color text, variant_id uuid, supplier_id uuid, uom text, group_code text)
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
           l.sub_seq, l.sub_name, l.material_id, l.thickness, bc.color, bc.variant_id, l.supplier_id, m.uom
      FROM lines l
      LEFT JOIN lines p ON p.line_key = l.parent_line_key
      JOIN bom_cell bc ON bc.bom_line_id = l.id AND bc.article_id = p_article_id AND bc.is_used
      JOIN material m ON m.id = l.material_id
     WHERE EXISTS (SELECT 1 FROM revision_article ra
                    WHERE ra.revision_id = p_spec_rev_id AND ra.article_id = p_article_id AND ra.status = 'ACTIVE')
  )
  SELECT (row_number() OVER (ORDER BY x.top_no NULLS LAST, x.top_sort, x.is_sub, x.sub_seq))::integer,
         x.line_key, x.origin_line_key, x.replaces_line_key, x.component_id, x.local_no, x.sub_seq,
         CASE WHEN x.is_sub THEN x.sub_name END, x.material_id, x.thickness, x.color, x.variant_id, x.supplier_id,
         x.uom, fn_cbd_group_code(x.component_id, x.local_no)
    FROM x
$$;

-- ---------------------------------------------------------------- Isi baris CBD dari specsheet (+ sumber)
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
        -- harga quotation ikut bila VARIAN sama dan materialnya masih bermetode Quotation
        v_carry := s.price_source = 'QUOTATION' AND s.variant_id IS NOT DISTINCT FROM e.variant_id
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

-- ---------------------------------------------------------------- Buat / hapus revisi CBD
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

  -- Rekap (rate, target FOB) ikut dari sumber
  INSERT INTO cbd_revision (article_id, stage, revision_no, specsheet_revision_id, exchange_rate,
                            target_fob, source_cbd_revision_id, updated_by)
  VALUES (v_art.id, v_spec.stage, v_no, v_spec.id, v_src.exchange_rate,
          v_src.target_fob, v_src.id, v_email)
  RETURNING id INTO v_id;

  IF v_src.id IS NOT NULL THEN
    SELECT sp.season || ' / ' || a.code || ' / ' || v_src.stage || ' r' || v_src.revision_no INTO v_ref
      FROM article a JOIN specsheet sp ON sp.id = a.specsheet_id WHERE a.id = v_src.article_id;
    SELECT array_agg(l ORDER BY l.sort_order) INTO v_lines FROM cbd_line l WHERE l.cbd_revision_id = v_src.id;
    INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, remarks, is_default, sort_order, updated_by)
    SELECT v_id, c.item_type, c.name, c.amount, c.remarks, c.is_default, c.sort_order, v_email
      FROM cbd_cost_item c WHERE c.cbd_revision_id = v_src.id;
  END IF;
  PERFORM fn_cbd_cost_defaults(v_id, v_email);
  PERFORM fn_cbd_populate(v_id, v_art.id, v_spec.id, v_lines, p_mode = 'NEXT', v_ref, v_email);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_delete_draft(p_token text, p_cbd_revision_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev   cbd_revision%ROWTYPE;
BEGIN
  SELECT * INTO v_rev FROM cbd_revision WHERE id = p_cbd_revision_id FOR UPDATE;
  IF v_rev.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'Revisi CBD ini sudah diterbitkan dan tidak bisa dihapus.';
  END IF;
  DELETE FROM cbd_revision WHERE id = v_rev.id;
  RETURN v_rev.id;
END;
$$;

-- ---------------------------------------------------------------- Ubah baris / harga / biaya / rekap
CREATE OR REPLACE FUNCTION fn_cbd_line_set(p_token text, p_line_id uuid, p_field text, p_value numeric)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_line_factory(p_line_id));
  v_line  cbd_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM cbd_line WHERE id = p_line_id;
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

CREATE OR REPLACE FUNCTION fn_cbd_set_quotation(p_token text, p_line_id uuid, p_price numeric,
                                                p_currency text, p_reference text)
RETURNS uuid
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
                        price_reference = nullif(btrim(coalesce(p_reference, '')), ''), updated_by = v_email
     WHERE id = v_line.id;
  END IF;
  RETURN v_line.id;
END;
$$;

-- Override CATALOG sudah dihapus (F10b) — fungsi lama dipertahankan agar query lama memberi pesan jelas
CREATE OR REPLACE FUNCTION fn_cbd_clear_override(p_token text, p_line_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Override harga tidak dipakai lagi. Harga material katalog diisi lewat Master Material.';
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_header_set(p_token text, p_cbd_revision_id uuid, p_field text, p_value numeric)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev   cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
BEGIN
  IF p_field = 'RATE' THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION 'Exchange rate harus lebih besar dari 0 (kosongkan kalau belum ada).';
    END IF;
    UPDATE cbd_revision SET exchange_rate = p_value, updated_by = v_email WHERE id = v_rev.id;
  ELSIF p_field = 'TARGET_FOB' THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION 'Target FOB harus lebih besar dari 0 (kosongkan kalau belum ada).';
    END IF;
    UPDATE cbd_revision SET target_fob = p_value, updated_by = v_email WHERE id = v_rev.id;
  ELSE
    RAISE EXCEPTION 'Kolom tidak valid (selling price & margin tidak disimpan di CBD).';
  END IF;
  RETURN v_rev.id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_cost_add(p_token text, p_cbd_revision_id uuid, p_type text, p_name text,
                                           p_amount numeric, p_remarks text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev   cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
  v_id    uuid;
BEGIN
  IF coalesce(p_type, '') NOT IN ('LABOUR', 'AMORTIZATION', 'ADJUSTMENT', 'OTHER') THEN
    RAISE EXCEPTION 'Pilih jenis biaya.';
  END IF;
  PERFORM fn_cbd_check_cost(p_type, p_amount);
  INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, remarks, is_default, sort_order, updated_by)
  VALUES (v_rev.id, p_type, coalesce(nullif(btrim(coalesce(p_name, '')), ''), fn_cbd_cost_label(p_type)),
          coalesce(p_amount, 0), nullif(btrim(coalesce(p_remarks, '')), ''), false,
          (SELECT coalesce(max(sort_order), 0) + 1 FROM cbd_cost_item WHERE cbd_revision_id = v_rev.id), v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_cost_set(p_token text, p_item_id uuid, p_field text, p_value text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_item_factory(p_item_id));
  v_item  cbd_cost_item%ROWTYPE := fn_cbd_cost_item(p_item_id);
  v_text  text := nullif(btrim(coalesce(p_value, '')), '');
  v_num   numeric;
BEGIN
  IF p_field = 'NAME' THEN
    IF v_text IS NULL THEN
      RAISE EXCEPTION 'Uraian biaya wajib diisi.';
    END IF;
    UPDATE cbd_cost_item SET name = v_text, updated_by = v_email WHERE id = v_item.id;
  ELSIF p_field = 'AMOUNT' THEN
    IF v_text IS NOT NULL AND v_text !~ '^-?[0-9]+(\.[0-9]+)?$' THEN
      RAISE EXCEPTION 'Nilai biaya harus angka.';
    END IF;
    v_num := coalesce(v_text::numeric, 0);
    PERFORM fn_cbd_check_cost(v_item.item_type, v_num);
    UPDATE cbd_cost_item SET amount = v_num, updated_by = v_email WHERE id = v_item.id;
  ELSIF p_field = 'REMARKS' THEN
    UPDATE cbd_cost_item SET remarks = v_text, updated_by = v_email WHERE id = v_item.id;
  ELSE
    RAISE EXCEPTION 'Kolom tidak valid.';
  END IF;
  RETURN v_item.id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_cost_delete(p_token text, p_item_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_item_factory(p_item_id));
  v_item  cbd_cost_item%ROWTYPE := fn_cbd_cost_item(p_item_id);
BEGIN
  IF v_item.is_default THEN
    RAISE EXCEPTION 'Baris % selalu ada dan tidak bisa dihapus (isi 0 bila tidak dipakai).', v_item.name;
  END IF;
  DELETE FROM cbd_cost_item WHERE id = v_item.id;
  RETURN v_item.id;
END;
$$;

-- ---------------------------------------------------------------- View baris, cek harga, rekap, checklist
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
       cl.material_id, v.code AS material_code, m.name AS material_name, cl.thickness, m.price_method,
       cl.color, cl.supplier_id, s.name AS supplier_name, cl.uom, bl.process AS remarks,
       cl.yield_value, cl.usage_value, cl.loss_pct,
       cl.price_original, cl.currency, cl.price_source, cl.material_price_id,
       NULL::text AS master_price_color, mp.valid_from AS master_price_valid_from,
       cl.price_override_reason, cl.price_reference,
       x.price_usd, x.price_idr,
       cl.usage_value * x.price_idr * (1 + coalesce(cl.loss_pct, 0) / 100) AS cost_per_pair,
       cl.value_origin, cl.value_source_ref, cl.sort_order,
       cl.variant_id
  FROM cbd_line cl
  JOIN cbd_revision cr ON cr.id = cl.cbd_revision_id
  JOIN material m ON m.id = cl.material_id
  LEFT JOIN material_variant v ON v.id = cl.variant_id
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

-- Hanya revisi DRAFT, baris ACTIVE. price_gap = kenapa harga kosong; pending = ada usulan harga menunggu
-- untuk varian + supplier baris ini (memblokir terbit).
CREATE VIEW v_cbd_price_check AS
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
 WHERE r.status = 'DRAFT' AND l.status = 'ACTIVE';

-- po_factor: revisi terbit = faktor yang dibekukan; draft = faktor stage sekarang (stage_setting)
CREATE VIEW v_cbd_recap AS
SELECT r.id AS cbd_revision_id, r.status, r.exchange_rate, r.target_fob,
       t.material_cost, ci.labour, ci.amortization, ci.adjustment, ci.other, ci.items_total,
       f.actual_fob,
       f.actual_fob - r.target_fob AS variance,
       CASE WHEN r.target_fob IS NULL THEN NULL
            WHEN f.actual_fob > r.target_fob THEN 'OVER'
            WHEN f.actual_fob < r.target_fob THEN 'UNDER'
            ELSE 'SESUAI' END AS variance_label,
       t.line_count, t.unpriced_count, t.no_yield_count, t.usd_no_rate_count, t.missing_count,
       coalesce(gc.group_costs, '{}'::jsonb) AS group_costs,
       r.stage, pf.po_factor, round(f.actual_fob * pf.po_factor, 2) AS po_price
  FROM cbd_revision r
  CROSS JOIN LATERAL (
    SELECT coalesce(sum(v.cost_per_pair) FILTER (WHERE v.status = 'ACTIVE'), 0) AS material_cost,
           count(*) FILTER (WHERE v.status = 'ACTIVE')::int AS line_count,
           count(*) FILTER (WHERE v.status = 'ACTIVE' AND v.price_original IS NULL)::int AS unpriced_count,
           count(*) FILTER (WHERE v.status = 'ACTIVE' AND v.price_original IS NOT NULL
                              AND v.yield_value IS NULL)::int AS no_yield_count,
           count(*) FILTER (WHERE v.status = 'ACTIVE' AND v.currency = 'USD' AND v.price_idr IS NULL)::int AS usd_no_rate_count,
           count(*) FILTER (WHERE v.status = 'MISSING_IN_SPEC')::int AS missing_count
      FROM v_cbd_line v WHERE v.cbd_revision_id = r.id
  ) t
  CROSS JOIN LATERAL (
    SELECT coalesce(sum(c.amount) FILTER (WHERE c.item_type = 'LABOUR'), 0) AS labour,
           coalesce(sum(c.amount) FILTER (WHERE c.item_type = 'AMORTIZATION'), 0) AS amortization,
           coalesce(sum(c.amount) FILTER (WHERE c.item_type = 'ADJUSTMENT'), 0) AS adjustment,
           coalesce(sum(c.amount) FILTER (WHERE c.item_type = 'OTHER'), 0) AS other,
           coalesce(sum(c.amount), 0) AS items_total
      FROM cbd_cost_item c WHERE c.cbd_revision_id = r.id
  ) ci
  CROSS JOIN LATERAL (
    SELECT jsonb_object_agg(x.group_code, x.cost) AS group_costs
      FROM (SELECT v.group_code, coalesce(sum(v.cost_per_pair), 0) AS cost
              FROM v_cbd_line v WHERE v.cbd_revision_id = r.id AND v.status = 'ACTIVE'
             GROUP BY v.group_code) x
  ) gc
  CROSS JOIN LATERAL (SELECT t.material_cost + ci.items_total AS actual_fob) f
  CROSS JOIN LATERAL (
    SELECT CASE WHEN r.status = 'PUBLISHED' THEN r.po_factor
                ELSE (SELECT s.po_factor FROM stage_setting s WHERE s.stage = r.stage) END AS po_factor
  ) pf;

CREATE VIEW v_cbd_checklist AS
SELECT x.*,
       (x.spec_status <> 'ACTIVE' OR x.spec_stale OR NOT x.rate_ok OR x.stale_prices > 0 OR x.no_yield_count > 0
        OR x.pending_prices > 0) AS blocked
  FROM (
    SELECT r.id AS cbd_revision_id, r.article_id, r.stage, r.revision_no, r.status,
           EXISTS (SELECT 1 FROM cbd_revision o
                    WHERE o.article_id = r.article_id AND o.status = 'PUBLISHED' AND o.id <> r.id) AS requires_reason,
           fn_cbd_article_spec_status(r.article_id) AS spec_status,
           (r.specsheet_revision_id IS DISTINCT FROM fn_spec_latest_pub(a.specsheet_id)) AS spec_stale,
           (r.exchange_rate IS NOT NULL) AS rate_ok,
           (SELECT count(*)::int FROM v_cbd_price_check pc
             WHERE pc.cbd_revision_id = r.id AND pc.master_stale) AS stale_prices,
           rc.no_yield_count, rc.unpriced_count, rc.line_count, rc.missing_count,
           (SELECT count(*)::int FROM v_cbd_price_check pc
             WHERE pc.cbd_revision_id = r.id AND pc.pending) AS pending_prices,
           (SELECT left(string_agg(DISTINCT v.material_code || ' · ' || v.supplier_name, ', '), 300)
              FROM v_cbd_price_check pc JOIN v_cbd_line v ON v.id = pc.line_id
             WHERE pc.cbd_revision_id = r.id AND pc.pending) AS pending_list
      FROM cbd_revision r
      JOIN article a ON a.id = r.article_id
      JOIN v_cbd_recap rc ON rc.cbd_revision_id = r.id
  ) x;

-- ---------------------------------------------------------------- Refresh, terbit, sinkron
CREATE OR REPLACE FUNCTION fn_cbd_refresh_prices(p_token text, p_cbd_revision_id uuid) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev   cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
  v_n     integer;
BEGIN
  UPDATE cbd_line l
     SET price_original = pc.master_price, currency = pc.master_currency,
         price_source = CASE WHEN pc.master_price_id IS NOT NULL THEN 'MASTER' END,
         material_price_id = pc.master_price_id, price_override_reason = NULL, price_reference = NULL,
         updated_by = v_email
    FROM v_cbd_price_check pc
   WHERE pc.line_id = l.id AND pc.cbd_revision_id = v_rev.id AND pc.master_stale;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'Harga semua baris sudah sama dengan master.';
  END IF;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_refresh_from_spec(p_token text, p_cbd_revision_id uuid) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev    cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);   -- dikunci, article ACTIVE
  v_spec   specsheet_revision%ROWTYPE;
  v_lines  cbd_line[];
  v_no     integer := v_rev.revision_no;
  v_n      integer;
BEGIN
  SELECT sr.* INTO v_spec FROM specsheet_revision sr
   WHERE sr.id = fn_spec_latest_pub((SELECT specsheet_id FROM article WHERE id = v_rev.article_id));
  IF v_spec.id = v_rev.specsheet_revision_id THEN
    RAISE EXCEPTION 'CBD ini sudah memakai specsheet terbit terakhir (% r%).', v_spec.stage, v_spec.revision_no;
  END IF;
  IF v_spec.stage <> v_rev.stage THEN
    SELECT coalesce(max(revision_no) + 1, 0) INTO v_no
      FROM cbd_revision WHERE article_id = v_rev.article_id AND stage = v_spec.stage;
  END IF;

  SELECT array_agg(l ORDER BY l.sort_order) INTO v_lines FROM cbd_line l WHERE l.cbd_revision_id = v_rev.id;
  DELETE FROM cbd_line WHERE cbd_revision_id = v_rev.id;
  UPDATE cbd_revision SET specsheet_revision_id = v_spec.id, stage = v_spec.stage, revision_no = v_no,
                          updated_by = v_email
   WHERE id = v_rev.id;
  v_n := fn_cbd_populate(v_rev.id, v_rev.article_id, v_spec.id, v_lines, true, NULL, v_email);
  PERFORM fn_audit(v_email, 'cbd_revision', v_rev.id::text, 'REFRESH_FROM_SPEC');
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_publish(p_token text, p_cbd_revision_id uuid, p_category text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_in(p_token, 'edit_cbd', fn_cbd_factory(p_cbd_revision_id));
  v_rev    cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
  v_chk    v_cbd_checklist%ROWTYPE;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_id     uuid;
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
  IF coalesce(p_category, '') NOT IN ('EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER') THEN
    RAISE EXCEPTION 'Pilih kategori perubahan.';
  END IF;
  IF v_chk.requires_reason AND v_reason IS NULL THEN
    RAISE EXCEPTION 'Alasan perubahan wajib diisi untuk revisi ini.';
  END IF;

  UPDATE cbd_revision
     SET status = 'PUBLISHED', sync_status = 'IN_SYNC', published_at = now(), published_by = v_email,
         po_factor = (SELECT s.po_factor FROM stage_setting s WHERE s.stage = v_rev.stage),   -- dibekukan
         updated_by = v_email
   WHERE id = v_rev.id;

  INSERT INTO change_log (doc_type, revision_id, category, reason, created_by)
  VALUES ('CBD', v_rev.id, p_category, coalesce(v_reason, 'Revisi awal.'), v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Specsheet terbit: CBD terbit terakhir tiap article ditandai PERLU REVISI bila (baris, supplier, varian) berubah
CREATE OR REPLACE FUNCTION fn_cbd_sync_spec(p_spec_rev_id uuid, p_email text) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  c      record;
  v_same boolean;
  v_n    integer := 0;
BEGIN
  FOR c IN
    SELECT DISTINCT ON (cr.article_id) cr.id, cr.article_id, cr.specsheet_revision_id, cr.sync_status
      FROM cbd_revision cr
      JOIN revision_article ra ON ra.article_id = cr.article_id AND ra.revision_id = p_spec_rev_id
                              AND ra.status = 'ACTIVE'
     WHERE cr.status = 'PUBLISHED'
     ORDER BY cr.article_id, cr.stage_order DESC, cr.revision_no DESC
  LOOP
    CONTINUE WHEN c.specsheet_revision_id = p_spec_rev_id;
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

-- ---------------------------------------------------------------- Worklist CBD (sama dengan R4, view dibuat ulang)
CREATE VIEW v_worklist_cbd AS
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
           pm.id AS model_id, pm.name AS model_name, pm.factory_id,
           a.specsheet_id, a.season,
           coalesce(a.draft_id, a.pub_id) AS cbd_revision_id,
           coalesce(a.draft_label, a.pub_label) AS rev_label,
           pr.pending_prices
      FROM v_cbd_article a
      JOIN product_model pm ON pm.id = a.model_id
      CROSS JOIN LATERAL (
        SELECT (count(*) FILTER (WHERE pc.master_stale))::integer AS stale_prices,
               (count(*) FILTER (WHERE pc.pending))::integer AS pending_prices
          FROM v_cbd_price_check pc
         WHERE pc.cbd_revision_id = a.draft_id
      ) pr
     WHERE a.spec_status = 'ACTIVE'
  ) x
 WHERE x.kind IS NOT NULL;

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'cbd_line.variant_id / thickness' AS cek,
       (SELECT count(*) FROM information_schema.columns WHERE table_name = 'cbd_line' AND column_name IN ('variant_id', 'thickness'))::text AS hasil
UNION ALL SELECT 'kolom lama dihapus (harus 0)', (SELECT count(*) FROM information_schema.columns
       WHERE (table_name = 'cbd_revision' AND column_name = 'selling_price')
          OR (table_name = 'material' AND column_name IN ('material_code', 'thickness'))
          OR (table_name = 'material_price' AND column_name IN ('color', 'color_key')))::text
UNION ALL SELECT 'stage_setting SMS', (SELECT po_factor::text FROM stage_setting WHERE stage = 'SMS')
UNION ALL SELECT 'fn_price_lookup (harus 1 versi)', count(*)::text FROM pg_proc WHERE proname = 'fn_price_lookup';


-- #################################################################### R6_tugas_pabrik
DO $$ BEGIN RAISE NOTICE 'mulai R6_tugas_pabrik'; END $$;

-- ============================================================================
-- R6 — Tugas Saya per role baru, Brand lintas pabrik, sapu bersih pabrik (PLAN.md §6 R6)
-- Bagian dari sql/R_revisi_semua.sql (urutan R3 -> R7). Aman diulang. Satu transaksi.
--
-- - Sapu bersih: semua fungsi tulis dokumen sudah dicek pabriknya di R3–R5; yang tersisa fn_change_log_attach.
--   Fungsi master bersama (supplier, komponen), admin (user, pabrik) dan login memang lintas pabrik.
-- - Tugas Saya Vendor CBD: usulan harga yang DITOLAK Manager Costing (30 hari terakhir) — v_worklist_price_rejected.
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('public.stage_setting') IS NULL THEN
    RAISE EXCEPTION 'Bagian R5 belum dijalankan. Jalankan file revisi dari awal.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Gambar change log: + cek pabrik dokumen
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
  v_email := fn_auth_in(p_token, CASE v_log.doc_type WHEN 'CBD' THEN 'edit_cbd' ELSE 'edit_specsheet' END,
                        CASE v_log.doc_type WHEN 'CBD' THEN fn_cbd_factory(v_log.revision_id)
                                            ELSE fn_rev_factory(v_log.revision_id) END);
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

-- ---------------------------------------------------------------- Tugas Saya Vendor CBD: usulan harga ditolak
-- Ditolak dalam 30 hari terakhir dan belum diajukan ulang (tidak ada usulan / harga baru setelahnya untuk
-- varian + supplier yang sama).
DROP VIEW IF EXISTS v_worklist_price_rejected;
CREATE VIEW v_worklist_price_rejected AS
SELECT mp.id, m.id AS material_id, m.factory_id, m.name AS material_name, v.code, v.color,
       fn_thickness_label(v.thickness) AS thickness_label, s.name AS supplier_name,
       mp.price, mp.currency, mp.reject_reason, mp.decided_by, mp.decided_at, mp.created_by
  FROM material_price mp
  JOIN material_variant v ON v.id = mp.variant_id
  JOIN material_supplier ms ON ms.id = mp.material_supplier_id
  JOIN material m ON m.id = ms.material_id
  JOIN supplier s ON s.id = ms.supplier_id
 WHERE mp.status = 'REJECTED' AND mp.decided_at > now() - interval '30 days'
   AND NOT EXISTS (SELECT 1 FROM material_price n
                    WHERE n.material_supplier_id = mp.material_supplier_id AND n.variant_id = mp.variant_id
                      AND n.id <> mp.id AND n.created_at >= mp.decided_at);

SELECT 'v_worklist_price_rejected' AS cek, coalesce(to_regclass('public.v_worklist_price_rejected')::text, 'TIDAK ADA') AS hasil
UNION ALL SELECT 'fn_change_log_attach cek pabrik',
       (position('fn_auth_in' IN pg_get_functiondef('fn_change_log_attach(text,uuid,text,text)'::regprocedure)) > 0)::text;


-- #################################################################### R7_copy_model
DO $$ BEGIN RAISE NOTICE 'mulai R7_copy_model'; END $$;

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

-- #################################################################### ringkasan
SELECT 'R3–R7 terpasang' AS cek,
       concat_ws(' · ',
         'variant_id harga: ' || (SELECT count(*) FROM information_schema.columns WHERE table_name = 'material_price' AND column_name = 'variant_id'),
         'model tanpa kode: ' || (SELECT (count(*) = 0)::text FROM information_schema.columns WHERE table_name = 'product_model' AND column_name = 'code'),
         'sel varian: ' || (SELECT count(*) FROM information_schema.columns WHERE table_name = 'bom_cell' AND column_name = 'variant_id'),
         'PO SMS: ' || coalesce((SELECT po_factor::text FROM stage_setting WHERE stage = 'SMS'), '-'),
         'model induk: ' || (SELECT count(*) FROM information_schema.columns WHERE table_name = 'product_model' AND column_name = 'parent_model_id')) AS hasil;
