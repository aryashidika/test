# R18: uji ganti teks (tombol "+ Create" dan Thickness jadi Dimension)

Isi R18 (permintaan user 26 Okt 2026):
- Specsheet: tombol **`+ Create Revision` jadi `+ Create`**, pesan kosong ikut: `No revisions yet. Click "+ Create".`
  Judul form `Create Revision: <season>` dan catatan di form Publish **tetap** (keputusan user).
- **Thickness jadi Dimension** di semua teks yang terlihat: label, kolom tabel, pesan, placeholder, tooltip, header Excel
  (specsheet `DIMENSION`, CBD `Dimension`), dan pesan dari database (`no dimension`, `same dimension`, dst.).
- **Tidak berubah:** nama kolom DB (`thickness`), fungsi SQL (`fn_clean_thickness`, `fn_thickness_label`), nama variabel, cara
  pembakuan nilai (`1.0 MM` = `1 MM`, dll.), dan data yang sudah ada.

> Build ini dibuat dari export app Anda tanggal 26 Okt 2026 (`exports/export_r17.json`, isinya sama dengan build R17).

Beri tanda di kolom **OK?** (v / x). Kalau ada yang beda, kirim tangkapan layar dan teks pesannya.

## 0. Pasang

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 0.1 | DB Tools → jalankan `sql/R18_dimension.sql` (prepared statements OFF) | `teks kosong: no dimension` | |
| 0.2 | Jalankan lagi `sql/R18_dimension.sql` | Aman: hasil sama | |
| 0.3 | DB Tools → jalankan `sql/R_selftest.sql` | **`SELFTEST LOLOS`** | |
| 0.4 | Import `exports/build_r18.json` (timpa app), lalu Deploy | Nama app `Product Management R18` | |
| 0.5 | Buka page **Login** → pastikan `LoginCtrl.onPageLoad` masih **Run on page load ON** | ON | |

## 1. Specsheet

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 1.1 | Buka specsheet (role Vendor Spec) | Tombol kanan atas **`+ Create`** | |
| 1.1b | Buka specsheet yang belum punya revisi (season baru) | Pesan `No revisions yet. Click "+ Create".` | |
| 1.2 | Klik `+ Create` | Form tetap berjudul `Create Revision: <season>`, isinya sama seperti dulu | |
| 1.3 | Lihat header grid BOM | Kolom **Dimension** (dulu Thickness) | |
| 1.4 | Klik kotak Material di baris tambah | Placeholder `Name · dimension / Material Code…` | |
| 1.5 | Ketik material yang ada dengan dimension baru, mis. `NAMA · 9.9 MM` | Kolom Dimension `9.9 MM (new)`; arahkan mouse: `New dimension for this material: ...` | |
| 1.6 | Ketik nama material saja yang punya beberapa dimension | Pesan `... has several dimensions. Pick from the list (NAME · DIMENSION) ...` | |
| 1.7 | Arahkan mouse ke sel kuning | `... a variant of this material + dimension ...`; tombol daftar: `Register variant NAMA · <dimension / no dimension> · WARNA` | |
| 1.8 | Ketik Material Code material lain di sel warna | `Code ... · ... · .... It does not match the material / dimension of this line.` | |
| 1.9 | Replace Material dengan material + dimension yang sama | Pesan dari DB: `The new material and dimension are the same as the current ones.` | |
| 1.10 | Export Excel specsheet | Header kolom **`DIMENSION`** | |

## 2. Form varian (Register variant di Specsheet, dan + Variant di Material Detail)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 2.1 | Buka form | Label **Dimension**; hint `4 material type · 3 dimension · 3 color. Filled in from color & dimension ...` | |
| 2.2 | Ketik kode 10 karakter dengan bagian tengah baru | Catatan `Dimension code XXX is new. ...` | |
| 2.3 | Ketik kode yang bagian tengahnya sudah berarti dimension lain | Peringatan `Dimension code XXX is already recorded as ...`; Save → pesan DB `Confirmation needed: dimension code ...` | |
| 2.4 | Ubah dimension varian yang sudah dipakai dokumen terbit | `... Its Material Code, color, and dimension cannot be changed. ...` | |

## 3. Master Material, Material Detail, Price Approval

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 3.1 | Master Material → `+ Add material` | Hint `No dimension & color here. ...`; info `... add variants (dimension × color → Material Code).` | |
| 3.2 | Material Detail → tab Varian dan tab Harga | Kolom **Dimension**; varian tanpa dimension tertulis `no dimension` | |
| 3.3 | Material Detail → form harga → kotak cari varian | Placeholder `Search code / color / dimension` | |
| 3.4 | Price Approval (Manager Costing) | Kolom **Dimension** | |

## 4. CBD

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 4.1 | Buka CBD | Kolom **Dimension** | |
| 4.2 | Export Excel CBD | Header kolom D **`Dimension`** | |
| 4.3 | Buat CBD dari model lain (cross-model) | Catatan `... same material + dimension; ...` | |
