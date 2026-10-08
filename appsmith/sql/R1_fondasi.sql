-- ============================================================================
-- R1 — Fondasi revisi: master Pabrik, user menempel ke pabrik, role baru, matriks izin
-- (keputusan user 8 Okt 2026, PLAN.md §2 "Revisi besar" & §6 R1)
-- Jalankan SETELAH RESET_data_uji.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi: kalau ada error, tidak ada yang tersimpan.
--
-- Aturan:
-- - Role: MASTER_ADMIN dihapus; MANAGER_COSTING (baru) hanya approve / tolak / akhiri harga.
-- - 1 user = 1 pabrik: VENDOR_SPEC, VENDOR_CBD, MANAGER_COSTING wajib punya pabrik;
--   BRAND_VIEWER & SYSTEM_ADMIN tanpa pabrik (lihat semua pabrik).
-- - Pabrik dikelola System Admin (manage_factory). Nama unik (huruf besar, spasi dirapatkan).
--   Pabrik tidak bisa dinonaktifkan selama masih punya user aktif.
-- - Masa transisi R1 → R3 (fungsi lama belum ditulis ulang):
--     * Vendor Spec memegang manage_master → master yang ia tambah langsung APPROVED (= tanpa approval).
--     * manage_material_supplier tetap untuk Vendor Spec sampai R2 (fn_link_save lama memerlukannya).
--     * Fungsi harga F3b ditambal: approve / tolak / akhiri = approve_price (Manager Costing),
--       usulan harga tidak pernah langsung APPROVED. Link supplier otomatis dari BOM langsung APPROVED.
-- ============================================================================

-- ---------------------------------------------------------------- Pengaman
DO $$
BEGIN
  IF to_regclass('public.factory') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'factory' AND column_name = 'name_key') THEN
    RAISE EXCEPTION 'Tabel "factory" sudah ada di database dan bukan milik proyek ini. Hentikan dan hubungi pengembang.';
  END IF;
  IF EXISTS (SELECT 1 FROM app_user WHERE role = 'MASTER_ADMIN') THEN
    RAISE EXCEPTION 'Masih ada user dengan role Master Admin. Jalankan RESET_data_uji.sql dulu (keputusan user 8 Okt 2026).';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Pabrik
CREATE TABLE IF NOT EXISTS factory (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL CHECK (btrim(name) <> ''),
  name_key   text GENERATED ALWAYS AS (fn_normalize(name)) STORED,
  status     text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_factory_name UNIQUE (name_key)
);

CREATE OR REPLACE FUNCTION fn_factory_check() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_other text;
BEGIN
  NEW.name := upper(btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g')));
  IF NEW.name = '' THEN
    RAISE EXCEPTION 'Nama pabrik wajib diisi.';
  END IF;
  SELECT name INTO v_other FROM factory WHERE name_key = fn_normalize(NEW.name) AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Pabrik "%" sudah ada.', v_other;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.status = 'INACTIVE' AND OLD.status <> 'INACTIVE'
     AND EXISTS (SELECT 1 FROM app_user WHERE factory_id = NEW.id AND is_active) THEN
    RAISE EXCEPTION 'Pabrik % masih punya user aktif. Nonaktifkan atau pindahkan user-nya dulu.', NEW.name;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_factory_check ON factory;
CREATE TRIGGER trg_factory_check BEFORE INSERT OR UPDATE ON factory
  FOR EACH ROW EXECUTE FUNCTION fn_factory_check();
SELECT fn_setup_table('factory');

-- ---------------------------------------------------------------- User: role & pabrik
ALTER TABLE app_user ADD COLUMN IF NOT EXISTS factory_id uuid REFERENCES factory(id);
CREATE INDEX IF NOT EXISTS idx_app_user_factory ON app_user (factory_id);

-- CHECK role lama (tanpa nama, dibuat F1) diganti constraint bernama
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'app_user'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) LIKE '%MASTER_ADMIN%'
  LOOP
    EXECUTE format('ALTER TABLE app_user DROP CONSTRAINT %I', r.conname);
  END LOOP;
END;
$$;
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS ck_app_user_role;
ALTER TABLE app_user ADD CONSTRAINT ck_app_user_role
  CHECK (role IN ('VENDOR_SPEC','VENDOR_CBD','MANAGER_COSTING','BRAND_VIEWER','SYSTEM_ADMIN'));
ALTER TABLE app_user DROP CONSTRAINT IF EXISTS ck_app_user_factory;
ALTER TABLE app_user ADD CONSTRAINT ck_app_user_factory
  CHECK ((role IN ('VENDOR_SPEC','VENDOR_CBD','MANAGER_COSTING')) = (factory_id IS NOT NULL));

CREATE OR REPLACE FUNCTION fn_role_label(p_role text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_role
    WHEN 'VENDOR_SPEC'     THEN 'Vendor - Specsheet'
    WHEN 'VENDOR_CBD'      THEN 'Vendor - CBD'
    WHEN 'MANAGER_COSTING' THEN 'Manager Costing'
    WHEN 'BRAND_VIEWER'    THEN 'Brand Viewer'
    WHEN 'SYSTEM_ADMIN'    THEN 'System Admin'
    ELSE p_role
  END
$$;

CREATE OR REPLACE FUNCTION fn_is_factory_role(p_role text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(p_role, '') IN ('VENDOR_SPEC', 'VENDOR_CBD', 'MANAGER_COSTING')
$$;

-- ---------------------------------------------------------------- Matriks izin (PLAN.md §5 "Mulai R1")
DELETE FROM role_permission;
INSERT INTO role_permission (role, permission) VALUES
  ('VENDOR_SPEC','view_master'), ('VENDOR_CBD','view_master'), ('MANAGER_COSTING','view_master'), ('BRAND_VIEWER','view_master'),
  ('VENDOR_SPEC','view_model'),  ('VENDOR_CBD','view_model'),  ('MANAGER_COSTING','view_model'),  ('BRAND_VIEWER','view_model'),
  ('VENDOR_SPEC','view_specsheet'), ('VENDOR_CBD','view_specsheet'), ('MANAGER_COSTING','view_specsheet'), ('BRAND_VIEWER','view_specsheet'),
  ('VENDOR_CBD','view_cbd'),   ('MANAGER_COSTING','view_cbd'),   ('BRAND_VIEWER','view_cbd'),
  ('VENDOR_CBD','view_price'), ('MANAGER_COSTING','view_price'), ('BRAND_VIEWER','view_price'),
  ('VENDOR_SPEC','view_drafts'), ('VENDOR_CBD','view_drafts'), ('MANAGER_COSTING','view_drafts'),
  ('VENDOR_SPEC','manage_master'),
  ('VENDOR_SPEC','manage_material_supplier'),          -- transisi, digabung ke manage_master di R2
  ('VENDOR_CBD','manage_price'),
  ('MANAGER_COSTING','approve_price'),
  ('VENDOR_SPEC','edit_model'), ('VENDOR_SPEC','edit_specsheet'),
  ('VENDOR_CBD','edit_cbd'),
  ('BRAND_VIEWER','simulate_margin'),
  ('SYSTEM_ADMIN','manage_users'), ('SYSTEM_ADMIN','manage_factory'), ('SYSTEM_ADMIN','view_audit');

-- ---------------------------------------------------------------- Helper pabrik (dipakai R2–R7)
-- Pabrik user (NULL = Brand / System Admin = semua pabrik)
CREATE OR REPLACE FUNCTION fn_user_factory(p_email text) RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT factory_id FROM app_user WHERE email = lower(btrim(coalesce(p_email, '')))
$$;

-- true kalau user boleh melihat data pabrik p_factory_id
CREATE OR REPLACE FUNCTION fn_can_see_factory(p_email text, p_factory_id uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT fn_user_factory(p_email) IS NULL OR fn_user_factory(p_email) = p_factory_id
$$;

-- Dipanggil fungsi tulis: menolak kalau data milik pabrik lain
CREATE OR REPLACE FUNCTION fn_assert_factory(p_email text, p_factory_id uuid) RETURNS void
LANGUAGE plpgsql STABLE AS $$
BEGIN
  IF NOT fn_can_see_factory(p_email, p_factory_id) THEN
    RAISE EXCEPTION 'Data ini milik pabrik lain.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Profil login (+ pabrik)
DROP FUNCTION IF EXISTS fn_me(text);
CREATE FUNCTION fn_me(p_token text)
RETURNS TABLE (email text, full_name text, role text, role_label text,
               must_change_password boolean, expires_at timestamptz, permissions text,
               factory_id uuid, factory_name text)
LANGUAGE sql STABLE AS $$
  SELECT u.email, u.full_name, u.role, fn_role_label(u.role), u.must_change_password, s.expires_at,
         coalesce((SELECT string_agg(rp.permission, ',' ORDER BY rp.permission)
                     FROM role_permission rp WHERE rp.role = u.role), ''),
         u.factory_id, f.name
    FROM app_session s
    JOIN app_user u ON u.email = s.email
    LEFT JOIN factory f ON f.id = u.factory_id
   WHERE s.token_hash = fn_token_hash(p_token) AND s.expires_at > now() AND u.is_active
$$;

-- ---------------------------------------------------------------- Kelola user (+ pabrik)
DROP FUNCTION IF EXISTS fn_user_save(text, text, text, text, boolean, boolean);
CREATE OR REPLACE FUNCTION fn_user_save(
  p_token text, p_email text, p_full_name text, p_role text, p_is_active boolean, p_is_new boolean,
  p_factory_id uuid
) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_actor   text := fn_auth(p_token, 'manage_users');
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_name    text := btrim(coalesce(p_full_name, ''));
  v_factory uuid := CASE WHEN fn_is_factory_role(p_role) THEN p_factory_id END;
  v_pass    text;
BEGIN
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'Format email tidak valid.';
  END IF;
  IF v_name = '' THEN
    RAISE EXCEPTION 'Nama wajib diisi.';
  END IF;
  IF coalesce(p_role, '') = '' THEN
    RAISE EXCEPTION 'Role wajib dipilih.';
  END IF;
  IF fn_is_factory_role(p_role) THEN
    IF v_factory IS NULL THEN
      RAISE EXCEPTION 'Role % wajib memilih pabrik.', fn_role_label(p_role);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM factory WHERE id = v_factory AND status = 'ACTIVE') THEN
      RAISE EXCEPTION 'Pabrik yang dipilih tidak ada atau sudah nonaktif.';
    END IF;
  END IF;
  IF v_email = v_actor AND (p_role <> 'SYSTEM_ADMIN' OR NOT coalesce(p_is_active, true)) THEN
    RAISE EXCEPTION 'Anda tidak bisa mengubah role atau menonaktifkan akun sendiri.';
  END IF;

  IF p_is_new THEN
    IF EXISTS (SELECT 1 FROM app_user WHERE email = v_email) THEN
      RAISE EXCEPTION 'Email % sudah terdaftar.', v_email;
    END IF;
    v_pass := fn_random_password();
    INSERT INTO app_user (email, full_name, role, factory_id, is_active, password_hash, must_change_password, updated_by)
    VALUES (v_email, v_name, p_role, v_factory, coalesce(p_is_active, true), crypt(v_pass, gen_salt('bf', 10)),
            true, v_actor);
  ELSE
    UPDATE app_user
       SET full_name = v_name, role = p_role, factory_id = v_factory, is_active = coalesce(p_is_active, true),
           updated_by = v_actor
     WHERE email = v_email;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'User % tidak ditemukan.', v_email;
    END IF;
    -- pindah role/pabrik atau nonaktif: sesi lama ditutup supaya izin & lingkup data langsung berlaku
    DELETE FROM app_session WHERE email = v_email;
  END IF;
  RETURN v_pass;
END;
$$;

-- ---------------------------------------------------------------- Kelola pabrik
CREATE OR REPLACE FUNCTION fn_factory_save(p_token text, p_id uuid, p_name text, p_status text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_actor text := fn_auth(p_token, 'manage_factory');
  v_id    uuid;
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Status pabrik wajib dipilih.';
  END IF;
  IF p_id IS NULL THEN
    INSERT INTO factory (name, status, updated_by) VALUES (p_name, p_status, v_actor) RETURNING id INTO v_id;
  ELSE
    UPDATE factory SET name = p_name, status = p_status, updated_by = v_actor WHERE id = p_id RETURNING id INTO v_id;
    IF v_id IS NULL THEN
      RAISE EXCEPTION 'Pabrik tidak ditemukan.';
    END IF;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE VIEW v_factory_list AS
SELECT f.id, f.name, f.status,
       (SELECT count(*) FROM app_user u WHERE u.factory_id = f.id AND u.is_active)::int AS active_users,
       f.updated_at, f.updated_by
  FROM factory f;

-- ---------------------------------------------------------------- Tambalan transisi (ditulis ulang di R2/R3)
-- Ganti teks di definisi function yang SEDANG terpasang (bukan salinan), supaya perubahan F3b/F10b ikut terbawa.
DO $$
DECLARE
  r     record;
  v_src text;
  v_new text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('fn_price_add(text,uuid,text,numeric,text,date,text)', 'fn_has_perm(v_email, ''manage_master'')', 'fn_has_perm(v_email, ''approve_price'')'),
      ('fn_price_add(text,uuid,text,numeric,text,date,text)', 'minta Master Admin', 'minta Manager Costing'),
      ('fn_price_approve(text,uuid)',      'fn_auth(p_token, ''manage_master'')', 'fn_auth(p_token, ''approve_price'')'),
      ('fn_price_reject(text,uuid,text)',  'fn_auth(p_token, ''manage_master'')', 'fn_auth(p_token, ''approve_price'')'),
      ('fn_price_end(text,uuid,date)',     'fn_auth(p_token, ''manage_price'')',  'fn_auth(p_token, ''approve_price'')'),
      ('fn_ensure_link(uuid,uuid)',        'p_supplier_id, ''PROPOSED''',         'p_supplier_id, ''APPROVED''')
    ) AS t(sig, old_text, new_text)
  LOOP
    v_src := pg_get_functiondef(r.sig::regprocedure);
    IF position(r.new_text IN v_src) > 0 THEN
      CONTINUE;                                   -- sudah ditambal (skrip diulang)
    END IF;
    IF position(r.old_text IN v_src) = 0 THEN
      RAISE EXCEPTION 'Tambalan R1 gagal: teks "%" tidak ditemukan di %. Hentikan dan hubungi pengembang.', r.old_text, r.sig;
    END IF;
    v_new := replace(v_src, r.old_text, r.new_text);
    EXECUTE v_new;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------- Cek hasil (dibaca di DB Tools)
SELECT 'role_permission' AS cek, count(*)::text AS hasil FROM role_permission
UNION ALL SELECT 'role tanpa Master Admin', string_agg(DISTINCT role, ', ' ORDER BY role) FROM role_permission
UNION ALL SELECT 'kolom app_user.factory_id', count(*)::text FROM information_schema.columns
           WHERE table_name = 'app_user' AND column_name = 'factory_id'
UNION ALL SELECT 'tabel factory', coalesce(to_regclass('public.factory')::text, 'TIDAK ADA')
UNION ALL SELECT 'fn_price_approve pakai approve_price',
           (position('approve_price' IN pg_get_functiondef('fn_price_approve(text,uuid)'::regprocedure)) > 0)::text;
