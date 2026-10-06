-- ============================================================================
-- RESET — kosongkan semua data proyek untuk uji end-to-end (keputusan user 5 Okt 2026)
-- ⚠️ MENGHAPUS DATA PERMANEN. Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Satu transaksi: kalau ada error, tidak ada yang terhapus.
--
-- Yang DIHAPUS : semua data bisnis (supplier, komponen, material, supplier material, harga, model, season,
--                article + lampiran, revisi specsheet + BOM, change log, CBD + baris + biaya), semua sesi login,
--                semua akun selain SYSTEM_ADMIN, dan seluruh audit log.
-- Yang DISIMPAN: akun SYSTEM_ADMIN (gagal login & kunci di-reset), role_permission (matriks izin),
--                component_group (kode grup a/b/c/d), semua struktur tabel / view / function / trigger.
-- Tabel aplikasi lain di database ini TIDAK disentuh. TRUNCATE dipakai tanpa CASCADE: kalau ada tabel lain
-- yang terhubung ke tabel proyek, skrip gagal (tidak ada yang terhapus) — hentikan dan hubungi pengembang.
-- TRUNCATE juga melewati trigger kunci revisi terbit (yang menolak DELETE) dan trigger audit.
-- Setelah ini semua user (termasuk System Admin) harus login ulang.
-- ============================================================================

-- Pengaman: harus ada System Admin aktif yang sudah punya password, supaya masih bisa login.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM app_user
                  WHERE role = 'SYSTEM_ADMIN' AND is_active AND password_hash IS NOT NULL) THEN
    RAISE EXCEPTION 'Tidak ada akun SYSTEM_ADMIN aktif yang punya password. Reset dibatalkan (Anda tidak akan bisa login).';
  END IF;
END;
$$;

-- Akun selain System Admin dihapus lebih dulu (sesinya ikut terhapus lewat FK ON DELETE CASCADE),
-- lalu kunci System Admin dibuka. Jejak audit dari langkah ini ikut dikosongkan di TRUNCATE di bawah.
DELETE FROM app_user WHERE role <> 'SYSTEM_ADMIN';
UPDATE app_user SET failed_attempts = 0, locked_until = NULL WHERE role = 'SYSTEM_ADMIN';

TRUNCATE TABLE
  cbd_cost_item, cbd_line, cbd_revision,
  change_log_attachment, change_log,
  bom_cell, bom_line, revision_article, specsheet_revision,
  article_attachment, article, specsheet, product_model,
  material_price, material_supplier, material,
  component, supplier,
  app_session,
  audit_log
RESTART IDENTITY;
