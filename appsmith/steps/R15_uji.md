# R15: sistem ke bahasa Inggris + tanpa em dash (14 Okt 2026)

Lanjut dari data yang ada (tanpa reset). Base build = `exports/build_r14.json` (app R14 Anda tidak diubah, hanya
di-deploy).

Isi R15:
- **Semua teks yang tampil di app** memakai bahasa Inggris sederhana: label, tombol, judul, pesan, isi Custom Widget,
  pesan error dari database, Tugas Saya, dan export Excel. Data yang Anda isi (nama material, alasan, dll.) **tidak**
  diubah, termasuk alasan lama seperti "Revisi awal." di riwayat.
- **Tanpa em dash** di app, pesan database, dan dokumen.
- **Nama page baru**: Beranda → **Home**, Master Komponen → **Master Component**, Master Pilihan → **Master Options**,
  Persetujuan Harga → **Price Approval**. Page lain tetap. Bookmark ke 4 page itu perlu diganti.
- **Kode status harga** (kolom Remarks di tab Prices, Material Detail): ACTIVE, UPCOMING, PENDING APPROVAL, REJECTED,
  CANCELLED, EXPIRED, NO PRICE. Selisih Target FOB: OVER / UNDER / MATCH.
- **Excel specsheet**: PURPOSE berisi 5 kotak sesuai sistem (Pullover, Preview, SMS, GTM, Production); stage yang
  dicentang = stage revisi.
- **T72**: kolom **Last login** di tabel user selama ini menampilkan jam sekarang (membaca kolom yang tidak ada).
- Format angka & tanggal tetap seperti sebelumnya (mis. 16.300,00 dan 14 Oct 2026, jam WIB).

**Perbaikan 14 Okt (T73):** `exports/build_r15.json` pertama membuat data tidak tampil (JSObject `Auth` tiap page
tertimpa template kosong, sehingga query page tidak dijalankan dan cek izin page hilang). Import ulang
`exports/build_r15.json` yang baru. SQL R15 tidak perlu dijalankan ulang. Cek data: `sql/R15_cek_data.sql` (hanya baca).

## 0. Pasang

| # | Langkah | Hasil |
|---|---|---|
| 0.1 | DB Tools → jalankan `sql/R15_english.sql` (prepared statements OFF) | `R15 terpasang` · `price states: ...` (kode bahasa Inggris) · `stage label: Production` · `role: Vendor - Specsheet` |
| 0.2 | DB Tools → jalankan `sql/R_selftest.sql` | **`SELFTEST LOLOS`** (204 cek, semua dibatalkan) |
| 0.3 | Import `exports/build_r15.json` sebagai app baru → cek datasource *Prestasi* tersambung → Deploy → nyalakan akses publik | Nama app *Product Management R15*; daftar page: Home, Admin, Master Supplier, Master Component, Master Material, Material Detail, Master Options, Price Approval, Model List, Model Detail, Specsheet, Cost Breakdown (CBD), Login |

Catatan: setelah R15 dipasang, app R14 lama masih jalan tetapi status harga di tab Prices tampil dengan kode baru
(bahasa Inggris) tanpa warna dan filter riwayatnya tidak jalan. Pakai app R15.

## A. Navigasi & bahasa (cek sekilas per role)

| # | Langkah | Hasil |
|---|---|---|
| A1 | Login (form Login, Change Password) | Teks bahasa Inggris (Log in, Show / Hide, Forgot password? …) |
| A2 | Home: menu & My Tasks untuk tiap role (Vendor Specsheet, Vendor CBD, Manager Costing, Brand, System Admin) | Kartu menu & My Tasks bahasa Inggris; klik menu membuka page yang benar (termasuk **Price Approval**) |
| A3 | Header: tombol Home, Change Password, Log out; tombol kembali "← Home" dari Specsheet / CBD yang dibuka dari My Tasks | Semua berpindah ke page yang benar |
| A4 | Buka semua page dan modal (form tambah / ubah, Create Revision, Create CBD, Publish, harga, varian, lampiran) | Tidak ada teks Indonesia dan tidak ada em dash (—) di layar. Catat bila menemukan |
| A5 | Picu beberapa pesan error database: simpan supplier tanpa nama; tolak harga tanpa alasan; terbitkan specsheet dengan sel kuning; tambah model dengan nama yang sudah ada | Pesan bahasa Inggris yang jelas (mis. "Supplier name is required.", "2 color cell(s) have no Material Code (yellow cells): …", "Model 'X' already exists in this factory.") |
| A6 | Pesan sesi: biarkan sesi habis lalu klik Search | "Session expired. Please log in again." lalu ke Login |

## B. Harga (Material Detail → tab Prices)

| # | Langkah | Hasil |
|---|---|---|
| B1 | Buka material yang punya harga | Kolom **Remarks**: ACTIVE (hijau), UPCOMING / PENDING APPROVAL (oranye), REJECTED: alasan (merah), NO PRICE (merah) |
| B2 | Nyalakan **Show history** | Baris EXPIRED dan CANCELLED (never active) ikut tampil |
| B3 | + Add Price / + Propose Price; Copy Price | Status per varian "Active: … since …" / "Pending: …"; tombol Save / Propose bekerja |
| B4 | Manager Costing: Approve / Reject / End; page **Price Approval** | Berjalan seperti sebelumnya; teks bahasa Inggris |
| B5 | Hapus varian yang masih punya harga | Pesan "… cannot be deleted: used in N specsheet revision(s); still has prices: ACTIVE (1) …" |

## C. Specsheet, CBD, Excel

| # | Langkah | Hasil |
|---|---|---|
| C1 | Specsheet: Create Revision (Start empty / Copy / Next revision / Next stage + Target stage), Publish dengan gambar | Berjalan seperti R14; teks bahasa Inggris |
| C2 | Specsheet → **Export Excel** untuk revisi Preview | PURPOSE: 5 kotak (Pullover, Preview, SMS di kolom kiri; GTM, Production di kanan), hanya **Preview** dicentang; baris "STAGE PREVIEW · REVISION 0 · …" |
| C3 | CBD: Create CBD, isi rate & yield, harga quotation / propose master price, no charge, Publish | Berjalan seperti sebelumnya; banner & checklist bahasa Inggris |
| C4 | CBD dengan Target FOB → **Export Excel** | Selisih: OVER / UNDER / MATCH; judul kolom & change log bahasa Inggris |

## D. Admin

| # | Langkah | Hasil |
|---|---|---|
| D1 | Admin → User | Kolom **Last login** berbeda per user (bukan jam sekarang); status Active / Inactive / Locked / Must change password |
| D2 | Admin → Audit Log → klik baris | Panel detail (R14) tetap berjalan |
| D3 | (T73) Login sebagai Vendor CBD lalu buka URL page Admin langsung | Ditolak: "Role … has no access to this page." lalu ke Home |

Kirim export app setelah uji (base build berikutnya) + daftar teks yang masih bahasa Indonesia / kurang pas bila ada.
