-- ============================================================================
-- 002_fondasi.sql — Seed dasar, hak akses per role, fn_assert_perm, fn_audit, v_my_perms
-- Jalankan setelah 001_schema.sql. Idempoten: aman diulang.
--
-- Pola untuk semua aksi tulis di Appsmith (dibangun mulai minggu 3):
--   query a_xxx  :  SELECT fn_xxx({{appsmith.user.email}}, ...param...);
--   function fn_xxx:
--       v_role := fn_assert_perm(p_email, 'manage_master');   -- tolak kalau role tidak berhak
--       ... validasi + INSERT/UPDATE ...
--       PERFORM fn_audit(p_email, v_role, 'material', v_id, 'CREATE', NULL, to_jsonb(new_row));
--   Satu function = satu transaksi, jadi validasi, perubahan data, dan audit log
--   selalu berhasil/gagal bersama.
-- ============================================================================

-- ---------------------------------------------------------------- Seed grup komponen
INSERT INTO component_group (code, name, range_start, range_end, sort_order) VALUES
    ('a', 'Upper',         0,    3990, 1),
    ('c', 'Bottom unit',   4000, 5990, 2),
    ('d', 'Packaging',     6000, 7990, 3),
    ('e', 'Miscellaneous', 8000, 9990, 4)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------- Matriks hak akses
-- Sumber: app/domain/permissions.py (mockup Flask). Ubah di sini, bukan di Appsmith.
INSERT INTO role_permission (role, permission) VALUES
    -- lihat menu
    ('MASTER_ADMIN', 'view_master'), ('VENDOR_SPEC', 'view_master'), ('VENDOR_CBD', 'view_master'), ('BRAND_VIEWER', 'view_master'),
    ('MASTER_ADMIN', 'view_model'),  ('VENDOR_SPEC', 'view_model'),  ('VENDOR_CBD', 'view_model'),  ('BRAND_VIEWER', 'view_model'),
    ('MASTER_ADMIN', 'view_specsheet'), ('VENDOR_SPEC', 'view_specsheet'), ('VENDOR_CBD', 'view_specsheet'), ('BRAND_VIEWER', 'view_specsheet'),
    ('MASTER_ADMIN', 'view_reports'),   ('VENDOR_SPEC', 'view_reports'),   ('VENDOR_CBD', 'view_reports'),   ('BRAND_VIEWER', 'view_reports'),
    -- CBD & harga: tim specsheet tidak melihat harga sama sekali
    ('MASTER_ADMIN', 'view_cbd'),   ('VENDOR_CBD', 'view_cbd'),   ('BRAND_VIEWER', 'view_cbd'),
    ('MASTER_ADMIN', 'view_price'), ('VENDOR_CBD', 'view_price'), ('BRAND_VIEWER', 'view_price'),
    -- brand hanya melihat revisi PUBLISHED
    ('MASTER_ADMIN', 'view_drafts'), ('VENDOR_SPEC', 'view_drafts'), ('VENDOR_CBD', 'view_drafts'),
    -- master data
    ('MASTER_ADMIN', 'manage_master'),
    ('VENDOR_SPEC', 'propose_master'), ('VENDOR_CBD', 'propose_master'),
    ('MASTER_ADMIN', 'manage_material_supplier'), ('VENDOR_SPEC', 'manage_material_supplier'),
    ('MASTER_ADMIN', 'approve_material_supplier'),
    ('MASTER_ADMIN', 'manage_price'), ('VENDOR_CBD', 'manage_price'),
    -- model, specsheet, CBD
    ('MASTER_ADMIN', 'edit_model'), ('VENDOR_SPEC', 'edit_model'),
    ('VENDOR_SPEC', 'edit_specsheet'),
    ('VENDOR_CBD', 'edit_cbd'),
    -- admin teknis: tidak melihat data bisnis
    ('SYSTEM_ADMIN', 'view_audit'),
    ('SYSTEM_ADMIN', 'manage_users')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------- Label role
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

-- ---------------------------------------------------------------- Cek hak akses
-- Dipanggil di awal setiap fn_* yang mengubah data. Mengembalikan role pengguna;
-- menolak (RAISE) kalau email tidak terdaftar, nonaktif, atau role-nya tidak punya izin.
-- Pesan error tampil apa adanya di Appsmith (query.responseMeta / showAlert).
CREATE OR REPLACE FUNCTION fn_assert_perm(p_email text, p_permission text) RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_role text;
BEGIN
    SELECT role INTO v_role
      FROM app_user
     WHERE email = lower(btrim(p_email)) AND is_active;

    IF v_role IS NULL THEN
        RAISE EXCEPTION 'Akun % belum terdaftar atau nonaktif. Hubungi System Admin.', p_email
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM role_permission WHERE role = v_role AND permission = p_permission) THEN
        RAISE EXCEPTION 'Role % tidak punya akses untuk aksi ini (%).', fn_role_label(v_role), p_permission
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    RETURN v_role;
END;
$$;

-- ---------------------------------------------------------------- Audit log
CREATE OR REPLACE FUNCTION fn_audit(
    p_email     text,
    p_role      text,
    p_entity    text,
    p_entity_id text,
    p_action    text,
    p_before    jsonb,
    p_after     jsonb
) RETURNS void
LANGUAGE sql AS $$
    INSERT INTO audit_log (user_email, user_role, entity, entity_id, action, before_json, after_json)
    VALUES (lower(btrim(p_email)), p_role, p_entity, p_entity_id, p_action, p_before, p_after);
$$;

-- ---------------------------------------------------------------- Profil & izin user login
-- Satu baris per user. permissions = daftar izin dipisah koma (dipecah di JS Auth.load),
-- supaya tidak bergantung pada cara driver Appsmith mengembalikan tipe array.
CREATE OR REPLACE VIEW v_my_perms AS
SELECT u.email,
       u.full_name,
       u.role,
       fn_role_label(u.role) AS role_label,
       u.is_active,
       coalesce(string_agg(rp.permission, ',' ORDER BY rp.permission), '') AS permissions
  FROM app_user u
  LEFT JOIN role_permission rp ON rp.role = u.role
 GROUP BY u.email, u.full_name, u.role, u.is_active;

-- ---------------------------------------------------------------- User awal (ubah email!)
-- Daftarkan email akun Appsmith Anda. Untuk menguji role lain di server dev, cukup:
--   UPDATE app_user SET role = 'VENDOR_CBD', updated_at = now() WHERE email = '...';
-- INSERT INTO app_user (email, full_name, role) VALUES
--     ('nama@perusahaan.com', 'Nama Anda', 'MASTER_ADMIN')
-- ON CONFLICT (email) DO NOTHING;
