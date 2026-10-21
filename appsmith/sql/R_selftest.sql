-- ============================================================================
-- R_selftest: uji alur inti R3–R16 langsung di database, lalu DIBATALKAN (ROLLBACK): tidak ada data yang tersimpan.
-- Jalankan SETELAH sql/R_revisi_semua.sql, sql/R8_catatan_uji.sql, R9_kode_varian.sql R10_hapus_varian.sql, R11_perbaikan.sql, R11b_harga_batal.sql, R12_golive.sql, R13_cbd_stage.sql, R14_audit_stage.sql, R15_english.sql DAN R16_baku_thickness.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF),
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
            t_cbdb, v_link, jsonb_build_array(v1)), '%another factory%', 'R3 Vendor CBD pabrik B tidak bisa mengajukan harga pabrik A');
  PERFORM pg_temp.must_fail(format('SELECT fn_price_propose(%L, %L, %L, 100, NULL, NULL, NULL)',
            t_cbd, v_link, jsonb_build_array(v1)), '%Currency%', 'R3 currency wajib');

  v_batch := fn_price_propose(t_cbd, v_link, jsonb_build_array(v1, v2, v3, v4), 45000, 'IDR', fn_today(), 'Q-1');
  PERFORM pg_temp.ok((SELECT count(*) FROM material_price WHERE batch_id = v_batch AND status = 'PROPOSED') = 4,
                     'R3 satu pengajuan 4 varian = 4 usulan PROPOSED');
  PERFORM pg_temp.must_fail(format('SELECT fn_price_propose(%L, %L, %L, 46000, ''IDR'', NULL, NULL)',
            t_cbd, v_link, jsonb_build_array(v1)), '%waiting for approval%', 'R3 maks. satu usulan per varian + supplier');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_worklist_admin WHERE ref_id = v_batch) = 1, 'R3 Beranda MC: 1 baris per pengajuan');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_price_pending WHERE batch_id = v_batch AND problem IS NULL) = 4,
                     'R3 v_price_pending 4 baris tanpa masalah');

  SELECT id INTO p1 FROM material_price WHERE batch_id = v_batch AND variant_id = v1;
  SELECT id INTO p2 FROM material_price WHERE batch_id = v_batch AND variant_id = v2;
  SELECT id INTO p3 FROM material_price WHERE batch_id = v_batch AND variant_id = v3;
  SELECT id INTO p4 FROM material_price WHERE batch_id = v_batch AND variant_id = v4;
  PERFORM pg_temp.must_fail(format('SELECT fn_price_decide(%L, %L, ''APPROVE'', NULL)', t_cbd, jsonb_build_array(p1)),
            '%has no access%', 'R3 Vendor CBD tidak bisa approve');
  PERFORM pg_temp.must_fail(format('SELECT fn_price_decide(%L, %L, ''REJECT'', '' '')', t_mc, jsonb_build_array(p4)),
            '%reason%', 'R3 tolak tanpa alasan ditolak');
  n := fn_price_decide(t_mc, jsonb_build_array(p4), 'REJECT', 'Harga tidak sesuai');
  PERFORM pg_temp.ok(n = 1 AND (SELECT status FROM material_price WHERE id = p4) = 'REJECTED', 'R3 tolak 1 dengan alasan');
  n := fn_price_decide(t_mc, jsonb_build_array(p1, p2, p3), 'APPROVE', NULL);
  PERFORM pg_temp.ok(n = 3, 'R3 setujui 3 sekaligus');
  PERFORM pg_temp.ok((SELECT price FROM fn_price_lookup(v1, v_sup)) = 45000, 'R3 lookup harga varian = 45000');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_worklist_admin WHERE ref_id = v_batch) = 0, 'R3 pengajuan selesai hilang dari Beranda');

  PERFORM pg_temp.must_fail(format('SELECT fn_price_propose(%L, %L, %L, 47000, ''IDR'', %L, NULL)',
            t_cbd, v_link, jsonb_build_array(v1), fn_today() - 10), '%earlier%', 'R3 tanggal lebih awal dari harga berlaku ditolak');
  v_b2 := fn_price_propose(t_cbd, v_link, jsonb_build_array(v1), 47000, 'IDR', fn_today() + 1, 'Q-2');
  PERFORM pg_temp.ok((SELECT price FROM fn_price_lookup(v1, v_sup)) = 45000, 'R3 harga lama tetap berlaku sebelum approve');
  SELECT id INTO pn FROM material_price WHERE batch_id = v_b2;
  PERFORM fn_price_decide(t_mc, jsonb_build_array(pn), 'APPROVE', NULL);
  PERFORM pg_temp.ok((SELECT valid_to FROM material_price WHERE id = p1) = fn_today() + 1, 'R3 approve menutup harga lama per tanggal baru');
  PERFORM pg_temp.ok((SELECT price FROM fn_price_lookup(v1, v_sup, fn_today() + 1)) = 47000, 'R3 harga baru berlaku besok');

  SELECT * INTO r FROM fn_price_copy(t_cbd, v3, jsonb_build_array(v4), fn_today(), NULL);
  PERFORM pg_temp.ok(r.created = 1 AND r.skipped IS NULL, 'R3 salin harga NAVY -> RED (1 supplier berharga)');
  PERFORM pg_temp.ok((SELECT reference FROM material_price WHERE batch_id = r.batch_id) = 'Copied from MSHU120NVY',
                     'R3 referensi salinan otomatis');
  PERFORM pg_temp.must_fail(format('SELECT * FROM fn_price_copy(%L, %L, %L, NULL, NULL)', t_cbd, v3, jsonb_build_array(v4)),
            '%No prices were copied%', 'R3 salin ulang dilewati semua -> ditolak');
  PERFORM pg_temp.must_fail(format('SELECT * FROM fn_price_copy(%L, %L, %L, NULL, NULL)', t_cbd, v4, jsonb_build_array(v2)),
            '%has no active%', 'R3 sumber tanpa harga berlaku ditolak');

  PERFORM pg_temp.must_fail(format('SELECT fn_price_end(%L, %L, NULL)', t_cbd, p3), '%has no access%',
            'R3 Vendor CBD tidak bisa mengakhiri harga');
  PERFORM fn_price_end(t_mc, p3, NULL);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM fn_price_lookup(v3, v_sup)), 'R3 harga diakhiri MC tidak berlaku lagi');

  PERFORM fn_link_save(t_spec, v_link, v_mat, v_sup, true, 'INACTIVE');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM fn_price_lookup(v2, v_sup)), 'R3/F10d link INACTIVE diabaikan lookup');
  PERFORM pg_temp.ok((SELECT problem FROM v_price_pending WHERE variant_id = v4) = 'Supplier inactive',
                     'R3 usulan dengan supplier nonaktif ditandai');
  PERFORM pg_temp.must_fail(format('SELECT fn_price_decide(%L, %L, ''APPROVE'', NULL)', t_mc,
            (SELECT jsonb_agg(id) FROM material_price WHERE variant_id = v4 AND status = 'PROPOSED')),
            '%inactive%', 'R3 approve usulan supplier nonaktif ditolak');
  PERFORM fn_link_save(t_spec, v_link, v_mat, v_sup, true, 'ACTIVE');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_material_price WHERE material_id = v_mat AND link_id = v_link2
                        AND state = 'NO PRICE') = 4, 'R3 baris BELUM ADA HARGA untuk supplier kedua');

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
            t_spec, v_cat, v_lastb), '%another factory%', 'R4 Last pabrik lain ditolak');
  PERFORM pg_temp.must_fail(format('SELECT fn_model_save(%L, NULL, ''Uji Runner Y'', %L, NULL, NULL, NULL, NULL, ''[40, 41]'', 39)',
            t_spec, v_cat), '%Sample size%', 'R4 sample size di luar ukuran ditolak');
  PERFORM pg_temp.must_fail(format('SELECT fn_model_save(%L, NULL, ''uji  runner x'', %L, NULL, NULL, NULL, NULL, NULL, NULL)',
            t_spec, v_cat), '%already%', 'R4 nama model unik per pabrik');
  m_b := fn_model_save(t_specb, NULL, 'Uji Runner X', v_cat, NULL, NULL, v_lastb, NULL, NULL, NULL);
  PERFORM pg_temp.ok(m_b IS NOT NULL, 'R4 nama sama boleh di pabrik lain');
  PERFORM pg_temp.must_fail(format('SELECT fn_model_save(%L, %L, ''Uji Ganti'', %L, NULL, NULL, NULL, NULL, NULL, NULL)',
            t_specb, m_a, v_cat), '%another factory%', 'R4 pabrik B tidak bisa mengubah model A');

  v_sheet := fn_season_add(t_spec, m_a, 'fh26');
  PERFORM pg_temp.must_fail(format('SELECT fn_season_add(%L, %L, ''SS27'')', t_specb, m_a), '%another factory%',
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
            '%does not match%', 'R4 kode material lain di sel ditolak');
  PERFORM fn_bom_cell_set(t_spec, l1, a3, 'Grey');
  PERFORM pg_temp.ok((SELECT yellow FROM v_bom_grid WHERE id = l1) = 1, 'R4 warna belum terdaftar = 1 sel kuning');
  PERFORM pg_temp.ok((SELECT yellow_cells FROM v_revision_checklist WHERE revision_id = v_rev) = 1
                     AND (SELECT blocked FROM v_revision_checklist WHERE revision_id = v_rev), 'R4 checklist: sel kuning memblokir');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_publish(%L, %L, ''OTHER'', NULL)', t_spec, v_rev),
            '%yellow cells%', 'R4 terbit ditolak selama ada sel kuning');
  vg := fn_variant_save(t_spec, NULL, v_mat, 'MSHU120GRY', 'GREY', '1.2MM', 'ACTIVE');
  PERFORM pg_temp.ok((SELECT variant_id FROM bom_cell WHERE bom_line_id = l1 AND article_id = a3) = vg,
                     'R4 varian baru menyambung sel kuning otomatis');
  PERFORM pg_temp.must_fail(format('SELECT fn_bom_cell_set(%L, %L, %L, ''RED'')', t_specb, l1, a1),
            '%another factory%', 'R4 pabrik B tidak bisa mengubah BOM pabrik A');
  PERFORM pg_temp.must_fail(format('SELECT fn_bom_add_line(%L, %L, %L, NULL, NULL, %L, ''1.2MM'', NULL, NULL, NULL)',
            t_spec, v_rev, v_comp, v_mat), '%already%', 'R4 komponen + material + thickness dobel ditolak');
  l2 := fn_bom_add_line(t_spec, v_rev, NULL, 15, 'uji lokal', v_mat2, '3mm', NULL, 'lem', NULL);
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_publish(%L, %L, ''OTHER'', NULL)', t_spec, v_rev),
            '%have no supplier%', 'R4 baris tanpa supplier memblokir terbit');
  PERFORM fn_bom_set_supplier(t_spec, l2, v_sup2);
  PERFORM fn_bom_set_process(t_spec, l2, ' lem kuning ');
  PERFORM fn_bom_cell_set(t_spec, l2, a1, 'black');
  PERFORM fn_link_save(t_spec, v_link2, v_mat, v_sup2, false, 'INACTIVE');      -- link material lain, tidak terpakai
  PERFORM pg_temp.ok((SELECT inactive_suppliers FROM v_revision_checklist WHERE revision_id = v_rev) IS NULL,
                     'R4 link INACTIVE yang tidak dipakai tidak memblokir');
  PERFORM fn_link_save(t_spec, v_link, v_mat, v_sup, true, 'INACTIVE');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_publish(%L, %L, ''OTHER'', NULL)', t_spec, v_rev),
            '%suppliers are inactive%', 'R4/F10d supplier material INACTIVE memblokir terbit');
  PERFORM fn_link_save(t_spec, v_link, v_mat, v_sup, true, 'ACTIVE');
  v_log := fn_revision_publish(t_spec, v_rev, 'OTHER', NULL);
  PERFORM pg_temp.ok((SELECT status FROM specsheet_revision WHERE id = v_rev) = 'PUBLISHED', 'R4 terbit setelah semua beres');

  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, %L, %L, ''MSHU120BLX'', ''BLACK'', ''1.2MM'', ''ACTIVE'')',
            t_spec, v1, v_mat), '%published documents%', 'R4 kode varian terpakai di dokumen terbit dikunci');
  PERFORM pg_temp.must_fail(format('SELECT fn_option_save(%L, %L, ''KATEGORI'', ''SELFTEST RUN'', NULL, ''ACTIVE'')', t_spec, v_cat),
            '%cannot be changed%', 'R4 nilai pilihan dipakai model terbit dikunci');
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
  PERFORM pg_temp.ok((SELECT yellow FROM v_bom_grid WHERE revision_id = v_rev2 AND thickness = '1.5 MM') = 3,
                     'R4 ganti thickness tanpa varian -> semua sel kuning');
  PERFORM pg_temp.ok((SELECT count(*) FROM v_model_list WHERE id IN (m_a, m_b)) = 2
                     AND (SELECT count(*) FROM v_recent_published WHERE model_id = m_a) = 1, 'R4 view model & terbit terbaru');

  -- ===== R5: CBD per varian =====
  c1 := fn_cbd_create(t_cbd, a1, 'NEW', NULL);
  PERFORM pg_temp.ok((SELECT material_code || '|' || thickness || '|' || price_source || '|' || trim_scale(price_original)::text
                        FROM v_cbd_line WHERE cbd_revision_id = c1 AND material_id = v_mat) = 'MSHU120BLK|1.2 MM|MASTER|45000',
                     'R5 baris CBD membawa Material Code + thickness, harga master per varian');
  PERFORM pg_temp.ok((SELECT pc.price_gap FROM v_cbd_price_check pc JOIN cbd_line l ON l.id = pc.line_id
                       WHERE l.cbd_revision_id = c1 AND l.material_id = v_mat2) = 'NO_PRICE', 'R5 varian tanpa harga = NO_PRICE');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_header_set(%L, %L, ''RATE'', 16300)', t_mc, c1), '%has no access%',
            'R5 Manager Costing hanya membaca CBD');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_header_set(%L, %L, ''RATE'', 16300)', t_cbdb, c1), '%another factory%',
            'R5 Vendor CBD pabrik B tidak bisa mengubah CBD pabrik A');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_header_set(%L, %L, ''SELLING_PRICE'', 500000)', t_cbd, c1), '%Invalid field%',
            'R5 selling price tidak disimpan di CBD');
  PERFORM fn_cbd_header_set(t_cbd, c1, 'RATE', 16300);
  PERFORM fn_cbd_line_set(t_cbd, l.id, 'YIELD', 2) FROM cbd_line l WHERE l.cbd_revision_id = c1;
  SELECT id INTO v_linke FROM material_supplier WHERE material_id = v_mat2 AND supplier_id = v_sup2;
  v_b3 := fn_price_propose(t_cbd, v_linke, jsonb_build_array(ve), 2.5, 'USD', fn_today(), 'Q-EVA');
  PERFORM pg_temp.ok((SELECT pending_prices FROM v_cbd_checklist WHERE cbd_revision_id = c1) = 1
                     AND (SELECT blocked FROM v_cbd_checklist WHERE cbd_revision_id = c1), 'R5 harga menunggu persetujuan memblokir');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_publish(%L, %L, ''OTHER'', NULL)', t_cbd, c1),
            '%waiting for Manager Costing%', 'R5 CBD tidak bisa terbit selama ada harga menunggu');
  PERFORM fn_price_decide(t_mc, (SELECT jsonb_agg(id) FROM material_price WHERE batch_id = v_b3), 'APPROVE', NULL);
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_publish(%L, %L, ''OTHER'', NULL)', t_cbd, c1),
            '%Refresh Prices%', 'R5 harga baru disetujui -> wajib refresh dulu');
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
            t_spec, ve, v_mat2), '%published documents%', 'R5 varian terpakai di CBD terbit dikunci');
  c2 := fn_cbd_create(t_cbd, a1, 'NEXT', NULL);
  PERFORM pg_temp.ok((SELECT count(*) FROM cbd_line WHERE cbd_revision_id = c2 AND yield_value = 2) = 2
                     AND (SELECT po_factor FROM v_cbd_recap WHERE cbd_revision_id = c2) = 1.25,
                     'R5 revisi berikutnya membawa Yield; draft memakai faktor stage');
  -- revisi specsheet berikutnya: baris material diganti -> CBD terbit PERLU REVISI
  PERFORM fn_variant_save(t_spec, v2, v_mat, 'MSHU120WHT', 'WHITE', '1.2MM', 'ACTIVE');
  PERFORM fn_bom_replace_material(t_spec, (SELECT id FROM bom_line WHERE revision_id = v_rev2 AND is_active AND thickness = '1.5 MM'),
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
            '%same factory%', 'R7 copy dari model pabrik lain ditolak');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_create(%L, %L, ''COPY'', ''SMS'', %L)', t_spec, sh_c, sh_d),
            '%same category%', 'R7 copy dari model kategori lain ditolak');
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
            '%origin model%', 'R7 CBD hanya dari model asal specsheet');
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
            'Confirmation needed: color code WHT%', 'R9 kode warna sudah berarti WHITE dipakai untuk CREAM -> perlu konfirmasi');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, NULL, %L, ''LINU100GRN'', ''GREEN'', ''2MM'', ''ACTIVE'')', t_spec, v_mat3),
            'Confirmation needed: thickness code 100%', 'R9 kode thickness sudah berarti 1MM dipakai untuk 2MM -> perlu konfirmasi');
  x3 := fn_variant_save(t_spec, NULL, v_mat3, 'LINU200WHT', 'CREAM', '2MM', 'ACTIVE', true);
  PERFORM pg_temp.ok(x3 IS NOT NULL, 'R9 dengan konfirmasi tetap bisa disimpan (kode ERP yang menyimpang)');
  PERFORM fn_variant_save(t_spec, x3, v_mat3, 'LINU200WHT', 'CREAM', '2MM', 'INACTIVE');
  PERFORM pg_temp.ok((SELECT status FROM material_variant WHERE id = x3) = 'INACTIVE', 'R9 ubah status saja tidak ditanya konfirmasi lagi');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, NULL, %L, ''LINU100BLK'', ''NAVY'', ''1MM'', ''ACTIVE'', true)', t_spec, v_mat3),
            '%already used%', 'R9 kode lengkap dobel tetap ditolak walau dikonfirmasi');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, NULL, %L, ''LINU100BL2'', ''black'', ''1mm'', ''ACTIVE'', true)', t_spec, v_mat3),
            '%already exists in this material%', 'R9 material + thickness + warna dobel tetap ditolak walau dikonfirmasi');
  PERFORM pg_temp.ok(fn_variant_save(t_spec, NULL, v_mat3, 'LINU100W10', 'IVORY', '1MM', 'ACTIVE') IS NOT NULL
                     AND (SELECT color_codes FROM fn_variant_code_suggest(t_spec, v_mat3, 'WHITE', '1MM')) = 'WHT',
                     'R9 kode warna baru untuk warna lain tanpa bentrok = langsung tersimpan');
  -- R10: hapus varian yang tidak dipakai (harga berakhir / ditolak ikut terhapus)
  PERFORM pg_temp.ok(fn_variant_delete_block(x1) LIKE '%ACTIVE%', 'R10 varian berharga berlaku tidak bisa dihapus (alasan tampil)');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_delete(%L, %L)', t_spec, x1), '%cannot be deleted%', 'R10 hapus varian berharga ditolak');
  PERFORM pg_temp.ok(fn_variant_delete_block((SELECT id FROM material_variant WHERE code = 'MSHU120BLK'
                       AND factory_id = (SELECT id FROM factory WHERE name = 'SELFTEST PABRIK A'))) LIKE '%specsheet%CBD%',
                     'R10 varian dipakai specsheet & CBD tidak bisa dihapus');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_delete(%L, %L)', t_cbd, x3), '%has no access%', 'R10 hapus varian butuh manage_master');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_delete(%L, %L)', t_specb, x3), '%another factory%', 'R10 hapus varian pabrik lain ditolak');
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
            '%already%', 'R8 kode article tetap unik per season');

  -- 5. ajukan harga master dari baris CBD
  SELECT l.id INTO l_eva FROM cbd_line l JOIN material m ON m.id = l.material_id
   WHERE l.cbd_revision_id = c3 AND m.name = 'UJI EVA' AND l.status = 'ACTIVE';
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_price_propose(%L, %L, 3, ''USD'', NULL, NULL)', t_cbdb, l_eva),
            '%another factory%', 'R8 ajukan dari CBD: pabrik lain ditolak');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_price_propose(%L, %L, 3, NULL, NULL, NULL)', t_cbd, l_eva),
            '%Currency%', 'R8 ajukan dari CBD: currency wajib');
  v_b := fn_cbd_price_propose(t_cbd, l_eva, 3, 'USD', NULL, 'Q-CBD');
  SELECT id INTO p FROM material_price WHERE batch_id = v_b;
  PERFORM pg_temp.ok((SELECT status FROM material_price WHERE id = p) = 'PROPOSED'
                     AND (SELECT variant_id FROM material_price WHERE id = p) = (SELECT variant_id FROM cbd_line WHERE id = l_eva),
                     'R8 ajukan dari CBD = usulan harga master varian × supplier baris itu');
  PERFORM pg_temp.ok((SELECT pending FROM v_cbd_price_check WHERE line_id = l_eva), 'R8 baris CBD langsung bertanda menunggu');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_price_propose(%L, %L, 3.1, ''USD'', NULL, NULL)', t_mc, l_eva),
            '%waiting for approval%', 'R8 usulan ganda dari CBD ditolak');
  PERFORM fn_price_decide(t_mc, jsonb_build_array(p), 'APPROVE', NULL);
  v_b := fn_cbd_price_propose(t_mc, l_eva, 3.2, 'USD', fn_today() + 3, 'MC dari CBD');
  PERFORM pg_temp.ok((SELECT status FROM material_price WHERE batch_id = v_b) = 'APPROVED',
                     'R8 Manager Costing ajukan dari CBD langsung berlaku');
END;
$$;

-- ---------------------------------------------------------------- R11 (skalabilitas, bug, alur)
DO $$
DECLARE
  t_spec  text := pg_temp.tok('spec.a@selftest.invalid');
  t_cbd   text := pg_temp.tok('cbd.a@selftest.invalid');
  t_mc    text := pg_temp.tok('mc.a@selftest.invalid');
  t_brand text := pg_temp.tok('brand@selftest.invalid');
  f_a     uuid := (SELECT id FROM factory WHERE name = 'SELFTEST PABRIK A');
  v_sup   uuid := (SELECT id FROM supplier WHERE name = 'SELFTEST SUPPLIER SATU');
  v_sup2  uuid := (SELECT id FROM supplier WHERE name = 'SELFTEST SUPPLIER DUA');
  v_mat   uuid := (SELECT id FROM material WHERE name = 'UJI MESH' AND factory_id = (SELECT id FROM factory WHERE name = 'SELFTEST PABRIK A'));
  v_mat2  uuid := (SELECT id FROM material WHERE name = 'UJI EVA' AND factory_id = (SELECT id FROM factory WHERE name = 'SELFTEST PABRIK A'));
  m_a     uuid := (SELECT id FROM product_model WHERE name = 'UJI RUNNER X' AND factory_id = (SELECT id FROM factory WHERE name = 'SELFTEST PABRIK A'));
  v_cat   uuid := (SELECT category_id FROM product_model WHERE name = 'UJI RUNNER X' AND factory_id = (SELECT id FROM factory WHERE name = 'SELFTEST PABRIK A'));
  v_sheet uuid; a1 uuid; c2 uuid; c4 uuid; c5 uuid; v_log uuid; v_link uuid; v_b uuid; p_old uuid; p_new uuid;
  v_s uuid; v_m uuid; v_mold uuid; sh_old uuid; sh_new uuid; ao uuid; an uuid; r_old uuid; r_new uuid; vp uuid; vp2 uuid; vq uuid;
  v_rev3 uuid; lx uuid; ly uuid; ls uuid; l_eva uuid; l_mesh uuid;
  n integer; d numeric; r record; v_diff jsonb;
BEGIN
  SELECT sh.id INTO v_sheet FROM specsheet sh WHERE sh.model_id = m_a AND sh.season = 'FH26';
  SELECT id INTO a1 FROM article WHERE specsheet_id = v_sheet AND code = 'UJI-01';
  SELECT id INTO c2 FROM cbd_revision WHERE article_id = a1 AND status = 'DRAFT';
  PERFORM pg_temp.ok(c2 IS NOT NULL, 'R11 data uji: draft CBD UJI-01 dari blok R5 ada');

  -- ===== S7: audit ramping =====
  v_s := fn_supplier_save(t_spec, NULL, 'SELFTEST SUP AUDIT', 'ACTIVE');
  PERFORM pg_temp.ok((SELECT before_data IS NULL AND after_data IS NULL FROM audit_log
                       WHERE entity = 'supplier' AND entity_id = v_s::text AND action = 'INSERT'),
                     'R11/S7 INSERT tercatat tanpa salinan isi');
  PERFORM fn_supplier_save(t_spec, v_s, 'SELFTEST SUP AUDIT DUA', 'ACTIVE');
  PERFORM pg_temp.ok((SELECT before_data ->> 'name' = 'SELFTEST SUP AUDIT' AND after_data ->> 'name' = 'SELFTEST SUP AUDIT DUA'
                             AND NOT before_data ? 'status' AND NOT after_data ? 'updated_at'
                        FROM audit_log WHERE entity = 'supplier' AND entity_id = v_s::text AND action = 'UPDATE'
                       ORDER BY id DESC LIMIT 1),
                     'R11/S7 UPDATE hanya mencatat kolom yang berubah (lama -> baru)');
  PERFORM fn_supplier_save(t_spec, v_s, 'SELFTEST SUP AUDIT DUA', 'ACTIVE');
  PERFORM pg_temp.ok((SELECT count(*) FROM audit_log WHERE entity = 'supplier' AND entity_id = v_s::text AND action = 'UPDATE') = 1,
                     'R11/S7 simpan tanpa perubahan tidak dicatat');
  PERFORM pg_temp.ok((SELECT audit_size_bytes > 0 AND audit_entries >= 0 FROM v_system_summary),
                     'R11/S8 ringkasan System Admin: ukuran audit log tersedia');

  -- ===== T54: akhiri harga AKAN BERLAKU = batal, harga sebelumnya berlaku lagi =====
  SELECT ms.id INTO v_link FROM material_supplier ms WHERE ms.material_id = v_mat AND ms.supplier_id = v_sup;
  vp := fn_variant_save(t_spec, NULL, v_mat, 'MSHU120PNK', 'PINK', '1.2MM', 'ACTIVE');
  v_b := fn_price_propose(t_mc, v_link, jsonb_build_array(vp), 10000, 'IDR', fn_today() - 5, 'LAMA');
  SELECT id INTO p_old FROM material_price WHERE batch_id = v_b;
  v_b := fn_price_propose(t_mc, v_link, jsonb_build_array(vp), 12000, 'IDR', fn_today() + 30, 'BARU');
  SELECT id INTO p_new FROM material_price WHERE batch_id = v_b;
  PERFORM pg_temp.ok((SELECT valid_to FROM material_price WHERE id = p_old) = fn_today() + 30,
                     'R11/T54 harga baru (akan berlaku) menutup harga lama per tanggal mulainya');
  PERFORM fn_price_end(t_mc, p_new, NULL);
  PERFORM pg_temp.ok((SELECT valid_to FROM material_price WHERE id = p_old) IS NULL
                     AND (SELECT price FROM fn_price_lookup(vp, v_sup, fn_today() + 40)) = 10000,
                     'R11/T54 akhiri harga AKAN BERLAKU -> harga lama dibuka lagi, tidak ada celah tanpa harga');
  PERFORM pg_temp.ok((SELECT valid_to = valid_from FROM material_price WHERE id = p_new), 'R11/T54 harga yang dibatalkan jadi 0 hari');
  PERFORM pg_temp.ok((SELECT state FROM v_material_price WHERE id = p_new) = 'CANCELLED'
                     AND (SELECT state FROM v_material_price WHERE id = p_old) = 'ACTIVE'
                     AND NOT EXISTS (SELECT 1 FROM v_material_price WHERE variant_id = vp AND link_id = v_link AND state = 'UPCOMING'),
                     'R11b keterangan: harga dibatalkan = DIBATALKAN, harga lama BERLAKU lagi (form Tambah Harga memakai ini)');
  -- tambah lagi dengan tanggal mulai sama -> akhiri lagi: harga pertama yang sudah dibatalkan TIDAK boleh hidup lagi
  v_b := fn_price_propose(t_mc, v_link, jsonb_build_array(vp), 12500, 'IDR', fn_today() + 30, 'BARU 2');
  PERFORM fn_price_end(t_mc, (SELECT id FROM material_price WHERE batch_id = v_b), NULL);
  PERFORM pg_temp.ok((SELECT state FROM v_material_price WHERE id = p_new) = 'CANCELLED'
                     AND (SELECT valid_to FROM material_price WHERE id = p_old) IS NULL
                     AND (SELECT count(*) FROM v_material_price WHERE variant_id = vp AND link_id = v_link AND state = 'CANCELLED') = 2
                     AND NOT EXISTS (SELECT 1 FROM v_material_price WHERE variant_id = vp AND link_id = v_link AND state = 'UPCOMING')
                     AND (SELECT price FROM fn_price_lookup(vp, v_sup, fn_today() + 40)) = 10000,
                     'R11b tambah -> akhiri -> tambah lagi (tanggal sama) -> akhiri: harga yang dibatalkan tidak hidup lagi');
  PERFORM fn_price_end(t_mc, p_old, NULL);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM fn_price_lookup(vp, v_sup)), 'R11/T54 harga BERLAKU tetap diakhiri per hari ini');
  vp2 := fn_variant_save(t_spec, NULL, v_mat, 'MSHU120TEL', 'TEAL', '1.2MM', 'ACTIVE');
  v_b := fn_price_propose(t_mc, v_link, jsonb_build_array(vp2), 9000, 'IDR', fn_today() + 30, 'BARU SAJA');
  PERFORM fn_price_end(t_mc, (SELECT id FROM material_price WHERE batch_id = v_b), NULL);
  PERFORM pg_temp.ok((SELECT string_agg(state, ',' ORDER BY state) FROM v_material_price WHERE variant_id = vp2 AND link_id = v_link)
                     = 'CANCELLED,NO PRICE',
                     'R11b varian yang hanya punya harga dibatalkan tetap BELUM ADA HARGA');
  -- T55: usulan yang sudah diproses tidak bisa dibatalkan / diproses lagi
  v_b := fn_price_propose(t_cbd, v_link, jsonb_build_array(vp), 11000, 'IDR', NULL, 'T55');
  SELECT id INTO p_new FROM material_price WHERE batch_id = v_b;
  PERFORM fn_price_decide(t_mc, jsonb_build_array(p_new), 'APPROVE', NULL);
  PERFORM pg_temp.must_fail(format('SELECT fn_price_cancel(%L, %L)', t_cbd, p_new), '%not processed yet%',
            'R11/T55 batal setelah disetujui ditolak (harga yang disetujui tidak terhapus)');
  PERFORM pg_temp.must_fail(format('SELECT fn_price_decide(%L, %L, ''REJECT'', ''x'')', t_mc, jsonb_build_array(p_new)),
            '%already processed%', 'R11/T55 tolak usulan yang sudah disetujui ditolak');

  -- ===== T57: material & model dikunci setelah dipakai dokumen terbit =====
  PERFORM pg_temp.must_fail(format('SELECT fn_material_update(%L, %L, ''UJI MESH BARU'', ''TEXTILE'', ''YD'', ''ACTIVE'', ''CATALOG'')',
            t_spec, v_mat), '%cannot be changed%published%', 'R11/T57 nama material terpakai di dokumen terbit dikunci');
  PERFORM pg_temp.must_fail(format('SELECT fn_material_update(%L, %L, ''UJI MESH'', ''TEXTILE'', ''M'', ''ACTIVE'', ''CATALOG'')',
            t_spec, v_mat), '%cannot be changed%published%', 'R11/T57 UoM material terpakai dikunci');
  PERFORM fn_material_update(t_spec, v_mat, 'uji mesh', 'textile', 'yd', 'ACTIVE', 'CATALOG');
  PERFORM pg_temp.ok((SELECT name FROM material WHERE id = v_mat) = 'UJI MESH', 'R11/T57 simpan ulang tanpa perubahan tetap bisa');
  v_m := fn_material_add(t_spec, 'UJI BELUM DIPAKAI', 'TEXTILE', 'YD');
  PERFORM fn_material_update(t_spec, v_m, 'UJI BELUM DIPAKAI 2', 'TEXTILE', 'M', 'ACTIVE', 'CATALOG');
  PERFORM pg_temp.ok((SELECT name || '|' || uom FROM material WHERE id = v_m) = 'UJI BELUM DIPAKAI 2|M',
                     'R11/T57 material belum dipakai dokumen terbit tetap bisa diubah');
  PERFORM pg_temp.must_fail(format('SELECT fn_model_save(%L, %L, ''Uji Runner Z'', %L, NULL, NULL, NULL, NULL, ''[40]'', NULL)',
            t_spec, m_a, v_cat), '%cannot be changed%published%', 'R11/T57 nama model dengan specsheet terbit dikunci');

  -- ===== S2: material belum ada harga = 2 season terakhir (yang punya specsheet terbit) per pabrik =====
  vq := fn_variant_save(t_spec, NULL, v_mat, 'MSHU120ORG', 'ORANGE', '1.2MM', 'ACTIVE');
  v_mold := fn_model_save(t_spec, NULL, 'Uji Lama', v_cat, NULL, NULL, NULL, NULL, '[40]', NULL);
  sh_old := fn_season_add(t_spec, v_mold, 'SS20');
  sh_new := fn_season_add(t_spec, v_mold, 'SS26');
  ao := fn_article_save(t_spec, NULL, sh_old, 'UJI-L1', 'PINK');
  an := fn_article_save(t_spec, NULL, sh_new, 'UJI-L2', 'ORANGE');
  r_old := fn_revision_create(t_spec, sh_old, 'EMPTY', 'SMS', NULL);
  PERFORM fn_bom_add_line(t_spec, r_old, (SELECT id FROM component WHERE name = 'SELFTEST VAMP'), NULL, NULL, v_mat, '1.2MM', v_sup, NULL, 'PINK');
  PERFORM fn_revision_publish(t_spec, r_old, 'OTHER', NULL);
  r_new := fn_revision_create(t_spec, sh_new, 'EMPTY', 'SMS', NULL);
  PERFORM fn_bom_add_line(t_spec, r_new, (SELECT id FROM component WHERE name = 'SELFTEST VAMP'), NULL, NULL, v_mat, '1.2MM', v_sup, NULL, 'ORANGE');
  PERFORM fn_revision_publish(t_spec, r_new, 'OTHER', NULL);
  PERFORM pg_temp.ok((SELECT codes FROM v_worklist_price_gap WHERE material_id = v_mat AND supplier_id = v_sup) LIKE '%MSHU120ORG%'
                     AND (SELECT codes FROM v_worklist_price_gap WHERE material_id = v_mat AND supplier_id = v_sup) NOT LIKE '%MSHU120PNK%',
                     'R11/S2 price gap: season SS26 dihitung, season lama SS20 (di luar 2 season terakhir) tidak');

  -- ===== T58: hapus baris hasil Ganti material = batalkan penggantian =====
  v_rev3 := fn_revision_create(t_spec, v_sheet, 'NEXT_REVISION', NULL, NULL);
  SELECT id INTO lx FROM bom_line WHERE revision_id = v_rev3 AND is_active AND material_id = v_mat AND parent_line_key IS NULL;
  ls := fn_bom_add_sub(t_spec, lx, 'sub uji', v_mat2, '3mm', v_sup2, NULL);
  ly := fn_bom_replace_material(t_spec, lx, v_mat, '1.5MM');
  PERFORM pg_temp.ok((SELECT parent_line_key FROM bom_line WHERE id = ls) = (SELECT line_key FROM bom_line WHERE id = ly),
                     'R11/T58 (awal) subkomponen pindah ke baris pengganti');
  PERFORM pg_temp.ok((SELECT undo_replace AND undo_material = 'UJI MESH 1.2 MM' FROM v_bom_grid WHERE id = ly)
                     AND NOT (SELECT undo_replace FROM v_bom_grid WHERE id = ls),
                     'R11/T58 grid: baris pengganti bertanda bisa dibatalkan (material lama tampil), baris biasa tidak');
  n := fn_bom_delete_line(t_spec, ly);
  PERFORM pg_temp.ok(n = 0 AND NOT EXISTS (SELECT 1 FROM bom_line WHERE id = ly)
                     AND (SELECT is_active FROM bom_line WHERE id = lx)
                     AND (SELECT parent_line_key FROM bom_line WHERE id = ls) = (SELECT line_key FROM bom_line WHERE id = lx),
                     'R11/T58 hapus baris pengganti -> baris lama aktif lagi beserta subkomponennya');
  PERFORM pg_temp.ok((SELECT yellow FROM v_bom_grid WHERE id = lx) = 0, 'R11/T58 Material Code baris lama tersambung lagi');
  n := fn_bom_delete_line(t_spec, ls);
  PERFORM pg_temp.ok(n = 1 AND NOT EXISTS (SELECT 1 FROM bom_line WHERE id = ls), 'R11/T58 hapus baris biasa tetap menghapus');
  PERFORM fn_revision_delete_draft(t_spec, v_rev3);

  -- ===== A4: rincian perubahan (cost bridge) =====
  IF (SELECT stale_prices FROM v_cbd_checklist WHERE cbd_revision_id = c2) > 0 THEN
    PERFORM fn_cbd_refresh_prices(t_cbd, c2);
  END IF;
  SELECT id INTO l_mesh FROM cbd_line WHERE cbd_revision_id = c2 AND status = 'ACTIVE' AND material_id = v_mat;
  SELECT id INTO l_eva FROM cbd_line WHERE cbd_revision_id = c2 AND status = 'ACTIVE' AND material_id = v_mat2;
  PERFORM fn_cbd_header_set(t_cbd, c2, 'RATE', 17000);
  PERFORM fn_cbd_line_set(t_cbd, l_mesh, 'YIELD', 2.5);
  PERFORM fn_cbd_line_set(t_cbd, l_eva, 'LOSS', 3);
  PERFORM fn_cbd_cost_set(t_cbd, (SELECT id FROM cbd_cost_item WHERE cbd_revision_id = c2 AND item_type = 'LABOUR'), 'AMOUNT', '1500');
  PERFORM fn_cbd_cost_add(t_cbd, c2, 'OTHER', 'Assembling', 7550, NULL);
  d := (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = c2)
     - (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = fn_cbd_prev_published(c2));
  PERFORM pg_temp.ok((SELECT sum(amount) FROM fn_cbd_bridge(c2)) = d, 'R11/A4 jumlah rincian = selisih Actual FOB (persis)');
  PERFORM pg_temp.ok((SELECT string_agg(DISTINCT category, ',' ORDER BY category) FROM fn_cbd_bridge(c2))
                     = 'EX_RATE,LOP,MATERIAL,OTHER,YIELD',
                     'R11/A4 kategori otomatis: kurs, LOP, harga material, biaya lain, yield/loss');
  PERFORM pg_temp.ok((SELECT description FROM fn_cbd_bridge(c2) WHERE category = 'EX_RATE') = 'Exchange rate 16.300 → 17.000',
                     'R11/A4 uraian kurs berformat Indonesia');
  PERFORM pg_temp.ok((SELECT count(*) FROM fn_cbd_bridge(c2) WHERE category = 'COMPONENT') = 0,
                     'R11/A4 baris hasil ganti material dicocokkan lewat identitas (bukan hapus + tambah)');
  PERFORM pg_temp.ok((SELECT count(*) FROM fn_cbd_bridge_view(t_cbd, c2)) = (SELECT count(*) FROM fn_cbd_bridge(c2))
                     AND NOT EXISTS (SELECT 1 FROM fn_cbd_bridge_view(t_brand, c2)),
                     'R11/A4 rincian draft: Vendor CBD melihat, Brand tidak');
  SELECT key INTO r FROM fn_cbd_bridge(c2) WHERE category = 'YIELD' LIMIT 1;
  v_log := fn_cbd_publish(t_cbd, c2, NULL, NULL,
                          jsonb_build_array(jsonb_build_object('key', r.key, 'category', 'COMPONENT', 'description', 'Yield vamp dikoreksi')));
  SELECT diff INTO v_diff FROM change_log WHERE id = v_log;
  PERFORM pg_temp.ok((SELECT count(*) FROM jsonb_array_elements(v_diff -> 'rows') x
                       WHERE x ->> 'key' = r.key AND x ->> 'category' = 'COMPONENT' AND x ->> 'description' = 'Yield vamp dikoreksi'
                         AND x ->> 'auto_category' = 'YIELD') = 1,
                     'R11/A4 kategori & uraian yang diubah vendor tersimpan (nilai tetap dari sistem)');
  PERFORM pg_temp.ok((SELECT (v_diff ->> 'fob')::numeric - (v_diff ->> 'prev_fob')::numeric) = d
                     AND (SELECT reason FROM change_log WHERE id = v_log) LIKE 'Exchange rate +%',
                     'R11/A4 change log: selisih FOB tersimpan, alasan kosong = ringkasan per kategori');
  PERFORM pg_temp.ok((SELECT count(*) FROM fn_cbd_bridge_view(t_brand, c2)) = jsonb_array_length(v_diff -> 'rows'),
                     'R11/A4 rincian revisi terbit dibaca dari change log (Brand juga bisa melihat)');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_publish(%L, %L, NULL, NULL, %L)', t_cbd, c2,
            jsonb_build_array(jsonb_build_object('key', 'x', 'category', 'NGAWUR'))), '%is published%',
            'R11/A4 revisi terbit tidak bisa diterbitkan ulang');

  -- ===== A1/T56: baris belum berharga = peringatan (tidak memblokir); Tanpa biaya (alasan wajib) =====
  c4 := fn_cbd_create(t_cbd, a1, 'NEXT', NULL);
  PERFORM fn_material_update(t_cbd, v_mat2, 'UJI EVA', 'FOAM', 'SHT', 'ACTIVE', 'QUOTATION');
  n := fn_cbd_refresh_prices(t_cbd, c4);
  SELECT id INTO l_eva FROM cbd_line WHERE cbd_revision_id = c4 AND status = 'ACTIVE' AND material_id = v_mat2;
  PERFORM pg_temp.ok((SELECT yield_value IS NOT NULL AND price_original IS NULL FROM v_cbd_line WHERE id = l_eva)
                     AND (SELECT unpriced_count = 1 AND blank_count = 0 AND NOT blocked AND unpriced_list LIKE '%UJI EVA%'
                            FROM v_cbd_checklist WHERE cbd_revision_id = c4),
                     'R11/T56 baris ber-Yield belum berharga: peringatan + daftar baris, tidak memblokir');
  BEGIN                                   -- terbit lolos (lalu dibatalkan lewat exception)
    PERFORM fn_cbd_publish(t_cbd, c4, 'OTHER', 'uji', NULL);
    RAISE EXCEPTION 'uji_batal';
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.ok(SQLERRM = 'uji_batal', 'R11/T56 terbit tetap bisa dengan baris belum berharga (cost 0) — ' || SQLERRM);
  END;
  BEGIN                                   -- Yield dikosongkan sementara (dibatalkan lewat exception)
    UPDATE cbd_line SET yield_value = NULL WHERE id = l_eva;
    PERFORM pg_temp.ok((SELECT unpriced_count = 0 AND blank_count = 1 AND NOT blocked AND unpriced_list IS NULL
                          FROM v_cbd_checklist WHERE cbd_revision_id = c4)
                       AND (SELECT unpriced_count = 1 AND no_yield_count = 0 FROM v_cbd_recap WHERE cbd_revision_id = c4),
                       'R11/T56 baris tanpa harga & tanpa Yield tidak didaftar (blank_count saja)');
    RAISE EXCEPTION 'uji_batal';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'uji_batal' THEN RAISE; END IF;
  END;
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_set_no_charge(%L, %L, true, ''  '')', t_cbd, l_eva), '%reason%',
            'R11/A1 tanpa biaya wajib alasan');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_set_no_charge(%L, %L, true, ''x'')', t_mc, l_eva), '%has no access%',
            'R11/A1 Manager Costing tidak bisa menandai tanpa biaya');
  PERFORM fn_cbd_set_no_charge(t_cbd, l_eva, true, 'harga termasuk baris vamp');
  PERFORM pg_temp.ok((SELECT unpriced_count = 0 AND no_charge_count = 1 AND NOT blocked FROM v_cbd_checklist WHERE cbd_revision_id = c4)
                     AND (SELECT cost_per_pair FROM v_cbd_line WHERE id = l_eva) = 0,
                     'R11/A1 tanpa biaya: tidak memblokir, cost 0');
  PERFORM fn_cbd_set_quotation(t_cbd, l_eva, 5, 'USD', 'Q-UJI');
  PERFORM pg_temp.ok((SELECT NOT no_charge AND no_charge_reason IS NULL FROM cbd_line WHERE id = l_eva),
                     'R11/A1 isi harga quotation membatalkan tanpa biaya');
  PERFORM fn_cbd_set_no_charge(t_cbd, l_eva, true, 'harga termasuk baris vamp');
  PERFORM pg_temp.ok((SELECT description FROM fn_cbd_bridge(c4) WHERE category = 'MATERIAL') LIKE '%set to no charge (harga termasuk baris vamp)%'
                     AND (SELECT sum(amount) FROM fn_cbd_bridge(c4))
                         = (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = c4) - (SELECT actual_fob FROM v_cbd_recap WHERE cbd_revision_id = c2),
                     'R11/A1+A4 rincian: baris dijadikan tanpa biaya, jumlah tetap = selisih FOB');
  PERFORM fn_cbd_publish(t_cbd, c4, NULL, 'Eva termasuk vamp', NULL);
  PERFORM pg_temp.ok((SELECT reason FROM change_log WHERE doc_type = 'CBD' AND revision_id = c4) = 'Eva termasuk vamp',
                     'R11/A4 alasan yang diisi vendor dipakai');
  c5 := fn_cbd_create(t_cbd, a1, 'NEXT', NULL);
  PERFORM pg_temp.ok((SELECT no_charge AND no_charge_reason = 'harga termasuk baris vamp' FROM cbd_line
                       WHERE cbd_revision_id = c5 AND status = 'ACTIVE' AND material_id = v_mat2),
                     'R11/A1 tanda tanpa biaya ikut ke revisi berikutnya');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM fn_cbd_bridge(c5)), 'R11/A4 revisi tanpa perubahan biaya = rincian kosong');

  -- ---- R12 (T60/T61/T65): batas lampiran 3,5 MB, index harga di baris CBD, fungsi override dihapus
  PERFORM pg_temp.must_fail(format('SELECT fn_attachment_add(%L, %L, %L, %L, NULL)', t_spec, a1, 'besar.pdf',
            encode(decode('255044462d', 'hex') || convert_to(repeat('x', 3670012), 'UTF8'), 'base64')),
            '%3.5 MB%', 'R12/T60 lampiran article > 3,5 MB ditolak');
  PERFORM pg_temp.ok(fn_attachment_add(t_spec, a1, 'pas.pdf',
            encode(decode('255044462d', 'hex') || convert_to(repeat('x', 3670011), 'UTF8'), 'base64'), NULL) IS NOT NULL,
            'R12/T60 lampiran article tepat 3,5 MB diterima');
  PERFORM pg_temp.must_fail(format('SELECT fn_change_log_attach(%L, %L, %L, %L)', t_spec,
            (SELECT cl.id FROM change_log cl WHERE cl.doc_type = 'SPECSHEET' AND cl.created_by = 'spec.a@selftest.invalid' ORDER BY cl.id LIMIT 1), 'besar.png',
            encode(decode('89504e470d0a1a0a', 'hex') || convert_to(repeat('x', 3670009), 'UTF8'), 'base64')),
            '%3.5 MB%', 'R12/T60 gambar change log > 3,5 MB ditolak');
  PERFORM pg_temp.ok(to_regclass('ix_cbd_line_material_price') IS NOT NULL, 'R12/T61 index cbd_line(material_price_id) ada');
  PERFORM pg_temp.ok(to_regprocedure('fn_cbd_clear_override(text,uuid)') IS NULL
                     AND to_regprocedure('fn_cbd_override_price(text,uuid,numeric,text,text)') IS NULL,
                     'R12/T65 fungsi override sudah dihapus');
END;
$$;

-- ---------------------------------------------------------------- R13: CBD per stage
DO $$
DECLARE
  t_spec text := pg_temp.tok('spec.a@selftest.invalid');
  t_cbd  text := pg_temp.tok('cbd.a@selftest.invalid');
  t_mc   text := pg_temp.tok('mc.a@selftest.invalid');
  v_cat uuid; v_sup uuid; v_comp uuid; v_mat uuid; v_var uuid; v_link uuid; v_b uuid;
  m uuid; sh uuid; x1 uuid; x2 uuid; rs0 uuid; rs1 uuid; rg0 uuid; rg1 uuid; rg2 uuid;
  cs uuid; cg uuid; cx uuid; n integer;
BEGIN
  SELECT pm.category_id INTO v_cat FROM product_model pm JOIN factory f ON f.id = pm.factory_id
   WHERE f.name = 'SELFTEST PABRIK A' LIMIT 1;
  SELECT id INTO v_sup FROM supplier WHERE name = 'SELFTEST SUPPLIER SATU';
  SELECT id INTO v_comp FROM component WHERE name = 'SELFTEST VAMP';
  v_mat  := fn_material_add(t_spec, 'UJI STAGE MESH', 'TEXTILE', 'YD');
  v_var  := fn_variant_save(t_spec, NULL, v_mat, 'MSTU100BLK', 'BLACK', '1MM', 'ACTIVE');
  v_link := fn_link_save(t_spec, NULL, v_mat, v_sup, true, 'ACTIVE');
  v_b    := fn_price_propose(t_cbd, v_link, jsonb_build_array(v_var), 30000, 'IDR', fn_today(), 'Q-STAGE');
  PERFORM fn_price_decide(t_mc, (SELECT jsonb_agg(id) FROM material_price WHERE batch_id = v_b), 'APPROVE', NULL);

  m  := fn_model_save(t_spec, NULL, 'Uji Stage', v_cat, NULL, NULL, NULL, NULL, '[40]', NULL);
  sh := fn_season_add(t_spec, m, 'FH27');
  x1 := fn_article_save(t_spec, NULL, sh, 'UJI-S1', 'BLACK');
  x2 := fn_article_save(t_spec, NULL, sh, 'UJI-S2', 'BLACK');
  rs0 := fn_revision_create(t_spec, sh, 'EMPTY', 'SMS', NULL);
  PERFORM fn_bom_add_line(t_spec, rs0, v_comp, NULL, NULL, v_mat, '1MM', v_sup, NULL, 'black');
  PERFORM fn_revision_publish(t_spec, rs0, 'OTHER', NULL);

  cs := fn_cbd_create(t_cbd, x1, 'NEW', NULL);
  PERFORM fn_cbd_header_set(t_cbd, cs, 'RATE', 16300);
  PERFORM fn_cbd_line_set(t_cbd, l.id, 'YIELD', 2) FROM cbd_line l WHERE l.cbd_revision_id = cs;

  -- specsheet SMS r1 (stage sama) -> draft SMS wajib refresh, stage & nomor tetap
  rs1 := fn_revision_create(t_spec, sh, 'NEXT_REVISION', NULL, NULL);
  PERFORM fn_revision_publish(t_spec, rs1, 'OTHER', 'uji');
  PERFORM pg_temp.ok((SELECT draft_stale AND draft_spec_label = 'SMS r1' FROM v_cbd_article WHERE id = x1)
                     AND (SELECT kind || '|' || refresh_reason FROM v_worklist_cbd WHERE article_id = x1) = 'TO_REFRESH|SPEC',
                     'R13 specsheet SMS r1 terbit -> draft SMS perlu refresh');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_publish(%L, %L, ''OTHER'', NULL)', t_cbd, cs),
            '%reference SMS specsheet%Refresh%', 'R13 draft SMS tertinggal SMS r1 tidak bisa terbit');
  n := fn_cbd_refresh_from_spec(t_cbd, cs);
  PERFORM pg_temp.ok((SELECT stage || ' r' || revision_no FROM cbd_revision WHERE id = cs) = 'SMS r0'
                     AND (SELECT specsheet_revision_id FROM cbd_revision WHERE id = cs) = rs1,
                     'R13 refresh: acuan SMS r1, CBD tetap SMS r0');

  -- specsheet GTM r0 terbit saat CBD SMS masih draft (kasus user) -> CBD SMS tetap bisa diterbitkan
  rg0 := fn_revision_create(t_spec, sh, 'NEXT_STAGE', NULL, NULL);
  PERFORM fn_revision_publish(t_spec, rg0, 'OTHER', 'uji');
  PERFORM pg_temp.ok(NOT (SELECT draft_stale FROM v_cbd_article WHERE id = x1)
                     AND NOT (SELECT spec_stale OR blocked FROM v_cbd_checklist WHERE cbd_revision_id = cs)
                     AND (SELECT kind FROM v_worklist_cbd WHERE article_id = x1) = 'IN_PROGRESS',
                     'R13 specsheet GTM terbit tidak membuat draft SMS tertinggal');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_refresh_from_spec(%L, %L)', t_cbd, cs),
            '%already uses the latest published SMS specsheet%', 'R13 refresh tidak memindahkan draft SMS ke GTM');
  PERFORM fn_cbd_publish(t_cbd, cs, 'OTHER', NULL);
  PERFORM pg_temp.ok((SELECT stage || ' r' || revision_no || '|' || po_factor FROM cbd_revision WHERE id = cs) = 'SMS r0|1.2500',
                     'R13 CBD SMS r0 terbit dengan PO SMS walau specsheet sudah GTM');
  PERFORM pg_temp.ok((SELECT pub_behind FROM v_cbd_article WHERE id = x1)
                     AND (SELECT kind || '|' || refresh_reason FROM v_worklist_cbd WHERE article_id = x1) = 'TO_REVISE|STAGE',
                     'R13 CBD terbit tertinggal stage -> perlu CBD GTM (chip & Tugas Saya)');

  -- specsheet GTM r1 tanpa perubahan: CBD SMS tidak dipindah acuannya ke GTM
  rg1 := fn_revision_create(t_spec, sh, 'NEXT_REVISION', NULL, NULL);
  PERFORM fn_revision_publish(t_spec, rg1, 'OTHER', 'uji');
  PERFORM pg_temp.ok((SELECT specsheet_revision_id = rs1 AND sync_status = 'IN_SYNC' FROM cbd_revision WHERE id = cs),
                     'R13 sinkron hanya di stage yang sama (acuan CBD SMS tetap SMS r1)');

  -- pilihan stage
  PERFORM pg_temp.ok((SELECT string_agg(stage || ':' || available || ':' || is_default || ':' || next_label, ',' ORDER BY stage_order)
                        FROM fn_cbd_stage_options(t_cbd, x1)) = 'SMS:true:false:SMS r1,GTM:true:true:GTM r0',
                     'R13 pilihan stage x1: SMS r1 / GTM r0 (default GTM)');
  PERFORM pg_temp.ok((SELECT string_agg(stage || ':' || available || ':' || is_default, ',' ORDER BY stage_order)
                        FROM fn_cbd_stage_options(t_cbd, x2)) = 'SMS:true:false,GTM:true:true',
                     'R13 pilihan stage x2 (belum ada CBD): SMS & GTM');
  cx := fn_cbd_create(t_cbd, x2, 'NEW', NULL, 'SMS');
  PERFORM pg_temp.ok((SELECT stage || ' r' || revision_no FROM cbd_revision WHERE id = cx) = 'SMS r0'
                     AND (SELECT specsheet_revision_id FROM cbd_revision WHERE id = cx) = rs1
                     AND (SELECT NOT draft_stale AND draft_spec_label = 'SMS r1' FROM v_cbd_article WHERE id = x2),
                     'R13 CBD SMS bisa dibuat setelah specsheet GTM terbit (acuan SMS r1)');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_create(%L, %L, ''NEXT'', NULL, ''PROD'')', t_cbd, x1),
            '%No published%', 'R13 stage tanpa specsheet terbit ditolak');

  -- revisi berikutnya ke GTM, lalu tidak boleh mundur ke SMS
  cg := fn_cbd_create(t_cbd, x1, 'NEXT', NULL);
  PERFORM pg_temp.ok((SELECT stage || ' r' || revision_no FROM cbd_revision WHERE id = cg) = 'GTM r0'
                     AND (SELECT specsheet_revision_id FROM cbd_revision WHERE id = cg) = rg1
                     AND (SELECT count(*) FROM cbd_line WHERE cbd_revision_id = cg AND yield_value = 2) = 1,
                     'R13 tanpa pilihan stage = stage specsheet terbaru (GTM r0, Yield dibawa)');
  PERFORM fn_cbd_publish(t_cbd, cg, 'OTHER', 'uji', NULL);
  PERFORM pg_temp.ok(NOT (SELECT pub_behind FROM v_cbd_article WHERE id = x1)
                     AND NOT EXISTS (SELECT 1 FROM v_worklist_cbd WHERE article_id = x1),
                     'R13 CBD GTM terbit -> tidak ada tugas lagi');
  PERFORM pg_temp.ok((SELECT available::text || ':' || note FROM fn_cbd_stage_options(t_cbd, x1) WHERE stage = 'SMS')
                     = 'false:A GTM CBD is already published', 'R13 pilihan SMS tertutup setelah CBD GTM terbit');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_create(%L, %L, ''NEXT'', NULL, ''SMS'')', t_cbd, x1),
            '%earlier stage%', 'R13 tidak bisa membuat CBD SMS setelah CBD GTM terbit');

  -- specsheet GTM r2 men-drop x2 -> draft SMS x2 hanya bisa dihapus
  rg2 := fn_revision_create(t_spec, sh, 'NEXT_REVISION', NULL, NULL);
  PERFORM fn_rev_article_set(t_spec, rg2, x2, 'DROPPED');
  PERFORM fn_revision_publish(t_spec, rg2, 'OTHER', 'uji');
  PERFORM pg_temp.must_fail(format('SELECT fn_cbd_header_set(%L, %L, ''RATE'', 17000)', t_cbd, cx),
            '%dropped%', 'R13 article di-drop di specsheet terbaru -> draft SMS terkunci');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM fn_cbd_stage_options(t_cbd, x2) WHERE available)
                     AND (SELECT note FROM fn_cbd_stage_options(t_cbd, x2) WHERE stage = 'SMS') LIKE '%dropped%',
                     'R13 article di-drop di specsheet terbaru -> tidak ada stage yang bisa dipilih');
  PERFORM fn_cbd_delete_draft(t_cbd, cx);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM cbd_revision WHERE id = cx), 'R13 draft SMS article di-drop bisa dihapus');
END;
$$;

-- ---------------------------------------------------------------- R14: 5 stage (Preview), label, stage boleh melompat
DO $$
DECLARE
  t_spec text := pg_temp.tok('spec.a@selftest.invalid');
  t_cbd  text := pg_temp.tok('cbd.a@selftest.invalid');
  t_mc   text := pg_temp.tok('mc.a@selftest.invalid');
  v_cat uuid; v_sup uuid; v_comp uuid; v_mat uuid; v_var uuid; v_link uuid; v_b uuid;
  m uuid; sh uuid; x1 uuid; rp0 uuid; rv0 uuid; rg0 uuid; cv uuid;
BEGIN
  PERFORM pg_temp.ok(array_to_string(fn_stages(), ',') = 'PULL,PREV,SMS,GTM,PROD'
                     AND fn_stage_order('PREV') = 2 AND fn_stage_order('PROD') = 5
                     AND fn_rev_label('PULL', 0) = 'Pullover r0' AND fn_rev_label('PREV', 1) = 'Preview r1'
                     AND fn_rev_label('SMS', 2) = 'SMS r2' AND fn_rev_label('PROD', 0) = 'Production r0'
                     AND fn_rev_label(NULL, NULL) IS NULL,
                     'R14 urutan & label stage');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM specsheet_revision WHERE stage_order IS DISTINCT FROM fn_stage_order(stage))
                     AND NOT EXISTS (SELECT 1 FROM cbd_revision WHERE stage_order IS DISTINCT FROM fn_stage_order(stage)),
                     'R14 stage_order data lama sudah dinomori ulang');

  SELECT pm.category_id INTO v_cat FROM product_model pm JOIN factory f ON f.id = pm.factory_id
   WHERE f.name = 'SELFTEST PABRIK A' LIMIT 1;
  SELECT id INTO v_sup FROM supplier WHERE name = 'SELFTEST SUPPLIER SATU';
  SELECT id INTO v_comp FROM component WHERE name = 'SELFTEST VAMP';
  v_mat  := fn_material_add(t_spec, 'UJI PREVIEW MESH', 'TEXTILE', 'YD');
  v_var  := fn_variant_save(t_spec, NULL, v_mat, 'MSTV100BLK', 'BLACK', '1MM', 'ACTIVE');
  v_link := fn_link_save(t_spec, NULL, v_mat, v_sup, true, 'ACTIVE');
  v_b    := fn_price_propose(t_cbd, v_link, jsonb_build_array(v_var), 20000, 'IDR', fn_today(), 'Q-PREV');
  PERFORM fn_price_decide(t_mc, (SELECT jsonb_agg(id) FROM material_price WHERE batch_id = v_b), 'APPROVE', NULL);

  m  := fn_model_save(t_spec, NULL, 'Uji Preview', v_cat, NULL, NULL, NULL, NULL, '[40]', NULL);
  sh := fn_season_add(t_spec, m, 'FH27');
  x1 := fn_article_save(t_spec, NULL, sh, 'UJI-P1', 'BLACK');
  rp0 := fn_revision_create(t_spec, sh, 'EMPTY', NULL, NULL);
  PERFORM fn_bom_add_line(t_spec, rp0, v_comp, NULL, NULL, v_mat, '1MM', v_sup, NULL, 'black');
  PERFORM fn_revision_publish(t_spec, rp0, 'OTHER', NULL);
  PERFORM pg_temp.ok((SELECT stage || ':' || stage_order FROM specsheet_revision WHERE id = rp0) = 'PULL:1'
                     AND (SELECT spec_label_pub FROM v_model_list WHERE specsheet_id = sh) = 'Pullover r0 · PUBLISHED',
                     'R14 revisi awal tanpa stage = Pullover r0 (label di Model List)');

  -- stage berikutnya tanpa pilihan = Preview
  rv0 := fn_revision_create(t_spec, sh, 'NEXT_STAGE', NULL, NULL);
  PERFORM pg_temp.ok((SELECT stage || ':' || stage_order || ':' || revision_no FROM specsheet_revision WHERE id = rv0) = 'PREV:2:0',
                     'R14 stage berikutnya dari Pullover = Preview r0');
  PERFORM fn_revision_publish(t_spec, rv0, 'OTHER', 'uji');
  PERFORM pg_temp.ok((SELECT spec_pub_label || '|' || spec_pub_stage FROM v_cbd_article WHERE id = x1) = 'Preview r0|PREV',
                     'R14 label specsheet terbit Preview r0 di CBD');

  -- CBD di stage Preview
  PERFORM pg_temp.ok((SELECT string_agg(stage || ':' || available || ':' || is_default || ':' || spec_label || ':' || next_label, ','
                                        ORDER BY stage_order)
                        FROM fn_cbd_stage_options(t_cbd, x1)) = 'PULL:true:false:Pullover r0:Pullover r0,PREV:true:true:Preview r0:Preview r0',
                     'R14 pilihan stage CBD: Pullover & Preview (default Preview)');
  cv := fn_cbd_create(t_cbd, x1, 'NEW', NULL, 'PREV');
  PERFORM fn_cbd_header_set(t_cbd, cv, 'RATE', 16300);
  PERFORM fn_cbd_line_set(t_cbd, l.id, 'YIELD', 1) FROM cbd_line l WHERE l.cbd_revision_id = cv;
  PERFORM fn_cbd_publish(t_cbd, cv, 'OTHER', NULL);
  PERFORM pg_temp.ok((SELECT stage || ':' || stage_order || ':' || coalesce(po_factor::text, '-') FROM cbd_revision WHERE id = cv) = 'PREV:2:-'
                     AND (SELECT pub_label FROM v_cbd_article WHERE id = x1) = 'Preview r0'
                     AND (SELECT cbd_pub_label FROM v_article_status WHERE id = x1) = 'Preview r0',
                     'R14 CBD Preview r0 terbit (tanpa PO), label di chip & Model Detail');

  -- lompat Preview -> GTM; mundur / stage sama / kode salah ditolak
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_create(%L, %L, ''NEXT_STAGE'', ''PREV'', NULL)', t_spec, sh),
            '%higher than the latest published stage (Preview)%', 'R14 stage berikutnya tidak boleh stage yang sama');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_create(%L, %L, ''NEXT_STAGE'', ''PULL'', NULL)', t_spec, sh),
            '%higher than%', 'R14 stage berikutnya tidak boleh mundur');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_create(%L, %L, ''NEXT_STAGE'', ''XYZ'', NULL)', t_spec, sh),
            '%Unknown stage XYZ%', 'R14 kode stage tidak dikenal ditolak');
  rg0 := fn_revision_create(t_spec, sh, 'NEXT_STAGE', 'GTM', NULL);
  PERFORM pg_temp.ok((SELECT stage || ':' || stage_order || ':' || revision_no || ':' || (source_revision_id = rv0)
                        FROM specsheet_revision WHERE id = rg0) = 'GTM:4:0:true'
                     AND (SELECT count(*) FROM bom_line WHERE revision_id = rg0) = 1,
                     'R14 stage berikutnya boleh melompat (Preview -> GTM r0, baris BOM ikut)');
  PERFORM fn_revision_publish(t_spec, rg0, 'OTHER', 'uji');
  PERFORM pg_temp.ok((SELECT pub_behind FROM v_cbd_article WHERE id = x1)
                     AND (SELECT kind || '|' || refresh_reason || '|' || rev_label FROM v_worklist_cbd WHERE article_id = x1)
                         = 'TO_REVISE|STAGE|Preview r0',
                     'R14 CBD Preview tertinggal -> perlu CBD GTM (label Preview r0)');
  PERFORM pg_temp.ok((SELECT string_agg(stage || ':' || available, ',' ORDER BY stage_order) FROM fn_cbd_stage_options(t_cbd, x1))
                       = 'PULL:false,PREV:true,GTM:true'
                     AND (SELECT note FROM fn_cbd_stage_options(t_cbd, x1) WHERE stage = 'PULL') = 'A Preview CBD is already published',
                     'R14 pilihan CBD setelah lompat: Pullover tertutup (label Preview), tanpa SMS');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_create(%L, %L, ''NEXT_STAGE'', ''SMS'', NULL)', t_spec, sh),
            '%higher than the latest published stage (GTM)%', 'R14 tidak bisa kembali ke SMS setelah GTM terbit');
END;
$$;

-- ---------------------------------------------------------------- R16: thickness baku + material baru tanpa kode (sel kuning)
DO $$
DECLARE
  t_spec  text := pg_temp.tok('spec.a@selftest.invalid');
  v_cat   uuid; v_sup uuid; v_comp uuid;
  v_mat   uuid; v_var uuid; v_v2 uuid;
  m uuid; sh uuid; a1 uuid; a2 uuid; rv uuid; l1 uuid; l2 uuid;
BEGIN
  -- ===== bentuk baku (sama dengan canonThickness di cwBomGrid) =====
  PERFORM pg_temp.ok(fn_clean_thickness('1,2 mm') = '1.2 MM' AND fn_clean_thickness('  1.2   MM ') = '1.2 MM'
                     AND fn_clean_thickness('1.2mm') = '1.2 MM', 'R16 spasi / koma / huruf kecil: 1,2mm = 1.2 MM');
  PERFORM pg_temp.ok(fn_clean_thickness('0.55mmx44"') = '0.55 MM X 44"' AND fn_clean_thickness('1.2MM X 44 "') = '1.2 MM X 44"'
                     AND fn_clean_thickness('1.4 - 1.6MM') = '1.4-1.6 MM' AND fn_clean_thickness('4MM(110X200 CM )') = '4 MM (110 X 200 CM)'
                     AND fn_clean_thickness('43''''') = '43"' AND fn_clean_thickness('A1A(275X170X100 MM)') = 'A1A (275 X 170 X 100 MM)',
                     'R16 ukuran "X", tanda "-", kurung, tanda kutip (gaya berspasi tim material)');
  PERFORM pg_temp.ok(fn_clean_thickness('MAX 5') = 'MAX 5' AND fn_clean_thickness('SIZE 37 - 39') = 'SIZE 37-39'
                     AND fn_clean_thickness('.') IS NULL AND fn_clean_thickness('-') IS NULL AND fn_clean_thickness('  ') IS NULL
                     AND fn_clean_thickness(NULL) IS NULL, 'R16 kata biasa tidak berubah, "." / "-" / kosong = tanpa thickness');
  PERFORM pg_temp.ok(fn_clean_thickness('2.0 mm') = '2 MM' AND fn_clean_thickness('2.00MM') = '2 MM' AND fn_clean_thickness('1,50mm') = '1.5 MM'
                     AND fn_clean_thickness('.5mm') = '0.5 MM' AND fn_clean_thickness('1.050 MM') = '1.05 MM' AND fn_clean_thickness('10 MM') = '10 MM'
                     AND fn_clean_thickness('1.0MMX44"') = '1 MM X 44"' AND fn_clean_thickness('100 MM') = '100 MM',
                     'R16 angka setara satu bentuk: 2.0 = 2, 1.50 = 1.5, .5 = 0.5 (nol di depan / tengah tetap)');
  PERFORM pg_temp.ok(fn_clean_thickness('44' || chr(8221)) = '44"' AND fn_clean_thickness('44 ' || chr(8243)) = '44"'
                     AND fn_clean_thickness('44' || chr(8217) || chr(8217)) = '44"'
                     AND fn_clean_thickness('44 inch') = '44"' AND fn_clean_thickness('44IN') = '44"' AND fn_clean_thickness('1.4mmx44 inches') = '1.4 MM X 44"'
                     AND fn_clean_thickness('2 IN 1') = '2 IN 1' AND fn_clean_thickness('10 INCL') = '10 INCL',
                     'R16 kutip pintar dan INCH / IN setelah angka = tanda kutip (kata lain tidak berubah)');
  PERFORM pg_temp.ok(fn_clean_thickness('1.4mm-1.6mm') = '1.4-1.6 MM' AND fn_clean_thickness('1,4 MM - 1,6 MM x 54"') = '1.4-1.6 MM X 54"'
                     AND fn_clean_thickness('1.4MM-1.6CM') = '1.4 MM-1.6 CM' AND fn_clean_thickness('SIZE 35-39 (3-4)') = 'SIZE 35-39 (3-4)',
                     'R16 rentang dengan satuan di kedua sisi = satu satuan di belakang');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM unnest(ARRAY['1,2 mm', '44 "', '0.55 MMX44"', 'LEBAR=140 CM', 'A ( 1 MM )', '10 CM X 6 CM',
                                                              '2.0MM(95X152 CM)', 'SIZE 37 - 39', '.50 mm', '44 inch', '1.4mm - 1.6mm', '44' || chr(8221)]) x
                      WHERE fn_clean_thickness(fn_clean_thickness(x)) IS DISTINCT FROM fn_clean_thickness(x)),
                     'R16 pembakuan idempoten (dibakukan dua kali = sama)');

  -- ===== induk baru tanpa kode + thickness diketik apa adanya =====
  SELECT pm.category_id INTO v_cat FROM product_model pm JOIN factory f ON f.id = pm.factory_id
   WHERE f.name = 'SELFTEST PABRIK A' LIMIT 1;
  SELECT id INTO v_sup FROM supplier WHERE name = 'SELFTEST SUPPLIER SATU';
  SELECT id INTO v_comp FROM component WHERE name = 'SELFTEST VAMP';
  v_mat := fn_material_add(t_spec, 'uji baru tanpa kode', 'textile', 'yd');            -- ketik huruf kecil
  PERFORM pg_temp.ok((SELECT name || '|' || category FROM material WHERE id = v_mat) = 'UJI BARU TANPA KODE|TEXTILE',
                     'R16 nama + kategori material baru otomatis huruf besar, tanpa kode');
  PERFORM pg_temp.must_fail(format('SELECT fn_material_add(%L, ''Uji  Baru  Tanpa Kode'', ''TEXTILE'', ''YD'')', t_spec),
            '%already exists%', 'R16 typo spasi ganda / huruf kecil = material yang sama (ditolak)');

  m  := fn_model_save(t_spec, NULL, 'Uji Baku', v_cat, NULL, NULL, NULL, NULL, '[40]', NULL);
  sh := fn_season_add(t_spec, m, 'FH27');
  a1 := fn_article_save(t_spec, NULL, sh, 'UJI-BAKU1', 'BLACK');
  a2 := fn_article_save(t_spec, NULL, sh, 'UJI-BAKU2', 'WHITE');
  rv := fn_revision_create(t_spec, sh, 'EMPTY', NULL, NULL);

  -- thickness diketik "2,0mm" -> disimpan "2 MM"; warna " Black " / "white" -> huruf besar
  l1 := fn_bom_add_line(t_spec, rv, v_comp, NULL, NULL, v_mat, '2,0mm', v_sup, NULL, NULL);
  PERFORM fn_bom_cell_set(t_spec, l1, a1, ' Black ');
  PERFORM fn_bom_cell_set(t_spec, l1, a2, 'white');
  PERFORM pg_temp.ok((SELECT thickness FROM bom_line WHERE id = l1) = '2 MM'
                     AND (SELECT string_agg(color, ',' ORDER BY color) FROM bom_cell WHERE bom_line_id = l1 AND color IS NOT NULL) = 'BLACK,WHITE',
                     'R16 thickness 2,0mm -> 2 MM, warna huruf besar');
  PERFORM pg_temp.ok((SELECT yellow_cells FROM v_revision_checklist WHERE revision_id = rv) = 2,
                     'R16 material baru tanpa varian: 2 sel kuning');
  PERFORM pg_temp.must_fail(format('SELECT fn_bom_add_line(%L, %L, %L, NULL, NULL, %L, ''2.0mm'', %L, NULL, NULL)', t_spec, rv, v_comp, v_mat, v_sup),
            '%already in this revision%', 'R16 komponen + material + thickness sama, beda cara tulis (2.0mm = 2 MM) = dobel, ditolak');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_publish(%L, %L, ''OTHER'', NULL)', t_spec, rv),
            '%no Material Code%', 'R16 tidak boleh terbit selama ada sel kuning');

  -- kode datang belakangan: daftarkan varian -> sel kuning tersambung otomatis (relink), thickness diketik beda cara tulis
  v_var := fn_variant_save(t_spec, NULL, v_mat, 'UBTK200BLK', 'black', '2.0 mm', 'ACTIVE');
  PERFORM pg_temp.ok((SELECT thickness || '|' || color FROM material_variant WHERE id = v_var) = '2 MM|BLACK'
                     AND (SELECT variant_id FROM bom_cell WHERE bom_line_id = l1 AND article_id = a1) = v_var
                     AND (SELECT yellow_cells FROM v_revision_checklist WHERE revision_id = rv) = 1,
                     'R16 varian didaftarkan dengan "2.0 mm": sel BLACK tersambung, sisa 1 kuning');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, NULL, %L, ''UBTK200BL2'', ''BLACK'', ''2,0MM'', ''ACTIVE'')', t_spec, v_mat),
            '%already exists%', 'R16 varian dobel beda cara tulis thickness (2,0MM = 2 MM) ditolak');
  v_v2 := fn_variant_save(t_spec, NULL, v_mat, 'UBTK200WHT', 'White', '2MM', 'ACTIVE');
  PERFORM pg_temp.ok((SELECT yellow_cells FROM v_revision_checklist WHERE revision_id = rv) = 0, 'R16 semua kuning hilang setelah kode lengkap');
  -- arti kode = yang paling banyak dipakai: pengecualian yang dikonfirmasi (200 = 9 MM) tidak membuat kode 200 normal (2 MM) diminta konfirmasi
  PERFORM fn_variant_save(t_spec, NULL, v_mat, 'UBTK200GRN', 'GREEN', '9 MM', 'ACTIVE', true);
  PERFORM fn_variant_save(t_spec, NULL, v_mat, 'UBTK200GRY', 'GREY', '2,0 mm', 'ACTIVE');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, NULL, %L, ''UBTK200PNK'', ''PINK'', ''9 MM'', ''ACTIVE'')', t_spec, v_mat),
            'Confirmation needed: thickness code 200 is recorded as "2 MM"%', 'R16 arti kode = paling banyak dipakai: pengecualian baru tetap diminta konfirmasi');

  -- thickness baru untuk induk yang sama: baris baru, kuning lagi sampai kodenya ada
  l2 := fn_bom_add_line(t_spec, rv, NULL, 91, 'Uji lokal baku', v_mat, '3mm', v_sup, NULL, 'Black');
  PERFORM pg_temp.ok((SELECT thickness FROM bom_line WHERE id = l2) = '3 MM'
                     AND (SELECT yellow_cells FROM v_revision_checklist WHERE revision_id = rv) = 2,
                     'R16 thickness baru (3mm) untuk induk yang sama: baris baru, 2 sel kuning');
  PERFORM pg_temp.must_fail(format('SELECT fn_revision_publish(%L, %L, ''OTHER'', NULL)', t_spec, rv),
            '%no Material Code%', 'R16 thickness baru tanpa kode tidak boleh terbit');
  PERFORM fn_variant_save(t_spec, NULL, v_mat, 'UBTK300BLK', 'BLACK', '3MM', 'ACTIVE');
  PERFORM fn_variant_save(t_spec, NULL, v_mat, 'UBTK300WHT', 'WHITE', '3 mm', 'ACTIVE');
  PERFORM pg_temp.ok((SELECT yellow_cells FROM v_revision_checklist WHERE revision_id = rv) = 0,
                     'R16 kode thickness baru lengkap, tidak ada kuning');
  PERFORM fn_revision_publish(t_spec, rv, 'OTHER', NULL);
  PERFORM pg_temp.ok((SELECT status FROM specsheet_revision WHERE id = rv) = 'PUBLISHED', 'R16 specsheet terbit setelah kode lengkap');
  PERFORM pg_temp.must_fail(format('SELECT fn_variant_save(%L, %L, %L, ''UBTK200BLK'', ''BLACK'', ''2.5MM'', ''ACTIVE'')', t_spec, v_var, v_mat),
            '%used in published documents%', 'R16 varian terpakai dokumen terbit tetap terkunci (thickness tidak bisa diubah)');
END;
$$;


-- ---------------------------------------------------------------- R16: Order master option = posisi (tanpa kembar, kosong = akhir)
DO $$
DECLARE
  t_spec  text := pg_temp.tok('spec.a@selftest.invalid');
  k text; v_fac uuid; x uuid; y uuid; z uuid; w uuid; q uuid; n integer;
  kinds text[] := ARRAY['KATEGORI', 'CONSTRUCTION', 'GENDER', 'LAST', 'OUTSOLE_MOLD'];
BEGIN
  FOREACH k IN ARRAY kinds LOOP
    v_fac := CASE WHEN fn_option_is_factory_kind(k) THEN fn_user_factory('spec.a@selftest.invalid') END;
    x := fn_option_save(t_spec, NULL, k, 'UJI ORD ' || k || ' X', NULL, 'ACTIVE');       -- kosong = paling akhir
    y := fn_option_save(t_spec, NULL, k, 'UJI ORD ' || k || ' Y', NULL, 'ACTIVE');
    PERFORM pg_temp.ok((SELECT sort_order FROM model_option WHERE id = y) = (SELECT count(*) FROM model_option WHERE kind = k AND factory_id IS NOT DISTINCT FROM v_fac)
                       AND (SELECT sort_order FROM model_option WHERE id = x) = (SELECT sort_order FROM model_option WHERE id = y) - 1,
                       'R16 ' || k || ': Order kosong = paling akhir, berurutan');
    z := fn_option_save(t_spec, NULL, k, 'UJI ORD ' || k || ' Z', 1, 'ACTIVE');          -- sisip di posisi 1
    PERFORM pg_temp.ok((SELECT sort_order FROM model_option WHERE id = z) = 1
                       AND (SELECT sort_order FROM model_option WHERE id = x) > 1,
                       'R16 ' || k || ': Order 1 dipakai = menyisip, yang lain bergeser ke bawah');
    n := (SELECT sort_order FROM model_option WHERE id = x);
    w := fn_option_save(t_spec, NULL, k, 'UJI ORD ' || k || ' W', n, 'ACTIVE');          -- angka yang sama dengan X
    PERFORM pg_temp.ok((SELECT sort_order FROM model_option WHERE id = w) = n
                       AND (SELECT sort_order FROM model_option WHERE id = x) = n + 1,
                       'R16 ' || k || ': Order kembar diketik = baris baru ambil posisi itu, X turun satu');
    q := fn_option_save(t_spec, NULL, k, 'UJI ORD ' || k || ' Q', 9999, 'ACTIVE');       -- terlalu besar = paling akhir
    PERFORM pg_temp.ok((SELECT sort_order FROM model_option WHERE id = q) = (SELECT count(*) FROM model_option WHERE kind = k AND factory_id IS NOT DISTINCT FROM v_fac),
                       'R16 ' || k || ': Order lebih besar dari jumlah baris = paling akhir');
    n := (SELECT sort_order FROM model_option WHERE id = x);
    PERFORM fn_option_save(t_spec, x, k, 'UJI ORD ' || k || ' X', NULL, 'ACTIVE');       -- edit, Order kosong = tidak berubah
    PERFORM pg_temp.ok((SELECT sort_order FROM model_option WHERE id = x) = n, 'R16 ' || k || ': edit dengan Order kosong tidak memindahkan');
    PERFORM fn_option_save(t_spec, x, k, 'UJI ORD ' || k || ' X', 1, 'ACTIVE');          -- pindah ke posisi 1
    PERFORM pg_temp.ok((SELECT sort_order FROM model_option WHERE id = x) = 1 AND (SELECT sort_order FROM model_option WHERE id = z) = 2,
                       'R16 ' || k || ': edit pindah ke posisi 1, yang lama turun');
    y := (SELECT id FROM model_option WHERE kind = k AND factory_id IS NOT DISTINCT FROM v_fac AND sort_order = 2);
    w := (SELECT id FROM model_option WHERE kind = k AND factory_id IS NOT DISTINCT FROM v_fac AND sort_order = 3);
    PERFORM fn_option_save(t_spec, x, k, 'UJI ORD ' || k || ' X', 3, 'ACTIVE');          -- pindah ke bawah: 1 -> 3
    PERFORM pg_temp.ok((SELECT sort_order FROM model_option WHERE id = x) = 3 AND (SELECT sort_order FROM model_option WHERE id = y) = 1
                       AND (SELECT sort_order FROM model_option WHERE id = w) = 2,
                       'R16 ' || k || ': edit pindah ke bawah (1 -> 3) tepat di posisi 3, yang di antaranya naik satu');
    PERFORM pg_temp.ok((SELECT min(sort_order) = 1 AND max(sort_order) = count(*) AND count(DISTINCT sort_order) = count(*)
                          FROM model_option WHERE kind = k AND factory_id IS NOT DISTINCT FROM v_fac),
                       'R16 ' || k || ': Order selalu 1..n tanpa kembar dan tanpa kosong');
  END LOOP;
  PERFORM fn_option_save(t_spec, NULL, 'UKURAN', '96', 5, 'ACTIVE');
  PERFORM pg_temp.ok((SELECT sort_order FROM model_option WHERE kind = 'UKURAN' AND value = '96') = 96,
                     'R16 UKURAN: Order tetap = angka ukuran (tidak ikut posisi)');
END;
$$;

SELECT 'SELFTEST LOLOS' AS hasil;
ROLLBACK;
