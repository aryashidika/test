-- ============================================================================
-- F1 — Fondasi: fungsi dasar, user & role, audit log otomatis
-- Jalankan lewat query z_run_sql (Use prepared statements = OFF).
-- Aman diulang (idempoten).
-- ============================================================================

-- ---------------------------------------------------------------- Fungsi dasar
-- Kunci pencocokan: huruf kecil, koma -> titik, spasi dirapatkan, trim (= app/normalize.py)
CREATE OR REPLACE FUNCTION fn_normalize(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT btrim(regexp_replace(replace(lower(coalesce(p, '')), ',', '.'), '\s+', ' ', 'g'))
$$;

-- "Hari ini" menurut WIB
CREATE OR REPLACE FUNCTION fn_today() RETURNS date
LANGUAGE sql STABLE AS $$
  SELECT (now() AT TIME ZONE 'Asia/Jakarta')::date
$$;

-- ---------------------------------------------------------------- Tabel
CREATE TABLE IF NOT EXISTS app_user (
  email      text PRIMARY KEY CHECK (email = lower(btrim(email))),
  full_name  text NOT NULL,
  role       text NOT NULL CHECK (role IN ('MASTER_ADMIN','VENDOR_SPEC','VENDOR_CBD','BRAND_VIEWER','SYSTEM_ADMIN')),
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text
);

CREATE TABLE IF NOT EXISTS role_permission (
  role       text NOT NULL,
  permission text NOT NULL,
  PRIMARY KEY (role, permission)
);

CREATE TABLE IF NOT EXISTS audit_log (
  id          bigserial PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  user_email  text,
  entity      text NOT NULL,
  entity_id   text,
  action      text NOT NULL,
  before_data jsonb,
  after_data  jsonb
);
CREATE INDEX IF NOT EXISTS idx_audit_entity  ON audit_log (entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log (created_at DESC);

-- ---------------------------------------------------------------- Matriks hak akses
INSERT INTO role_permission (role, permission) VALUES
  ('MASTER_ADMIN','view_master'), ('VENDOR_SPEC','view_master'), ('VENDOR_CBD','view_master'), ('BRAND_VIEWER','view_master'),
  ('MASTER_ADMIN','view_model'),  ('VENDOR_SPEC','view_model'),  ('VENDOR_CBD','view_model'),  ('BRAND_VIEWER','view_model'),
  ('MASTER_ADMIN','view_specsheet'), ('VENDOR_SPEC','view_specsheet'), ('VENDOR_CBD','view_specsheet'), ('BRAND_VIEWER','view_specsheet'),
  ('MASTER_ADMIN','view_cbd'),   ('VENDOR_CBD','view_cbd'),   ('BRAND_VIEWER','view_cbd'),
  ('MASTER_ADMIN','view_price'), ('VENDOR_CBD','view_price'), ('BRAND_VIEWER','view_price'),
  ('MASTER_ADMIN','view_drafts'), ('VENDOR_SPEC','view_drafts'), ('VENDOR_CBD','view_drafts'),
  ('MASTER_ADMIN','manage_master'),
  ('VENDOR_SPEC','propose_master'), ('VENDOR_CBD','propose_master'),
  ('MASTER_ADMIN','manage_material_supplier'), ('VENDOR_SPEC','manage_material_supplier'),
  ('MASTER_ADMIN','manage_price'), ('VENDOR_CBD','manage_price'),
  ('MASTER_ADMIN','edit_model'), ('VENDOR_SPEC','edit_model'),
  ('VENDOR_SPEC','edit_specsheet'),
  ('VENDOR_CBD','edit_cbd'),
  ('SYSTEM_ADMIN','manage_users'), ('SYSTEM_ADMIN','view_audit')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION fn_role_label(p_role text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_role
    WHEN 'MASTER_ADMIN' THEN 'Master Admin'
    WHEN 'VENDOR_SPEC'  THEN 'Vendor - Specsheet'
    WHEN 'VENDOR_CBD'   THEN 'Vendor - CBD'
    WHEN 'BRAND_VIEWER' THEN 'Brand Viewer'
    WHEN 'SYSTEM_ADMIN' THEN 'System Admin'
    ELSE p_role
  END
$$;

-- Profil + izin user login (permissions = teks dipisah koma, dipecah di JS Auth)
CREATE OR REPLACE VIEW v_my_perms AS
SELECT u.email, u.full_name, u.role, fn_role_label(u.role) AS role_label, u.is_active,
       coalesce(string_agg(rp.permission, ',' ORDER BY rp.permission), '') AS permissions
  FROM app_user u
  LEFT JOIN role_permission rp ON rp.role = u.role
 GROUP BY u.email, u.full_name, u.role, u.is_active;

-- Dipanggil di awal setiap fn_* yang mengubah data. Menolak kalau user tidak
-- terdaftar/nonaktif/tidak berizin, lalu mencatat email-nya untuk trigger audit.
CREATE OR REPLACE FUNCTION fn_assert_perm(p_email text, p_permission text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_role  text;
BEGIN
  SELECT role INTO v_role FROM app_user WHERE email = v_email AND is_active;
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'Akun % belum terdaftar atau nonaktif. Hubungi System Admin.', v_email;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM role_permission WHERE role = v_role AND permission = p_permission) THEN
    RAISE EXCEPTION 'Role % tidak punya akses untuk aksi ini.', fn_role_label(v_role);
  END IF;
  PERFORM set_config('app.user', v_email, true);
  RETURN v_role;
END;
$$;

-- ---------------------------------------------------------------- Trigger standar
-- BEFORE: isi created_*/updated_* otomatis.
-- Query tulis dari Appsmith WAJIB mengisi updated_by = email user.
CREATE OR REPLACE FUNCTION fn_touch_trigger() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_user text := nullif(current_setting('app.user', true), '');
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := coalesce(v_user, NEW.created_by, NEW.updated_by);
    NEW.updated_by := coalesce(v_user, NEW.updated_by, NEW.created_by);
    NEW.created_at := now();
    NEW.updated_at := now();
  ELSE
    NEW.created_at := OLD.created_at;
    NEW.created_by := OLD.created_by;
    NEW.updated_at := now();
    NEW.updated_by := coalesce(v_user, NEW.updated_by);
  END IF;
  RETURN NEW;
END;
$$;

-- AFTER: catat before/after ke audit_log (kolom file `content` tidak ikut dicatat).
CREATE OR REPLACE FUNCTION fn_audit_trigger() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_old jsonb;
  v_new jsonb;
  v_row jsonb;
BEGIN
  IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD) - 'content'; END IF;
  IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW) - 'content'; END IF;
  -- UPDATE yang tidak mengubah apa pun tidak dicatat
  IF TG_OP = 'UPDATE' AND (v_old - 'updated_at' - 'updated_by') = (v_new - 'updated_at' - 'updated_by') THEN
    RETURN NULL;
  END IF;
  v_row := coalesce(v_new, v_old);
  INSERT INTO audit_log (user_email, entity, entity_id, action, before_data, after_data)
  VALUES (
    coalesce(nullif(current_setting('app.user', true), ''), v_new ->> 'updated_by', v_old ->> 'updated_by'),
    TG_TABLE_NAME,
    coalesce(v_row ->> 'id', v_row ->> 'email', v_row ->> 'code',
             concat_ws(':', v_row ->> 'revision_id', v_row ->> 'bom_line_id', v_row ->> 'article_id')),
    TG_OP, v_old, v_new
  );
  RETURN NULL;
END;
$$;

-- Pasang kedua trigger di satu tabel bisnis. Dipakai lagi di setiap fase.
CREATE OR REPLACE FUNCTION fn_setup_table(p_table regclass) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('DROP TRIGGER IF EXISTS trg_touch ON %s', p_table);
  EXECUTE format('CREATE TRIGGER trg_touch BEFORE INSERT OR UPDATE ON %s
                  FOR EACH ROW EXECUTE FUNCTION fn_touch_trigger()', p_table);
  EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON %s', p_table);
  EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON %s
                  FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger()', p_table);
END;
$$;

SELECT fn_setup_table('app_user');

-- ---------------------------------------------------------------- Kelola user
CREATE OR REPLACE FUNCTION fn_user_save(
  p_actor text, p_email text, p_full_name text, p_role text, p_is_active boolean, p_is_new boolean
) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_actor text := lower(btrim(coalesce(p_actor, '')));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_name  text := btrim(coalesce(p_full_name, ''));
BEGIN
  PERFORM fn_assert_perm(v_actor, 'manage_users');
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'Format email tidak valid.';
  END IF;
  IF v_name = '' THEN
    RAISE EXCEPTION 'Nama wajib diisi.';
  END IF;
  IF p_role IS NULL OR p_role = '' THEN
    RAISE EXCEPTION 'Role wajib dipilih.';
  END IF;
  IF v_email = v_actor AND (p_role <> 'SYSTEM_ADMIN' OR NOT coalesce(p_is_active, true)) THEN
    RAISE EXCEPTION 'Anda tidak bisa mengubah role atau menonaktifkan akun sendiri.';
  END IF;

  IF p_is_new THEN
    IF EXISTS (SELECT 1 FROM app_user WHERE email = v_email) THEN
      RAISE EXCEPTION 'Email % sudah terdaftar.', v_email;
    END IF;
    INSERT INTO app_user (email, full_name, role, is_active, updated_by)
    VALUES (v_email, v_name, p_role, coalesce(p_is_active, true), v_actor);
  ELSE
    UPDATE app_user
       SET full_name = v_name, role = p_role, is_active = coalesce(p_is_active, true), updated_by = v_actor
     WHERE email = v_email;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'User % tidak ditemukan.', v_email;
    END IF;
  END IF;
  RETURN v_email;
END;
$$;
