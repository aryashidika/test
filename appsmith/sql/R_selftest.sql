-- ============================================================================
-- R_selftest — uji alur inti R3–R10 langsung di database, lalu DIBATALKAN (ROLLBACK): tidak ada data yang tersimpan.
-- Jalankan SETELAH sql/R_revisi_semua.sql, sql/R8_catatan_uji.sql, R9_kode_varian.sql DAN R10_hapus_varian.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF),
-- SEBELUM import app. Hasil yang diharapkan: baris terakhir "SELFTEST LOLOS". Kalau ada yang salah, query berhenti
-- dengan pesan "SELFTEST GAGAL: ..." — kirim pesan itu ke pengembang.
-- Aman di DB yang sudah berisi data: pabrik SELFTEST PABRIK A/B, email @selftest.invalid; master BERSAMA (supplier,
-- komponen, pilihan Kategori) memakai nama berawalan SELFTEST dan nomor komponen = kelipatan 10 kosong pertama di
-- kelompok 'a'; data per pabrik (material, model, article) ada di pabrik SELFTEST. Semua dibatalkan (ROLLBACK).
-- ============================================================================
BEGIN;

-- ---------------------------------------------------------------- helper (hanya untuk sesi ini)
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS NOT TRUE THEN
    RAISE EXCEPTION 'SELFTEST GAGAL: %', p_label;
  END IF;
  RAISE NOTICE 'ok  %', p_label;
END;
$$;

-- p_sql harus GAGAL dengan pesan yang cocok p_pattern (ILIKE)
CREATE FUNCTION pg_temp.must_fail(p_sql text, p_pattern text, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT ILIKE p_pattern THEN
      RAISE EXCEPTION 'SELFTEST GAGAL: % — pesan tidak sesuai: %', p_label, SQLERRM;
    END IF;
    RAISE NOTICE 'ok  % (ditolak: %)', p_label, left(SQLERRM, 90);
    RETURN;
  END;
  RAISE EXCEPTION 'SELFTEST GAGAL: % — seharusnya ditolak', p_label;
END;
$$;

CREATE FUNCTION pg_temp.tok(p_email text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v record;
BEGIN
  SELECT * INTO v FROM fn_login(p_email, 'Uji-12345');
  IF NOT v.ok THEN
    RAISE EXCEPTION 'SELFTEST GAGAL: login % — %', p_email, v.message;
  END IF;
  RETURN v.token;
END;
$$;

-- ---------------------------------------------------------------- data uji: 2 pabrik, user per role
INSERT INTO factory (name) VALUES ('SELFTEST PABRIK A'), ('SELFTEST PABRIK B');
INSERT INTO app_user (email, full_name, role, is_active, password_hash, must_change_password, failed_attempts, factory_id)
SELECT u.email, u.name, u.role, true, crypt('Uji-12345', gen_salt('bf', 4)), false, 0,
       (SELECT id FROM factory WHERE name = u.factory)
  FROM (VALUES ('spec.a@selftest.invalid', 'UJI SPEC A', 'VENDOR_SPEC', 'SELFTEST PABRIK A'),
               ('cbd.a@selftest.invalid', 'UJI CBD A', 'VENDOR_CBD', 'SELFTEST PABRIK A'),
               ('mc.a@selftest.invalid', 'UJI MC A', 'MANAGER_COSTING', 'SELFTEST PABRIK A'),
               ('spec.b@selftest.invalid', 'UJI SPEC B', 'VENDOR_SPEC', 'SELFTEST PABRIK B'),
               ('cbd.b@selftest.invalid', 'UJI CBD B', 'VENDOR_CBD', 'SELFTEST PABRIK B'),
               ('brand@selftest.invalid', 'UJI BRAND', 'BRAND_VIEWER', NULL)) AS u(email, name, role, factory);

-- ---------------------------------------------------------------- R3 + R4
DO $$
DECLARE
  t_spec  text := pg_temp.tok('spec.a@selftest.invalid');
  t_cbd   text := pg_temp.tok('cbd.a@selftest.invalid');
  t_mc    text := pg_temp.tok('mc.a@selftest.invalid');
  t_specb text := pg_temp.tok('spec.b@selftest.invalid');
  t_cbdb  text := pg_temp.tok('cbd.b@selftest.invalid');
  v_sup   uuid; v_sup2 uuid; v_mat uuid; v_mat2 uuid;
  v1 uuid; v2 uuid; v3 uuid; v4 uuid; vg uuid; ve uuid;
  v_link  uuid; v_link2 uuid; v_batch uuid; v_b2 uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; pn uuid;
  v_cat   uuid; v_last uuid; v_lastb uuid; v_gender uuid;
  m_a uuid; m_b uuid; v_sheet uuid; a1 uuid; a2 uuid; a3 uuid; v_comp uuid;
  v_rev uuid; v_rev2 uuid; l1 uuid; l2 uuid; v_log uuid; v_no integer;
  c1 uuid; c2 uuid; v_linke uuid; v_b3 uuid;
  m_c uuid; m_d uuid; v_cat2 uuid; sh_c uuid; sh_d uuid; sh_b uuid; ac1 uuid; ad1 uuid; rev_c uuid; c3 uuid;
  n integer;
  r record;
BEGIN
  -- ===== R3: harga varian × supplier =====
  v_sup  := fn_supplier_save(t_spec, NULL, 'SELFTEST SUPPLIER SATU', 'ACTIVE');
  v_sup2 := fn_supplier_save(t_spec, NULL, 'SELFTEST SUPPLIER DUA', 'ACTIVE');
  v_mat  := fn_material_add(t_spec, 'UJI MESH', 'TEXTILE', 'YD');
  v1 := fn_variant_save(t_spec, NULL, v_mat, 'MSHU120BLK', 'BLACK', '1.2MM', 'ACTIVE');
  v2 := fn_variant_save(t_spec, NULL, v_mat, 'MSHU120WHT', 'WHITE', '1.2MM', 'ACTIVE');
  v3 := fn_variant_save(t_spec, NULL, v_mat, 'MSHU120NVY', 'NAVY', '1.2MM', 'ACTIVE');
  v4 := fn_variant_save(t_spec, NULL, v_mat, 'MSHU120RED', 'RED', '1.2MM', 'ACTIVE');
  v_link  := fn_link_save(t_spec, NULL, v_mat, v_sup, true, 'ACTIVE');
  v_link2 := fn_link_save(t_spec, NULL, v_mat, v_sup2, false, 'ACTIVE');

  PERFORM pg_temp.must_fail(format('SELECT fn_price_propose(%L, %L, %L, 100, ''IDR'', NULL, NULL)',
            t_cbdb, v_link, jsonb_build_array(v1)), '%pabrik lain%', 'R3 Vendor CBD pabrik B tidak bisa mengajukan harga pabrik A');
  PERFORM pg_temp.must_fail(format('SELECT fn_price_propose(%L, %L, %L, 100, NULL, NULL, NULL)',
            t_cbd, v_link, jsonb_build_array(v1)), '%Currency%', 'R3 currency wajib');

  v_batch := fn_price_propose(t_cbd, v_link, jsonb_build_array(v1, v2, v3, v4), 45000, 'IDR', fn_today(), 'Q-1');
  PERFORM pg_temp.ok((SELECT count(*) FROM material_price WHERE batch_id = v_batch AND status = 'PROPOSED') = 4,
                     'R3 satu pengajuan 4 varian = 4 usulan PROPOSED');
  PERFORM pg_temp.must_fail(format('SELECT fn_price_propose(%L, %L, %L, 46000, ''IDR'', NULL, NULL)',
            t_cbd, v_link, jsonb_build_array(v1)), '%menunggu approval%', 'R3 maks. satu usulan per varian + supplier');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_worklist_admin WHERE ref_id = v_batch) = 1, 'R3 Beranda MC: 1 baris per pengajuan');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_price_pending WHERE batch_id = v_batch AND problem IS NULL) = 4,
                     'R3 v_price_pending 4 baris tanpa masalah');

  SELECT id INTO p1 FROM material_price WHERE batch_id = v_batch AND variant_id = v1;
  SELECT id INTO p2 FROM material_price WHERE batch_id = v_batch AND variant_id = v2;
  SELECT id INTO p3 FROM material_price WHERE batch_id = v_batch AND variant_id = v3;
  SELECT id INTO p4 FROM material_price WHERE batch_id = v_batch AND variant_id = v4;
  PERFORM pg_temp.must_fail(format('SELECT fn_price_decide(%L, %L, ''APPROVE'', NULL)', t_cbd, jsonb_build_array(p1)),
            '%tidak punya akses%', 'R3 Vendor CBD tidak bisa approve');
  PERFORM pg_temp.must_fail(format('SELECT fn_price_decide(%L, %L, ''REJECT'', '' '')', t_mc, jsonb_build_array(p4)),
            '%Alasan%', 'R3 tolak tanpa alasan ditolak');
  n := fn_price_decide(t_mc, jsonb_build_array(p4), 'REJECT', 'Harga tidak sesuai');
  PERFORM pg_temp.ok(n = 1 AND (SELECT status FROM material_price WHERE id = p4) = 'REJECTED', 'R3 tolak 1 dengan alasan');
  n := fn_price_decide(t_mc, jsonb_build_array(p1, p2, p3), 'APPROVE', NULL);
  PERFORM pg_temp.ok(n = 3, 'R3 setujui 3 sekaligus');
  PERFORM pg_temp.ok((SELECT price FROM fn_price_lookup(v1, v_sup)) = 45000, 'R3 lookup harga varian = 45000');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_worklist_admin WHERE ref_id = v_batch) = 0, 'R3 pengajuan selesai hilang dari Beranda');

  PERFORM pg_temp.must_fail(format('SELECT fn_price_propose(%L, %L, %L, 47000, ''IDR'', %L, NULL)',
            t_cbd, v_link, jsonb_build_array(v1), fn_today() - 10), '%lebih awal%', 'R3 tanggal lebih awal dari harga berlaku ditolak');
  v_b2 := fn_price_propose(t_cbd, v_link, jsonb_build_array(v1), 47000, 'IDR', fn_today() + 1, 'Q-2');
  PERFORM pg_temp.ok((SELECT price FROM fn_price_lookup(v1, v_sup)) = 45000, 'R3 harga lama tetap berlaku sebelum approve');
  SELECT id INTO pn FROM material_price WHERE batch_id = v_b2;
  PERFORM fn_price_decide(t_mc, jsonb_build_array(pn), 'APPROVE', NULL);
  PERFORM pg_temp.ok((SELECT valid_to FROM material_price WHERE id = p1) = fn_today() + 1, 'R3 approve menutup harga lama per tanggal baru');
  PERFORM pg_temp.ok((SELECT price FROM fn_price_lookup(v1, v_sup, fn_today() + 1)) = 47000, 'R3 harga baru berlaku besok');

  SELECT * INTO r FROM fn_price_copy(t_cbd, v3, jsonb_build_array(v4), fn_today(), NULL);
  PERFORM pg_temp.ok(r.created = 1 AND r.skipped IS NULL, 'R3 salin harga NAVY -> RED (1 supplier berharga)');
  PERFORM pg_temp.ok((SELECT reference FROM material_price WHERE batch_id = r.batch_id) = 'Salin dari MSHU120NVY',
                     'R3 referensi salinan otomatis');
  PERFORM pg_temp.must_fail(format('SELECT * FROM fn_price_copy(%L, %L, %L, NULL, NULL)', t_cbd, v3, jsonb_build_array(v4)),
            '%Tidak ada harga yang disalin%', 'R3 salin ulang dilewati semua -> ditolak');
  PERFORM pg_temp.must_fail(format('SELECT * FROM fn_price_copy(%L, %L, %L, NULL, NULL)', t_cbd, v4, jsonb_build_array(v2)),
            '%belum punya harga berlaku%', 'R3 sumber tanpa harga berlaku ditolak');

  PERFORM pg_temp.must_fail(format('SELECT fn_price_end(%L, %L, NULL)', t_cbd, p3), '%tidak punya akses%',
            'R3 Vendor CBD tidak bisa mengakhiri harga');
  PERFORM fn_price_end(t_mc, p3, NULL);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM fn_price_lookup(v3, v_sup)), 'R3 harga diakhiri MC tidak berlaku lagi');

  PERFORM fn_link_save(t_spec, v_link, v_mat, v_sup, true, 'INACTIVE');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM fn_price_lookup(v2, v_sup)), 'R3/F10d link INACTIVE diabaikan lookup');
  PERFORM pg_temp.ok((SELECT problem FROM v_price_pending WHERE variant_id = v4) = 'Supplier nonaktif',
                     'R3 usulan dengan supplier nonaktif ditandai');
  PERFORM pg_temp.must_fail(format('SELECT fn_price_decide(%L, %L, ''APPROVE'', NULL)', t_mc,
            (SELECT jsonb_agg(id) FROM material_price WHERE variant_id = v4 AND status = 'PROPOSED')),
            '%nonaktif%', 'R3 approve usulan supplier nonaktif ditolak');
  PERFORM fn_link_save(t_spec, v_link, v_mat, v_sup, true, 'ACTIVE');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_material_price WHERE material_id = v_mat AND link_id = v_link2
                        AND state = 'BELUM ADA HARGA') = 4, 'R3 baris BELUM ADA HARGA untuk supplier kedua');

  -- ===== R4: model tanpa kode =====
  v_cat    := fn_option_save(t_spec, NULL, 'KATEGORI', 'Selftest Running', NULL, 'ACTIVE');
  v_last   := fn_option_save(t_spec, NULL, 'LAST', 'UJI-L01', NULL, 'ACTIVE');
  v_lastb  := fn_option_save(t_specb, NULL, 'LAST', 'UJI-LB1', NULL, 'ACTIVE');
  SELECT id INTO v_gender FROM model_option WHERE kind = 'GENDER' AND value = 'UNISEX';
  m_a := fn_model_save(t_spec, NULL, 'Uji Runner X', v_cat, NULL, v_gender, v_last, NULL, '[44, 37, 38, 39, 40, 42, 43]', 40);
  PERFORM pg_temp.ok((SELECT size_range FROM v_model WHERE id = m_a) = '37–40, 42–44', 'R4 ukuran tersimpan & label ringkas');
  PERFORM pg_temp.ok((SELECT name || '|' || factory_name || '|' || last_no FROM v_model WHERE id = m_a)
                     = 'UJI RUNNER X|SELFTEST PABRIK A|UJI-L01', 'R4 nama huruf besar, pabrik otomatis, last per pabrik');
  PERFORM pg_temp.must_fail(format('SELECT fn_model_save(%L, NULL, ''Uji Runner Y'', %L, NULL, NULL, %L, NULL, ''[40]'', NULL)',
            t_spec, v_cat, v_lastb), '%pabrik lain%', 'R4 Last pabrik lain ditolak');
  PERFORM pg_temp.must_fail(format('SELECT fn_model_save(%L, NULL, ''Uji Runner Y'', %L, NULL, NULL, NULL, NULL, ''[40, 41]'', 39)',
            t_spec, v_cat), '%Sample size%', 'R4 sample size di luar ukuran ditolak');
  PERFORM pg_temp.must_fail(format('SELECT fn_model_save(%L, NULL, ''uji  runner x'', %L, NULL, NULL, NULL, NULL, NULL, NULL)',
            t_spec, v_cat), '%sudah ada%', 'R4 nama model unik per pabrik');
  m_b := fn_model_save(t_specb, NULL, 'Uji Runner X', v_cat, NULL, NULL, v_lastb, NULL, NULL, NULL);
  PERFORM pg_temp.ok(m_b IS NOT NULL, 'R4 nama sama boleh di pabrik lain');
  PERFORM pg_temp.must_fail(format('SELECT fn_model_save(%L, %L, ''Uji Ganti'', %L, NULL, NULL, NULL, NULL, NULL, NULL)',
            t_specb, m_a, v_cat), '%pabrik lain%', 'R4 pabrik B tidak bisa mengubah model A');

  v_sheet := fn_season_add(t_spec, m_a, 'fh26');
  PERFORM pg_temp.must_fail(format('SELECT fn_season_add(%L, %L, ''SS27'')', t_specb, m_a), '%pabrik lain%',
            'R4 pabrik B tidak bisa menambah season model A');
  a1 := fn_article_save(t_spec, NULL, v_sheet, 'uji-01', 'black white');
  a2 := fn_article_save(t_spec, NULL, v_sheet, 'UJI-02', 'WHITE');
  a3 := fn_article_save(t_spec, NULL, v_sheet, 'UJI-03', 'GREY');

  -- ===== R4: specsheet per varian =====
  v_rev  := fn_revision_create(t_spec, v_sheet, 'EMPTY', 'SMS', NULL);
  -- nomor komponen bersama: kelipatan 10 kosong pertama di rentang kelompok 'a' (jangan bentrok dengan data user)
  SELECT g.n INTO v_no
    FROM component_group cg
    CROSS JOIN LATERAL generate_series(((cg.range_start + 9) / 10) * 10, cg.range_end, 10) AS g(n)
   WHERE cg.code = 'a' AND NOT EXISTS (SELECT 1 FROM component c WHERE c.number = g.n)
   ORDER BY g.n LIMIT 1;
  PERFORM pg_temp.ok(v_no IS NOT NULL, 'R4 ada nomor komponen kosong di kelompok a untuk data uji');
  v_comp := fn_component_add(t_spec, 'a', v_no, 'SELFTEST VAMP');
  l1 := fn_bom_add_line(t_spec, v_rev, v_comp, NULL, NULL, v_mat, '1.2mm', v_sup, NULL, 'black');
  PERFORM pg_temp.ok((SELECT count(*) FROM bom_cell WHERE bom_line_id = l1 AND color = 'BLACK' AND variant_id = v1) = 3,
                     'R4 isi warna dari kode -> 3 sel BLACK tersambung ke MSHU120BLK');
  PERFORM fn_bom_cell_set(t_spec, l1, a2, 'mshu120wht');
  PERFORM pg_temp.ok((SELECT color FROM bom_cell WHERE bom_line_id = l1 AND article_id = a2) = 'WHITE'
                     AND (SELECT variant_id FROM bom_cell WHERE bom_line_id = l1 AND article_id = a2) = v2,
                     'R4 Material Code diketik di sel -> warna WHITE');
  v_mat2 := fn_material_add(t_spec, 'UJI EVA', 'FOAM', 'SHT');
  ve := fn_variant_save(t_spec, NULL, v_mat2, 'EVAU030BLK', 'BLACK', '3MM', 'ACTIVE');
  PERFORM pg_temp.must_fail(format('SELECT fn_bom_cell_set(%L, %L, %L, ''EVAU030BLK'')', t_spec, l1, a2),
            '%tidak cocok%', 'R4 kode material lain di sel ditolak');
  PERFORM fn_bom_cell_set(t_spec, l1, a3, 'Grey');
  PERFORM pg_temp.ok((SELECT yellow FROM v_bom_grid WHERE id = l1) = 1, 'R4 warna belum terdaftar = 1 sel kuning');
  PERFORM pg_temp.ok((SELECT yellow_cells FROM v_revision_checklist WHERE revision_id = v_rev) = 1
                     AND (SELECT blocked FROM v_revision_checklist WHERE revision_id = v_rev), 'R4 checklist: sel kuning memblokir');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_publish(%L, %L, ''OTHER'', NULL)', t_spec, v_rev),
            '%sel kuning%', 'R4 terbit ditolak selama ada sel kuning');
  vg := fn_variant_save(t_spec, NULL, v_mat, 'MSHU120GRY', 'GREY', '1.2MM', 'ACTIVE');
  PERFORM pg_temp.ok((SELECT variant_id FROM bom_cell WHERE bom_line_id = l1 AND article_id = a3) = vg,
                     'R4 varian baru menyambung sel kuning otomatis');
  PERFORM pg_temp.must_fail(format('SELECT fn_bom_cell_set(%L, %L, %L, ''RED'')', t_specb, l1, a1),
            '%pabrik lain%', 'R4 pabrik B tidak bisa mengubah BOM pabrik A');
  PERFORM pg_temp.must_fail(format('SELECT fn_bom_add_line(%L, %L, %L, NULL, NULL, %L, ''1.2MM'', NULL, NULL, NULL)',
            t_spec, v_rev, v_comp, v_mat), '%sudah ada%', 'R4 komponen + material + thickness dobel ditolak');
  l2 := fn_bom_add_line(t_spec, v_rev, NULL, 15, 'uji lokal', v_mat2, '3mm', NULL, 'lem', NULL);
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_publish(%L, %L, ''OTHER'', NULL)', t_spec, v_rev),
            '%tanpa supplier%', 'R4 baris tanpa supplier memblokir terbit');
  PERFORM fn_bom_set_supplier(t_spec, l2, v_sup2);
  PERFORM fn_bom_set_process(t_spec, l2, ' lem kuning ');
  PERFORM fn_bom_cell_set(t_spec, l2, a1, 'black');
  PERFORM fn_link_save(t_spec, v_link2, v_mat, v_sup2, false, 'INACTIVE');      -- link material lain, tidak terpakai
  PERFORM pg_temp.ok((SELECT inactive_suppliers FROM v_revision_checklist WHERE revision_id = v_rev) IS NULL,
                     'R4 link INACTIVE yang tidak dipakai tidak memblokir');
  PERFORM fn_link_save(t_spec, v_link, v_mat, v_sup, true, 'INACTIVE');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_publish(%L, %L, ''OTHER'', NULL)', t_spec, v_rev),
            '%supplier nonaktif%', 'R4/F10d supplier material INACTIVE memblokir terbit');
  PERFORM fn_link_save(t_spec, v_link, v_mat, v_sup, true, 'ACTIVE');
  v_log := fn_revision_publish(t_spec, v_rev, 'OTHER', NULL);
  PERFORM pg_temp.ok((SELECT status FROM specsheet_revision WHERE id = v_rev) = 'PUBLISHED', 'R4 terbit setelah semua beres');

  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, %L, %L, ''MSHU120BLX'', ''BLACK'', ''1.2MM'', ''ACTIVE'')',
            t_spec, v1, v_mat), '%dokumen terbit%', 'R4 kode varian terpakai di dokumen terbit dikunci');
  PERFORM pg_temp.must_fail(format('SELECT fn_option_save(%L, %L, ''KATEGORI'', ''SELFTEST RUN'', NULL, ''ACTIVE'')', t_spec, v_cat),
            '%tidak bisa diubah%', 'R4 nilai pilihan dipakai model terbit dikunci');
  PERFORM fn_option_save(t_spec, v_cat, 'KATEGORI', 'SELFTEST RUNNING', NULL, 'INACTIVE');
  PERFORM pg_temp.ok((SELECT category FROM v_model WHERE id = m_a) = 'SELFTEST RUNNING', 'R4 pilihan INACTIVE tetap tampil di model lama');

  PERFORM fn_variant_save(t_spec, v2, v_mat, 'MSHU120WHT', 'WHITE', '1.2MM', 'INACTIVE');
  v_rev2 := fn_revision_create(t_spec, v_sheet, 'NEXT_REVISION', NULL, NULL);
  PERFORM pg_temp.ok((SELECT yellow_cells FROM v_revision_checklist WHERE revision_id = v_rev2) = 1,
                     'R4 revisi berikutnya: varian INACTIVE jadi sel kuning');
  PERFORM pg_temp.ok((SELECT yellow_cells FROM v_worklist_spec WHERE revision_id = v_rev2) = 1, 'R4 worklist spec menghitung sel kuning');
  PERFORM pg_temp.ok((SELECT codes FROM v_worklist_price_gap WHERE material_id = v_mat AND supplier_id = v_sup) = 'MSHU120GRY',
                     'R4 price gap per varian (GREY belum berharga)');
  PERFORM fn_bom_replace_material(t_spec, (SELECT id FROM bom_line WHERE revision_id = v_rev2 AND line_key =
                                    (SELECT line_key FROM bom_line WHERE id = l1)), v_mat, '1.5MM');
  PERFORM pg_temp.ok((SELECT yellow FROM v_bom_grid WHERE revision_id = v_rev2 AND thickness = '1.5MM') = 3,
                     'R4 ganti thickness tanpa varian -> semua sel kuning');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_model_list WHERE id IN (m_a, m_b)) = 2
                     AND (SELECT count(*) FROM v_recent_published WHERE model_id = m_a) = 1, 'R4 view model & terbit terbaru');

  -- ===== R5: CBD per varian =====
  c1 := fn_cbd_create(t_cbd, a1, 'NEW', NULL);
  PERFORM pg_temp.ok((SELECT material_code || '|' || thickness || '|' || price_source || '|' || trim_scale(price_original)::text
                        FROM v_cbd_line WHERE cbd_revision_id = c1 AND material_id = v_mat) = 'MSHU120BLK|1.2MM|MASTER|45000',
                     'R5 baris CBD membawa Material Code + thickness, harga master per varian');
  PERFORM pg_temp.ok((SELECT pc.price_gap FROM v_cbd_price_check pc JOIN cbd_line l ON l.id = pc.line_id
                       WHERE l.cbd_revision_id = c1 AND l.material_id = v_mat2) = 'NO_PRICE', 'R5 varian tanpa harga = NO_PRICE');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_header_set(%L, %L, ''RATE'', 16300)', t_mc, c1), '%tidak punya akses%',
            'R5 Manager Costing hanya membaca CBD');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_header_set(%L, %L, ''RATE'', 16300)', t_cbdb, c1), '%pabrik lain%',
            'R5 Vendor CBD pabrik B tidak bisa mengubah CBD pabrik A');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_header_set(%L, %L, ''SELLING_PRICE'', 500000)', t_cbd, c1), '%tidak valid%',
            'R5 selling price tidak disimpan di CBD');
  PERFORM fn_cbd_header_set(t_cbd, c1, 'RATE', 16300);
  PERFORM fn_cbd_line_set(t_cbd, l.id, 'YIELD', 2) FROM cbd_line l WHERE l.cbd_revision_id = c1;
  SELECT id INTO v_linke FROM material_supplier WHERE material_id = v_mat2 AND supplier_id = v_sup2;
  v_b3 := fn_price_propose(t_cbd, v_linke, jsonb_build_array(ve), 2.5, 'USD', fn_today(), 'Q-EVA');
  PERFORM pg_temp.ok((SELECT pending_prices FROM v_cbd_checklist WHERE cbd_revision_id = c1) = 1
                     AND (SELECT blocked FROM v_cbd_checklist WHERE cbd_revision_id = c1), 'R5 harga menunggu persetujuan memblokir');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_publish(%L, %L, ''OTHER'', NULL)', t_cbd, c1),
            '%menunggu persetujuan%', 'R5 CBD tidak bisa terbit selama ada harga menunggu');
  PERFORM fn_price_decide(t_mc, (SELECT jsonb_agg(id) FROM material_price WHERE batch_id = v_b3), 'APPROVE', NULL);
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_publish(%L, %L, ''OTHER'', NULL)', t_cbd, c1),
            '%Refresh Harga%', 'R5 harga baru disetujui -> wajib refresh dulu');
  n := fn_cbd_refresh_prices(t_cbd, c1);
  PERFORM pg_temp.ok(n = 1 AND (SELECT price_original FROM cbd_line WHERE cbd_revision_id = c1 AND material_id = v_mat2) = 2.5,
                     'R5 refresh harga mengambil harga varian yang baru disetujui');
  PERFORM fn_cbd_cost_set(t_cbd, (SELECT id FROM cbd_cost_item WHERE cbd_revision_id = c1 AND item_type = 'LABOUR'), 'AMOUNT', '1300');
  PERFORM fn_cbd_cost_set(t_cbd, (SELECT id FROM cbd_cost_item WHERE cbd_revision_id = c1 AND item_type = 'AMORTIZATION'), 'AMOUNT', '500');
  PERFORM fn_cbd_header_set(t_cbd, c1, 'TARGET_FOB', 90000);
  PERFORM fn_cbd_publish(t_cbd, c1, 'OTHER', NULL);
  PERFORM pg_temp.ok((SELECT po_factor FROM cbd_revision WHERE id = c1) = 1.25
                     AND (SELECT po_price = round(actual_fob * 1.25, 2) FROM v_cbd_recap WHERE cbd_revision_id = c1),
                     'R5 PO SMS = Actual FOB x 1,25 (dibekukan saat terbit)');
  UPDATE stage_setting SET po_factor = 1.30 WHERE stage = 'SMS';
  PERFORM pg_temp.ok((SELECT po_factor FROM v_cbd_recap WHERE cbd_revision_id = c1) = 1.25,
                     'R5 ubah faktor stage tidak mengubah CBD terbit');
  UPDATE stage_setting SET po_factor = 1.25 WHERE stage = 'SMS';
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM information_schema.columns
                                  WHERE table_name IN ('v_cbd_recap', 'cbd_revision') AND column_name IN ('selling_price', 'margin_pct')),
                     'R5 selling price & margin tidak ada di CBD');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, %L, %L, ''EVAU030BLX'', ''BLACK'', ''3MM'', ''ACTIVE'')',
            t_spec, ve, v_mat2), '%dokumen terbit%', 'R5 varian terpakai di CBD terbit dikunci');
  c2 := fn_cbd_create(t_cbd, a1, 'NEXT', NULL);
  PERFORM pg_temp.ok((SELECT count(*) FROM cbd_line WHERE cbd_revision_id = c2 AND yield_value = 2) = 2
                     AND (SELECT po_factor FROM v_cbd_recap WHERE cbd_revision_id = c2) = 1.25,
                     'R5 revisi berikutnya membawa Yield; draft memakai faktor stage');
  -- revisi specsheet berikutnya: baris material diganti -> CBD terbit PERLU REVISI
  PERFORM fn_variant_save(t_spec, v2, v_mat, 'MSHU120WHT', 'WHITE', '1.2MM', 'ACTIVE');
  PERFORM fn_bom_replace_material(t_spec, (SELECT id FROM bom_line WHERE revision_id = v_rev2 AND is_active AND thickness = '1.5MM'),
                                  v_mat, '1.2MM');
  PERFORM pg_temp.ok((SELECT yellow_cells FROM v_revision_checklist WHERE revision_id = v_rev2) = 0,
                     'R5 (spec) varian aktif lagi -> sel tersambung kembali');
  PERFORM fn_revision_publish(t_spec, v_rev2, 'MATERIAL', 'Ganti material uji');
  PERFORM pg_temp.ok((SELECT sync_status FROM cbd_revision WHERE id = c1) = 'NEEDS_REVISION',
                     'R5 specsheet berubah -> CBD terbit PERLU REVISI');
  PERFORM pg_temp.ok((SELECT kind || '|' || refresh_reason FROM v_worklist_cbd WHERE article_id = a1) = 'TO_REFRESH|SPEC',
                     'R5 draft CBD tertinggal specsheet -> perlu refresh');
  n := fn_cbd_refresh_from_spec(t_cbd, c2);
  PERFORM pg_temp.ok((SELECT count(*) FROM cbd_line WHERE cbd_revision_id = c2 AND status = 'ACTIVE' AND yield_value = 2) = 2,
                     'R5 refresh dari specsheet: Yield ikut lewat baris pengganti');

  -- ===== R6: Tugas Saya & pabrik =====
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM v_worklist_price_rejected WHERE material_id = v_mat AND code = 'MSHU120RED'),
                     'R6 usulan ditolak yang sudah diajukan ulang tidak muncul lagi');
  v_b3 := fn_price_propose(t_cbd, v_link, jsonb_build_array(vg), 50000, 'IDR', NULL, NULL);
  PERFORM fn_price_decide(t_mc, (SELECT jsonb_agg(id) FROM material_price WHERE batch_id = v_b3), 'REJECT', 'Terlalu mahal');
  PERFORM pg_temp.ok((SELECT reject_reason FROM v_worklist_price_rejected WHERE material_id = v_mat AND code = 'MSHU120GRY') = 'Terlalu mahal',
                     'R6 Tugas Saya CBD: usulan ditolak + alasan');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_worklist_cbd WHERE factory_id = (SELECT id FROM factory WHERE name = 'SELFTEST PABRIK B')) = 0
                     AND (SELECT count(*) FROM v_recent_published WHERE factory_id = (SELECT id FROM factory WHERE name = 'SELFTEST PABRIK A')) >= 2,
                     'R6 worklist & terbit terbaru membawa pabrik (filter di query)');

  -- ===== R7: copy lintas model =====
  PERFORM fn_option_save(t_spec, v_cat, 'KATEGORI', 'SELFTEST RUNNING', NULL, 'ACTIVE');
  PERFORM fn_link_save(t_spec, v_link2, v_mat, v_sup2, false, 'ACTIVE');
  v_cat2 := fn_option_save(t_spec, NULL, 'KATEGORI', 'SELFTEST SANDAL', NULL, 'ACTIVE');
  m_c := fn_model_save(t_spec, NULL, 'Uji Runner IN', v_cat, NULL, NULL, NULL, NULL, '[40]', NULL);
  m_d := fn_model_save(t_spec, NULL, 'Uji Sandal', v_cat2, NULL, NULL, NULL, NULL, '[40]', NULL);
  sh_c := fn_season_add(t_spec, m_c, 'FH26');
  sh_d := fn_season_add(t_spec, m_d, 'FH26');
  sh_b := fn_season_add(t_specb, m_b, 'FH26');
  ac1 := fn_article_save(t_spec, NULL, sh_c, 'UJI-IN1', 'BLACK');
  ad1 := fn_article_save(t_spec, NULL, sh_d, 'UJI-SD1', 'BLACK');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_create(%L, %L, ''COPY'', ''SMS'', %L)', t_spec, sh_c, sh_b),
            '%pabrik%', 'R7 copy dari model pabrik lain ditolak');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_create(%L, %L, ''COPY'', ''SMS'', %L)', t_spec, sh_c, sh_d),
            '%kategori%', 'R7 copy dari model kategori lain ditolak');
  rev_c := fn_revision_create(t_spec, sh_c, 'COPY', 'SMS', v_sheet);
  PERFORM pg_temp.ok((SELECT count(*) FROM bom_line WHERE revision_id = rev_c AND is_active)
                     = (SELECT count(*) FROM bom_line WHERE revision_id = v_rev2 AND is_active)
                     AND NOT EXISTS (SELECT 1 FROM bom_cell bc JOIN bom_line l ON l.id = bc.bom_line_id
                                      WHERE l.revision_id = rev_c AND bc.color IS NOT NULL),
                     'R7 copy lintas model: semua baris tersalin, warna kosong');
  PERFORM pg_temp.ok((SELECT parent_model_id FROM product_model WHERE id = m_c) = m_a, 'R7 model induk terisi otomatis');
  PERFORM pg_temp.ok(fn_sheet_origin_model(sh_c) = m_a, 'R7 model asal specsheet tercatat');
  PERFORM fn_bom_cell_set(t_spec, l.id, ac1, 'BLACK') FROM bom_line l WHERE l.revision_id = rev_c AND l.is_active;
  PERFORM fn_revision_publish(t_spec, rev_c, 'OTHER', NULL);
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_create(%L, %L, ''COPY'', %L)', t_cbd, ac1, ad1),
            '%model asal%', 'R7 CBD hanya dari model asal specsheet');
  c3 := fn_cbd_create(t_cbd, ac1, 'COPY', a1);
  PERFORM pg_temp.ok((SELECT yield_value FROM cbd_line WHERE cbd_revision_id = c3 AND material_id = v_mat2) = 2,
                     'R7 Yield ikut lewat origin_line_key bila induk + thickness sama');
  PERFORM pg_temp.ok((SELECT yield_value FROM cbd_line WHERE cbd_revision_id = c3 AND material_id = v_mat) IS NULL,
                     'R7 pencocokan identitas dimatikan (baris tanpa origin sumber -> Yield kosong)');
  PERFORM pg_temp.ok((SELECT exchange_rate FROM cbd_revision WHERE id = c3) = 16300
                     AND (SELECT target_fob FROM cbd_revision WHERE id = c3) IS NULL,
                     'R7 rekap: rate ikut, Target FOB kosong');
  PERFORM pg_temp.ok((SELECT amount FROM cbd_cost_item WHERE cbd_revision_id = c3 AND item_type = 'LABOUR') = 1300
                     AND (SELECT amount FROM cbd_cost_item WHERE cbd_revision_id = c3 AND item_type = 'AMORTIZATION') = 0,
                     'R7 biaya: hanya LOP ikut, Amortisasi kembali 0');
END;
$$;

-- ---------------------------------------------------------------- R8 (catatan uji E2E-R)
DO $$
DECLARE
  t_spec  text := pg_temp.tok('spec.a@selftest.invalid');
  t_cbd   text := pg_temp.tok('cbd.a@selftest.invalid');
  t_mc    text := pg_temp.tok('mc.a@selftest.invalid');
  t_cbdb  text := pg_temp.tok('cbd.b@selftest.invalid');
  t_specb text := pg_temp.tok('spec.b@selftest.invalid');
  v_sup   uuid := (SELECT id FROM supplier WHERE name = 'SELFTEST SUPPLIER SATU');
  v_sheet uuid := (SELECT sh.id FROM specsheet sh JOIN product_model pm ON pm.id = sh.model_id
                    WHERE pm.name = 'UJI RUNNER X' AND pm.factory_id = (SELECT id FROM factory WHERE name = 'SELFTEST PABRIK A'));
  c3      uuid := (SELECT cr.id FROM cbd_revision cr JOIN article a ON a.id = cr.article_id
                     JOIN specsheet sh ON sh.id = a.specsheet_id JOIN product_model pm ON pm.id = sh.model_id
                    WHERE a.code = 'UJI-IN1' AND cr.status = 'DRAFT'
                      AND pm.factory_id = (SELECT id FROM factory WHERE name = 'SELFTEST PABRIK A'));
  v_mat3 uuid; x1 uuid; x2 uuid; x3 uuid; v_link3 uuid; v_b uuid; l_eva uuid; p uuid;
BEGIN
  -- 1. Manager Costing mengajukan -> langsung berlaku; Vendor CBD tetap menunggu
  v_mat3 := fn_material_add(t_spec, 'UJI LINING', 'TEXTILE', 'YD');
  x1 := fn_variant_save(t_spec, NULL, v_mat3, 'LINU100BLK', 'BLACK', '1MM', 'ACTIVE');
  v_link3 := fn_link_save(t_spec, NULL, v_mat3, v_sup, true, 'ACTIVE');
  v_b := fn_price_propose(t_mc, v_link3, jsonb_build_array(x1), 10000, 'IDR', NULL, 'MC langsung');
  PERFORM pg_temp.ok((SELECT status || '|' || decided_by FROM material_price WHERE batch_id = v_b) = 'APPROVED|mc.a@selftest.invalid',
                     'R8 usulan Manager Costing langsung APPROVED (penyetuju = dirinya)');
  PERFORM pg_temp.ok((SELECT price FROM fn_price_lookup(x1, v_sup)) = 10000, 'R8 harga Manager Costing langsung berlaku');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_worklist_admin WHERE ref_id = v_b) = 0, 'R8 tidak muncul di Persetujuan Harga');

  -- 4. awalan Material Code (R9: peringatan saja, tidak ditolak — kasus ERP CANVAS 6 OZ)
  PERFORM pg_temp.ok((SELECT other_prefixes FROM fn_variant_code_hint(t_spec, v_mat3, 'LINX100CRM', NULL)) = 'LINU',
                     'R9 awalan beda diberi peringatan (hint other_prefixes)');
  PERFORM pg_temp.ok(fn_variant_save(t_spec, NULL, v_mat3, 'LINX100CRM', 'CREAM', '1MM', 'ACTIVE') IS NOT NULL,
                     'R9 awalan beda tetap bisa disimpan');
  x2 := fn_variant_save(t_spec, NULL, v_mat3, 'linu100wht', 'WHITE', '1MM', 'ACTIVE');
  PERFORM pg_temp.ok(x2 IS NOT NULL, 'R8 awalan sama diterima');
  -- R9: usulan Material Code dari varian yang sudah tercatat
  PERFORM pg_temp.ok((SELECT prefixes || '|' || thickness_codes || '|' || color_codes
                        FROM fn_variant_code_suggest(t_spec, v_mat3, ' black ', '1mm')) = 'LINU,LINX|100|BLK',
                     'R9 usulan kode: awalan material (paling sering dulu), kode thickness & warna se-pabrik');
  PERFORM pg_temp.ok((SELECT color_codes IS NULL AND thickness_codes = '100'
                        FROM fn_variant_code_suggest(t_spec, v_mat3, 'UNGU MUDA', '1MM')),
                     'R9 warna baru: kode warna kosong, bagian lain tetap diusulkan');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM fn_variant_code_suggest(t_specb, v_mat3, 'BLACK', '1MM')),
                     'R9 usulan kode tidak bisa dibaca pabrik lain');
  -- R9: tiga tingkat — TOLAK (kode / varian dobel), KONFIRMASI (arti bagian kode beda), INFO (hanya di form)
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, NULL, %L, ''LINU200WHT'', ''CREAM'', ''2MM'', ''ACTIVE'')', t_spec, v_mat3),
            'Perlu konfirmasi: kode warna WHT%', 'R9 kode warna sudah berarti WHITE dipakai untuk CREAM -> perlu konfirmasi');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, NULL, %L, ''LINU100GRN'', ''GREEN'', ''2MM'', ''ACTIVE'')', t_spec, v_mat3),
            'Perlu konfirmasi: kode thickness 100%', 'R9 kode thickness sudah berarti 1MM dipakai untuk 2MM -> perlu konfirmasi');
  x3 := fn_variant_save(t_spec, NULL, v_mat3, 'LINU200WHT', 'CREAM', '2MM', 'ACTIVE', true);
  PERFORM pg_temp.ok(x3 IS NOT NULL, 'R9 dengan konfirmasi tetap bisa disimpan (kode ERP yang menyimpang)');
  PERFORM fn_variant_save(t_spec, x3, v_mat3, 'LINU200WHT', 'CREAM', '2MM', 'INACTIVE');
  PERFORM pg_temp.ok((SELECT status FROM material_variant WHERE id = x3) = 'INACTIVE', 'R9 ubah status saja tidak ditanya konfirmasi lagi');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, NULL, %L, ''LINU100BLK'', ''NAVY'', ''1MM'', ''ACTIVE'', true)', t_spec, v_mat3),
            '%sudah dipakai%', 'R9 kode lengkap dobel tetap ditolak walau dikonfirmasi');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, NULL, %L, ''LINU100BL2'', ''black'', ''1mm'', ''ACTIVE'', true)', t_spec, v_mat3),
            '%sudah ada di material ini%', 'R9 material + thickness + warna dobel tetap ditolak walau dikonfirmasi');
  PERFORM pg_temp.ok(fn_variant_save(t_spec, NULL, v_mat3, 'LINU100W10', 'IVORY', '1MM', 'ACTIVE') IS NOT NULL
                     AND (SELECT color_codes FROM fn_variant_code_suggest(t_spec, v_mat3, 'WHITE', '1MM')) = 'WHT',
                     'R9 kode warna baru untuk warna lain tanpa bentrok = langsung tersimpan');
  -- R10: hapus varian yang tidak dipakai (harga berakhir / ditolak ikut terhapus)
  PERFORM pg_temp.ok(fn_variant_delete_block(x1) LIKE '%BERLAKU%', 'R10 varian berharga berlaku tidak bisa dihapus (alasan tampil)');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_delete(%L, %L)', t_spec, x1), '%tidak bisa dihapus%', 'R10 hapus varian berharga ditolak');
  PERFORM pg_temp.ok(fn_variant_delete_block((SELECT id FROM material_variant WHERE code = 'MSHU120BLK'
                       AND factory_id = (SELECT id FROM factory WHERE name = 'SELFTEST PABRIK A'))) LIKE '%specsheet%CBD%',
                     'R10 varian dipakai specsheet & CBD tidak bisa dihapus');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_delete(%L, %L)', t_cbd, x3), '%tidak punya akses%', 'R10 hapus varian butuh manage_master');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_delete(%L, %L)', t_specb, x3), '%pabrik lain%', 'R10 hapus varian pabrik lain ditolak');
  PERFORM fn_variant_save(t_spec, x3, v_mat3, 'LINU200WHT', 'CREAM', '2MM', 'ACTIVE');
  v_b := fn_price_propose(t_cbd, v_link3, jsonb_build_array(x3), 500, 'IDR', NULL, NULL);
  PERFORM fn_price_decide(t_mc, (SELECT jsonb_agg(id) FROM material_price WHERE batch_id = v_b), 'REJECT', 'uji hapus');
  PERFORM pg_temp.ok(fn_variant_delete_block(x3) IS NULL, 'R10 varian tanpa pemakaian (harga ditolak saja) boleh dihapus');
  PERFORM pg_temp.ok(fn_variant_delete(t_spec, x3) = 'LINU200WHT', 'R10 hapus varian mengembalikan kodenya');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM material_variant WHERE id = x3)
                     AND NOT EXISTS (SELECT 1 FROM material_price WHERE variant_id = x3)
                     AND EXISTS (SELECT 1 FROM audit_log WHERE entity_id = x3::text AND action = 'DELETE'),
                     'R10 varian & harga ditolaknya terhapus, tercatat di audit log');
  SELECT * INTO v_b FROM fn_price_copy(t_mc, x1, jsonb_build_array(x2), NULL, NULL);
  PERFORM pg_temp.ok((SELECT price FROM fn_price_lookup(x2, v_sup)) = 10000, 'R8 salin harga oleh Manager Costing langsung berlaku');
  PERFORM fn_variant_save(t_spec, x2, v_mat3, 'LINU100WHT', 'WHITE', '1MM', 'INACTIVE');
  PERFORM pg_temp.ok((SELECT status FROM material_variant WHERE id = x2) = 'INACTIVE', 'R8 ubah status varian tanpa ubah kode tetap bisa');

  -- 3. article tanpa batas 5
  PERFORM fn_article_save(t_spec, NULL, v_sheet, 'UJI-0' || g, 'WARNA ' || g) FROM generate_series(4, 7) g;
  PERFORM pg_temp.ok((SELECT count(*) FROM article WHERE specsheet_id = v_sheet) = 7, 'R8 7 article dalam satu season');
  PERFORM pg_temp.must_fail(format('SELECT fn_article_save(%L, NULL, %L, ''uji-07'', ''X'')', t_spec, v_sheet),
            '%sudah ada%', 'R8 kode article tetap unik per season');

  -- 5. ajukan harga master dari baris CBD
  SELECT l.id INTO l_eva FROM cbd_line l JOIN material m ON m.id = l.material_id
   WHERE l.cbd_revision_id = c3 AND m.name = 'UJI EVA' AND l.status = 'ACTIVE';
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_price_propose(%L, %L, 3, ''USD'', NULL, NULL)', t_cbdb, l_eva),
            '%pabrik lain%', 'R8 ajukan dari CBD: pabrik lain ditolak');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_price_propose(%L, %L, 3, NULL, NULL, NULL)', t_cbd, l_eva),
            '%Currency%', 'R8 ajukan dari CBD: currency wajib');
  v_b := fn_cbd_price_propose(t_cbd, l_eva, 3, 'USD', NULL, 'Q-CBD');
  SELECT id INTO p FROM material_price WHERE batch_id = v_b;
  PERFORM pg_temp.ok((SELECT status FROM material_price WHERE id = p) = 'PROPOSED'
                     AND (SELECT variant_id FROM material_price WHERE id = p) = (SELECT variant_id FROM cbd_line WHERE id = l_eva),
                     'R8 ajukan dari CBD = usulan harga master varian × supplier baris itu');
  PERFORM pg_temp.ok((SELECT pending FROM v_cbd_price_check WHERE line_id = l_eva), 'R8 baris CBD langsung bertanda menunggu');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_price_propose(%L, %L, 3.1, ''USD'', NULL, NULL)', t_mc, l_eva),
            '%menunggu approval%', 'R8 usulan ganda dari CBD ditolak');
  PERFORM fn_price_decide(t_mc, jsonb_build_array(p), 'APPROVE', NULL);
  v_b := fn_cbd_price_propose(t_mc, l_eva, 3.2, 'USD', fn_today() + 3, 'MC dari CBD');
  PERFORM pg_temp.ok((SELECT status FROM material_price WHERE batch_id = v_b) = 'APPROVED',
                     'R8 Manager Costing ajukan dari CBD langsung berlaku');
END;
$$;

SELECT 'SELFTEST LOLOS' AS hasil;
ROLLBACK;
