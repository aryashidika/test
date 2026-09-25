# PLAN — Migrasi Sistem Specsheet & CBD ke Appsmith

| | |
|---|---|
| Sumber (hanya dibaca) | `app/` (Flask + htmx + SQLite), `run_web.py`, `tests/` |
| Folder kerja | `appsmith/` — file ini + `exports/export_vN.json` |
| Target | Appsmith **v2.4** self-hosted (HTTPS) + PostgreSQL **16.15** (datasource `pg_main`) |
| Akses | App **publik** dengan login di dalam app (email + password), bukan akun Appsmith |
| Data lama | Tidak dimigrasi (mulai dari DB kosong) |
| Status | Rencana disetujui 24 Sep 2026 (termasuk P1–P3) · login in-app disetujui 25 Sep 2026 · UI campuran + Custom Widget disetujui 25 Sep 2026 · sedang: **F1** |
| File siap tempel | `sql/F<n>_*.sql` (jalankan lewat `z_run_sql` di app privat **DB Tools**), `js/*.js` (isi JSObject), `widgets/<cw>/` (Custom Widget: HTML/CSS/JS + README kontrak) |

Legenda status: ⬜ belum · 🟡 dibuat (belum diverifikasi dari export) · ✅ terverifikasi

---

## 1. Ringkasan status

| Fase | Isi | Export | Status |
|---|---|---|---|
| F0 | Persiapan: cek versi, app, cara menjalankan SQL | – | 🟡 sisa: page `Login`, app DB Tools, pgcrypto |
| F1 | Fondasi DB, login in-app & role, Admin user + audit | `export_v1.json` | 🟡 SQL F1 jalan; F1b + UI diberikan |
| F2 | Master Supplier & Komponen | `export_v2.json` | ⬜ |
| F3 | Master Material, supplier material, harga | `export_v3.json` | ⬜ |
| F4 | Model, Season, Article, lampiran article | `export_v4.json` | ⬜ |
| F5 | Specsheet: revisi & grid BOM | `export_v5.json` | ⬜ |
| F6 | Specsheet: checklist & terbit | `export_v6.json` | ⬜ |
| F7 | CBD: buat revisi & grid baris | `export_v7.json` | ⬜ |
| F8 | CBD: harga, rekap, refresh, terbit, sinkron specsheet | `export_v8.json` | ⬜ |
| F9 | Export Excel specsheet & CBD | `export_v9.json` | ⬜ |
| F10 | Beranda "Tugas Saya" | `export_v10.json` | ⬜ |
| F11 | Dokumentasi & handover (`appsmith/README.md`) | – | ⬜ |
| Opsional | Where-used, histori harga, diff revisi, harga referensi brand | – | ⬜ |

---

## 2. Keputusan arsitektur

1. **Logika sederhana → SQL langsung di Appsmith.** CRUD master, model, article, edit sel/nilai: query `INSERT/UPDATE` biasa. Aturan data dijaga oleh constraint & trigger di Postgres (tidak bergantung UI).
2. **Logika banyak-langkah → function Postgres `fn_*`** (satu function = satu transaksi): buat/hapus revisi, tambah/ganti baris BOM, terbit, buat/refresh CBD, harga baru. Appsmith memanggil `SELECT fn_x(...)`.
3. **Audit otomatis lewat trigger** `trg_audit` (+ `trg_touch` untuk `created_*`/`updated_*`) di semua tabel bisnis, dipasang dengan `SELECT fn_setup_table('<tabel>')`. Setiap query tulis mengisi `updated_by = fn_auth(token, izin)`; trigger mencatat before/after ke `audit_log` (password tidak pernah dicatat). Tidak ada kode audit di Appsmith.
4. **Kunci revisi terbit lewat trigger** `trg_lock_published`: baris BOM/sel/article revisi & baris CBD tidak bisa diubah kalau revisinya PUBLISHED. UPDATE langsung dari Appsmith jadi aman.
5. **Login & hak akses di database.** App dipublikasikan, jadi siapa pun bisa memanggil query-nya langsung — semua pengecekan ada di Postgres:
   - Login email + password (bcrypt via `pgcrypto`), token acak disimpan di browser (`appsmith.store.token`), di DB hanya hash-nya (`app_session`). Sesi 12 jam. Terkunci 15 menit setelah 5 kali salah.
   - Password min. 8 karakter; wajib ganti saat login pertama & setelah reset; reset hanya oleh System Admin (password sementara). Satu akun = satu role.
   - **Setiap query** (baca & tulis) memanggil `fn_auth(token, izin)`; token tidak valid → error `SESI_HABIS` → Util mengarahkan ke page `Login`.
   - UI tetap menyembunyikan menu/tombol dengan `Auth.can()` (kenyamanan saja).
   - `z_run_sql` (prepared statements OFF) hanya ada di app terpisah yang **privat**: **DB Tools**.
6. **Uang/angka = `numeric`** dan dihitung di Postgres (view). JS hanya memformat tampilan.
7. **Tanggal "hari ini" = WIB** lewat `fn_today()` = `(now() AT TIME ZONE 'Asia/Jakarta')::date`.
8. **Tanpa penguncian multi-user** — yang terakhir menyimpan yang berlaku.
9. **ID = `uuid`** (`gen_random_uuid()`, butuh PostgreSQL ≥ 13).
10. **UI campuran (standar untuk handover):**
    - **Widget bawaan** Appsmith untuk halaman CRUD standar: Beranda, Admin, Master (Supplier, Komponen, Material), Model — bisa dirawat lewat panel properti tanpa coding.
    - **Custom Widget** hanya untuk bagian yang tidak bisa dibuat baik dengan widget bawaan: `cwLogin` (Login), `cwStepper` (stage + chip article, dipakai Specsheet & CBD), `cwBomGrid` (grid BOM, maks. 5 article per season), `cwCbdGrid` (grid CBD + rekap).
    - Aturan Custom Widget: **hanya tampilan** (tanpa logika bisnis/query); data masuk lewat *Default model*, aksi keluar lewat `appsmith.updateModel()` + `appsmith.triggerEvent()` yang ditangani `<Page>Ctrl`; JavaScript biasa tanpa framework (library CDN jsDelivr dengan versi terkunci hanya bila perlu); warna/radius/font mengikuti tema app (`appsmith.theme`).
    - Setiap Custom Widget punya folder `appsmith/widgets/<cw>/` berisi `index.html`, `style.css`, `script.js`, dan `README.md` (kontrak model, nilai keluar, event).
11. **Export Excel**: library ExcelJS dipasang di Appsmith (Libraries). Cadangan: SheetJS tanpa style.
12. **Lampiran article**: FilePicker (Base64) → disimpan `bytea` di tabel `article_attachment`. Jenis jpg/png/pdf, maks 5 MB per file.
13. **Desain**: palet mockup Flask — primary navy `#122A52`, aksen `#3B6FE0`, latar `#F3F5FA`, radius 8px, font sistem (Segoe UI); chip status hijau/kuning/merah/abu. Hanya untuk laptop/PC (lebar ≥ 1280px).

### Penyederhanaan dari sistem Python

| Di Python | Di Appsmith |
|---|---|
| Login pilih role bebas | Login email + password di dalam app; role dari tabel `app_user` |
| 4 cara buat revisi specsheet (kosong, carryover, lintas model, stage sama/berikut) | Satu function `fn_revision_create(mode)`; "carryover" & "lintas model" digabung jadi **Copy dari specsheet lain** |
| 5 cara buat CBD | Satu function `fn_cbd_create(article, source)`. Stage CBD **selalu mengikuti stage specsheet terbit terakhir**; nomor revisi = terakhir di stage itu + 1 |
| `is_used` sel BOM dihitung di Python | Kolom generated di DB |
| Usage = 1/Yield dihitung di Python | Kolom generated di DB |
| Diff BOM/CBD saat terbit (JSON) | MVP: change log kategori + alasan saja; diff masuk fase Opsional (kolom `diff` sudah disiapkan) |
| Menu Specsheet & CBD dengan daftar sendiri | Satu `Model_List`; dari sana buka Model / Specsheet / CBD |
| Persetujuan di halaman terpisah | Filter "PROPOSED" + tombol Approve di tiap halaman master; ringkasan di Beranda admin |
| Merge material, import CSV, reset data, halaman cetak, laporan validasi CBD, harga referensi brand | Tidak dibawa (cetak diganti Excel; harga referensi di Opsional) |
| Foto per specsheet (belum ada UI) | Lampiran per **article** |

### Perbaikan inkonsistensi Python (disetujui: diperbaiki)

| # | Di Python | Di Appsmith |
|---|---|---|
| P1 | Copy lintas model memilih revisi sumber "terakhir" hanya dari nomor revisi (PULL r2 dianggap lebih baru dari PROD r0) | Urut stage dulu, lalu nomor revisi |
| P2 | Ringkasan status di daftar model memakai revisi yang **dibuat** terakhir | Pakai urutan stage + nomor revisi, sama seperti bagian lain |
| P3 | Form tambah material tidak punya pilihan metode harga (selalu CATALOG) | Ada pilihan CATALOG / QUOTATION |

---

## 3. Mapping Python → Appsmith

| Python | Page | Query / JSObject | DB |
|---|---|---|---|
| `web/auth.py`, `permissions.py`, `user_session.py`, `main.py` (masuk/keluar) | `Login` + semua page | `q_me`, `a_login`, `a_logout`, `a_change_password` · `Auth`, `Util`, `LoginCtrl` | `app_user`, `app_session`, `role_permission`, `fn_login`, `fn_me`, `fn_auth` |
| `admin.py` (audit log) + user (baru) | `Admin` | `q_users`, `a_user_save`, `a_user_reset_password`, `q_audit` · `AdminCtrl` | `app_user`, `audit_log`, `fn_user_save`, `fn_user_reset_password` |
| `audit.py` | – | – | `trg_audit` |
| `normalize.py`, `ids.py` | – | – | `fn_normalize`, `gen_random_uuid()` |
| `supplier_service.py` | `Master_Supplier` | `q_suppliers`, `a_supplier_insert/update/set_status` · `SupplierCtrl` | `supplier` |
| `component_service.py` | `Master_Komponen` | `q_components`, `q_component_groups`, `q_next_component_no`, `a_component_*` · `KomponenCtrl` | `component_group`, `component`, `trg_component_check` |
| `material_service.py` | `Master_Material`, `Material_Detail` | `q_materials`, `q_next_material_code`, `a_material_*` · `MaterialCtrl` | `material`, `v_material_list` |
| `material_price_service.py` | `Material_Detail` | `q_material_suppliers`, `q_material_prices`, `a_link_*`, `a_price_add`, `a_price_end` · `MaterialCtrl` | `material_supplier`, `material_price`, `fn_price_add`, `fn_price_lookup`, `fn_ensure_link` |
| `model_service.py`, `specsheet_service.py` (season) | `Model_List`, `Model_Detail` | `q_models`, `q_model`, `q_seasons`, `a_model_*`, `a_season_insert` · `ModelCtrl` | `product_model`, `specsheet`, `v_model_list` |
| `article_service.py` (Model) + lampiran (baru) | `Model_Detail` | `q_articles`, `a_article_*`, `q_attachments`, `q_attachment_file`, `a_attachment_*` · `ModelCtrl` | `article`, `article_attachment`, `v_article_status` |
| `revision_service.py` | `Specsheet` | `q_revisions`, `a_revision_create`, `a_revision_delete`, `a_revision_publish`, `q_publish_checklist` · `SpecCtrl` | `specsheet_revision`, `revision_article`, `change_log`, `fn_revision_*`, `v_revision_checklist` |
| `bom_service.py`, `article_service.py` (revisi) | `Specsheet` | `q_bom_grid`, `q_rev_articles`, `a_bom_add_line`, `a_bom_add_sub`, `a_bom_replace_material`, `a_bom_update`, `a_cell_save`, `a_rev_article_*` · `BomCtrl` | `bom_line`, `bom_cell`, `fn_bom_*`, `v_bom_grid` |
| `cbd_service.py`, `cbd_calc.py` | `CBD` | `q_cbd_articles`, `q_cbd_revisions`, `q_cbd_lines`, `q_cbd_recap`, `a_cbd_create`, `a_cbd_line_update`, `a_cbd_header_update`, `a_cbd_set_margin`, `a_cbd_price_*`, `a_cbd_refresh*`, `a_cbd_publish`, `a_cbd_delete` · `CbdCtrl` | `cbd_revision`, `cbd_line`, `fn_cbd_*`, `v_cbd_line`, `v_cbd_recap`, `v_cbd_checklist` |
| `export_service.py` | `Specsheet`, `CBD` | `ExportCtrl` (ExcelJS) | pakai view yang sama |
| `worklist_service.py` | `Beranda` | `q_worklist_*` · `BerandaCtrl` | `v_worklist_*` |
| `report_service.py`, `diff_service.py`, `cbd_diff_service.py` | Opsional | – | – |
| `merge_service.py`, `csv_import.py`, `reset_service.py`, `seed_*.py`, `photo_service.py` | tidak dibawa | – | – |

---

## 4. Konvensi penamaan

| Objek | Pola | Contoh |
|---|---|---|
| Page | `Kata_Kata` | `Login`, `Master_Material`, `Material_Detail`, `CBD` |
| Query baca | `q_<benda>` | `q_materials`, `q_bom_grid` |
| Query tulis | `a_<benda>_<aksi>` | `a_material_insert`, `a_cbd_publish` |
| JSObject | `Auth` (setiap page kecuali Login), `Util` (setiap page), `<Nama>Ctrl` per page | `LoginCtrl`, `MaterialCtrl`, `BomCtrl` |
| Fungsi JSObject | kata kerja camelCase | `save()`, `openAdd()`, `publish()` |
| Widget | prefiks jenis + NamaPascal | lihat tabel di bawah |
| Tabel DB | snake_case tunggal | `material_price` |
| View / function / trigger | `v_*` / `fn_*` / `trg_*` | `v_cbd_line`, `fn_cbd_create` |

Prefiks widget: `tbl` Table · `inp` Input · `sel` Select · `ms` MultiSelect · `btn` Button · `mdl` Modal · `txt` Text · `tab` Tabs · `fp` FilePicker · `dp` DatePicker · `chk` Checkbox · `sw` Switch · `img` Image · `cnt` Container · `lst` List · **`cw` Custom Widget**.

Custom Widget: nama `cw<Nama>` sama dengan nama folder di `appsmith/widgets/`; event diberi nama `on<Aksi>` (mis. `onLogin`, `onSaveCell`); nilai keluar dibaca JSObject dari `cw<Nama>.model.<field>` **sebelum** state JSObject diubah (model di-reset saat Default model berubah).

Aturan query:
- Semua parameter pakai `{{this.params.x}}`, dipanggil dari JSObject (`a_x.run({ x: ... })`), kecuali query baca sederhana yang langsung membaca widget.
- Selalu cast tipe: `{{this.params.id}}::uuid`, `{{...}}::numeric`, `{{...}}::date`.
- **Token di setiap query** (lihat pola di bawah). Jangan memakai `appsmith.user.email`.
- *Use prepared statements* = ON di semua query app. OFF hanya untuk `z_run_sql` di app **DB Tools**.
- *Run on page load* = OFF untuk semua query; query baca page didaftarkan di `Auth.pageQueries()` supaya baru jalan setelah login valid.

Pola query:

| Jenis | Pola |
|---|---|
| Baca | `SELECT … FROM x WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_…')) IS NOT NULL` |
| Tambah | `INSERT INTO x (kolom…, updated_by) SELECT {{…}}, fn_auth({{appsmith.store.token}}, 'manage_…')` |
| Ubah | `UPDATE x SET …, updated_by = fn_auth({{appsmith.store.token}}, 'manage_…') WHERE id = {{…}}::uuid` |
| Function | `SELECT fn_x({{appsmith.store.token}}, …)` — function memanggil `fn_auth` sendiri |

---

## 5. Matriks hak akses

| Izin | MASTER_ADMIN | VENDOR_SPEC | VENDOR_CBD | BRAND_VIEWER | SYSTEM_ADMIN |
|---|:-:|:-:|:-:|:-:|:-:|
| `view_master`, `view_model`, `view_specsheet` | ✓ | ✓ | ✓ | ✓ | |
| `view_cbd`, `view_price` | ✓ | | ✓ | ✓ | |
| `view_drafts` (lihat DRAFT) | ✓ | ✓ | ✓ | | |
| `manage_master` (CRUD + approve) | ✓ | | | | |
| `propose_master` (usul material/komponen, status PROPOSED) | | ✓ | ✓ | | |
| `manage_material_supplier` | ✓ | ✓ | | | |
| `manage_price` (harga & metode harga) | ✓ | | ✓ | | |
| `edit_model` (model, season, article, lampiran) | ✓ | ✓ | | | |
| `edit_specsheet` | | ✓ | | | |
| `edit_cbd` | | | ✓ | | |
| `manage_users`, `view_audit` | | | | | ✓ |

---

## 6. Fase implementasi

Setiap fase: saya beri langkah konkret → Anda kerjakan di Appsmith → export ke `appsmith/exports/export_vN.json` → saya review → checklist di sini diperbarui.
Tabel DB baru di tiap fase ditulis di bagian **7. Perubahan database** dan dicatat di **8. Register objek DB**.

### F0 — Persiapan
- [x] Cek versi Appsmith → **v2.4** (self-hosted); Custom Widget **tersedia**
- [x] Cek versi PostgreSQL → **16.15**
- [ ] Buat app **Sistem Specsheet & CBD**, navigasi: Sidebar
- [ ] Tema app: primary `#122A52`, background `#F3F5FA`, radius M, font *System Default*
- [ ] Buat page kosong: `Login` (home page), `Beranda`, `Admin`, `Master_Supplier`, `Master_Komponen`, `Master_Material`, `Material_Detail`, `Model_List`, `Model_Detail`, `Specsheet`, `CBD`
- [ ] Buat app privat **DB Tools** berisi `z_run_sql` (prepared statements OFF); hapus `z_run_sql` dari app utama
- [ ] Pasang extension `pgcrypto`
- [x] Uji pasang library ExcelJS (Libraries → +) → **berhasil**

**Selesai bila:** versi Appsmith & Postgres diketahui, 11 page ada, library terpasang, `pgcrypto` aktif, `z_run_sql` hanya ada di DB Tools.

### F1 — Fondasi, login in-app & role
- [x] Jalankan SQL F1 (`sql/F1_fondasi.sql`: fungsi dasar, `app_user`, `role_permission`, `audit_log`, trigger audit)
- [ ] Jalankan SQL F1b (`sql/F1b_login.sql`: kolom password, `app_session`, `fn_auth`, `fn_me`, `fn_login`, `fn_logout`, `fn_change_password`, `fn_user_save`, `fn_user_reset_password`)
- [ ] Set password awal akun System Admin Anda lewat `z_run_sql`
- [ ] Page `Login` (home page): Custom Widget **`cwLogin`** (masuk + ganti password), logout lewat `?mode=keluar` — `Util`, `LoginCtrl`
- [ ] `q_me`, `Auth` (cek sesi + izin + `pageQueries`), `Util` — disalin ke setiap page lain
- [ ] Beranda: sapaan, role, tombol menu sesuai izin, **Ganti Password**, **Keluar**
- [ ] Page `Admin`: tab **User** (tambah → password sementara, ubah role/nonaktif, reset password) dan **Audit Log**
- [ ] Navigasi: sembunyikan `Login`, `Material_Detail`, `Model_Detail` dari sidebar; Share → **Make application public** → Deploy

**Selesai bila:** buka URL app tanpa login → halaman Login; login benar masuk Beranda sesuai role; password sementara wajib diganti; 5 kali salah → terkunci 15 menit; logout/sesi habis → kembali ke Login; query tanpa token ditolak DB; login/logout/ganti password tercatat di Audit Log.

### F2 — Master Supplier & Komponen
- [ ] SQL F2 (`supplier`, `component_group` + seed a/c/d/e, `component`, `trg_component_check`)
- [ ] `Master_Supplier`: tabel + cari + filter status, tambah (modal), ubah nama, currency default, status
- [ ] `Master_Komponen`: tabel per grup, saran nomor berikutnya (max+10), tambah, ubah, status; vendor → otomatis PROPOSED; admin → Approve

**Selesai bila:** nomor bukan kelipatan 10 / di luar rentang / sudah dipakai ditolak dengan pesan jelas; nama supplier beda kapital ditolak; semua perubahan masuk audit log.

### F3 — Master Material, supplier material, harga
- [ ] SQL F3 (`material`, `material_supplier`, `material_price`, `fn_today`, `fn_price_add`, `fn_price_end`, `fn_price_lookup`, `fn_ensure_link`, `v_material_list`)
- [ ] `Master_Material`: tabel (kode, nama, kategori, thickness, UoM, metode harga, status, ringkasan supplier/harga), cari & filter (status, kategori, "belum ada harga"), tambah dengan saran `MTR-NNNN` dan pilihan metode harga (P3)
- [ ] `Material_Detail` tab **Info**: edit identitas (admin), status, metode harga (`manage_price`)
- [ ] Tab **Supplier & Harga**: daftar supplier material (kode di supplier, utama, status, approve), tambah supplier; per supplier harga berlaku + riwayat, tambah harga (warna opsional, tanggal berlaku), akhiri harga. Harga disembunyikan untuk VENDOR_SPEC

**Selesai bila:** duplikat material (nama+thickness+UoM setelah normalisasi) ditolak; harga baru menutup harga lama; tanggal mundur ditolak; material QUOTATION tidak bisa diberi harga; `fn_price_lookup` mengembalikan harga warna dulu lalu semua warna.

### F4 — Model, Season, Article, lampiran
- [ ] SQL F4 (`product_model`, `specsheet`, `article`, `article_attachment`, `trg_article_limit`, `v_model_list`, `v_article_status`)
- [ ] `Model_List`: tabel model + filter season + cari; ringkasan specsheet terakhir (P2); tombol Buka Model / Specsheet / CBD (CBD hanya bila `view_cbd`); tambah model (modal)
- [ ] `Model_Detail` tab **Info**: edit data model
- [ ] Tab **Season & Article**: pilih/tambah season (format SS26/FH26), tabel article (kode, colorway, status specsheet & CBD), tambah/ubah/hapus article (hapus hanya bila belum dipakai), copy article dari season lain
- [ ] Lampiran per article: upload (jpg/png/pdf, ≤ 5 MB), lihat gambar, unduh, hapus

**Selesai bila:** article ke-6 di satu season ditolak; kode article yang sudah dipakai tidak bisa diubah; lampiran bisa diunggah, dilihat, dan diunduh.

### F5 — Specsheet: revisi & grid BOM
- [ ] SQL F5 (`specsheet_revision`, `revision_article`, `bom_line`, `bom_cell`, `trg_lock_published`, `fn_revision_create`, `fn_revision_delete_draft`, `fn_bom_add_line`, `fn_bom_add_sub`, `fn_bom_replace_material`, `fn_bom_set_supplier`, `fn_rev_article_set`, `v_bom_grid`)
- [ ] Custom Widget **`cwStepper`**: stepper stage PULL→SMS→GTM→PROD berisi revisi (brand: hanya PUBLISHED)
- [ ] Page `Specsheet` (`?model_id=`): pilih season (widget bawaan) + `cwStepper`
- [ ] Wizard **Buat Revisi**: Kosong (pilih stage) / Copy dari specsheet lain (P1) / Revisi berikutnya / Stage berikutnya; hapus draft
- [ ] Custom Widget **`cwBomGrid`**: No, Komponen, Material, Supplier, UoM, Remarks + satu kolom per article (edit warna langsung di sel, saran warna se-season); tambah baris (komponen master atau lokal), tambah subkomponen, ganti material, ubah supplier/remarks
- [ ] Article di revisi: pilih article season, drop/aktifkan

**Selesai bila:** hanya satu draft per specsheet; revisi terbit tidak bisa diedit (ditolak DB); ganti material menonaktifkan baris lama; supplier baru di BOM membuat link PROPOSED; link INACTIVE ditolak.

### F6 — Specsheet: checklist & terbit
- [ ] SQL F6 (`change_log`, `v_revision_checklist`, `fn_revision_publish`)
- [ ] Modal **Terbitkan**: checklist (article aktif ≥ 1, tiap article aktif dipakai, tidak ada material INACTIVE [blok]; baris tanpa supplier [peringatan]), kategori + alasan (wajib selain revisi awal)
- [ ] Tab **Riwayat**: change log revisi

**Selesai bila:** terbit ditolak bila checklist gagal; setelah terbit revisi terkunci dan muncul di Riwayat.

### F7 — CBD: buat revisi & grid baris
- [ ] SQL F7 (`cbd_revision`, `cbd_line`, `fn_cbd_expected_lines`, `fn_cbd_create`, `fn_cbd_delete_draft`, `v_cbd_line`, `v_cbd_article`)
- [ ] Page `CBD` (`?model_id=`): pilih season, `cwStepper` (chip article + status: belum ada CBD / draft / terbit / perlu revisi / di-drop, dan stepper revisi)
- [ ] **Buat CBD**: baru / lanjut dari CBD terbit article ini / copy dari article lain (model sama)
- [ ] Custom Widget **`cwCbdGrid`**: grid per grup a/c/d/e + bagian MISSING_IN_SPEC; edit Yield & Loss % di sel; Usage, harga IDR/USD, cost/pair dari view

**Selesai bila:** baris CBD = baris BOM terbit yang dipakai article (termasuk subkomponen); yield/loss tersalin dari sumber (lineKey → originLineKey → identitas); baris sumber yang hilang jadi MISSING_IN_SPEC.

### F8 — CBD: harga, rekap, refresh, terbit, sinkron
- [ ] SQL F8 (`fn_cbd_set_quotation`, `fn_cbd_override_price`, `fn_cbd_clear_override`, `fn_cbd_refresh_prices`, `fn_cbd_refresh_from_spec`, `fn_cbd_set_margin`, `v_cbd_recap`, `v_cbd_checklist`, `fn_cbd_publish`, perbarui `fn_revision_publish` dengan penandaan sinkron)
- [ ] Harga: quotation (material QUOTATION), override + alasan (material CATALOG), hapus override; info kenapa harga kosong
- [ ] Rekap di `cwCbdGrid` (panel ringkasan menempel): exchange rate, amortisasi, adjustment, target FOB, actual FOB, selisih (OVER/UNDER/SESUAI), selling price ⇄ margin %
- [ ] Banner + tombol **Refresh dari Specsheet** / **Refresh Harga dari Master**
- [ ] Modal **Terbitkan** CBD + tab Riwayat
- [ ] Terbit specsheet → CBD terbit article terkait jadi NEEDS_REVISION bila baris/supplier/warna berubah

**Selesai bila:** angka rekap sama dengan rumus Python (cek 1 contoh manual); terbit ditolak bila specsheet usang / rate kosong / harga master berubah / baris berharga tanpa yield.

### F9 — Export Excel
- [ ] Library ExcelJS terpasang
- [ ] `ExportCtrl.specsheet()` — header model/season/stage, tabel BOM × article, blok tanda tangan
- [ ] `ExportCtrl.cbd()` — per grup, MISSING_IN_SPEC, rekap biaya & margin, change log
- [ ] Tombol Export di `Specsheet` & `CBD` (brand hanya revisi terbit)

**Selesai bila:** file `.xlsx` terunduh, isinya sama dengan layar.

### F10 — Beranda "Tugas Saya"
- [ ] SQL F10 (`v_worklist_spec`, `v_worklist_cbd`, `v_worklist_admin`, `v_recent_published`)
- [ ] Per role: Vendor Spec (draft berjalan, article belum masuk revisi) · Vendor CBD (belum ada CBD, perlu refresh, perlu revisi, harga master kosong) · Master Admin (antrian PROPOSED) · Brand (terbit terbaru) · System Admin (ringkasan)

**Selesai bila:** setiap role melihat daftar yang benar, klik membuka page tujuan.

### F11 — Dokumentasi & handover
- [ ] `appsmith/README.md` (panduan operasional): arsitektur (diagram DB ↔ query ↔ JSObject ↔ widget), daftar page & hak akses, cara menambah user / reset password, cara menjalankan SQL di DB Tools, cara export & deploy, cara mengubah matriks hak akses, cara mengubah Custom Widget, troubleshooting (sesi habis, akun terkunci, error constraint)
- [ ] Semua `widgets/<cw>/README.md` sesuai kondisi akhir
- [ ] `PLAN.md` final: semua checklist & register terverifikasi, log review lengkap
- [ ] Skrip SQL gabungan untuk instalasi baru (`sql/install_all.sql` = F1 … F10 berurutan)

**Selesai bila:** orang baru bisa memasang ulang sistem dari DB kosong dan menjalankan tugas admin rutin hanya dengan membaca `README.md`.

### Opsional (setelah F10, bila diminta)
- [ ] Tab Material: **Dipakai di** (where-used) & **Histori Harga**
- [ ] Diff BOM/CBD saat terbit (isi kolom `change_log.diff`)
- [ ] Harga referensi untuk Brand di specsheet terbit

---

## 7. Perubahan database (DDL tabel per fase)

Function, view, dan trigger yang disebut di checklist fase diberikan lengkap saat fase itu dikerjakan. Kolom standar di setiap tabel bisnis:

```sql
created_at timestamptz NOT NULL DEFAULT now(),
created_by text,
updated_at timestamptz NOT NULL DEFAULT now(),
updated_by text
```

### F1
```sql
-- Kunci pencocokan: huruf kecil, koma → titik, spasi dirapatkan, trim (= app/normalize.py)
CREATE OR REPLACE FUNCTION fn_normalize(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT btrim(regexp_replace(replace(lower(coalesce(p, '')), ',', '.'), '\s+', ' ', 'g'))
$$;

CREATE OR REPLACE FUNCTION fn_today() RETURNS date
LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'Asia/Jakarta')::date $$;

CREATE TABLE app_user (
  email      text PRIMARY KEY CHECK (email = lower(btrim(email))),
  full_name  text NOT NULL,
  role       text NOT NULL CHECK (role IN ('MASTER_ADMIN','VENDOR_SPEC','VENDOR_CBD','BRAND_VIEWER','SYSTEM_ADMIN')),
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text
);

CREATE TABLE role_permission (
  role       text NOT NULL,
  permission text NOT NULL,
  PRIMARY KEY (role, permission)
);

CREATE TABLE audit_log (
  id          bigserial PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  user_email  text,
  entity      text NOT NULL,
  entity_id   text,
  action      text NOT NULL,          -- INSERT / UPDATE / DELETE / nama aksi dari fn_*
  before_data jsonb,
  after_data  jsonb
);
CREATE INDEX idx_audit_entity  ON audit_log (entity, entity_id);
CREATE INDEX idx_audit_created ON audit_log (created_at DESC);
```

F1b (login in-app, butuh extension `pgcrypto`):
```sql
ALTER TABLE app_user
  ADD COLUMN password_hash        text,                          -- bcrypt
  ADD COLUMN must_change_password boolean NOT NULL DEFAULT true,
  ADD COLUMN failed_attempts      integer NOT NULL DEFAULT 0,
  ADD COLUMN locked_until         timestamptz,
  ADD COLUMN last_login_at        timestamptz;

CREATE TABLE app_session (
  token_hash text PRIMARY KEY,                                    -- SHA-256 dari token
  email      text NOT NULL REFERENCES app_user(email) ON UPDATE CASCADE ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL                                 -- login + 12 jam
);
```

### F2
```sql
CREATE TABLE supplier (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name             text NOT NULL CHECK (btrim(name) <> ''),
  name_key         text GENERATED ALWAYS AS (fn_normalize(name)) STORED,
  default_currency text NOT NULL DEFAULT 'IDR' CHECK (default_currency IN ('IDR','USD')),
  status           text NOT NULL DEFAULT 'APPROVED' CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_supplier_name UNIQUE (name_key)
);

CREATE TABLE component_group (
  code        text PRIMARY KEY,
  name        text NOT NULL,
  range_start integer NOT NULL,
  range_end   integer NOT NULL,
  sort_order  integer NOT NULL
);
INSERT INTO component_group VALUES
  ('a','Upper',0,3990,1), ('c','Bottom unit',4000,5990,2),
  ('d','Packaging',6000,7990,3), ('e','Miscellaneous',8000,9990,4);

CREATE TABLE component (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number     integer NOT NULL CHECK (number % 10 = 0),
  name       text NOT NULL CHECK (btrim(name) <> ''),
  group_code text NOT NULL REFERENCES component_group(code),
  status     text NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_component_number UNIQUE (number)
);
-- trg_component_check: nomor harus di rentang grupnya
```

### F3
```sql
CREATE TABLE material (
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

CREATE TABLE material_supplier (
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
CREATE UNIQUE INDEX uq_material_one_preferred ON material_supplier (material_id) WHERE is_preferred;

-- valid_from inklusif, valid_to eksklusif; color NULL = semua warna
CREATE TABLE material_price (
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
CREATE INDEX idx_material_price_link ON material_price (material_supplier_id, color_key);
```

### F4
```sql
CREATE TABLE product_model (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code         text NOT NULL CHECK (btrim(code) <> ''),
  name         text NOT NULL CHECK (btrim(name) <> ''),
  factory      text, category text, outsole_mold text, last_no text,
  construction text, size_range text, sample_size text,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_model_code UNIQUE (code)
);

-- Satu baris per model + season (= "specsheet" di Python)
CREATE TABLE specsheet (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id    uuid NOT NULL REFERENCES product_model(id),
  season      text NOT NULL CHECK (season ~ '^(SS|FH)[0-9]{2}$'),
  season_sort integer GENERATED ALWAYS AS
              (substr(season, 3, 2)::integer * 10 + CASE WHEN left(season, 2) = 'FH' THEN 1 ELSE 0 END) STORED,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_specsheet_season UNIQUE (model_id, season)
);

CREATE TABLE article (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  specsheet_id uuid NOT NULL REFERENCES specsheet(id),
  code         text NOT NULL CHECK (btrim(code) <> ''),
  colorway     text NOT NULL CHECK (btrim(colorway) <> ''),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_article_code UNIQUE (specsheet_id, code)
);
-- trg_article_limit: maksimal 5 article per season

CREATE TABLE article_attachment (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id uuid NOT NULL REFERENCES article(id) ON DELETE CASCADE,
  file_name  text NOT NULL,
  mime_type  text NOT NULL CHECK (mime_type IN ('image/jpeg','image/png','application/pdf')),
  size_bytes integer NOT NULL CHECK (size_bytes <= 5242880),
  content    bytea NOT NULL,
  note       text,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text
);
CREATE INDEX idx_attachment_article ON article_attachment (article_id);
```

### F5
```sql
CREATE TABLE specsheet_revision (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  specsheet_id       uuid NOT NULL REFERENCES specsheet(id),
  stage              text NOT NULL CHECK (stage IN ('PULL','SMS','GTM','PROD')),
  stage_order        smallint GENERATED ALWAYS AS
                     (CASE stage WHEN 'PULL' THEN 1 WHEN 'SMS' THEN 2 WHEN 'GTM' THEN 3 ELSE 4 END) STORED,
  revision_no        integer NOT NULL CHECK (revision_no >= 0),
  status             text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','PUBLISHED')),
  source_revision_id uuid REFERENCES specsheet_revision(id),
  published_at       timestamptz,
  published_by       text,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_revision_no UNIQUE (specsheet_id, stage, revision_no)
);
CREATE UNIQUE INDEX uq_one_draft_per_specsheet ON specsheet_revision (specsheet_id) WHERE status = 'DRAFT';

CREATE TABLE revision_article (
  revision_id uuid NOT NULL REFERENCES specsheet_revision(id) ON DELETE CASCADE,
  article_id  uuid NOT NULL REFERENCES article(id),
  status      text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DROPPED')),
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  PRIMARY KEY (revision_id, article_id)
);

CREATE TABLE bom_line (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  revision_id          uuid NOT NULL REFERENCES specsheet_revision(id) ON DELETE CASCADE,
  line_key             uuid NOT NULL,          -- identitas baris lintas revisi
  origin_line_key      uuid,                   -- line_key sumber saat copy/carryover
  replaces_line_key    uuid,                   -- baris yang diganti ("Ganti material")
  component_id         uuid REFERENCES component(id),
  local_component_no   integer CHECK (local_component_no % 10 <> 0),
  local_component_name text,
  parent_line_key      uuid,                   -- terisi = subkomponen
  sub_seq              integer,
  sub_name             text,
  material_id          uuid NOT NULL REFERENCES material(id),
  supplier_id          uuid REFERENCES supplier(id),
  process              text,                   -- "Remarks"
  is_active            boolean NOT NULL DEFAULT true,
  sort_order           integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_bom_line_key UNIQUE (revision_id, line_key),
  CHECK (parent_line_key IS NOT NULL OR component_id IS NOT NULL OR local_component_no IS NOT NULL)
);
CREATE INDEX idx_bom_line_revision ON bom_line (revision_id);
CREATE UNIQUE INDEX uq_bom_local_no ON bom_line (revision_id, local_component_no)
  WHERE is_active AND parent_line_key IS NULL AND local_component_no IS NOT NULL;

-- is_used otomatis: kosong / none / - / n/a / na = tidak dipakai
CREATE TABLE bom_cell (
  bom_line_id uuid NOT NULL REFERENCES bom_line(id) ON DELETE CASCADE,
  article_id  uuid NOT NULL REFERENCES article(id),
  color       text,
  is_used     boolean GENERATED ALWAYS AS
              (fn_normalize(color) NOT IN ('', 'none', '-', 'n/a', 'na')) STORED,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  PRIMARY KEY (bom_line_id, article_id)
);
-- trg_lock_published: tolak perubahan revision_article / bom_line / bom_cell bila revisinya PUBLISHED
```

### F6
```sql
CREATE TABLE change_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_type    text NOT NULL CHECK (doc_type IN ('SPECSHEET','CBD')),
  revision_id uuid NOT NULL,
  category    text NOT NULL CHECK (category IN
              ('EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER')),
  reason      text NOT NULL,
  diff        jsonb,                            -- diisi di fase Opsional
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  text NOT NULL
);
CREATE INDEX idx_change_log_revision ON change_log (revision_id);
```

### F7
```sql
CREATE TABLE cbd_revision (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  article_id             uuid NOT NULL REFERENCES article(id),
  stage                  text NOT NULL CHECK (stage IN ('PULL','SMS','GTM','PROD')),
  stage_order            smallint GENERATED ALWAYS AS
                         (CASE stage WHEN 'PULL' THEN 1 WHEN 'SMS' THEN 2 WHEN 'GTM' THEN 3 ELSE 4 END) STORED,
  revision_no            integer NOT NULL CHECK (revision_no >= 0),
  specsheet_revision_id  uuid NOT NULL REFERENCES specsheet_revision(id),
  exchange_rate          numeric(18,4) CHECK (exchange_rate > 0),
  amortization           numeric(18,4) NOT NULL DEFAULT 0,
  adjustment             numeric(18,4) NOT NULL DEFAULT 0,
  target_fob             numeric(18,4),
  selling_price          numeric(18,4),
  status                 text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','PUBLISHED')),
  sync_status            text NOT NULL DEFAULT 'IN_SYNC' CHECK (sync_status IN ('IN_SYNC','NEEDS_REVISION')),
  source_cbd_revision_id uuid REFERENCES cbd_revision(id) ON DELETE SET NULL,
  published_at           timestamptz,
  published_by           text,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_cbd_revision_no UNIQUE (article_id, stage, revision_no)
);
CREATE UNIQUE INDEX uq_one_cbd_draft ON cbd_revision (article_id) WHERE status = 'DRAFT';

CREATE TABLE cbd_line (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cbd_revision_id       uuid NOT NULL REFERENCES cbd_revision(id) ON DELETE CASCADE,
  line_key              uuid NOT NULL,
  component_id          uuid REFERENCES component(id),
  local_component_no    integer,
  sub_seq               integer,
  sub_name              text,
  material_id           uuid NOT NULL REFERENCES material(id),
  color                 text,
  supplier_id           uuid REFERENCES supplier(id),
  uom                   text NOT NULL,
  group_code            text NOT NULL REFERENCES component_group(code),
  yield_value           numeric(18,6) CHECK (yield_value > 0),
  usage_value           numeric GENERATED ALWAYS AS (1 / yield_value) STORED,   -- usage = 1 / yield
  loss_pct              numeric(9,4) NOT NULL DEFAULT 0,
  price_original        numeric(18,4) CHECK (price_original > 0),
  currency              text CHECK (currency IN ('IDR','USD')),
  price_source          text CHECK (price_source IN ('MASTER','OVERRIDE','QUOTATION')),
  material_price_id     uuid REFERENCES material_price(id),
  price_override_reason text,
  price_reference       text,
  status                text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','MISSING_IN_SPEC')),
  value_origin          text NOT NULL DEFAULT 'INPUT' CHECK (value_origin IN ('INPUT','COPIED','CARRIED_FROM_REPLACED')),
  value_source_ref      text,
  sort_order            integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CONSTRAINT uq_cbd_line_key UNIQUE (cbd_revision_id, line_key),
  CHECK ((price_original IS NULL) = (currency IS NULL)),
  CHECK (price_source <> 'OVERRIDE' OR btrim(coalesce(price_override_reason, '')) <> '')
);
CREATE INDEX idx_cbd_line_revision ON cbd_line (cbd_revision_id);
-- trg_lock_published diperluas ke cbd_line & cbd_revision (revisi terbit hanya boleh berubah sync_status / specsheet_revision_id)
```

### F8 – F10
Tidak ada tabel baru, hanya function & view.

---

## 8. Register objek DB

Diperbarui setiap fase selesai direview. Kolom **Dibuat** = Anda sudah menjalankan SQL-nya; **Diverifikasi** = hasil query cek skema sudah dicocokkan.

| Objek | Jenis | Fase | Dibuat | Diverifikasi |
|---|---|---|:-:|:-:|
| `fn_normalize`, `fn_today` | function | F1 | 🟡 | ⬜ |
| `app_user` | tabel | F1 | 🟡 | ⬜ |
| `role_permission` | tabel | F1 | 🟡 | ⬜ |
| `audit_log` | tabel | F1 | 🟡 | ⬜ |
| `fn_touch_trigger` + `trg_touch`, `fn_audit_trigger` + `trg_audit`, `fn_setup_table` | trigger/function | F1 | 🟡 | ⬜ |
| `fn_role_label` | function | F1 | 🟡 | ⬜ |
| ~~`fn_assert_perm`, `v_my_perms`, `fn_user_save` (versi email)~~ | diganti F1b (di-DROP) | F1 | 🟡 | – |
| extension `pgcrypto` | extension | F1b | ⬜ | ⬜ |
| `app_user` + kolom password/lock/login | tabel (ALTER) | F1b | ⬜ | ⬜ |
| `app_session` | tabel | F1b | ⬜ | ⬜ |
| `fn_audit`, `fn_token_hash`, `fn_random_password`, `fn_auth`, `fn_me` | function | F1b | ⬜ | ⬜ |
| `fn_login`, `fn_logout`, `fn_change_password`, `fn_user_save`, `fn_user_reset_password` | function | F1b | ⬜ | ⬜ |
| `supplier` | tabel | F2 | ⬜ | ⬜ |
| `component_group` | tabel | F2 | ⬜ | ⬜ |
| `component` + `trg_component_check` | tabel | F2 | ⬜ | ⬜ |
| `material` | tabel | F3 | ⬜ | ⬜ |
| `material_supplier` | tabel | F3 | ⬜ | ⬜ |
| `material_price` | tabel | F3 | ⬜ | ⬜ |
| `fn_price_add`, `fn_price_end`, `fn_price_lookup`, `fn_ensure_link`, `v_material_list` | function/view | F3 | ⬜ | ⬜ |
| `product_model` | tabel | F4 | ⬜ | ⬜ |
| `specsheet` | tabel | F4 | ⬜ | ⬜ |
| `article` + `trg_article_limit` | tabel | F4 | ⬜ | ⬜ |
| `article_attachment` | tabel | F4 | ⬜ | ⬜ |
| `v_model_list`, `v_article_status` | view | F4 | ⬜ | ⬜ |
| `specsheet_revision` | tabel | F5 | ⬜ | ⬜ |
| `revision_article` | tabel | F5 | ⬜ | ⬜ |
| `bom_line` | tabel | F5 | ⬜ | ⬜ |
| `bom_cell` | tabel | F5 | ⬜ | ⬜ |
| `trg_lock_published`, `fn_revision_*`, `fn_bom_*`, `v_bom_grid` | trigger/function/view | F5 | ⬜ | ⬜ |
| `change_log` | tabel | F6 | ⬜ | ⬜ |
| `v_revision_checklist`, `fn_revision_publish` | view/function | F6 | ⬜ | ⬜ |
| `cbd_revision` | tabel | F7 | ⬜ | ⬜ |
| `cbd_line` | tabel | F7 | ⬜ | ⬜ |
| `fn_cbd_expected_lines`, `fn_cbd_create`, `fn_cbd_delete_draft`, `v_cbd_line`, `v_cbd_article` | function/view | F7 | ⬜ | ⬜ |
| `fn_cbd_set_*`, `fn_cbd_refresh_*`, `v_cbd_recap`, `v_cbd_checklist`, `fn_cbd_publish` | function/view | F8 | ⬜ | ⬜ |
| `v_worklist_*`, `v_recent_published` | view | F10 | ⬜ | ⬜ |

Cara verifikasi skema (dijalankan di akhir tiap fase lewat query `z_run_sql`, hasilnya ditempel ke chat):
```sql
SELECT 'table' AS jenis, table_name AS nama FROM information_schema.tables
 WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
UNION ALL SELECT 'view', table_name FROM information_schema.views WHERE table_schema = 'public'
UNION ALL SELECT 'function', routine_name FROM information_schema.routines WHERE routine_schema = 'public'
UNION SELECT 'trigger', trigger_name FROM information_schema.triggers WHERE trigger_schema = 'public'
ORDER BY 1, 2;
```

### Register Custom Widget

| Widget | Page | Fase | Dibuat | Diverifikasi |
|---|---|---|:-:|:-:|
| `cwLogin` | `Login` | F1 | ⬜ | ⬜ |
| `cwStepper` | `Specsheet`, `CBD` | F5 / F7 | ⬜ | ⬜ |
| `cwBomGrid` | `Specsheet` | F5 | ⬜ | ⬜ |
| `cwCbdGrid` | `CBD` | F7 / F8 | ⬜ | ⬜ |

---

## 9. Log review export

| Versi | Tanggal | Fase | Hasil review |
|---|---|---|---|
| – | – | – | – |
