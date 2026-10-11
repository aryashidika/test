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
