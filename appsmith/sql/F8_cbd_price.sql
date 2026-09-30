-- ============================================================================
-- F8 — CBD: harga, rekap, refresh, terbit, sinkron specsheet
-- Jalankan SETELAH F7, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
-- Tidak ada tabel baru.
--
-- Aturan (= cbd_service.py / cbd_calc.py):
-- - Harga baris CBD (hanya baris ACTIVE di revisi DRAFT):
--     material QUOTATION -> harga quotation diisi di CBD (kosong = tidak dihargai terpisah), referensi opsional
--     material CATALOG   -> harga master (fn_price_lookup, hanya APPROVED) atau OVERRIDE khusus baris ini
--                           (alasan wajib); Hapus override -> kembali ke harga master
--   Currency IDR/USD wajib dipilih setiap input (tanpa nilai awal).
-- - Harga master "usang" = harga master berlaku sekarang beda dengan yang tersimpan (harga baru / diganti /
--   diakhiri / harga khusus warna / metode harga berubah). Override tidak pernah usang.
--   Refresh Harga dari Master menyamakan semua baris usang.
-- - Refresh dari Specsheet (draft yang specsheet acuannya sudah terbit revisi baru): baris dibangun ulang dari
--   specsheet terbit terakhir; Yield / Loss % / harga input dibawa dari isi draft ini (pencocokan sama dengan
--   F7); baris yang tidak ada lagi -> MISSING_IN_SPEC. Stage ikut specsheet (nomor revisi disesuaikan).
-- - Rekap (Rupiah): Material cost = jumlah cost/pair baris ACTIVE (baris belum lengkap = 0)
--   Actual FOB = material cost + amortisasi + adjustment · Selisih = Actual FOB - Target FOB (OVER / UNDER / SESUAI)
--   Margin % = (Selling price - Actual FOB) / Selling price x 100 · isi Margin % -> Selling price = FOB / (1 - m/100)
-- - Terbit ditolak bila: specsheet acuan bukan terbit terakhir · exchange rate kosong · ada harga master usang ·
--   ada baris berharga tanpa Yield. Baris tanpa harga hanya peringatan (cost 0).
--   Alasan wajib kecuali revisi awal (r0 tanpa sumber) -> "Revisi awal.".
-- - Terbit specsheet -> CBD terbit terakhir tiap article ACTIVE dibandingkan (baris, supplier, warna) dengan
--   specsheet acuannya: sama -> acuan dipindah ke revisi baru (IN_SYNC); beda -> NEEDS_REVISION.
--   (Python membandingkan dengan specsheet terbit sebelumnya; di sini dengan acuan CBD itu sendiri, jadi CBD yang
--   sudah NEEDS_REVISION tidak kembali IN_SYNC tanpa sebab — P5.)
-- ============================================================================

-- ---------------------------------------------------------------- fn_cbd_populate: sumber = array baris
-- F7 membaca baris sumber dari cbd_line (revisi lain). Refresh dari specsheet memakai baris revisi ITU SENDIRI
-- sebagai sumber (dihapus dulu, lalu dibangun ulang), jadi sumber sekarang dikirim sebagai array.
-- p_ref NULL = asal nilai (value_origin / value_source_ref) dibawa apa adanya (refresh).
DROP FUNCTION IF EXISTS fn_cbd_populate(uuid, uuid, uuid, uuid, boolean, text, text);

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
    v_yield := NULL; v_loss := 0; v_origin := 'INPUT'; v_ref := NULL; v_carry := false;
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
           AND fn_cbd_identity(x.component_id, x.local_component_no, x.sub_seq, x.sub_name, x.material_id)
             = fn_cbd_identity(e.component_id, e.local_component_no, e.sub_seq, e.sub_name, e.material_id)
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
        -- harga input CBD ikut bila material sama dan metode harganya masih cocok
        v_carry := s.price_source IN ('OVERRIDE', 'QUOTATION') AND s.material_id = e.material_id
                   AND (s.price_source = 'QUOTATION') =
                       EXISTS (SELECT 1 FROM material WHERE id = e.material_id AND price_method = 'QUOTATION');
      ELSIF e.replaces_line_key IS NOT NULL THEN
        -- baris hasil "Ganti material": bawa Yield/Loss % baris lama, harga dari master material baru
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
                            material_id, color, supplier_id, uom, group_code, yield_value, loss_pct,
                            price_original, currency, price_source, material_price_id, price_override_reason,
                            price_reference, status, value_origin, value_source_ref, sort_order, updated_by)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.color, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              s.price_original, s.currency, s.price_source, NULL, s.price_override_reason,
              s.price_reference, 'ACTIVE', v_origin, v_ref, v_sort, p_email);
    ELSE
      v_pid := NULL; v_price := NULL; v_cur := NULL;
      IF e.supplier_id IS NOT NULL THEN
        SELECT price_id, price, currency INTO v_pid, v_price, v_cur
          FROM fn_price_lookup(e.material_id, e.supplier_id, e.color);
      END IF;
      INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                            material_id, color, supplier_id, uom, group_code, yield_value, loss_pct,
                            price_original, currency, price_source, material_price_id,
                            status, value_origin, value_source_ref, sort_order, updated_by)
      VALUES (p_revision_id, e.line_key, e.component_id, e.local_component_no, e.sub_seq, e.sub_name,
              e.material_id, e.color, e.supplier_id, e.uom, e.group_code, v_yield, v_loss,
              v_price, v_cur, CASE WHEN v_pid IS NOT NULL THEN 'MASTER' END, v_pid,
              'ACTIVE', v_origin, v_ref, v_sort, p_email);
    END IF;
    v_sort := v_sort + 1;
  END LOOP;

  IF p_mark_missing AND v_has_src THEN
    INSERT INTO cbd_line (cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
                          material_id, color, supplier_id, uom, group_code, yield_value, loss_pct,
                          price_original, currency, price_source, material_price_id, price_override_reason,
                          price_reference, status, value_origin, value_source_ref, sort_order, updated_by)
    SELECT p_revision_id, x.line_key, x.component_id, x.local_component_no, x.sub_seq, x.sub_name,
           x.material_id, x.color, x.supplier_id, x.uom, x.group_code, x.yield_value, x.loss_pct,
           x.price_original, x.currency, x.price_source, x.material_price_id, x.price_override_reason,
           x.price_reference, 'MISSING_IN_SPEC', x.value_origin, x.value_source_ref,
           v_sort + (row_number() OVER (ORDER BY x.sort_order))::integer, p_email
      FROM unnest(p_src) x
     WHERE NOT (x.line_key = ANY (v_matched));
  END IF;
  RETURN v_sort;
END;
$$;

-- fn_cbd_create (F7) memanggil fn_cbd_populate versi baru. Isi lainnya sama dengan F7.
CREATE OR REPLACE FUNCTION fn_cbd_create(p_token text, p_article_id uuid, p_mode text, p_source_article_id uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'edit_cbd');
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

  -- Rekap (rate, amortisasi, adjustment, target FOB, selling price) ikut dari sumber
  INSERT INTO cbd_revision (article_id, stage, revision_no, specsheet_revision_id, exchange_rate, amortization,
                            adjustment, target_fob, selling_price, source_cbd_revision_id, updated_by)
  VALUES (v_art.id, v_spec.stage, v_no, v_spec.id, v_src.exchange_rate, coalesce(v_src.amortization, 0),
          coalesce(v_src.adjustment, 0), v_src.target_fob, v_src.selling_price, v_src.id, v_email)
  RETURNING id INTO v_id;

  IF v_src.id IS NOT NULL THEN
    SELECT sp.season || ' / ' || a.code || ' / ' || v_src.stage || ' r' || v_src.revision_no INTO v_ref
      FROM article a JOIN specsheet sp ON sp.id = a.specsheet_id WHERE a.id = v_src.article_id;
    SELECT array_agg(l ORDER BY l.sort_order) INTO v_lines FROM cbd_line l WHERE l.cbd_revision_id = v_src.id;
  END IF;
  PERFORM fn_cbd_populate(v_id, v_art.id, v_spec.id, v_lines, p_mode = 'NEXT', v_ref, v_email);
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------- Cek harga per baris
-- Hanya baris ACTIVE revisi DRAFT (revisi terbit terkunci, harganya tidak dicek ulang).
-- master_stale: harga master berlaku sekarang beda dengan yang tersimpan (lihat header).
-- price_gap (baris tanpa harga): QUOTATION · NO_SUPPLIER · AVAILABLE (harga master sudah ada -> refresh)
--   · PENDING (usulan harga menunggu approval, F3b) · NO_COLOR_PRICE (other_colors = warna yang ada harganya)
--   · NO_PRICE.
CREATE OR REPLACE VIEW v_cbd_price_check AS
SELECT l.id AS line_id, l.cbd_revision_id,
       cur.price_id AS master_price_id, cur.price AS master_price, cur.currency AS master_currency,
       CASE WHEN l.price_source = 'OVERRIDE' THEN false
            WHEN l.price_source = 'QUOTATION' THEN m.price_method = 'CATALOG'
            ELSE cur.price_id IS DISTINCT FROM l.material_price_id END AS master_stale,
       CASE WHEN l.price_original IS NOT NULL THEN NULL
            WHEN m.price_method = 'QUOTATION' THEN 'QUOTATION'
            WHEN l.supplier_id IS NULL THEN 'NO_SUPPLIER'
            WHEN cur.price_id IS NOT NULL THEN 'AVAILABLE'
            WHEN EXISTS (SELECT 1 FROM material_price mp JOIN material_supplier ms ON ms.id = mp.material_supplier_id
                          WHERE ms.material_id = l.material_id AND ms.supplier_id = l.supplier_id
                            AND mp.status = 'PROPOSED' AND mp.color_key IN (fn_normalize(l.color), '')) THEN 'PENDING'
            WHEN oc.colors IS NOT NULL THEN 'NO_COLOR_PRICE'
            ELSE 'NO_PRICE' END AS price_gap,
       oc.colors AS other_colors
  FROM cbd_line l
  JOIN cbd_revision r ON r.id = l.cbd_revision_id
  JOIN material m ON m.id = l.material_id
  LEFT JOIN LATERAL fn_price_lookup(l.material_id, l.supplier_id, l.color) cur ON true
  LEFT JOIN LATERAL (
    SELECT string_agg(DISTINCT mp.color, ', ') AS colors
      FROM material_price mp JOIN material_supplier ms ON ms.id = mp.material_supplier_id
     WHERE ms.material_id = l.material_id AND ms.supplier_id = l.supplier_id
       AND mp.status = 'APPROVED' AND mp.color_key <> ''
       AND mp.valid_from <= fn_today() AND (mp.valid_to IS NULL OR mp.valid_to > fn_today())
  ) oc ON l.price_original IS NULL AND l.supplier_id IS NOT NULL
 WHERE r.status = 'DRAFT' AND l.status = 'ACTIVE';

-- ---------------------------------------------------------------- Rekap
-- Satu baris per revisi CBD. Semua angka Rupiah. Baris belum lengkap (tanpa harga / yield / rate untuk USD) = 0.
CREATE OR REPLACE VIEW v_cbd_recap AS
SELECT r.id AS cbd_revision_id, r.status, r.exchange_rate, r.amortization, r.adjustment, r.target_fob,
       r.selling_price, t.material_cost, f.actual_fob,
       f.actual_fob - r.target_fob AS variance,
       CASE WHEN r.target_fob IS NULL THEN NULL
            WHEN f.actual_fob > r.target_fob THEN 'OVER'
            WHEN f.actual_fob < r.target_fob THEN 'UNDER'
            ELSE 'SESUAI' END AS variance_label,
       CASE WHEN r.selling_price <> 0 THEN (r.selling_price - f.actual_fob) / r.selling_price * 100 END AS margin_pct,
       t.line_count, t.unpriced_count, t.no_yield_count, t.usd_no_rate_count, t.missing_count
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
  CROSS JOIN LATERAL (SELECT t.material_cost + r.amortization + r.adjustment AS actual_fob) f;

-- ---------------------------------------------------------------- Checklist terbit
CREATE OR REPLACE VIEW v_cbd_checklist AS
SELECT x.*,
       (x.spec_status <> 'ACTIVE' OR x.spec_stale OR NOT x.rate_ok OR x.stale_prices > 0 OR x.no_yield_count > 0) AS blocked
  FROM (
    SELECT r.id AS cbd_revision_id, r.article_id, r.stage, r.revision_no, r.status,
           (r.source_cbd_revision_id IS NOT NULL OR r.revision_no <> 0) AS requires_reason,
           fn_cbd_article_spec_status(r.article_id) AS spec_status,
           (r.specsheet_revision_id IS DISTINCT FROM fn_spec_latest_pub(a.specsheet_id)) AS spec_stale,
           (r.exchange_rate IS NOT NULL) AS rate_ok,
           (SELECT count(*)::int FROM v_cbd_price_check pc
             WHERE pc.cbd_revision_id = r.id AND pc.master_stale) AS stale_prices,
           rc.no_yield_count, rc.unpriced_count, rc.line_count, rc.missing_count
      FROM cbd_revision r
      JOIN article a ON a.id = r.article_id
      JOIN v_cbd_recap rc ON rc.cbd_revision_id = r.id
  ) x;

-- ---------------------------------------------------------------- Harga baris
-- Baris ACTIVE di revisi DRAFT (dikunci), atau error.
CREATE OR REPLACE FUNCTION fn_cbd_price_line(p_line_id uuid) RETURNS cbd_line
LANGUAGE plpgsql AS $$
DECLARE
  v_line cbd_line%ROWTYPE;
BEGIN
  SELECT * INTO v_line FROM cbd_line WHERE id = p_line_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Baris CBD tidak ditemukan. Muat ulang halaman.';
  END IF;
  PERFORM fn_cbd_draft(v_line.cbd_revision_id);
  IF v_line.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Baris yang sudah hilang dari specsheet (MISSING_IN_SPEC) tidak bisa diubah harganya.';
  END IF;
  RETURN v_line;
END;
$$;

CREATE OR REPLACE FUNCTION fn_cbd_check_price(p_price numeric, p_currency text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_price IS NULL OR p_price <= 0 THEN
    RAISE EXCEPTION 'Harga harus diisi dan lebih besar dari 0.';
  END IF;
  IF coalesce(p_currency, '') NOT IN ('IDR', 'USD') THEN
    RAISE EXCEPTION 'Pilih currency (IDR / USD).';
  END IF;
END;
$$;

-- Harga quotation (material QUOTATION). p_price NULL = kosongkan (tidak dihargai terpisah).
CREATE OR REPLACE FUNCTION fn_cbd_set_quotation(p_token text, p_line_id uuid, p_price numeric,
                                                p_currency text, p_reference text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_cbd');
  v_line  cbd_line%ROWTYPE := fn_cbd_price_line(p_line_id);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM material WHERE id = v_line.material_id AND price_method = 'QUOTATION') THEN
    RAISE EXCEPTION 'Harga quotation hanya untuk material dengan metode harga Quotation. Material katalog memakai harga master (atau override).';
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

-- Override harga (material CATALOG), alasan wajib. Harga untuk semua CBD (termasuk harga khusus warna)
-- bukan override — diisi di Master Material.
CREATE OR REPLACE FUNCTION fn_cbd_override_price(p_token text, p_line_id uuid, p_price numeric,
                                                 p_currency text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'edit_cbd');
  v_line   cbd_line%ROWTYPE := fn_cbd_price_line(p_line_id);
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
BEGIN
  IF EXISTS (SELECT 1 FROM material WHERE id = v_line.material_id AND price_method = 'QUOTATION') THEN
    RAISE EXCEPTION 'Material ini memakai metode harga Quotation — isi harga quotation, bukan override.';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Alasan override harga wajib diisi.';
  END IF;
  PERFORM fn_cbd_check_price(p_price, p_currency);
  UPDATE cbd_line SET price_original = p_price, currency = p_currency, price_source = 'OVERRIDE',
                      material_price_id = NULL, price_override_reason = v_reason, price_reference = NULL,
                      updated_by = v_email
   WHERE id = v_line.id;
  RETURN v_line.id;
END;
$$;

-- Hapus override: kembali ke harga master yang berlaku sekarang (boleh kosong).
CREATE OR REPLACE FUNCTION fn_cbd_clear_override(p_token text, p_line_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_cbd');
  v_line  cbd_line%ROWTYPE := fn_cbd_price_line(p_line_id);
  v_pid   uuid;
  v_price numeric;
  v_cur   text;
BEGIN
  IF v_line.price_source IS DISTINCT FROM 'OVERRIDE' THEN
    RAISE EXCEPTION 'Baris ini tidak memakai override harga.';
  END IF;
  IF v_line.supplier_id IS NOT NULL THEN
    SELECT price_id, price, currency INTO v_pid, v_price, v_cur
      FROM fn_price_lookup(v_line.material_id, v_line.supplier_id, v_line.color);
  END IF;
  UPDATE cbd_line SET price_original = v_price, currency = v_cur,
                      price_source = CASE WHEN v_pid IS NOT NULL THEN 'MASTER' END, material_price_id = v_pid,
                      price_override_reason = NULL, price_reference = NULL, updated_by = v_email
   WHERE id = v_line.id;
  RETURN v_line.id;
END;
$$;

-- Samakan semua baris dengan harga master usang. Mengembalikan jumlah baris yang berubah.
CREATE OR REPLACE FUNCTION fn_cbd_refresh_prices(p_token text, p_cbd_revision_id uuid) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_cbd');
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

-- ---------------------------------------------------------------- Refresh dari specsheet
-- Draft yang specsheet acuannya bukan terbit terakhir -> bangun ulang dari specsheet terbit terakhir.
-- Mengembalikan jumlah baris ACTIVE.
CREATE OR REPLACE FUNCTION fn_cbd_refresh_from_spec(p_token text, p_cbd_revision_id uuid) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'edit_cbd');
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

-- ---------------------------------------------------------------- Rekap: ubah nilai
-- p_field: RATE (wajib > 0) · AMORTIZATION (kosong = 0, >= 0) · ADJUSTMENT (kosong = 0, boleh minus)
-- · TARGET_FOB (kosong boleh, > 0) · SELLING_PRICE (kosong boleh, > 0)
-- · MARGIN (kosong = selling price dikosongkan; < 100; selling price = Actual FOB / (1 - m/100), 2 desimal).
CREATE OR REPLACE FUNCTION fn_cbd_header_set(p_token text, p_cbd_revision_id uuid, p_field text, p_value numeric)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_cbd');
  v_rev   cbd_revision%ROWTYPE := fn_cbd_draft(p_cbd_revision_id);
  v_fob   numeric;
BEGIN
  IF p_field = 'RATE' THEN
    IF p_value IS NULL OR p_value <= 0 THEN
      RAISE EXCEPTION 'Exchange rate harus diisi dan lebih besar dari 0.';
    END IF;
    UPDATE cbd_revision SET exchange_rate = p_value, updated_by = v_email WHERE id = v_rev.id;
  ELSIF p_field = 'AMORTIZATION' THEN
    IF coalesce(p_value, 0) < 0 THEN
      RAISE EXCEPTION 'Amortisasi tidak boleh minus.';
    END IF;
    UPDATE cbd_revision SET amortization = coalesce(p_value, 0), updated_by = v_email WHERE id = v_rev.id;
  ELSIF p_field = 'ADJUSTMENT' THEN
    UPDATE cbd_revision SET adjustment = coalesce(p_value, 0), updated_by = v_email WHERE id = v_rev.id;
  ELSIF p_field IN ('TARGET_FOB', 'SELLING_PRICE') THEN
    IF p_value IS NOT NULL AND p_value <= 0 THEN
      RAISE EXCEPTION '% harus lebih besar dari 0 (kosongkan kalau belum ada).',
        CASE p_field WHEN 'TARGET_FOB' THEN 'Target FOB' ELSE 'Selling price' END;
    END IF;
    IF p_field = 'TARGET_FOB' THEN
      UPDATE cbd_revision SET target_fob = p_value, updated_by = v_email WHERE id = v_rev.id;
    ELSE
      UPDATE cbd_revision SET selling_price = p_value, updated_by = v_email WHERE id = v_rev.id;
    END IF;
  ELSIF p_field = 'MARGIN' THEN
    IF p_value IS NULL THEN
      UPDATE cbd_revision SET selling_price = NULL, updated_by = v_email WHERE id = v_rev.id;
    ELSE
      IF p_value >= 100 THEN
        RAISE EXCEPTION 'Margin harus kurang dari 100%%.';
      END IF;
      SELECT actual_fob INTO v_fob FROM v_cbd_recap WHERE cbd_revision_id = v_rev.id;
      IF coalesce(v_fob, 0) <= 0 THEN
        RAISE EXCEPTION 'Actual FOB masih 0 — isi harga & Yield dulu, atau isi Selling price langsung.';
      END IF;
      UPDATE cbd_revision SET selling_price = round(v_fob / (1 - p_value / 100), 2), updated_by = v_email
       WHERE id = v_rev.id;
    END IF;
  ELSE
    RAISE EXCEPTION 'Kolom tidak valid.';
  END IF;
  RETURN v_rev.id;
END;
$$;

-- ---------------------------------------------------------------- Terbitkan CBD
-- Mengembalikan id change_log. Checklist dihitung ulang setelah revisi dikunci (fn_cbd_draft FOR UPDATE).
CREATE OR REPLACE FUNCTION fn_cbd_publish(p_token text, p_cbd_revision_id uuid, p_category text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'edit_cbd');
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
         updated_by = v_email
   WHERE id = v_rev.id;

  INSERT INTO change_log (doc_type, revision_id, category, reason, created_by)
  VALUES ('CBD', v_rev.id, p_category, coalesce(v_reason, 'Revisi awal.'), v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------- Sinkron saat specsheet terbit
-- Dipanggil fn_revision_publish. Mengembalikan jumlah CBD yang baru ditandai NEEDS_REVISION.
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
    -- tanda tangan baris: lineKey + supplier + warna (supplier & warna menentukan harga master)
    SELECT NOT EXISTS (
             (SELECT line_key, supplier_id, fn_normalize(color) FROM fn_cbd_expected_lines(c.article_id, c.specsheet_revision_id)
              EXCEPT
              SELECT line_key, supplier_id, fn_normalize(color) FROM fn_cbd_expected_lines(c.article_id, p_spec_rev_id))
             UNION ALL
             (SELECT line_key, supplier_id, fn_normalize(color) FROM fn_cbd_expected_lines(c.article_id, p_spec_rev_id)
              EXCEPT
              SELECT line_key, supplier_id, fn_normalize(color) FROM fn_cbd_expected_lines(c.article_id, c.specsheet_revision_id)))
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

-- fn_revision_publish (F6) + penandaan sinkron CBD. Isi lainnya sama dengan F6.
CREATE OR REPLACE FUNCTION fn_revision_publish(p_token text, p_revision_id uuid, p_category text, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'edit_specsheet');
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
