# PLAN — Migrasi Sistem Specsheet & CBD ke Appsmith

| | |
|---|---|
| Sumber (hanya dibaca) | `app/` (Flask + htmx + SQLite), `run_web.py`, `tests/` |
| Folder kerja | `appsmith/` — file ini + `exports/export_vN.json` |
| Target | Appsmith **v2.4** self-hosted (HTTPS) + PostgreSQL **16.15** (datasource `pg_main`) |
| Akses | App **publik** dengan login di dalam app (email + password), bukan akun Appsmith |
| Data lama | Tidak dimigrasi (mulai dari DB kosong) |
| Status | Rencana disetujui 24 Sep 2026 (termasuk P1–P3) · login in-app disetujui 25 Sep 2026 · UI campuran + Custom Widget disetujui 25 Sep 2026 · **F0 + F1 selesai** (export v1, 25 Sep 2026) · **F2 selesai** (export v2, 29 Sep 2026) · **F3 dikerjakan** (export v3, 29 Sep 2026; T13–T17 diperbaiki user) · **F3 + F3b selesai** (export v3b, 30 Sep 2026) · **F4 selesai** (export v4 = file user v4.7, 30 Sep 2026; Copy Article dihapus — keputusan user) · **F5 + F5b selesai** (export v5 = file user v5.5, 30 Sep 2026) · **F6 selesai** (export v6; uji ulang dilaporkan lolos di v7) · **F7 selesai** (export v7 = file user v7.1, 30 Sep 2026; T34–T35 diperbaiki) · **F8 dikerjakan** (export v8, 5 Okt 2026; temuan T37–T41, hasil uji & cek skema belum dikirim) |
| File siap tempel | `steps/F<n>_langkah.md` (langkah per fase: query, widget, uji), `sql/F<n>_*.sql` (jalankan lewat `z_run_sql` di app privat **DB Tools**), `js/*.js` (isi JSObject), `widgets/<cw>/` (Custom Widget: HTML/CSS/JS + README kontrak) |

Legenda status: ⬜ belum · 🟡 dibuat (belum diverifikasi dari export) · ✅ terverifikasi

---

## 1. Ringkasan status

| Fase | Isi | Export | Status |
|---|---|---|---|
| F0 | Persiapan: cek versi, app, cara menjalankan SQL | – | ✅ |
| F1 | Fondasi DB, login in-app & role, Admin user + audit | `export_v1.json` | ✅ semua uji lolos · temuan T1–T8 (lihat §9) |
| F2 | Master Supplier & Komponen | `export_v2.json` | ✅ semua uji lolos · temuan T9–T12 (lihat §9) |
| F3 | Master Material, supplier material, harga | `export_v3.json` | ✅ (T13–T17 diperbaiki di export v3b) |
| F3b | Approval harga oleh Master Admin (tambahan, keputusan user 29 Sep 2026) | `export_v3b.json` | ✅ semua uji lolos · T18–T19 diperbaiki |
| F4 | Model, Season, Article, lampiran article | `export_v4.json` | ✅ semua uji lolos · T21–T27 diperbaiki (v4.7) · Copy Article dihapus (keputusan user, lihat §6 F4) |
| F5 | Specsheet: revisi & grid BOM (+ F5b hapus baris) | `export_v5.json` | ✅ semua uji lolos · T28–T29, U1–U3 diperbaiki (v5.5) |
| F6 | Specsheet: checklist & terbit | `export_v6.json` | ✅ T30 ✅, T31 sebagian, T33 dilaporkan lolos (hasil E3 belum dikirim) |
| F7 | CBD: buat revisi & grid baris | `export_v7.json` | ✅ semua uji lolos (laporan user) · T34–T35 ✅, T36 sebagian (v7.1) |
| F8 | CBD: harga, rekap, refresh, terbit, sinkron specsheet | `export_v8.json` | 🟡 export v8 direview 5 Okt 2026 · temuan T37–T41 · hasil uji & cek skema belum dikirim |
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
    - **Custom Widget** hanya untuk bagian yang tidak bisa dibuat baik dengan widget bawaan: `cwLogin` (Login), `cwStepper` (stage + chip article, dipakai Specsheet & CBD), `cwBomGrid` (grid BOM, maks. 5 article per season), `cwCbdGrid` (grid CBD + rekap). Ditambahkan user di F1 (keputusan user, 25 Sep 2026): `cwHeader` (header di setiap page), `cwMenu` (menu Beranda), `cwUserForm` (form user), `cwTempPassword` (password sementara). Ditambahkan di F2 (keputusan user, 27 Sep 2026): `cwSupplierForm`, `cwKomponenForm` (isi modal tambah/ubah, pola sama dengan `cwUserForm`). Pola yang sama di F3 (`cwMaterialForm`, `cwLinkForm`, `cwPriceForm`, `cwReasonForm`) dan F4 (`cwModelForm`, `cwSeasonForm`, `cwArticleForm`).
    - Aturan Custom Widget: **hanya tampilan** (tanpa logika bisnis/query); data masuk lewat *Default model*, aksi keluar lewat `appsmith.updateModel()` + `appsmith.triggerEvent()` yang ditangani `<Page>Ctrl`; JavaScript biasa tanpa framework (library CDN jsDelivr dengan versi terkunci hanya bila perlu); warna/radius/font mengikuti tema app (`appsmith.theme`).
    - Setiap Custom Widget punya folder `appsmith/widgets/<cw>/` berisi `index.html`, `style.css`, `script.js`, dan `README.md` (kontrak model, nilai keluar, event).
11. **Export Excel**: library ExcelJS dipasang di Appsmith (Libraries). Cadangan: SheetJS tanpa style.
12. **Lampiran article**: FilePicker (Base64) → disimpan `bytea` di tabel `article_attachment`. Jenis jpg/png/pdf, maks 5 MB per file.
13. **Desain**: palet mockup Flask — primary navy `#122A52`, aksen `#3B6FE0`, latar `#F3F5FA`, radius 8px, font sistem (Segoe UI); chip status hijau/kuning/merah/abu. Hanya untuk laptop/PC (lebar ≥ 1280px).
14. **Approval harga material (F3b, keputusan user 29 Sep 2026)**: harga dari Vendor CBD = usulan PROPOSED, Master Admin approve/tolak (alasan wajib, tetap tersimpan); harga dari Master Admin langsung APPROVED. Harga lama tetap berlaku sampai usulan di-approve. Maks. satu usulan per supplier + warna (bisa dibatalkan tim CBD). Akhiri harga tanpa approval. Hanya harga APPROVED yang dipakai (lookup CBD, ringkasan material).

### Penyederhanaan dari sistem Python

| Di Python | Di Appsmith |
|---|---|
| Login pilih role bebas | Login email + password di dalam app; role dari tabel `app_user` |
| 4 cara buat revisi specsheet (kosong, carryover, lintas model, stage sama/berikut) | Satu function `fn_revision_create(mode)`; **Copy dari season lain** = carryover dari **model yang sama** saja (development NC / New Color), sumber hanya revisi **terbit**, baris BOM di-copy, article = article season tujuan, warna per article kosong. Copy **lintas model tidak dibawa** (keputusan user 30 Sep 2026) |
| 5 cara buat CBD | Satu function `fn_cbd_create(article, source)`. Stage CBD **selalu mengikuti stage specsheet terbit terakhir**; nomor revisi = terakhir di stage itu + 1 |
| `is_used` sel BOM dihitung di Python | Kolom generated di DB |
| Usage = 1/Yield dihitung di Python | Kolom generated di DB |
| Diff BOM/CBD saat terbit (JSON) | MVP: change log kategori + alasan saja; diff masuk fase Opsional (kolom `diff` sudah disiapkan) |
| Copy Article antar season (halaman Model) | Tidak dibawa — article diisi per season (keputusan user 30 Sep 2026) |
| Menu Specsheet & CBD dengan daftar sendiri | Satu `Model_List`; dari sana buka Model / Specsheet / CBD |
| Persetujuan di halaman terpisah | Filter "PROPOSED" + tombol Approve di tiap halaman master; ringkasan di Beranda admin |
| Merge material, import CSV, reset data, halaman cetak, harga referensi brand | Tidak dibawa (cetak diganti Excel; harga referensi di Opsional) |
| Foto per specsheet (belum ada UI) | Lampiran per **article** |

### Perbaikan inkonsistensi Python (disetujui: diperbaiki)

| # | Di Python | Di Appsmith |
|---|---|---|
| P1 | Copy (carryover / lintas model) memilih revisi sumber "terakhir" hanya dari nomor revisi (PULL r2 dianggap lebih baru dari PROD r0) | Urut stage dulu, lalu nomor revisi |
| P2 | Ringkasan status di daftar model memakai revisi yang **dibuat** terakhir | Pakai urutan stage + nomor revisi, sama seperti bagian lain |
| P3 | Form tambah material tidak punya pilihan metode harga (selalu CATALOG) | Ada pilihan CATALOG / QUOTATION |
| P4 | Ganti material pada baris induk: subkomponen tetap menunjuk `line_key` baris lama yang sudah nonaktif → hilang dari grid | Subkomponen ikut dipindah ke baris baru (`fn_bom_replace_material`) — ditemukan saat menyiapkan F5, 30 Sep 2026 |
| P5 | Penandaan sinkron CBD membandingkan specsheet terbit **sebelumnya** dengan yang baru → CBD yang sudah NEEDS_REVISION kembali IN_SYNC bila revisi specsheet berikutnya tidak mengubah apa-apa | Dibandingkan dengan **acuan CBD itu sendiri** (`fn_cbd_sync_spec`) — ditemukan saat menyiapkan F8, 30 Sep 2026 |

---

## 3. Mapping Python → Appsmith

| Python | Page | Query / JSObject | DB |
|---|---|---|---|
| `web/auth.py`, `permissions.py`, `user_session.py`, `main.py` (masuk/keluar) | `Login` + semua page | `q_me`, `a_login`, `a_logout`, `a_change_password` · `Auth`, `Util`, `LoginCtrl` | `app_user`, `app_session`, `role_permission`, `fn_login`, `fn_me`, `fn_auth` |
| `admin.py` (audit log) + user (baru) | `Admin` | `q_users`, `a_user_save`, `a_user_reset_password`, `q_audit` · `AdminCtrl` | `app_user`, `audit_log`, `fn_user_save`, `fn_user_reset_password` |
| `audit.py` | – | – | `trg_audit` |
| `normalize.py`, `ids.py` | – | – | `fn_normalize`, `gen_random_uuid()` |
| `supplier_service.py` | `Master_Supplier` | `q_suppliers`, `a_supplier_insert`, `a_supplier_update` (nama, currency, status) · `SupplierCtrl` | `supplier`, `trg_supplier_check` |
| `component_service.py` | `Master_Komponen` | `q_components`, `q_component_groups` (+ saran nomor `next_no`), `a_component_add`, `a_component_update`, `a_component_set_status` · `KomponenCtrl` | `component_group`, `component`, `trg_component_check`, `fn_component_add` |
| `material_service.py` | `Master_Material`, `Material_Detail` | `q_materials`, `q_material_meta` (saran kode + kategori/UoM), `a_material_add`, `a_material_set_status`, `q_material`, `a_material_update` · `MaterialCtrl`, `MaterialDetailCtrl` | `material`, `trg_material_check`, `fn_material_add`, `fn_material_update`, `v_material_list` |
| `material_price_service.py` | `Material_Detail` | `q_links`, `q_link_supplier_options`, `q_prices`, `a_link_save`, `a_link_set_status`, `a_price_add`, `a_price_end` · `MaterialDetailCtrl` | `material_supplier`, `material_price`, `trg_material_supplier_check`, `fn_link_save`, `fn_price_add`, `fn_price_end`, `fn_price_lookup`, `fn_ensure_link` |
| `model_service.py`, `specsheet_service.py` (season) | `Model_List`, `Model_Detail` | `q_known_seasons`, `q_models`, `a_model_add` · `ModelCtrl` (Model List) · `q_model`, `q_seasons`, `a_model_update`, `a_season_add` · `ModelDetailCtrl` (Model Detail) | `product_model`, `specsheet`, `trg_model_check`, `trg_specsheet_check`, `v_model_list` |
| `article_service.py` (Model) + lampiran (baru) | `Model_Detail` | `q_articles`, `a_article_add`, `a_article_update`, `a_article_delete`, `q_attachments`, `q_attachment_file`, `a_attachment_add`, `a_attachment_delete` · `ModelDetailCtrl` | `article`, `article_attachment`, `trg_article_check`, `trg_article_delete_check`, `fn_article_is_used`, `fn_attachment_add`, `v_article_status` |
| `revision_service.py` | `Specsheet` | `q_spec_models`, `q_spec_model`, `q_spec_seasons`, `q_revisions`, `a_revision_create`, `a_revision_delete` (F5) · `a_revision_publish`, `q_publish_checklist`, `q_change_log` (F6) · `SpecCtrl` (+ `cwPublishForm`) | `specsheet_revision`, `revision_article`, `trg_lock_published`, `trg_revision_lock`, `fn_revision_create`, `fn_revision_delete_draft` · `change_log`, `v_revision_checklist`, `fn_revision_publish` (F6) |
| `bom_service.py`, `article_service.py` (revisi) | `Specsheet` | `q_bom_grid`, `q_rev_articles`, `q_bom_options`, `q_season_colors`, `a_bom_add_line`, `a_bom_add_sub`, `a_bom_replace_material`, `a_bom_set_supplier`, `a_bom_set_process`, `a_cell_save`, `a_rev_article_set`, `a_bom_delete_line` (F5b) · `BomCtrl` (grid = Custom Widget `cwBomGrid`, satu event `onAction`) | `bom_line`, `bom_cell`, `fn_bom_add_line`, `fn_bom_add_sub`, `fn_bom_replace_material`, `fn_bom_set_supplier`, `fn_bom_cell_set`, `fn_rev_article_set`, `fn_bom_delete_line` (F5b), `v_bom_grid` |
| `cbd_service.py`, `cbd_calc.py` | `Cost Breakdown (CBD)` | F7: `q_cbd_models`, `q_cbd_model`, `q_cbd_seasons`, `q_cbd_articles`, `q_cbd_revisions`, `q_cbd_lines`, `q_cbd_sources`, `a_cbd_create`, `a_cbd_delete`, `a_cbd_line_set` · F8: `q_cbd_recap`, `q_cbd_checklist`, `q_cbd_change_log`, `a_cbd_header_set`, `a_cbd_set_quotation`, `a_cbd_override_price`, `a_cbd_clear_override`, `a_cbd_refresh_prices`, `a_cbd_refresh_spec`, `a_cbd_publish` · `CbdCtrl`, `CbdGridCtrl` (grid + rekap + banner = Custom Widget `cwCbdGrid`, satu event `onAction`; buat = `cwCbdForm`; harga = `cwCbdPriceForm`; terbit = `cwPublishForm`) | `cbd_revision`, `cbd_line`, `fn_cbd_*`, `v_cbd_line`, `v_cbd_article` (F7) · `v_cbd_price_check`, `v_cbd_recap`, `v_cbd_checklist`, `fn_cbd_publish`, `fn_cbd_sync_spec` (F8) |
| `export_service.py` | `Specsheet`, `CBD` | `ExportCtrl` (ExcelJS) | pakai view yang sama |
| `worklist_service.py` | `Beranda` | `q_worklist_*` · `BerandaCtrl` | `v_worklist_*` |
| `report_service.py`, `diff_service.py`, `cbd_diff_service.py` | Opsional | – | – |
| `merge_service.py`, `csv_import.py`, `reset_service.py`, `seed_*.py`, `photo_service.py` | tidak dibawa | – | – |

---

## 4. Konvensi penamaan

| Objek | Pola | Contoh |
|---|---|---|
| Page | nama tampil di sidebar (boleh spasi) — dipakai persis oleh `navigateTo()` | lihat tabel **Nama page di app** di bawah |
| Query baca | `q_<benda>` | `q_materials`, `q_bom_grid` |
| Query tulis | `a_<benda>_<aksi>` | `a_material_insert`, `a_cbd_publish` |
| JSObject | `Auth` (setiap page kecuali Login), `Util` (setiap page), `<Nama>Ctrl` per page | `LoginCtrl`, `MaterialCtrl`, `BomCtrl` |
| Fungsi JSObject | kata kerja camelCase | `save()`, `openAdd()`, `publish()` |
| Widget | prefiks jenis + NamaPascal | lihat tabel di bawah |
| Tabel DB | snake_case tunggal | `material_price` |
| View / function / trigger | `v_*` / `fn_*` / `trg_*` | `v_cbd_line`, `fn_cbd_create` |

**Nama page di app** (export v1). Di dokumen ini page kadang ditulis dengan nama rencana (kiri); di Appsmith dan di `navigateTo()` selalu pakai nama di app (kanan).

| Nama rencana | Nama di app | Tampil di sidebar |
|---|---|---|
| `Login` | `Login` (home page) | tidak |
| `Beranda` | `Beranda` | ya |
| `Admin` | `Admin` | ya |
| `Master_Supplier` | `Master Supplier` | ya |
| `Master_Komponen` | `Master Komponen` | ya |
| `Master_Material` | `Master Material` | ya |
| `Material_Detail` | `Material Detail` | tidak |
| `Model_List` | `Model List` | ya |
| `Model_Detail` | `Model Detail` | tidak |
| `Specsheet` | `Specsheet` | ya — pilih model & season di page; dari Model List / Model Detail langsung terpilih (keputusan user 30 Sep 2026) |
| `CBD` | `Cost Breakdown (CBD)` | ya — sama seperti Specsheet (F7) |

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
| `manage_price` (harga & metode harga; harga Vendor CBD = usulan) | ✓ | | ✓ | | |
| approve / tolak usulan harga (pakai `manage_master`, F3b) | ✓ | | | | |
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
- [x] Buat app, navigasi: Sidebar *(nama app di Appsmith: "Test Database", datasource: `Prestasi` — lihat §9)*
- [x] Tema app: primary `#122A52`, background `#F3F5FA`, radius M, font *System Default*
- [x] Buat page kosong: `Login` (home page), `Beranda`, `Admin`, `Master_Supplier`, `Master_Komponen`, `Master_Material`, `Material_Detail`, `Model_List`, `Model_Detail`, `Specsheet`, `CBD`
- [x] Buat app privat **DB Tools** berisi `z_run_sql` (prepared statements OFF); hapus `z_run_sql` dari app utama
- [x] Pasang extension `pgcrypto`
- [x] Uji pasang library ExcelJS (Libraries → +) → **berhasil**

**Selesai bila:** versi Appsmith & Postgres diketahui, 11 page ada, library terpasang, `pgcrypto` aktif, `z_run_sql` hanya ada di DB Tools.

### F1 — Fondasi, login in-app & role
- [x] Jalankan SQL F1 (`sql/F1_fondasi.sql`: fungsi dasar, `app_user`, `role_permission`, `audit_log`, trigger audit)
- [x] Jalankan SQL F1b (`sql/F1b_login.sql`: kolom password, `app_session`, `fn_auth`, `fn_me`, `fn_login`, `fn_logout`, `fn_change_password`, `fn_user_save`, `fn_user_reset_password`)
- [x] Set password awal akun System Admin Anda lewat `z_run_sql`
- [x] Page `Login` (home page): Custom Widget **`cwLogin`** (masuk + ganti password), logout lewat flag `appsmith.store.doLogout` (T7) — `Util`, `LoginCtrl`
- [x] `q_me`, `Auth` (cek sesi + izin + `pageQueries`), `Util` — disalin ke setiap page lain
- [x] Beranda: sapaan, role, tombol menu sesuai izin, **Ganti Password**, **Keluar** *(dibuat dengan Custom Widget `cwHeader` + `cwMenu`)*
- [x] Page `Admin`: tab **User** (tambah → password sementara, ubah role/nonaktif, reset password) dan **Audit Log** *(form user `cwUserForm`, password sementara `cwTempPassword`, header `cwHeader`)*
- [x] Navigasi: sembunyikan `Login`, `Material_Detail`, `Model_Detail` dari sidebar; Share → **Make application public** → Deploy

**Selesai bila:** buka URL app tanpa login → halaman Login; login benar masuk Beranda sesuai role; password sementara wajib diganti; 5 kali salah → terkunci 15 menit; logout/sesi habis → kembali ke Login; query tanpa token ditolak DB; login/logout/ganti password tercatat di Audit Log.

### F2 — Master Supplier & Komponen
- [x] SQL F2 (`sql/F2_master.sql`: `fn_has_perm`, `fn_auth_any`, `supplier` + `trg_supplier_check`, `component_group` + seed a/b/c/d, `component` + `trg_component_check`, `fn_component_add`)
- [x] `Master_Supplier`: tabel + cari + filter status, tambah (modal), ubah nama, status (tanpa currency default — keputusan user 27 Sep 2026: currency dipilih saat harga dimasukkan) — form modal: Custom Widget `cwSupplierForm`
- [x] `Master_Komponen`: tabel per grup, saran nomor berikutnya (max+10), tambah, ubah, status; vendor → otomatis PROPOSED; admin → Approve — form modal: Custom Widget `cwKomponenForm`

**Selesai bila:** nomor bukan kelipatan 10 / di luar rentang / sudah dipakai ditolak dengan pesan jelas; nama supplier beda kapital ditolak; semua perubahan masuk audit log.

### F3 — Master Material, supplier material, harga
- [x] SQL F3 (`sql/F3_material.sql`: `material` + `trg_material_check`, `material_supplier` + `trg_material_supplier_check`, `material_price`, `fn_material_add`, `fn_material_update`, `fn_link_save`, `fn_ensure_link`, `fn_price_add`, `fn_price_end`, `fn_price_lookup`, `v_material_list`; `fn_today` sudah ada dari F1)
- [x] Form modal Custom Widget (keputusan user): `cwMaterialForm` (tambah & ubah material), `cwLinkForm` (supplier material), `cwPriceForm` (harga; currency tanpa nilai awal, angka ambigu `47.500` ditolak)
- [x] `Master_Material`: tabel (kode, nama, kategori, thickness, UoM, metode harga, status, ringkasan supplier/harga), cari & filter (status, kategori, "belum ada harga"), tambah dengan saran `MTR-NNNN` dan pilihan metode harga (P3)
- [x] `Material_Detail` tab **Info**: edit identitas (admin), status, metode harga (`manage_price`)
- [x] Tab **Supplier & Harga**: daftar supplier material (kode di supplier, utama, status, approve), tambah supplier; per supplier harga berlaku + riwayat, tambah harga (warna opsional, tanggal berlaku, **currency IDR/USD wajib dipilih — tanpa nilai awal**), akhiri harga. Tambah/akhiri harga: Master Admin & Vendor – CBD (`manage_price`, keputusan user 27 Sep 2026). Harga disembunyikan untuk VENDOR_SPEC

### F3b — Approval harga (tambahan, keputusan user 29 Sep 2026)
- [x] SQL F3b (`sql/F3b_price_approval.sql`: kolom `status`/`decided_by`/`decided_at`/`reject_reason` di `material_price`, `uq_price_one_proposed`, `fn_price_activate`, `fn_price_approve`, `fn_price_reject`, `fn_price_cancel`; `fn_price_add`, `fn_price_end`, `fn_price_lookup`, `v_material_list` diperbarui)
- [x] `Master Material`: filter **Harga menunggu approval**, ringkasan usulan di kolom Supplier
- [x] `Material Detail`: status MENUNGGU APPROVAL / DITOLAK di tabel harga, tombol **Approve**, **Tolak** (Custom Widget `cwReasonForm`), **Batalkan**; `cwPriceForm` mode **Usulkan**

**Selesai bila:** usulan Vendor CBD tidak dipakai sebelum di-approve dan harga lama tetap berlaku; approve menutup harga lama; tolak wajib beralasan; hanya satu usulan per supplier + warna.

**Selesai bila (F3):** duplikat material (nama+thickness+UoM setelah normalisasi) ditolak; harga baru menutup harga lama; tanggal mundur ditolak; material QUOTATION tidak bisa diberi harga; `fn_price_lookup` mengembalikan harga warna dulu lalu semua warna.

### F4 — Model, Season, Article, lampiran
File siap (30 Sep 2026): `sql/F4_model.sql`, `js/ModelCtrl.js`, `js/ModelDetailCtrl.js`, `widgets/cwModelForm/`, `widgets/cwSeasonForm/`, `widgets/cwArticleForm/`, `steps/F4_langkah.md`.
- [x] SQL F4 (`sql/F4_model.sql`: `product_model` + `trg_model_check`, `specsheet` + `trg_specsheet_check`, `article` + `trg_article_check` (batas 5 article, kode unik per season, kode terpakai terkunci) + `trg_article_delete_check`, `article_attachment`, `fn_article_is_used`, `fn_attachment_add` (jenis file dicek dari isi), `v_model_list`, `v_article_status`)
- [x] `Model List`: tabel model + filter season + cari; tombol Buka / Specsheet / CBD (CBD hanya bila `view_cbd`); tambah model (modal `cwModelForm`)
- [x] `Model Detail` tab **Info Model**: edit data model (`cwModelForm`)
- [x] Tab **Season & Article**: pilih/tambah season (`cwSeasonForm`, format SS26/FH26), tabel article (kode, colorway, jumlah lampiran), tambah/ubah (`cwArticleForm`)/hapus article (hapus hanya bila belum dipakai)
- [x] Lampiran per article (modal `mdlLampiran`): upload (jpg/png/pdf, ≤ 5 MB), lihat gambar, unduh, hapus
- [ ] **Hapus Copy Article** (keputusan user 30 Sep 2026: article tidak di-copy antar season, hanya struktur specsheet di F5): `DROP FUNCTION fn_article_copy`, hapus `selArticleSumber`, `btnArticleCopy`, `a_article_copy`, tempel ulang `ModelDetailCtrl` (`steps/F4_langkah.md` §5)
- ➡️ Dipindah ke F5: ringkasan specsheet terakhir di Model List (P2) & status article di specsheet · ke F7: status article di CBD (tabelnya belum ada di F4; view ditambah kolom di akhir)

**Selesai bila:** article ke-6 di satu season ditolak; kode article duplikat (beda huruf besar/kecil) ditolak; lampiran bisa diunggah, dilihat, dan diunduh; file bukan jpg/png/pdf ditolak DB. *Kode article terpakai tidak bisa diubah/dihapus* diuji di F5.

### F5 — Specsheet: revisi & grid BOM
File siap (30 Sep 2026): `sql/F5_specsheet.sql`, `js/SpecCtrl.js`, `js/BomCtrl.js`, `js/ModelCtrl.js` + `js/ModelDetailCtrl.js` (kolom status specsheet), `widgets/cwStepper/`, `widgets/cwRevisionForm/`, `widgets/cwBomGrid/`, `steps/F5_langkah.md`.
- [x] SQL F5 (`sql/F5_specsheet.sql`: `specsheet_revision`, `revision_article`, `bom_line`, `bom_cell`, `trg_lock_published`, `trg_revision_lock`, `fn_revision_draft`, `fn_revision_create`, `fn_revision_delete_draft`, `fn_bom_check_material`, `fn_bom_create_cells`, `fn_bom_add_line`, `fn_bom_add_sub`, `fn_bom_replace_material` (P4), `fn_bom_set_supplier`, `fn_bom_cell_set`, `fn_rev_article_set`, `v_bom_grid`; `v_model_list` & `v_article_status` ditambah kolom status specsheet)
- [x] Model List kolom **Specsheet** (revisi terakhir, P2; Brand hanya terbit) · Model Detail kolom **Specsheet** per article (pindahan dari F4)
- [x] Custom Widget **`cwStepper`**: stepper stage PULL→SMS→GTM→PROD berisi revisi (brand: hanya PUBLISHED)
- [x] Custom Widget **`cwRevisionForm`** (modal Buat Revisi, pola form modal)
- [x] Page `Specsheet` (`?model_id=`): pilih season (widget bawaan) + `cwStepper`
- [x] Wizard **Buat Revisi**: Kosong (pilih stage) / Copy dari season lain model yang sama (hanya revisi terbit, default terbit terakhir — P1; baris BOM di-copy, semua article season tujuan masuk revisi, warna kosong) / Revisi berikutnya / Stage berikutnya; hapus draft
- [x] Custom Widget **`cwBomGrid`**: No, Komponen, Material, Supplier, UoM, Remarks + satu kolom per article (edit warna langsung di sel, saran warna se-season); tambah baris (komponen master atau lokal), tambah subkomponen, ganti material, ubah supplier/remarks
- [x] **F5b** (permintaan user 30 Sep 2026, tidak ada di Python): hapus baris BOM di draft (`sql/F5b_bom_delete.sql`, `fn_bom_delete_line`, tombol **Hapus** di `cwBomGrid`; induk ikut menghapus subkomponennya)
- [x] Article di revisi: pilih article season, drop/aktifkan

**Selesai bila:** hanya satu draft per specsheet; revisi terbit tidak bisa diedit (ditolak DB); ganti material menonaktifkan baris lama; supplier baru di BOM membuat link PROPOSED; link INACTIVE ditolak.

### F6 — Specsheet: checklist & terbit
File siap (30 Sep 2026): `sql/F6_publish.sql`, `js/SpecCtrl.js`, `widgets/cwPublishForm/`, `steps/F6_langkah.md`.
- [x] SQL F6 (`change_log`, `v_revision_checklist`, `fn_revision_publish` — checklist dihitung ulang di DB setelah revisi dikunci)
- [x] Modal **Terbitkan** (`mdlTerbit`, Custom Widget `cwPublishForm`): checklist (article aktif ≥ 1, tiap article aktif dipakai, tidak ada material INACTIVE [blok]; baris tanpa supplier [peringatan]), kategori + alasan (wajib selain revisi awal; revisi awal kategori terpilih *Lainnya*). Pilihan kategori specsheet: MATERIAL / COMPONENT / TREATMENT / OTHER (kategori CBD dipakai di F8)
- [x] **Riwayat**: tombol **Riwayat (n)** → modal `mdlRiwayat` + `tblRiwayat` (semua terbit season ini, terbaru dulu) — penyederhanaan dari tab; change log revisi terbit juga tampil di `txtRevisi`

**Selesai bila:** terbit ditolak bila checklist gagal; setelah terbit revisi terkunci dan muncul di Riwayat.

### F7 — CBD: buat revisi & grid baris
File siap (30 Sep 2026): `sql/F7_cbd.sql`, `js/CbdCtrl.js`, `js/CbdGridCtrl.js`, `js/ModelDetailCtrl.js` (kolom CBD), `js/SpecCtrl.js` (`openCbd` meneruskan `from`), `widgets/cwStepper/` (baris chip article, opsional), `widgets/cwCbdForm/`, `widgets/cwCbdGrid/`, `steps/F7_langkah.md`.
- [x] SQL F7 (`cbd_revision`, `cbd_line`, `fn_cbd_revision_lock`/`fn_cbd_line_lock`, `fn_spec_latest_pub`, `fn_cbd_article_spec_status`, `fn_cbd_draft`, `fn_cbd_group_code`, `fn_cbd_identity`, `fn_cbd_expected_lines`, `fn_cbd_populate`, `fn_cbd_create`, `fn_cbd_delete_draft`, `fn_cbd_line_set`, `v_cbd_line`, `v_cbd_article`; `v_article_status` + kolom CBD)
- [x] Page `Cost Breakdown (CBD)` (`?model_id=&season=&from=`): pilih model & season di page (sama dengan Specsheet), `cwStepper` (chip article + status: belum ada CBD / draft / terbit / perlu revisi / di-drop / specsheet belum terbit, dan stepper revisi)
- [x] **Buat CBD** (`cwCbdForm`): baru dari specsheet / copy dari article lain (model sama, season apa pun) — bila article belum punya CBD; revisi berikutnya — bila sudah ada CBD terbit. Stage = stage specsheet acuan
- [x] Custom Widget **`cwCbdGrid`**: grid per grup a/b/c/d + bagian MISSING_IN_SPEC; edit Yield & Loss % di sel; Usage, harga IDR/USD, cost/pair dari view; keterangan kenapa harga kosong
- [x] Model Detail kolom **CBD** per article (pindahan dari F4)
- ➡️ F8: terbit CBD (pakai ulang `cwPublishForm`), refresh dari specsheet (pakai ulang `fn_cbd_populate`), harga, rekap. Uji F7 menerbitkan CBD sementara lewat DB Tools

**Selesai bila:** baris CBD = baris BOM terbit yang dipakai article (termasuk subkomponen); yield/loss tersalin dari sumber (lineKey → originLineKey → identitas); baris sumber yang hilang jadi MISSING_IN_SPEC.

### F8 — CBD: harga, rekap, refresh, terbit, sinkron
File siap (30 Sep 2026): `sql/F8_cbd_price.sql`, `js/CbdCtrl.js`, `js/CbdGridCtrl.js`, `widgets/cwCbdGrid/` (rekap + banner + tombol harga), `widgets/cwCbdPriceForm/` (baru), `widgets/cwPublishForm/` (opsi `blockedWhere`), `steps/F8_langkah.md`.
- [x] SQL F8 (`fn_cbd_populate` versi array — sumber bisa revisi itu sendiri, `fn_cbd_create` diperbarui, `v_cbd_price_check`, `v_cbd_recap`, `v_cbd_checklist`, `fn_cbd_price_line`, `fn_cbd_check_price`, `fn_cbd_set_quotation`, `fn_cbd_override_price`, `fn_cbd_clear_override`, `fn_cbd_refresh_prices`, `fn_cbd_refresh_from_spec`, `fn_cbd_header_set` (rate/amortisasi/adjustment/target FOB/selling price/margin), `fn_cbd_publish`, `fn_cbd_sync_spec`, `fn_revision_publish` + penandaan sinkron)
- [x] Harga: quotation (material QUOTATION, kosong = tidak dihargai terpisah), override + alasan (material CATALOG), hapus override — modal `mdlCbdHarga` / `cwCbdPriceForm`; info kenapa harga kosong (`price_gap`: quotation, tanpa supplier, harga tersedia, *menunggu approval* F3b, warna lain, tidak ada) — currency wajib dipilih setiap input (tanpa nilai awal)
- [x] Rekap di `cwCbdGrid` (panel ringkasan menempel): exchange rate, amortisasi, adjustment, target FOB, actual FOB, selisih (OVER/UNDER/SESUAI), selling price ⇄ margin %
- [x] Banner + tombol **Refresh dari Specsheet** / **Refresh Harga dari Master** (di `cwCbdGrid`)
- [x] Modal **Terbitkan** CBD (`mdlCbdTerbit`, `cwPublishForm`) + **Riwayat** (tombol + modal `mdlCbdRiwayat`, sama dengan Specsheet F6)
- [x] Terbit specsheet → CBD terbit terakhir article aktif jadi NEEDS_REVISION bila baris/supplier/warna berubah dibanding acuannya (P5); sama → acuan dipindah, IN_SYNC

**Selesai bila:** angka rekap sama dengan rumus Python (cek 1 contoh manual); terbit ditolak bila specsheet usang / rate kosong / harga master berubah / baris berharga tanpa yield.

### F9 — Export Excel
- [ ] Library ExcelJS terpasang
- [ ] `ExportCtrl.specsheet()` — header model/season/stage, tabel BOM × article, blok tanda tangan
- [ ] `ExportCtrl.cbd()` — per grup, MISSING_IN_SPEC, rekap biaya & margin, change log
- [ ] Tombol Export di `Specsheet` & `CBD` (brand hanya revisi terbit)

**Selesai bila:** file `.xlsx` terunduh, isinya sama dengan layar.

### F10 — Beranda "Tugas Saya"
- [ ] SQL F10 (`v_worklist_spec`, `v_worklist_cbd`, `v_worklist_admin`, `v_recent_published`)
- [ ] Per role: Vendor Spec (draft berjalan, article belum masuk revisi) · Vendor CBD (belum ada CBD, perlu refresh, perlu revisi, harga master kosong) · Master Admin (antrian PROPOSED, termasuk usulan harga F3b) · Brand (terbit terbaru) · System Admin (ringkasan)

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
  ('a','Upper',0,3990,1), ('b','Bottom unit',4000,5990,2),
  ('c','Packaging',6000,7990,3), ('d','Miscellaneous',8000,9990,4);
-- kode a/b/c/d berurutan (keputusan user 27 Sep 2026; Python memakai a/c/d/e)

CREATE TABLE component (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number     integer NOT NULL CHECK (number % 10 = 0),
  name       text NOT NULL CHECK (btrim(name) <> ''),
  group_code text NOT NULL REFERENCES component_group(code) ON UPDATE CASCADE,
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

-- F3b: approval harga
ALTER TABLE material_price
  ADD COLUMN status        text NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED','APPROVED','REJECTED')),
  ADD COLUMN decided_by    text,
  ADD COLUMN decided_at    timestamptz,
  ADD COLUMN reject_reason text;           -- wajib bila REJECTED
CREATE UNIQUE INDEX uq_price_one_proposed ON material_price (material_supplier_id, color_key) WHERE status = 'PROPOSED';
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
CREATE INDEX idx_article_specsheet ON article (specsheet_id);
-- trg_article_check: maksimal 5 article per season, kode unik per season (tidak peka huruf besar/kecil),
-- kode tidak bisa diubah bila article sudah dipakai (fn_article_is_used); trg_article_delete_check: tolak hapus bila dipakai

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
CREATE INDEX idx_revision_article_article ON revision_article (article_id);

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
CREATE INDEX idx_bom_cell_article ON bom_cell (article_id);
-- trg_lock_published: tolak perubahan revision_article / bom_line / bom_cell bila revisinya PUBLISHED
-- trg_revision_lock: revisi PUBLISHED tidak bisa diubah/dihapus (DRAFT -> PUBLISHED tetap boleh)
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
| `fn_normalize`, `fn_today` | function | F1 | ✅ | ✅ |
| `app_user` | tabel | F1 | ✅ | ✅ |
| `role_permission` | tabel | F1 | ✅ | ✅ |
| `audit_log` | tabel | F1 | ✅ | ✅ |
| `fn_touch_trigger` + `trg_touch`, `fn_audit_trigger` + `trg_audit`, `fn_setup_table` | trigger/function | F1 | ✅ | ✅ |
| `fn_role_label` | function | F1 | ✅ | ✅ |
| ~~`fn_assert_perm`, `v_my_perms`, `fn_user_save` (versi email)~~ | diganti F1b (di-DROP) | F1 | ✅ | – (sudah tidak ada ✅) |
| extension `pgcrypto` | extension | F1b | ✅ | ✅ |
| `app_user` + kolom password/lock/login | tabel (ALTER) | F1b | ✅ | ✅ |
| `app_session` | tabel | F1b | ✅ | ✅ |
| `fn_audit`, `fn_token_hash`, `fn_random_password`, `fn_auth`, `fn_me` | function | F1b | ✅ | ✅ |
| `fn_login`, `fn_logout`, `fn_change_password`, `fn_user_save`, `fn_user_reset_password` | function | F1b | ✅ | ✅ |
| `fn_has_perm`, `fn_auth_any` | function | F2 | ✅ | ✅ |
| `supplier` + `fn_supplier_check`/`trg_supplier_check` | tabel/trigger | F2 | ✅ | ✅ |
| `component_group` | tabel | F2 | ✅ | ✅ |
| `component` + `fn_component_check`/`trg_component_check`, `idx_component_group` | tabel/trigger | F2 | ✅ | ✅ |
| `fn_component_add` | function | F2 | ✅ | ✅ |
| `material` | tabel | F3 | ✅ | ✅ |
| `material_supplier` | tabel | F3 | ✅ | ✅ |
| `material_price` | tabel | F3 | ✅ | ✅ |
| `fn_material_check`/`trg_material_check`, `fn_material_supplier_check`/`trg_material_supplier_check` | trigger | F3 | ✅ | ✅ |
| `fn_material_add`, `fn_material_update`, `fn_link_save` | function | F3 | ✅ | ✅ |
| `fn_price_add`, `fn_price_end`, `fn_price_lookup`, `fn_ensure_link`, `v_material_list` | function/view | F3 | ✅ | ✅ |
| `material_price` + kolom approval, `uq_price_one_proposed` | tabel (ALTER) | F3b | ✅ | ✅ |
| `fn_price_activate`, `fn_price_approve`, `fn_price_reject`, `fn_price_cancel` (+ `fn_price_add`, `fn_price_end`, `fn_price_lookup`, `v_material_list` diperbarui) | function/view | F3b | ✅ | ✅ |
| `product_model` + `fn_model_check`/`trg_model_check` | tabel/trigger | F4 | ✅ | ✅ |
| `specsheet` + `fn_specsheet_check`/`trg_specsheet_check` | tabel/trigger | F4 | ✅ | ✅ |
| `article` + `fn_article_check`/`trg_article_check`, `fn_article_delete_check`/`trg_article_delete_check`, `idx_article_specsheet` | tabel/trigger | F4 | ✅ | ✅ |
| `article_attachment` | tabel | F4 | ✅ | ✅ |
| `fn_article_is_used`, `fn_attachment_add` | function | F4 | ✅ | ✅ |
| ~~`fn_article_copy`~~ | di-DROP (Copy Article dihapus, keputusan user 30 Sep 2026) | F4 | ⬜ DROP | – |
| `v_model_list`, `v_article_status` (kolom status specsheet/CBD ditambah di F5/F7) | view | F4 | ✅ | ✅ |
| `specsheet_revision` + `uq_one_draft_per_specsheet`, `fn_revision_lock`/`trg_revision_lock` | tabel/trigger | F5 | ✅ | ✅ |
| `revision_article` + `idx_revision_article_article` | tabel | F5 | ✅ | ✅ |
| `bom_line` + `uq_bom_local_no` | tabel | F5 | ✅ | ✅ |
| `bom_cell` + `idx_bom_cell_article` | tabel | F5 | ✅ | ✅ |
| `fn_lock_published`/`trg_lock_published` (revision_article, bom_line, bom_cell) | trigger | F5 | ✅ | ✅ |
| `fn_revision_draft`, `fn_revision_create`, `fn_revision_delete_draft` | function | F5 | ✅ | ✅ |
| `fn_bom_check_material`, `fn_bom_create_cells`, `fn_bom_add_line`, `fn_bom_add_sub`, `fn_bom_replace_material`, `fn_bom_set_supplier`, `fn_bom_cell_set`, `fn_rev_article_set` | function | F5 | ✅ | ✅ |
| `v_bom_grid`; `v_model_list`, `v_article_status` diperluas (kolom status specsheet) | view | F5 | ✅ | ✅ |
| `fn_bom_delete_line` | function | F5b | ✅ | ✅ (query `a_bom_delete_line` + uji user) |
| `change_log` + `idx_change_log_revision` | tabel | F6 | ✅ | ✅ |
| `v_revision_checklist`, `fn_revision_publish` | view/function | F6 | ✅ | ✅ |
| `cbd_revision` + `uq_one_cbd_draft`, `fn_cbd_revision_lock`/`trg_cbd_revision_lock` | tabel/trigger | F7 | ✅ | ✅ |
| `cbd_line` + `idx_cbd_line_revision`, `fn_cbd_line_lock`/`trg_lock_published` | tabel/trigger | F7 | ✅ | ✅ |
| `fn_spec_latest_pub`, `fn_cbd_article_spec_status`, `fn_cbd_draft`, `fn_cbd_group_code`, `fn_cbd_identity`, `fn_cbd_expected_lines`, `fn_cbd_populate`, `fn_cbd_create`, `fn_cbd_delete_draft`, `fn_cbd_line_set` | function | F7 | ✅ | ✅ |
| `v_cbd_line`, `v_cbd_article`; `v_article_status` diperluas (kolom CBD) | view | F7 | ✅ | ✅ |
| `fn_cbd_populate` (versi `cbd_line[]`, versi F7 di-DROP), `fn_cbd_create` diperbarui | function | F8 | ✅ | ✅ (pg_proc: hanya versi `cbd_line[]`) |
| `v_cbd_price_check`, `v_cbd_recap`, `v_cbd_checklist` | view | F8 | ✅ | ⬜ (cek skema belum dikirim) |
| `fn_cbd_price_line`, `fn_cbd_check_price`, `fn_cbd_set_quotation`, `fn_cbd_override_price`, `fn_cbd_clear_override`, `fn_cbd_refresh_prices`, `fn_cbd_refresh_from_spec`, `fn_cbd_header_set`, `fn_cbd_publish` | function | F8 | ✅ | ⬜ (cek skema belum dikirim) |
| `fn_cbd_sync_spec`; `fn_revision_publish` diperbarui (penandaan sinkron) | function | F8 | ✅ | ⬜ (cek skema belum dikirim) |
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
| `cwLogin` | `Login` | F1 | ✅ | ✅ |
| `cwHeader` *(dibuat user)* | `Beranda`, `Admin` (+ page lain) | F1 | ✅ | ✅ |
| `cwMenu` *(dibuat user)* | `Beranda` | F1 | ✅ | ⚠️ target page salah (T1) |
| `cwUserForm` *(dibuat user)* | `Admin` (modal `mdlUser`) | F1 | ✅ | ✅ |
| `cwTempPassword` *(dibuat user)* | `Admin` (modal `mdlPasswordSementara`) | F1 | ✅ | ✅ |
| `cwSupplierForm` | `Master Supplier` (modal `mdlSupplier`) | F2 | ✅ | ✅ |
| `cwKomponenForm` | `Master Komponen` (modal `mdlKomponen`) | F2 | ✅ | ✅ |
| `cwMaterialForm` | `Master Material` + `Material Detail` (modal `mdlMaterial`) | F3 | ✅ | ✅ |
| `cwLinkForm` | `Material Detail` (modal `mdlLink`) | F3 | ✅ | ✅ |
| `cwPriceForm` | `Material Detail` (modal `mdlHarga`) | F3 | ✅ | ✅ |
| `cwReasonForm` (umum, dipakai ulang) | `Material Detail` (modal `mdlTolakHarga`) | F3b | ✅ | ✅ |
| `cwModelForm` | `Model List` + `Model Detail` (modal `mdlModel`) | F4 | ✅ | ✅ |
| `cwSeasonForm` | `Model Detail` (modal `mdlSeason`) | F4 | ✅ | ✅ |
| `cwArticleForm` | `Model Detail` (modal `mdlArticle`) | F4 | ✅ | ✅ |
| `cwStepper` | `Specsheet`, `CBD` (+ baris chip article, event `onArticle`) | F5 / F7 | ✅ | ✅ (kode sama di kedua page) |
| `cwRevisionForm` | `Specsheet` (modal `mdlRevisi`) | F5 | ✅ | ✅ |
| `cwBomGrid` | `Specsheet` | F5 | ✅ | ✅ (termasuk tombol Hapus F5b, v5.5) |
| `cwPublishForm` | `Specsheet` (modal `mdlTerbit`); `CBD` (modal `mdlCbdTerbit`, F8 — opsi `blockedWhere`) | F6 / F8 | ✅ | ✅ (v8.1, kode sama di kedua page) |
| `cwCbdForm` | `CBD` (modal `mdlCbdBaru`) | F7 | ✅ | ✅ |
| `cwCbdGrid` | `CBD` (+ rekap, banner, tombol harga F8) | F7 / F8 | ✅ | ✅ (kode F8 identik; tinggi → T40) |
| `cwCbdPriceForm` | `CBD` (modal `mdlCbdHarga`) | F8 | ✅ | ✅ (kode identik, event & Default model sesuai) |

---

## 9. Log review export

| Versi | Tanggal | Fase | Hasil review |
|---|---|---|---|
| v1 | 25 Sep 2026 | F0 + F1 | ✅ Lolos, semua uji user berhasil. Skema DB sesuai register (F1 + F1b lengkap, objek lama sudah di-DROP). Query & `Auth`/`Util`/`LoginCtrl` identik dengan file repo; `cwLogin` identik (hanya diformat ulang Appsmith). Deviasi atas keputusan user: 4 Custom Widget tambahan (kode disalin ke `widgets/`), `AdminCtrl` ditulis ulang untuk `cwUserForm` (disalin ke `js/AdminCtrl.js`), nama page memakai spasi, filter audit pakai tombol **Cari**, panel detail before/after audit tidak dibuat. Temuan T1–T6 di bawah. |
| v2 | 29 Sep 2026 | F2 | ✅ Lolos, semua uji user berhasil. Skema DB: semua objek F2 ada (`supplier`, `component_group`, `component`, `fn_has_perm`, `fn_auth_any`, `fn_supplier_check`, `fn_component_check`, `fn_component_add`, trigger). Query, `SupplierCtrl`, `KomponenCtrl`, `Auth` (`requiredPerm`, `pageQueries`) identik dengan repo; `cwSupplierForm`/`cwKomponenForm` identik (teks info supplier dipersingkat user → disalin ke repo). Deviasi: filter & cari pakai tombol **Cari** (sama seperti Audit Log), bukan otomatis. T1, T3–T8 sudah diperbaiki; T2 belum. Temuan baru T9–T12. |
| v3 | 29 Sep 2026 | F3 | 🟡 Uji user lolos. Semua 14 query F3 identik dengan panduan; `MaterialCtrl`, `MaterialDetailCtrl`, `Auth` (izin + `pageQueries`) identik dengan repo; `cwMaterialForm`/`cwLinkForm`/`cwPriceForm` identik; event & Default model sesuai. T9 & T10 sudah diperbaiki. **Terlewat:** kolom tombol **Ganti harga** & **Akhiri** di `tblPrices` (T13). Temuan T13–T17. Hasil cek skema F3 belum dikirim. |
| v3b | 30 Sep 2026 | F3b (+ perbaikan T13–T17) | ✅ File dari user `export_v4.json`, lalu `export_v4.5.json` (setelah perbaikan T18–T20) — versi terakhir disimpan sebagai `export_v3b.json`. Semua 17 query Master Material & Material Detail identik dengan panduan; `a_price_end` & `a_price_cancel` konfirmasi ON; query baca Manual. `MaterialCtrl`, `MaterialDetailCtrl` identik; kode `cwMaterialForm`, `cwLinkForm`, `cwPriceForm`, `cwReasonForm` identik, event & Default model sesuai. T13–T16 ✅. Deviasi (diterima): tombol **Batalkan** tidak tampil untuk Master Admin (admin memakai Tolak). Temuan T18–T20; di export v4.5: T18 ✅, T19 ✅, T20 sebagian (kosmetik tersisa). |
| v4 | 30 Sep 2026 | F4 | 🟡 File dari user `export_v4.6.json` → `export_v4.json`. Cek skema: semua objek F3, F3b, F4 ada (register ✅). Semua 14 query F4 identik dengan panduan (prepared statements ON, konfirmasi `a_article_delete`/`a_attachment_delete` ON, timeout `a_attachment_add` 30 s). `ModelCtrl`, `ModelDetailCtrl`, `Util` identik; `Auth` (izin + `pageQueries`) sesuai. `cwModelForm`/`cwSeasonForm`/`cwArticleForm` identik (hanya format), event & Default model sesuai; `fpLampiran` sesuai (Base64, 1 file, 5 MB, jpg/png/pdf). Deviasi (diterima): beberapa tombol dinonaktifkan (Disabled) alih-alih disembunyikan; kolom tombol memakai *Cell visible*; modal lebar ±780–1090 px & *close on outside click* ON (sama dengan keputusan T11/T12). Temuan T21–T27. **Update v4.7** (disimpan menimpa `export_v4.json`): T21–T27 ✅ terverifikasi, user: semua uji lolos. Keputusan user 30 Sep 2026: article **tidak** di-copy antar season (hanya struktur specsheet yang di-copy, F5) → Copy Article dihapus. |
| v5 | 30 Sep 2026 | F5 | 🟡 Cek skema: semua objek F5 ada (register ✅), `fn_article_copy` sudah di-DROP. Semua 17 query F5 page Specsheet identik dengan panduan (prepared ON, `a_revision_delete` konfirmasi ON); `q_models`/`q_articles` diperbarui sesuai. `SpecCtrl` (teks *…dahulu* dari user, disalin ke repo), `BomCtrl`, `ModelCtrl`, `ModelDetailCtrl`, `Util` identik; `Auth` sesuai. `cwStepper`, `cwRevisionForm`, `cwBomGrid` identik (hanya format); event & Default model sesuai. Deviasi (diterima): `btnBukaCbd` Disabled bukan disembunyikan, `selSpecSeason` filterable, modal `mdlRevisi` lebar 1190 px. User: semua uji lolos. Temuan T28–T29 + 3 permintaan user (grid tampil tanpa revisi, tombol kembali selalu ke Model Detail, tidak ada hapus baris BOM) → perbaikan `steps/F5_langkah.md` §6. |
| v7 | 30 Sep 2026 | F7 (+ sisa F6) | ✅ Cek skema: semua objek F7 ada. 10 query page CBD + `q_articles` identik dengan panduan (prepared ON, semua Manual, `a_cbd_delete` konfirmasi ON); `CbdCtrl`, `CbdGridCtrl`, `ModelDetailCtrl`, `SpecCtrl` identik dengan repo; `Auth` CBD (`view_cbd`, `pageQueries`) sesuai; `cwStepper` (Specsheet & CBD), `cwCbdForm`, `cwCbdGrid` identik (hanya format), event `onSelect`/`onArticle`/`onAction`/`onSave`/`onCancel` & Default model sesuai; kolom **CBD** di `tblArticles` sesuai; `cwHeader` CBD pola logout terbaru. Sisa F6: T30 ✅, T31 label ✅ (Search masih ON). Deviasi (diterima): tombol Disabled alih-alih disembunyikan, `mdlCbdBaru` lebar 902 px. User: semua uji lolos (hasil E3 F6 & Q-cbd tidak dikirim). Temuan T34–T36. |
| v7.1 | 30 Sep 2026 | F7 perbaikan | ✅ File dari user `export_v7.1.json` (disimpan menimpa `export_v7.json`). `Query1` di Specsheet dihapus (T34 ✅), tidak ada query uji lain; `cwCbdGrid` tinggi ±570 px (T35 ✅); `txtCbdJudul`/`btnBukaSpec` (T36 rename ✅). Hanya page CBD berubah + `Query1` terhapus; query & JSObject lain identik dengan v7. Sisa kosmetik: Search `tblRiwayat` ON. |
| v8 | 5 Okt 2026 | F8 | 🟡 File dari user (Downloads) → `export_v8.json`. 10 query F8 + `q_cbd_lines` identik dengan panduan (prepared ON; konfirmasi `a_cbd_clear_override`/`a_cbd_refresh_spec` ON, `a_cbd_publish` OFF). `CbdCtrl`, `CbdGridCtrl` identik dengan repo; `cwCbdGrid` (HTML/CSS/JS, CSS hanya diformat), `cwCbdPriceForm`, `cwStepper`, `cwCbdForm` identik; event & Default model semua Custom Widget sesuai (handler CBD, bukan Specsheet). Tombol `btnCbdRiwayat` / `btnCbdTerbitkan` sesuai (pola Disabled); `tblCbdRiwayat` data & kolom sesuai (`source_label` disembunyikan); `btnRiwayatTutup` menutup `mdlCbdRiwayat`. Tidak ada `Query1`; query & widget page lain tidak berubah dari v7. Deviasi (diterima, pola user): modal lebar 854 / 1038 / 1104 px, judul + tombol Tutup di `mdlCbdRiwayat`. Temuan T37–T41. Hasil uji A–E, Q-cbd, dan cek skema belum dikirim. |
| v8.1 | 5 Okt 2026 | F8 perbaikan | 🟡 File dari user `export_v8.1.json` (disimpan menimpa `export_v8.json`). T37 (3 query baca Manual), T38 (modal harga & terbit tidak tertutup klik luar), T39 (`cwPublishForm` JS baru di Specsheet & CBD) ✅; judul riwayat per article ✅. Cek alur JSON: sintaks semua JSObject & Custom Widget page CBD lolos parser JS; semua query/widget/modal yang dirujuk ada; params setiap `.run()` / `exec()` cocok dengan `this.params` query; handler event Custom Widget menunjuk fungsi yang ada. `fn_cbd_populate` hanya satu (versi `cbd_line[]`) ✅. Sisa: T40 tinggi grid 570 px, Search `tblCbdRiwayat` ON. Uji A–E ditunda ke uji end-to-end di akhir (keputusan user 5 Okt 2026). |
| v6 | 30 Sep 2026 | F6 | 🟡 User: cek skema berhasil. 3 query F6 identik dengan panduan (prepared ON, Manual, `a_revision_publish` konfirmasi OFF); `SpecCtrl` identik dengan repo; `cwPublishForm` identik (hanya format), Default model & event `onPublish`/`onCancel` sesuai; `tblRiwayat` data & kolom Waktu sesuai. Tidak ada `Query1`; page lain tidak berubah dari v5. Deviasi (diterima, pola v4): `btnTerbitkan` & `btnHapusDraft` **Disabled** `{{!SpecCtrl.editable()}}` alih-alih disembunyikan. Audit log: hanya **1** terbit lewat F6 (`change_log` 1 baris, MATERIAL) → uji B1, C4–C6, E2 belum terbukti (T33). Temuan T30–T33. |
| v5.5 | 30 Sep 2026 | F5 perbaikan + F5b | ✅ File dari user `export_v5.5.json` (disimpan menimpa `export_v5.json`). 8 query baca Specsheet Manual (T28 ✅); `a_bom_delete_line` sesuai panduan; `ModelCtrl`, `ModelDetailCtrl`, `SpecCtrl`, `BomCtrl` identik dengan repo; `cwBomGrid` JS/CSS identik (hanya format), Visible `{{!!SpecCtrl.revision()}}` (U1 ✅); `btnKembali` = `{{SpecCtrl.backLabel()}}` (U2, T29 ✅); tombol Hapus baris (U3/F5b ✅). Tidak ada `Query1`. User: semua uji lolos. |

### Temuan review v1 (diperbaiki sebelum/bersama F2)

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T1 | **Bug** | `cwMenu` memakai `target: 'Master_Material'` dan `'Model_List'`, padahal nama page di app `Master Material` / `Model List` → menu Master & Model tidak bisa dibuka (tidak terlihat oleh System Admin, jadi lolos uji) | Ubah target di Default model `cwMenu` menjadi `'Master Material'` dan `'Model List'` | ✅ v2 |
| T2 | **Bug (kemungkinan)** | Kolom tanggal memakai `currentRow["Login terakhir"]` (`tblUsers.last_login_at`) dan `currentRow["Created At"]` (`tblAudit.created_at`) — `currentRow` memakai nama kolom data, bukan label → semua baris menampilkan waktu sekarang / "Invalid date" | Computed value: `{{Util.fmtDateTime(currentRow.last_login_at)}}` dan `{{Util.fmtDateTime(currentRow.created_at)}}` | ➖ dibiarkan (keputusan user 29 Sep 2026) |
| T3 | Kecil | Run behaviour `q_me`, `q_users`, `q_audit_entities` = *Automatic* → jalan sebelum `Auth` mengecek sesi (dobel, dan memunculkan error saat sesi habis) | Set ke **Manual** (sudah dijalankan oleh `Auth.onPageLoad` / `pageQueries`) | ✅ v2 (Beranda/Admin) · sisa `q_me` di page lain → T10 |
| T4 | Kecil | `selAuditEntitas` punya Default value sisa template `GREEN` | Kosongkan Default selected value | ✅ v2 |
| T5 | Kecil | `a_user_reset_password`: *Request confirmation before running* OFF → reset langsung jalan tanpa konfirmasi | Nyalakan (atau konfirmasi di widget) | ✅ v2 |
| T6 | Kecil | `mdlPasswordSementara` bisa tertutup dengan klik di luar modal (password sementara hanya tampil sekali) | *Quick dismiss* / close on outside click **OFF** | ✅ v2 |
| T7 | **Bug** | Keluar lewat URL `Login?mode=keluar` tersimpan di riwayat browser: setelah login ulang, tombol **Back** kembali ke URL itu dan user ikut ter-logout | `LoginCtrl` baru (flag `appsmith.store.doLogout`, tidak lagi membaca `?mode=keluar`) + event `onLogout` di `cwHeader` (Beranda & Admin): `{{storeValue('doLogout', true).then(() => navigateTo('Login'))}}` | ✅ v2 (Beranda/Admin) · page baru → T9 |
| T8 | Kecil | `txtIzin` (teks uji sementara berisi daftar izin) masih ada di Beranda | Hapus widget, Deploy | ✅ v2 |

### Temuan review v2

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T9 | **Bug** | `cwHeader` di `Master Supplier` & `Master Komponen` masih `onLogout: {{navigateTo('Login', { mode: 'keluar' })}}` (disalin sebelum T7). `LoginCtrl` tidak lagi membaca `?mode=keluar` → tombol **Keluar** tidak logout; token masih valid sehingga Login langsung kembali ke Beranda | Event `onLogout` di kedua page: `{{storeValue('doLogout', true).then(() => navigateTo('Login'))}}`. Page lain: salin `cwHeader` dari Admin/Beranda, bukan dari page lama | ✅ v3 |
| T10 | Kecil | `q_me` = *Automatic* di 9 page (semua kecuali Beranda & Admin, termasuk Login) → jalan dobel sebelum `Auth`/`LoginCtrl` | Set **Manual** di semua page | ✅ v3 (sisa: `q_me` di Login masih Automatic — lihat T17) |
| T11 | Kecil | Tinggi `cwKomponenForm` 430 px, isi terpanjang (vendor + pesan error + info usulan) ±490 px → tombol Simpan terpotong/harus scroll. Lebar modal 884 px & 736 px (rencana ±480 px) | `mdlKomponen`: tinggi ±540, `cwKomponenForm` ±520 px; `mdlSupplier` tinggi ±360, widget ±340 px; lebar kedua modal ±480–520 px | ➖ dibiarkan (keputusan user 29 Sep 2026) |
| T12 | Kecil | `mdlSupplier` & `mdlKomponen`: *close on outside click* ON → klik di luar modal menutup form dan isian hilang | Matikan (tutup lewat Batal / ✕) | ➖ dibiarkan (keputusan user 29 Sep 2026) |

### Temuan review v3

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T13 | **Terlewat** | `tblPrices` tidak punya kolom tombol **Ganti harga** dan **Akhiri** → harga tidak bisa diakhiri dari UI (mis. harga khusus warna yang sudah tidak berlaku); `MaterialDetailCtrl.endPrice()` tidak dipakai | Tambah 2 kolom Button sesuai `steps/F3_langkah.md` §3c (Cell visible `{{!currentRow.valid_to}}`) | ✅ v3b |
| T14 | **Bug** | `a_price_end`: *Request confirmation before running* **OFF** (panduan: ON) → begitu tombol Akhiri ada, harga langsung diakhiri tanpa konfirmasi | Nyalakan | ✅ v3b |
| T15 | Sedang | 5 query baca di `Material Detail` (`q_material`, `q_material_meta`, `q_links`, `q_link_supplier_options`, `q_prices`) = *Automatic* → jalan sebelum `Auth` dan di luar `pageQueries`; untuk Vendor Spec `q_prices` ditolak DB → muncul toast error *tidak punya akses* (data harga tetap aman) | Set **Manual** | ✅ v3b |
| T16 | Kecil | Kolom `price` (`tblPrices`) & `supplier_count` (`tblMaterials`) bertipe **Number** padahal Computed value berupa teks terformat → berisiko tampil salah (mis. `45.000` terbaca 45) | Column type **Text** | ✅ v3b |
| T17 | Kecil | Kolom **Metode Harga** disembunyikan lewat *Cell visible* → judul kolom tetap tampil untuk Vendor Spec; label `Kategory`; `q_me` di Login masih *Automatic* | Visible (kolom) `{{MaterialCtrl.canViewPrice()}}`; label `Kategori`; `q_me` Login → Manual | 🟡 label ✅; sisanya → T20 |

### Temuan review v3b

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T18 | **Bug** | Kolom `state` (Keterangan) di `tblPrices` belum diganti: Computed value masih `currentRow["state"]` dan Text color mapping lama → **alasan penolakan tidak terlihat** oleh tim CBD (`reject_reason` disembunyikan), MENUNGGU APPROVAL & DITOLAK berwarna abu-abu | Computed value `{{MaterialDetailCtrl.stateText(currentRow)}}`, Text color `{{MaterialDetailCtrl.stateColor(currentRow.state)}}` (`steps/F3b_langkah.md` §3c) | ✅ v3b (export v4.5) |
| T19 | Sedang | Cell visible tombol **Ganti Harga** & **Akhiri** masih `!currentRow.valid_to` → tombol juga muncul di baris usulan (MENUNGGU APPROVAL) dan DITOLAK; Akhiri di baris itu ditolak DB, Ganti Harga membuka form yang langsung terblokir | Tambah `&& currentRow.status === 'APPROVED'` di Cell visible kedua tombol | ✅ v3b (export v4.5) |
| T20 | Kecil | Sisa T17: kolom **Metode Harga** masih disembunyikan lewat *Cell visible* (judul kolom tetap tampil untuk Vendor Spec); `q_me` di Login masih *Automatic*; label switch `swMaterialHargaPending` = `Approval` | Kolom: Visible `{{MaterialCtrl.canViewPrice()}}` (kalau tidak bisa di-binding, biarkan); `q_me` Login → Manual; label `Harga menunggu approval` | 🟡 `q_me` Login ✅; judul kolom Metode Harga & label switch `Approval` belum (kosmetik) |

### Temuan review v4

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T21 | **Keamanan** | Query `Query1` di page `Model Detail` (query cek skema) dan `Admin` (`fn_price_lookup` MTR-0001 / PT Maju Jaya) ada di app **publik** tanpa `fn_auth` → siapa pun bisa menjalankannya lewat API app (daftar objek DB / harga material) | Hapus kedua `Query1`; query uji hanya di app **DB Tools** | ✅ v4.7 |
| T22 | **Bug** | `q_articles` & `q_attachments` = *Automatic* → ikut jalan saat page dibuka tanpa params (hasil kosong) dan bisa selesai **setelah** `ModelDetailCtrl.init()` → tabel article tampil kosong padahal ada data | Set **Manual** | ✅ v4.7 |
| T23 | Sedang | `tblArticles` kolom **Hapus**: Cell visible hanya `{{ModelDetailCtrl.canEdit()}}` — kurang `!currentRow.is_used` → tombol muncul di article yang sudah dipakai (DB tetap menolak, tapi membingungkan) | Cell visible: `{{ModelDetailCtrl.canEdit() && !currentRow.is_used}}` | ✅ v4.7 |
| T24 | Sedang | `btnSeasonTambah` Visible diawali karakter **Tab** (`	{{…}}`) → dibaca sebagai teks, bukan boolean → tombol bisa tampil untuk semua role (Brand/Vendor CBD; simpan ditolak DB) | Hapus Tab di depan `{{` (juga di `txtModelJudul`, kosmetik) | ✅ v4.7 |
| T25 | Kecil | `tblLampiran`: label tertukar (`created_at` = "Oleh", `created_by` = "Diunggah") dan `created_at` tanpa format | `created_by` → label `Oleh`; `created_at` → label `Diunggah`, Computed value `{{Util.fmtDateTime(currentRow.created_at)}}` | ✅ v4.7 |
| T26 | Kecil | Kolom `attachment_count` (`tblArticles`) & `size_bytes` (`tblLampiran`) bertipe **Number** padahal Computed value berupa teks (`1 file`, `12 KB`) — sama dengan T16 | Column type **Text** | ✅ v4.7 |
| T27 | Kosmetik | `cwHeader` di `Model Detail`: `pageTitle: 'Model List'` | `pageTitle: 'Model Detail'` | ✅ v4.7 |

### Temuan review v5

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T28 | **Bug** | 8 query baca page Specsheet (`q_spec_models`, `q_spec_model`, `q_spec_seasons`, `q_revisions`, `q_rev_articles`, `q_bom_grid`, `q_bom_options`, `q_season_colors`) = *Automatic* → ikut jalan tanpa params saat page dibuka; bisa selesai setelah `SpecCtrl.init()` sehingga stepper/grid kosong (sama dengan T22) | Set **Manual** | ✅ v5.5 |
| T29 | Kosmetik | Label `btnKembali` diakhiri karakter Tab | Diganti `{{SpecCtrl.backLabel()}}` (§6c) | ✅ v5.5 |
| U1 | Permintaan user | `cwBomGrid` selalu tampil walau belum ada revisi | Visible `{{!!SpecCtrl.revision()}}` | ✅ v5.5 |
| U2 | Permintaan user | Tombol kembali selalu ke Model Detail walau dibuka dari Model List | Parameter `from` (`list`/`detail`) dari Model List / Model Detail, `SpecCtrl.backLabel()` | ✅ v5.5 |
| U3 | Permintaan user | Tidak ada hapus baris BOM | F5b: `fn_bom_delete_line` + tombol **Hapus** (klik dua kali) di `cwBomGrid` | ✅ v5.5 |

### Temuan review v6

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T30 | Kecil | `mdlTerbit`: *close on outside click* ON → klik di luar modal menutup form, kategori & alasan hilang (sama dengan T12) | Matikan | ✅ v7 |
| T31 | Kosmetik | `tblRiwayat`: label kolom `category` = `Category` (panduan `Kategori`); Search tampil | Label `Kategori`, Search OFF | 🟡 label ✅; Search → T36 |
| T32 | Kosmetik | Modal `mdlTerbit` lebar 970 px & `mdlRiwayat` 1104 px (panduan ±560 / ±900) | Opsional | ⬜ |
| T33 | **Uji** | Audit log hanya mencatat 1 terbit lewat F6 (2 baris lain = terbit manual DB Tools saat uji F5, tanpa change log). Belum terbukti: B1 terbit revisi awal dengan alasan kosong (*Revisi awal.*, kategori Lainnya), C4–C6 revisi berikutnya/stage berikutnya, E2 penolakan DB dari dua tab | Jalankan B, C, E lalu kirim hasil query E3 (harus ≥ 4 baris `change_log`) | 🟡 user: lolos (v7); hasil E3 belum dikirim |

### Temuan review v7

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T34 | **Keamanan** | `Query1` di page `Specsheet` (query uji E3 `SELECT … FROM change_log`) ada di app **publik** tanpa `fn_auth` → siapa pun bisa membaca change log lewat API app (sama dengan T21) | Hapus `Query1`; query uji hanya di app **DB Tools** | ✅ v7.1 |
| T35 | Kecil | `cwCbdGrid` tinggi ±300 px (panduan ±600) → hanya ±8 baris terlihat, sisanya scroll di dalam widget | Tinggi ±600 px | ✅ v7.1 (±570 px) |
| T36 | Kosmetik | Widget di page CBD masih bernama dari Specsheet: `txtSpecJudul`, `btnBukaCbd` (panduan `txtCbdJudul`, `btnBukaSpec`); sisa T31: Search `tblRiwayat` ON | Rename (tidak ada kode yang merujuk nama ini); Search OFF | 🟡 rename ✅ v7.1; Search `tblRiwayat` masih ON (kosmetik, dibiarkan) |

### Temuan review v8

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T37 | **Bug** | `q_cbd_recap`, `q_cbd_checklist`, `q_cbd_change_log` = *Automatic* → jalan tanpa params saat page dibuka dan bisa selesai setelah `CbdCtrl.init()` → rekap / riwayat kosong (sama dengan T22/T28) | Set **Manual** | ✅ v8.1 |
| T38 | Sedang | `mdlCbdHarga` & `mdlCbdTerbit`: *close on outside click* ON → klik di luar modal menutup form, harga/alasan/kategori hilang (sama dengan T30) | Matikan | ✅ v8.1 |
| T39 | Kecil | Kode JS `cwPublishForm` di **CBD dan Specsheet** masih versi F6 (tidak ditempel ulang) → di CBD pesan blokir *Perbaiki N hal di atas di grid BOM…* (opsi `blockedWhere` tidak terbaca) | Tempel ulang tab JavaScript `widgets/cwPublishForm/script.js` di kedua page | ✅ v8.1 (kedua page) |
| T40 | Kecil | `cwCbdGrid` tinggi 570 px (panduan ±680): banner + rekap memakan ±110 px → baris grid yang terlihat tinggal ±6–8 | Tinggi ±680 px | ⬜ masih 570 px |
| T41 | Kosmetik | `tblCbdRiwayat` Search ON; `txtRiwayatJudul` = *Riwayat terbit — <season>* padahal riwayat CBD per **article** | Search OFF; Text `{{'Riwayat CBD — ' + ((CbdCtrl.article() || {}).code || '')}}` | 🟡 judul ✅ v8.1; Search masih ON |

Catatan lain:
- Nama app di Appsmith "Test Database" dan datasource `Prestasi` (rencana: "Sistem Specsheet & CBD" / `pg_main`) — tidak memengaruhi fungsi. **User akan merapikan nama app sebelum handover** (dicek lagi di F11).
- Database **dipakai bersama aplikasi lain** (dikonfirmasi user; tabel `master_store`, `master_store_mapping` bukan milik proyek ini). Aturan: semua objek proyek ini memakai nama sendiri (`app_*`, `fn_*`, `v_*`, tabel bisnis proyek) dan **jangan pernah** menyentuh tabel lain; cek bentrok nama sebelum membuat tabel baru. Untuk produksi disarankan database/schema terpisah (dicatat untuk F11).
- Export v1 mencatat `isPublic: false`; karena uji incognito berhasil, kemungkinan hanya tidak ikut ter-export.
