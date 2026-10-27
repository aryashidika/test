# PLAN - Migrasi Sistem Specsheet & CBD ke Appsmith

| | |
|---|---|
| Sumber (hanya dibaca) | `app/` (Flask + htmx + SQLite), `run_web.py`, `tests/` |
| Folder kerja | `appsmith/` - file ini + `exports/export_vN.json` |
| Target | Appsmith **v2.4** self-hosted (HTTPS) + PostgreSQL **16.15** (datasource `pg_main`) |
| Akses | App **publik** dengan login di dalam app (email + password), bukan akun Appsmith |
| Data lama | Tidak dimigrasi (mulai dari DB kosong) |
| Status | Rencana disetujui 24 Sep 2026 (termasuk P1–P3) · login in-app disetujui 25 Sep 2026 · UI campuran + Custom Widget disetujui 25 Sep 2026 · **F0 + F1 selesai** (export v1, 25 Sep 2026) · **F2 selesai** (export v2, 29 Sep 2026) · **F3 dikerjakan** (export v3, 29 Sep 2026; T13–T17 diperbaiki user) · **F3 + F3b selesai** (export v3b, 30 Sep 2026) · **F4 selesai** (export v4 = file user v4.7, 30 Sep 2026; Copy Article dihapus - keputusan user) · **F5 + F5b selesai** (export v5 = file user v5.5, 30 Sep 2026) · **F6 selesai** (export v6; uji ulang dilaporkan lolos di v7) · **F7 selesai** (export v7 = file user v7.1, 30 Sep 2026; T34–T35 diperbaiki) · **F8 dikerjakan** (export v8.1, 5 Okt 2026; uji ditunda ke end-to-end) · **F8b dikerjakan** (export v8b; T42) · **F9 dikerjakan** (export v9 = file user v9.5, 5 Okt 2026; uji ditunda ke end-to-end) · **F10 + E2E + F10b/F10c selesai** (export v11 = file user v10.5, 6 Okt 2026; uji E2E lolos, sisa T49–T52 kosmetik/kecil) · **F11 setelah UAT & go-live** (keputusan user 6 Okt 2026) · **Revisi besar R1–R7 direncanakan 8 Okt 2026** · **R1 selesai** (`export_r1.json`, 8 Okt 2026) · **R2 + R2b selesai** (`export_r2.json`, 8 Okt 2026) · **R3–R7 dibuat sekaligus** (11 Okt 2026, satu SQL `sql/R_revisi_semua.sql` + satu import `exports/build_r7.json`; diverifikasi di PostgreSQL 16 lokal) → E2E-R (material per warna/thickness, role baru, pemisahan pabrik, model tanpa kode, copy lintas model - lihat §2 "Revisi besar" dan §6 R) |
| File siap tempel | `steps/F<n>_langkah.md` (langkah per fase: query, widget, uji), `sql/F<n>_*.sql` (jalankan lewat `z_run_sql` di app privat **DB Tools**), `js/*.js` (isi JSObject), `widgets/<cw>/` (Custom Widget: HTML/CSS/JS + README kontrak) |
| Mulai R1 | Saya mengedit JSON app langsung → `exports/build_rN.json`, Anda **import sebagai app baru** (keputusan user 8 Okt 2026, lihat §6 "Alur kerja R") |

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
| F8b | CBD: Cost recapitulation (baris biaya) + Harga jual di bawah grid, subtotal grup (permintaan user 5 Okt 2026) | `export_v8b.json` | 🟡 export v8b direview 5 Okt 2026 · T42 ✅ (v9.5) · uji ditunda ke end-to-end |
| F9 | Export Excel specsheet & CBD | `export_v9.json` | 🟡 export v9.5 direview 5 Okt 2026 (T43–T44 terpasang) · uji X1–X9 ditunda ke end-to-end |
| F10 | Beranda "Tugas Saya" | `export_v10.json` | ✅ export v10.1 (T45 diperbaiki); uji H1–H17 lolos lewat E2E (6 Okt 2026) |
| F10b | Revisi dari uji E2E (laporan user 5 Okt 2026, uji sampai G8): 14 keluhan - lihat §6 F10b | `export_v11.json` | ✅ export v11 (file user v10.5, 6 Okt 2026); uji G8–J lolos; sisa T49–T52 (→ R1) · usulan F10d (blokir terbit bila supplier/pasangan INACTIVE) **disetujui 8 Okt 2026 → R3/R4** |
| E2E | Uji end-to-end dari DB kosong (keputusan user 5 Okt 2026: hapus semua data kecuali akun System Admin, semua data diinput lewat UI, audit log dihapus) - gabungan uji tertunda F8 A–E, F8b G, F9 X, F10 H | – | ✅ lolos 6 Okt 2026 (uji lanjut dari G8 pada data yang ada; selisih angka terjelaskan oleh input data, bukan bug) |
| R1 | Fondasi revisi: master Pabrik, user menempel ke pabrik, role baru (Master Admin dihapus, Manager Costing), matriks izin, reset data uji, T49–T52 | `build_r1.json` → `export_r1.json` | ✅ uji A1–A13 lolos (laporan user 8 Okt 2026) · tombol **Ubah** di `tblFactories` tidak tampil (bug build: id kolom salinan tidak diganti) → ditambahkan user manual; skrip & validator diperbaiki · `export_r1.json` diterima 8 Okt 2026 (= base R2; T53) |
| R2 | Master tanpa approval: supplier & komponen bersama, Material Induk + Varian per pabrik, pilihan model (dropdown) | `build_r2.json` → `export_r2.json` | ✅ `build_r2.json` → dirapikan user (`export_r2a.json`) → revisi **R2b** (varian satu baris seperti ERP) `build_r2b.json`; uji B1–B17 lolos (laporan user 8 Okt 2026); `export_r2.json` = build R2b tanpa perubahan (= base R3) |
| R3 | Harga Varian × Supplier, pengajuan banyak varian, salin harga, approval Manager Costing | `build_r3.json` (base R4) | 🟡 dibuat 11 Okt 2026, dicek (parser SQL, validator, harness widget & JSObject) - diuji di E2E-R |
| R4 | Model tanpa kode (dropdown, ukuran ala kalender, gender) + Specsheet per varian (sel kuning, ketik kode, shortcut daftar) + F10d | `build_r4.json` (base R5) | 🟡 dibuat 11 Okt 2026 · SQL dijalankan di PostgreSQL 16 lokal + self-test 55 cek lolos · 132 query app lolos EXPLAIN · harness widget & JSObject |
| R5 | CBD per varian, blokir harga menunggu, PO SMS × 1,25, Selling price & Margin keluar dari CBD (simulasi Brand) | `build_r5.json` (base R6) | 🟡 dibuat 11 Okt 2026 · SQL di PostgreSQL lokal + self-test (R3–R5) lolos · 132 query EXPLAIN · harness |
| R6 | Tugas Saya per role baru, Brand lintas pabrik, export Excel (Material Code, PO SMS), sapu bersih filter pabrik | `build_r6.json` (base R7) | 🟡 dibuat 11 Okt 2026 · self-test R3–R6 lolos · 134 query EXPLAIN |
| R7 | Copy lintas model (specsheet & CBD, pabrik + kategori sama) | `build_r7.json` → **`export_r7.json`** (file user `export_v12.json`, 12 Okt 2026) | ✅ lolos E2E-R |
| E2E-R | Uji end-to-end ulang dari DB kosong dengan **2 pabrik** - panduan `steps/E2E_R_uji.md` (pasang: `RESET_data_bisnis` → `R_revisi_semua` → `R_selftest` → import `build_r7.json`) | – | ✅ lolos semua (laporan user 12 Okt 2026) setelah perbaikan manual: antrean aksi `cwBomGrid`/`cwCbdGrid` (warna/Yield hilang saat ketik cepat), `a_cbd_override_price` tak terdefinisi; 5 catatan → R8 |
| R10 | Hapus varian yang tidak dipakai (manual, tanpa build) | – (tempel manual: SQL R10, `q_variants`, `a_variant_delete`, `MaterialDetailCtrl.deleteVariant`, kolom Hapus `tblVariants`) | 🟡 dibuat 12 Okt 2026 · self-test 121 cek lolos |
| R9 | Material Code: isi otomatis (usulan) + kamus kode tiga tingkat (tolak / konfirmasi / info); awalan kembali info - panduan `steps/R9_uji.md` | **`build_r9.json` (di-import)** (base `build_r8.json`) | 🟡 dibuat 12 Okt 2026 · self-test 113 cek lolos (DB bersih & DB tiruan data user) · 845 kode ERP: 844 masuk, 1 ditolak (T-160 WHITE dobel) · 139 query EXPLAIN · harness |
| R8 | Catatan uji E2E-R: Manager Costing langsung berlaku, riwayat harga, article tanpa batas, awalan Material Code wajib sama, ajukan harga master dari CBD - panduan `steps/R8_uji.md` | **`build_r8.json` (di-import)** | 🟡 dibuat 12 Okt 2026 · R8 2× tanpa error · self-test 102 cek lolos · 137 query EXPLAIN · harness widget & JSObject |
| R19 | Catatan uji user (26 Okt 2026): **nomor komponen = posisi** (geser +10 di kelompok), **nomor artikel boleh kosong** (peringatan SMS / GTM, blokir Production, Tugas Saya), **Dimension di kolom sendiri** + **saran material terbaca penuh** (grid BOM), **material Process** (tanpa kode, quotation per CBD), **ganti komponen** di specsheet draft, **reset filter** saat page dibuka (kecuali kembali dari detail), **semua field model wajib** (lihat §6 R19) · panduan `steps/R19_uji.md` | `sql/R19_catatan_uji.sql` + **`exports/build_r19.json`** (base **`export_r18.json`** = export user 26 Okt 2026, sama dengan build R18 kecuali format ulang Appsmith) | ✅ lolos uji user 27 Okt 2026 (termasuk koreksi pindah posisi komponen, nomor artikel opsi B, Process oleh tim CBD, ganti komponen per baris, Dimension mengikuti material) · dibuat 26 Okt 2026 · R19 SQL 2× tanpa error (salinan DB R18) · self-test **372 cek** (62 baru R19, termasuk koreksi pindah posisi komponen; 7 pembuatan model lama dilengkapi karena field wajib) · 146 query EXPLAIN tanpa error · query baru/diubah dijalankan per role pada data uji (0 error) · harness `cwBomGrid` + `BomCtrl` asli (data DB nyata: saran membungkus, nama sama beda UoM, ketikan lama dipisah, kode, dimension wajib, pilih dimension setelah ganti material, Esc, Process, Change komponen) + `cwMaterialForm` / `cwModelForm` / `cwArticleForm` + `Util.resetFilters` / `goDetail` · validator **LOLOS** |
| R20 | Penulisan material seragam (27 Okt 2026): **nama beda spasi / tanda baca = material yang sama**, saran nama mirip hanya bila **angka sama**, **Material Code 10 karakter ketat dua arah tanpa centang konfirmasi** (awalan = 1 material, kode tengah = 1 dimension (kosong: per UoM), kode akhir = 1 warna, dan sebaliknya), **Material Code hanya diketik di Register** (grid tidak membaca kode), **Use** di modal Register (kode sudah dipakai -> sel memakai varian itu, sel kuning yang sama di semua draft ikut, material lama tanpa varian jadi INACTIVE) · query cek C1 to C3 + **perbaikan data** (11 material proses -> Process, gabung 98 D -> 98 A, BSW-0032 -> BSW-032) · panduan `steps/R20_uji.md` (SQL di dalam dokumen, permintaan user: tanpa file .sql baru) | SQL di `steps/R20_uji.md` §0a + **`exports/build_r20.json`** (base **`build_r19.json`**: export R19 user belum ada) | ✅ cek cepat 11 poin lolos di DB user 27 Okt 2026 (SQL, self-test, preview P1/P2, perbaikan data, C2 = 0, import, Register + Use), uji lengkap `R20_uji.md` menyusul saat user testing · dibuat 27 Okt 2026 · SQL dari dokumen 2× di atas R19 tanpa error · self-test **R_selftest.sql** LOLOS (40 cek R20; cek R4 kode di sel diganti; cek R9/R16 konfirmasi diganti aturan ketat, 3 kode uji lama disesuaikan) · query diubah/baru EXPLAIN tanpa error · harness `cwBomGrid` (kode di sel = teks, kode di Material ditolak, klik di luar menyimpan, nama rapat, nearName) + `cwVariantForm` (kotak merah, Use, Save ditolak) · query cek dijalankan pada 845 kode ERP (`MATERIAL CODE.xlsx`, tanpa trigger): C1 6, C2 95 (semua awalan), C3 0 · skrip perbaikan dari dokumen 2× pada data tiruan seperti hasil user (aman diulang) · validator **LOLOS** |
| R18 | Ganti teks (permintaan user 26 Okt 2026): tombol Specsheet `+ Create Revision` → `+ Create` (+ pesan kosong), **Thickness → Dimension** di semua teks yang terlihat + header Excel + pesan DB; nama kolom / fungsi / variabel tetap (lihat §6 R18) · panduan `steps/R18_uji.md` | `sql/R18_dimension.sql` + **`exports/build_r18.json`** (base **`export_r17.json`** = export user 26 Okt 2026, sama dengan build R17 kecuali format ulang Appsmith) | ✅ lolos uji user 26 Okt 2026 · R18 SQL 2× + self-test LOLOS di PostgreSQL lokal (salinan DB R17) · validator **LOLOS** (0 error baru) · sisa kata thickness di build hanya nama internal / komentar |
| R17 | **Remember me** di halaman Login (permintaan user 22 Okt 2026, app hanya lewat VPN): dicentang = sesi 7 hari tanpa dibuka, diperpanjang tiap app dibuka, maks 30 hari sejak login; tidak dicentang = 12 jam seperti dulu; email terakhir diingat di browser; **bagian 2 (22 Okt 2026): Material Code wajib mulai SMS + harga ESTIMATE untuk baris CBD tanpa kode di Pullover / Preview, baris ber-Yield tanpa harga memblokir mulai SMS** (lihat §6 R17) · panduan `steps/R17_uji.md` | `sql/R17_remember_estimate.sql` (dulu `R17_remember_me.sql`) + **`exports/build_r17.json`** (base **`export_r16.json`** = export user 22 Okt 2026: sama dengan build R16, hanya tata letak tabel Model List / Master Material / Master Component / Master Options / Master Supplier / Material Detail, kolom Factory `tblMaterials` disembunyikan, nama material wrap) | ✅ lolos uji user 26 Okt 2026 · R16 + R17 2× tanpa error di PostgreSQL lokal · self-test **280 cek** (13 baru R17) · `fn_login` dipanggil seperti app lama (2 parameter) dan baru (teks → boolean) · harness `cwLogin` (checkbox, nilai `remember` di event, email tersimpan datang setelah render pertama, tidak mengisi ulang email yang dihapus user) · validator **LOLOS** (0 error baru) · **bagian 2:** PostgreSQL lokal baru (F1 s.d. R16 dari file SQL, lalu R17 2× tanpa error), self-test **310 cek** (30 baru: skenario Preview → SMS user + lompat Pullover → GTM; 2 tes lama disesuaikan: T56 di SMS kini memblokir, tes sel kuning R16 pindah ke SMS), 145 query EXPLAIN tanpa error, query baru/diubah dijalankan dengan token per role pada data uji, harness `cwCbdGrid` + `cwCbdPriceForm` + `CbdGridCtrl` asli (tombol Enter / Edit estimate, badge, tanda no Material Code, saran Use, isian awal Propose), validator **LOLOS** |
| R16 | Specsheet boleh disusun dengan material tanpa Material Code (sel kuning, terbit tetap diblokir), **+ New material** (bar atas & di baris yang tidak ketemu, baris dilanjutkan otomatis), saran "Did you mean", sel kuning di Export Excel, thickness baku (gaya berspasi tim material; 20 Okt: nol belakang dibuang, kutip miring / INCH, rentang), Order master option = posisi; review seluruh app 20 Okt 2026: T74–T86 (lihat §6 R16 & §9) · panduan `steps/R16_uji.md` | `sql/R16_baku_thickness.sql` + **`exports/build_r16.json`** (base `build_r15.json`) | ✅ lolos uji user 21 Okt 2026 · self-test **267 cek** (DB kosong & data sintetis 1 tahun) · 144 query dijalankan per role tanpa error · pembakuan thickness SQL = JS pada 239 teks · pindah Order 42/42 · alur panduan bagian 1–6 lewat fungsi DB 19/19 · uji browser `cwBomGrid` + `BomCtrl` + `cwVariantForm` + `cwCbdGrid` asli · validator **LOLOS** |
| R15 | Seluruh app ke bahasa Inggris sederhana + tanpa em dash (keputusan user 13 Okt 2026): label, tombol, pesan, isi Custom Widget, pesan error DB, Tugas Saya, export Excel; nama page Home / Master Component / Master Options / Price Approval; kode status harga bahasa Inggris; PURPOSE Excel specsheet 5 stage (catatan uji R14); T72, T73 (lihat §6 R15) · panduan `steps/R15_uji.md` | `sql/R15_english.sql` + **`exports/build_r15.json`** (base `build_r14.json`: app R14 user tidak diubah) | ✅ lolos uji user 14 Okt 2026 (commit 33b943d) · R15 2× tanpa error (DB bersih & DB data uji) · logika 88 fungsi/view identik (dibandingkan tanpa teks & komentar) · 0 teks Indonesia tersisa di literal DB · self-test **204 cek** (pola pesan bahasa Inggris) · 143 query EXPLAIN · query kode status harga per role 11/11 · harness 45/45 (28 Custom Widget dirender tanpa error, Material Detail dengan data DB, PURPOSE 5 stage) · validator **LOLOS** · em dash di app & dokumen: 0 · tinjauan kalimat utuh (906 baris) + perbaikan frasa · **14 Okt: uji user menemukan T73 (data tidak tampil), build diperbaiki, Auth per page dicek sama dengan R14, validator LOLOS** |
| R14 | Detail audit (panel `cwAuditDetail` di Admin, tab Audit Log: UPDATE kolom berubah lama → baru, INSERT keterangan, DELETE isi lengkap, kolom teknis diringkas, password tidak pernah tampil) + T71 (kolom Waktu audit) + **5 stage** Pullover, Preview, SMS, GTM, Production (kode `PULL`/`PREV`/`SMS`/`GTM`/`PROD`, label di app, stage berikutnya boleh melompat) (lihat §6 R14) · panduan `steps/R14_uji.md` | `sql/R14_audit_stage.sql` + **`exports/build_r14.json`** (base `build_r13.json`: app R13 user tidak diubah, hanya di-deploy) | ✅ lolos uji user 13 Okt 2026 (catatan: PURPOSE di Excel specsheet dibuat 5 stage → R15) · dibuat 13 Okt 2026 · R14 2× tanpa error (DB bersih & DB data uji, data lama dinomori ulang tanpa audit) · self-test **204 cek** · 143 query EXPLAIN · query baru/diubah per role 24/24 · harness (AdminCtrl, Util, SpecCtrl, CbdCtrl, SpecExportCtrl asli + `cwAuditDetail`, `cwRevisionForm`, `cwStepper`, `cwCbdForm` asli, data `q_audit` asli) 41/41 · scan fungsi menganggur: tidak ada yang baru · validator **LOLOS** |
| R13 | CBD per stage (laporan user 13 Okt 2026: draft CBD SMS r0 pindah jadi GTM r0 saat *Refresh dari Specsheet* setelah specsheet GTM terbit → CBD & PO SMS hilang): acuan CBD = specsheet terbit terakhir **di stage CBD itu**, stage dipilih saat Buat CBD, tidak boleh mundur, chip/Tugas Saya *perlu CBD <stage>*, sinkron hanya stage sama, perbaikan data acuan lintas stage + **bersih-bersih** hasil scan (lihat §6 R13) - panduan `steps/R13_uji.md` | `sql/R13_cbd_stage.sql` + **`exports/build_r13.json`** (base `export_r12.json` = export user "Product Management R12", sama dengan build R12 kecuali tata letak kecil) | ✅ lolos uji user 13 Okt 2026 · dibuat 13 Okt 2026 · R13 2× tanpa error (DB bersih & DB data uji) · self-test **190 cek** · bug lama direproduksi dengan kode R12 lalu acuan dipulihkan R13 · 143 query EXPLAIN · query baru/diubah per role 12/12 · data 5 tahun: Tugas Saya CBD ±0,6–1 dtk (sama), chip article 2–4 ms, checklist ±30 ms · harness (CbdCtrl/CbdGridCtrl/BerandaCtrl asli + `cwCbdForm` asli) 17/17 · validator **LOLOS** (0 error) |
| R12 | Perbaikan pra-UAT dari review go-live per halaman (13 Okt 2026): gambar/lampiran vs batas respons Appsmith (gambar terbit diperkecil, galeri satu per satu, lampiran 3,5 MB), index harga di `cbd_line`, antrean pemuatan Specsheet/CBD (klik cepat), sesi habis di tombol Cari, override & ExcelJS dihapus, jam WIB, keseragaman modal/tabel - lihat §9 T60–T70, panduan `steps/R12_uji.md` | `sql/R12_golive.sql` + **`exports/build_r12.json`** (base `export_r11b.json` = export user "Product Management R11 (1)", identik dengan build R11b) | ✅ lolos uji user 13 Okt 2026 · dibuat 13 Okt 2026 · R12 2× tanpa error · self-test **171 cek** · 142 query EXPLAIN · query baru per role 20/20 · index diukur di data 5 tahun (1,1 s → 5 ms) · harness JSObject asli: antrean CBD 15/15, Specsheet 4/4, galeri 12/12, Util/Auth/WIB 8/8 (kode lama gagal di skenario klik cepat yang sama) · harness `cwPublishForm` (PNG 16 MB → JPEG 1,3 MB) |
| R11b | Temuan uji C: harga AKAN BERLAKU yang diakhiri tampil **DIBATALKAN** (bukan AKAN BERLAKU) & tidak dipakai form Tambah Harga - lihat §9 T54 | `sql/R11b_harga_batal.sql` + **`exports/build_r11b.json`** (base `export_r11.json` = export user "Product Management R11", identik dengan build R11) | 🟡 dibuat 13 Okt 2026 · skenario user direproduksi (sebelum: AKAN BERLAKU 13-11→13-11; sesudah: DIBATALKAN, harga lama BERLAKU) · bug kedua (harga dibatalkan hidup lagi) direproduksi & diperbaiki + pemulihan data dari audit (uji: dipulihkan 1) · R11b 2× tanpa error · instal bersih R11 → R11b · self-test **166 cek** · uji `MaterialDetailCtrl` dengan data `q_prices` asli |
| R11 | Skalabilitas (S1–S10), bug (T54–T59), alur CBD: Tanpa biaya + peringatan baris belum berharga (A1/T56, tidak memblokir - keputusan 13 Okt 2026), rincian perubahan / cost bridge (A4) - panduan `steps/R11_uji.md` | `sql/R11_perbaikan.sql` + **`exports/build_r11.json`** (base `export_r10.json` = export user "Product Management R9" + tempelan R10) | 🟡 dibuat 12 Okt 2026 · R11 2× tanpa error · self-test **163 cek** lolos · 141 query EXPLAIN + 18 query baru dijalankan per role · harness widget (cwCbdGrid, cwPublishForm CBD & Specsheet, cwBomGrid) + uji JSObject · uji balapan T55 · data 5 tahun diukur ulang |
| F11 | Dokumentasi & handover (`appsmith/README.md`) | – | ⬜ dikerjakan **setelah UAT & go-live** (keputusan user 6 Okt 2026) |
| Opsional | Where-used, histori harga, diff revisi, harga referensi brand | – | ⬜ |

---

## 2. Keputusan arsitektur

1. **Logika sederhana → SQL langsung di Appsmith.** CRUD master, model, article, edit sel/nilai: query `INSERT/UPDATE` biasa. Aturan data dijaga oleh constraint & trigger di Postgres (tidak bergantung UI).
2. **Logika banyak-langkah → function Postgres `fn_*`** (satu function = satu transaksi): buat/hapus revisi, tambah/ganti baris BOM, terbit, buat/refresh CBD, harga baru. Appsmith memanggil `SELECT fn_x(...)`.
3. **Audit otomatis lewat trigger** `trg_audit` (+ `trg_touch` untuk `created_*`/`updated_*`) di semua tabel bisnis, dipasang dengan `SELECT fn_setup_table('<tabel>')`. Setiap query tulis mengisi `updated_by = fn_auth(token, izin)`; trigger mencatat before/after ke `audit_log` (password tidak pernah dicatat). Tidak ada kode audit di Appsmith.
4. **Kunci revisi terbit lewat trigger** `trg_lock_published`: baris BOM/sel/article revisi & baris CBD tidak bisa diubah kalau revisinya PUBLISHED. UPDATE langsung dari Appsmith jadi aman.
5. **Login & hak akses di database.** App dipublikasikan, jadi siapa pun bisa memanggil query-nya langsung - semua pengecekan ada di Postgres:
   - Login email + password (bcrypt via `pgcrypto`), token acak disimpan di browser (`appsmith.store.token`), di DB hanya hash-nya (`app_session`). Sesi 12 jam. Terkunci 15 menit setelah 5 kali salah.
   - Password min. 8 karakter; wajib ganti saat login pertama & setelah reset; reset hanya oleh System Admin (password sementara). Satu akun = satu role.
   - **Setiap query** (baca & tulis) memanggil `fn_auth(token, izin)`; token tidak valid → error `SESI_HABIS` → Util mengarahkan ke page `Login`.
   - UI tetap menyembunyikan menu/tombol dengan `Auth.can()` (kenyamanan saja).
   - `z_run_sql` (prepared statements OFF) hanya ada di app terpisah yang **privat**: **DB Tools**.
6. **Uang/angka = `numeric`** dan dihitung di Postgres (view). JS hanya memformat tampilan.
7. **Tanggal "hari ini" = WIB** lewat `fn_today()` = `(now() AT TIME ZONE 'Asia/Jakarta')::date`.
8. **Tanpa penguncian multi-user** - yang terakhir menyimpan yang berlaku.
9. **ID = `uuid`** (`gen_random_uuid()`, butuh PostgreSQL ≥ 13).
10. **UI campuran (standar untuk handover):**
    - **Widget bawaan** Appsmith untuk halaman CRUD standar: Beranda, Admin, Master (Supplier, Komponen, Material), Model - bisa dirawat lewat panel properti tanpa coding.
    - **Custom Widget** hanya untuk bagian yang tidak bisa dibuat baik dengan widget bawaan: `cwLogin` (Login), `cwStepper` (stage + chip article, dipakai Specsheet & CBD), `cwBomGrid` (grid BOM, maks. 5 article per season), `cwCbdGrid` (grid CBD + rekap). Ditambahkan user di F1 (keputusan user, 25 Sep 2026): `cwHeader` (header di setiap page), `cwMenu` (menu Beranda), `cwUserForm` (form user), `cwTempPassword` (password sementara). Ditambahkan di F2 (keputusan user, 27 Sep 2026): `cwSupplierForm`, `cwKomponenForm` (isi modal tambah/ubah, pola sama dengan `cwUserForm`). Pola yang sama di F3 (`cwMaterialForm`, `cwLinkForm`, `cwPriceForm`, `cwReasonForm`) dan F4 (`cwModelForm`, `cwSeasonForm`, `cwArticleForm`).
    - Aturan Custom Widget: **hanya tampilan** (tanpa logika bisnis/query); data masuk lewat *Default model*, aksi keluar lewat `appsmith.updateModel()` + `appsmith.triggerEvent()` yang ditangani `<Page>Ctrl`; JavaScript biasa tanpa framework (library CDN jsDelivr dengan versi terkunci hanya bila perlu); warna/radius/font mengikuti tema app (`appsmith.theme`).
    - Setiap Custom Widget punya folder `appsmith/widgets/<cw>/` berisi `index.html`, `style.css`, `script.js`, dan `README.md` (kontrak model, nilai keluar, event).
11. **Export Excel**: library ExcelJS dipasang di Appsmith (Libraries). Cadangan: SheetJS tanpa style.
12. **Lampiran article**: FilePicker (Base64) → disimpan `bytea` di tabel `article_attachment`. Jenis jpg/png/pdf, maks 5 MB per file.
13. **Desain**: palet mockup Flask - primary navy `#122A52`, aksen `#3B6FE0`, latar `#F3F5FA`, radius 8px, font sistem (Segoe UI); chip status hijau/kuning/merah/abu. Hanya untuk laptop/PC (lebar ≥ 1280px).
14. **Approval harga material (F3b, keputusan user 29 Sep 2026)**: harga dari Vendor CBD = usulan PROPOSED, Master Admin approve/tolak (alasan wajib, tetap tersimpan); harga dari Master Admin langsung APPROVED. Harga lama tetap berlaku sampai usulan di-approve. Maks. satu usulan per supplier + warna (bisa dibatalkan tim CBD). Akhiri harga tanpa approval. Hanya harga APPROVED yang dipakai (lookup CBD, ringkasan material). - *diganti mulai R3: approver = Manager Costing, lihat "Revisi besar" di bawah.*

### Revisi besar 8 Okt 2026 (R1–R7)

Pemicu: **Material Code dari ERP pabrik ternyata unik per warna dan thickness**, tetapi nama material tidak boleh diketik ulang. Diskusi meluas ke role, pabrik, model, dan CBD. Semua keputusan di bawah dari user, 8 Okt 2026.

**Pabrik**
- Master **Pabrik** (diisi System Admin, cukup nama). **1 user = 1 pabrik**; Brand Viewer & System Admin tanpa pabrik.
- **Model milik 1 pabrik** (tidak dipakai bersama; pabrik model = pabrik user pembuat, otomatis). Pabrik lain hanya melihat model pabriknya sendiri. Copy apa pun (season, article, lintas model) hanya di dalam pabrik yang sama.
- **Material (induk, varian, link supplier, harga) milik pabrik**, karena kodenya berasal dari ERP masing-masing pabrik → harga otomatis per pabrik, supplier utama per pabrik.
- **Supplier & komponen bersama** semua pabrik. Grup komponen (a/b/c/d) tetap.
- **Brand** melihat dokumen terbit semua pabrik, dengan filter pabrik.

**Role** (matriks baru di §5)
- **Master Admin dihapus.** **Vendor Spec** mengisi semua master tanpa approval (supplier, komponen, material, varian, link supplier, pilihan model).
- **Manager Costing** (baru, pihak pabrik, 1 orang dulu): **hanya** approve/tolak harga dan mengakhiri harga; **tidak bisa mengajukan** harga (maker–checker). Melihat CBD pabriknya (baca saja).
- **Vendor CBD**: mengajukan harga + CBD; tidak menambah master.
- Selling price & Margin % **tidak terlihat** oleh role pabrik mana pun.

**Master data (tanpa approval)**
- Status master hanya **ACTIVE / INACTIVE** (PROPOSED/APPROVED di master hilang, termasuk komponen). Komponen lokal di specsheet **tetap ada**.
- Pola **"cari dulu, baru buat"** di setiap form tambah: daftar nama mirip muncul saat mengetik (abaikan PT/CV/Tbk, titik, spasi); tidak memblokir.
- Data bersama (supplier, komponen): **tambah** bebas; **ubah nama** hanya selama belum dipakai di dokumen terbit pabrik mana pun; **INACTIVE** ditolak selama masih dipakai di draft pabrik mana pun.
- **Material Code** boleh diubah hanya selama belum dipakai di dokumen terbit; sesudahnya INACTIVE + daftarkan varian baru.
- **Material Code tidak di-prefill** (saran `MTR-xxxx` dihapus) - selalu diketik dari ERP pabrik. **Kode material di supplier** (`supplier_material_code`) **dihapus** (catatan user setelah uji R1, 8 Okt 2026).
- Metode harga default **CATALOG**, hanya Vendor CBD (`manage_price`) yang mengubah.

**Material Induk + Varian**
- **Induk**: nama, kategori, UoM, metode harga - diketik sekali. **Varian**: thickness (angka **mm**, boleh kosong) + warna + **Material Code** (diketik, dari ERP pabrik). **Semua material punya kode per warna.**
- Tambah varian sekaligus: pilih beberapa thickness × warna → baris kombinasi → kode diketik per baris.
- Supplier **tidak** membentuk kode baru. Harga = **Varian × Supplier**.

**Harga**
- Vendor CBD **mengajukan**: pilih supplier, **centang banyak varian**, harga, currency (wajib dipilih), berlaku mulai, referensi → satu pengajuan, semua PROPOSED. **Salin harga dari varian lain** → hasilnya juga PROPOSED.
- Manager Costing menyetujui **per baris** ("Setujui semua" + tolak sebagian dengan alasan).
- Harga baru untuk kode + supplier yang sama = PROPOSED; saat di-approve harga lama otomatis ditutup (aturan F3b). **Akhiri harga** hanya Manager Costing.
- Vendor CBD hanya mengajukan untuk supplier yang **sudah terhubung** ke material.

**Model**
- **Kode model dihapus**; **nama model = identitas**, unik per pabrik, boleh diubah (tercatat di audit). Kode article tetap.
- Identitas model lewat **dropdown**: Kategori, Construction, Gender (Laki-laki / Perempuan / Unisex) = pilihan **bersama**; Last, Outsole mold = pilihan **per pabrik**. Satu tabel pilihan untuk semua jenis (jenis baru = baris data, tanpa ubah tabel).
- **Ukuran ala kalender**: grid angka bulat (awal 35–47, tanpa setengah ukuran) → klik awal & akhir = rentang, klik lagi untuk membuang ukuran tertentu; disimpan sebagai daftar, tampil ringkas "37–40, 42–44". Sample size dipilih dari ukuran terpilih.

**Specsheet**
- Baris BOM = **Induk + thickness**; sel per article = **warna** → kode varian. **Hanya sel kosong = tidak dipakai** (`none`/`-`/`n/a` tidak istimewa lagi).
- Kode bisa diketik langsung: di kolom Material (mengisi induk + thickness, menawarkan isi warna ke sel kosong) atau di sel (mengisi warna; kode beda induk/thickness ditolak).
- Warna belum terdaftar → **sel kuning** + tombol **Daftarkan varian** (modal terisi, cukup ketik kode); setelah terdaftar, semua sel kuning yang sama tersambung otomatis. Tombol **+ Supplier baru** juga ada di specsheet.
- Dropdown supplier: supplier material itu di atas, supplier lain di bawah (dipilih → ditautkan otomatis).
- **Tidak bisa terbit** bila ada sel kuning, baris tanpa supplier, atau supplier/link INACTIVE (**F10d disetujui**).

**CBD**
- Harga dicari per **kode varian + supplier**, hanya APPROVED dari supplier & link ACTIVE. Status baris: Belum ada harga / Menunggu persetujuan.
- **Tidak bisa terbit** selama ada baris "menunggu persetujuan". Override CATALOG tetap tidak ada (F10b); harga QUOTATION tetap diisi di CBD tanpa approval (disengaja).
- **PO SMS** = Actual FOB × **1,25**, baris terpisah, hanya stage SMS (faktor disimpan per stage, dibekukan saat terbit). Target FOB tetap diisi pabrik dan dibandingkan dengan FOB **tanpa** ×1,25.
- **Selling price & Margin dihapus dari CBD.** Brand mendapat **kalkulator simulasi** di CBD terbit (isi selling price ↔ margin), **tidak disimpan**, tanpa tombol simpan; tidak ikut export.
- Export Excel specsheet & CBD: tambah kolom **Material Code**.

**Alur kerja**: mulai R1 saya mengedit JSON app (lihat §6 "Alur kerja R").

### Penyederhanaan dari sistem Python

| Di Python | Di Appsmith |
|---|---|
| Login pilih role bebas | Login email + password di dalam app; role dari tabel `app_user` |
| 4 cara buat revisi specsheet (kosong, carryover, lintas model, stage sama/berikut) | Satu function `fn_revision_create(mode)`; **Copy dari season lain** = carryover dari **model yang sama** saja (development NC / New Color), sumber hanya revisi **terbit**, baris BOM di-copy, article = article season tujuan, warna per article kosong. Copy **lintas model tidak dibawa** (keputusan user 30 Sep 2026) - *dibuka kembali 7 Okt 2026, dijadwalkan sebagai **R7** (8 Okt 2026)* |
| 5 cara buat CBD | Satu function `fn_cbd_create(article, source, stage)`. ~~Stage CBD selalu mengikuti stage specsheet terbit terakhir~~ → **R13 (13 Okt 2026): stage dipilih** (default stage specsheet terbit terbaru); acuan = specsheet terbit terakhir **di stage itu**; tidak boleh membuat/menerbitkan CBD stage lebih rendah dari CBD terbit terakhir; nomor revisi = terakhir di stage itu + 1 |
| `is_used` sel BOM dihitung di Python | Kolom generated di DB |
| Usage = 1/Yield dihitung di Python | Kolom generated di DB |
| Diff BOM/CBD saat terbit (JSON) | MVP: change log kategori + alasan saja; diff masuk fase Opsional (kolom `diff` sudah disiapkan) |
| Copy Article antar season (halaman Model) | Tidak dibawa - article diisi per season (keputusan user 30 Sep 2026) |
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
| P4 | Ganti material pada baris induk: subkomponen tetap menunjuk `line_key` baris lama yang sudah nonaktif → hilang dari grid | Subkomponen ikut dipindah ke baris baru (`fn_bom_replace_material`) - ditemukan saat menyiapkan F5, 30 Sep 2026 |
| P5 | Penandaan sinkron CBD membandingkan specsheet terbit **sebelumnya** dengan yang baru → CBD yang sudah NEEDS_REVISION kembali IN_SYNC bila revisi specsheet berikutnya tidak mengubah apa-apa | Dibandingkan dengan **acuan CBD itu sendiri** (`fn_cbd_sync_spec`) - ditemukan saat menyiapkan F8, 30 Sep 2026 |
| P6 | Beranda Brand "terbit terbaru" memilih revisi per season/article berdasarkan waktu terbit | Revisi terbit terakhir = urut stage + nomor revisi (sama dengan P1/P2); daftar tetap diurutkan terbaru dulu (`v_recent_published`, F10) |

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
| `export_service.py` | `Specsheet`, `CBD` | `SpecExportCtrl`, `CbdExportCtrl` (ExcelJS; data dari query page, tanpa query baru; `q_cbd_model` + 3 kolom) | pakai view yang sama |
| `worklist_service.py` | `Beranda` | `q_worklist_spec`, `q_worklist_proposals`, `q_worklist_cbd`, `q_worklist_gap`, `q_worklist_admin`, `q_worklist_pub_spec`, `q_worklist_pub_cbd`, `q_worklist_system` · `BerandaCtrl` (+ `Auth.pageQueries` → `BerandaCtrl.load()`) · Custom Widget `cwWorklist` | `v_worklist_spec`, `v_worklist_cbd`, `v_worklist_price_gap`, `v_worklist_admin`, `v_recent_published`, `v_system_summary` |
| `report_service.py`, `diff_service.py`, `cbd_diff_service.py` | Opsional | – | – |
| `merge_service.py`, `csv_import.py`, `reset_service.py`, `seed_*.py`, `photo_service.py` | tidak dibawa | – | – |

---

## 4. Konvensi penamaan

| Objek | Pola | Contoh |
|---|---|---|
| Page | nama tampil di sidebar (boleh spasi) - dipakai persis oleh `navigateTo()` | lihat tabel **Nama page di app** di bawah |
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
| `Specsheet` | `Specsheet` | ya - pilih model & season di page; dari Model List / Model Detail langsung terpilih (keputusan user 30 Sep 2026) |
| `CBD` | `Cost Breakdown (CBD)` | ya - sama seperti Specsheet (F7) |

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
| Function | `SELECT fn_x({{appsmith.store.token}}, …)` - function memanggil `fn_auth` sendiri |

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

*Matriks di atas berlaku sampai F10c.* **Mulai R1** (keputusan user 8 Okt 2026):

| Izin | VENDOR_SPEC | VENDOR_CBD | MANAGER_COSTING | BRAND_VIEWER | SYSTEM_ADMIN |
|---|:-:|:-:|:-:|:-:|:-:|
| `view_master`, `view_model`, `view_specsheet` | ✓ | ✓ | ✓ | ✓ | |
| `view_cbd`, `view_price` | | ✓ | ✓ | ✓ | |
| `view_drafts` (lihat DRAFT) | ✓ | ✓ | ✓ | | |
| `manage_master` (supplier, komponen, material, varian, link, pilihan model - tanpa approval) | ✓ | | | | |
| `manage_price` (ajukan & salin harga, metode harga; R8: Manager Costing juga → langsung berlaku) | | ✓ | ✓ | | |
| `approve_price` (setujui / tolak / akhiri harga) | | | ✓ | | |
| `edit_model`, `edit_specsheet` | ✓ | | | | |
| `edit_cbd` | | ✓ | | | |
| `simulate_margin` (kalkulator selling price ↔ margin, tidak disimpan) | | | | ✓ | |
| `manage_users`, `manage_factory`, `view_audit` | | | | | ✓ |
| **Lingkup data** | pabriknya | pabriknya | pabriknya | semua pabrik (terbit saja) | semua |

Dihapus: `MASTER_ADMIN`, `propose_master`, `manage_material_supplier` (digabung ke `manage_master`).

---

## 6. Fase implementasi

Setiap fase: saya beri langkah konkret → Anda kerjakan di Appsmith → export ke `appsmith/exports/export_vN.json` → saya review → checklist di sini diperbarui.
Tabel DB baru di tiap fase ditulis di bagian **7. Perubahan database** dan dicatat di **8. Register objek DB**.
**Mulai R1 alurnya berubah** - lihat "Alur kerja R" di bawah F11.

### F0 - Persiapan
- [x] Cek versi Appsmith → **v2.4** (self-hosted); Custom Widget **tersedia**
- [x] Cek versi PostgreSQL → **16.15**
- [x] Buat app, navigasi: Sidebar *(nama app di Appsmith: "Test Database", datasource: `Prestasi` - lihat §9)*
- [x] Tema app: primary `#122A52`, background `#F3F5FA`, radius M, font *System Default*
- [x] Buat page kosong: `Login` (home page), `Beranda`, `Admin`, `Master_Supplier`, `Master_Komponen`, `Master_Material`, `Material_Detail`, `Model_List`, `Model_Detail`, `Specsheet`, `CBD`
- [x] Buat app privat **DB Tools** berisi `z_run_sql` (prepared statements OFF); hapus `z_run_sql` dari app utama
- [x] Pasang extension `pgcrypto`
- [x] Uji pasang library ExcelJS (Libraries → +) → **berhasil**

**Selesai bila:** versi Appsmith & Postgres diketahui, 11 page ada, library terpasang, `pgcrypto` aktif, `z_run_sql` hanya ada di DB Tools.

### F1 - Fondasi, login in-app & role
- [x] Jalankan SQL F1 (`sql/F1_fondasi.sql`: fungsi dasar, `app_user`, `role_permission`, `audit_log`, trigger audit)
- [x] Jalankan SQL F1b (`sql/F1b_login.sql`: kolom password, `app_session`, `fn_auth`, `fn_me`, `fn_login`, `fn_logout`, `fn_change_password`, `fn_user_save`, `fn_user_reset_password`)
- [x] Set password awal akun System Admin Anda lewat `z_run_sql`
- [x] Page `Login` (home page): Custom Widget **`cwLogin`** (masuk + ganti password), logout lewat flag `appsmith.store.doLogout` (T7) - `Util`, `LoginCtrl`
- [x] `q_me`, `Auth` (cek sesi + izin + `pageQueries`), `Util` - disalin ke setiap page lain
- [x] Beranda: sapaan, role, tombol menu sesuai izin, **Ganti Password**, **Keluar** *(dibuat dengan Custom Widget `cwHeader` + `cwMenu`)*
- [x] Page `Admin`: tab **User** (tambah → password sementara, ubah role/nonaktif, reset password) dan **Audit Log** *(form user `cwUserForm`, password sementara `cwTempPassword`, header `cwHeader`)*
- [x] Navigasi: sembunyikan `Login`, `Material_Detail`, `Model_Detail` dari sidebar; Share → **Make application public** → Deploy

**Selesai bila:** buka URL app tanpa login → halaman Login; login benar masuk Beranda sesuai role; password sementara wajib diganti; 5 kali salah → terkunci 15 menit; logout/sesi habis → kembali ke Login; query tanpa token ditolak DB; login/logout/ganti password tercatat di Audit Log.

### F2 - Master Supplier & Komponen
- [x] SQL F2 (`sql/F2_master.sql`: `fn_has_perm`, `fn_auth_any`, `supplier` + `trg_supplier_check`, `component_group` + seed a/b/c/d, `component` + `trg_component_check`, `fn_component_add`)
- [x] `Master_Supplier`: tabel + cari + filter status, tambah (modal), ubah nama, status (tanpa currency default - keputusan user 27 Sep 2026: currency dipilih saat harga dimasukkan) - form modal: Custom Widget `cwSupplierForm`
- [x] `Master_Komponen`: tabel per grup, saran nomor berikutnya (max+10), tambah, ubah, status; vendor → otomatis PROPOSED; admin → Approve - form modal: Custom Widget `cwKomponenForm`

**Selesai bila:** nomor bukan kelipatan 10 / di luar rentang / sudah dipakai ditolak dengan pesan jelas; nama supplier beda kapital ditolak; semua perubahan masuk audit log.

### F3 - Master Material, supplier material, harga
- [x] SQL F3 (`sql/F3_material.sql`: `material` + `trg_material_check`, `material_supplier` + `trg_material_supplier_check`, `material_price`, `fn_material_add`, `fn_material_update`, `fn_link_save`, `fn_ensure_link`, `fn_price_add`, `fn_price_end`, `fn_price_lookup`, `v_material_list`; `fn_today` sudah ada dari F1)
- [x] Form modal Custom Widget (keputusan user): `cwMaterialForm` (tambah & ubah material), `cwLinkForm` (supplier material), `cwPriceForm` (harga; currency tanpa nilai awal, angka ambigu `47.500` ditolak)
- [x] `Master_Material`: tabel (kode, nama, kategori, thickness, UoM, metode harga, status, ringkasan supplier/harga), cari & filter (status, kategori, "belum ada harga"), tambah dengan saran `MTR-NNNN` dan pilihan metode harga (P3)
- [x] `Material_Detail` tab **Info**: edit identitas (admin), status, metode harga (`manage_price`)
- [x] Tab **Supplier & Harga**: daftar supplier material (kode di supplier, utama, status, approve), tambah supplier; per supplier harga berlaku + riwayat, tambah harga (warna opsional, tanggal berlaku, **currency IDR/USD wajib dipilih - tanpa nilai awal**), akhiri harga. Tambah/akhiri harga: Master Admin & Vendor – CBD (`manage_price`, keputusan user 27 Sep 2026). Harga disembunyikan untuk VENDOR_SPEC

### F3b - Approval harga (tambahan, keputusan user 29 Sep 2026)
- [x] SQL F3b (`sql/F3b_price_approval.sql`: kolom `status`/`decided_by`/`decided_at`/`reject_reason` di `material_price`, `uq_price_one_proposed`, `fn_price_activate`, `fn_price_approve`, `fn_price_reject`, `fn_price_cancel`; `fn_price_add`, `fn_price_end`, `fn_price_lookup`, `v_material_list` diperbarui)
- [x] `Master Material`: filter **Harga menunggu approval**, ringkasan usulan di kolom Supplier
- [x] `Material Detail`: status MENUNGGU APPROVAL / DITOLAK di tabel harga, tombol **Approve**, **Tolak** (Custom Widget `cwReasonForm`), **Batalkan**; `cwPriceForm` mode **Usulkan**

**Selesai bila:** usulan Vendor CBD tidak dipakai sebelum di-approve dan harga lama tetap berlaku; approve menutup harga lama; tolak wajib beralasan; hanya satu usulan per supplier + warna.

**Selesai bila (F3):** duplikat material (nama+thickness+UoM setelah normalisasi) ditolak; harga baru menutup harga lama; tanggal mundur ditolak; material QUOTATION tidak bisa diberi harga; `fn_price_lookup` mengembalikan harga warna dulu lalu semua warna.

### F4 - Model, Season, Article, lampiran
File siap (30 Sep 2026): `sql/F4_model.sql`, `js/ModelCtrl.js`, `js/ModelDetailCtrl.js`, `widgets/cwModelForm/`, `widgets/cwSeasonForm/`, `widgets/cwArticleForm/`, `steps/F4_langkah.md`.
- [x] SQL F4 (`sql/F4_model.sql`: `product_model` + `trg_model_check`, `specsheet` + `trg_specsheet_check`, `article` + `trg_article_check` (batas 5 article, kode unik per season, kode terpakai terkunci) + `trg_article_delete_check`, `article_attachment`, `fn_article_is_used`, `fn_attachment_add` (jenis file dicek dari isi), `v_model_list`, `v_article_status`)
- [x] `Model List`: tabel model + filter season + cari; tombol Buka / Specsheet / CBD (CBD hanya bila `view_cbd`); tambah model (modal `cwModelForm`)
- [x] `Model Detail` tab **Info Model**: edit data model (`cwModelForm`)
- [x] Tab **Season & Article**: pilih/tambah season (`cwSeasonForm`, format SS26/FH26), tabel article (kode, colorway, jumlah lampiran), tambah/ubah (`cwArticleForm`)/hapus article (hapus hanya bila belum dipakai)
- [x] Lampiran per article (modal `mdlLampiran`): upload (jpg/png/pdf, ≤ 5 MB), lihat gambar, unduh, hapus
- [ ] **Hapus Copy Article** (keputusan user 30 Sep 2026: article tidak di-copy antar season, hanya struktur specsheet di F5): `DROP FUNCTION fn_article_copy`, hapus `selArticleSumber`, `btnArticleCopy`, `a_article_copy`, tempel ulang `ModelDetailCtrl` (`steps/F4_langkah.md` §5)
- ➡️ Dipindah ke F5: ringkasan specsheet terakhir di Model List (P2) & status article di specsheet · ke F7: status article di CBD (tabelnya belum ada di F4; view ditambah kolom di akhir)

**Selesai bila:** article ke-6 di satu season ditolak; kode article duplikat (beda huruf besar/kecil) ditolak; lampiran bisa diunggah, dilihat, dan diunduh; file bukan jpg/png/pdf ditolak DB. *Kode article terpakai tidak bisa diubah/dihapus* diuji di F5.

### F5 - Specsheet: revisi & grid BOM
File siap (30 Sep 2026): `sql/F5_specsheet.sql`, `js/SpecCtrl.js`, `js/BomCtrl.js`, `js/ModelCtrl.js` + `js/ModelDetailCtrl.js` (kolom status specsheet), `widgets/cwStepper/`, `widgets/cwRevisionForm/`, `widgets/cwBomGrid/`, `steps/F5_langkah.md`.
- [x] SQL F5 (`sql/F5_specsheet.sql`: `specsheet_revision`, `revision_article`, `bom_line`, `bom_cell`, `trg_lock_published`, `trg_revision_lock`, `fn_revision_draft`, `fn_revision_create`, `fn_revision_delete_draft`, `fn_bom_check_material`, `fn_bom_create_cells`, `fn_bom_add_line`, `fn_bom_add_sub`, `fn_bom_replace_material` (P4), `fn_bom_set_supplier`, `fn_bom_cell_set`, `fn_rev_article_set`, `v_bom_grid`; `v_model_list` & `v_article_status` ditambah kolom status specsheet)
- [x] Model List kolom **Specsheet** (revisi terakhir, P2; Brand hanya terbit) · Model Detail kolom **Specsheet** per article (pindahan dari F4)
- [x] Custom Widget **`cwStepper`**: stepper stage PULL→SMS→GTM→PROD berisi revisi (brand: hanya PUBLISHED)
- [x] Custom Widget **`cwRevisionForm`** (modal Buat Revisi, pola form modal)
- [x] Page `Specsheet` (`?model_id=`): pilih season (widget bawaan) + `cwStepper`
- [x] Wizard **Buat Revisi**: Kosong (pilih stage) / Copy dari season lain model yang sama (hanya revisi terbit, default terbit terakhir - P1; baris BOM di-copy, semua article season tujuan masuk revisi, warna kosong) / Revisi berikutnya / Stage berikutnya; hapus draft
- [x] Custom Widget **`cwBomGrid`**: No, Komponen, Material, Supplier, UoM, Remarks + satu kolom per article (edit warna langsung di sel, saran warna se-season); tambah baris (komponen master atau lokal), tambah subkomponen, ganti material, ubah supplier/remarks
- [x] **F5b** (permintaan user 30 Sep 2026, tidak ada di Python): hapus baris BOM di draft (`sql/F5b_bom_delete.sql`, `fn_bom_delete_line`, tombol **Hapus** di `cwBomGrid`; induk ikut menghapus subkomponennya)
- [x] Article di revisi: pilih article season, drop/aktifkan

**Selesai bila:** hanya satu draft per specsheet; revisi terbit tidak bisa diedit (ditolak DB); ganti material menonaktifkan baris lama; supplier baru di BOM membuat link PROPOSED; link INACTIVE ditolak.

### F6 - Specsheet: checklist & terbit
File siap (30 Sep 2026): `sql/F6_publish.sql`, `js/SpecCtrl.js`, `widgets/cwPublishForm/`, `steps/F6_langkah.md`.
- [x] SQL F6 (`change_log`, `v_revision_checklist`, `fn_revision_publish` - checklist dihitung ulang di DB setelah revisi dikunci)
- [x] Modal **Terbitkan** (`mdlTerbit`, Custom Widget `cwPublishForm`): checklist (article aktif ≥ 1, tiap article aktif dipakai, tidak ada material INACTIVE [blok]; baris tanpa supplier [peringatan]), kategori + alasan (wajib selain revisi awal; revisi awal kategori terpilih *Lainnya*). Pilihan kategori specsheet: MATERIAL / COMPONENT / TREATMENT / OTHER (kategori CBD dipakai di F8)
- [x] **Riwayat**: tombol **Riwayat (n)** → modal `mdlRiwayat` + `tblRiwayat` (semua terbit season ini, terbaru dulu) - penyederhanaan dari tab; change log revisi terbit juga tampil di `txtRevisi`

**Selesai bila:** terbit ditolak bila checklist gagal; setelah terbit revisi terkunci dan muncul di Riwayat.

### F7 - CBD: buat revisi & grid baris
File siap (30 Sep 2026): `sql/F7_cbd.sql`, `js/CbdCtrl.js`, `js/CbdGridCtrl.js`, `js/ModelDetailCtrl.js` (kolom CBD), `js/SpecCtrl.js` (`openCbd` meneruskan `from`), `widgets/cwStepper/` (baris chip article, opsional), `widgets/cwCbdForm/`, `widgets/cwCbdGrid/`, `steps/F7_langkah.md`.
- [x] SQL F7 (`cbd_revision`, `cbd_line`, `fn_cbd_revision_lock`/`fn_cbd_line_lock`, `fn_spec_latest_pub`, `fn_cbd_article_spec_status`, `fn_cbd_draft`, `fn_cbd_group_code`, `fn_cbd_identity`, `fn_cbd_expected_lines`, `fn_cbd_populate`, `fn_cbd_create`, `fn_cbd_delete_draft`, `fn_cbd_line_set`, `v_cbd_line`, `v_cbd_article`; `v_article_status` + kolom CBD)
- [x] Page `Cost Breakdown (CBD)` (`?model_id=&season=&from=`): pilih model & season di page (sama dengan Specsheet), `cwStepper` (chip article + status: belum ada CBD / draft / terbit / perlu revisi / di-drop / specsheet belum terbit, dan stepper revisi)
- [x] **Buat CBD** (`cwCbdForm`): baru dari specsheet / copy dari article lain (model sama, season apa pun) - bila article belum punya CBD; revisi berikutnya - bila sudah ada CBD terbit. Stage = stage specsheet acuan
- [x] Custom Widget **`cwCbdGrid`**: grid per grup a/b/c/d + bagian MISSING_IN_SPEC; edit Yield & Loss % di sel; Usage, harga IDR/USD, cost/pair dari view; keterangan kenapa harga kosong
- [x] Model Detail kolom **CBD** per article (pindahan dari F4)
- ➡️ F8: terbit CBD (pakai ulang `cwPublishForm`), refresh dari specsheet (pakai ulang `fn_cbd_populate`), harga, rekap. Uji F7 menerbitkan CBD sementara lewat DB Tools

**Selesai bila:** baris CBD = baris BOM terbit yang dipakai article (termasuk subkomponen); yield/loss tersalin dari sumber (lineKey → originLineKey → identitas); baris sumber yang hilang jadi MISSING_IN_SPEC.

### F8 - CBD: harga, rekap, refresh, terbit, sinkron
File siap (30 Sep 2026): `sql/F8_cbd_price.sql`, `js/CbdCtrl.js`, `js/CbdGridCtrl.js`, `widgets/cwCbdGrid/` (rekap + banner + tombol harga), `widgets/cwCbdPriceForm/` (baru), `widgets/cwPublishForm/` (opsi `blockedWhere`), `steps/F8_langkah.md`.
- [x] SQL F8 (`fn_cbd_populate` versi array - sumber bisa revisi itu sendiri, `fn_cbd_create` diperbarui, `v_cbd_price_check`, `v_cbd_recap`, `v_cbd_checklist`, `fn_cbd_price_line`, `fn_cbd_check_price`, `fn_cbd_set_quotation`, `fn_cbd_override_price`, `fn_cbd_clear_override`, `fn_cbd_refresh_prices`, `fn_cbd_refresh_from_spec`, `fn_cbd_header_set` (rate/amortisasi/adjustment/target FOB/selling price/margin), `fn_cbd_publish`, `fn_cbd_sync_spec`, `fn_revision_publish` + penandaan sinkron)
- [x] Harga: quotation (material QUOTATION, kosong = tidak dihargai terpisah), override + alasan (material CATALOG), hapus override - modal `mdlCbdHarga` / `cwCbdPriceForm`; info kenapa harga kosong (`price_gap`: quotation, tanpa supplier, harga tersedia, *menunggu approval* F3b, warna lain, tidak ada) - currency wajib dipilih setiap input (tanpa nilai awal)
- [x] Rekap di `cwCbdGrid` (panel ringkasan menempel): exchange rate, amortisasi, adjustment, target FOB, actual FOB, selisih (OVER/UNDER/SESUAI), selling price ⇄ margin %
- [x] Banner + tombol **Refresh dari Specsheet** / **Refresh Harga dari Master** (di `cwCbdGrid`)
- [x] Modal **Terbitkan** CBD (`mdlCbdTerbit`, `cwPublishForm`) + **Riwayat** (tombol + modal `mdlCbdRiwayat`, sama dengan Specsheet F6)
- [x] Terbit specsheet → CBD terbit terakhir article aktif jadi NEEDS_REVISION bila baris/supplier/warna berubah dibanding acuannya (P5); sama → acuan dipindah, IN_SYNC

### F8b - CBD: Cost recapitulation (permintaan user 5 Okt 2026, contoh Excel `FH26_CBD PRODUCTION_ACC ILLUZION IV ELITE FG PRM 097.xlsx`)
File siap (5 Okt 2026): `sql/F8b_cbd_cost.sql`, `js/CbdGridCtrl.js`, `widgets/cwCbdGrid/`, `steps/F8b_langkah.md`.
- [x] SQL F8b (`cbd_cost_item` + `uq_cbd_cost_default` + `trg_lock_published`; amortisasi/adjustment dipindah ke baris default lalu kolomnya di-DROP; `v_cbd_recap` (+ `labour`, `other`, `items_total`, `group_costs`) & `v_cbd_checklist` dibuat ulang; `fn_cbd_cost_label`, `fn_cbd_cost_defaults`, `fn_cbd_check_cost`, `fn_cbd_cost_item`, `fn_cbd_cost_add`, `fn_cbd_cost_set`, `fn_cbd_cost_delete`; `fn_cbd_header_set` tanpa AMORTIZATION/ADJUSTMENT; `fn_cbd_create` meng-copy baris biaya)
- [x] Tabel baris CBD tetap + baris **Subtotal** per grup
- [x] **Cost recapitulation** di bawah grid: Material cost (otomatis) + baris biaya jenis tetap (Direct Labour/LOP, Amortisasi, Adjustment, Lainnya); 3 baris default selalu ada; tambah/hapus baris; ACTUAL FOB, Target FOB, Selisih
- [x] **Harga jual** (tabel terpisah): Selling price ⇄ Margin %
- Tidak dibuat (keputusan user): simulasi FOB tanpa treatment, PO = FOB × markup; tabel dampak perubahan per kategori → Opsional (diff)

**Selesai bila:** angka rekap sama dengan rumus Python (cek 1 contoh manual); terbit ditolak bila specsheet usang / rate kosong / harga master berubah / baris berharga tanpa yield.

### F9 - Export Excel
File: `js/XlsxWriter.js`, `js/SpecExportCtrl.js`, `js/CbdExportCtrl.js`, `steps/F9_langkah.md`. Satu JSObject per page (bukan satu `ExportCtrl`) supaya tidak merujuk query page lain. Terpasang di export v9.5; uji ditunda ke end-to-end.
- [x] ~~Library ExcelJS~~ → diganti JSObject `XlsxWriter` (tanpa library) di page Specsheet & CBD (T43); ExcelJS masih terpasang tapi tidak dipakai (boleh dihapus)
- [x] `SpecExportCtrl.exportExcel()` - layout contoh PDF user *SS_SPECS_…_PROD.pdf* tanpa kotak validasi (T44): judul, FACTORY/REVISION/season/PURPOSE (dari stage), info model, stage·revisi·status + change log, tabel NO · COMPONENT NAME · MATERIAL DESCRIPTION · SOURCE · warna per article · UoM · PROCESS; header berulang tiap halaman, landscape A4
- [x] `CbdExportCtrl.exportExcel()` - layout contoh Excel user (header kurs `1 $ =`, Model/Article/Construction/Color), per grup + Subtotal, MISSING_IN_SPEC (tidak dihitung), Cost recapitulation (F8b) + Actual FOB, Target FOB + OVER/UNDER, Harga jual, change log; sel hitungan = rumus Excel + hasil dari DB
- [x] Tombol `btnSpecExport` / `btnCbdExport` (Visible bila ada revisi dibuka; brand hanya revisi terbit karena draft tidak terbaca query)

**Selesai bila:** file `.xlsx` terunduh, isinya sama dengan layar.

### F10 - Beranda "Tugas Saya"
File siap (5 Okt 2026): `sql/F10_worklist.sql`, `js/BerandaCtrl.js`, `widgets/cwWorklist/` (satu Custom Widget untuk semua role - penyimpangan dari keputusan 10 "Beranda = widget bawaan", alasan: daftar multi-bagian per role; user boleh menolak), `js/SpecCtrl.js` + `js/CbdCtrl.js` (parameter `from=home`, CBD + `article`), `steps/F10_langkah.md`. View: `v_worklist_spec`, `v_worklist_cbd`, `v_worklist_price_gap`, `v_worklist_admin` (+ usulan harga F3b), `v_recent_published`, `v_system_summary`. Query: `q_worklist_spec/proposals/cbd/gap/admin/pub_spec/pub_cbd/system`. P6: "terbit terbaru" memakai urutan stage + nomor revisi.
- [x] (dibuat, belum diverifikasi) SQL F10 (`v_worklist_spec`, `v_worklist_cbd`, `v_worklist_admin`, `v_recent_published`)
- [ ] Per role: Vendor Spec (draft berjalan, article belum masuk revisi) · Vendor CBD (belum ada CBD, perlu refresh, perlu revisi, harga master kosong) · Master Admin (antrian PROPOSED, termasuk usulan harga F3b) · Brand (terbit terbaru) · System Admin (ringkasan)

**Selesai bila:** setiap role melihat daftar yang benar, klik membuka page tujuan.

### F10b - Revisi dari uji end-to-end (5 Okt 2026)
File: `sql/F10b_revisi_uji.sql`, `steps/F10b_langkah.md`, JS `LoginCtrl`, `SupplierCtrl`, `MaterialCtrl`, `MaterialDetailCtrl`,
`SpecCtrl`, `SpecExportCtrl`, `CbdCtrl`, `CbdGridCtrl`, `BerandaCtrl`; widget `cwBomGrid`, `cwMaterialForm`,
`cwSupplierForm`, `cwPublishForm`, `cwCbdGrid`, **`cwImageGallery`** (baru). `RESET_data_uji.sql` + `change_log_attachment`.
Keputusan user 5 Okt 2026:
- ~~Width material~~ **dibatalkan 6 Okt 2026 (F10c)**: user maksud **Thickness**. `sql/F10c_hapus_width.sql` menghapus `material.width`/`width_key`, fungsi material kembali ke parameter F3, view dibuat ulang (view turunan disimpan & dibuat ulang otomatis). Grid BOM: kolom **Thickness** setelah UoM; Excel specsheet: kolom THICKNESS (MATERIAL DESCRIPTION = nama saja). CBD sudah punya kolom Thickness.
- **Supplier usulan**: Vendor (propose_master) bisa menambah supplier → PROPOSED → Master Admin approve.
- **Gambar di change log**: tempel / pilih saat Terbitkan (Specsheet & CBD), lihat di Riwayat.
- **Huruf kapital** "lebih luas": nama & kategori material, nama komponen, supplier, kode & nama model, kode article & colorway,
  nama komponen lokal & subkomponen BOM (trigger `trg_aa_upper`; data lama diubah kecuali baris BOM terbit & kode article terpakai).
- Specsheet **tidak bisa terbit** bila ada baris tanpa supplier atau usulan belum di-approve (keputusan sebelumnya "usulan boleh terbit" dicabut).
- **Override harga katalog dihapus**; **Loss %** default kosong (= 0 %, tidak memblokir); **rate** boleh dikosongkan (memblokir terbit).
- **Revisi awal** = belum ada revisi terbit lain di article (CBD) / season (specsheet) - termasuk hasil copy.
Bug: T47 trigger kunci CBD terbit membandingkan kolom generated `stage_order` (NULL di BEFORE trigger) → penandaan sinkron
(`fn_cbd_sync_spec`) saat terbit specsheet selalu gagal; T48 "harga NaN" di form tolak (baris tabel berisi teks tampilan).

### F11 - Dokumentasi & handover
- [ ] `appsmith/README.md` (panduan operasional): arsitektur (diagram DB ↔ query ↔ JSObject ↔ widget), daftar page & hak akses, cara menambah user / reset password, cara menjalankan SQL di DB Tools, cara export & deploy, cara mengubah matriks hak akses, cara mengubah Custom Widget, troubleshooting (sesi habis, akun terkunci, error constraint)
- [ ] Semua `widgets/<cw>/README.md` sesuai kondisi akhir
- [ ] `PLAN.md` final: semua checklist & register terverifikasi, log review lengkap
- [ ] Skrip SQL gabungan untuk instalasi baru (`sql/install_all.sql` = F1 … F10 berurutan)

**Selesai bila:** orang baru bisa memasang ulang sistem dari DB kosong dan menjalankan tugas admin rutin hanya dengan membaca `README.md`.
*Catatan R:* `install_all.sql` nanti = F1 … F10c lalu R1 … R7.

---

### Alur kerja R (keputusan user 8 Okt 2026)
Appsmith versi ini tidak punya "import ke app yang sudah ada"; import selalu membuat **app baru**. Karena belum UAT, setiap fase R = app baru.

1. Saya siapkan `sql/R<n>_*.sql` → Anda jalankan di **DB Tools**.
2. Anda export app terbaru → `exports/` (= **base**). **Sejak export ini, jangan ubah app** sampai hasil saya di-import (perubahan di UI akan hilang).
3. Saya edit JSON lewat skrip → `exports/build_r<n>.json` + `steps/R<n>_langkah.md` (singkat: import, hal yang perlu dirapikan di UI, uji).
   Validasi sebelum dikirim: JSON terbaca, setiap query/JSObject/widget yang dirujuk ada, params `run()`/`exec()` cocok, sintaks JS (esprima), semua query baca *Manual* + prepared ON, tidak ada `Query1`, diff dibanding base.
4. Anda **import sebagai app baru** → hubungkan ulang datasource `Prestasi` bila diminta → cek akses publik → Deploy → uji → rapikan posisi/ukuran widget di UI.
5. Lolos → app lama diarsipkan, app baru di-rename → export → `exports/export_r<n>.json` → saya review → base fase berikutnya.

**Perubahan alur 11 Okt 2026 (keputusan user):** R3–R7 dikerjakan berurutan tanpa import per fase → **satu file SQL** `sql/R_revisi_semua.sql` (gabungan `sql/R3_…`–`R7_…`, satu transaksi) + `sql/R_selftest.sql` (uji alur inti lalu ROLLBACK, dijalankan sebelum import) + **satu import** `exports/build_r7.json` (build berantai: `build_r3` dari `export_r2`, `build_r4` dari `build_r3`, …) → uji **E2E-R** (`steps/E2E_R_uji.md`). Setiap fase dicek ulang sebelum lanjut: parser SQL (pglast), `tools/check.sh` terhadap build sebelumnya, harness widget, uji logika JSObject dengan data contoh. Detail kecil diputuskan sesuai PLAN dan dicatat di fase masing-masing ("Keputusan detail").

Aturan tetap: **jangan upgrade Appsmith** di tengah R (export sekarang `serverSchemaVersion` 12). Git sync = pilihan setelah go-live.
Filter pabrik dikerjakan **di setiap fase** pada query/fungsi yang disentuh; R6 menyapu sisanya.

### R1 - Fondasi: pabrik, role, matriks izin
SQL `sql/R1_fondasi.sql` (didahului `RESET_data_uji.sql`; keputusan user: data uji boleh di-reset). Build `exports/build_r1.json` = salinan `export_v11.json` yang diedit (`tools/build_r1.py`, validasi `tools/check.sh`). Panduan `steps/R1_langkah.md`.
- [x] (dibuat) Tabel `factory` (nama unik huruf besar, ACTIVE/INACTIVE, tidak bisa nonaktif selama ada user aktif) + `fn_factory_save` (`manage_factory`) + `v_factory_list`
- [x] (dibuat) `app_user.factory_id`: **wajib** untuk VENDOR_SPEC / VENDOR_CBD / MANAGER_COSTING, **kosong** untuk BRAND_VIEWER / SYSTEM_ADMIN (`ck_app_user_factory`); ganti role/pabrik → sesi user ditutup
- [x] (dibuat) Role: `MASTER_ADMIN` dihapus, `MANAGER_COSTING` ditambah (`ck_app_user_role`, `fn_role_label`, `fn_is_factory_role`); `role_permission` = matriks §5 "Mulai R1" (32 baris; `manage_material_supplier` Vendor Spec masih ada sampai R2)
- [x] (dibuat) `fn_me` + `factory_id`, `factory_name`; helper `fn_user_factory`, `fn_can_see_factory`, `fn_assert_factory`
- [x] (dibuat) Tambalan transisi (teks fungsi terpasang diganti): approve/tolak/akhiri harga = `approve_price`; usulan harga tidak pernah langsung APPROVED; `fn_ensure_link` → APPROVED
- [x] (dibuat) Admin: tab **Pabrik** (`tblFactories`, `btnPabrikTambah`, `mdlPabrik` + `cwFactoryForm` baru), form user + pilihan pabrik (`cwUserForm`), kolom Pabrik di `tblUsers`; `q_factories`, `a_factory_save` baru; `q_users`, `a_user_save` diubah
- [x] (dibuat) Header semua page: role + pabrik. Menu tetap dari izin (`Auth.can`) - tidak ada kode khusus Master Admin di menu
- [x] (dibuat) Beranda: `MANAGER_COSTING` → antrian usulan harga (`q_worklist_admin` pakai `approve_price`, kind PRICE)
- [x] (dibuat) Material Detail: Approve/Tolak/Akhiri = `canApprovePrice()`, Batalkan = Vendor CBD; teks "Master Admin" di harga → "Manager Costing" (`MaterialDetailCtrl`, `cwPriceForm`, `CbdGridCtrl`, `cwCbdGrid`)
- [x] (dibuat) T49–T52 diperbaiki langsung di JSON
- [x] Import + uji A1–A13 lolos (user, 8 Okt 2026); tombol Ubah pabrik ditambah manual oleh user
- [x] `export_r1.json` diterima (8 Okt 2026): sama dengan build R1, kecuali `q_factories` & `q_change_log_images` kembali *Automatic* setelah import → **T53** (diperbaiki di R2)

**Selesai bila:** 2 pabrik + satu user per role per pabrik bisa login; menu sesuai role; user role pabrik tanpa pabrik ditolak.

### R2 - Master tanpa approval, Material Induk + Varian, pilihan model
SQL `sql/R2_master.sql` (didahului `sql/RESET_data_bisnis.sql` = hapus data master/dokumen uji, **user & pabrik tetap**). Build `exports/build_r2.json` = salinan `export_r1.json` (`tools/build_r2.py`). Panduan `steps/R2_langkah.md` (uji B1–B17).
- [x] (dibuat) Supplier & komponen (bersama): status ACTIVE/INACTIVE saja (`ck_*_status`); `fn_supplier_save`, `fn_component_save` (+ `fn_component_add` tanpa usulan): ubah nama (komponen: nama/nomor/kelompok) ditolak bila dipakai dokumen terbit pabrik mana pun, INACTIVE ditolak bila dipakai draft (`fn_master_usage`)
- [x] (dibuat) `fn_similar_names(token, kind, text, exclude)` + `fn_similar_key`/`fn_similar_match` (abaikan PT/CV/Tbk/UD/Persero, tanda baca, spasi; cocok bila saling memuat) - form supplier, komponen, material (pabrik user), pilihan model; event `onSearch` di Custom Widget, hasil lewat `q_similar`
- [x] (dibuat) `material` = **induk** + `factory_id` (wajib); unik `(factory_id, name_key, uom)`; `material_code`/`thickness` lama dikosongkan trigger (kolom dihapus di R4); `fn_material_add(token, nama, kategori, uom)` selalu CATALOG; `fn_material_update` metode harga hanya `manage_price`
- [x] (dibuat) `material_variant` (thickness mm boleh kosong, warna & kode huruf besar, kode unik per pabrik, varian unik per induk+thickness+warna, ACTIVE/INACTIVE) + `fn_variant_add` (jsonb, semua-atau-tidak) + `fn_variant_update`; **kunci kode setelah dipakai dokumen terbit → R4** (kolom `bom_cell.variant_id` belum ada)
- [x] (dibuat) `material_supplier` = induk × supplier tanpa approval; `supplier_material_code` dihapus (+ field `cwLinkForm`, kolom `tblLinks`); `fn_link_save` baru (tanpa kode, `manage_master`, cek pabrik), `fn_ensure_link` → ACTIVE
- [x] (dibuat) PROPOSED/APPROVED master hilang: tombol Approve (`tblComponents`, `tblMaterials`, `tblLinks`), query `a_component_set_status`, `a_material_set_status`, `a_link_set_status`, `q_worklist_proposals` dihapus; kartu usulan di Beranda dihapus; `v_worklist_admin` = PRICE saja; izin `propose_master` & `manage_material_supplier` dihapus
- [x] (dibuat) Material Code tanpa prefill (`next_code` dihapus dari `q_material_meta`, tombol "Pakai saran" hilang)
- [x] (dibuat) `model_option` (kind, factory kosong = bersama, nilai huruf besar, urutan, status; `ck_model_option_scope`: LAST/OUTSOLE_MOLD wajib pabrik, lainnya bersama) + `fn_option_save`; seed GENDER (LAKI-LAKI/PEREMPUAN/UNISEX) & UKURAN 35–47 (angka bulat, urut otomatis)
- [x] (dibuat) UI: Master Supplier & Komponen tanpa approve + daftar nama mirip; Master Material = daftar induk (kolom Pabrik, Varian; cari per kode); Material Detail: header info + **tab Varian | Supplier** (`tabMaterial`, salinan bentuk `tabAdmin`), `tblVariants` + `mdlVarian`/**`cwVariantForm`** (thickness × warna → kode per baris), `cntHarga` disembunyikan (R3); page baru **Master Pilihan** (`selPilihanJenis`, `tblPilihan`, `mdlPilihan`/**`cwOptionForm`**, `OptionCtrl`)
- [x] (dibuat) Query material difilter pabrik user (`fn_can_see_factory` di `q_materials`, `q_material`, `q_links`, `q_variants`, `q_material_meta`, `q_similar`); fungsi tulis material/varian/link memanggil `fn_assert_factory`
- [x] (dibuat) T53: semua query Manual diberi `userSetOnLoad = true` (cegah berubah Automatic saat import)
- [x] **R2b** (keputusan user 8 Okt 2026, setelah melihat `MATERIAL CODE.xlsx` = 845 kode ERP): form kombinasi thickness × warna **dihapus** (membingungkan) → varian **satu baris** (Material Code, warna, thickness) + *Simpan & tambah lagi*; `sql/R2b_varian.sql`: `thickness_mm` → **`thickness` teks persis ERP** (`.`/kosong = tanpa), `uq_variant_identity` (induk, thickness, warna) tetap **menolak** kode ganda (kasus T-160 WHITE 44"); kode ERP 10 karakter = 4 jenis · 3 thickness · 3 warna: di satu pabrik 3 tengah/3 akhir harus konsisten (trigger menolak bentrok), form mengisi & mengunci thickness/warna lewat `fn_variant_code_hint` (`q_code_hint`, event `onLookup`); **4 depan tidak dipakai sebagai identitas** (pilihan user "C": tanpa koordinasi kode dengan vendor) - hanya peringatan bila awalan beda dari varian lain di induk yang sama; Mea = UoM induk (label "Mea (UoM)", **teks bebas** - keputusan user 8 Okt 2026, bukan dropdown; saran diambil dari Mea material yang sudah ada); `fn_variant_save` menggantikan `fn_variant_add/update`; impor data ERP **ditunda** (fokus sistem dulu). Build `tools/build_r2b.py` dari `export_r2a.json`
- [x] Validator: kolom hasil query yang tabelnya `{{q_x.data}}` wajib terdaftar di `primaryColumns` (pglast) - mencegah kolom muncul sendiri (temuan user di build R2: `tblMaterials` menampilkan active_variant_count, thicknesses, …)
- [x] Import `build_r2b.json` + uji B1–B17 lolos (user, 8 Okt 2026) → `export_r2.json` (identik dengan build; semua query tetap Manual → T53 selesai)

Masa transisi (disengaja): Specsheet & CBD belum memakai varian (R4/R5) dan harga disembunyikan (R3) - page itu tidak diuji di R2.

**Selesai bila:** Vendor Spec pabrik A membuat induk + varian + link tanpa approval; pabrik B tidak melihat material A; kode ganda di pabrik yang sama ditolak; nama supplier mirip muncul saat mengetik.

### R3 - Harga Varian × Supplier, approval Manager Costing
SQL `sql/R3_harga.sql`. Build `tools/build_r3.py` → `exports/build_r3.json` (base `export_r2.json`).
- [x] (dibuat) `material_price` + `variant_id` (wajib) + `batch_id` (satu pengajuan); `uq_price_one_proposed` = (supplier material, varian) PROPOSED; kolom `color`/`color_key` dibiarkan kosong sampai R5 (masih dibaca `v_cbd_line` lama); `fn_price_add/approve/reject` di-DROP
- [x] (dibuat) `fn_price_propose` (satu supplier + banyak varian, semua-atau-tidak), `fn_price_copy` (harga berlaku varian sumber dari semua supplier aktif → varian tujuan, pasangan yang masih menunggu / bertanggal lebih baru dilewati & dilaporkan), `fn_price_cancel` - `manage_price`, cek pabrik
- [x] (dibuat) `fn_price_decide(ids jsonb, APPROVE|REJECT, alasan)` (banyak baris, semua-atau-tidak, tidak bisa memproses usulan sendiri, approve ditolak bila material Quotation / supplier atau link nonaktif / varian INACTIVE), `fn_price_end` - `approve_price`; `fn_price_activate` menutup harga lama varian + supplier
- [x] (dibuat) `fn_price_lookup(variant, supplier, tanggal)`: APPROVED, CATALOG, supplier & link ACTIVE (F10d); versi warna lama (dipakai CBD lama) tidak mengembalikan harga sampai R5
- [x] (dibuat) View `v_material_price` (semua baris harga + baris **BELUM ADA HARGA** per varian ACTIVE × link ACTIVE), `v_price_pending` (+ harga yang akan ditutup, `problem`), `v_worklist_admin` per pengajuan (+ `factory_id`)
- [x] (dibuat) UI Material Detail: tab **Harga** (tab ke-3, hanya `view_price`; isi `cntHarga` dipindah, `cntHarga` dihapus) - `tblPrices` satu baris per harga / pasangan (Material Code, Warna, Thickness, Supplier, …), tombol per baris **Ajukan** (Vendor CBD) · **Setujui / Tolak** · **Akhiri** (Manager Costing) · **Batalkan** (Vendor CBD); tombol atas **+ Ajukan Harga** & **Salin Harga**; `cwPriceForm` ditulis ulang (mode propose / copy); query `a_price_propose`, `a_price_copy`, `a_price_decide` (baru), `a_price_add/approve/reject` dihapus
- [x] (dibuat) Page baru **Persetujuan Harga** (salinan Beranda; `Auth.requiredPerm = approve_price`) dengan Custom Widget baru **`cwPriceApproval`** + `ApprovalCtrl`, `q_price_pending`, `a_price_decide`; Beranda Manager Costing → satu baris per pengajuan, klik membuka page itu (`?batch=`); menu Beranda + item **Persetujuan Harga**

Keputusan detail (Claude, 11 Okt 2026, sesuai PLAN): "matriks varian × supplier" = tabel satu baris per pasangan (bukan kolom dinamis per supplier) + baris BELUM ADA HARGA; satu pengajuan = satu harga untuk semua varian yang dicentang; setujui di page Persetujuan Harga **dan** per baris di Material Detail; Setujui di page persetujuan = dua klik; Salin harga hanya di dalam material yang sama (supplier material per induk).

**Selesai bila:** Vendor CBD mengajukan 4 varian sekaligus; Manager Costing menyetujui 3, menolak 1 dengan alasan; harga lama tertutup saat approve; Manager Costing tidak bisa mengajukan; Vendor CBD tidak bisa approve/akhiri.

### R4 - Model tanpa kode + Specsheet per varian
SQL `sql/R4_model_specsheet.sql`. Build `tools/build_r4.py` (helper `tools/rlib.py`) → `exports/build_r4.json` (base `build_r3.json`).
- [x] (dibuat) `product_model`: kolom `code`, `factory`, `category`, `outsole_mold`, `last_no`, `construction`, `size_range`, `sample_size` (teks) dihapus → `factory_id` (otomatis pabrik user), `name_key` + `uq_model_name` (pabrik, nama), `category_id` (wajib) / `construction_id` / `gender_id` / `last_id` / `outsole_mold_id` → `model_option`, `sizes integer[]`, `sample_size integer` (harus salah satu ukuran); `fn_model_save`, `fn_model_option_ref`, `fn_size_label` ("37–40, 42–44"); view **`v_model`** (nama pilihan + alias kolom lama `factory`, `category`, `last_no`, `size_range`… supaya Specsheet/CBD/export tetap membaca nama yang sama)
- [x] (dibuat) Penjaga pabrik tulis: `fn_auth_in` + `fn_model_factory` / `fn_sheet_factory` / `fn_article_factory` / `fn_rev_factory` / `fn_line_factory`; `fn_season_add`, `fn_article_save`, `fn_article_delete`, `fn_attachment_add` (+cek pabrik), `fn_attachment_delete` menggantikan INSERT/UPDATE/DELETE langsung di query; semua query baca Model List / Model Detail / Specsheet / Beranda difilter `fn_can_see_factory`
- [x] (dibuat) `bom_line.thickness` (teks ERP); `bom_cell.variant_id` + `is_used` = warna tidak kosong; trigger `trg_bom_cell_variant` (warna huruf besar + cari varian ACTIVE induk + thickness + warna) dan `trg_variant_relink` (varian baru/berubah → sel draft tersambung / jadi kuning)
- [x] (dibuat) `fn_bom_add_line` (+ thickness, + `p_fill_color`), `fn_bom_add_sub`, `fn_bom_replace_material` (induk dan/atau thickness), `fn_bom_set_supplier`, `fn_bom_set_process` (baru), `fn_bom_cell_set` (Material Code diketik → warna; kode material/thickness lain ditolak), `fn_bom_check_material(material, pabrik)`, `fn_bom_check_supplier` (supplier ACTIVE); komponen master = ACTIVE (bukan APPROVED)
- [x] (dibuat) `v_bom_grid` (+ `cell_codes`, `yellow`; `material_code` = kode-kode baris), `v_revision_checklist` (+ `yellow_cells`, `yellow_list`, `inactive_suppliers`; − `proposed_items`), `fn_revision_publish` (blokir sel kuning & supplier/link INACTIVE = **F10d**), `v_worklist_spec` (+ sel kuning), `v_worklist_price_gap` per varian, `v_worklist_cbd`, `v_recent_published` (+ pabrik), `v_model_list` - semua tanpa kode model
- [x] (dibuat) `fn_variant_save`: kode/warna/thickness dikunci bila dipakai dokumen terbit (`fn_variant_used_published`, R5 menambah CBD); `fn_option_save`: ubah nilai ditolak bila dipakai model ber-specsheet terbit (UKURAN: dipakai model mana pun); INACTIVE selalu boleh
- [x] (dibuat) UI: `cwModelForm` ditulis ulang (dropdown + **grid ukuran ala kalender** + sample size dari ukuran terpilih), `q_model_options`, `tblModels` tanpa Kode (+ Gender, Pabrik); `cwBomGrid`: material = NAMA · THICKNESS / Material Code (+ tawaran isi warna ke semua article), sel = warna / kode, **sel kuning + Daftarkan**, **+ Supplier baru**, badge usulan dihapus; modal `mdlVarianBaru` (salinan `cwVariantForm`, opsi baru `fixed`) & `mdlSupplierBaru` (salinan `cwSupplierForm`) di Specsheet; checklist terbit (sel kuning, supplier nonaktif); Beranda/Specsheet/CBD memakai nama model; export specsheet: sel = warna + Material Code, header Gender
- [x] Tetap ada sampai R5: `material.material_code` / `material.thickness` (masih dibaca view CBD)

Keputusan detail (Claude, 11 Okt 2026): Kategori wajib (dipakai filter copy R7), pilihan lain opsional; warna sel disimpan huruf besar; tawaran "isi warna" hanya di baris tambah (ganti material tidak mengisi sel kosong - sel kosong = tidak dipakai); daftar material di grid = kombinasi induk × thickness dari varian ACTIVE (+ induk tanpa varian); daftarkan varian dari specsheet mengunci warna & thickness.

**Selesai bila:** contoh RUNNER-X (Black/White/Navy) berjalan seperti diskusi: Navy kuning → didaftarkan → tersambung → terbit; pabrik B tidak melihat model A.

### R5 - CBD per varian, PO SMS, selling price keluar dari CBD
SQL `sql/R5_cbd.sql`. Build `tools/build_r5.py` → `exports/build_r5.json` (base `build_r4.json`).
- [x] (dibuat) `cbd_line.variant_id` + `thickness` (dari sel/baris specsheet; `color` tetap untuk tampilan); `fn_cbd_expected_lines` (+ thickness, varian), `fn_cbd_identity` (+ thickness), `fn_cbd_populate`: harga master `fn_price_lookup(varian, supplier)`, quotation ikut bila **varian sama**
- [x] (dibuat) `v_cbd_price_check` per varian: `price_gap` (QUOTATION / NO_SUPPLIER / AVAILABLE / PENDING / NO_PRICE) + `pending` (ada usulan menunggu untuk varian + supplier); `v_cbd_checklist` + `pending_prices`, `pending_list`; `fn_cbd_publish` **menolak terbit selama ada harga menunggu**; `fn_cbd_sync_spec` membandingkan (baris, supplier, varian)
- [x] (dibuat) `stage_setting(stage, po_factor)` seed SMS = 1,25 (stage lain kosong); `cbd_revision.po_factor` dibekukan saat terbit; `v_cbd_recap` + `stage`, `po_factor`, `po_price` (Target FOB tetap dibanding Actual FOB tanpa faktor)
- [x] (dibuat) `cbd_revision.selling_price` dihapus; `fn_cbd_header_set` hanya RATE / TARGET_FOB; `v_cbd_recap` tanpa margin
- [x] (dibuat) Penjaga pabrik semua tulis CBD (`fn_cbd_factory`, `fn_cbd_line_factory`, `fn_cbd_item_factory` + `fn_auth_in`) dan query baca page CBD; Manager Costing baca saja (tanpa `edit_cbd`)
- [x] (dibuat) Kolom lama dihapus: `material.material_code`, `material.thickness`, `material_price.color/color_key`, `fn_price_lookup` versi warna; `fn_material_check` tanpa kolom lama; `fn_variant_used_published` + CBD terbit; `fn_cbd_clear_override` hanya memberi pesan
- [x] (dibuat) UI: banner & status baris "menunggu persetujuan", checklist terbit + "tidak ada harga menunggu", baris **PO SMS** di rekap atas & Cost recapitulation, tabel Harga jual diganti **Simulasi harga jual** (hanya `simulate_margin` = Brand; dihitung di layar dari Actual FOB, tidak disimpan, tidak ikut export); export CBD: blok Harga jual dihapus, baris PO SMS (rumus Excel), Material Code = kode varian

Keputusan detail (Claude, 11 Okt 2026): "menunggu persetujuan" memblokir terbit walau baris sudah punya harga lama (harga bisa berubah); simulasi memakai Actual FOB (bukan PO); faktor PO hanya diubah lewat DB (`stage_setting`), belum ada layar.

**Selesai bila:** CBD tidak bisa terbit selama ada harga menunggu; PO SMS = FOB × 1,25 hanya di SMS; role pabrik tidak melihat selling price/margin; Brand bisa simulasi tanpa menyimpan.

### R6 - Tugas Saya, Brand lintas pabrik, export, sapu bersih pabrik
SQL `sql/R6_tugas_pabrik.sql`. Build `tools/build_r6.py` → `exports/build_r6.json` (base `build_r5.json`).
- [x] (dibuat) Tugas Saya: Vendor Spec (draft + sel kuning + supplier nonaktif, statistik sel kuning - R4/R6) · Vendor CBD (CBD dibuat/refresh/revisi, flag harga menunggu, harga belum ada per Material Code, **usulan harga ditolak** 30 hari & belum diajukan ulang = `v_worklist_price_rejected` + `q_worklist_rejected`) · Manager Costing (pengajuan menunggu - R3) · Brand (terbit terbaru + nama pabrik) · System Admin (tetap); antrian Master Admin sudah dihapus (R2)
- [x] (dibuat) Brand / System Admin: kolom Pabrik + **filter Pabrik** (`selModelPabrik`, `q_model_factories`) di Model List; dropdown model Specsheet/CBD berlabel "MODEL · PABRIK" (R4)
- [x] (dibuat) Export: specsheet sel = warna + Material Code, header Gender (R4); CBD: Material Code varian di kolom material, baris PO SMS, tanpa selling price/margin (R5), nama pabrik di baris Model Name
- [x] (dibuat) Sapu bersih (dipindai otomatis): semua fungsi tulis ber-token memakai `fn_auth_in` / `fn_assert_factory` kecuali master bersama (supplier, komponen), admin (user, pabrik), login - `fn_change_log_attach` ditambah cek pabrik; semua query baca dokumen memakai `fn_can_see_factory` kecuali Admin, master bersama, dan login - `q_worklist_pub_spec/cbd` ditambah filter pabrik

Keputusan detail (Claude, 11 Okt 2026): Material Code di export CBD tetap di kolom deskripsi material "[KODE]" (tidak menambah kolom supaya rumus kolom L tidak bergeser); nama pabrik CBD disisipkan ke baris Model Name (tata letak header tidak berubah).

**Selesai bila:** user pabrik A tidak bisa membaca/menulis data pabrik B lewat query mana pun (diuji juga dengan memanggil query langsung).

### R7 - Copy lintas model
SQL `sql/R7_copy_model.sql`. Build `tools/build_r7.py` → **`exports/build_r7.json`** (base `build_r6.json`; build yang di-import).
- [x] (dibuat) **Specsheet**: `fn_revision_create` mode COPY menerima season model lain bila **pabrik sama + kategori sama** (aturan COPY tetap: r0, sumber revisi terbit terakhir, `origin_line_key`, article season tujuan, warna kosong); wizard Buat Revisi + pilihan **Copy dari model lain** (`cwRevisionForm` mode `COPY_MODEL`, `q_copy_model_sources`: nama model, mold, season, label revisi, ringkasan jumlah baris)
- [x] (dibuat) **Model induk**: `product_model.parent_model_id` diisi otomatis pada copy lintas model pertama; header revisi "disalin dari MODEL · SEASON · STAGE r#" (`q_revisions.source_model`); `fn_sheet_origin_model`
- [x] (dibuat) **CBD**: `fn_cbd_create` COPY menerima article **model asal specsheet** (`q_cbd_sources` + `is_cross`, label "(model asal)"); `fn_cbd_populate(…, p_cross)`: lintas model = Yield/Loss hanya lewat `origin_line_key` **dan** induk + thickness sama, identitas & baris pengganti dimatikan, quotation bila varian sama
- [x] (dibuat) **Rekap lintas model**: hanya exchange rate & LOP (Direct Labour) yang ikut; Amortisasi/Adjustment/Lainnya default 0; Target FOB kosong

**Selesai bila:** copy FG → IN, ganti material outsole, terbit, CBD IN dari CBD FG (yield outsole kosong, amortisasi 0, LOP & rate ikut); sumber pabrik/kategori lain tidak muncul.

### Verifikasi R3–R7 (11 Okt 2026, sebelum diserahkan)
- PostgreSQL 16.4 lokal (binari resmi EDB, disetujui user): seluruh SQL F1 → R2b dijalankan berurutan, lalu `RESET_data_bisnis` + `R_revisi_semua` **2×** (aman diulang) - tanpa error.
- `sql/R_selftest.sql`: **87 cek** alur inti per role dengan 2 pabrik (harga, maker-checker, pemisahan pabrik, sel kuning, F10d, kunci varian/pilihan, CBD per varian, blokir harga menunggu, PO SMS beku, simulasi tanpa simpan, sinkron perlu revisi, Tugas Saya, copy lintas model) - lolos.
- Semua **135 query app** lolos `EXPLAIN` di skema akhir; semua query baca dijalankan sungguhan dengan token per role pada data self-test.
- Validator build tiap fase (tanpa error baru), cek sintaks JS, harness browser untuk `cwPriceForm`, `cwPriceApproval`, `cwModelForm`, `cwBomGrid`, `cwCbdGrid`, `cwRevisionForm` + uji logika JSObject dengan data contoh.
- Bug yang tertangkap & diperbaiki selama verifikasi: urutan DROP view R3 saat diulang; kondisi "diajukan ulang" di `v_worklist_price_rejected`; argumen `fmt` PO; pilihan bawaan GENDER/UKURAN hilang setelah `RESET_data_bisnis` (sekarang diisi ulang di R4).

### E2E-R - Uji ulang dari DB kosong
- [ ] 2 pabrik, 1 user per role per pabrik + Brand + System Admin; data dari contoh Excel FH26 (SMS, GTM)
- [ ] Alur lengkap: master → harga (ajukan, tolak sebagian, setujui) → model → specsheet (sel kuning, daftar varian) → terbit → CBD (menunggu harga → blokir → approve → refresh) → terbit → PO SMS → Brand simulasi → export
- [ ] Silang pabrik: setiap role pabrik B tidak melihat data pabrik A

### Perbaikan manual setelah E2E-R (12 Okt 2026, ditempel user; sudah ada di `export_r7.json`)
- **Antrean aksi + ack** di `cwBomGrid` + `BomCtrl` dan `cwCbdGrid` + `CbdGridCtrl`: aksi sel dikirim satu per satu, berikutnya setelah `doneSeq` (ack) - sebelumnya aksi tertimpa saat ketik cepat dan nilai yang dipulihkan setelah render ulang tidak pernah dikirim (warna/Yield "tersimpan" di layar, hilang setelah refresh). Sel juga disimpan saat blur; nilai terkirim tampil sampai antrean kosong; kirim ulang bila tanpa ack 5 detik.
- `CbdGridCtrl.savePrice()`: cabang override (query `a_cbd_override_price` sudah dihapus F10b) dibuang. Sisa bug `q is not defined` setelah simpan quotation diperbaiki di R8.
- `R_selftest.sql`: data uji memakai `@selftest.invalid` / `SELFTEST PABRIK A/B` (bentrok dengan `brand@uji.test` buatan user).
- `R_selftest.sql` aman di DB berisi data (laporan user 12 Okt 2026: nomor komponen 10 sudah dipakai): master bersama memakai nama berawalan SELFTEST (supplier, komponen, Kategori), nomor komponen = kelipatan 10 kosong pertama kelompok 'a', cek view lintas pabrik dibatasi material/pabrik uji. Diuji di DB tiruan (komponen 10/20/30, supplier & kategori bernama sama/mirip, data pabrik user dengan kode & article sama): lolos 2×, jumlah baris semua tabel sama sebelum/sesudah.

### R8 - Catatan uji E2E-R (12 Okt 2026)
SQL `sql/R8_catatan_uji.sql` (setelah `R_revisi_semua`; aman diulang). Build `tools/build_r8.py` → **`exports/build_r8.json`** (base `export_r7.json`). Panduan `steps/R8_uji.md`.
- [x] **1. Manager Costing mengajukan harga = langsung berlaku**: izin `manage_price` untuk Manager Costing; `trg_price_self_approve` (AFTER INSERT `material_price`): pengaju yang punya `approve_price` → `fn_price_activate` (penyetuju = dirinya). Berlaku untuk Ajukan, Salin Harga, dan ajukan dari CBD. Usulan Vendor CBD tetap PROPOSED. UI: tombol *+ Tambah Harga*, form *Simpan*, pesan "langsung berlaku".
- [x] **2. Switch Tampilkan riwayat** (keputusan user): OFF = sembunyikan harga yang sudah berakhir **dan** DITOLAK yang sudah diganti (ada usulan/harga baru untuk varian × supplier yang sama sesudah ditolak - aturan sama dengan kartu Beranda) atau lebih dari 30 hari (`MaterialDetailCtrl.pricesShown`).
- [x] **3. Article per season tanpa batas**: `fn_article_check` tanpa batas 5; tombol *+ Article (n)*, teks Model Detail & `cwArticleForm` tanpa "maks. 5". Export Excel specsheet sudah dinamis.
- [x] **4. Awalan Material Code wajib sama** (keputusan user: blokir): `trg_material_variant_prefix` - kode 10 karakter dengan 4 karakter depan berbeda dari varian lain di material yang sama ditolak (hanya saat varian baru / kode diubah, jadi data lama tetap bisa diubah statusnya); `cwVariantForm` memblokir sebelum simpan. Pengecekan lain tetap: kode unik per pabrik, warna + thickness unik per material, kode thickness (5–7) & warna (8–10) konsisten se-pabrik.
- [x] **5. Ajukan harga master dari CBD** (keputusan user: modal di halaman CBD): tombol *Ajukan harga master* (Manager Costing: *Harga master baru*) di kolom Harga baris katalog yang punya Material Code + supplier dan tidak sedang menunggu (revisi DRAFT, izin `manage_price`) → `cwCbdPriceForm` mode `PROPOSE` (harga, currency, berlaku mulai, referensi) → `a_cbd_price_propose` → `fn_cbd_price_propose` → `fn_price_propose` (bukan override; approval sama; banner "menunggu" langsung muncul; setelah disetujui → Refresh Harga dari Master).

**Verifikasi:** PostgreSQL lokal: R8 2× tanpa error di atas skema R7; `R_selftest.sql` **102 cek** lolos (+15 cek R8, +1 cek nomor komponen kosong; cek lama "Manager Costing tidak bisa mengajukan" dihapus); 137 query `EXPLAIN` (1 error = `Query1` buatan user berisi `ROLLBACK;`, aman); validator tanpa error baru; harness `cwCbdPriceForm`, `cwCbdGrid`, `cwVariantForm`, `cwPriceForm` + uji logika `MaterialDetailCtrl.pricesShown` & `CbdGridCtrl.savePrice/priceFormModel`.

### R10 - Hapus varian (12 Okt 2026, permintaan user; dipasang manual)
SQL `sql/R10_hapus_varian.sql`: `fn_variant_delete_block(varian)` = alasan tidak bisa dihapus (dipakai sel specsheet / baris CBD mana pun, atau masih punya harga MENUNGGU APPROVAL / BERLAKU / AKAN BERLAKU); `fn_variant_delete(token, varian)` (izin `manage_master`, cek pabrik) menghapus varian + harga berakhir/ditolaknya; tercatat di `audit_log`. App: `q_variants` + kolom `delete_block`, query `a_variant_delete` (Request confirmation ON), `MaterialDetailCtrl.deleteVariant(row)` (alasan ditampilkan sebagai peringatan), kolom tombol **Hapus** di `tblVariants`. Self-test +7 cek (121 total).

### R9 - Material Code: isi otomatis + kamus kode (12 Okt 2026)
SQL `sql/R9_kode_varian.sql` (setelah R8). Build `tools/build_r9.py` → **`exports/build_r9.json`** (base `build_r8.json` - R8 lolos uji, app tidak diubah). Panduan `steps/R9_uji.md`.
Analisis `MATERIAL CODE.xlsx` (845 kode ERP): awalan per material konsisten 457/458 (CANVAS 6 OZ = 209B & 2100); kode tengah → thickness 1:1; thickness kosong punya beberapa kode (K00/C00/800); kode akhir → warna 1:1 kecuali W10 (WHITE & WHITE C); WHITE/DOVE/PALE KHAKI punya >1 kode; T-160 WHITE 44" punya 2 kode (W01, W10). Usulan kode (uji leave-one-out): lengkap & benar 270/844, 7 karakter pertama benar 478; bila hanya satu pilihan, thickness benar 612/612, warna 555/558.
Keputusan user - **tiga tingkat**:
- [x] **Tolak**: kode dobel; material + thickness + warna dobel (sel specsheet harus menunjuk satu kode; pesan menyarankan bedakan nama warna sesuai ERP, mis. WHITE C).
- [x] **Konfirmasi**: kode thickness / warna sudah berarti lain di pabrik ini (W01 = WHITE diisi CREAM) - `fn_material_variant_check` menolak dengan pesan `Perlu konfirmasi: …` kecuali `fn_variant_save(…, p_confirm = true)` (setelan transaksi `app.variant_confirm`); hanya dicek saat varian baru / kode-warna-thickness berubah. Form: kotak merah + centang "Sudah saya cek, kode ini benar sesuai ERP".
- [x] **Info**: warna / thickness biasanya berkode lain, awalan beda (trigger R8 `trg_material_variant_prefix` dihapus), kode bukan 10 karakter - kotak kuning, tetap bisa simpan.
- [x] **Isi otomatis**: `fn_variant_code_suggest` (awalan dari varian material ini; kode thickness & warna dari varian se-pabrik; paling sering dipakai, seri = paling awal dicatat) → kode langsung terisi di Daftarkan (sel kuning) dan di + Varian setelah warna/thickness diketik; bagian yang belum diketahui dikosongkan; "kode lain: …" ditampilkan; tidak ada tombol pilihan (keputusan user). Arah kode → warna/thickness tetap, isian tidak dikunci lagi.
- Catatan skalabilitas: kamus dibentuk dari data varian per pabrik (tanpa tabel baru); kode pertama menentukan arti (koreksi: ubah varian salah bila belum terbit, atau simpan yang benar dengan konfirmasi). Bila nanti beberapa pabrik berbagi kamus ERP → pertimbangkan master kamus kode eksplisit.

**Verifikasi:** R9 2× tanpa error di DB bersih & DB tiruan data user; `R_selftest.sql` 113 cek (+12 R9); 845 kode ERP dimasukkan lewat trigger: 844 masuk, 1 ditolak (benar); 139 query EXPLAIN; validator tanpa error baru; harness `cwVariantForm` skenario A1–A7, B9–B10, konfirmasi (blokir tanpa centang, `confirm: true` dengan centang), pesan DB `Perlu konfirmasi`. Konten terpanjang form 687 px → modal 760 px.

### R11 - Skalabilitas (uji beban 12 Okt 2026; temuan dikumpulkan dulu)
Alat: `tools/beban/gen_beban.sql` (data sintetis langsung ke tabel), `tools/beban/ukur_beban.py` (semua query `q_*` dari export R9 dijalankan per role: `EXPLAIN ANALYZE`, jumlah baris, ukuran payload), `tools/beban/perbaikan_draft.sql` (perbaikan yang sudah diuji), hasil di `tools/beban/hasil/`. PostgreSQL 16.4 lokal, setelan bawaan (`shared_buffers` 128 MB) - angka absolut tergantung server; yang penting pola pertumbuhannya.
Asumsi volume (1 pabrik): 200 model/season, 2 season/tahun, 4 article, revisi spec PULL/SMS r0–r1/GTM/PROD, BOM 60 baris, CBD PULL/SMS/GTM/PROD per article, ±3.400 varian. **5 tahun** = 2,4 jt sel BOM, 1,9 jt baris CBD, 7 jt baris audit, DB 8 GB. Batas waktu query Appsmith = 10 detik.

| # | Fitur (query) | 1 th | 3 th | 5 th (ms) | Penyebab | Usulan | Status |
|---|---|---|---|---|---|---|---|
| S1 | **Beranda Vendor CBD** (`q_worklist_cbd` / `v_worklist_cbd`) | 658 | **timeout >120 dtk** | timeout | Filter `fn_cbd_article_spec_status(id) = 'ACTIVE'` diperkirakan planner hanya 28 baris (nyatanya hampir semua) → nested loop menghitung ulang `fn_spec_latest_pub` semua specsheet per article. Patah mendadak, bukan pelan | Tulis ulang view: set article dari join biasa (`MATERIALIZED`) - hasil identik (0 beda) | ✅ R11 (~0,7 dtk di 5 th) |
| S2 | **Beranda Vendor CBD - material belum ada harga** (`q_worklist_gap` / `v_worklist_price_gap`) | 1.525 | 4.700 | 9.700–52.000 | Membaca BOM revisi terbit terakhir **semua specsheet semua season** (480 rb sel di 5 th, I/O) + `fn_price_lookup` per baris (152 rb) | (a) cek harga sekali per varian × supplier - diuji, hasil identik, tapi tetap 5–14 dtk; (b) **perlu keputusan cakupan pemakaian** (material memang tanpa season; yang dibatasi adalah specsheet tempat varian dipakai): N season terakhir (2 → 2,7 dtk, 4 → 4,3 dtk, tetap) **atau** hanya article yang CBD-nya belum selesai (belum PROD terbit sinkron / ada draft / NEEDS_REVISION: 259 dari 8.018 article → 0,5–3,6 dtk, tanpa konsep season; risiko: article yang ditinggal tanpa di-drop ikut terus) | ✅ keputusan user 12 Okt 2026: **2 season terakhir** (opsi A) - ✅ R11 (per pabrik, season yang punya specsheet terbit; ±1,5 dtk di 5 th) |
| S3 | Material Detail - daftar varian (`q_variants` → `fn_variant_delete_block`) | 1.530 | 4.310 | 8.600 | `cbd_line.variant_id` tanpa index → scan 1,9 jt baris per varian | `CREATE INDEX idx_cbd_line_variant` | ✅ R11 |
| S4 | Grid CBD, grid BOM, rekap, biaya, artikel revisi (±30 query app) | 178 | 465 | 970 (`q_cbd_lines`) | Filter app `kolom::text = '{{id}}'` → index biasa tidak terpakai, scan seluruh `cbd_line` / `bom_line` | Cepat (DB saja): index ekspresi `((kolom::text))` di 5 tabel besar (±23 MB). Bersih (app): `kolom = nullif({{…}}, '')::uuid` | ✅ R11 (index ekspresi; query app tidak diubah) |
| S5 | Admin - cari audit (`q_audit` + kotak cari) | 3.000 | 42.500 | 88.900 | `ILIKE '%..%'` scan seluruh `audit_log` sampai dapat 200 baris (kata yang jarang/tidak ada = scan penuh) | **Keputusan user: batasi periode** (bukan index trigram 908 MB). 90 hari ≈ 1,1 dtk di data uji (yang menumpuk per season = pesimistis). Perlu ubah `q_audit` (+ pilihan periode di UI) | ✅ keputusan user: **90 hari** - ✅ R11 (`q_audit` + teks `txtAuditInfo`) |
| S6 | Admin - dropdown entitas audit (`q_audit_entities`) | 540 | 1.250 | 13.000 | `SELECT DISTINCT entity` scan seluruh `audit_log` | Loose index scan (`WITH RECURSIVE … min(entity) > …`) pakai `idx_audit_entity` → 0,4 ms; atau daftar entitas tetap | ✅ R11 (`q_audit_entities`) |
| S7 | `audit_log` membengkak | – | 4,3 jt | 7 jt baris = **6,4 GB dari 8 GB** DB | Trigger audit menyimpan baris penuh (jsonb) untuk setiap insert/update; tabel terbesar, memperberat backup (DB dipakai bersama aplikasi lain) | Audit **ramping** (disetujui user 12 Okt 2026, IT tidak merawat rutin) - UPDATE simpan kolom yang berubah saja, INSERT tanpa salinan isi, DELETE lengkap → simulasi 5 th: 6,4 GB → 1,55 GB (±310 MB/th); tanpa penghapusan otomatis; Beranda System Admin menampilkan ukuran + peringatan > 3 GB | ✅ R11 (`fn_audit_trigger`, `v_system_summary.audit_size_bytes`, `BerandaCtrl.systemModel`) |
| S8 | Beranda System Admin (`q_worklist_system`) | 149 | 403 | 700 | `count(*)` seluruh `audit_log` & tabel lain tiap Beranda dibuka | Angka perkiraan (`pg_class.reltuples`) atau dihitung berkala | ✅ R11 (perkiraan; 12 ms) |
| S9 | Model List & Master Material - **baris terpotong diam-diam** | – | – | 650 model > `LIMIT 500` | `q_models` / `q_materials` `LIMIT 500` tanpa tanda | Tampilkan "500 dari N - persempit pencarian" atau paging server | ✅ R11 (`total_count`, `txtModelLimit` / `txtMaterialLimit`) |
| S10 | `v_cbd_checklist.pending_list` | 449 | 18 | 28 | Join `v_cbd_line` tanpa filter revisi → di 1 th scan seluruh `cbd_line` (plan sekarang kebetulan bagus) | Tambah `AND v.cbd_revision_id = r.id` | ✅ R11 |
| S11 | Specsheet - dropdown varian (`q_bom_options`) | 873 KB | 873 KB | 873 KB | Semua varian aktif pabrik dikirim ke browser tiap Specsheet dibuka; tumbuh dengan jumlah varian (bukan season) | Aman di ±3.400 varian; pantau bila > 10 rb (cari di server) | ⬜ pantau |
| S12 | Specsheet `q_season_colors`, Beranda `q_worklist_spec` | 292 / 163 | 345 / 162 | 746 / 459 | Tumbuh pelan seiring jumlah specsheet | Belum perlu | ⬜ pantau |

Urutan patah (tanpa perbaikan): **S1 di ±3 tahun** (Tugas Saya Vendor CBD kosong/timeout) → S2 di ±5 tahun (lebih cepat bila cache server kecil) → S3 lambat (8,6 dtk di 5 th); S5 (cari audit) sudah lewat 10 dtk di ±3 tahun dan S6 di ±5 tahun, tapi hanya Admin. S9 sudah salah tampil di ±5 tahun.

**Dibuat (12 Okt 2026):** `sql/R11_perbaikan.sql` (setelah R10, aman diulang, satu transaksi) + `exports/build_r11.json` (`tools/build_r11.py`, base `exports/export_r10.json`) + panduan `steps/R11_uji.md`.
**Verifikasi:** R11 2× tanpa error di DB bersih; `R_selftest.sql` **163 cek** lolos (+42 cek R11: audit ramping, T54, T55, T57, S2, T58 + grid, A1/T56, A4 jumlah rincian = selisih FOB persis, kategori/uraian vendor tersimpan, Brand membaca rincian terbit); uji balapan 2 sesi (setujui+tolak, setujui+batal) → sesi kedua ditolak, harga tetap; 141 query build `EXPLAIN` tanpa error; 18 query baru/diubah dijalankan per role dengan parameter seperti app; harness (query asli build + JSObject asli): `cwCbdGrid` Tanpa biaya (validasi, Enter/Esc, antrean aksi), `cwPublishForm` CBD (rincian, ubah kategori/uraian, uraian kosong ditolak) & Specsheet (tidak berubah), `cwBomGrid` Batal ganti; uji `limitNote`, `systemModel`, `endPrice`; validator: tidak ada error baru (26 error lama = contoh di komentar `Util`).
**Data 5 tahun setelah R11 (ms, query build R11):** `q_worklist_gap` 1.385 · cari audit tanpa hasil 1.159 · `q_worklist_cbd` 781 · `q_season_colors` 584 · `q_worklist_spec` 424 · `q_variants` 54 · `q_cbd_bridge` 82–120 · `q_worklist_system` 12 · semua query lain < 200 (dulu: timeout >120.000, 52.000, 88.900, 13.000, 8.600). Hasil: `tools/beban/hasil/log_5th_r11.txt`.

### R13 - CBD per stage + bersih-bersih (13 Okt 2026)

Pemicu (laporan user): CBD SMS r0 masih draft, specsheet GTM r0 terbit, klik *Refresh dari Specsheet* → draft pindah jadi
GTM r0; CBD SMS (dan PO SMS ×1,25) tidak pernah ada, dan tidak bisa dibuat lagi (Buat CBD selalu memakai stage specsheet
terbaru; checklist memblokir terbit selama specsheet lebih baru ada). Keputusan user: CBD adalah catatan biaya **per tahap**.

- [x] (dibuat) `fn_spec_latest_pub_stage(specsheet, stage)`, `fn_cbd_stage_spec_status(article, stage)`
- [x] (dibuat) `fn_cbd_draft`: article juga harus ACTIVE di specsheet terbit terakhir stage draft (DROPPED di specsheet terbaru tetap memblokir)
- [x] (dibuat) `fn_cbd_stage_options(token, article)` → `q_cbd_stages` (form Buat CBD): stage yang specsheet-nya terbit; tersedia bila article aktif di specsheet terbaru & stage itu dan stage ≥ CBD terbit terakhir; default = tertinggi
- [x] (dibuat) `fn_cbd_create` + `p_stage` (versi 4 argumen DROP); `fn_cbd_refresh_from_spec` tidak memindah stage; `fn_cbd_publish` menolak bila sudah ada CBD terbit stage lebih tinggi; `fn_cbd_sync_spec` hanya specsheet stage sama (CBD tidak dipindah acuannya ke stage lain)
- [x] (dibuat) `v_cbd_checklist` (spec_stale & spec_status per stage), `v_cbd_article` (+ `draft_spec_label`, `pub_behind`), `v_worklist_cbd` (TO_REFRESH per stage draft; TO_REVISE + `refresh_reason = 'STAGE'` bila CBD terbit tertinggal stage)
- [x] (dibuat) Data: CBD terbit dengan acuan specsheet stage lain (aturan lama) → acuan specsheet terbit terakhir stage-nya sendiri
- [x] (dibuat) UI: `cwCbdForm` baris **Stage CBD** (tombol per stage, nonaktif + alasan; `{spec}`/`{next}` di teks), `CbdCtrl` (chip **PERLU CBD <stage>**, teks bawah stepper, kirim `stage`), banner `CbdGridCtrl` per stage, `BerandaCtrl` (keterangan STAGE)

**Bersih-bersih (scan 13 Okt 2026, permintaan user):** app - query tak dirujuk 0, modal tak dibuka 0; dihapus `Util.fmtRp`,
`Util.prettyJson` (13 page), `ModelDetailCtrl.attachments`, `CbdCtrl.STAGES`, switch tersembunyi `swMaterialBelumHarga` /
`swMaterialHargaPending` (sisa F3, tanpa onChange). Fungsi Util lain dipakai di sebagian page (salinan sama di semua page -
tetap). `Auth.onPageLoad` / `LoginCtrl.onPageLoad` dipanggil lewat *Run on page load* (tetap). DB - fungsi/view yang tidak
dirujuk app, view, fungsi lain, trigger, atau default/constraint: hanya `fn_setup_table` (alat pasang audit tabel baru -
tetap); kolom tabel tak dirujuk: 0. Repo - semua `js/` & `widgets/` ada di app; log `tools/*_err.txt`, `build_out.txt`
dihapus & masuk `.gitignore`; validator tidak lagi membaca komentar baris penuh di JSObject (26 error palsu `Util` hilang).

**Keputusan user 13 Okt 2026:** naik stage tanpa perubahan tetap wajib alasan (tidak diisi otomatis). Kategori model
**tidak dikunci** setelah copy / terbit: syarat kategori sama hanya dicek saat copy specsheet lintas model; copy CBD lintas
model mengikuti model asal specsheet (bukan kategori); header & export membaca kategori terkini (beda dengan nama model, T57).

**Selesai bila:** draft CBD SMS bisa diterbitkan setelah specsheet GTM terbit; CBD SMS bisa dibuat setelah GTM terbit (bila belum ada CBD GTM terbit); refresh tidak mengubah stage; setelah CBD GTM terbit, SMS tertutup.

### R14: Detail audit + stage Preview (13 Okt 2026)

Permintaan user: (1) klik baris audit → detail "kolom: nilai lama → nilai baru"; (2) stage menjadi Pullover, Preview,
SMS, GTM, Production; (3) sistem memakai bahasa Inggris sederhana dan tanpa em dash. Keputusan user: **2 fase** (R14 =
detail audit + 5 stage, teks baru sudah bahasa Inggris; R15 = seluruh app ke bahasa Inggris + hapus em dash), kode stage
pendek di DB + label di layar, stage berikutnya boleh melompat, cakupan bahasa Inggris = semua yang tampil di app
(dokumen tetap Bahasa Indonesia). App R13 user tidak diubah (hanya di-deploy) → base build = `build_r13.json`.

- [x] (dibuat) Detail audit: panel `cwAuditDetail` (tab Audit Log, kolom 39–64, tinggi = `tblAudit`; `tblAudit` 0–38),
  Default model `{{AdminCtrl.auditModel(tblAudit.selectedRow.id)}}` (mengikuti baris terpilih, tanpa event; baris pertama
  terpilih otomatis). Logika di `AdminCtrl.auditModel` / `auditJson` / `auditValue`: UPDATE = kolom yang berubah saja
  (juga untuk audit lama berisi baris penuh), INSERT = keterangan (isi bila ada), DELETE = isi lengkap, aksi lain = data
  bila ada; kolom teknis `id`, `created_at`, `created_by`, `updated_at`, `updated_by` dipisah (tombol *Show technical
  fields*); uuid 8 karakter + …, waktu ISO → WIB, nilai > 160 karakter dipotong (lengkap di tooltip, maks. 2.000).
- [x] (dibuat) Rahasia: `q_audit` membuang kunci `password|token|secret|hash` dari `before_data` / `after_data` sebelum
  dikirim; `AdminCtrl` menyaring lagi. (Trigger audit sejak F1b sudah membuang `password_hash`.)
- [x] (dibuat) T71: kolom Waktu `tblAudit` membaca `currentRow["Created At"]` (tidak ada) → semua baris jam sekarang.
- [x] (dibuat) DB: `fn_stages()`, `fn_stage_order()`, `fn_stage_label()`, `fn_rev_label()`; CHECK stage + `PREV` di
  `specsheet_revision`, `cbd_revision`, `stage_setting` (+ baris `PREV` tanpa faktor PO); `stage_order` bukan generated
  lagi (`DROP EXPRESSION`, PostgreSQL 16 tidak bisa mengubah rumusnya) → trigger `trg_stage_order` (`fn_stage_order_set`),
  data lama dinomori ulang 1..5 dengan trigger dimatikan sementara (tanpa audit / `updated_at` / kunci revisi terbit).
- [x] (dibuat) `fn_revision_create`: NEXT_STAGE menerima `p_stage` (harus lebih tinggi dari stage terbit terakhir; kosong =
  stage berikutnya); `fn_cbd_stage_options` & `fn_cbd_create` memakai `fn_stages()`; label revisi lewat `fn_rev_label` di
  `v_article_status`, `v_model_list`, `v_cbd_article`, `v_worklist_cbd`, `fn_cbd_bridge_view`, `fn_cbd_create`,
  `fn_cbd_publish`, `fn_cbd_stage_options` dan 11 ekspresi di 8 query app.
- [x] (dibuat) App: `Util.stageLabel` / `Util.revLabel` (13 page); `SpecCtrl` (STAGES 5, `nextStages`, `stages`),
  `CbdCtrl` (label tombol stage, chip PERLU CBD), `CbdGridCtrl`, `BerandaCtrl`, `SpecExportCtrl` (Preview Sample =
  Pullover & Preview; form PURPOSE tetap 3 kotak), `CbdExportCtrl`; `cwStepper` 5 kolom berlabel, `cwRevisionForm`
  (stage awal dari model + **Target stage** untuk NEXT_STAGE), `cwCbdForm` (teks tombol = label).
- [x] (dibuat) `steps/R13_uji.md` D3 diganti uji panel detail; panduan `steps/R14_uji.md`.

**Keputusan detail (Claude, R14):** pesan baru di DB/app bahasa Inggris, pesan lama (masih Indonesia, sebagian menyebut kode
stage) diterjemahkan di R15; nilai `prev_label` di `change_log.diff` yang sudah tersimpan tetap label lama (`SMS r0`);
nama file export memakai label (`Preview-r0`); CBD bisa dibuat di kelima stage; `po_factor` Preview kosong.

**Selesai bila:** klik baris audit menampilkan detail sesuai aksi tanpa password; stepper 5 stage; Pullover → Preview
default, lompat ke SMS/GTM bisa, mundur ditolak; CBD Preview bisa dibuat & terbit; data lama tetap.

### R15: Sistem ke bahasa Inggris + tanpa em dash (14 Okt 2026)

Keputusan user (13 Okt 2026): semua yang tampil di app memakai bahasa Inggris sederhana (tidak bertele-tele, bukan
terjemahan kata per kata); data isian user tidak diubah; dokumen & chat tetap Bahasa Indonesia; tanpa em dash di mana pun.
Catatan uji R14: PURPOSE di Excel specsheet dibuat 5 stage sesuai sistem.

- [x] (dibuat) Alat di `tools/r15/`: `extract_js.py` (literal string JS / teks HTML), kamus `en_app*.py` (JSObject & Custom
  Widget, per file + umum), `apply_js.py` (ganti hanya literal string / teks & atribut HTML, em dash di komentar),
  `en_widgets.py` (properti widget native: nilai utuh + teks dalam binding), `db_dump.py` + `en_db.py` + `make_r15_sql.py`
  (definisi fungsi & view dari DB setelah R14, literal diganti utuh, jumlah `%` dicek, argumen stage di RAISE dibungkus
  `fn_stage_label`), `scan_app.py`, `todo.py`, `show.py`.
- [x] (dibuat) `js/*.js` (20) & `widgets/*/` (28): teks bahasa Inggris, komentar tetap Bahasa Indonesia tanpa em dash.
  Build mengambil JS & HTML Custom Widget dari repo (isi sama dengan versi app setelah kamus, dicek otomatis) dan CSS dari app
  (sebagian widget memakai CSS gabungan).
- [x] (dibuat) DB: 88 fungsi/view dibuat ulang dengan pesan & label bahasa Inggris; logika identik. Kode status harga
  (`fn_price_state`): BERLAKU → ACTIVE, AKAN BERLAKU → UPCOMING, MENUNGGU APPROVAL → PENDING APPROVAL, DITOLAK → REJECTED,
  DIBATALKAN → CANCELLED, RIWAYAT → EXPIRED, BELUM ADA HARGA → NO PRICE (dihitung, tidak tersimpan; JS/widget ikut diganti);
  `v_cbd_recap.variance_label` SESUAI → MATCH (CSS `.vl.match`, rumus Excel). Kode tersimpan (mis. `KATEGORI`, `UKURAN` di
  `model_option.kind`) tetap.
- [x] (dibuat) Nama page: Beranda → Home, Master Komponen → Master Component, Master Pilihan → Master Options,
  Persetujuan Harga → Price Approval (nama, slug, id action/collection, layoutOnLoadActions, navigateTo).
- [x] (dibuat) Excel specsheet: PURPOSE = 5 stage (2 kolom × 3 baris), dicentang sesuai stage revisi.
- [x] (dibuat) T72: kolom Last login `tblUsers` membaca `currentRow["Login terakhir"]` (tidak ada) → jam sekarang.
- [x] (dibuat) T73: build R15 pertama menimpa JSObject `Auth` semua page dengan template repo (`requiredPerm: ''`, `pageQueries` kosong) → tidak ada query dijalankan saat page dibuka (data tidak tampil) dan cek izin page hilang. Auth kini diterjemahkan dari isi app per page; build gagal bila ada Auth yang kosong.
- [x] (dibuat) `sql/R_selftest.sql`: pola pesan & kode status bahasa Inggris (butuh R15). `steps/R15_uji.md`.
- [x] (dibuat) Em dash dihapus dari semua dokumen `.md` (PLAN, steps, README widget). File SQL fase lama (riwayat
  pemasangan) tidak diubah; teksnya ditimpa R15 di database.

**Keputusan detail (Claude, R15):** format angka & tanggal tetap (16.300,00; 14 Oct 2026; WIB); teks label stage dan
role tetap (Pullover … Production, Vendor - Specsheet …); kata "Mea", "Colorway", "LOP", "FOB" tetap (istilah kerja);
bentuk jamak sederhana "line(s)" bila jumlah bisa 1; alasan terbit lama ("Revisi awal.") tetap sebagai data.

**Selesai bila:** semua page & modal tanpa teks Indonesia / em dash; pesan error DB bahasa Inggris; status harga & filter
riwayat berjalan; Excel PURPOSE 5 stage; navigasi ke 4 page yang berganti nama berjalan.

### R16: Material baru tanpa kode di specsheet + thickness baku (15 Okt 2026)

Latar: Vendor Spec menyusun specsheet langsung tanpa membuka master dulu, padahal Material Code berasal dari tim material
UMK yang tidak memegang app (lead time). Keputusan user: draft boleh berisi material yang belum punya kode; **specsheet tetap
tidak boleh terbit selama ada sel kuning** (aturan lama, tidak berubah). Penyeragaman penulisan: huruf besar + trim (nama,
warna, kode sudah sejak F10b / R2b / R9) dan thickness dibakukan.

**Temuan pemindaian sebelum membangun:** rencana awal "baris sementara bernama bebas" **tidak perlu**. Induk material tidak
punya kode (kode ada di varian), `bom_line.thickness` sudah teks bebas, dan sel warna tanpa varian sudah berupa sel kuning
(`variant_id` NULL, terbit diblokir `v_revision_checklist.yellow_cells`) yang tersambung otomatis saat varian didaftarkan
(`trg_variant_relink`). Tidak ada tabel yang diubah; risiko baris tanpa induk (BOM, CBD, copy model, export) tidak ada.
Celah sebenarnya hanya dua: (1) induk yang belum ada di master / thickness baru tidak bisa diketik di grid ("add it in
Master Material first"), (2) tidak ada daftar untuk diminta ke tim material.

**Koreksi catatan lama:** kunci pencocokan `fn_normalize` hanya huruf kecil + spasi dirapatkan, **tidak** membuang tanda baca
atau spasi di dalam. Jadi "1.2 MM" dan "1.2MM" selama ini dianggap dua thickness (varian dobel bisa lolos) dan "HONEY-LON" tidak
sama dengan "HONEYLON". Nama material sudah huruf besar otomatis (`trg_aa_upper`), tidak diubah.

- [x] (dibuat) `sql/R16_baku_thickness.sql`: `fn_clean_thickness` = bentuk baku (huruf besar, spasi ganda dirapikan, koma desimal
  jadi titik, angka + satuan satu spasi `1.2MM` jadi `1.2 MM`, `X` antar ukuran berspasi `1.0MMX44"` jadi `1.0 MM X 44"`, tanpa spasi di
  sekitar `-`, spasi sebelum `(` dan tidak ada spasi di dalam kurung, dua apostrof jadi tanda kutip; kosong / "." / "-" = tanpa thickness; idempoten; "MAX 5" tidak berubah). Data lama (`material_variant`, `bom_line`,
  `cbd_line`, termasuk di dokumen terbit) dibakukan; kunci dokumen terbit dimatikan sebentar hanya untuk penulisan ulang teks.
  Varian yang menabrak varian lain setelah dibakukan (material + warna sama) **dilewati** dan dilaporkan lewat NOTICE.
  Gaya berspasi dipilih user (15 Okt 2026) karena sama dengan standar tim material (file `MATERIAL_CODE_KLASIFIKASI_v8`): dari 603 thickness
  asli, 599 menghasilkan bentuk yang sama dengan hasil rapi tim (4 sisanya `SZ` jadi `SIZE` = isi), dan 690 thickness v8 tidak berubah.
  Uji impor 690 kode v8 ke DB uji: 686 diterima, 4 ditolak (identitas dobel), 0 thickness berubah bentuk.
- [x] (dibuat) Grid BOM (`cwBomGrid`): kolom Material menerima `NAMA · THICKNESS` dengan thickness baru untuk induk yang ada
  (dibakukan di klien seperti DB, `canonThickness`, diuji sama dengan DB pada 126 teks): baris baru bertanda "(new)", sel warna
  kuning sampai kodenya didaftarkan. Nama tidak ditemukan: pesan "Did you mean" (typo nama sampai ±25%, urutan kata, typo
  Material Code) + tombol **+ New material**.
- [x] (dibuat) **+ New material**: modal `mdlMaterialBaru` (salinan modal Master Material: nama, kategori, Mea; daftar nama mirip
  dari DB + typo dari master pabrik) tanpa kode, lalu Enter lagi di baris tambah. Hanya role `manage_master`.
  `q_bom_options` + `categories`, `uoms`; action baru `a_material_add`.
- [x] (dibuat) **Export Excel specsheet**: sel warna tanpa Material Code diberi latar kuning dan tulisan `(no code)`, plus satu baris
  keterangan di blok header (jumlah sel). Satu sheet, tanpa tombol baru (keputusan user 15 Okt 2026: "gausah banyak tombol, gausah
  banyak sheet, yang penting tahu kodenya apa saja yang di request"). Rencana awal tombol **Code request** + sheet daftar
  usulan kode dibatalkan. Kode yang kembali diketik lewat tombol Register di sel kuning (flow R4).
- [x] (dibuat) `sql/R_selftest.sql` +bagian R16 (pembakuan, material baru tanpa kode, kuning, terbit diblokir, relink, dobel beda
  cara tulis ditolak, kode terkunci setelah terbit). `tools/build_r16.py` (basis `build_r15.json`). `steps/R16_uji.md`.

- [x] (dibuat) **Order master option = posisi** (permintaan user 16 Okt 2026: Order tidak boleh kembar). Sebelumnya Order opsional, tidak unik
  (dua "10" lolos), kosong tersimpan NULL dan tampil paling bawah (Category, Construction, Gender, Last, Outsole Mold; Size sudah selalu
  = angka ukuran). Sekarang `fn_option_renumber` + `fn_option_save`: Order selalu 1..n tanpa kembar dan tanpa kosong per jenis (dan per
  pabrik untuk Last / Outsole Mold). Kosong saat tambah = paling akhir; kosong saat edit = posisi tetap; angka yang sudah dipakai =
  baris ini mengambil posisi itu dan yang lain turun; angka lebih besar dari jumlah baris = paling akhir. Data lama dinomori ulang
  mempertahankan urutan (kembar urut nama, lubang ditutup, kosong paling bawah). Label form: "Order (position)", placeholder "empty = last".
  Uji: selftest 5 jenis x 7 pemeriksaan + Size; migrasi data seperti tangkapan layar user (dua Order 10 + kosong + lubang).

**Tidak termasuk (diputuskan):** daftar / usulan kode terpisah, impor 845 kode ERP (tersendiri), impor balik Excel kode dari tim material (kode diketik satu per
satu seperti sekarang), pencarian kode di form harga / Material Detail, tombol Gabungkan varian dobel.

**Keputusan detail (Claude, R16):** bentuk baku thickness = berspasi seperti standar tim material (pilihan user; rencana awal saya padat `1.0MMX44"` dibatalkan); thickness
kosong setelah `·` dianggap masih mengetik (nama saja); nama material tidak ditebak otomatis dari kode (ERP sumber kebenaran);
tidak ada status "menunggu kode" baru (sel kuning sudah itu).

**Review 20 Okt 2026 (permintaan user: tutup celah pembakuan thickness poin 1–4 + cek bug seluruh app, sebelum uji R16 selain SQL):**
- [x] (dibuat) Pembakuan thickness diperluas, sama persis di `fn_clean_thickness` (kini plpgsql, satu langkah per baris), `canonThickness`
  di `cwBomGrid` **dan** `cwVariantForm`: (1) angka setara satu bentuk, **nol di belakang koma dibuang** (keputusan user 20 Okt 2026: "Buang nol
  belakang"; `2.0 MM` = `2 MM`, `1.50` = `1.5`, `.5` = `0.5`), (2) kutip miring `” “ ″ ＂` dan dua apostrof miring jadi `"`, (3) `INCH` / `INCHES` / `IN`
  setelah angka jadi `"` (hanya bila diikuti akhir teks, `X`, `(`, `-` atau tanda baca; `2 IN 1`, `10 INCL` tidak berubah), (4) rentang dengan
  satuan di kedua sisi `1.4 MM-1.6 MM` jadi `1.4-1.6 MM` (satuan berbeda tidak diubah). Uji: 239 teks (semua thickness file tim + kasus tepi)
  SQL = JS (Chromium) dan idempoten; dari nilai rapi file tim hanya 4 yang berubah (`1.0 MM ...`, `2.0 MM ...` jadi `1 MM ...`, `2 MM ...`).
  Yang tetap tidak bisa dibakukan: satuan yang hilang (`1.4 X 44` vs `1.4 MM X 44"`).
- [x] (dibuat) Migrasi R16 + sambung ulang sel kuning draft yang setelah dibakukan cocok dengan varian (diuji pada data dengan fungsi lama:
  varian `2.0 MM` vs `2 MM` warna sama = dilewati + NOTICE, terbit dibakukan, kunci terbit aktif lagi, sel `1 MM X 44 INCH` tersambung).
- [x] (dibuat) Perbaikan bug T74–T80 (tabel di §9 "Temuan review R16"). Build: `tools/build_r16.py` juga menimpa `CbdCtrl` (CBD) dan JS
  `cwVariantForm` (Specsheet & Material Detail), dengan assert isi app = repo R15. `tools/validate.py`: tidak lagi crash bila sintaks JSObject gagal.
- [x] (dibuat) `R_selftest.sql` +6 cek (angka setara, kutip miring / INCH, rentang, pindah Order ke bawah per jenis); 266 cek lolos di DB kosong
  dan DB berisi data sintetis 1 tahun. Semua 144 query build dijalankan per role di data 1 tahun (tanpa error). Pindah Order: 42 kombinasi
  (dari posisi mana pun ke mana pun, 6 nilai) = hasil yang diharapkan.

- [x] (dibuat) **+ New material di baris** (permintaan user 20 Okt 2026, pilihan "a"): material yang tidak ketemu saat Enter / + Add / Add sub /
  ganti material di sel menampilkan tombol **+ New material** di sel Material baris itu; setelah Save di modal, baris itu **langsung
  ditambahkan / diganti otomatis** dengan nama yang disimpan (tanpa Enter lagi). Tombol di bar atas tetap ada. `cwBomGrid` (`awaitNew`,
  `matAdded`), `BomCtrl.matAdded`. Diuji di browser dengan `cwBomGrid` + `BomCtrl` asli: tambah, sub, ganti, tanpa izin, isian diubah.

- [x] (dibuat) **Material tanpa titik tengah** (permintaan user 21 Okt 2026, setelah R16 lolos uji): `·` tidak ada di keyboard, jadi
  `NAMA . 1,5 mm`, `NAMA - 1.5mm`, `NAMA / 44 inch`, `NAMA 1,5mm` dibaca `NAMA · THICKNESS` bila bagian depan persis nama material yang ada
  (terpanjang dulu) dan sisanya mirip thickness (dengan pemisah: ada angka; tanpa pemisah: angka + satuan); isian ditulis ulang.
  `HONEYLON MESH 2` / `... blue` tidak dipecah, nama berisi `-` / kurung tetap utuh. Material baru `NAMA . THICKNESS`: modal tanpa
  thickness, baris dilanjutkan dengan thickness itu. Uji browser 19 variasi + alur material baru. Panduan: `steps/R16_uji.md` **bagian 11**
  (hanya bagian ini yang perlu diuji ulang), 9.5 diubah.

**Selesai bila:** semua uji `steps/R16_uji.md` lolos, selftest lolos, migrasi pada data lama tidak mengubah Material Code di
dokumen terbit.

### R17: Remember me di halaman Login (22 Okt 2026)
Permintaan user: app hanya bisa dibuka lewat VPN (user login VPN setiap kali), jadi ketikan login app dikurangi. Didiskusikan: ingat email saja
vs ingat sesi; user memilih ingat sesi dengan angka **7 hari tanpa dibuka, maks 30 hari** (alasan: VPN = lapisan pertama, admin tetap bisa memutus
sesi lewat reset password / nonaktifkan / ubah role atau pabrik; tidak menyimpan password di app, sesi tanpa batas tidak dipakai).
- [x] `app_session.remember` (boolean, default false) + `app_session.max_expires_at` (login + 30 hari, NULL untuk sesi biasa)
- [x] `fn_login(p_email, p_password, p_remember DEFAULT false)`: versi 2 parameter di-DROP (kalau tidak, panggilan 2 argumen ambigu); app lama tetap jalan
- [x] `fn_me` jadi plpgsql VOLATILE: sesi remember yang masih hidup diperpanjang ke `least(now() + 7 hari, max_expires_at)`, paling sering sekali
      per jam (tidak menulis di setiap page). Kolom hasil sama dengan R1. `fn_auth` tidak diubah (tidak memperpanjang, cukup dari `fn_me` di setiap page)
- [x] `cwLogin`: checkbox **Remember me** (tidak dicentang default, tidak diingat) + catatan; `updateModel({ email, password, remember })`; email
      dari model diisikan juga bila datang setelah render pertama (`fillEmail`, `filledEmail`), tidak mengisi ulang bila user menghapusnya
- [x] `LoginCtrl`: kirim `remember` ke `a_login`; `storeValue('lastEmail', email, true)` setelah login berhasil (tidak dihapus saat Log out);
      `onPageLoad` membaca `appsmith.store.lastEmail`. Default model `cwLogin`: `email: LoginCtrl.lastEmail || appsmith.store.lastEmail || ''`
- [x] `a_login`: `fn_login(email, password, {{this.params.remember === true ? 'true' : 'false'}}::boolean)` (pola `confirm` yang sudah dipakai)
- Keputusan detail (Claude): token tetap disimpan permanen di browser untuk dua pilihan (sama seperti dulu); "tidak dicentang = keluar saat
  browser ditutup" tidak dipakai karena refresh (F5) juga akan logout. Audit login tetap `LOGIN` (tidak dibedakan remember).

#### R17 bagian 2: Material Code wajib mulai SMS + harga ESTIMATE (22 Okt 2026)
Latar (user): di Pullover / Preview purchasing belum membuat Material Code karena barang belum dibeli, tetapi specsheet **dan CBD harus tetap
terbit dari stage awal**. Keputusan user 22 Okt 2026 (setelah diskusi opsi A = estimasi di CBD vs B = harga master tanpa kode; B ditolak karena
mulai SMS harga pasti dari master, jadi estimasi hanya sementara dan tidak perlu dipindah ke master):
- **Specsheet**: sel kuning (tanpa kode) memblokir terbit hanya mulai **SMS** (SMS, GTM, Production; menurut urutan stage, jadi lompatan
  Pullover → GTM juga terkunci). Pullover / Preview = peringatan di checklist. Revisi Pullover / Preview yang sudah terbit tetap tanpa kode.
- **CBD baris tanpa kode di Pullover / Preview**: harga **ESTIMATE** diketik Vendor CBD (harga, currency, referensi), tanpa approval, dihitung
  di cost/pair, ikut ke revisi CBD berikutnya selama barisnya masih tanpa kode (supplier, material, thickness sama), kuning di Excel CBD.
  Saran = estimasi terakhir material + thickness + supplier yang sama (warna sama didahulukan), tombol **Use**.
- **Baris yang punya kode**: tetap harga master (tidak bisa estimasi; "kode ada = harga harus didaftarkan"). Pending tetap memblokir.
- **Baris ber-Yield tanpa harga** (mengubah T56 untuk SMS ke atas, keputusan user): Pullover / Preview tetap peringatan; **mulai SMS memblokir**
  (kecuali No charge), karena PO SMS ×1,25 dipakai untuk pembelian. Baris tanpa harga & tanpa Yield tetap tidak diperiksa.
- Kode & harga datang terpisah: harga menyusul lewat Tugas Saya Vendor CBD (harga belum ada, sudah ada). Saat *Propose master price* untuk
  kode baru, angka estimasi terakhir menjadi **isian awal** (harga + currency; referensi tidak ikut), tetap perlu approval.
- [x] (dibuat) `fn_stage_code_required(stage)` = urutan stage ≥ SMS; CHECK `cbd_line.price_source` + `ESTIMATE`; index `ix_cbd_line_estimate`
- [x] (dibuat) `v_revision_checklist` (+ `code_required`, blocked: kuning hanya bila wajib), `fn_revision_publish` (pesan `From SMS every color needs a Material Code...`)
- [x] (dibuat) `v_cbd_price_check` (price_gap `NO_CODE`, + `can_estimate`), `v_cbd_checklist` (+ `price_required`, `estimate_count`; blocked: belum
  berharga / estimasi mulai SMS), `fn_cbd_publish` (2 pesan baru), `fn_cbd_populate` (estimasi ikut), `fn_cbd_set_quotation` (satu pintu:
  material Quotation = QUOTATION, baris Catalog tanpa kode di Pullover / Preview = ESTIMATE, selain itu ditolak), `fn_cbd_estimate_hint` (baru)
- [x] (dibuat) App: `cwCbdGrid` (badge **estimate**, tombol **Enter / Edit estimate**, tanda **no Material Code**, teks `NO_CODE`), `cwCbdPriceForm`
  (mode ESTIMATE, kotak saran + **Use**, currency isian awal), `CbdGridCtrl` (openPrice memuat `q_cbd_estimate_hint`, form model, banner per stage),
  `CbdCtrl` (checklist terbit: harga wajib mulai SMS, baris estimasi), `SpecCtrl` (checklist sel kuning per stage), `CbdExportCtrl` (baris tanpa
  kode kuning, `(no code)`, sumber `estimate`), `q_cbd_lines` (+ `can_estimate`), `q_cbd_estimate_hint` (baru)
- Keputusan detail (Claude): estimasi tidak bisa di material metode Quotation (sudah punya harga quotation sendiri); estimasi di CBD SMS (tidak
  bisa lewat app) tetap ditolak saat terbit; batas stage di banner grid ditulis ulang di JS (`SMS/GTM/PROD`) dengan komentar ke fungsi DB.

### Opsional (setelah F10, bila diminta)
- [ ] Tab Material: **Dipakai di** (where-used) & **Histori Harga**
- [ ] Diff BOM/CBD saat terbit (isi kolom `change_log.diff`)
- [ ] Harga referensi untuk Brand di specsheet terbit
- [ ] ~~**Copy lintas model**~~ → **dipindah ke R7** (8 Okt 2026); teks asli di bawah disimpan sebagai riwayat. (disepakati user 7 Okt 2026, dicatat dulu, belum dijadwalkan). Kasus: model varian dalam satu season yang hanya beda outsole / beberapa part (mis. IN vs FG). Membuka kembali keputusan 30 Sep 2026 (§2 Penyederhanaan).
  - **Specsheet**: mode Copy dari model lain di wizard Buat Revisi (aturan sama dengan COPY sekarang: season tujuan belum punya revisi → r0, sumber hanya revisi terbit, baris BOM di-copy dengan `origin_line_key` = `line_key` sumber, article season tujuan, warna kosong). Pilihan sumber difilter **kategori sama**, tampilkan kode, nama, `outsole_mold`, season & label revisi terbit; ringkasan sebelum konfirmasi ("Akan menyalin N baris dari Model · Season · Stage r#"). Tanpa penandaan baris bottom (user tidak setuju) - user menghapus/mengganti baris sendiri.
  - **Model induk**: kolom `product_model.parent_model_id` diisi **otomatis** oleh sistem saat copy lintas model pertama berhasil (tidak diisi manual di form model). Header revisi menampilkan "Disalin dari Model · Season · Stage r#". Tidak ada sinkron otomatis setelah copy (perubahan di model sumber diulang manual).
  - **CBD**: copy lintas model hanya dari article **model asal specsheet** (lewat `source_revision_id` → specsheet → model), supaya specsheet & CBD bersumber sama. Struktur baris tetap dari specsheet terbit article sendiri (seperti sekarang). Yield / Loss % ikut **hanya** bila cocok lewat `origin_line_key` **dan** material sama; baris hasil Ganti material & baris baru → kosong; pencocokan identitas (komponen + material) dimatikan untuk lintas model.
  - **Rekap & biaya CBD**: yang ikut hanya **exchange rate** dan **LOP** (`item_type = 'LABOUR'`); Amortisasi / Adjustment / Other kembali default 0; Selling price & Target FOB kosong. Harga quotation/override ikut bila material sama, `price_reference` tetap tampil.
  - **Uji E2E**: copy FG → IN, Ganti material outsole lalu terbit, buat CBD IN dari CBD FG (yield outsole kosong, selling price kosong, amortisasi 0, LOP & rate ikut), pilihan sumber kategori lain tidak muncul.
- [ ] ~~**Pemisahan data per pabrik**~~ → **dipindah ke R1–R6** (8 Okt 2026, persiapan lebih dari 1 vendor); teks asli disimpan sebagai riwayat. - **tidak dikerjakan** (keputusan user 7 Okt 2026: saat ini hanya 1 pabrik). Bila ada pabrik kedua: tabel `factory`, `app_user.factory_id` (kosong = user Brand, lihat semua), `fn_visible_models(token)` di ±40 query baca, `fn_assert_model` di ±35 fungsi tulis; putuskan dulu apakah harga material per pabrik. Copy lintas model otomatis terbatas pabrik yang sama.

---

### R18: Create + Dimension (26 Okt 2026)
Permintaan user: ubah "create revision" jadi "create" dan semua thickness di aplikasi jadi dimension. Keputusan user 26 Okt 2026:
- **Create:** tombol `btnBuatRevisi` (`+ Create`) + pesan kosong `SpecCtrl` (`No revisions yet. Click "+ Create".`, user 26 Okt 2026).
  Judul `cwRevisionForm` (`Create Revision: <season>`) dan catatan `cwPublishForm` tetap.
- **Dimension:** hanya teks yang terlihat (label, kolom `tblVariants` / `tblPrices`, pesan, placeholder, tooltip, header Excel specsheet
  `DIMENSION` dan CBD `Dimension`). Kolom DB `thickness`, `fn_clean_thickness`, `fn_thickness_label`, id / variabel JS tetap: tanpa migrasi data.
- Pesan DB ikut (terlihat user): `sql/R18_dimension.sql` = definisi R17 dari 6 fungsi (`fn_thickness_label` → `no dimension`,
  `fn_bom_add_line`, `fn_bom_cell_set`, `fn_bom_replace_material`, `fn_variant_save`, `fn_material_variant_check`), hanya teks pesan diganti.
  Self-test: 2 cek pesan `Confirmation needed: dimension code ...` disesuaikan.
- `tools/build_r18.py`: tabel PAIRS (teks lama → baru, tepat 1x) diterapkan ke file repo (`--repo`) dan ke isi app; build memastikan hasil = repo.

### R20: Penulisan material seragam + Material Code ketat + Use (27 Okt 2026)
Base: `exports/build_r19.json` (R19 lolos uji, export user belum ada). SQL ditulis di `steps/R20_uji.md` §0a (permintaan user: tanpa file
.sql baru; sumber kerja di scratchpad). Masalah dari uji user: material yang sudah ada diketik dengan cara tulis lain lalu didaftarkan lagi;
saat kode dari purchasing datang, kodenya sudah dipakai dan tidak bisa masuk. Keputusan user 27 Okt 2026 (diskusi 9 putaran):
1. **Nama beda spasi / tanda baca = material yang sama** (per UoM), tanpa bertanya: grid langsung memakai nama master, DB menolak tambah /
   ganti nama ke nama rapat yang sudah ada. Saran nama mirip **sempit** supaya user tidak jenuh: angka harus sama (`FOAM 50 KG` bukan saran
   untuk `FOAM 60 KG`), lalu beda tanda baca, kata sama urutan lain, typo 1 huruf di kata 5 huruf ke atas, atau nama memuat ketikan. Diuji ke
   459 nama ERP: aturan lama menandai 2.039 pasangan, aturan baru 8 (semua duplikat asli). Hanya saran, tidak menahan.
2. **Material Code 10 karakter ketat dua arah, tanpa centang** (menggantikan tingkat KONFIRMASI R9 dan INFO awalan): kode -> arti (4 awal = 1
   material, 3 tengah = 1 dimension, 3 akhir = 1 warna, semua material) dan arti -> kode (1 material = 1 awalan, 1 dimension = 1 kode tengah,
   dimension kosong per UoM (`800` PRS, `K00` KG/LT/CAN, `C00` PCS/EA), 1 warna di satu material = 1 kode akhir; warna sama di material lain
   boleh kode lain, mis. DOVE benang jahit vs bonded). Arti = yang paling banyak dipakai (seri: tercatat paling awal). Dicek hanya saat
   varian baru / kode / warna / dimension berubah, jadi data lama yang menyimpang tetap bisa diubah statusnya. Kode bukan 10 karakter = info.
   Kasus ERP: `W10` WHITE vs WHITE C (ditolak, duplikat ERP), PALE KHAKI dua shade satu material (hanya satu bisa, user: specsheet tidak
   serinci shade), `CANVAS 6 OZ` awalan `2100` (salah tulis ERP, kodenya nanti saja).
3. **Use** (tanpa alias, keputusan user: alias menormalisasi salah tulis dan bisa salah ganti warna yang memang BLK): Material Code material /
   dimension / warna lain di modal Register -> **Use KODE in the specsheet** (Use di sel dan Pick code dihapus di revisi poin 5).
   Satu-satunya konfirmasi = klik Use. Sel
   kuning yang sama (material + dimension + warna) di **semua draft** pabrik ikut pindah otomatis; revisi terbit tidak berubah. Baris pindah
   seluruhnya (Ganti material, Undo replace tersedia) bila sel lain di baris belum berkode; bila ada sel lain berkode, sel ini pindah ke baris
   komponen yang sama dengan material + dimension varian (yang ada / baris baru; komponen lokal = ditolak, tambah baris sendiri). Material
   lama tanpa varian yang tidak dipakai lagi di draft specsheet / CBD -> INACTIVE (Undo replace mengaktifkan lagi).
   - Keputusan detail (Claude): aturan nama rapat di DB hanya saat tambah / nama / UoM berubah (data lama kembar tidak menghalangi ubah
     status). Pesan hasil Use: jumlah sel, draft lain, material yang di-INACTIVE.
   - **Review sebelum uji (27 Okt 2026, pertanyaan user):** (a) baris di draft LAIN yang bentrok (article sudah berwarna lain di baris tujuan,
     komponen lokal) dulu membatalkan seluruh Use dengan pesan tentang model lain; kini dilewati (tetap kuning, `skipped` di hasil + pesan),
     baris yang diklik tetap memberi pesan bila gagal. (b) Esc di sel kini menghapus kotak Use. (c) Undo replace setelah Use mengaktifkan lagi
     material lama tanpa varian (ditemukan saat menulis panduan).
4. **Perbaikan data lama**: user menjalankan query cek C1 (material kembar), C2 (varian melanggar aturan), C3 (kode bukan 10 karakter) dari
   `steps/R20_uji.md` §1. **Hasil user 27 Okt 2026:** C1 0, C2 13 (11 material proses berkode dummy `PRxxK00000` / `0000000000`,
   `938L` 98 D vs 98 A, `5005` BSW-0032 vs BSW-032). Keputusan user: proses -> material **Process** (varian dummy + harga lama dihapus);
   gabung ke **98 A** dan **BSW-032** (varian, supplier, harga, baris draft pindah; lama INACTIVE). Skrip preview P1/P2 + perbaikan di
   §1b (aman diulang, berhenti bila dipakai dokumen terbit / CBD / harga berlaku). Pindah varian antar material hanya lewat
   `app.variant_merge` di skrip itu (`fn_material_variant_check`).
5. **Revisi user 27 Okt 2026 (setelah hasil cek): Material Code hanya diketik di Register.** Kolom Material menolak kode (pesan), sel warna
   menyimpan kode sebagai teks biasa (pilihan user: bukan ditolak), Pick code dan Use di sel dihapus, tawaran isi warna dari kode dihapus.
   Warna terdaftar tetap langsung dapat kode. **Use tetap di modal Register.** `fn_bom_cell_set` tidak membaca kode lagi.
   Uji pada 845 kode ERP (dimuat tanpa trigger): C1 6 pasang, C2 95 varian (semua soal awalan: nama benang ERP memuat nomor shade padahal
   satu awalan untuk semua shade, `EVA HARDNES`/`HARDNESS`, `+ COAT`, `CANVAS 6 OZ` `2100`), C3 0. Di app benang didaftarkan satu material
   tanpa nomor shade.

### R19: Catatan uji user (26 Okt 2026)
Base: `exports/export_r18.json` (export user 26 Okt 2026 = build R18, hanya format ulang Appsmith). SQL: `sql/R19_catatan_uji.sql`.
Keputusan user 26 Okt 2026 (setelah diskusi 3 putaran):
1. **Nomor komponen = posisi** (seperti Master Options, tanpa konfirmasi): nomor yang sudah dipakai di kelompok yang sama → komponen itu
   dan yang menempel di bawahnya bergeser +10 (berantai sampai ada celah), hanya di dalam kelompok. Melewati batas rentang kelompok =
   ditolak. Nomor di specsheet / CBD lama ikut berubah (dibaca langsung dari master, disetujui user).
   - [x] (dibuat) `fn_component_shift` (baru), `fn_component_add`, `fn_component_save`; `cwKomponenForm` (hint + catatan edit)
   - Keputusan detail (Claude): nomor komponen yang sudah dipakai di dokumen terbit boleh dipindah (posisi), **nama & kelompok tetap
     terkunci**. Celah tidak dirapatkan (beda dengan Order master option yang 1..n), supaya nomor lain tidak ikut berubah tanpa perlu.
   - **Koreksi user 26 Okt 2026 (uji R19):** edit 50 → 60 membuat yang di 60 jadi 70 (50 kosong), seharusnya seperti Master Options. Kini
     **edit di kelompok yang sama = pindah posisi** (`fn_component_move`): pindah ke bawah → komponen di antara (lama, baru] naik 10
     (50 → 60: yang di 60 jadi 50); pindah ke atas → komponen di antara [baru, lama) turun 10. Nomor tujuan kosong = hanya komponen itu.
     **Tambah** baru dan edit pindah kelompok tetap seperti sebelumnya (`fn_component_make_room`). Hint edit `cwKomponenForm` disesuaikan.
   - **Temuan uji 2.7 (27 Okt 2026):** Edit article tanpa nomor yang sudah dipakai dokumen terbit tampil terkunci berisi `(no article no.)`:
     `currentRow` tombol tabel membawa nilai TAMPILAN kolom `code` (computedValue), bukan nilai asli. `ModelDetailCtrl.openEditArticle` /
     `deleteArticle` kini mengambil baris asli dari `q_articles` (id). DB tidak berubah.
   - **Keputusan user 27 Okt 2026 (opsi B, salah ketik nomor artikel):** nomor boleh **dikoreksi** selama article belum ada di specsheet / CBD
     **Production** terbit (`fn_article_prod_published`, baru); dokumen terbit stage awal ikut tampil nomor baru. Nomor yang sudah dipakai
     tidak bisa dikosongkan lagi. `q_articles` + `code_locked` (kolom tersembunyi `tblArticles`), `ModelDetailCtrl.codeLocked`, teks `cwArticleForm`.
   - **Review alur CBD (27 Okt 2026, permintaan user):** chip article CBD tanpa nomor menulis `(no article no.) <colorway>` (dulu semua chip
     sama), juga nama file / sheet Excel CBD (`CbdCtrl.artLabel`, `q_cbd_articles` + `no_code`). Tugas Saya `NO_ARTICLE_NO` tidak menghitung
     article yang DROPPED di revisi terakhirnya. Alur stage CBD tetap aturan R13 (chip `NEEDS CBD <stage>`, stage boleh dilompati).
   - **Temuan uji 4.10 (27 Okt 2026):** tim CBD (`manage_price`, boleh ubah metode harga) kini juga boleh memasang / melepas tanda Process
     (aturan kunci sama). Dilepas oleh tim CBD dengan metode Quotation = tetap Quotation. `fn_material_update`, `cwMaterialForm`.
   - **Temuan user 27 Okt 2026 (ganti komponen):** dua baris UPPER, satu diganti → dua-duanya ikut. Kini **hanya baris itu** (+ subkomponen
     dan baris lama di rantai Ganti material) yang pindah; ditolak hanya bila komponen tujuan sudah punya material + dimension yang sama
     (aturan "tujuan sudah ada = ditolak" tidak dipakai lagi karena satu komponen boleh punya beberapa baris).
   - **Revisi user 27 Okt 2026 (3.7b):** baris tambah / sub, Material diganti ke material LAIN → Dimension selalu mengikuti material baru
     (terdaftar juga = tetap; satu dimension = itu; beberapa = kosong; tanpa dimension / Process = kosong), tanpa membedakan terisi otomatis
     atau diketik (logika `thkAuto` dihapus). Nama sama = tidak disentuh; dimension baru tetap boleh diketik sesudahnya; kode tetap dipakai.
2. **Nomor artikel boleh kosong**: Pullover / Preview tanpa catatan, SMS / GTM = peringatan di checklist terbit, **Production = terbit
   diblokir**. Diisi Vendor Spec (Model Detail). Nomor boleh diisi belakangan walau article sudah dipakai di dokumen terbit; setelah
   terisi dan dipakai tetap terkunci (tidak bisa diganti / dikosongkan). Article tanpa nomor muncul di **Tugas Saya** Vendor Spec.
   CBD Production otomatis aman karena dibuat dari specsheet Production terbit (R13), tanpa cek tambahan (dijelaskan ke user).
   - [x] (dibuat) `article.code` boleh NULL (CHECK + NOT NULL dilepas), colorway unik per season untuk article tanpa nomor; `fn_article_check`
   - [x] (dibuat) `fn_article_label(code, colorway)` = nomor, atau `(no article no.) <colorway>` untuk pesan & teks; tampilan app `(no article no.)`
   - [x] (dibuat) `fn_stage_article_required(stage)` = Production; `v_revision_checklist` (+ `no_code_articles`, `no_code_list`, `article_required`),
     `fn_revision_publish`; `SpecCtrl` checklist; view / query yang menampilkan nomor artikel
3. **Dimension diisi di kolom Dimension**, bukan di nama material (grid BOM): kolom Material = nama (atau Material Code, tetap dipertahankan:
   mengisi nama + dimension), kolom Dimension = input dengan saran dimension terdaftar material itu (boleh dimension baru). Ganti dimension
   baris = Ganti material (material sama, dimension baru). Ketikan lama `NAMA · DIMENSION` / `NAMA . 1,5 mm` tetap dibaca lalu dipisah ke
   dua kolom.
4. **Material Process** (tanpa kode, biaya dari quotation per model): tanda **Process** di Master Material, diisi Vendor Spec (form material
   & + New material di specsheet), terkunci setelah material dipakai di dokumen terbit. Material Process tidak punya varian / Material
   Code, sel warnanya tidak pernah kuning dan tidak memblokir terbit di stage mana pun. Harga = **QUOTATION per baris CBD** (metode harga
   Quotation otomatis, sudah ada sejak F8: diisi role pengisi harga CBD, tanpa approval di semua stage termasuk Production, ikut ke revisi
   CBD berikutnya untuk article yang sama).
   - [x] (dibuat) `material.is_process`; `fn_material_add` / `fn_material_update` (+ parameter), `fn_variant_save` (tolak), `v_material_list`,
     `v_bom_grid`, checklist sel kuning; `cwMaterialForm`, `MaterialCtrl`, `BomCtrl` (+ New material), `cwBomGrid`, Excel specsheet & CBD
   - Keputusan detail (Claude): tanda Process hanya bisa dipasang bila material belum punya varian; metode harga dikunci Quotation selama
     Process (dilepas = kembali Catalog). Copy CBD lintas model tetap membawa harga quotation material yang sama (aturan R7), bisa diedit.
5. **Ganti komponen di specsheet** (draft): semua baris komponen itu (beserta subkomponennya) dipindah ke komponen master lain; identitas
   baris (`line_key`) tetap, jadi CBD tetap tersambung. Komponen tujuan sudah ada di revisi itu = **ditolak**. Komponen lokal juga boleh
   diganti ke komponen master.
   - [x] (dibuat) `fn_bom_change_component` (baru), `a_bom_change_component` (baru), `cwBomGrid` (aksi `changeComponent`), `BomCtrl`
6. **Saran material di grid terbaca penuh**: daftar saran sendiri (bukan datalist browser) yang membungkus teks, `NAMA` + `UOM · dimension`
   (kolom Material) dan `DIMENSION` + jumlah warna (kolom Dimension); nama sama beda UoM ditulis `NAMA (UOM)`. Sel Material & Dimension
   ikut membungkus.
7. **Filter di-reset saat halaman dibuka** (semua halaman berfilter), kecuali saat kembali dari halaman detail. Reset juga setelah login,
   dari Home / menu, dan F5.
   - [x] (dibuat) `Auth` per page: `pageName`, `filterWidgets()`, reset sebelum `pageQueries`; `Util.keepFilters()` dipanggil sebelum pindah ke
     halaman detail; Home mengosongkan daftar (`appsmith.store.keepFilters`, tidak persisten = hilang saat F5)
8. **Semua field model wajib** (permintaan user saat menjawab): Model Name, Category, Gender, Construction, Last No., Outsole Mould, Size
   (min. 1), Sample Size. Model lama yang belum lengkap tetap tampil; saat Edit harus dilengkapi dulu.
   - [x] (dibuat) `fn_model_save`; `cwModelForm` (tanda wajib + cek sebelum simpan)

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

### F8b
```sql
-- Biaya di luar material (Cost recapitulation). LABOUR/AMORTIZATION/ADJUSTMENT default selalu ada per revisi.
CREATE TABLE cbd_cost_item (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cbd_revision_id uuid NOT NULL REFERENCES cbd_revision(id) ON DELETE CASCADE,
  item_type       text NOT NULL CHECK (item_type IN ('LABOUR','AMORTIZATION','ADJUSTMENT','OTHER')),
  name            text NOT NULL CHECK (btrim(name) <> ''),
  amount          numeric(18,4) NOT NULL DEFAULT 0,      -- Rupiah; hanya ADJUSTMENT boleh minus
  remarks         text,
  is_default      boolean NOT NULL DEFAULT false,
  sort_order      integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(), created_by text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by text,
  CHECK (item_type = 'ADJUSTMENT' OR amount >= 0),
  CHECK (NOT is_default OR item_type <> 'OTHER')
);
CREATE UNIQUE INDEX uq_cbd_cost_default ON cbd_cost_item (cbd_revision_id, item_type) WHERE is_default;
ALTER TABLE cbd_revision DROP COLUMN amortization, DROP COLUMN adjustment;   -- setelah nilainya dipindah
```

### F9 – F10
Tidak ada tabel baru, hanya function & view.

### R1 – R5 (rancangan 8 Okt 2026 - final saat fase dikerjakan)
```sql
-- R1
CREATE TABLE factory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL, name_key text GENERATED ALWAYS AS (fn_normalize(name)) STORED UNIQUE,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE'))
);
ALTER TABLE app_user ADD COLUMN factory_id uuid REFERENCES factory(id);
-- role IN ('VENDOR_SPEC','VENDOR_CBD','MANAGER_COSTING','BRAND_VIEWER','SYSTEM_ADMIN'); factory wajib untuk 3 role pabrik

-- R2
ALTER TABLE material ADD COLUMN factory_id uuid NOT NULL REFERENCES factory(id);   -- induk; thickness pindah ke varian
CREATE TABLE material_variant (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  material_id  uuid NOT NULL REFERENCES material(id),
  factory_id   uuid NOT NULL REFERENCES factory(id),        -- salinan dari induk, untuk unik kode per pabrik
  thickness_mm numeric(6,2),                                -- boleh kosong
  color text NOT NULL, color_key text GENERATED ALWAYS AS (fn_normalize(color)) STORED,
  code  text NOT NULL,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE')),
  UNIQUE (factory_id, code),
  UNIQUE NULLS NOT DISTINCT (material_id, thickness_mm, color_key)
);
CREATE TABLE model_option (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('KATEGORI','CONSTRUCTION','GENDER','UKURAN','LAST','OUTSOLE_MOLD')),
  factory_id uuid REFERENCES factory(id),                   -- NULL = bersama
  value text NOT NULL, sort_order integer,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE'))
);
-- supplier, component, material, material_supplier: status → ACTIVE/INACTIVE
ALTER TABLE material_supplier DROP COLUMN supplier_material_code;   -- catatan user 8 Okt 2026
-- material.material_code pindah ke material_variant.code (tanpa prefill)

-- R3
ALTER TABLE material_price ADD COLUMN variant_id uuid REFERENCES material_variant(id),
                           ADD COLUMN batch_id uuid;        -- color / color_key dihapus
CREATE UNIQUE INDEX uq_price_one_proposed ON material_price (material_supplier_id, variant_id) WHERE status = 'PROPOSED';

-- R4
ALTER TABLE product_model DROP COLUMN code, ADD COLUMN factory_id uuid NOT NULL REFERENCES factory(id),
  ADD COLUMN category_id uuid, ADD COLUMN construction_id uuid, ADD COLUMN gender_id uuid,
  ADD COLUMN last_id uuid, ADD COLUMN outsole_mold_id uuid,        -- → model_option
  ADD COLUMN sizes numeric[], ADD COLUMN sample_size numeric;       -- ganti size_range / teks lama
-- UNIQUE (factory_id, name_key)
ALTER TABLE bom_line ADD COLUMN thickness_mm numeric(6,2);
ALTER TABLE bom_cell ADD COLUMN variant_id uuid REFERENCES material_variant(id);
-- is_used = btrim(coalesce(color,'')) <> ''

-- R5
CREATE TABLE stage_setting (stage text PRIMARY KEY, po_factor numeric(6,4));  -- seed ('SMS', 1.25)
ALTER TABLE cbd_revision ADD COLUMN po_factor numeric(6,4), DROP COLUMN selling_price;
ALTER TABLE cbd_line ADD COLUMN variant_id uuid REFERENCES material_variant(id);  -- menggantikan color
```
R7: `ALTER TABLE product_model ADD COLUMN parent_model_id uuid REFERENCES product_model(id);`
R17: `ALTER TABLE app_session ADD COLUMN remember boolean NOT NULL DEFAULT false, ADD COLUMN max_expires_at timestamptz;`

R19: `ALTER TABLE article ALTER COLUMN code DROP NOT NULL; ALTER TABLE article DROP CONSTRAINT article_code_check;` (nomor kosong = NULL) · `ALTER TABLE material ADD COLUMN is_process boolean NOT NULL DEFAULT false;` · trigger `trg_a_variant_not_process` (BEFORE INSERT `material_variant`)

R20: tanpa perubahan tabel (hanya function, lihat §8).

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
| `cbd_cost_item` + `idx_cbd_cost_item_revision`, `uq_cbd_cost_default`, `trg_lock_published`; kolom `cbd_revision.amortization`/`adjustment` di-DROP | tabel | F8b | ✅ | ⬜ (cek skema belum dikirim) |
| `v_cbd_recap`, `v_cbd_checklist` (dibuat ulang), `fn_cbd_cost_label`, `fn_cbd_cost_defaults`, `fn_cbd_check_cost`, `fn_cbd_cost_item`, `fn_cbd_cost_add`, `fn_cbd_cost_set`, `fn_cbd_cost_delete`; `fn_cbd_header_set`, `fn_cbd_create` diperbarui | view/function | F8b | ✅ | ⬜ (cek skema belum dikirim) |
| `fn_cbd_sync_spec`; `fn_revision_publish` diperbarui (penandaan sinkron) | function | F8 | ✅ | ⬜ (cek skema belum dikirim) |
| `v_worklist_spec`, `v_worklist_cbd`, `v_worklist_price_gap`, `v_worklist_admin`, `v_recent_published`, `v_system_summary` | view | F10 | ✅ (user: tanpa error) | ⬜ |
| `factory` + `trg_factory_check`, `uq_factory_name`; `app_user.factory_id` + `ck_app_user_role`, `ck_app_user_factory`; `role_permission` (matriks R1); `fn_role_label`, `fn_is_factory_role`, `fn_user_factory`, `fn_can_see_factory`, `fn_assert_factory`, `fn_me` (+pabrik), `fn_user_save` (+`p_factory_id`), `fn_factory_save`, `v_factory_list`; tambalan `fn_price_add/approve/reject/end`, `fn_ensure_link` | tabel/view/function | R1 | ⬜ | ⬜ |
| `ck_supplier_status`, `ck_component_status`, `ck_material_status`, `ck_material_supplier_status` (ACTIVE/INACTIVE); `material.factory_id` + `uq_material_identity` (pabrik, nama, UoM) + `idx_material_factory`, `uq_material_code` dihapus; `material_supplier.supplier_material_code` dihapus; `material_variant` + `uq_variant_code`, `uq_variant_identity`, `idx_variant_material`, `trg_material_variant_check`; `model_option` + `uq_model_option`, `ck_model_option_scope`, `idx_model_option_kind`, `trg_model_option_check`; `fn_similar_key`, `fn_similar_match`, `fn_similar_names`, `fn_master_usage`, `fn_supplier_save`, `fn_component_add`/`fn_component_save`, `fn_material_check`/`fn_material_add`/`fn_material_update` (signature baru), `fn_thickness_label`, `fn_material_variant_check`, `fn_variant_add`, `fn_variant_update` (R2b: diganti `fn_variant_save` + `fn_variant_code_hint`, `fn_clean_thickness`, kolom `thickness` teks + `thickness_key`, `idx_variant_code_parts`), `fn_material_supplier_check`, `fn_link_save` (signature baru), `fn_ensure_link`, `fn_option_is_factory_kind`, `fn_option_kind_label`, `fn_model_option_check`, `fn_option_save`; `v_material_list` (induk), `v_worklist_admin` (PRICE saja); izin `propose_master`, `manage_material_supplier` dihapus | tabel/view/function | R2 + R2b | ✅ (user: uji lolos) | ⬜ |
| `material_price.variant_id` (wajib) + `batch_id`, `uq_price_one_proposed` (link, varian), `idx_material_price_variant`, `idx_material_price_batch`; `fn_uuid_list`, `fn_price_state`, `fn_price_lookup(uuid,uuid,date)` (baru) + versi warna lama dikosongkan, `fn_price_activate`, `fn_price_propose`, `fn_price_copy`, `fn_price_cancel`, `fn_price_decide`, `fn_price_end`; `v_material_price`, `v_price_pending`, `v_worklist_admin` (per pengajuan); DROP `fn_price_add/approve/reject` | tabel/view/function | R3 | ⬜ | ⬜ |
| `product_model` tanpa kode (+ `factory_id`, `name_key`, `uq_model_name`, `category_id`…`outsole_mold_id`, `sizes`, `sample_size` int), `v_model`, `fn_model_save`, `fn_model_option_ref`, `fn_size_label`, `fn_model_factory`/`fn_sheet_factory`/`fn_article_factory`/`fn_rev_factory`/`fn_line_factory`, `fn_auth_in`, `fn_season_add`, `fn_article_save`, `fn_article_delete`, `fn_attachment_delete`; `bom_line.thickness`, `bom_cell.variant_id` + `is_used` baru, `trg_bom_cell_variant`, `trg_variant_relink`, `fn_bom_variant_for`, `fn_bom_check_supplier`, `fn_bom_set_process`, fungsi BOM baru; `fn_variant_used_published`; `v_bom_grid`, `v_revision_checklist`, `v_worklist_spec`, `v_worklist_cbd`, `v_worklist_price_gap`, `v_recent_published`, `v_model_list` dibuat ulang | tabel/view/function | R4 | ⬜ | ⬜ |
| `cbd_line.variant_id`/`thickness`, `stage_setting` (SMS 1,25), `cbd_revision.po_factor`, DROP `cbd_revision.selling_price`, `material.material_code/thickness`, `material_price.color/color_key`, `fn_price_lookup` versi warna; `fn_cbd_factory`/`fn_cbd_line_factory`/`fn_cbd_item_factory`, `fn_price_pending`, `fn_cbd_identity` (+ thickness), `fn_cbd_expected_lines` (+ varian); `v_cbd_line`, `v_cbd_price_check`, `v_cbd_recap`, `v_cbd_checklist` dibuat ulang; semua fungsi tulis CBD + cek pabrik | tabel/view/function | R5 | ⬜ | ⬜ |
| `fn_change_log_attach` (+ cek pabrik), `v_worklist_price_rejected` | view/function | R6 | ⬜ | ⬜ |
| `product_model.parent_model_id`, `fn_sheet_origin_model`, `fn_revision_create` (COPY lintas model), `fn_cbd_populate(…, p_cross)`, `fn_cbd_create` (COPY dari model asal) | tabel/function | R7 | ⬜ | ⬜ |
| `ix_cbd_line_material_price`; `fn_attachment_add` & `fn_change_log_attach` maks. 3,5 MB; `fn_cbd_override_price` & `fn_cbd_clear_override` **dihapus** | index/function | R12 | ⬜ | ⬜ |
| `fn_spec_latest_pub_stage`, `fn_cbd_stage_spec_status`, `fn_cbd_stage_options` (baru); `fn_cbd_create` (+ `p_stage`, versi 4 argumen DROP), `fn_cbd_draft`, `fn_cbd_refresh_from_spec`, `fn_cbd_sync_spec`, `fn_cbd_publish` diganti; `v_cbd_checklist`, `v_cbd_article` (+ kolom akhir), `v_worklist_cbd` dibuat ulang | function/view | R13 | 🟡 | ⬜ |
| R15: 88 fungsi/view dibuat ulang (pesan & label bahasa Inggris, logika sama); kode `fn_price_state` & `v_material_price.state` bahasa Inggris; `v_cbd_recap.variance_label` MATCH | function/view | R15 | 🟡 | ⬜ |
| `fn_stages`, `fn_stage_order`, `fn_stage_label`, `fn_rev_label`, `fn_stage_order_set` + `trg_stage_order` (specsheet_revision, cbd_revision; `stage_order` bukan generated lagi); CHECK `*_stage_check` + `PREV` (3 tabel), `stage_setting` baris `PREV`; `fn_revision_create` (NEXT_STAGE + `p_stage`), `fn_cbd_stage_options`, `fn_cbd_create`, `fn_cbd_publish`, `fn_cbd_bridge_view` diganti; `v_article_status`, `v_model_list`, `v_cbd_article`, `v_worklist_cbd` dibuat ulang (label) | tabel/view/function/trigger | R14 | 🟡 | ⬜ |
| `cbd_line.loss_pct` boleh NULL, `change_log_attachment`, `trg_aa_upper` (6 tabel), `fn_upper_names`, `fn_change_log_attach`; `v_revision_checklist` (+ `proposed_items`) & `v_worklist_spec` dibuat ulang; `fn_cbd_revision_lock`, `fn_material_check`, `fn_cbd_line_set`, `fn_cbd_populate`, `fn_cbd_override_price` (ditolak), `fn_cbd_header_set`, `fn_revision_publish`, `v_bom_grid` (+ `supplier_status`), `v_cbd_line`, `v_cbd_checklist`, `v_worklist_admin` diperbarui | tabel/view/function | F10b | ⬜ | ⬜ |
| Hapus `material.width` + `width_key`; `uq_material_identity` kembali (nama + thickness + UoM); `fn_material_add/update` kembali ke parameter F3; `v_material_list`, `v_bom_grid`, `v_cbd_line` + view turunannya dibuat ulang | tabel/view/function | F10c | ⬜ | ⬜ |

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
| `cwPublishForm` | `Specsheet` (modal `mdlTerbit`); `CBD` (modal `mdlCbdTerbit`, F8 - opsi `blockedWhere`) | F6 / F8 | ✅ | ✅ (v8.1, kode sama di kedua page) |
| `cwCbdForm` | `CBD` (modal `mdlCbdBaru`) | F7 | ✅ | ✅ |
| `cwCbdGrid` | `CBD` (+ rekap, banner, tombol harga F8; Cost recapitulation, Harga jual, subtotal F8b) | F7 / F8 / F8b | ✅ | ✅ (kode F8 identik; tinggi → T40) |
| `cwCbdPriceForm` | `CBD` (modal `mdlCbdHarga`) | F8 | ✅ | ✅ (kode identik, event & Default model sesuai) |
| `cwWorklist` | `Beranda` (Tugas Saya, semua role; event `onOpen`, `onRefresh`) | F10 | ✅ | ✅ (v10, kode identik) |
| `cwImageGallery` | `Specsheet` (`mdlRiwayat`), `CBD` (`mdlCbdRiwayat`) - gambar change log, event `onDownload` | F10b | 🟡 file siap (harness) | ⬜ |
| `cwPriceForm` (ditulis ulang: Ajukan banyak varian / Salin harga) | `Material Detail` (`mdlHarga`) | R3 | 🟡 build_r3 (harness) | ⬜ |
| `cwPriceApproval` | `Persetujuan Harga` (events `onDecide`, `onOpenMaterial`, `onRefresh`) | R3 | 🟡 build_r3 (harness) | ⬜ |
| `cwModelForm` (ditulis ulang: dropdown + grid ukuran) | `Model List`, `Model Detail` | R4 | 🟡 build_r4 (harness) | ⬜ |
| `cwBomGrid` (induk × thickness, sel kuning, Daftarkan, + Supplier baru) | `Specsheet` | R4 | 🟡 build_r4 (harness) | ⬜ |
| `cwVariantForm` (+ opsi `fixed`) / `cwSupplierForm` disalin ke `Specsheet` (`mdlVarianBaru`, `mdlSupplierBaru`) | `Specsheet` | R4 | 🟡 build_r4 | ⬜ |
| `cwCbdGrid` (PO SMS, status menunggu, simulasi harga jual) | `CBD` | R5 | 🟡 build_r5 (harness) | ⬜ |
| `cwRevisionForm` (+ Copy dari model lain) | `Specsheet` | R7 | 🟡 build_r7 (harness) | ⬜ |
| `cwPublishForm` (gambar > 1 MB diperkecil, maks. 3,5 MB) · `cwCbdGrid` (tanpa *Hapus override*) | `Specsheet`, `CBD` | R12 | 🟡 build_r12 (harness) | ⬜ |
| `cwCbdForm` (+ baris Stage CBD) | `CBD` (modal `mdlCbdBaru`) | R13 | ✅ lolos uji user | ⬜ |
| Semua 28 Custom Widget: teks bahasa Inggris (R15); `cwCbdGrid` CSS `.vl.match` | semua page | R15 | 🟡 build_r15 (harness) | ⬜ |
| `cwAuditDetail` (baru, panel detail audit; tanpa event) | `Admin` (tab Audit Log, sebelah `tblAudit`) | R14 | 🟡 build_r14 (harness) | ⬜ |
| `cwStepper` (5 stage berlabel) · `cwRevisionForm` (Target stage) · `cwCbdForm` (label tombol stage) | `Specsheet`, `CBD` | R14 | 🟡 build_r14 (harness) | ⬜ |
| `fn_login(text, text, boolean)` (ganti `fn_login(text, text)`), `fn_me` plpgsql (perpanjang sesi remember), kolom `app_session.remember` / `max_expires_at` | function/tabel | R17 | ✅ | ✅ lolos uji user 26 Okt 2026 |
| `cwLogin` (Remember me) · `LoginCtrl` (remember, `lastEmail`) · `a_login` (parameter ke-3) | `Login` | R17 | ✅ | ✅ lolos uji user 26 Okt 2026 |
| `fn_stage_code_required`, `fn_cbd_estimate_hint` (baru), `cbd_line.price_source` + ESTIMATE, `ix_cbd_line_estimate`; `v_revision_checklist`, `v_cbd_price_check`, `v_cbd_checklist`, `fn_revision_publish`, `fn_cbd_publish`, `fn_cbd_populate`, `fn_cbd_set_quotation` diganti | function/view/tabel | R17 (bagian 2) | ✅ | ✅ lolos uji user 26 Okt 2026 |
| `cwCbdGrid` · `cwCbdPriceForm` · `CbdGridCtrl` · `CbdCtrl` · `CbdExportCtrl` · `q_cbd_lines` · `q_cbd_estimate_hint` (baru) · `SpecCtrl` | `Cost Breakdown (CBD)`, `Specsheet` | R17 (bagian 2) | ✅ | ✅ lolos uji user 26 Okt 2026 |
| `fn_thickness_label`, `fn_bom_add_line`, `fn_bom_cell_set`, `fn_bom_replace_material`, `fn_variant_save`, `fn_material_variant_check` (teks pesan Dimension) | function | R18 | ✅ | ✅ lolos uji user 26 Okt 2026 |
| Teks Dimension: `cwBomGrid`, `cwVariantForm`, `cwMaterialForm`, `cwCbdGrid`, `cwPriceApproval`, `cwPriceForm`, `cwRevisionForm`, `BomCtrl`, `CbdCtrl`, `CbdExportCtrl`, `SpecExportCtrl`, kolom `tblVariants` / `tblPrices`; tombol `btnBuatRevisi` `+ Create`, pesan kosong `SpecCtrl` | `Specsheet`, `Material Detail`, `Master Material`, `Price Approval`, `Cost Breakdown (CBD)` | R18 | ✅ | ✅ lolos uji user 26 Okt 2026 |
| `fn_component_make_room`, `fn_component_move` (baru), `fn_component_add`, `fn_component_save`, `fn_component_check` (bypass saat geser); `fn_article_code_label`, `fn_article_label`, `fn_stage_article_required` (baru), `fn_article_check`, `v_revision_checklist`, `fn_revision_publish`, `v_worklist_spec` (+ `NO_ARTICLE_NO`), `v_worklist_cbd`, `v_recent_published`, `fn_master_usage`, `fn_cbd_create`; `material.is_process`, `fn_material_add(…, boolean)`, `fn_material_update(…, boolean)` (versi lama di-DROP), `fn_variant_not_process` + trigger, `v_material_list`, `v_bom_grid`; `fn_bom_change_component` (baru); `fn_model_save` (semua field wajib) | function/view/tabel | R19 | ✅ | ✅ lolos uji user 27 Okt 2026 |
| `cwBomGrid` · `cwMaterialForm` · `cwModelForm` · `cwArticleForm` · `cwKomponenForm` · `BomCtrl` · `SpecCtrl` · `SpecExportCtrl` · `MaterialCtrl` · `MaterialDetailCtrl` · `ModelCtrl` · `ModelDetailCtrl` · `BerandaCtrl` · `Util` (semua page) · `Auth` (semua page: `pageName`, `filterWidgets`) · `a_bom_change_component` (baru) · `q_rev_articles`, `q_cbd_articles`, `q_cbd_sources`, `q_cbd_revisions`, `q_articles`, `a_material_add` (2), `a_material_update`, `q_material`, `q_materials`, `q_bom_options` · `tblArticles`, `tblMaterials`, `btnVarianTambah` | semua page | R19 | ✅ | ✅ lolos uji user 27 Okt 2026 |
| `fn_tight_key` (baru), `fn_material_check` (nama rapat), `fn_variant_code_problems` (baru), `fn_material_variant_check` (aturan ketat, konfirmasi R9 dihapus), `fn_variant_save` (`p_confirm` tidak dipakai), `fn_variant_code_hint` (+ `p_color`, `p_thickness`, `used_*`, `problems`; versi 4 parameter di-DROP), `fn_variant_code_suggest` (dimension kosong per UoM, kode warna per material dulu), `fn_bom_take_cells`, `fn_bom_use_variant` (baru), `fn_bom_cell_set` (kode tidak dibaca), `fn_bom_delete_line` (Undo replace mengaktifkan lagi material tanpa varian) | function | R20 | ✅ | ✅ cek cepat lolos 27 Okt 2026 |
| `cwBomGrid` (kode tidak dibaca, nama rapat, `nearName`) · `cwVariantForm` (2 page: kotak merah tanpa centang, Use) · `BomCtrl` (`useText`, `useFromRegister`, `nearMaterialNames`) · `MaterialDetailCtrl` · `q_code_hint` (2) · `a_variant_save` (2, tanpa confirm) · `a_bom_use_variant` (baru) | `Specsheet`, `Material Detail` | R20 | ✅ | ✅ cek cepat lolos 27 Okt 2026 |

---

## 9. Log review export

| Versi | Tanggal | Fase | Hasil review |
|---|---|---|---|
| v1 | 25 Sep 2026 | F0 + F1 | ✅ Lolos, semua uji user berhasil. Skema DB sesuai register (F1 + F1b lengkap, objek lama sudah di-DROP). Query & `Auth`/`Util`/`LoginCtrl` identik dengan file repo; `cwLogin` identik (hanya diformat ulang Appsmith). Deviasi atas keputusan user: 4 Custom Widget tambahan (kode disalin ke `widgets/`), `AdminCtrl` ditulis ulang untuk `cwUserForm` (disalin ke `js/AdminCtrl.js`), nama page memakai spasi, filter audit pakai tombol **Cari**, panel detail before/after audit tidak dibuat. Temuan T1–T6 di bawah. |
| v2 | 29 Sep 2026 | F2 | ✅ Lolos, semua uji user berhasil. Skema DB: semua objek F2 ada (`supplier`, `component_group`, `component`, `fn_has_perm`, `fn_auth_any`, `fn_supplier_check`, `fn_component_check`, `fn_component_add`, trigger). Query, `SupplierCtrl`, `KomponenCtrl`, `Auth` (`requiredPerm`, `pageQueries`) identik dengan repo; `cwSupplierForm`/`cwKomponenForm` identik (teks info supplier dipersingkat user → disalin ke repo). Deviasi: filter & cari pakai tombol **Cari** (sama seperti Audit Log), bukan otomatis. T1, T3–T8 sudah diperbaiki; T2 belum. Temuan baru T9–T12. |
| v3 | 29 Sep 2026 | F3 | 🟡 Uji user lolos. Semua 14 query F3 identik dengan panduan; `MaterialCtrl`, `MaterialDetailCtrl`, `Auth` (izin + `pageQueries`) identik dengan repo; `cwMaterialForm`/`cwLinkForm`/`cwPriceForm` identik; event & Default model sesuai. T9 & T10 sudah diperbaiki. **Terlewat:** kolom tombol **Ganti harga** & **Akhiri** di `tblPrices` (T13). Temuan T13–T17. Hasil cek skema F3 belum dikirim. |
| v3b | 30 Sep 2026 | F3b (+ perbaikan T13–T17) | ✅ File dari user `export_v4.json`, lalu `export_v4.5.json` (setelah perbaikan T18–T20) - versi terakhir disimpan sebagai `export_v3b.json`. Semua 17 query Master Material & Material Detail identik dengan panduan; `a_price_end` & `a_price_cancel` konfirmasi ON; query baca Manual. `MaterialCtrl`, `MaterialDetailCtrl` identik; kode `cwMaterialForm`, `cwLinkForm`, `cwPriceForm`, `cwReasonForm` identik, event & Default model sesuai. T13–T16 ✅. Deviasi (diterima): tombol **Batalkan** tidak tampil untuk Master Admin (admin memakai Tolak). Temuan T18–T20; di export v4.5: T18 ✅, T19 ✅, T20 sebagian (kosmetik tersisa). |
| v4 | 30 Sep 2026 | F4 | 🟡 File dari user `export_v4.6.json` → `export_v4.json`. Cek skema: semua objek F3, F3b, F4 ada (register ✅). Semua 14 query F4 identik dengan panduan (prepared statements ON, konfirmasi `a_article_delete`/`a_attachment_delete` ON, timeout `a_attachment_add` 30 s). `ModelCtrl`, `ModelDetailCtrl`, `Util` identik; `Auth` (izin + `pageQueries`) sesuai. `cwModelForm`/`cwSeasonForm`/`cwArticleForm` identik (hanya format), event & Default model sesuai; `fpLampiran` sesuai (Base64, 1 file, 5 MB, jpg/png/pdf). Deviasi (diterima): beberapa tombol dinonaktifkan (Disabled) alih-alih disembunyikan; kolom tombol memakai *Cell visible*; modal lebar ±780–1090 px & *close on outside click* ON (sama dengan keputusan T11/T12). Temuan T21–T27. **Update v4.7** (disimpan menimpa `export_v4.json`): T21–T27 ✅ terverifikasi, user: semua uji lolos. Keputusan user 30 Sep 2026: article **tidak** di-copy antar season (hanya struktur specsheet yang di-copy, F5) → Copy Article dihapus. |
| v5 | 30 Sep 2026 | F5 | 🟡 Cek skema: semua objek F5 ada (register ✅), `fn_article_copy` sudah di-DROP. Semua 17 query F5 page Specsheet identik dengan panduan (prepared ON, `a_revision_delete` konfirmasi ON); `q_models`/`q_articles` diperbarui sesuai. `SpecCtrl` (teks *…dahulu* dari user, disalin ke repo), `BomCtrl`, `ModelCtrl`, `ModelDetailCtrl`, `Util` identik; `Auth` sesuai. `cwStepper`, `cwRevisionForm`, `cwBomGrid` identik (hanya format); event & Default model sesuai. Deviasi (diterima): `btnBukaCbd` Disabled bukan disembunyikan, `selSpecSeason` filterable, modal `mdlRevisi` lebar 1190 px. User: semua uji lolos. Temuan T28–T29 + 3 permintaan user (grid tampil tanpa revisi, tombol kembali selalu ke Model Detail, tidak ada hapus baris BOM) → perbaikan `steps/F5_langkah.md` §6. |
| v7 | 30 Sep 2026 | F7 (+ sisa F6) | ✅ Cek skema: semua objek F7 ada. 10 query page CBD + `q_articles` identik dengan panduan (prepared ON, semua Manual, `a_cbd_delete` konfirmasi ON); `CbdCtrl`, `CbdGridCtrl`, `ModelDetailCtrl`, `SpecCtrl` identik dengan repo; `Auth` CBD (`view_cbd`, `pageQueries`) sesuai; `cwStepper` (Specsheet & CBD), `cwCbdForm`, `cwCbdGrid` identik (hanya format), event `onSelect`/`onArticle`/`onAction`/`onSave`/`onCancel` & Default model sesuai; kolom **CBD** di `tblArticles` sesuai; `cwHeader` CBD pola logout terbaru. Sisa F6: T30 ✅, T31 label ✅ (Search masih ON). Deviasi (diterima): tombol Disabled alih-alih disembunyikan, `mdlCbdBaru` lebar 902 px. User: semua uji lolos (hasil E3 F6 & Q-cbd tidak dikirim). Temuan T34–T36. |
| v7.1 | 30 Sep 2026 | F7 perbaikan | ✅ File dari user `export_v7.1.json` (disimpan menimpa `export_v7.json`). `Query1` di Specsheet dihapus (T34 ✅), tidak ada query uji lain; `cwCbdGrid` tinggi ±570 px (T35 ✅); `txtCbdJudul`/`btnBukaSpec` (T36 rename ✅). Hanya page CBD berubah + `Query1` terhapus; query & JSObject lain identik dengan v7. Sisa kosmetik: Search `tblRiwayat` ON. |
| v8 | 5 Okt 2026 | F8 | 🟡 File dari user (Downloads) → `export_v8.json`. 10 query F8 + `q_cbd_lines` identik dengan panduan (prepared ON; konfirmasi `a_cbd_clear_override`/`a_cbd_refresh_spec` ON, `a_cbd_publish` OFF). `CbdCtrl`, `CbdGridCtrl` identik dengan repo; `cwCbdGrid` (HTML/CSS/JS, CSS hanya diformat), `cwCbdPriceForm`, `cwStepper`, `cwCbdForm` identik; event & Default model semua Custom Widget sesuai (handler CBD, bukan Specsheet). Tombol `btnCbdRiwayat` / `btnCbdTerbitkan` sesuai (pola Disabled); `tblCbdRiwayat` data & kolom sesuai (`source_label` disembunyikan); `btnRiwayatTutup` menutup `mdlCbdRiwayat`. Tidak ada `Query1`; query & widget page lain tidak berubah dari v7. Deviasi (diterima, pola user): modal lebar 854 / 1038 / 1104 px, judul + tombol Tutup di `mdlCbdRiwayat`. Temuan T37–T41. Hasil uji A–E, Q-cbd, dan cek skema belum dikirim. |
| v8.1 | 5 Okt 2026 | F8 perbaikan | 🟡 File dari user `export_v8.1.json` (disimpan menimpa `export_v8.json`). T37 (3 query baca Manual), T38 (modal harga & terbit tidak tertutup klik luar), T39 (`cwPublishForm` JS baru di Specsheet & CBD) ✅; judul riwayat per article ✅. Cek alur JSON: sintaks semua JSObject & Custom Widget page CBD lolos parser JS; semua query/widget/modal yang dirujuk ada; params setiap `.run()` / `exec()` cocok dengan `this.params` query; handler event Custom Widget menunjuk fungsi yang ada. `fn_cbd_populate` hanya satu (versi `cbd_line[]`) ✅. Sisa: T40 tinggi grid 570 px, Search `tblCbdRiwayat` ON. Uji A–E ditunda ke uji end-to-end di akhir (keputusan user 5 Okt 2026). |
| v8b | 5 Okt 2026 | F8b | 🟡 File dari user `export_v8.5.json` → `export_v8b.json`. 4 query F8b identik dengan panduan (prepared ON, `a_cbd_cost_delete` konfirmasi ON); `CbdGridCtrl`, `CbdCtrl` identik dengan repo; `cwCbdGrid` HTML/CSS identik, JS identik kecuali catatan di bawah tabel Harga jual dihapus user (disalin ke repo); tinggi 730 px (T40 ✅); Search `tblCbdRiwayat` OFF (T41 ✅). Cek alur: sintaks JSObject & Custom Widget lolos, semua nama yang dirujuk ada, params `exec()`/`.run()` cocok. Temuan T42. Uji G1–G12 & cek skema ditunda ke end-to-end. |
| v9 | 5 Okt 2026 | F9 | 🟡 File dari user `Export_v9.5.json` → `export_v9.json`. JSObject `XlsxWriter` (page Specsheet & CBD), `SpecExportCtrl`, `CbdExportCtrl` identik dengan repo (hanya komentar kepala yang dibuang Appsmith); JSObject lain tidak berubah. `q_cbd_model` (+ `outsole_mold`, `last_no`, `construction`) sesuai panduan, Manual, prepared ON; `q_cbd_cost_items` Manual (T42 ✅). Tombol `btnSpecExport` / `btnCbdExport`: label, onClick, Visible, Disabled sesuai; SECONDARY, ikon `cloud-download`, kolom 53–64 (tombol Buat dipersempit 42–53). Tidak ada `Query1`. Library ExcelJS masih terpasang (tidak dipakai). Uji X1–X9 ditunda ke end-to-end. |
| v10 | 5 Okt 2026 | F10 | 🟡 File dari user (Downloads) → `export_v10.json`. 8 query `q_worklist_*` identik dengan panduan (prepared ON) tetapi **Automatic** (T45). `BerandaCtrl`, `SpecCtrl`, `CbdCtrl` identik dengan repo; `Auth.pageQueries` Beranda = `BerandaCtrl.load()` ✅. `cwWorklist` HTML/CSS/JS identik, Default model `{{BerandaCtrl.model()}}`, event `onOpen`/`onRefresh` sesuai, tinggi 740 px. Deviasi (diterima): `cwWorklist` diletakkan **di bawah** `cwMenu` (panduan: di atas). Page lain: hanya `SpecCtrl`/`CbdCtrl` berubah (sesuai rencana), widget tidak berubah. Tidak ada `Query1`. Hasil uji H1–H17 & cek SQL F10 belum dikirim. |
| v10.1 | 5 Okt 2026 | F10 perbaikan | ✅ File dari user `export_v10.1.json` (disimpan menimpa `export_v10.json`). T45 ✅: 8 query `q_worklist_*` Manual, `layoutOnLoadActions` Beranda tinggal `Auth.onPageLoad`; tidak ada perubahan lain. User: SQL F10 jalan tanpa error. Uji H1–H17 digabung ke uji end-to-end. |
| v10.2 | 6 Okt 2026 | F10b + F10c (sebelum uji G8) | 🟡 File dari user `export_v10.2.json` (disimpan sebagai `export_v11.json`). Semua query F10b sesuai panduan (`a_material_add`/`a_material_update` kembali ke versi F3, `a_supplier_insert`, `q_season_colors`, `q_change_log`(+`image_count`), `q_cbd_change_log`, `q_change_log_images` ×2, `a_change_log_attach` ×2 timeout 30000, `q_worklist_proposals` +SUPPLIER); semua JSObject = repo (LoginCtrl, SupplierCtrl, MaterialDetailCtrl, SpecCtrl, SpecExportCtrl, CbdCtrl, CbdGridCtrl, BerandaCtrl); semua Custom Widget = repo (beda format saja), cwImageGallery terpasang di kedua modal Riwayat; T46 ✅ (`LoginCtrl.onPageLoad` On page load). Temuan T49–T52. |
| v10.5 | 6 Okt 2026 | Uji ulang G8–J | 🟡 File dari user `export_v10.5.json` (disimpan menimpa `export_v11.json`). Satu-satunya perubahan dari v10.2: `a_cbd_override_price` dihapus. **T49–T52 belum diperbaiki.** User: semua uji lolos. Angka DB: SMS r0 566/567 174.413,98 / 259.413,98 (data lama sebelum F10b; LOP 85.000, bukan 81.370), GTM r0 566 189.213,46 / 277.453,46 **OVER** (harapan 192.695,51 / 280.935,51 UNDER - selisih material 3.482,05 terjelaskan: harga master HS ALPHA diisi USD 12,80 bukan 12,60 (+470,66), usulan Elastic Knit USD 2,49 tidak pernah di-approve sehingga CBD benar memakai 2,27 (−3.952,72); target FOB diisi 260.000 → OVER benar. **Tidak ada bug.**), GTM r0 567 175.729,70 / 260.729,70. |
| v6 | 30 Sep 2026 | F6 | 🟡 User: cek skema berhasil. 3 query F6 identik dengan panduan (prepared ON, Manual, `a_revision_publish` konfirmasi OFF); `SpecCtrl` identik dengan repo; `cwPublishForm` identik (hanya format), Default model & event `onPublish`/`onCancel` sesuai; `tblRiwayat` data & kolom Waktu sesuai. Tidak ada `Query1`; page lain tidak berubah dari v5. Deviasi (diterima, pola v4): `btnTerbitkan` & `btnHapusDraft` **Disabled** `{{!SpecCtrl.editable()}}` alih-alih disembunyikan. Audit log: hanya **1** terbit lewat F6 (`change_log` 1 baris, MATERIAL) → uji B1, C4–C6, E2 belum terbukti (T33). Temuan T30–T33. |
| v5.5 | 30 Sep 2026 | F5 perbaikan + F5b | ✅ File dari user `export_v5.5.json` (disimpan menimpa `export_v5.json`). 8 query baca Specsheet Manual (T28 ✅); `a_bom_delete_line` sesuai panduan; `ModelCtrl`, `ModelDetailCtrl`, `SpecCtrl`, `BomCtrl` identik dengan repo; `cwBomGrid` JS/CSS identik (hanya format), Visible `{{!!SpecCtrl.revision()}}` (U1 ✅); `btnKembali` = `{{SpecCtrl.backLabel()}}` (U2, T29 ✅); tombol Hapus baris (U3/F5b ✅). Tidak ada `Query1`. User: semua uji lolos. |

### Temuan review v1 (diperbaiki sebelum/bersama F2)

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T1 | **Bug** | `cwMenu` memakai `target: 'Master_Material'` dan `'Model_List'`, padahal nama page di app `Master Material` / `Model List` → menu Master & Model tidak bisa dibuka (tidak terlihat oleh System Admin, jadi lolos uji) | Ubah target di Default model `cwMenu` menjadi `'Master Material'` dan `'Model List'` | ✅ v2 |
| T2 | **Bug (kemungkinan)** | Kolom tanggal memakai `currentRow["Login terakhir"]` (`tblUsers.last_login_at`) dan `currentRow["Created At"]` (`tblAudit.created_at`) - `currentRow` memakai nama kolom data, bukan label → semua baris menampilkan waktu sekarang / "Invalid date" | Computed value: `{{Util.fmtDateTime(currentRow.last_login_at)}}` dan `{{Util.fmtDateTime(currentRow.created_at)}}` | ➖ dibiarkan (keputusan user 29 Sep 2026) |
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
| T10 | Kecil | `q_me` = *Automatic* di 9 page (semua kecuali Beranda & Admin, termasuk Login) → jalan dobel sebelum `Auth`/`LoginCtrl` | Set **Manual** di semua page | ✅ v3 (sisa: `q_me` di Login masih Automatic - lihat T17) |
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
| T23 | Sedang | `tblArticles` kolom **Hapus**: Cell visible hanya `{{ModelDetailCtrl.canEdit()}}` - kurang `!currentRow.is_used` → tombol muncul di article yang sudah dipakai (DB tetap menolak, tapi membingungkan) | Cell visible: `{{ModelDetailCtrl.canEdit() && !currentRow.is_used}}` | ✅ v4.7 |
| T24 | Sedang | `btnSeasonTambah` Visible diawali karakter **Tab** (`	{{…}}`) → dibaca sebagai teks, bukan boolean → tombol bisa tampil untuk semua role (Brand/Vendor CBD; simpan ditolak DB) | Hapus Tab di depan `{{` (juga di `txtModelJudul`, kosmetik) | ✅ v4.7 |
| T25 | Kecil | `tblLampiran`: label tertukar (`created_at` = "Oleh", `created_by` = "Diunggah") dan `created_at` tanpa format | `created_by` → label `Oleh`; `created_at` → label `Diunggah`, Computed value `{{Util.fmtDateTime(currentRow.created_at)}}` | ✅ v4.7 |
| T26 | Kecil | Kolom `attachment_count` (`tblArticles`) & `size_bytes` (`tblLampiran`) bertipe **Number** padahal Computed value berupa teks (`1 file`, `12 KB`) - sama dengan T16 | Column type **Text** | ✅ v4.7 |
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
| T40 | Kecil | `cwCbdGrid` tinggi 570 px (panduan ±680): banner + rekap memakan ±110 px → baris grid yang terlihat tinggal ±6–8 | Tinggi ±680 px | ✅ v8b (730 px) |
| T41 | Kosmetik | `tblCbdRiwayat` Search ON; `txtRiwayatJudul` = *Riwayat terbit - <season>* padahal riwayat CBD per **article** | Search OFF; Text `{{'Riwayat CBD - ' + ((CbdCtrl.article() || {}).code || '')}}` | ✅ v8b |

### Temuan review v8b

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T42 | **Bug** | `q_cbd_cost_items` = *Automatic* → jalan tanpa params saat page dibuka, bisa selesai setelah `CbdCtrl.init()` → tabel Cost recapitulation kosong (sama dengan T22/T28/T37) | Set **Manual** | ✅ (v9.5) |

### Temuan uji F9 (export v9, sebagian)

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T43 | **Bug** | Klik **Export Excel** (Specsheet): `RangeError: Maximum call stack size exceeded`, lalu `SpecExportCtrl is not defined`, tanpa toast (error lolos dari try/catch → terjadi di dalam ExcelJS/worker Appsmith, bukan di kode kita). Perbaikan pertama (gaya `thin()`, base64 manual) tidak membantu | ExcelJS dilepas. JSObject baru **`XlsxWriter`** (`js/XlsxWriter.js`, ditempel di page Specsheet & CBD): penulis .xlsx tanpa library (XML + zip STORE, tanpa rekursi). API = subset ExcelJS yang dipakai, jadi `build()` tidak berubah; `save()` → `wb.toBase64()`. Diuji: file dibuka openpyxl - isi, rumus + hasil, merge, border, fill, font, numFmt, freeze, landscape A4 benar | 🟡 terpasang (v9.5), uji di end-to-end |
| T44 | Permintaan | Export Excel specsheet dibuat seperti PDF contoh user (*SS_SPECS_FH26_…_PROD.pdf*) tanpa kotak validasi. Jawaban user: tanpa gambar/logo, PURPOSE dicentang otomatis dari stage, tanpa highlight, kolom persis PDF | `SpecExportCtrl.build()` ditulis ulang (layout PDF; komposisi material tidak ada di DB → tidak ikut); `XlsxWriter` + `printTitleRows` (header berulang tiap halaman) & `footer` (`Page &P / &N`). Diuji: xlsx → PDF (LibreOffice) tampil sesuai | 🟡 terpasang (v9.5), uji di end-to-end |

### Temuan review v10

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T45 | **Bug** | 8 query `q_worklist_*` = *Automatic* → masuk `layoutOnLoadActions` dan jalan **sebelum** `Auth.onPageLoad`, untuk **semua role**: query role lain ditolak DB → muncul hingga 6–7 toast error *Role … tidak punya akses* setiap Beranda dibuka (data tetap aman); dan query jalan dobel (sekali otomatis, sekali dari `BerandaCtrl.load()`) | Set **Manual** di kedelapan query, Deploy | ✅ v10.1 |
| T46 | **Bug** (laporan user 5 Okt 2026) | `LoginCtrl.onPageLoad` di page Login = *Manual* sejak v2 (v1: On page load; kemungkinan ikut terubah saat T10/T17) → page Login tidak pernah memproses `doLogout`: **Keluar tidak menghapus token**, dan state JSObject (`view = 'change'` dari login pertama) tetap tersimpan → setelah Keluar muncul form ganti password, tombol Keluar/Batal membawa kembali ke Beranda karena sesi masih aktif. Juga `?mode=ganti` dan redirect "sudah login → Beranda" tidak jalan | 1) `LoginCtrl.onPageLoad` → *Run behaviour* **On page load**; 2) `LoginCtrl` baru: `resetView()`/`goHome()` mengembalikan tampilan ke login setiap kali pindah ke Beranda (tidak bergantung pada sisa state) | ✅ v10.2 |
| T49 | **Bug** | `q_change_log_images` page CBD = *Automatic* → masuk `layoutOnLoadActions` (jalan sebelum `Auth.onPageLoad`, tanpa `log_id`) | Set **Manual**, Deploy | ✅ (dicek di export R9, 12 Okt 2026) |
| T50 | **Bug** | Event `onRowSelected` `tblRiwayat` (Specsheet) = `{{SpecCtrl.showImages(tblRiwayat.selectedRow)}}.` - ada titik setelah `}}` → nilai jadi teks campuran, gambar bisa tidak dimuat | Hapus titik di akhir | ✅ (dicek di export R9, 12 Okt 2026) |
| T51 | Tampilan | Kolom **Gambar** di `tblRiwayat` & `tblCbdRiwayat` bertipe *Number* padahal isinya teks ("2 gambar" / "-") | Ubah *Column type* → **Plain text** | ✅ (dicek di export R9, 12 Okt 2026) |
| T53 | **Bug** (review `export_r1.json`, 8 Okt 2026) | `q_factories` (Admin) & `q_change_log_images` (CBD) kembali *Automatic* setelah import walau di build *Manual*: query yang dirujuk widget dengan `userSetOnLoad = false` diubah Appsmith menjadi on-load saat import | Build R2: semua query Manual diberi `userSetOnLoad = true` (`aslib.set_query/add_query`), validator memberi peringatan bila belum | ✅ `export_r2.json` (semua query tetap Manual setelah import) |
| T52 | Tampilan | `cwPublishForm` & modal Terbit tidak ditinggikan (Specsheet 46 baris / `mdlTerbit` 480 px, CBD 47 baris / `mdlCbdTerbit` 500 px - sama dengan v10) → bagian Gambar + tombol Terbitkan bisa terpotong / harus scroll di dalam widget | Tinggi widget & modal +160 px (widget ±62 baris, modal ±640–660 px) | ⬜ |

### Temuan review bug R9 (12 Okt 2026, permintaan user sebelum R11)
Cara: 174 fungsi DB + 44 JSObject + 45 Custom Widget dari export R9 dibaca; temuan yang mencurigakan diuji di PostgreSQL lokal (skema F1 → R10, transaksi uji / DB salinan). Yang diperiksa dan **aman**: parsing angka di grid & form harga (koma/titik, "47.500" ditolak), draft tidak terlihat Brand (semua query revisi), cek pabrik di semua fungsi tulis, antre per season/article (`FOR UPDATE`) saat buat revisi/CBD, sesi habis (`Util.run` sama di 13 page), export Excel memakai angka dari DB.

| # | Tingkat | Temuan | Perbaikan (usulan) | Status |
|---|---|---|---|---|
| T54 | **Bug** (terbukti) | Material Detail → **Akhiri** pada harga *AKAN BERLAKU*: harga itu jadi 0 hari, tetapi harga lama sudah ditutup di tanggal mulai harga baru (saat disetujui) dan tidak dibuka lagi → **mulai tanggal itu varian tidak punya harga** (uji: hari ini 10 USD, +40 hari kosong). Pesan "diakhiri per hari ini" juga keliru. Selain itu harga lama yang sudah "ditutup ke depan" tidak punya tombol Akhiri | `fn_price_end` untuk harga yang belum berlaku: buka lagi harga sebelumnya (`valid_to` = NULL bila `valid_to` = `valid_from` harga ini), pesan disesuaikan. **Uji C user 13 Okt 2026 gagal sebagian:** harga yang dibatalkan masih berketerangan *AKAN BERLAKU* (sampai = mulai) dan form Tambah Harga menganggapnya harga berlaku terbaru → **R11b**: `fn_price_state` rentang 0 hari = **DIBATALKAN** (disembunyikan bila riwayat OFF, tanpa tombol Ajukan), `v_material_price` pasangan yang hanya punya harga dibatalkan tetap *BELUM ADA HARGA*. **Uji ulang user 13 Okt 2026:** tambah → akhiri → tambah lagi (tanggal mulai sama) → akhiri lagi **menghidupkan harga pertama yang sudah dibatalkan** (valid_to-nya = tanggal mulai harga kedua) → `fn_price_end` hanya membuka harga yang mulai lebih awal; data terkena dipulihkan dari `audit_log` (valid_to dari tanggal mulainya sendiri → kosong) | ✅ R11 + R11b (`sql/R11b_harga_batal.sql`, `exports/build_r11b.json`; self-test 166 cek) |
| T55 | **Bug** (terbukti, jarang) | Balapan proses usulan harga: (a) Manager Costing A **setujui** + B **tolak** hampir bersamaan → harga lama tertutup, usulan berstatus DITOLAK; (b) pengaju **Batal** saat usulan sedang disetujui → harga yang baru disetujui **terhapus**. Keduanya: varian kehilangan harga | `fn_price_decide` & `fn_price_cancel`: kunci baris (`FOR UPDATE`) lalu cek ulang status; `UPDATE/DELETE … AND status = 'PROPOSED'` | ✅ R11 (uji 2 sesi bersamaan: sesi kedua ditolak, harga tetap ada) |
| T56 | **Risiko data** | CBD **boleh terbit dengan baris tanpa harga** (katalog belum ada harga berlaku / quotation kosong): baris itu dihitung 0 di Material Cost → Actual FOB & PO price terlalu rendah; checklist hanya memblokir yield kosong, harga menunggu, harga basi, rate | ~~Keputusan user 12 Okt 2026: blokir~~ → **diubah user 13 Okt 2026: peringatan saja** - baris ber-Yield yang belum berharga: banner + checklist "!" dengan daftar baris (`unpriced_list`), tidak memblokir; baris tanpa harga **dan** tanpa Yield dianggap memang tanpa biaya, tidak didaftar (`blank_count`); baris "Tanpa biaya" (A1) tidak dihitung | ✅ R11 |
| T57 | Sedang (integritas dokumen terbit) | Nama / kategori / UoM **material** (dan nama model) bisa diubah walau sudah dipakai di specsheet/CBD terbit - supplier & komponen dikunci (`fn_master_usage`), material tidak. View specsheet membaca nama live → dokumen terbit lama ikut berubah (UoM di CBD tersimpan per baris, di specsheet tidak) | **Keputusan user 12 Okt 2026: kunci** seperti supplier - nama/kategori/UoM material (dan nama model) tidak bisa diubah bila dipakai di dokumen terbit | ✅ R11 (`fn_material_used_published`, `fn_material_update`, `fn_model_save`) |
| T58 | Kecil (UX) | Hapus baris hasil **Ganti material** menghapus komponen itu beserta subkomponennya; baris lama tetap nonaktif - tidak kembali ke material semula | Hapus baris pengganti = batalkan penggantian (`fn_bom_undo_target`, dipakai `fn_bom_delete_line` & `v_bom_grid.undo_replace`); tombol grid **Batal ganti** | ✅ R11 |
| T59 | Kecil | `Query1` (`ROLLBACK;`) buatan user masih ada di page Beranda | Hapus | ✅ R11 (build menghapus `Query1`) |

### Temuan review go-live per halaman (13 Okt 2026, permintaan user sebelum UAT) - R12
Cara: `build_r11b.json` dibaca per halaman (13 page, 141 query, 44 JSObject, event widget) + katalog DB R11b di PostgreSQL
lokal (fungsi bertoken tanpa `fn_auth`, SECURITY DEFINER, trigger audit per tabel, FK tanpa index, constraint unik) + DB
uji 5 tahun. Yang **aman**: semua query prepared statement; setiap fungsi bertoken memanggil `fn_auth` (2 pengecualian =
stub override yang selalu menolak → T65); `set_config('app.user', …, true)` lokal per transaksi (aman untuk pool koneksi);
audit tidak menyimpan isi file/password; tidak ada `Query1`/query uji tersisa; periode harga APPROVED tidak tumpang tindih
(0 di DB uji & 5 tahun).

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T60 | **Tinggi** (belum terbukti di server) | Lampiran article ≤ 5 MB & gambar change log 5 × 5 MB dikirim ke browser sebagai base64 (+33%); `q_change_log_images` mengirim semua gambar sekaligus (bisa ±33 MB). Appsmith membatasi ukuran respons query (`APPSMITH_PLUGIN_MAX_RESPONSE_SIZE_MB`; default tidak bisa dipastikan) → file/gambar besar bisa gagal dibuka. Uji sebelumnya hanya file kecil | `cwPublishForm`: gambar > 1 MB diperkecil di browser (maks. 2000 px, JPEG 85%); galeri: `q_change_log_images` daftar saja + `q_change_log_image` per gambar (tampil bertahap, gagal satu tidak menggagalkan semua); batas lampiran & gambar **3,5 MB** (`fn_attachment_add`, `fn_change_log_attach`, `fpLampiran`, `MAX_BYTES`). User tidak punya akses server (13 Okt 2026) → menaikkan batas server hanya saran ke tim IT | ✅ R12 |
| T61 | **Tinggi** (terbukti) | FK `cbd_line.material_price_id` tanpa index: setiap hapus baris harga (Batal usulan, Hapus varian) membaca seluruh `cbd_line` - data 5 tahun 1,1 s per harga; varian dengan banyak harga bisa melewati timeout 10 s | `ix_cbd_line_material_price` (diukur: 4,6 ms) | ✅ R12 |
| T62 | Sedang (terbukti di harness) | Klik cepat chip article / revisi / season saat jaringan lambat: data query = respons yang **selesai terakhir** → CBD bisa menampilkan article B dengan revisi & baris draft article A (edit Yield masuk ke draft A); Specsheet grid revisi lama di bawah revisi baru | `SpecCtrl`/`CbdCtrl.nav()`: semua pemuatan berurutan, klik yang masuk saat memuat digabung (yang terakhir menang; muat ulang setelah buat/terbit/hapus tidak hilang); `BomCtrl.fetch` / `CbdGridCtrl.reload` memuat ulang bila tersalip; grid hanya baris revisi terpilih (`q_cbd_cost_items` + `cbd_revision_id`) dan read-only "Memuat…" selama antrean | ✅ R12 |
| T63 | Sedang | Token login disimpan permanen di browser (12 jam) - risiko di PC bersama | **Tidak diubah** - keputusan user 13 Okt 2026: PC tidak dipakai bersama | ✅ (keputusan) |
| T64 | Sedang | Tombol Cari / filter memanggil query langsung → saat sesi habis hanya error mentah Appsmith, tidak ke Login; query halaman di `Auth.onPageLoad` juga hanya menampilkan pesan | `Util.load()` (sesi habis → Login) di 8 event; `Auth.onPageLoad` → Login bila query halaman gagal karena sesi | ✅ R12 |
| T65 | Kecil | Kode mati: `a_cbd_clear_override`, tombol *Hapus override* di `cwCbdGrid`, `fn_cbd_override_price` / `fn_cbd_clear_override` (sejak F10b/R5 selalu menolak) | Dihapus (query, case `CbdGridCtrl`, tombol, `DROP FUNCTION`) | ✅ R12 |
| T66 | Kecil | Library **ExcelJS** (CDN jsDelivr) masih terpasang walau export memakai `XlsxWriter` sejak T43 → dimuat dari internet tiap app dibuka | Dilepas dari `customJSLibList` & `unpublishedCustomJSLibs` | ✅ R12 |
| T67 | Kecil | Jam ditampilkan sesuai zona waktu PC (pesan DB memakai WIB); tanggal export Excel ikut zona PC | `Util.fmtDateTime` / `fmtDate` selalu WIB (kolom date tidak digeser); tanggal export Specsheet & CBD WIB | ✅ R12 |
| T68 | Kecil (tidak standar) | Modal form dengan ketikan tertutup bila klik di luar (isian hilang); kotak cari & download tabel tidak seragam | *Close on outside click* OFF di 11 modal form; Search OFF `tblModels` (sudah ada kotak Cari), ON `tblCbdRiwayat`; Download OFF `tblLampiran` | ✅ R12 |
| T69 | Info | `XlsxWriter` ada 2 salinan (Specsheet & CBD) - Appsmith tidak bisa berbagi JSObject antar page | Dicatat untuk handover F11 (ubah keduanya bersamaan) | ⬜ F11 |
| T70 | Opsional | Tidak ada pengaman DB (`EXCLUDE`) terhadap periode harga APPROVED yang tumpang tindih - dijaga fungsi saja | Ditunda (keputusan user 13 Okt 2026, prioritas rendah); butuh `btree_gist` | ⬜ nanti |
| T71 | Sedang (terbukti) | Kolom **Waktu** `tblAudit` membaca `currentRow["Created At"]` (kunci tidak ada) → semua baris audit menampilkan jam sekarang (sejak export R1) | Dibaca dari `created_at`; panel detail R14 juga menampilkan waktu baris | ✅ R14 |
| T72 | Sedang (terbukti) | Kolom **Last login** `tblUsers` membaca `currentRow["Login terakhir"]` (label, bukan kunci data) → semua user tampil jam sekarang (sejenis T71) | Dibaca dari `last_login_at` | ✅ R15 |
| T73 | Tinggi (terbukti, uji user) | Build R15 pertama: JSObject `Auth` semua page tertimpa template repo → data tidak tampil di semua page & cek izin page hilang | Auth diterjemahkan dari isi app per page + assert di `build_r15.py` | ✅ R15 |


### Temuan review R16 (20 Okt 2026, permintaan user sebelum uji R16) - seluruh app
Cara: semua JSObject (20 file) & Custom Widget yang berubah sejak R12 dibaca; cek silang otomatis (parameter `.run({...})` vs `this.params`
di query, properti model yang dibaca Custom Widget vs yang dikirim fungsi Default model), validator build, semua query baca build R16 dijalankan
per role di PostgreSQL lokal dengan data sintetis 1 tahun, fungsi DB yang berubah di R13–R16 dibaca, pencarian sisa teks / pola Indonesia (R15),
uji browser (Chromium) `cwBomGrid` + `BomCtrl.gridModel()` asli dan `cwVariantForm` versi lama vs baru. Yang **aman**: logika revisi & CBD per
stage (buat, terbit, refresh, sinkron), hapus/ubah varian dengan thickness baku, pesan yang dikutip panduan uji R16 cocok dengan kode,
DB tanpa sisa teks Indonesia.

| # | Tingkat | Temuan | Perbaikan | Status |
|---|---|---|---|---|
| T74 | **Tinggi** (terbukti, R16) | Tombol **+ New material** di grid BOM **tidak pernah tampil**: `BomCtrl.gridModel()` tidak mengirim `canAddMaterial` (widget membaca `M.canAddMaterial`). Pesan material tidak ditemukan juga selalu menyuruh "ask Vendor Specsheet", juga untuk Vendor Spec. Lolos uji harness R16 karena model harness diisi manual | `canAddMaterial: Auth.can('manage_master')` | ✅ R16 (review) |
| T75 | Sedang (terbukti, R16) | `cwVariantForm` masih memakai pembakuan thickness lama (rapikan spasi saja): kode yang bagian thickness-nya sudah tercatat (`404` = `44"`) dengan thickness diketik `44 "` / `6mm x 44 "` memunculkan kotak merah "already recorded as 44", not 44 "" dan wajib centang (uji R16 1.2 & 1.5 akan gagal) | Salinan `canonThickness` di `cwVariantForm` (dibandingkan dalam bentuk baku) | ✅ R16 (review) |
| T76 | Sedang (terbukti, sejak R15) | `cwVariantForm` mencari pesan DB `/^Perlu konfirmasi:/`, padahal sejak R15 pesannya `Confirmation needed: ...` (regex tidak ikut diterjemahkan). Bila DB yang menolak (petunjuk kode belum dimuat), kotak centang konfirmasi tidak muncul; hanya pesan merah | Pola `Confirmation needed:` / `Check the Material Code;` | ✅ R16 (review) |
| T77 | Sedang (terbukti, R16) | Master Options: pindah Order **ke bawah** meleset satu (A,B,C,D: A diberi 3 → B,A,C,D). Selftest hanya menguji pindah ke atas | `fn_option_renumber` membaca posisi lama (pindah ke bawah: sesudah baris di posisi itu); `fn_option_save` tidak mengubah `sort_order` sebelum renumber | ✅ R16 (review) |
| T78 | Kecil (R16) | Modal **+ New material** di Specsheet: saran Category / Mea kosong (`BomCtrl.options()` tidak meneruskan `categories` / `uoms` dari `q_bom_options`) → rawan kategori baru karena salah ketik | Diteruskan | ✅ R16 (review) |
| T79 | Kecil | Export Excel specsheet membaca `q_bom_grid.data` tanpa saring revisi (pola T62): bila revisi baru saja diganti, isi bisa milik revisi lain | `BomCtrl.gridLines()` | ✅ R16 (review) |
| T80 | Kecil (R15) | Chip article CBD menampilkan `TERBIT <label>` (sisa bahasa Indonesia) | `PUBLISHED <label>` | ✅ R16 (review) |
| T82 | **Tinggi** (terbukti di export, sejak R1) | Page Login: `LoginCtrl.onPageLoad` tercatat **Manual** dan `layoutOnLoadActions` kosong di semua export sejak `export_r1.json` (v11 masih benar; fungsi itu dibuat ulang 8 Okt 2026). Akibat: **Logout tidak logout** (token tetap di browser, sesi DB tidak ditutup, tombol Back masuk lagi tanpa password), tombol **Change password** di header membuka form login biasa, user yang sudah login tidak langsung ke Home. Jenis bug T46 | Build R16: `runBehaviour = ON_PAGE_LOAD`, `userSetOnLoad = true`, entri `layoutOnLoadActions` (pola sama dengan `Auth.onPageLoad`). **Cek setelah import**: Login → LoginCtrl → onPageLoad → *Run on page load* ON | ✅ R16 (review ke-2) |
| T83 | Sedang (R16) | Master Options: tabel mengurutkan INACTIVE ke paling bawah sebelum Order, padahal sejak R16 Order = posisi → nilai yang dinonaktifkan "melompat" ke bawah dan kolom Order tidak berurutan (uji 8.8 tampak gagal) | `q_options`: urut menurut Order saja (status tetap terlihat di kolom Status) | ✅ R16 (review ke-2) |
| T84 | Kecil (R15) | Master Options kolom Factory: `Bersama` untuk opsi milik bersama (sisa bahasa Indonesia di query) | `Shared` | ✅ R16 (review ke-2) |
| T85 | Kecil | CBD simulasi harga jual: Margin → Selling price ditulis dengan pemisah ribuan (`319.730`), lalu angka itu ditolak widget sebagai ambigu saat diubah → Margin kosong | Selling price hasil hitungan tanpa pemisah ribuan | ✅ R16 (review ke-2) |
| T86 | Sedang (terbukti, uji user 1.16b, sejak R9) | Konfirmasi arti kode di trigger varian membandingkan dengan varian pertama yang thickness / warnanya **berbeda**, sedangkan form memakai varian pertama yang memakai bagian kode itu. Setelah satu pengecualian dikonfirmasi (`2003404BLK` 404 = `58"`), setiap varian normal 404 = `44"` ikut diminta konfirmasi | Trigger `fn_material_variant_check` & `fn_variant_code_hint`: arti bagian kode = thickness / warna yang **paling banyak** memakainya (seri: yang tercatat paling awal, lalu kode). Pengecualian baru tetap diminta konfirmasi. Hanya SQL (`R16_baku_thickness.sql`), app tidak berubah | ✅ R16 (uji user) |
| T81 | Info | (a) Kolom Main supplier `tblLinks`: teks cadangan `★ Utama` hanya dipakai saat tabel kosong (tidak tampil). (b) Varian yang **dilewati** migrasi karena bentrok (thickness lama) tidak bisa diubah statusnya lewat form (akan dibakukan → bentrok); selesaikan lewat DB Tools. Tidak terjadi di DB user (material kosong). (c) `q_cbd_sources` menerima `model_id` yang tidak dipakai | Dibiarkan | ✅ (dicatat) |

**Review ke-2 (20 Okt 2026, permintaan user "recheck"):** cek otomatis tambahan: kolom setiap tabel (`currentRow` / `selectedRow` /
`triggeredRow`) vs kolom hasil query (15 tabel, semua cocok), properti snake_case yang dibaca JSObject & widget vs kolom query page itu
(tidak ada yang hilang), aksi saat page dibuka per page, event `cwHeader` di 12 page, konfirmasi pada semua aksi hapus / batal, izin
tombol vs izin fungsi DB, teks Indonesia di literal query / view / fungsi, `innerHTML` (semua di-escape), nama sheet Excel (sudah
dibersihkan `XlsxWriter`). Dibaca: `cwCbdGrid`, `cwPublishForm`, `cwPriceForm`, `cwPriceApproval`, `cwStepper`, `cwModelForm`,
`cwOptionForm`, `CbdExportCtrl` (rumus Excel = rumus DB), fungsi harga DB. Alur panduan R16 bagian 1-6 dijalankan lewat fungsi DB:
18 hasil sesuai panduan. Temuan T82-T85.

### Temuan kesesuaian alur kerja (12 Okt 2026) - dibanding CBD asli UMK
Acuan: `FH26_CBD PRODUCTION_ACC ILLUZION IV ELITE FG PRM 097.xlsx` (sheet SMS, GTM OKT, PROD OKT, 2 article) + Project Charter. Yang **sudah sesuai**: stage PULL/SMS/GTM/PROD, revisi terkunci setelah terbit, CBD per article, kolom Yield–Usage–Loss–USD–IDR–Cost/pr–Supplier, kelompok Upper/Bottom/Packaging/Misc, rekap Material + Direct Labour + Amortisasi (boleh beberapa baris) + Adjustment, Target FOB & under/over, PO SMS × 1,25, kurs per revisi, tanda perlu revisi bila specsheet berubah.

| # | Tingkat | Temuan | Usulan | Status |
|---|---|---|---|---|
| A1 | **Tinggi** | CBD asli punya baris **tanpa harga yang sah** (dekorasi yang sudah termasuk di harga baris lain, mis. *Decoration Printing Block Motif Area*, *Sockliner logo*; *Plastic Pading* yang dihapus = biaya 0). Sistem tidak menerima harga 0 → bila T56 (blokir terbit bila ada baris tanpa harga) dipasang apa adanya, CBD seperti ini **tidak bisa terbit** | T56 diubah: blokir hanya baris yang *lupa* diberi harga; baris boleh ditandai **"Tanpa biaya / termasuk baris lain"** (alasan wajib, tampil di export). **User 12 Okt 2026:** benar - printing dibreakdown tapi harga disatukan di satu baris; ada item memang tanpa harga (plastic padding) | ✅ R11 (`cbd_line.no_charge` + alasan, `fn_cbd_set_no_charge`, cost 0, ikut revisi berikutnya; grid & export) |
| A2 | **Tinggi** | Template mengisi **Usage langsung** untuk bahan habis pakai: benang 105 m/psg, strobel thread 25,2, carton box 1/12, isolatape 0,0625, wrapping paper 0,002 (yield 1). Sistem: Usage = 1 / Yield, hanya Yield yang bisa diisi → vendor harus menghitung kebalikan (1/105 = 0,0095238…), rawan salah & selisih pembulatan | **User 12 Okt 2026: dibiarkan** (tetap isi Yield) - dicatat untuk training (Usage 105 → Yield 1/105) | ✅ tidak diubah |
| A3 | Sedang | **Loss %** di template diisi sebagai **faktor**: 1,01 (= loss 1%) dan 1 (= tanpa loss); rumus = Usage × faktor × harga. Sistem membaca angka sebagai persen: ketik "1" → loss 1% (seharusnya 0), "1,05" → 1,05% (seharusnya 5%). Salah hitung diam-diam | **User 12 Okt 2026: tetap seperti sistem (persen)** - dicatat untuk training/User Manual (1 = 1%) | ✅ tidak diubah |
| A4 | Sedang–tinggi | **Penjelasan revisi**: template mencatat beberapa perubahan per revisi, masing-masing dengan kategori (Ex-rate, LOP, Amortisasi, Material, Yield, Component, Treatment) **dan nilai rupiahnya** - jumlahnya = selisih FOB dari revisi sebelumnya (GTM: +28.042,87). Sistem: satu kategori + satu teks per terbit, tanpa angka → Brand kehilangan "jembatan biaya"; risiko penjelasan kembali lewat Excel/email | ✅ R11 - standar (cost bridge / analisis selisih per pemicu): saat terbit, sistem membandingkan dengan CBD terbit sebelumnya per baris (`line_key`) dan membagi selisih FOB berurutan ke Ex-rate → Material (harga) → Yield/Loss → Component (baris tambah/hapus/ganti material) → Treatment (A6) → LOP / Amortisasi / Adjustment-Lainnya; total = selisih FOB persis. Vendor hanya melengkapi uraian per kategori yang bernilai ≠ 0 (wajib), menggantikan pilihan satu kategori. Disimpan di `change_log.diff`, tampil di riwayat (alasan = ringkasan per kategori bila kosong) & export (blok "Rincian perubahan") | ✅ R11 (`fn_cbd_bridge`, `fn_cbd_bridge_view`, `fn_cbd_publish` 5 argumen; baris cocok lewat line_key → replaces_line_key → identitas, sama dengan `fn_cbd_populate`) |
| A5 | Sedang | Baris **non-BOM** di *e. Miscellaneous* (Cement "Upper" 2.600, Assembling 7.550) masuk Material Cost di template. Di sistem baris CBD hanya dari BOM specsheet yang wajib material master + supplier + Material Code per article → perlu material/supplier/varian "bohongan", atau ditaruh sebagai biaya *Lainnya* (di luar Material Cost → struktur beda dari template). Item tanpa warna (Laminating "None", benang 2 warna) juga wajib varian | Usulan (tanpa pengembangan): item tanpa warna → satu Material Code per material (mis. NONE) + isian "isi semua sel" saat tambah baris; Cement → material BOM biasa; Assembling (biaya proses) → baris biaya *Lainnya* di rekap (FOB sama, hanya letak subtotal beda) - konfirmasi ke Brand saat UAT | ✅ disetujui user (tanpa pengembangan; masuk training) |
| A6 | Sedang | **Simulasi FOB tanpa treatment** (FOB − biaya dekorasi/proses MGE: 321.806 → 271.706) ada di template; sistem tidak bisa menandai baris treatment, kategori TREATMENT tidak punya data | Usulan: centang **Treatment** di Master Material → "Simulasi FOB tanpa treatment" | ❌ dihapus (keputusan user 12 Okt 2026); kategori Treatment tetap bisa dipilih manual di rincian perubahan |
| A7 | Rendah | Huruf kelompok template: a. UPPER, c. Bottom unit, d. Packaging, e. Miscellaneous; sistem a/b/c/d → export beda huruf dari yang biasa dibaca Brand | Biarkan a–d (urut) dan informasikan ke Brand; ubah hanya bila Brand keberatan saat UAT | ✅ disetujui user |
| A8 | Catatan proses | Approval CBD oleh Brand di luar scope (Charter) - praktik umum brand mengonfirmasi FOB; tanpa jalur respons di sistem, negosiasi kembali ke email | Opsional pasca go-live: komentar / status "OK / perlu revisi" dari Brand pada CBD terbit (tidak memblokir) | ⬜ pasca go-live |
| A9 | Catatan proses | Harga per varian (warna + thickness, keputusan R2/R3): colorway baru → varian baru → harga harus diajukan & disetujui sebelum CBD bisa terbit; di template harga material umumnya sama antar warna | Tetap (keputusan lama); pastikan alur *Salin Harga* ke banyak varian dipakai di training; pantau di UAT | ⬜ pantau |

Catatan lain:
- Nama app di Appsmith "Test Database" dan datasource `Prestasi` (rencana: "Sistem Specsheet & CBD" / `pg_main`) - tidak memengaruhi fungsi. **User akan merapikan nama app sebelum handover** (dicek lagi di F11).
- Database **dipakai bersama aplikasi lain** (dikonfirmasi user; tabel `master_store`, `master_store_mapping` bukan milik proyek ini). Aturan: semua objek proyek ini memakai nama sendiri (`app_*`, `fn_*`, `v_*`, tabel bisnis proyek) dan **jangan pernah** menyentuh tabel lain; cek bentrok nama sebelum membuat tabel baru. Untuk produksi disarankan database/schema terpisah (dicatat untuk F11).
- Export v1 mencatat `isPublic: false`; karena uji incognito berhasil, kemungkinan hanya tidak ikut ter-export.
