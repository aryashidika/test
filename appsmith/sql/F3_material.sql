-- ============================================================================
-- F3 — Master Material, supplier material, harga
-- Jalankan SETELAH F2, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
--
-- Aturan (= material_service.py / material_price_service.py):
-- - Material unik per Material Code dan per (nama + thickness + UoM) setelah normalisasi.
-- - Tambah material: Master Admin -> APPROVED, vendor (propose_master) -> PROPOSED.
-- - Supplier material: didaftarkan tim specsheet (manage_material_supplier) -> PROPOSED,
--   Master Admin -> APPROVED; status diubah hanya oleh Master Admin. Maks. satu supplier utama.
-- - Harga (manage_price): tidak pernah ditimpa. Harga baru untuk supplier + warna yang sama
--   menutup harga yang masih berlaku (valid_to = valid_from harga baru). valid_from inklusif,
--   valid_to eksklusif. color NULL = semua warna; harga warna menang atas harga semua warna.
--   Currency WAJIB dipilih setiap input (keputusan user 27 Sep 2026).
-- - Material QUOTATION tidak punya harga master (harganya diisi per CBD).
-- ============================================================================

-- ---------------------------------------------------------------- Cek bentrok nama
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('material', 'name_key'), ('material_supplier', 'is_preferred'),
                                 ('material_price', 'color_key')) AS t(tbl, col)
  LOOP
    IF to_regclass('public.' || r.tbl) IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = r.tbl AND column_name = r.col) THEN
      RAISE EXCEPTION 'Tabel "%" sudah ada di database dan bukan milik proyek ini. Hentikan dan hubungi pengembang.', r.tbl;
    END IF;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------- Tabel
CREATE TABLE IF NOT EXISTS material (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  material_code text NOT NULL,
  name          text NOT NULL CHECK (btrim(name) <> ''),
  name_key      text GENERATED ALWAYS AS (fn_normalize(name)) STORED,
  category      text NOT NULL,
  thickness     text,
  thickness_key text GENERATED ALWAYS AS (fn_normalize(thickness)) STORED,
  uom           text NOT NULL,
  price_method  text NOT NULL DEFAULT 'CATALOG' CHECK (price_method IN ('CATALOG','QUOTATION')),
  status        text NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_material_code     UNIQUE (material_code),
  CONSTRAINT uq_material_identity UNIQUE (name_key, thickness_key, uom)
);

CREATE TABLE IF NOT EXISTS material_supplier (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  material_id            uuid NOT NULL REFERENCES material(id),
  supplier_id            uuid NOT NULL REFERENCES supplier(id),
  supplier_material_code text,
  is_preferred           boolean NOT NULL DEFAULT false,
  status                 text NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_material_supplier UNIQUE (material_id, supplier_id),
  CHECK (NOT (is_preferred AND status = 'INACTIVE'))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_material_one_preferred ON material_supplier (material_id) WHERE is_preferred;

CREATE TABLE IF NOT EXISTS material_price (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  material_supplier_id uuid NOT NULL REFERENCES material_supplier(id),
  color                text,
  color_key            text GENERATED ALWAYS AS (fn_normalize(color)) STORED,
  price                numeric(18,4) NOT NULL CHECK (price > 0),
  currency             text NOT NULL CHECK (currency IN ('IDR','USD')),
  valid_from           date NOT NULL,
  valid_to             date,
  reference            text,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CHECK (valid_to IS NULL OR valid_to >= valid_from)
);
CREATE INDEX IF NOT EXISTS idx_material_price_link ON material_price (material_supplier_id, color_key);

-- ---------------------------------------------------------------- Trigger material
-- Merapikan isian + pesan jelas untuk duplikat (constraint tetap jadi pengaman terakhir).
-- Material Code & UoM disimpan huruf besar supaya "mtr-0001"/"MTR-0001" dan "yd"/"YD" dianggap sama.
CREATE OR REPLACE FUNCTION fn_material_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other record;
BEGIN
  NEW.material_code := upper(btrim(coalesce(NEW.material_code, '')));
  NEW.name          := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  NEW.category      := btrim(regexp_replace(coalesce(NEW.category, ''), '\s+', ' ', 'g'));
  NEW.thickness     := nullif(btrim(coalesce(NEW.thickness, '')), '');
  NEW.uom           := upper(btrim(coalesce(NEW.uom, '')));
  IF NEW.material_code = '' THEN RAISE EXCEPTION 'Material Code wajib diisi.'; END IF;
  IF NEW.name = ''          THEN RAISE EXCEPTION 'Nama material wajib diisi.'; END IF;
  IF NEW.category = ''      THEN RAISE EXCEPTION 'Kategori material wajib diisi.'; END IF;
  IF NEW.uom = ''           THEN RAISE EXCEPTION 'UoM wajib diisi.'; END IF;

  SELECT material_code, name INTO v_other FROM material
   WHERE material_code = NEW.material_code AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material Code % sudah dipakai material "%".', NEW.material_code, v_other.name;
  END IF;

  SELECT material_code, name INTO v_other FROM material
   WHERE name_key = fn_normalize(NEW.name) AND thickness_key = fn_normalize(NEW.thickness)
     AND uom = NEW.uom AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material dengan nama, thickness, dan UoM yang sama sudah ada: % — %.', v_other.material_code, v_other.name;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_material_check ON material;
CREATE TRIGGER trg_material_check BEFORE INSERT OR UPDATE ON material
  FOR EACH ROW EXECUTE FUNCTION fn_material_check();
SELECT fn_setup_table('material');

-- ---------------------------------------------------------------- Trigger supplier material
CREATE OR REPLACE FUNCTION fn_material_supplier_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_sup supplier%ROWTYPE;
BEGIN
  NEW.supplier_material_code := nullif(btrim(coalesce(NEW.supplier_material_code, '')), '');
  IF NEW.status = 'INACTIVE' THEN
    NEW.is_preferred := false;          -- supplier nonaktif tidak bisa jadi supplier utama
  END IF;
  IF TG_OP = 'INSERT' OR NEW.supplier_id IS DISTINCT FROM OLD.supplier_id THEN
    SELECT * INTO v_sup FROM supplier WHERE id = NEW.supplier_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Supplier tidak ditemukan di Master Supplier.';
    END IF;
    IF v_sup.status = 'INACTIVE' THEN
      RAISE EXCEPTION 'Supplier % sudah dinonaktifkan di Master Supplier.', v_sup.name;
    END IF;
    IF EXISTS (SELECT 1 FROM material_supplier
                WHERE material_id = NEW.material_id AND supplier_id = NEW.supplier_id AND id <> NEW.id) THEN
      RAISE EXCEPTION 'Supplier % sudah terdaftar untuk material ini.', v_sup.name;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_material_supplier_check ON material_supplier;
CREATE TRIGGER trg_material_supplier_check BEFORE INSERT OR UPDATE ON material_supplier
  FOR EACH ROW EXECUTE FUNCTION fn_material_supplier_check();
SELECT fn_setup_table('material_supplier');
SELECT fn_setup_table('material_price');

-- ---------------------------------------------------------------- Material: tambah & ubah
CREATE OR REPLACE FUNCTION fn_material_add(
  p_token text, p_code text, p_name text, p_category text, p_thickness text, p_uom text, p_price_method text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_any(p_token, ARRAY['manage_master', 'propose_master']);
  v_id    uuid;
BEGIN
  INSERT INTO material (material_code, name, category, thickness, uom, price_method, status, updated_by)
  VALUES (p_code, p_name, p_category, p_thickness, p_uom, coalesce(nullif(p_price_method, ''), 'CATALOG'),
          CASE WHEN fn_has_perm(v_email, 'manage_master') THEN 'APPROVED' ELSE 'PROPOSED' END, v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Satu form "Ubah Material": identitas & status hanya Master Admin (manage_master),
-- metode harga hanya manage_price (Master Admin, Vendor CBD). Field yang tidak berubah boleh dikirim apa adanya.
CREATE OR REPLACE FUNCTION fn_material_update(
  p_token text, p_id uuid, p_code text, p_name text, p_category text, p_thickness text, p_uom text,
  p_status text, p_price_method text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth_any(p_token, ARRAY['manage_master', 'manage_price']);
  v_master boolean := fn_has_perm(v_email, 'manage_master');
  v_price  boolean := fn_has_perm(v_email, 'manage_price');
  v_old    material%ROWTYPE;
BEGIN
  SELECT * INTO v_old FROM material WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Material tidak ditemukan.';
  END IF;
  IF NOT v_master AND (
       fn_normalize(p_code) IS DISTINCT FROM fn_normalize(v_old.material_code)
    OR fn_normalize(p_name) IS DISTINCT FROM v_old.name_key
    OR fn_normalize(p_category) IS DISTINCT FROM fn_normalize(v_old.category)
    OR fn_normalize(p_thickness) IS DISTINCT FROM v_old.thickness_key
    OR fn_normalize(p_uom) IS DISTINCT FROM fn_normalize(v_old.uom)
    OR p_status IS DISTINCT FROM v_old.status) THEN
    RAISE EXCEPTION 'Hanya Master Admin yang bisa mengubah data dan status material.';
  END IF;
  IF NOT v_price AND p_price_method IS DISTINCT FROM v_old.price_method THEN
    RAISE EXCEPTION 'Metode harga hanya bisa diubah oleh tim CBD atau Master Admin.';
  END IF;
  UPDATE material
     SET material_code = CASE WHEN v_master THEN p_code      ELSE material_code END,
         name          = CASE WHEN v_master THEN p_name      ELSE name END,
         category      = CASE WHEN v_master THEN p_category  ELSE category END,
         thickness     = CASE WHEN v_master THEN p_thickness ELSE thickness END,
         uom           = CASE WHEN v_master THEN p_uom       ELSE uom END,
         status        = CASE WHEN v_master THEN p_status    ELSE status END,
         price_method  = CASE WHEN v_price  THEN p_price_method ELSE price_method END,
         updated_by    = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$$;

-- ---------------------------------------------------------------- Supplier material
-- Tambah (p_link_id NULL) atau ubah satu supplier material.
-- manage_material_supplier: tambah, kode di supplier, supplier utama. manage_master: status.
CREATE OR REPLACE FUNCTION fn_link_save(
  p_token text, p_link_id uuid, p_material_id uuid, p_supplier_id uuid,
  p_code text, p_is_preferred boolean, p_status text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email   text := fn_auth_any(p_token, ARRAY['manage_material_supplier', 'manage_master']);
  v_link    boolean := fn_has_perm(v_email, 'manage_material_supplier');
  v_master  boolean := fn_has_perm(v_email, 'manage_master');
  v_old     material_supplier%ROWTYPE;
  v_id      uuid;
  v_pref    boolean := coalesce(p_is_preferred, false);
BEGIN
  IF p_link_id IS NULL THEN
    IF NOT v_link THEN
      RAISE EXCEPTION 'Role Anda tidak bisa menambah supplier material.';
    END IF;
    IF p_supplier_id IS NULL THEN
      RAISE EXCEPTION 'Pilih supplier.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM material WHERE id = p_material_id) THEN
      RAISE EXCEPTION 'Material tidak ditemukan.';
    END IF;
    INSERT INTO material_supplier (material_id, supplier_id, supplier_material_code, status, updated_by)
    VALUES (p_material_id, p_supplier_id, p_code,
            CASE WHEN v_master THEN 'APPROVED' ELSE 'PROPOSED' END, v_email)
    RETURNING * INTO v_old;
  ELSE
    SELECT * INTO v_old FROM material_supplier WHERE id = p_link_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Supplier material tidak ditemukan.';
    END IF;
    IF NOT v_link AND (nullif(btrim(coalesce(p_code, '')), '') IS DISTINCT FROM v_old.supplier_material_code
                       OR v_pref IS DISTINCT FROM v_old.is_preferred) THEN
      RAISE EXCEPTION 'Role Anda tidak bisa mengubah kode supplier atau supplier utama.';
    END IF;
    IF NOT v_master AND p_status IS DISTINCT FROM v_old.status THEN
      RAISE EXCEPTION 'Status supplier material hanya bisa diubah oleh Master Admin.';
    END IF;
    UPDATE material_supplier
       SET supplier_material_code = p_code,
           status = coalesce(p_status, status),
           is_preferred = CASE WHEN coalesce(p_status, status) = 'INACTIVE' THEN false ELSE is_preferred END,
           updated_by = v_email
     WHERE id = p_link_id
    RETURNING * INTO v_old;
    IF v_old.status = 'INACTIVE' THEN
      v_pref := false;                  -- dinonaktifkan: otomatis bukan supplier utama lagi
    END IF;
  END IF;
  v_id := v_old.id;

  -- Supplier utama: maksimal satu per material
  IF v_pref AND NOT v_old.is_preferred THEN
    IF v_old.status = 'INACTIVE' THEN
      RAISE EXCEPTION 'Supplier yang nonaktif tidak bisa dijadikan supplier utama.';
    END IF;
    UPDATE material_supplier SET is_preferred = false, updated_by = v_email
     WHERE material_id = v_old.material_id AND is_preferred AND id <> v_id;
    UPDATE material_supplier SET is_preferred = true, updated_by = v_email WHERE id = v_id;
  ELSIF NOT v_pref AND v_old.is_preferred THEN
    UPDATE material_supplier SET is_preferred = false, updated_by = v_email WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;

-- Dipakai fungsi BOM (F5): supplier dipilih di BOM -> link otomatis (PROPOSED) kalau belum ada.
-- Link yang dinonaktifkan Master Admin ditolak. Tidak cek izin sendiri: pemanggil sudah memanggil fn_auth.
CREATE OR REPLACE FUNCTION fn_ensure_link(p_material_id uuid, p_supplier_id uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_link material_supplier%ROWTYPE;
  v_id   uuid;
BEGIN
  IF p_supplier_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_link FROM material_supplier WHERE material_id = p_material_id AND supplier_id = p_supplier_id;
  IF FOUND THEN
    IF v_link.status = 'INACTIVE' THEN
      RAISE EXCEPTION 'Supplier % sudah dinonaktifkan untuk material %. Pilih supplier lain.',
        (SELECT name FROM supplier WHERE id = p_supplier_id), (SELECT name FROM material WHERE id = p_material_id);
    END IF;
    RETURN v_link.id;
  END IF;
  INSERT INTO material_supplier (material_id, supplier_id, status, updated_by)
  VALUES (p_material_id, p_supplier_id, 'PROPOSED', nullif(current_setting('app.user', true), ''))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------- Harga
CREATE OR REPLACE FUNCTION fn_price_add(
  p_token text, p_link_id uuid, p_color text, p_price numeric, p_currency text,
  p_valid_from date, p_reference text
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email  text := fn_auth(p_token, 'manage_price');
  v_link   record;
  v_open   material_price%ROWTYPE;
  v_color  text := nullif(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g')), '');
  v_from   date := coalesce(p_valid_from, fn_today());
  v_id     uuid;
BEGIN
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

  SELECT * INTO v_open FROM material_price
   WHERE material_supplier_id = p_link_id AND color_key = fn_normalize(v_color) AND valid_to IS NULL
   ORDER BY valid_from DESC LIMIT 1;
  IF FOUND THEN
    IF v_from < v_open.valid_from THEN
      RAISE EXCEPTION 'Sudah ada harga yang berlaku mulai % untuk %. Tanggal berlaku harga baru tidak boleh lebih awal dari itu.',
        to_char(v_open.valid_from, 'DD-MM-YYYY'), CASE WHEN v_color IS NULL THEN 'semua warna' ELSE 'warna ' || v_color END;
    END IF;
    UPDATE material_price SET valid_to = v_from, updated_by = v_email WHERE id = v_open.id;
  END IF;

  INSERT INTO material_price (material_supplier_id, color, price, currency, valid_from, reference, updated_by)
  VALUES (p_link_id, v_color, p_price, p_currency, v_from, nullif(btrim(coalesce(p_reference, '')), ''), v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Akhiri harga yang masih berlaku (default hari ini, WIB)
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
  IF v_row.valid_to IS NOT NULL THEN
    RAISE EXCEPTION 'Harga ini sudah tidak berlaku.';
  END IF;
  UPDATE material_price
     SET valid_to = greatest(coalesce(p_valid_to, fn_today()), valid_from), updated_by = v_email
   WHERE id = p_price_id;
  RETURN p_price_id;
END;
$$;

-- Harga master yang berlaku (dipakai CBD di F7/F8): harga warna dulu, lalu harga semua warna.
-- Tidak ada fallback lintas supplier. Material QUOTATION -> 0 baris.
CREATE OR REPLACE FUNCTION fn_price_lookup(p_material_id uuid, p_supplier_id uuid, p_color text, p_on date DEFAULT NULL)
RETURNS TABLE (price_id uuid, price numeric, currency text, tier text)
LANGUAGE sql STABLE AS $$
  SELECT mp.id, mp.price, mp.currency, CASE WHEN mp.color_key = '' THEN 'ALL_COLORS' ELSE 'COLOR' END
    FROM material_price mp
    JOIN material_supplier ms ON ms.id = mp.material_supplier_id
    JOIN material m ON m.id = ms.material_id
   WHERE ms.material_id = p_material_id AND ms.supplier_id = p_supplier_id
     AND m.price_method = 'CATALOG'
     AND mp.color_key IN (fn_normalize(p_color), '')
     AND mp.valid_from <= coalesce(p_on, fn_today())
     AND (mp.valid_to IS NULL OR mp.valid_to > coalesce(p_on, fn_today()))
   ORDER BY (mp.color_key = '') ASC, mp.valid_from DESC, mp.created_at DESC
   LIMIT 1
$$;

-- ---------------------------------------------------------------- Daftar material + ringkasan supplier/harga
-- missing_price = material CATALOG yang punya supplier aktif tanpa harga berlaku hari ini.
CREATE OR REPLACE VIEW v_material_list AS
SELECT m.id, m.material_code, m.name, m.name_key, m.category, m.thickness, m.uom, m.price_method, m.status,
       m.updated_at, m.updated_by,
       coalesce(s.suppliers, 0) AS supplier_count,
       coalesce(s.proposed, 0)  AS proposed_links,
       coalesce(s.priced, 0)    AS priced_links,
       s.preferred_supplier,
       (m.price_method = 'CATALOG' AND coalesce(s.suppliers, 0) > coalesce(s.priced, 0)) AS missing_price
  FROM material m
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE ms.status <> 'INACTIVE') AS suppliers,
           count(*) FILTER (WHERE ms.status = 'PROPOSED')  AS proposed,
           count(*) FILTER (WHERE ms.status <> 'INACTIVE' AND EXISTS (
             SELECT 1 FROM material_price mp
              WHERE mp.material_supplier_id = ms.id AND mp.valid_from <= fn_today()
                AND (mp.valid_to IS NULL OR mp.valid_to > fn_today()))) AS priced,
           max(sp.name) FILTER (WHERE ms.is_preferred) AS preferred_supplier
      FROM material_supplier ms JOIN supplier sp ON sp.id = ms.supplier_id
     WHERE ms.material_id = m.id
  ) s ON true;
