-- ============================================================================
-- F8b — CBD: Cost recapitulation (baris biaya) + subtotal grup (keputusan user 5 Okt 2026, contoh Excel
--       "FH26_CBD PRODUCTION_ACC ILLUZION IV ELITE FG PRM 097.xlsx")
-- Jalankan SETELAH F8, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
-- ⚠️ Setelah F8b, file F8 TIDAK boleh dijalankan ulang (F8 masih memakai kolom amortization/adjustment).
--
-- Aturan:
-- - Biaya di luar material = baris cbd_cost_item per revisi CBD. Jenis tetap: LABOUR (Direct Labour / LOP),
--   AMORTIZATION, ADJUSTMENT, OTHER. Nilai Rupiah; hanya ADJUSTMENT yang boleh minus.
-- - Setiap revisi selalu punya 3 baris default (LABOUR, AMORTIZATION, ADJUSTMENT) — tidak bisa dihapus, nama &
--   nilai boleh diubah. Baris tambahan bisa ditambah & dihapus (draft saja).
-- - Actual FOB = material cost + jumlah semua baris biaya. (Menggantikan kolom amortization & adjustment di
--   cbd_revision — nilainya dipindah ke baris default, lalu kolomnya di-DROP.)
-- - Revisi berikutnya / copy dari article lain: baris biaya ikut ter-copy. Revisi terbit: terkunci (trigger).
-- - Subtotal cost/pair per grup (a/b/c/d) di v_cbd_recap.group_costs.
-- ============================================================================

-- ---------------------------------------------------------------- Cek bentrok nama
DO $$
BEGIN
  IF to_regclass('public.cbd_cost_item') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'cbd_cost_item' AND column_name = 'item_type') THEN
    RAISE EXCEPTION 'Tabel "cbd_cost_item" sudah ada di database dan bukan milik proyek ini. Hentikan dan hubungi pengembang.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Tabel
CREATE TABLE IF NOT EXISTS cbd_cost_item (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cbd_revision_id uuid NOT NULL REFERENCES cbd_revision(id) ON DELETE CASCADE,
  item_type       text NOT NULL CHECK (item_type IN ('LABOUR','AMORTIZATION','ADJUSTMENT','OTHER')),
  name            text NOT NULL CHECK (btrim(name) <> ''),
  amount          numeric(18,4) NOT NULL DEFAULT 0,
  remarks         text,
  is_default      boolean NOT NULL DEFAULT false,
  sort_order      integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CHECK (item_type = 'ADJUSTMENT' OR amount >= 0),
  CHECK (NOT is_default OR item_type <> 'OTHER')
);
CREATE INDEX IF NOT EXISTS idx_cbd_cost_item_revision ON cbd_cost_item (cbd_revision_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_cbd_cost_default ON cbd_cost_item (cbd_revision_id, item_type) WHERE is_default;

SELECT fn_setup_table('cbd_cost_item');

-- ---------------------------------------------------------------- Pindahkan amortisasi/adjustment ke baris
-- View lama memakai kolom yang akan di-DROP -> dibuat ulang di bawah. Trigger kunci dipasang SETELAH pemindahan
-- (revisi terbit juga perlu diberi baris default).
DROP TRIGGER IF EXISTS trg_lock_published ON cbd_cost_item;
DROP VIEW IF EXISTS v_cbd_checklist;
DROP VIEW IF EXISTS v_cbd_recap;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'cbd_revision' AND column_name = 'amortization') THEN
    INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, is_default, sort_order, updated_by)
    SELECT r.id, t.typ, t.nm,
           CASE t.typ WHEN 'AMORTIZATION' THEN r.amortization WHEN 'ADJUSTMENT' THEN r.adjustment ELSE 0 END,
           true, t.ord, 'migrasi F8b'
      FROM cbd_revision r
     CROSS JOIN (VALUES ('LABOUR', 'Direct Labour', 1), ('AMORTIZATION', 'Amortisasi', 2),
                        ('ADJUSTMENT', 'Adjustment', 3)) AS t(typ, nm, ord)
     WHERE NOT EXISTS (SELECT 1 FROM cbd_cost_item c WHERE c.cbd_revision_id = r.id AND c.item_type = t.typ AND c.is_default);
    ALTER TABLE cbd_revision DROP COLUMN amortization, DROP COLUMN adjustment;
  END IF;
END;
$$;

-- Baris biaya revisi terbit tidak bisa diubah (fungsi kunci baris CBD F7 dipakai ulang).
CREATE TRIGGER trg_lock_published BEFORE INSERT OR UPDATE OR DELETE ON cbd_cost_item
  FOR EACH ROW EXECUTE FUNCTION fn_cbd_line_lock();

-- ---------------------------------------------------------------- Rekap & checklist (dibuat ulang)
-- Semua angka Rupiah. Baris belum lengkap (tanpa harga / yield / rate untuk USD) = 0.
-- group_costs = { "a": subtotal cost/pair, ... } baris ACTIVE.
CREATE VIEW v_cbd_recap AS
SELECT r.id AS cbd_revision_id, r.status, r.exchange_rate, r.target_fob, r.selling_price,
       t.material_cost, ci.labour, ci.amortization, ci.adjustment, ci.other, ci.items_total,
       f.actual_fob,
       f.actual_fob - r.target_fob AS variance,
       CASE WHEN r.target_fob IS NULL THEN NULL
            WHEN f.actual_fob > r.target_fob THEN 'OVER'
            WHEN f.actual_fob < r.target_fob THEN 'UNDER'
            ELSE 'SESUAI' END AS variance_label,
       CASE WHEN r.selling_price <> 0 THEN (r.selling_price - f.actual_fob) / r.selling_price * 100 END AS margin_pct,
       t.line_count, t.unpriced_count, t.no_yield_count, t.usd_no_rate_count, t.missing_count,
       coalesce(gc.group_costs, '{}'::jsonb) AS group_costs
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
  CROSS JOIN LATERAL (SELECT t.material_cost + ci.items_total AS actual_fob) f;

CREATE VIEW v_cbd_checklist AS
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

-- ---------------------------------------------------------------- Baris biaya: helper
CREATE OR REPLACE FUNCTION fn_cbd_cost_label(p_type text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_type WHEN 'LABOUR' THEN 'Direct Labour' WHEN 'AMORTIZATION' THEN 'Amortisasi'
                     WHEN 'ADJUSTMENT' THEN 'Adjustment' ELSE 'Lainnya' END
$$;

-- Lengkapi 3 baris default revisi ini (nilai 0) bila belum ada.
CREATE OR REPLACE FUNCTION fn_cbd_cost_defaults(p_cbd_revision_id uuid, p_email text) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, is_default, sort_order, updated_by)
  SELECT p_cbd_revision_id, t.typ, fn_cbd_cost_label(t.typ), 0, true, t.ord, p_email
    FROM (VALUES ('LABOUR', 1), ('AMORTIZATION', 2), ('ADJUSTMENT', 3)) AS t(typ, ord)
   WHERE NOT EXISTS (SELECT 1 FROM cbd_cost_item c
                      WHERE c.cbd_revision_id = p_cbd_revision_id AND c.item_type = t.typ AND c.is_default)
$$;

CREATE OR REPLACE FUNCTION fn_cbd_check_cost(p_type text, p_amount numeric) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF p_type <> 'ADJUSTMENT' AND coalesce(p_amount, 0) < 0 THEN
    RAISE EXCEPTION 'Nilai % tidak boleh minus (hanya Adjustment yang boleh minus).', fn_cbd_cost_label(p_type);
  END IF;
END;
$$;

-- Baris biaya di revisi DRAFT (revisi dikunci), atau error.
CREATE OR REPLACE FUNCTION fn_cbd_cost_item(p_item_id uuid) RETURNS cbd_cost_item
LANGUAGE plpgsql AS $$
DECLARE
  v_item cbd_cost_item%ROWTYPE;
BEGIN
  SELECT * INTO v_item FROM cbd_cost_item WHERE id = p_item_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Baris biaya tidak ditemukan. Muat ulang halaman.';
  END IF;
  PERFORM fn_cbd_draft(v_item.cbd_revision_id);
  RETURN v_item;
END;
$$;

-- ---------------------------------------------------------------- Baris biaya: tambah / ubah / hapus
CREATE OR REPLACE FUNCTION fn_cbd_cost_add(p_token text, p_cbd_revision_id uuid, p_type text, p_name text,
                                           p_amount numeric, p_remarks text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_cbd');
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

-- p_field: NAME (wajib) · AMOUNT (kosong = 0) · REMARKS (kosong = dihapus)
CREATE OR REPLACE FUNCTION fn_cbd_cost_set(p_token text, p_item_id uuid, p_field text, p_value text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'edit_cbd');
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
  v_email text := fn_auth(p_token, 'edit_cbd');
  v_item  cbd_cost_item%ROWTYPE := fn_cbd_cost_item(p_item_id);
BEGIN
  IF v_item.is_default THEN
    RAISE EXCEPTION 'Baris % selalu ada dan tidak bisa dihapus (isi 0 bila tidak dipakai).', v_item.name;
  END IF;
  DELETE FROM cbd_cost_item WHERE id = v_item.id;
  RETURN v_item.id;
END;
$$;

-- ---------------------------------------------------------------- Rekap: ubah nilai (tanpa amortisasi/adjustment)
-- p_field: RATE (wajib > 0) · TARGET_FOB (kosong boleh, > 0) · SELLING_PRICE (kosong boleh, > 0)
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

-- ---------------------------------------------------------------- fn_cbd_create (F8) + baris biaya
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

  -- Rekap (rate, target FOB, selling price) ikut dari sumber
  INSERT INTO cbd_revision (article_id, stage, revision_no, specsheet_revision_id, exchange_rate,
                            target_fob, selling_price, source_cbd_revision_id, updated_by)
  VALUES (v_art.id, v_spec.stage, v_no, v_spec.id, v_src.exchange_rate,
          v_src.target_fob, v_src.selling_price, v_src.id, v_email)
  RETURNING id INTO v_id;

  IF v_src.id IS NOT NULL THEN
    SELECT sp.season || ' / ' || a.code || ' / ' || v_src.stage || ' r' || v_src.revision_no INTO v_ref
      FROM article a JOIN specsheet sp ON sp.id = a.specsheet_id WHERE a.id = v_src.article_id;
    SELECT array_agg(l ORDER BY l.sort_order) INTO v_lines FROM cbd_line l WHERE l.cbd_revision_id = v_src.id;
    -- baris biaya ikut ter-copy (F8b)
    INSERT INTO cbd_cost_item (cbd_revision_id, item_type, name, amount, remarks, is_default, sort_order, updated_by)
    SELECT v_id, c.item_type, c.name, c.amount, c.remarks, c.is_default, c.sort_order, v_email
      FROM cbd_cost_item c WHERE c.cbd_revision_id = v_src.id;
  END IF;
  PERFORM fn_cbd_cost_defaults(v_id, v_email);
  PERFORM fn_cbd_populate(v_id, v_art.id, v_spec.id, v_lines, p_mode = 'NEXT', v_ref, v_email);
  RETURN v_id;
END;
$$;
