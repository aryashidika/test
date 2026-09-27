-- ============================================================================
-- F2 — Master Supplier & Komponen
-- Jalankan SETELAH F1 + F1b, lewat z_run_sql di app "DB Tools"
-- (Use prepared statements = OFF). Aman diulang.
-- Seluruh file berjalan sebagai satu transaksi: kalau ada error, tidak ada yang tersimpan.
-- ============================================================================

-- ---------------------------------------------------------------- Cek bentrok nama
-- Database dipakai bersama aplikasi lain: berhenti kalau tabel dengan nama yang sama
-- sudah ada tapi bukan milik proyek ini (tidak punya kolom khas proyek).
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('supplier', 'name_key'), ('component_group', 'range_start'),
                                 ('component', 'group_code')) AS t(tbl, col)
  LOOP
    IF to_regclass('public.' || r.tbl) IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = r.tbl AND column_name = r.col) THEN
      RAISE EXCEPTION 'Tabel "%" sudah ada di database dan bukan milik proyek ini. Hentikan dan hubungi pengembang.', r.tbl;
    END IF;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------- Helper izin
-- true kalau user aktif dengan role yang punya izin tsb.
CREATE OR REPLACE FUNCTION fn_has_perm(p_email text, p_permission text) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM app_user u JOIN role_permission rp ON rp.role = u.role
                  WHERE u.email = p_email AND u.is_active AND rp.permission = p_permission)
$$;

-- Seperti fn_auth, tapi cukup punya SALAH SATU izin (mis. manage_master atau propose_master).
CREATE OR REPLACE FUNCTION fn_auth_any(p_token text, p_permissions text[]) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, NULL);   -- SESI_HABIS kalau token tidak valid
  v_perm  text;
BEGIN
  FOREACH v_perm IN ARRAY p_permissions LOOP
    IF fn_has_perm(v_email, v_perm) THEN
      RETURN fn_auth(p_token, v_perm);        -- cek wajib-ganti-password + catat user audit
    END IF;
  END LOOP;
  RAISE EXCEPTION 'Role % tidak punya akses untuk aksi ini.',
    fn_role_label((SELECT role FROM app_user WHERE email = v_email));
END;
$$;

-- ---------------------------------------------------------------- Supplier
CREATE TABLE IF NOT EXISTS supplier (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name             text NOT NULL CHECK (btrim(name) <> ''),
  name_key         text GENERATED ALWAYS AS (fn_normalize(name)) STORED,
  status           text NOT NULL DEFAULT 'APPROVED' CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_supplier_name UNIQUE (name_key)
);
-- Supplier tidak punya currency default: currency dipilih per harga (material_price / CBD).
-- Hapus kolom lama kalau versi awal F2 sudah telanjur dijalankan.
ALTER TABLE supplier DROP COLUMN IF EXISTS default_currency;

-- Nama dirapikan; nama yang hanya beda huruf besar/kecil/spasi dengan supplier lain ditolak
-- dengan pesan jelas (constraint uq_supplier_name tetap jadi pengaman terakhir).
CREATE OR REPLACE FUNCTION fn_supplier_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other text;
BEGIN
  NEW.name := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  IF NEW.name = '' THEN
    RAISE EXCEPTION 'Nama supplier wajib diisi.';
  END IF;
  SELECT name INTO v_other FROM supplier
   WHERE name_key = fn_normalize(NEW.name) AND id <> NEW.id;
  IF v_other IS NOT NULL THEN
    RAISE EXCEPTION 'Supplier "%" sudah ada.', v_other;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_supplier_check ON supplier;
CREATE TRIGGER trg_supplier_check BEFORE INSERT OR UPDATE ON supplier
  FOR EACH ROW EXECUTE FUNCTION fn_supplier_check();
SELECT fn_setup_table('supplier');

-- ---------------------------------------------------------------- Kelompok komponen
CREATE TABLE IF NOT EXISTS component_group (
  code        text PRIMARY KEY,
  name        text NOT NULL,
  range_start integer NOT NULL,
  range_end   integer NOT NULL,
  sort_order  integer NOT NULL
);
-- Kode kelompok berurutan a/b/c/d (keputusan user 27 Sep 2026; di Python a/c/d/e).
-- Seed diisi di bawah, setelah tabel component (lihat "Kode kelompok a/b/c/d").

-- ---------------------------------------------------------------- Komponen
CREATE TABLE IF NOT EXISTS component (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number     integer NOT NULL CHECK (number % 10 = 0),
  name       text NOT NULL CHECK (btrim(name) <> ''),
  group_code text NOT NULL REFERENCES component_group(code) ON UPDATE CASCADE,
  status     text NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_component_number UNIQUE (number)
);
CREATE INDEX IF NOT EXISTS idx_component_group ON component (group_code, number);

-- ---------------------------------------------------------------- Kode kelompok a/b/c/d
-- FK ON UPDATE CASCADE supaya kode kelompok bisa diganti tanpa merusak komponen.
ALTER TABLE component DROP CONSTRAINT IF EXISTS component_group_code_fkey;
ALTER TABLE component ADD CONSTRAINT component_group_code_fkey
  FOREIGN KEY (group_code) REFERENCES component_group(code) ON UPDATE CASCADE;

-- Versi awal F2 memakai a/c/d/e: ganti berurutan c->b, d->c, e->d (komponen ikut lewat CASCADE).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM component_group WHERE code = 'e') THEN
    UPDATE component_group SET code = 'b' WHERE code = 'c';
    UPDATE component_group SET code = 'c' WHERE code = 'd';
    UPDATE component_group SET code = 'd' WHERE code = 'e';
  END IF;
END;
$$;

INSERT INTO component_group (code, name, range_start, range_end, sort_order) VALUES
  ('a', 'Upper',         0,    3990, 1),
  ('b', 'Bottom unit',   4000, 5990, 2),
  ('c', 'Packaging',     6000, 7990, 3),
  ('d', 'Miscellaneous', 8000, 9990, 4)
ON CONFLICT (code) DO NOTHING;

-- Aturan nomor (= component_service._validate): wajib, kelipatan 10, di rentang kelompoknya,
-- belum dipakai komponen lain. Komponen tidak bisa dihapus, jadi nomor tidak pernah dipakai ulang.
CREATE OR REPLACE FUNCTION fn_component_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_group component_group%ROWTYPE;
  v_other text;
BEGIN
  NEW.name := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  IF NEW.name = '' THEN
    RAISE EXCEPTION 'Nama komponen wajib diisi.';
  END IF;
  -- Ubah status saja tidak perlu cek ulang nomor
  IF TG_OP = 'UPDATE' AND NEW.number IS NOT DISTINCT FROM OLD.number
     AND NEW.group_code IS NOT DISTINCT FROM OLD.group_code THEN
    RETURN NEW;
  END IF;
  IF NEW.number IS NULL THEN
    RAISE EXCEPTION 'Nomor komponen wajib diisi.';
  END IF;
  SELECT * INTO v_group FROM component_group WHERE code = NEW.group_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kelompok komponen wajib dipilih.';
  END IF;
  IF NEW.number % 10 <> 0 THEN
    RAISE EXCEPTION 'Nomor komponen harus kelipatan 10.';
  END IF;
  IF NEW.number NOT BETWEEN v_group.range_start AND v_group.range_end THEN
    RAISE EXCEPTION 'Nomor harus berada di rentang %–% untuk kelompok %.',
      v_group.range_start, v_group.range_end, v_group.name;
  END IF;
  SELECT name INTO v_other FROM component WHERE number = NEW.number AND id <> NEW.id;
  IF v_other IS NOT NULL THEN
    RAISE EXCEPTION 'Nomor % sudah dipakai komponen "%" dan tidak bisa dipakai ulang.', NEW.number, v_other;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_component_check ON component;
CREATE TRIGGER trg_component_check BEFORE INSERT OR UPDATE ON component
  FOR EACH ROW EXECUTE FUNCTION fn_component_check();
SELECT fn_setup_table('component');

-- Tambah komponen: Master Admin -> APPROVED, vendor (propose_master) -> PROPOSED.
-- Status ditentukan di DB, bukan di UI.
CREATE OR REPLACE FUNCTION fn_component_add(p_token text, p_group_code text, p_number integer, p_name text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth_any(p_token, ARRAY['manage_master', 'propose_master']);
  v_id    uuid;
BEGIN
  INSERT INTO component (number, name, group_code, status, updated_by)
  VALUES (p_number, p_name, p_group_code,
          CASE WHEN fn_has_perm(v_email, 'manage_master') THEN 'APPROVED' ELSE 'PROPOSED' END,
          v_email)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
