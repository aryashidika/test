-- ============================================================================
-- KEMBALIKAN draft ILLUZION IV CORE FG SS27 (PROD rev 0) ke kondisi sebelum uji mandiri
-- (28 Okt 2026). Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
--
-- Batas uji   : 2026-10-28 03:37:04 UTC (steps/BASELINE_ILLUZION_IV_CORE_FG_SS27.md)
-- Yang dibatalkan: SEMUA perubahan oleh spec@uji.test sesudah batas:
--   * baris BOM baru di revisi ini (ganti material, termasuk rantai ganti berulang) DIHAPUS
--   * baris lama dikembalikan (aktif lagi, material/dimension/sub-induk seperti semula)
--   * warna + kode sel baris lama dikembalikan ke nilai sebelum batas
--   * status / kategori / Process material lama dikembalikan (mis. ACTIVE lagi)
--   * varian, link supplier, dan material yang DIBUAT spec@uji.test dan tidak dipakai lagi DIHAPUS
-- Yang TIDAK disentuh:
--   * pekerjaan firman@piero.co.id (104 NX SS28, komponen, material, supplier baru)
--   * varian buatan skrip sistem (R20 warna baku, Seragamkan kode warna, Perbaiki warna W10)
--   * nomor komponen di master (geser nomor oleh firman + 1 pindah oleh spec@uji.test 03:56,
--     karena penomoran firman sesudahnya bergantung padanya). Baris BOM merujuk komponen
--     lewat id, jadi nama/nomor yang tampil mengikuti master yang sekarang.
--   * audit_log (riwayat tetap ada)
--
-- CARA PAKAI
--   1. Jalankan bagian P (pratinjau, hanya SELECT), cek hasilnya.
--   2. Jalankan bagian H apa adanya (v_simpan = false): semua dijalankan lalu DIBATALKAN, dan
--      pesan error "UJI SAJA ..." menampilkan jumlahnya. Tidak ada yang tersimpan.
--   3. Kalau angkanya cocok, ubah v_simpan menjadi true dan jalankan bagian H lagi.
--   4. Jalankan lagi sql/CEK_specsheet_ILLUZION_IV_CORE_FG_SS27.sql dan bandingkan dengan baseline.
-- ============================================================================


-- ======================== P. PRATINJAU (hanya SELECT) ========================

-- P1. Baris yang akan DIHAPUS (baru dibuat sesudah batas di revisi ini)
SELECT l.id, l.is_active, coalesce(c.name, l.local_component_name, l.sub_name) AS komponen,
       m.name AS material, l.thickness AS dimension, l.created_by, l.created_at
FROM bom_line l
JOIN material m ON m.id = l.material_id
LEFT JOIN component c ON c.id = l.component_id
WHERE l.revision_id = 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf'
  AND l.created_at >= timestamptz '2026-10-28 03:37:04+00'
ORDER BY l.sort_order, l.created_at;

-- Catatan: audit_log UPDATE hanya menyimpan kolom yang berubah. Nilai "dulu" per kolom = before_data dari
-- catatan PERTAMA sesudah batas yang mengubah kolom itu (k), digabung per baris (f), lalu ditimpakan ke baris sekarang.

-- P2. Baris lama yang akan DIKEMBALIKAN: sekarang vs sebelum batas
WITH k AS (
  SELECT DISTINCT ON (a.entity_id, e.key) a.entity_id, e.key, e.value
  FROM audit_log a CROSS JOIN LATERAL jsonb_each(a.before_data) e
  WHERE a.entity = 'bom_line' AND a.action = 'UPDATE' AND a.created_at >= timestamptz '2026-10-28 03:37:04+00'
  ORDER BY a.entity_id, e.key, a.created_at, a.id
), f AS (SELECT entity_id, jsonb_object_agg(key, value) AS b FROM k GROUP BY entity_id)
SELECT l.id, coalesce(c.name, l.local_component_name, l.sub_name) AS komponen,
       (SELECT string_agg(x, ', ' ORDER BY x) FROM jsonb_object_keys(f.b) x) AS kolom_berubah,
       l.is_active AS aktif_sekarang, r.is_active AS aktif_dulu,
       m.name AS material_sekarang, mb.name AS material_dulu,
       l.thickness AS dimension_sekarang, r.thickness AS dimension_dulu,
       l.parent_line_key IS DISTINCT FROM r.parent_line_key AS induk_berubah
FROM f
JOIN bom_line l ON l.id = f.entity_id::uuid
CROSS JOIN LATERAL jsonb_populate_record(NULL::bom_line, to_jsonb(l) || f.b) AS r
JOIN material m ON m.id = l.material_id
JOIN material mb ON mb.id = r.material_id
LEFT JOIN component c ON c.id = l.component_id
WHERE l.revision_id = 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf'
  AND l.created_at < timestamptz '2026-10-28 03:37:04+00'
ORDER BY l.sort_order;

-- P3. Sel baris lama yang akan DIKEMBALIKAN (warna / kode sekarang vs dulu)
WITH k AS (
  SELECT DISTINCT ON (a.entity_id, e.key) a.entity_id, e.key, e.value
  FROM audit_log a CROSS JOIN LATERAL jsonb_each(a.before_data) e
  WHERE a.entity = 'bom_cell' AND a.action = 'UPDATE' AND a.created_at >= timestamptz '2026-10-28 03:37:04+00'
  ORDER BY a.entity_id, e.key, a.created_at, a.id
), f AS (SELECT entity_id, jsonb_object_agg(key, value) AS b FROM k GROUP BY entity_id)
SELECT coalesce(co.name, l.local_component_name, l.sub_name) AS komponen, ar.code AS article,
       c.color AS warna_sekarang, r.color AS warna_dulu,
       v.code AS kode_sekarang, vb.code AS kode_dulu
FROM f
JOIN bom_cell c ON c.bom_line_id = split_part(f.entity_id, ':', 1)::uuid
               AND c.article_id = split_part(f.entity_id, ':', 2)::uuid
CROSS JOIN LATERAL jsonb_populate_record(NULL::bom_cell, to_jsonb(c) || f.b) AS r
JOIN bom_line l ON l.id = c.bom_line_id
JOIN article ar ON ar.id = c.article_id
LEFT JOIN component co ON co.id = l.component_id
LEFT JOIN material_variant v ON v.id = c.variant_id
LEFT JOIN material_variant vb ON vb.id = r.variant_id
WHERE l.revision_id = 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf'
  AND l.created_at < timestamptz '2026-10-28 03:37:04+00'
  AND (c.color IS DISTINCT FROM r.color OR c.variant_id IS DISTINCT FROM r.variant_id)
ORDER BY l.sort_order, ar.code;

-- P4. Material lama yang status / kategori / Process-nya DIKEMBALIKAN (hanya perubahan oleh spec@uji.test)
WITH k AS (
  SELECT DISTINCT ON (a.entity_id, e.key) a.entity_id, e.key, e.value
  FROM audit_log a CROSS JOIN LATERAL jsonb_each(a.before_data) e
  WHERE a.entity = 'material' AND a.action = 'UPDATE' AND a.user_email = 'spec@uji.test'
    AND a.created_at >= timestamptz '2026-10-28 03:37:04+00'
  ORDER BY a.entity_id, e.key, a.created_at, a.id
), f AS (SELECT entity_id, jsonb_object_agg(key, value) AS b FROM k GROUP BY entity_id)
SELECT m.name, m.status AS status_sekarang, r.status AS status_dulu,
       m.category AS kategori_sekarang, r.category AS kategori_dulu,
       m.is_process AS process_sekarang, r.is_process AS process_dulu,
       m.price_method AS harga_sekarang, r.price_method AS harga_dulu
FROM f
JOIN material m ON m.id = f.entity_id::uuid
CROSS JOIN LATERAL jsonb_populate_record(NULL::material, to_jsonb(m) || f.b) AS r
WHERE m.created_at < timestamptz '2026-10-28 03:37:04+00'
  AND (m.status, m.category, m.is_process, m.price_method)
      IS DISTINCT FROM (r.status, r.category, r.is_process, r.price_method);

-- P5. Master buatan spec@uji.test yang akan DIHAPUS (varian, link supplier, material)
SELECT 'variant' AS jenis, v.code AS nama, m.name AS material, v.created_at
FROM material_variant v JOIN material m ON m.id = v.material_id
WHERE v.created_by = 'spec@uji.test' AND v.created_at >= timestamptz '2026-10-28 03:37:04+00'
UNION ALL
SELECT 'material_supplier', s.name, m.name, ms.created_at
FROM material_supplier ms JOIN material m ON m.id = ms.material_id JOIN supplier s ON s.id = ms.supplier_id
WHERE ms.created_by = 'spec@uji.test' AND ms.created_at >= timestamptz '2026-10-28 03:37:04+00'
UNION ALL
SELECT 'material', m.name, m.uom, m.created_at
FROM material m
WHERE m.created_by = 'spec@uji.test' AND m.created_at >= timestamptz '2026-10-28 03:37:04+00'
ORDER BY jenis, created_at;


-- ======================== H. KEMBALIKAN (satu transaksi) ========================

DO $$
DECLARE
  v_simpan  boolean     := false;   -- false = uji saja (dibatalkan), true = simpan
  v_rev     uuid        := 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf';
  v_batas   timestamptz := '2026-10-28 03:37:04+00';
  v_penguji text        := 'spec@uji.test';
  v_base    uuid[]      := ARRAY[
    '3e952b17-a465-417c-8f92-137914a254b6','842c4098-4681-4b4d-b461-759ce3433d67','c33f0a37-a307-44b5-8881-c614c08f7041',
    'e7944cf2-8549-4620-901c-ffca7442205f','3bdde6e0-f74e-4818-89b0-d8361bd8e63f','53e6420c-1b3c-4cd2-8239-d9dd193b8c75',
    '5cebf4ba-8b50-40bc-8e2f-f773a5ce33a8','f10d79cd-bcc4-40d1-9919-db21df56f5d5','ae22bc55-a77c-4241-9857-61f7bed8f6bd',
    '2a30e4d8-4a21-4a07-af3f-02e6cc9e9a97','1f189c47-45e8-4f3e-94d4-67b2688dde85','0b4a4a84-6159-454b-97d7-19c3578ae66d',
    '318e3731-b6ff-4087-a9bd-4b399e6e9c05','76823fe1-6255-45bf-ab38-10fd2be98b4f','b5552bf4-6f86-4e7f-952d-c08f31e076a8',
    'bd6f2016-8640-475c-b617-9068e84aa3b5','5e84d4e8-eca7-4b72-add0-190052b223de','c6d5769d-7912-4818-b573-3d5bb487fe7f',
    'acfdfc07-81ff-4bbd-ab62-1bd656d1adc6','6ea4c27c-6733-4010-b2b5-de2af56fd481','24d3814d-553f-4f2c-b8c1-6a12af56b294',
    'b503b871-8e87-4f08-b786-51d166d0adba','175d8f90-16a7-460d-9957-72bdcc21e95e','fb856c27-3ae9-4a34-9d42-9cba4a72308e',
    'a46f3d4c-2d16-45c8-8a91-26fe89dc1f13','28890688-9de9-4045-b01d-d3d9ebe986de','829cc786-7f0b-4907-b094-39de45458ef4',
    '01d86f87-f3cb-47c0-b8bd-4f72475f5642','f4505f31-55b6-444d-96e6-fab1be90132d','4159bbeb-125f-4ae3-98f2-294e6905d654',
    'd9fe2a4b-4208-4ebe-a827-0df943dcc02c','33fc25cf-f686-4a94-8b1c-c5d2072bcbf2','6479278e-79e3-4a2e-ab3f-30cad8b34c91',
    'e832c9f4-4bce-43c1-a515-78ecea2f8eb6','75f58db5-f8c8-40e6-964b-b695a3f7254f','208aca99-f5bf-48dc-9713-48e82fd7f48a',
    '2778867f-d0c8-4adf-b4c7-1cbd7869e214','58927b24-0e4e-4d28-a4a1-660adbdb4233','8234bb7e-62c7-45a5-ac3f-3676fbfa2210',
    '2d1d646f-d6a4-45e6-8e4f-0b0c19126d8e','3985f934-0605-4d6c-a5e9-c32fb9191836']::uuid[];
  n_mat_kembali integer; n_line_hapus integer; n_line_kembali integer; n_cell_hapus integer;
  n_cell_kembali integer; n_var integer; n_ms integer; n_mat_hapus integer;
  n_aktif integer; n_cell integer; n_kuning integer; n_sambung integer; v_beda text;
BEGIN
  IF (SELECT status FROM specsheet_revision WHERE id = v_rev) IS DISTINCT FROM 'DRAFT' THEN
    RAISE EXCEPTION 'Revisi tidak ditemukan atau sudah bukan DRAFT. Dibatalkan.';
  END IF;

  -- Kode otomatis R20 dimatikan selama skrip, supaya sel yang dikembalikan tidak langsung diberi kode lagi
  PERFORM set_config('app.r20_autofill', 'on', true);
  PERFORM set_config('app.user', 'Kembalikan uji ILLUZION', true);

  -- 1. Material lama: status / kategori / Process / metode harga seperti sebelum batas
  --    (audit UPDATE hanya menyimpan kolom yang berubah: nilai dulu per kolom = catatan pertama sesudah batas)
  WITH k AS (
    SELECT DISTINCT ON (a.entity_id, e.key) a.entity_id, e.key, e.value
    FROM audit_log a CROSS JOIN LATERAL jsonb_each(a.before_data) e
    WHERE a.entity = 'material' AND a.action = 'UPDATE' AND a.user_email = v_penguji AND a.created_at >= v_batas
    ORDER BY a.entity_id, e.key, a.created_at, a.id
  ), f AS (SELECT entity_id, jsonb_object_agg(key, value) AS b FROM k GROUP BY entity_id),
  r AS (
    SELECT x.* FROM f JOIN material m ON m.id = f.entity_id::uuid AND m.created_at < v_batas
    CROSS JOIN LATERAL jsonb_populate_record(NULL::material, to_jsonb(m) || f.b) AS x
  )
  UPDATE material m
     SET status = r.status, category = r.category, is_process = r.is_process, price_method = r.price_method
    FROM r
   WHERE m.id = r.id
     AND (m.status, m.category, m.is_process, m.price_method)
         IS DISTINCT FROM (r.status, r.category, r.is_process, r.price_method);
  GET DIAGNOSTICS n_mat_kembali = ROW_COUNT;

  -- 2. Hapus baris baru di revisi ini (selnya ikut terhapus)
  DELETE FROM bom_line WHERE revision_id = v_rev AND created_at >= v_batas;
  GET DIAGNOSTICS n_line_hapus = ROW_COUNT;

  -- 3. Baris lama: kembalikan setiap kolom yang berubah ke nilai sebelum batas
  WITH k AS (
    SELECT DISTINCT ON (a.entity_id, e.key) a.entity_id, e.key, e.value
    FROM audit_log a CROSS JOIN LATERAL jsonb_each(a.before_data) e
    WHERE a.entity = 'bom_line' AND a.action = 'UPDATE' AND a.created_at >= v_batas
    ORDER BY a.entity_id, e.key, a.created_at, a.id
  ), f AS (SELECT entity_id, jsonb_object_agg(key, value) AS b FROM k GROUP BY entity_id),
  r AS (
    SELECT x.* FROM f
    JOIN bom_line l ON l.id = f.entity_id::uuid AND l.revision_id = v_rev AND l.created_at < v_batas
    CROSS JOIN LATERAL jsonb_populate_record(NULL::bom_line, to_jsonb(l) || f.b) AS x
  )
  UPDATE bom_line l
     SET is_active = r.is_active, component_id = r.component_id,
         local_component_no = r.local_component_no, local_component_name = r.local_component_name,
         parent_line_key = r.parent_line_key, sub_seq = r.sub_seq, sub_name = r.sub_name,
         material_id = r.material_id, thickness = r.thickness, supplier_id = r.supplier_id,
         process = r.process, sort_order = r.sort_order,
         origin_line_key = r.origin_line_key, replaces_line_key = r.replaces_line_key
    FROM r
   WHERE l.id = r.id;
  GET DIAGNOSTICS n_line_kembali = ROW_COUNT;

  -- 4. Sel baris lama: hapus sel yang baru ditambahkan, kembalikan warna + kode sel yang diubah.
  --    trg_bom_cell_variant biasanya memilih kode sendiri dari material + dimension + warna, jadi dimatikan
  --    sementara supaya nilai sebelum batas bisa ditulis persis dan varian uji bisa dilepas (ikut dibatalkan bila error).
  ALTER TABLE bom_cell DISABLE TRIGGER trg_bom_cell_variant;

  DELETE FROM bom_cell c USING bom_line l
   WHERE l.id = c.bom_line_id AND l.revision_id = v_rev AND l.created_at < v_batas AND c.created_at >= v_batas;
  GET DIAGNOSTICS n_cell_hapus = ROW_COUNT;

  --    (entity_id sel di audit = "bom_line_id:article_id")
  WITH k AS (
    SELECT DISTINCT ON (a.entity_id, e.key) a.entity_id, e.key, e.value
    FROM audit_log a CROSS JOIN LATERAL jsonb_each(a.before_data) e
    WHERE a.entity = 'bom_cell' AND a.action = 'UPDATE' AND a.created_at >= v_batas
    ORDER BY a.entity_id, e.key, a.created_at, a.id
  ), f AS (SELECT entity_id, jsonb_object_agg(key, value) AS b FROM k GROUP BY entity_id),
  r AS (
    SELECT x.* FROM f
    JOIN bom_cell c ON c.bom_line_id = split_part(f.entity_id, ':', 1)::uuid
                   AND c.article_id = split_part(f.entity_id, ':', 2)::uuid
    JOIN bom_line l ON l.id = c.bom_line_id AND l.revision_id = v_rev AND l.created_at < v_batas
    CROSS JOIN LATERAL jsonb_populate_record(NULL::bom_cell, to_jsonb(c) || f.b) AS x
  )
  UPDATE bom_cell c
     SET color = r.color, variant_id = r.variant_id
    FROM r
   WHERE c.bom_line_id = r.bom_line_id AND c.article_id = r.article_id
     AND (c.color IS DISTINCT FROM r.color OR c.variant_id IS DISTINCT FROM r.variant_id);
  GET DIAGNOSTICS n_cell_kembali = ROW_COUNT;

  -- 5. Varian buatan penguji yang sudah tidak dipakai sel mana pun
  DELETE FROM material_variant v
   WHERE v.created_by = v_penguji AND v.created_at >= v_batas
     AND NOT EXISTS (SELECT 1 FROM bom_cell c WHERE c.variant_id = v.id);
  GET DIAGNOSTICS n_var = ROW_COUNT;

  -- 5b. Trigger kode dinyalakan lagi, lalu sel baseline yang masih kosong disentuh sekali: kalau di master sudah
  --     ada varian yang cocok (mis. buatan skrip R20 warna baku), sel langsung tersambung seperti perilaku app biasa.
  --     Kode baru TIDAK disusun (app.r20_autofill = on), jadi sel lain tetap kuning sampai diisi bersama user.
  ALTER TABLE bom_cell ENABLE TRIGGER trg_bom_cell_variant;
  UPDATE bom_cell c SET color = c.color
    FROM bom_line l
   WHERE l.id = c.bom_line_id AND l.id = ANY (v_base) AND c.variant_id IS NULL AND c.color IS NOT NULL;
  SELECT count(*) INTO n_sambung
    FROM bom_cell c WHERE c.bom_line_id = ANY (v_base) AND c.variant_id IS NOT NULL;

  -- 6. Link supplier buatan penguji yang sudah tidak dipakai baris mana pun
  DELETE FROM material_supplier ms
   WHERE ms.created_by = v_penguji AND ms.created_at >= v_batas
     AND NOT EXISTS (SELECT 1 FROM bom_line l WHERE l.material_id = ms.material_id AND l.supplier_id = ms.supplier_id);
  GET DIAGNOSTICS n_ms = ROW_COUNT;

  -- 7. Material buatan penguji yang sudah tidak dipakai (tanpa baris, varian, atau link supplier)
  DELETE FROM material m
   WHERE m.created_by = v_penguji AND m.created_at >= v_batas
     AND NOT EXISTS (SELECT 1 FROM bom_line l WHERE l.material_id = m.id)
     AND NOT EXISTS (SELECT 1 FROM material_variant v WHERE v.material_id = m.id)
     AND NOT EXISTS (SELECT 1 FROM material_supplier ms WHERE ms.material_id = m.id);
  GET DIAGNOSTICS n_mat_hapus = ROW_COUNT;

  -- 8. Cek hasil: baris aktif harus persis 41 baris baseline, sel 82
  SELECT string_agg(x::text, ', ') INTO v_beda
  FROM (
    (SELECT id FROM bom_line WHERE revision_id = v_rev AND is_active EXCEPT SELECT unnest(v_base))
    UNION ALL
    (SELECT unnest(v_base) EXCEPT SELECT id FROM bom_line WHERE revision_id = v_rev AND is_active)
  ) d(x);
  IF v_beda IS NOT NULL THEN
    RAISE EXCEPTION 'Baris aktif tidak sama dengan baseline (beda: %). Dibatalkan, tidak ada yang tersimpan.', v_beda;
  END IF;

  SELECT count(*) INTO n_aktif FROM bom_line WHERE revision_id = v_rev AND is_active;
  SELECT count(*), count(*) FILTER (WHERE c.variant_id IS NULL AND c.is_used AND NOT m.is_process) INTO n_cell, n_kuning
    FROM bom_cell c JOIN bom_line l ON l.id = c.bom_line_id JOIN material m ON m.id = l.material_id
   WHERE l.revision_id = v_rev AND l.is_active;

  IF NOT v_simpan THEN
    RAISE EXCEPTION 'UJI SAJA, tidak ada yang tersimpan. material dikembalikan %, baris dihapus %, baris dikembalikan %, sel baru dihapus %, sel dikembalikan %, varian dihapus %, link supplier dihapus %, material dihapus %. Hasil: baris aktif %, sel %, sel berkode %, sel tanpa kode %.',
      n_mat_kembali, n_line_hapus, n_line_kembali, n_cell_hapus, n_cell_kembali, n_var, n_ms, n_mat_hapus,
      n_aktif, n_cell, n_sambung, n_kuning;
  END IF;
  RAISE NOTICE 'TERSIMPAN. baris aktif %, sel %, varian dihapus %, material dihapus %.', n_aktif, n_cell, n_var, n_mat_hapus;
END;
$$;

-- Sesudah disimpan: ringkasan (harus 41 baris aktif dan 82 sel)
SELECT (SELECT count(*) FROM bom_line WHERE revision_id = 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf' AND is_active) AS baris_aktif,
       (SELECT count(*) FROM bom_cell c JOIN bom_line l ON l.id = c.bom_line_id
         WHERE l.revision_id = 'e9a655b7-8dfe-4e7d-8806-744d7e865eaf' AND l.is_active) AS sel,
       (SELECT count(*) FROM material_variant WHERE created_by = 'spec@uji.test'
          AND created_at >= timestamptz '2026-10-28 03:37:04+00') AS sisa_varian_uji,
       (SELECT count(*) FROM material WHERE created_by = 'spec@uji.test'
          AND created_at >= timestamptz '2026-10-28 03:37:04+00') AS sisa_material_uji;
