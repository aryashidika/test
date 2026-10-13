-- ============================================================================
-- R11b — Harga AKAN BERLAKU yang diakhiri tampil "DIBATALKAN" (temuan uji C user, 13 Okt 2026).
-- Jalankan SETELAH R11_perbaikan.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi. Satu-satunya perubahan data: memulihkan harga yang terkena bug fn_price_end (lihat bawah).
--
-- R11 (T54) membatalkan harga AKAN BERLAKU dengan valid_to = valid_from (rentang 0 hari, tidak pernah berlaku) dan
-- membuka lagi harga sebelumnya — lookup harga CBD sudah benar, tetapi keterangan di tabel masih "AKAN BERLAKU"
-- (valid_to belum lewat) sehingga form Tambah Harga juga menganggapnya harga berlaku terbaru.
--   - fn_price_state: rentang 0 hari = DIBATALKAN (sebelum RIWAYAT / AKAN BERLAKU)
--   - v_material_price: pasangan yang hanya punya harga dibatalkan tetap tampil "BELUM ADA HARGA"
--   - fn_price_end: membatalkan harga AKAN BERLAKU kedua dengan tanggal mulai sama (tambah → akhiri → tambah lagi →
--     akhiri lagi) ikut MENGHIDUPKAN harga pertama yang sudah dibatalkan (valid_to-nya = tanggal itu) → yang dibuka
--     lagi hanya harga yang mulai LEBIH AWAL. Data yang sudah terkena dipulihkan dari audit_log (valid_to diubah dari
--     tanggal mulainya sendiri menjadi kosong = hanya bisa terjadi karena bug ini) → dibatalkan lagi.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_cbd_bridge_view(text,uuid)') IS NULL THEN
    RAISE EXCEPTION 'R11 belum terpasang. Jalankan sql/R11_perbaikan.sql dulu.';
  END IF;
END;
$$;

-- Keterangan harga untuk tabel: MENUNGGU APPROVAL / DITOLAK / DIBATALKAN / RIWAYAT / AKAN BERLAKU / BERLAKU
CREATE OR REPLACE FUNCTION fn_price_state(p_status text, p_valid_from date, p_valid_to date) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN p_status = 'PROPOSED' THEN 'MENUNGGU APPROVAL'
              WHEN p_status = 'REJECTED' THEN 'DITOLAK'
              WHEN p_valid_to IS NOT NULL AND p_valid_to <= p_valid_from THEN 'DIBATALKAN'
              WHEN p_valid_to IS NOT NULL AND p_valid_to <= fn_today() THEN 'RIWAYAT'
              WHEN p_valid_from > fn_today() THEN 'AKAN BERLAKU'
              ELSE 'BERLAKU' END
$$;

-- Sama dengan R3, kecuali: harga dibatalkan (rentang 0 hari) tidak dihitung sebagai harga hidup untuk baris
-- "BELUM ADA HARGA".
CREATE OR REPLACE VIEW v_material_price AS
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
                           OR (mp.status = 'APPROVED' AND (mp.valid_to IS NULL OR (mp.valid_to > fn_today() AND mp.valid_to > mp.valid_from)))));


-- ---------------------------------------------------------------- akhiri harga: jangan hidupkan harga yang dibatalkan
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

-- Pulihkan harga yang terlanjur hidup lagi karena bug di atas
CREATE TEMP TABLE r11b_pulih ON COMMIT DROP AS
SELECT mp.id
  FROM material_price mp
 WHERE mp.status = 'APPROVED' AND mp.valid_to IS NULL
   AND EXISTS (SELECT 1 FROM audit_log a
                WHERE a.entity = 'material_price' AND a.entity_id = mp.id::text AND a.action = 'UPDATE'
                  AND a.before_data ->> 'valid_to' = mp.valid_from::text
                  AND a.after_data ? 'valid_to' AND a.after_data -> 'valid_to' = 'null'::jsonb);
UPDATE material_price SET valid_to = valid_from, updated_by = 'R11b'
 WHERE id IN (SELECT id FROM r11b_pulih);

COMMIT;

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'R11b terpasang' AS cek,
       'dipulihkan: ' || (SELECT count(*) FROM material_price WHERE updated_by = 'R11b')
       || ' · harga dibatalkan: ' || count(*) FILTER (WHERE state = 'DIBATALKAN')
       || ' · masih AKAN BERLAKU: ' || count(*) FILTER (WHERE state = 'AKAN BERLAKU') AS hasil
  FROM v_material_price;
