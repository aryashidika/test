# Uji end-to-end - dari DB kosong sampai CBD GTM terbit

Menggabungkan semua uji yang ditunda (F8 A–E, F8b G1–G12, F9 X1–X9, F10 H1–H17) dalam satu alur nyata.
Data diambil dari Excel contoh user **FH26_CBD PRODUCTION_ACC ILLUZION IV ELITE FG PRM 097.xlsx**
(sheet SMS & GTM, article SPE1010566 dan SPE1010567). Supaya uji tidak terlalu panjang, BOM memakai 13 komponen +
4 subkomponen dari 40 baris Excel. Angka di Excel dan hasil hitung sistem sudah dicocokkan: Upper Overlay 31.307,39.

Keputusan user (5 Okt 2026): semua data dihapus, kecuali akun System Admin. Semua data lain diinput lewat UI.
Audit log ikut dihapus.

**Diperbarui untuk F10b** (uji ulang dari awal): setiap baris BOM wajib punya supplier dan semua usulan harus
di-approve sebelum specsheet terbit. Override harga dihapus. Grid BOM & Excel specsheet menampilkan kolom **Thickness**, dan nama tersimpan huruf kapital.
Karena itu Plastic Padding diberi supplier ASEMINDO (IDR 1.650, nilai dari Excel) dan Cement diberi supplier NANPAO
(IDR 2.600). Angka SMS ikut berubah (+154,31 dari Plastic Padding). Uji lanjutan dari G8 untuk data yang sudah ada:
lihat `steps/F10b_langkah.md` §3.

Cara mencatat: tandai ✅ / ❌ di kolom **Hasil**. Untuk ❌, tulis pesan error atau screenshot. Kirim tabel ini plus
`export_v11.json` hanya bila ada yang diubah di Appsmith.

Pakai **5 jendela browser terpisah** (mis. Chrome biasa + 4 profil/incognito), satu per role, supaya tidak perlu
login-keluar terus.

---

## 0. Reset data

| # | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| R1 | DB Tools → `z_run_sql` → tempel seluruh `sql/RESET_data_uji.sql` → Run | Tanpa error | |
| R2 | Jalankan cek di bawah | Semua 0 kecuali `system_admin ≥ 1`, `grup = 4`, `izin > 0` | |

```sql
SELECT (SELECT count(*) FROM app_user)                              AS user_total,
       (SELECT count(*) FROM app_user WHERE role = 'SYSTEM_ADMIN')  AS system_admin,
       (SELECT count(*) FROM supplier) + (SELECT count(*) FROM component) + (SELECT count(*) FROM material)
       + (SELECT count(*) FROM product_model) + (SELECT count(*) FROM cbd_revision) AS data_bisnis,
       (SELECT count(*) FROM audit_log)       AS audit,
       (SELECT count(*) FROM component_group) AS grup,
       (SELECT count(*) FROM role_permission) AS izin;
```

---

## A. Akun - System Admin

| # | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| A1 | Buka URL app → login System Admin | Masuk Beranda; *Ringkasan Sistem* semua 0, user aktif 1 (H14) | |
| A2 | Admin → User → tambah 4 akun (tabel di bawah) | Setiap simpan menampilkan **password sementara** sekali; modal tidak tertutup klik di luar | |
| A3 | Login `spec@uji.test` dengan password sementara | Diminta ganti password (min. 8 karakter) → Beranda Vendor – Specsheet | |
| A4 | Ulangi A3 untuk 3 akun lain (password baru dicatat sendiri) | Tiap role melihat Beranda & menu sesuai izin | |
| A5 | Login `brand@uji.test` dengan password salah 5× | Percobaan ke-5 → akun terkunci 15 menit; dengan password benar tetap ditolak | |
| A6 | System Admin → Reset password `brand@uji.test` (konfirmasi muncul) → login dengan password sementara baru | Bisa masuk lagi (kunci terbuka), wajib ganti password | |
| A7 | Admin → Audit Log | Tercatat login, ganti password, reset, tambah user | |

| Email | Nama | Role |
|---|---|---|
| `master@uji.test` | Master Admin Uji | Master Admin |
| `spec@uji.test` | Vendor Spec Uji | Vendor – Specsheet |
| `cbd@uji.test` | Vendor CBD Uji | Vendor – CBD |
| `brand@uji.test` | Brand Viewer Uji | Brand Viewer |

---

## B. Master data - Master Admin

Tanggal berlaku semua harga = **hari ini**. Currency harus dipilih setiap kali (tidak ada nilai awal).

### B1. Supplier (Master Supplier → Tambah)

`Hwasung` · `HWASUNG ( ANAN )` · `MGE` · `Asemindo` · `BHS` · `DAE YOUNG` · `GMT` · `winfaith` · `Hanyoung` · `Kim` ·
`Pelangi Elasindo` · `Nanpao` - tersimpan huruf kapital (mis. `HWASUNG`).

| # | Uji tambahan | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| B1a | Tambah `mge` (huruf kecil) | Ditolak: nama sudah ada | |
| B1b | 12 supplier tersimpan, status APPROVED, huruf kapital | Tabel berisi 12 | |

### B2. Komponen (Master Komponen → Tambah)

| Grup | Nomor · Nama |
|---|---|
| a Upper | `10` Upper Overlay · `20` Tongue Logo · `50` Eyestay Insert Coating Film · `60` Upper Underlay · `70` Tongue Collar · `80` Upper Lining · `100` Plastic Padding |
| b Bottom unit | `4010` Sockliner Cover · `4040` Outsole · `4060` Insole |
| c Packaging | `6010` Inner Box |
| d Miscellaneous | `8030` Shoe Lace |

| # | Uji tambahan | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| B2a | Tambah nomor `15` (bukan kelipatan 10) | Ditolak | |
| B2b | Tambah `4020` di grup **a** | Ditolak: di luar rentang grup a (0–3990) | |
| B2c | Tambah `10` lagi | Ditolak: nomor sudah dipakai | |
| B2d | Saran nomor berikutnya di grup a setelah `100` | `110` | |

### B3. Material (Master Material → Tambah, lalu Material Detail → Supplier & Harga)

Kode otomatis `MTR-0001`… (urutan boleh beda). Metode harga **Catalog**, kecuali Outsole (**Quotation**).

| Material (nama) | Kategori | Thickness | UoM | Supplier → harga |
|---|---|---|---|---|
| Hulex Mono DE 107 | Synthetic | 0,3 mm | XM | Hwasung → **USD 14,70** |
| HS ALPHA DE 107 | Synthetic | 0,3 mm | XM | HWASUNG ( ANAN ) → **USD 12,60** |
| Decoration TPU Clear HF Welding Logo | Decoration | 1,0 mm | PRS | MGE → IDR 20.500 |
| Decoration Printing Block + Logo | Decoration | – | PRS | MGE → IDR 1.500 |
| Hotmelt FA7100 Paper 200 UM + Sticker | Hotmelt | – | XM | Asemindo → USD 3,50 |
| Honeylon Mesh | Mesh | – | XM | BHS → IDR 14.000 |
| Elastic Knit UW240801 | Knit | – | PRS | GMT → USD 2,27 |
| HASI 022T 160 | Lining | – | XM | Hwasung → USD 1,55 |
| Laminating Asemindo | Process | – | XM | Asemindo → USD 0,65 |
| W/ Coating FA 7300 50 Micron + Sticker | Process | – | XM | Asemindo → USD 1,27 |
| Plastic | Plastic | – | XM | Asemindo → IDR 1.650 |
| Merry Mesh | Mesh | – | XM | BHS → IDR 11.500 **khusus warna `True Red 19-1664 TPG`** |
| Outsole PRM-097 | Outsole | – | PRS | winfaith (supplier saja; metode **Quotation** → tidak bisa diberi harga) |
| Hysock 16 N | Insole | 1,6 mm | XM | Hanyoung → USD 2,42 |
| Inner Box Specs New Design 2023 A6 | Packaging | – | PRS | Kim → IDR 4.100 |
| Lace Dual Width 32353 | Lace | 6-4 mm | PRS | Pelangi Elasindo → USD 0,311 |
| Cement Upper | Chemical | – | PRS | Nanpao → IDR 2.600 |

| # | Uji tambahan | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| B3a | Tambah `hulex mono de 107` / `0.3 mm` / `xm` | Ditolak: duplikat (nama + thickness + UoM setelah normalisasi) | |
| B3b | Outsole PRM-097 → Tambah harga | Ditolak: metode Quotation | |
| B3c | Harga dengan tanggal berlaku kemarin di bawah harga hari ini | Ditolak: tanggal mundur | |
| B3d | Ketik harga `47.500` | Ditolak sebagai angka ambigu | |
| B3e | Filter **belum ada harga** di Master Material | Kosong (Outsole Quotation tidak dihitung) | |
| B3f | Beranda Master Admin | Semua antrian 0 (data admin langsung APPROVED) | |

---

## C. Model, season, article - Vendor – Specsheet

| # | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| C1 | Model List → Tambah model: kode `ACC-ILZ4-FG`, nama `ACC ILLUZION IV ELITE FG`, kategori `Football`, factory `Factory 1`, outsole mould `PRM-097`, last `PRL 025`, construction `STROBLE+TOE LAST`, size range `37-44`, sample size `42` | Tersimpan | |
| C2 | Model Detail → Season & Article → + Season `FH26`; coba juga `FH2026` | `FH26` tersimpan; `FH2026` ditolak (format) | |
| C3 | + Article `SPE1010566` colorway `WHITE / TRUE RED`; + Article `SPE1010567` colorway `SAFETY YELLOW / ICE FLOW` | 2 article | |
| C4 | Tambah article `spe1010566` | Ditolak: kode sudah ada (beda huruf besar/kecil) | |
| C5 | Lampiran SPE1010566: unggah 1 jpg/png dan 1 pdf; coba file .xlsx | jpg/pdf tersimpan & bisa dilihat/diunduh; .xlsx ditolak | |
| C6 | Beranda Vendor – Specsheet | *Article belum masuk specsheet*: `ACC-ILZ4-FG · FH26` → `SPE1010566, SPE1010567`, lencana **Specsheet belum dibuat** (H3) | |

---

## D. Specsheet SMS r0 - Vendor – Specsheet

| # | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| D1 | Klik tugas di Beranda (C6) | Page Specsheet, model & season terpilih, tombol **← Beranda** (H4) | |
| D2 | + Buat Revisi → **Kosong**, stage **SMS** | Draft `SMS r0`, kedua article aktif | |
| D3 | Isi BOM sesuai tabel di bawah (tambah baris, subkomponen, komponen lokal, supplier, warna per article) | Grid sesuai tabel | |
| D4 | Sebelum mengisi warna kolom SPE1010567, dan dengan supplier baris 100 dikosongkan sementara → **Terbitkan** | Checklist memblokir: SPE1010567 belum dipakai di BOM; *Semua baris punya supplier* ✕. Isi lagi supplier ASEMINDO | |
| D5 | Beranda (jendela yang sama, Muat ulang) | Draft `FH26 - SMS r0`, lencana *1 article belum dipakai di BOM* (H1–H2) | |
| D6 | Lengkapi warna SPE1010567 → Terbitkan, alasan kosong | Terbit dengan *Revisi awal.* (kategori Lainnya); revisi terkunci | |
| D7 | Coba ubah satu sel di SMS r0 yang terbit | Tidak bisa (grid baca saja / ditolak DB) | |
| D8 | **Export Excel** specsheet | File `Specsheet_ACC-ILZ4-FG_FH26_SMS-r0.xlsx`; layout seperti PDF contoh, PURPOSE **Salesman Sample** tercentang, subkomponen ter-merge (X1–X2) | |
| D9 | Vendor – Specsheet: menu CBD / harga | Tidak ada menu CBD; tidak ada angka harga di Master Material | |

BOM SMS r0 (kolom warna = **SPE1010566** / **SPE1010567**):

| No | Komponen | Material | Supplier | SPE1010566 | SPE1010567 |
|---|---|---|---|---|---|
| 10 | Upper Overlay | Hulex Mono DE 107 | Hwasung | White C | Neon Safety Yellow 1 |
| 10-1 | *sub* Decoration HF Welding | Decoration TPU Clear HF Welding Logo | MGE | Holographic Coloring | Holographic Coloring |
| 20 | Tongue Logo | Hulex Mono DE 107 | Hwasung | White C | Neon Safety Yellow 1 |
| 20-1 | *sub* Printing Block + Logo | Decoration Printing Block + Logo | MGE | True Red 19-1664 TPG | Ice Flow 13-4404 TPG |
| 50 | Eyestay Insert Coating Film | Hotmelt FA7100 Paper 200 UM + Sticker | Asemindo | Clear | Clear |
| 60 | Upper Underlay | Honeylon Mesh | BHS | White | White |
| 70 | Tongue Collar | Elastic Knit UW240801 | GMT | White C / RIB | Neon Safety Yellow / RIB |
| 80 | Upper Lining | HASI 022T 160 | Hwasung | White | White |
| 80-1 | *sub* Laminating | Laminating Asemindo | Asemindo | Clear | Clear |
| 80-2 | *sub* Coating | W/ Coating FA 7300 50 Micron + Sticker | Asemindo | Clear | Clear |
| 100 | Plastic Padding | Plastic | Asemindo | Clear | Clear |
| 4010 | Sockliner Cover | Merry Mesh | BHS | True Red 19-1664 TPG | Ice Flow 13-4404 TPG |
| 4040 | Outsole | Outsole PRM-097 | winfaith | White C / True Red | Neon Safety Yellow / Ice Flow |
| 4060 | Insole | Hysock 16 N | Hanyoung | White | White |
| 6010 | Inner Box | Inner Box Specs New Design 2023 A6 | Kim | Red / White | Red / White |
| 8015 | **lokal** `Cement` | Cement Upper | Nanpao | Natural | Natural |
| 8030 | Shoe Lace | Lace Dual Width 32353 | Pelangi Elasindo | White C / Deco True Red | Neon Safety Yellow / Deco Ice Flow |

Remarks baris 8030 (dua baris, **Shift+Enter**): `Size 37-40: 115 cm` / `Size 41-44: 120 cm`.

---

## E. CBD SMS - Vendor – CBD

Nilai Yield / Loss % dari Excel. Loss % `1` = Excel 1,01. Loss % `0` = Excel 1.

| No | Yield | Loss % | Harga di CBD | Cost/pr (Rp) @ 16.300 |
|---|---|---|---|---|
| 10 | 7,73 | 1 | master USD 14,70 | 31.307,39 |
| 10-1 | 1 | 0 | master IDR 20.500 | 20.500,00 |
| 20 | 619,03 | 1 | master USD 14,70 | 390,94 |
| 20-1 | 1 | 0 | master IDR 1.500 | 1.500,00 |
| 50 | 49,09 | 1 | master USD 3,50 | 1.173,77 |
| 60 | 6,36 | 1 | master IDR 14.000 | 2.223,27 |
| 70 | 1 | 1 | master USD 2,27 | 37.371,01 |
| 80 | 6,36 | 1 | master USD 1,55 | 4.012,21 |
| 80-1 | 6,3 | 0 | master USD 0,65 | 1.681,75 |
| 80-2 | 6,3 | 0 | master USD 1,27 | 3.285,87 |
| 100 | 10,8 | 1 | master IDR 1.650 | 154,31 |
| 4010 | 12 | 1 | master IDR 11.500 (warna True Red) | 967,92 |
| 4040 | 1 | 1 | **quotation USD 3,45**, referensi `Quotation winfaith Sep 2025` | 56.797,35 |
| 4060 | 27,8 | 1 | master USD 2,42 | 1.433,11 |
| 6010 | 1 | 0 | master IDR 4.100 | 4.100,00 |
| 8015 | 1 | 0 | master IDR 2.600 | 2.600,00 |
| 8030 | 1 | 0 | master USD 0,311 | 5.069,30 |
| | | | **Material cost** | **174.568,20** |

Loss % baris baru **kosong** (F10b) - isi sesuai tabel (kosong dihitung 0 %).

Cost recapitulation: Direct Labour (LOP) **81.370** (keterangan `Estimasi LOP 2026`), Amortisasi 0, Adjustment 0 →
**ACTUAL FOB 255.938,20** · Target FOB **365.308** → **UNDER −109.369,80** · Margin **10 %** → Selling price
**284.375,77**.

| # | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| E1 | Beranda Vendor – CBD | *CBD perlu dibuat* 2 (SPE1010566, SPE1010567); *Harga master belum ada*: Merry Mesh · BHS, `1 warna tanpa harga` (Ice Flow) (H6, H10) | |
| E2 | Klik SPE1010566 | Page CBD, article **SPE1010566** terpilih, tombol ← Beranda (H9) | |
| E3 | + Buat CBD → **Baru dari specsheet** | Draft `SMS r0`, 17 baris per grup a/b/c/d + Subtotal, harga master terisi, Loss kosong, keterangan harga kosong hanya 4040 *quotation*; tidak ada tombol **Override…** | |
| E4 | Isi Yield & Loss %, quotation 4040, exchange rate **16.300**, LOP, target FOB, margin 10 % | Angka per baris & rekap **sama dengan tabel di atas** (pembulatan tampilan boleh beda ±1) | |
| E5 | Kosongkan exchange rate → Terbitkan | Rate tersimpan kosong; diblokir: *Exchange rate terisi* ✕; isi lagi | |
| E6 | Hapus Yield baris 50 → Terbitkan | Diblokir: baris berharga tanpa Yield; isi lagi | |
| E7 | Terbitkan (kategori bebas, alasan kosong) | Terbit *Revisi awal.*; Riwayat (1) | |
| E8 | **Export Excel** CBD | File `CBD_ACC-ILZ4-FG_FH26_SPE1010566_SMS-r0.xlsx`; angka = layar; ubah kurs L3 di Excel → semua ikut berubah (X4–X6) | |
| E9 | SPE1010567 → + Buat CBD → **Copy dari article lain** (SPE1010566) | Yield, Loss %, quotation, rate, LOP, target, selling price ikut; baris 4010 tanpa harga, keterangan harga hanya ada untuk warna lain (True Red 19-1664 TPG) | |
| E10 | Master Admin: Merry Mesh · BHS → tambah harga **IDR 11.500 warna `Ice Flow 13-4404 TPG`** | Harga APPROVED | |
| E11 | Vendor – CBD: muat ulang CBD SPE1010567 | Banner/keterangan *harga master tersedia* → **Refresh Harga dari Master** → 4010 = 967,92; material cost 174.568,20 | |
| E12 | Terbitkan SPE1010567 **tanpa alasan** | Terbit dengan *Revisi awal.* (revisi pertama article ini, walau hasil copy); Beranda Vendor – CBD: semua daftar kosong | |

---

## F. Usulan & approval

| # | Akun | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|---|
| F1 | Vendor – Spec | Master Komponen → Tambah `8040` Size Label · Master Supplier → **Usulkan** `su indonesia` | Komponen **PROPOSED**; supplier **SU INDONESIA** PROPOSED | |
| F2 | Vendor – Spec | Master Material → Tambah `Darmi Mesh`, Mesh, XM, Catalog → Supplier & Harga → tambah supplier **DAE YOUNG** | Material PROPOSED; supplier material PROPOSED; tidak ada kolom harga | |
| F3 | Vendor – Spec | Beranda | *Usulan Master Data*: `1 supplier · 1 material · 1 komponen · 1 supplier material` (H5) | |
| F4 | Vendor – CBD | Darmi Mesh → Usulkan harga **USD 2,95** (DAE YOUNG) | Status MENUNGGU APPROVAL | |
| F5 | Vendor – CBD | Elastic Knit UW240801 · GMT → Usulkan harga **USD 2,49** | MENUNGGU APPROVAL; harga 2,27 tetap berlaku | |
| F6 | Vendor – CBD | Hysock 16 N · Hanyoung → Usulkan **USD 24,20** (sengaja salah) | MENUNGGU APPROVAL | |
| F7 | Master Admin | Beranda | 5 bagian: supplier SU INDONESIA, material Darmi Mesh, komponen 8040, supplier material Darmi/DAE YOUNG, **3 usulan harga** (`USD 2.95`, `USD 2.49`, `USD 24.2`) (H11) | |
| F8 | Master Admin | Approve supplier (Master Supplier → Ubah → APPROVED), material, komponen, supplier material | Item hilang dari Beranda setelah Muat ulang (H12) | |
| F9 | Master Admin | **Tolak** usulan Hysock USD 24,20, alasan `Salah ketik, harga tetap 2,42` | Form tolak menampilkan *USD 24,2* (bukan NaN); DITOLAK; Vendor – CBD melihat alasannya | |
| F10 | - | Usulan Darmi & Elastic Knit **belum** di-approve (dipakai di langkah H) | | |

---

## G. Specsheet GTM r0 - Vendor – Specsheet

| # | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| G1 | Model Detail → + Article `SPE1010568` `BLACK / GOLD` | Beranda: *Article belum masuk specsheet* → `SPE1010568`, lencana **Pilih di revisi specsheet** | |
| G2 | Specsheet → + Buat Revisi → **Stage berikutnya** | Draft `GTM r0`, BOM SMS ter-copy, SPE1010568 belum ikut | |
| G3 | Baris 10 → **Ganti material** → HS ALPHA DE 107, supplier HWASUNG ( ANAN ) | Baris lama nonaktif; subkomponen 10-1 ikut pindah ke baris baru (P4) | |
| G4 | Baris 20 → Ganti material → HS ALPHA DE 107 / HWASUNG ( ANAN ) | Sub 20-1 ikut | |
| G5 | Baris 60 → Ganti material → **Darmi Mesh** / **DAE YOUNG** (disetujui di F8) | Bisa dipilih | |
| G6 | Baris 100 Plastic Padding → **Hapus** (klik dua kali) | Baris hilang | |
| G7 | Article di revisi: tambahkan SPE1010568 lalu **Drop** | SPE1010568 DROPPED; checklist tidak memblokir | |
| G8 | Terbitkan: kategori **Material**, alasan `Ganti Hulex Mono ke HS ALPHA, Upper Underlay ke Darmi Mesh, hapus Plastic Padding`, **tempel 1 screenshot (Ctrl+V)** | Terbit tanpa error; Riwayat (2); baris GTM r0 *1 gambar* → gambar tampil | |
| G9 | Coba terbitkan revisi berikutnya tanpa alasan (buat draft GTM r1 lalu Terbitkan) | Ditolak: alasan wajib → hapus draft GTM r1 | |

---

## H. CBD GTM r0 - Vendor – CBD (setelah specsheet GTM terbit)

| # | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| H1 | Beranda Vendor – CBD | *CBD terbit perlu revisi*: SPE1010566 & SPE1010567 (`SMS r0`, PERLU REVISI); SPE1010568 tidak muncul (di-drop) (H7) | |
| H2 | Page CBD → chip SPE1010568 | `DI-DROP`, tidak bisa buat CBD | |
| H3 | SPE1010566 → + Buat Revisi CBD → **Revisi berikutnya** | Draft **GTM r0** (stage ikut specsheet); Yield/Loss dibawa; baris 10/20/60 asal *ganti material*; Plastic Padding di bagian **Hilang dari specsheet** (tidak dihitung); 8015 harga master IDR 2.600 | |
| H4 | Lihat baris 60 (Darmi Mesh) & 70 (Elastic Knit) | 60: kosong, keterangan **menunggu approval**; 70 masih USD 2,27 | |
| H5 | Master Admin approve usulan Darmi USD 2,95 dan Elastic Knit USD 2,49 | Approve; harga Elastic Knit 2,27 ditutup | |
| H6 | Vendor – CBD: Beranda | SPE1010566 di *Draft CBD perlu refresh* lencana **Harga master berubah** (H8) | |
| H7 | Page CBD → **Refresh Harga dari Master** | 60 = USD 2,95, 70 = USD 2,49 | |
| H8 | Ubah: rate **17.789** · Insole Yield **25,5** · LOP **83.740** (`LOP 2026`) · tambah baris Amortisasi `Amortisasi Mold Upper` **4.000** · Adjustment (`Adjustment Piero`) **500** · margin 10 % | Material cost **192.695,51** · ACTUAL FOB **280.935,51** · UNDER **−84.372,49** · Selling price **312.150,57** | |
| H9 | Hapus baris Amortisasi default | Tidak bisa (baris default); baris tambahan bisa dihapus | |
| H10 | Adjustment `-100` lalu kembali `500`; LOP `-1` | Adjustment boleh minus; LOP minus ditolak | |
| H11 | Terbitkan: kategori **Exchange rate**, alasan `Kurs 16.300 → 17.789, LOP 2026, amortisasi mold upper, harga knit & Darmi Mesh` | Terbit; Riwayat CBD (2) | |
| H12 | Ulangi H3–H11 seperlunya untuk SPE1010567 (atau cukup H3 + H7 + terbit) | Terbit | |
| H13 | Beranda Vendor – CBD | Semua daftar kosong | |

Hasil cost GTM per baris (rate 17.789): 10 = 29.286,26 · 10-1 = 20.500 · 20 = 365,71 · 20-1 = 1.500 · 50 = 1.281,00 ·
60 = 8.333,70 · 70 = 44.737,56 · 80 = 4.378,72 · 80-1 = 1.835,37 · 80-2 = 3.586,04 · 4010 = 967,92 ·
4040 = 61.985,77 · 4060 = 1.705,09 · 6010 = 4.100 · 8015 = 2.600 · 8030 = 5.532,38.

---

## I. Brand Viewer

| # | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| I1 | Beranda | 2 kolom: Specsheet `ACC-ILZ4-FG · FH26 - GTM r0`; CBD SPE1010566/567 `GTM r0` (tanpa draft) (H13) | |
| I2 | Klik specsheet → stepper | Hanya revisi terbit (SMS r0, GTM r0); tidak ada tombol ubah | |
| I3 | CBD SPE1010566 | Revisi terbit saja; harga, rekap, selling price & margin terlihat; tidak bisa diubah | |
| I4 | Export Excel specsheet & CBD | File sama dengan layar (X8) | |
| I5 | Buat draft CBD baru di jendela Vendor – CBD (jangan terbitkan) → Brand muat ulang | Draft **tidak** terlihat oleh Brand | |

---

## J. System Admin & penutup

| # | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|
| J1 | Beranda System Admin | Model 1, Specsheet 1, Revisi CBD ≥ 4, user aktif 5, aktivitas terakhir = barusan | |
| J2 | Audit Log, filter entitas `cbd_revision` / `material_price` | Terbit, refresh, approve/tolak tercatat dengan email pelaku | |
| J3 | Semua role: tombol **↻ Muat ulang** di Beranda; jendela ±1280 px | Berfungsi; tampilan rapi (H15, H17) | |
| J4 | Hapus token (DevTools → Local storage) lalu muat ulang Beranda | Kembali ke Login (H16) | |
| J5 | Vendor – CBD **Keluar**, lalu tombol Back browser | Tetap di Login (tidak masuk lagi) | |

Cek angka langsung di DB (opsional, DB Tools):
```sql
SELECT a.code, r.stage || ' r' || r.revision_no AS rev, r.status, rc.material_cost, rc.actual_fob, rc.variance_label
FROM cbd_revision r JOIN article a ON a.id = r.article_id JOIN v_cbd_recap rc ON rc.cbd_revision_id = r.id
ORDER BY a.code, r.stage_order, r.revision_no;
```
Harapan: SPE1010566 `SMS r0` 174.568,20 / 255.938,20 / UNDER · `GTM r0` 192.695,51 / 280.935,51 / UNDER.
