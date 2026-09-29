-- ============================================================================
-- F3b — Approval harga material oleh Master Admin (keputusan user 29 Sep 2026)
-- Jalankan SETELAH F3, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi.
--
-- Aturan:
-- - Harga dari Vendor CBD -> PROPOSED; dari Master Admin (manage_master) -> langsung APPROVED.
-- - Harga lama TETAP berlaku sampai usulan di-approve; saat approve baru ditutup
--   (valid_to = valid_from harga baru). Pengecekan tanggal diulang saat approve.
-- - Maks. satu usulan (PROPOSED) per supplier material + warna.
-- - Tolak: status REJECTED + alasan wajib (tetap tersimpan). Batalkan usulan: dihapus (tercatat di audit).
-- - Akhiri harga: langsung, tanpa approval (hanya harga APPROVED).
-- - Hanya harga APPROVED yang dipakai (fn_price_lookup untuk CBD, ringkasan v_material_list).
-- Harga yang sudah ada sebelum F3b dianggap APPROVED.
-- ============================================================================

-- ---------------------------------------------------------------- Kolom
ALTER TABLE material_price
  ADD COLUMN IF NOT EXISTS status        text NOT NULL DEFAULT 'APPROVED',
  ADD COLUMN IF NOT EXISTS decided_by    text,          -- Master Admin yang approve / tolak
  ADD COLUMN IF NOT EXISTS decided_at    timestamptz,
  ADD COLUMN IF NOT EXISTS reject_reason text;
ALTER TABLE material_price ALTER COLUMN status SET DEFAULT 'PROPOSED';

ALTER TABLE material_price DROP CONSTRAINT IF EXISTS ck_material_price_status;
ALTER TABLE material_price ADD CONSTRAINT ck_material_price_status
  CHECK (status IN ('PROPOSED', 'APPROVED', 'REJECTED'));
ALTER TABLE material_price DROP CONSTRAINT IF EXISTS ck_material_price_reject_reason;
ALTER TABLE material_price ADD CONSTRAINT ck_material_price_reject_reason
  CHECK (status <> 'REJECTED' OR btrim(coalesce(reject_reason, '')) <> '');

CREATE UNIQUE INDEX IF NOT EXISTS uq_price_one_proposed
  ON material_price (material_supplier_id, color_key) WHERE status = 'PROPOSED';

-- ---------------------------------------------------------------- Aktifkan harga (dipakai add & approve)
-- Menutup harga APPROVED yang masih berlaku untuk supplier + warna yang sama, lalu set APPROVED.
CREATE OR REPLACE FUNCTION fn_price_activate(p_price_id uuid, p_actor text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_row  material_price%ROWTYPE;
  v_open material_price%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM material_price WHERE id = p_price_id;
  SELECT * INTO v_open FROM material_price
   WHERE material_supplier_id = v_row.material_supplier_id AND color_key = v_row.color_key
     AND status = 'APPROVED' AND valid_to IS NULL AND id <> v_row.id
   ORDER BY valid_from DESC LIMIT 1;
  IF FOUND THEN
    IF v_row.valid_from < v_open.valid_from THEN
      RAISE EXCEPTION 'Sudah ada harga yang berlaku mulai % untuk %. Tanggal berlaku harga baru tidak boleh lebih awal dari itu.',
        to_char(v_open.valid_from, 'DD-MM-YYYY'),
        CASE WHEN v_row.color IS NULL THEN 'semua warna' ELSE 'warna ' || v_row.color END;
    END IF;
    UPDATE material_price SET valid_to = v_row.valid_from, updated_by = p_actor WHERE id = v_open.id;
  END IF;
  UPDATE material_price
     SET status = 'APPROVED', decided_by = p_actor, decided_at = now(), reject_reason = NULL, updated_by = p_actor
   WHERE id = p_price_id;
END;
$$;

-- ---------------------------------------------------------------- Tambah harga (menggantikan versi F3)
CREATE OR REPLACE FUNCTION fn_price_add(
  p_token text, p_link_id uuid, p_color text, p_price numeric, p_currency text,
  p_valid_from date, p_reference text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email   text := fn_auth(p_token, 'manage_price');
  v_link    record;
  v_open    material_price%ROWTYPE;
  v_pending material_price%ROWTYPE;
  v_color   text := nullif(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g')), '');
  v_from    date := coalesce(p_valid_from, fn_today());
  v_what    text;
  v_id      uuid;
BEGIN
  v_what := CASE WHEN v_color IS NULL THEN 'semua warna' ELSE 'warna ' || v_color END;
  SELECT ms.status, m.price_method INTO v_link
    FROM material_supplier ms JOIN material m ON m.id = ms.material_id
   WHERE ms.id = p_link_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pilih supplier untuk harga ini.';
  END IF;
  IF v_link.status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Supplier ini sudah nonaktif untuk material ini — tidak bisa diberi harga baru.';
  END IF;
  IF v_link.price_method = 'QUOTATION' THEN
    RAISE EXCEPTION 'Material ini memakai metode harga Quotation — harganya diisi per CBD, bukan di master.';
  END IF;
  IF p_price IS NULL OR p_price <= 0 THEN
    RAISE EXCEPTION 'Harga harus lebih besar dari 0.';
  END IF;
  IF coalesce(p_currency, '') NOT IN ('IDR', 'USD') THEN
    RAISE EXCEPTION 'Currency wajib dipilih (IDR atau USD).';
  END IF;

  SELECT * INTO v_pending FROM material_price
   WHERE material_supplier_id = p_link_id AND color_key = fn_normalize(v_color) AND status = 'PROPOSED';
  IF FOUND THEN
    RAISE EXCEPTION 'Masih ada usulan harga % % untuk % yang menunggu approval. Batalkan usulan itu atau minta Master Admin memprosesnya dulu.',
      v_pending.price, v_pending.currency, v_what;
  END IF;

  -- Cek awal tanggal (dicek lagi saat approve)
  SELECT * INTO v_open FROM material_price
   WHERE material_supplier_id = p_link_id AND color_key = fn_normalize(v_color)
     AND status = 'APPROVED' AND valid_to IS NULL
   ORDER BY valid_from DESC LIMIT 1;
  IF FOUND AND v_from < v_open.valid_from THEN
    RAISE EXCEPTION 'Sudah ada harga yang berlaku mulai % untuk %. Tanggal berlaku harga baru tidak boleh lebih awal dari itu.',
      to_char(v_open.valid_from, 'DD-MM-YYYY'), v_what;
  END IF;

  INSERT INTO material_price (material_supplier_id, color, price, currency, valid_from, reference, status, updated_by)
  VALUES (p_link_id, v_color, p_price, p_currency, v_from, nullif(btrim(coalesce(p_reference, '')), ''),
          'PROPOSED', v_email)
  RETURNING id INTO v_id;

  IF fn_has_perm(v_email, 'manage_master') THEN
    PERFORM fn_price_activate(v_id, v_email);      -- Master Admin: langsung APPROVED
  END IF;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------- Approve / tolak / batalkan
CREATE OR REPLACE FUNCTION fn_price_approve(p_token text, p_price_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_row   record;
BEGIN
  SELECT mp.status, ms.status AS link_status, m.price_method INTO v_row
    FROM material_price mp
    JOIN material_supplier ms ON ms.id = mp.material_supplier_id
    JOIN material m ON m.id = ms.material_id
   WHERE mp.id = p_price_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Harga tidak ditemukan.';
  END IF;
  IF v_row.status <> 'PROPOSED' THEN
    RAISE EXCEPTION 'Harga ini sudah diproses (%).', v_row.status;
  END IF;
  IF v_row.link_status = 'INACTIVE' THEN
    RAISE EXCEPTION 'Supplier ini sudah nonaktif untuk material ini — tolak usulan harganya.';
  END IF;
  IF v_row.price_method = 'QUOTATION' THEN
    RAISE EXCEPTION 'Material ini sekarang memakai metode Quotation — tolak usulan harganya.';
  END IF;
  PERFORM fn_price_activate(p_price_id, v_email);
  RETURN p_price_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_price_reject(p_token text, p_price_id uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'manage_master');
  v_status text;
BEGIN
  SELECT status INTO v_status FROM material_price WHERE id = p_price_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Harga tidak ditemukan.';
  END IF;
  IF v_status <> 'PROPOSED' THEN
    RAISE EXCEPTION 'Harga ini sudah diproses (%).', v_status;
  END IF;
  IF btrim(coalesce(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'Alasan penolakan wajib diisi.';
  END IF;
  UPDATE material_price
     SET status = 'REJECTED', reject_reason = btrim(p_reason), decided_by = v_email, decided_at = now(),
         updated_by = v_email
   WHERE id = p_price_id;
  RETURN p_price_id;
END;
$$;

-- Tim CBD membatalkan usulan yang belum diproses
CREATE OR REPLACE FUNCTION fn_price_cancel(p_token text, p_price_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'manage_price');
  v_status text;
BEGIN
  SELECT status INTO v_status FROM material_price WHERE id = p_price_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Harga tidak ditemukan.';
  END IF;
  IF v_status <> 'PROPOSED' THEN
    RAISE EXCEPTION 'Hanya usulan yang belum diproses yang bisa dibatalkan.';
  END IF;
  DELETE FROM material_price WHERE id = p_price_id;
  RETURN p_price_id;
END;
$$;

-- ---------------------------------------------------------------- Akhiri harga: hanya APPROVED
CREATE OR REPLACE FUNCTION fn_price_end(p_token text, p_price_id uuid, p_valid_to date) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, 'manage_price');
  v_row   material_price%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM material_price WHERE id = p_price_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Harga tidak ditemukan.';
  END IF;
  IF v_row.status <> 'APPROVED' THEN
    RAISE EXCEPTION 'Hanya harga yang sudah di-approve yang bisa diakhiri. Untuk usulan, pakai Batalkan.';
  END IF;
  IF v_row.valid_to IS NOT NULL THEN
    RAISE EXCEPTION 'Harga ini sudah tidak berlaku.';
  END IF;
  UPDATE material_price
     SET valid_to = greatest(coalesce(p_valid_to, fn_today()), valid_from), updated_by = v_email
   WHERE id = p_price_id;
  RETURN p_price_id;
END;
$$;

-- ---------------------------------------------------------------- Lookup CBD: hanya APPROVED
CREATE OR REPLACE FUNCTION fn_price_lookup(p_material_id uuid, p_supplier_id uuid, p_color text, p_on date DEFAULT NULL)
RETURNS TABLE (price_id uuid, price numeric, currency text, tier text)
LANGUAGE sql STABLE AS $$
  SELECT mp.id, mp.price, mp.currency, CASE WHEN mp.color_key = '' THEN 'ALL_COLORS' ELSE 'COLOR' END
    FROM material_price mp
    JOIN material_supplier ms ON ms.id = mp.material_supplier_id
    JOIN material m ON m.id = ms.material_id
   WHERE ms.material_id = p_material_id AND ms.supplier_id = p_supplier_id
     AND m.price_method = 'CATALOG'
     AND mp.status = 'APPROVED'
     AND mp.color_key IN (fn_normalize(p_color), '')
     AND mp.valid_from <= coalesce(p_on, fn_today())
     AND (mp.valid_to IS NULL OR mp.valid_to > coalesce(p_on, fn_today()))
   ORDER BY (mp.color_key = '') ASC, mp.valid_from DESC, mp.created_at DESC
   LIMIT 1
$$;

-- ---------------------------------------------------------------- Daftar material: + pending_prices
-- (kolom baru hanya boleh ditambah di akhir view)
CREATE OR REPLACE VIEW v_material_list AS
SELECT m.id, m.material_code, m.name, m.name_key, m.category, m.thickness, m.uom, m.price_method, m.status,
       m.updated_at, m.updated_by,
       coalesce(s.suppliers, 0) AS supplier_count,
       coalesce(s.proposed, 0)  AS proposed_links,
       coalesce(s.priced, 0)    AS priced_links,
       s.preferred_supplier,
       (m.price_method = 'CATALOG' AND coalesce(s.suppliers, 0) > coalesce(s.priced, 0)) AS missing_price,
       (SELECT count(*) FROM material_price mp JOIN material_supplier ms ON ms.id = mp.material_supplier_id
         WHERE ms.material_id = m.id AND mp.status = 'PROPOSED') AS pending_prices
  FROM material m
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE ms.status <> 'INACTIVE') AS suppliers,
           count(*) FILTER (WHERE ms.status = 'PROPOSED')  AS proposed,
           count(*) FILTER (WHERE ms.status <> 'INACTIVE' AND EXISTS (
             SELECT 1 FROM material_price mp
              WHERE mp.material_supplier_id = ms.id AND mp.status = 'APPROVED'
                AND mp.valid_from <= fn_today() AND (mp.valid_to IS NULL OR mp.valid_to > fn_today()))) AS priced,
           max(sp.name) FILTER (WHERE ms.is_preferred) AS preferred_supplier
      FROM material_supplier ms JOIN supplier sp ON sp.id = ms.supplier_id
     WHERE ms.material_id = m.id
  ) s ON true;
