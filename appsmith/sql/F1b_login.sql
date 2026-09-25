-- ============================================================================
-- F1b — Login di dalam app (email + password), sesi 12 jam, token per query
-- Jalankan SETELAH F1_fondasi.sql, lewat z_run_sql di app "DB Tools"
-- (Use prepared statements = OFF). Aman diulang.
-- Syarat: extension pgcrypto sudah terpasang (lihat langkah di chat / PLAN.md).
--
-- Mengganti dari F1: fn_assert_perm -> fn_auth, v_my_perms -> fn_me,
-- fn_user_save(email, ...) -> fn_user_save(token, ...).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- crypt(), gen_salt(), gen_random_bytes()

-- ---------------------------------------------------------------- Kolom & tabel
ALTER TABLE app_user
  ADD COLUMN IF NOT EXISTS password_hash        text,
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS failed_attempts      integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS locked_until         timestamptz,
  ADD COLUMN IF NOT EXISTS last_login_at        timestamptz;

-- Token disimpan sebagai hash SHA-256 (token asli hanya ada di browser user)
CREATE TABLE IF NOT EXISTS app_session (
  token_hash text PRIMARY KEY,
  email      text NOT NULL REFERENCES app_user(email) ON UPDATE CASCADE ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_session_email ON app_session (email);

-- ---------------------------------------------------------------- Bersihkan objek F1 yang diganti
DROP VIEW IF EXISTS v_my_perms;
DROP FUNCTION IF EXISTS fn_assert_perm(text, text);
DROP FUNCTION IF EXISTS fn_user_save(text, text, text, text, boolean, boolean);

-- ---------------------------------------------------------------- Audit
-- Password hash tidak pernah masuk audit; update pembukuan login tidak dicatat.
CREATE OR REPLACE FUNCTION fn_audit_trigger() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_old jsonb;
  v_new jsonb;
  v_row jsonb;
BEGIN
  IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD) - 'content' - 'password_hash'; END IF;
  IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW) - 'content' - 'password_hash'; END IF;
  IF TG_OP = 'UPDATE'
     AND (v_old - 'updated_at' - 'updated_by' - 'failed_attempts' - 'locked_until' - 'last_login_at')
       = (v_new - 'updated_at' - 'updated_by' - 'failed_attempts' - 'locked_until' - 'last_login_at') THEN
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

-- Catatan audit manual (login, logout, ganti/reset password)
CREATE OR REPLACE FUNCTION fn_audit(p_email text, p_entity text, p_entity_id text, p_action text)
RETURNS void
LANGUAGE sql AS $$
  INSERT INTO audit_log (user_email, entity, entity_id, action) VALUES (p_email, p_entity, p_entity_id, p_action);
$$;

-- ---------------------------------------------------------------- Helper
CREATE OR REPLACE FUNCTION fn_token_hash(p_token text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
$$;

-- Password sementara 10 karakter, tanpa huruf/angka yang mirip (i l o I O 0 1)
CREATE OR REPLACE FUNCTION fn_random_password() RETURNS text
LANGUAGE sql VOLATILE AS $$
  SELECT string_agg(substr('abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                           1 + get_byte(b, i) % 55, 1), '')
    FROM (SELECT gen_random_bytes(10) AS b) x, generate_series(0, 9) AS i
$$;

-- ---------------------------------------------------------------- Otorisasi
-- Dipakai di SETIAP query. Mengembalikan email user kalau token valid dan role-nya
-- punya izin p_permission (NULL/'' = cukup login). Kalau tidak: error.
-- Pesan diawali "SESI_HABIS" supaya Util di Appsmith mengarahkan ke page Login.
CREATE OR REPLACE FUNCTION fn_auth(p_token text, p_permission text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_email text;
  v_role  text;
  v_must  boolean;
BEGIN
  SELECT u.email, u.role, u.must_change_password INTO v_email, v_role, v_must
    FROM app_session s JOIN app_user u ON u.email = s.email
   WHERE s.token_hash = fn_token_hash(p_token) AND s.expires_at > now() AND u.is_active;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'SESI_HABIS: Sesi login habis atau tidak valid. Silakan login lagi.';
  END IF;
  IF coalesce(p_permission, '') <> '' THEN
    IF v_must THEN
      RAISE EXCEPTION 'Ganti password Anda dulu sebelum memakai aplikasi.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM role_permission WHERE role = v_role AND permission = p_permission) THEN
      RAISE EXCEPTION 'Role % tidak punya akses untuk aksi ini.', fn_role_label(v_role);
    END IF;
  END IF;
  PERFORM set_config('app.user', v_email, true);   -- dibaca trigger audit
  RETURN v_email;
END;
$$;

-- Profil + izin user dari token. 0 baris = belum login / sesi habis (tidak error).
CREATE OR REPLACE FUNCTION fn_me(p_token text)
RETURNS TABLE (email text, full_name text, role text, role_label text,
               must_change_password boolean, expires_at timestamptz, permissions text)
LANGUAGE sql STABLE AS $$
  SELECT u.email, u.full_name, u.role, fn_role_label(u.role), u.must_change_password, s.expires_at,
         coalesce((SELECT string_agg(rp.permission, ',' ORDER BY rp.permission)
                     FROM role_permission rp WHERE rp.role = u.role), '')
    FROM app_session s JOIN app_user u ON u.email = s.email
   WHERE s.token_hash = fn_token_hash(p_token) AND s.expires_at > now() AND u.is_active
$$;

-- ---------------------------------------------------------------- Login / logout
-- Tidak memakai RAISE untuk login gagal: RAISE membatalkan transaksi, sehingga
-- hitungan percobaan gagal & audit tidak tersimpan. Hasil: ok + pesan.
CREATE OR REPLACE FUNCTION fn_login(p_email text, p_password text)
RETURNS TABLE (ok boolean, message text, token text, must_change_password boolean)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_user  app_user%ROWTYPE;
  v_token text;
BEGIN
  SELECT * INTO v_user FROM app_user WHERE app_user.email = v_email;

  IF NOT FOUND OR NOT v_user.is_active OR v_user.password_hash IS NULL THEN
    PERFORM fn_audit(v_email, 'app_user', v_email, 'LOGIN_FAILED');
    RETURN QUERY SELECT false, 'Email atau password salah.'::text, NULL::text, NULL::boolean;
    RETURN;
  END IF;

  IF v_user.locked_until IS NOT NULL AND v_user.locked_until > now() THEN
    RETURN QUERY SELECT false,
      format('Akun terkunci karena 5 kali salah password. Coba lagi setelah pukul %s WIB, atau minta System Admin reset password.',
             to_char(v_user.locked_until AT TIME ZONE 'Asia/Jakarta', 'HH24:MI')),
      NULL::text, NULL::boolean;
    RETURN;
  END IF;

  IF v_user.password_hash <> crypt(coalesce(p_password, ''), v_user.password_hash) THEN
    UPDATE app_user
       SET failed_attempts = CASE WHEN failed_attempts + 1 >= 5 THEN 0 ELSE failed_attempts + 1 END,
           locked_until    = CASE WHEN failed_attempts + 1 >= 5 THEN now() + interval '15 minutes' END
     WHERE app_user.email = v_email;
    PERFORM fn_audit(v_email, 'app_user', v_email, 'LOGIN_FAILED');
    RETURN QUERY SELECT false, 'Email atau password salah.'::text, NULL::text, NULL::boolean;
    RETURN;
  END IF;

  v_token := encode(gen_random_bytes(32), 'hex');
  DELETE FROM app_session WHERE app_session.expires_at < now();
  INSERT INTO app_session (token_hash, email, expires_at)
  VALUES (fn_token_hash(v_token), v_email, now() + interval '12 hours');
  UPDATE app_user SET failed_attempts = 0, locked_until = NULL, last_login_at = now()
   WHERE app_user.email = v_email;
  PERFORM fn_audit(v_email, 'app_user', v_email, 'LOGIN');
  RETURN QUERY SELECT true, NULL::text, v_token, v_user.must_change_password;
END;
$$;

CREATE OR REPLACE FUNCTION fn_logout(p_token text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_email text;
BEGIN
  DELETE FROM app_session WHERE token_hash = fn_token_hash(p_token) RETURNING email INTO v_email;
  IF v_email IS NOT NULL THEN
    PERFORM fn_audit(v_email, 'app_user', v_email, 'LOGOUT');
  END IF;
END;
$$;

-- ---------------------------------------------------------------- Password
CREATE OR REPLACE FUNCTION fn_change_password(p_token text, p_old text, p_new text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_email text := fn_auth(p_token, NULL);
  v_hash  text;
BEGIN
  SELECT password_hash INTO v_hash FROM app_user WHERE email = v_email;
  IF v_hash IS NULL OR v_hash <> crypt(coalesce(p_old, ''), v_hash) THEN
    RAISE EXCEPTION 'Password lama salah.';
  END IF;
  IF length(coalesce(p_new, '')) < 8 THEN
    RAISE EXCEPTION 'Password baru minimal 8 karakter.';
  END IF;
  IF p_new = p_old THEN
    RAISE EXCEPTION 'Password baru harus berbeda dari password lama.';
  END IF;
  UPDATE app_user
     SET password_hash = crypt(p_new, gen_salt('bf', 10)), must_change_password = false, updated_by = v_email
   WHERE email = v_email;
  -- sesi lain (perangkat lain) ikut keluar
  DELETE FROM app_session WHERE email = v_email AND token_hash <> fn_token_hash(p_token);
  PERFORM fn_audit(v_email, 'app_user', v_email, 'PASSWORD_CHANGE');
END;
$$;

-- System Admin: buat password sementara untuk user lain (juga membuka kunci akun)
CREATE OR REPLACE FUNCTION fn_user_reset_password(p_token text, p_email text) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_actor text := fn_auth(p_token, 'manage_users');
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_pass  text := fn_random_password();
BEGIN
  IF v_email = v_actor THEN
    RAISE EXCEPTION 'Untuk akun sendiri gunakan menu Ganti Password.';
  END IF;
  UPDATE app_user
     SET password_hash = crypt(v_pass, gen_salt('bf', 10)), must_change_password = true,
         failed_attempts = 0, locked_until = NULL, updated_by = v_actor
   WHERE email = v_email;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % tidak ditemukan.', v_email;
  END IF;
  DELETE FROM app_session WHERE email = v_email;
  PERFORM fn_audit(v_actor, 'app_user', v_email, 'PASSWORD_RESET');
  RETURN v_pass;
END;
$$;

-- ---------------------------------------------------------------- Kelola user
-- Mengembalikan password sementara untuk user BARU (NULL saat ubah).
CREATE OR REPLACE FUNCTION fn_user_save(
  p_token text, p_email text, p_full_name text, p_role text, p_is_active boolean, p_is_new boolean
) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  v_actor text := fn_auth(p_token, 'manage_users');
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_name  text := btrim(coalesce(p_full_name, ''));
  v_pass  text;
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
  IF v_email = v_actor AND (p_role <> 'SYSTEM_ADMIN' OR NOT coalesce(p_is_active, true)) THEN
    RAISE EXCEPTION 'Anda tidak bisa mengubah role atau menonaktifkan akun sendiri.';
  END IF;

  IF p_is_new THEN
    IF EXISTS (SELECT 1 FROM app_user WHERE email = v_email) THEN
      RAISE EXCEPTION 'Email % sudah terdaftar.', v_email;
    END IF;
    v_pass := fn_random_password();
    INSERT INTO app_user (email, full_name, role, is_active, password_hash, must_change_password, updated_by)
    VALUES (v_email, v_name, p_role, coalesce(p_is_active, true), crypt(v_pass, gen_salt('bf', 10)), true, v_actor);
  ELSE
    UPDATE app_user
       SET full_name = v_name, role = p_role, is_active = coalesce(p_is_active, true), updated_by = v_actor
     WHERE email = v_email;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'User % tidak ditemukan.', v_email;
    END IF;
    IF NOT coalesce(p_is_active, true) THEN
      DELETE FROM app_session WHERE email = v_email;   -- user nonaktif langsung keluar
    END IF;
  END IF;
  RETURN v_pass;
END;
$$;
