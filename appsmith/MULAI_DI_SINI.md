# Mulai membangun di Appsmith — Hari 1

Target hari ini: **database siap + page Beranda yang tahu siapa yang login dan role-nya.**
Ini bagian dari milestone M1 "Fondasi siap" (timeline item 0.2, 0.3, 0.5).

File pendukung:

| File | Isi |
|---|---|
| `sql/001_schema.sql` | Semua tabel (migrasi dari SQLite), NUMERIC untuk uang, JSONB, BOOLEAN |
| `sql/002_fondasi.sql` | Seed grup komponen, matriks hak akses per role, `fn_assert_perm`, `fn_audit`, `v_my_perms` |
| `js/Auth.js`, `js/Util.js` | Isi JS Object yang disalin ke setiap page |

---

## Langkah 1 — Pastikan dengan IT (±15 menit)

Appsmith butuh **database PostgreSQL terpisah untuk data aplikasi**. Database bawaan Appsmith
(MongoDB/Postgres internal) hanya untuk menyimpan aplikasi, **bukan** tempat data kita.

Tanyakan ke IT:

- [ ] URL Appsmith dan akun Anda sudah bisa buat workspace/app?
- [ ] Edisi & versi Appsmith (Community/Business, v1.xx) — menentukan fitur yang bisa dipakai
- [ ] PostgreSQL untuk data aplikasi: **host, port, nama database, user, password** (versi ≥ 13)
- [ ] Host Postgres bisa dijangkau **dari server Appsmith** (bukan hanya dari laptop Anda)
- [ ] User Postgres punya hak `CREATE` di database tsb
- [ ] (Opsional) Repo Git untuk Git sync Appsmith

Kalau Postgres belum ada, langkah 3–6 tetap bisa dikerjakan di Appsmith; query `q_me` baru jalan setelah DB siap.

## Langkah 2 — Jalankan skrip SQL

Pakai DBeaver / pgAdmin kalau ada, jalankan berurutan:

1. `sql/001_schema.sql`
2. `sql/002_fondasi.sql`
3. Daftarkan diri Anda (email **harus sama** dengan email login Appsmith, huruf kecil):

```sql
INSERT INTO app_user (email, full_name, role)
VALUES ('email.anda@perusahaan.com', 'Nama Anda', 'MASTER_ADMIN');
```

Kalau tidak ada DBeaver/pgAdmin: buat datasource dulu (langkah 3), buat query sementara di Appsmith,
**matikan "Use prepared statements"** di tab Settings query itu, tempel isi file, Run, lalu hapus query sementara tsb.

Cek hasilnya:

```sql
SELECT * FROM v_my_perms;                                  -- 1 baris: Anda, dengan daftar izin
SELECT fn_assert_perm('email.anda@perusahaan.com', 'edit_cbd');  -- harus ERROR untuk MASTER_ADMIN
```

## Langkah 3 — Buat app & datasource

1. Workspace baru, mis. **Specsheet & CBD**. App baru: **Sistem Specsheet & CBD**.
2. Datasource → PostgreSQL → nama **`pg_main`** → isi host/port/db/user dari IT → *Test* → *Save*.
3. App settings → Navigation: **Sidebar**, tampilkan nama app.
4. Ganti nama page pertama menjadi **`Beranda`** (nama page harus persis sama dengan `progress/plan.toml`).

## Langkah 4 — Query & JS Object di page Beranda

**Query `q_me`** (datasource `pg_main`, *Run on page load* = OFF — dijalankan oleh `Auth`):

```sql
SELECT email, full_name, role, role_label, is_active, permissions
  FROM v_my_perms
 WHERE email = lower({{appsmith.user.email}});
```

**JS Object `Auth`** → tempel isi `js/Auth.js`. Biarkan `requiredPerm: ''` (khusus Beranda).
Di setelan fungsi `onPageLoad` → **Run on page load = ON**.

**JS Object `Util`** → tempel isi `js/Util.js`.

## Langkah 5 — Widget Beranda (sederhana dulu)

| Widget | Nama | Isi / properti |
|---|---|---|
| Text | `txtHalo` | `Halo, {{Auth.me ? Auth.me.full_name : appsmith.user.email}}` |
| Text | `txtRole` | `{{Auth.me ? Auth.me.role_label : ''}}` |
| Text | `txtBelumTerdaftar` | "Akun Anda belum terdaftar di aplikasi. Hubungi System Admin." · Visible: `{{!Auth.me}}` |
| Text | `txtIzin` (sementara, untuk uji) | `{{Auth.perms.join(', ')}}` |

Menu kartu ke page lain (Master, Model, Specsheet, CBD) ditambahkan setelah page-nya ada, dengan
Visible `{{Auth.can('view_master')}}`, `{{Auth.can('view_cbd')}}`, dst.

## Langkah 6 — Uji ganti role

Deploy/preview app, lalu di DB ganti role Anda dan refresh:

```sql
UPDATE app_user SET role = 'VENDOR_SPEC', updated_at = now() WHERE email = 'email.anda@perusahaan.com';
```

- [ ] `VENDOR_SPEC` → izin tidak berisi `view_cbd` / `view_price`
- [ ] `BRAND_VIEWER` → tidak ada `view_drafts`, tidak ada izin `edit_*`
- [ ] `SYSTEM_ADMIN` → hanya `view_audit`, `manage_users`
- [ ] Hapus sementara baris Anda dari `app_user` → muncul pesan "belum terdaftar"

Kembalikan ke `MASTER_ADMIN` setelah selesai.

## Langkah 7 — Catat progres

1. Appsmith → menu app → **Export** → simpan JSON ke `progress/exports/`.
2. Untuk skema DB: `pg_dump --schema-only` ke `progress/db/skema.sql`
   (atau sementara salin `sql/001_schema.sql` + `sql/002_fondasi.sql` jadi satu file di situ).
3. Jalankan `python progress/update_progress.py` → `PROGRESS.md` terisi.
4. Item yang sudah diuji di langkah 6 → tulis di `progress/status.toml` bagian `diuji`.

---

## Aturan yang dipakai mulai hari ini

- **Nama** page/query/JS/view/function persis seperti `progress/plan.toml` — tracker mencocokkan nama.
- **Query baca** `q_*` hanya `SELECT ... FROM v_*`. **Query aksi** `a_*` hanya `SELECT fn_*({{appsmith.user.email}}, ...)`.
  Tidak ada `INSERT/UPDATE/DELETE` langsung di Appsmith (tracker memberi peringatan kalau ada).
- **Hak akses ditegakkan di function DB** (`fn_assert_perm`), menyembunyikan tombol hanya untuk kenyamanan.
- Setiap page: salin `Auth` + `Util`, set `requiredPerm` sesuai page.

Catatan keamanan: email dikirim dari browser sebagai parameter query, jadi user yang paham teknis
secara teori bisa memalsukannya. Untuk aplikasi internal ini diterima; semua aksi tetap tercatat di
`audit_log`. Dibahas ulang saat setup produksi (C.3).

## Kalau waktu masih ada

- Kirim permintaan data ke vendor ERP (timeline A.1, sheet *Req Master Material* di
  `Timeline_Appsmith_12_Minggu.xlsx`) — ini jalur paling berisiko terlambat.
- Coba-coba **Custom Widget** Appsmith dengan tabel sederhana — persiapan spike Grid BOM (risiko #3).
