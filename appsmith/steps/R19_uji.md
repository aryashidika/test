# R19: uji catatan user (nomor komponen, nomor artikel, Dimension, Process, ganti komponen, filter, field model)

Isi R19 (catatan uji user 26 Okt 2026, keputusan setelah diskusi):
1. **Nomor komponen = posisi**: nomor yang sudah dipakai di kelompok yang sama -> komponen itu dan yang menempel di bawahnya
   bergeser +10, langsung tanpa konfirmasi. Nomor di specsheet / CBD lama ikut berubah.
2. **Nomor artikel boleh kosong**: Pullover / Preview bebas, SMS / GTM peringatan, **Production terbit diblokir**. Muncul di Tugas Saya.
3. **Dimension diisi di kolom Dimension** (bukan di nama material). Ketik Material Code di kolom Material tetap bisa.
4. **Material Process**: tanda Process di material (tanpa Material Code, tidak kuning, harga quotation per CBD tanpa approval).
5. **Ganti komponen** di specsheet draft (tombol **Change** di kolom Component).
6. **Saran material terbaca penuh** (teks membungkus, nama + UoM + dimension).
7. **Filter di-reset** setiap halaman dibuka (dari Home, setelah login, F5), kecuali saat kembali dari halaman detail.
8. **Semua field model wajib**.

> Build ini dibuat dari export app Anda tanggal 26 Okt 2026 (`exports/export_r18.json`, isinya sama dengan build R18).

Beri tanda di kolom **OK?** (v / x). Kalau ada yang beda, kirim tangkapan layar dan teks pesannya.

## 0. Pasang

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 0.1 | DB Tools → jalankan `sql/R19_catatan_uji.sql` (prepared statements OFF) | `R19: article tanpa nomor 0, material Process 0` | |
| 0.2 | Jalankan lagi `sql/R19_catatan_uji.sql` | Aman: hasil sama | |
| 0.3 | DB Tools → jalankan `sql/R_selftest.sql` | **`SELFTEST LOLOS`** | |
| 0.4 | Import `exports/build_r19.json` (timpa app), lalu Deploy | Nama app `Product Management R19` | |
| 0.5 | Buka page **Login** → pastikan `LoginCtrl.onPageLoad` masih **Run on page load ON** | ON | |
| 0.6 | Buka page **Home** → JSObject **Auth** → `onPageLoad` masih **Run on page load ON** (cek juga 1-2 page lain) | ON | |

## 1. Nomor komponen = posisi (Master Component, Vendor Spec)

Siapkan di kelompok Upper tiga nomor kosong berurutan, mis. komponen uji `UJI A` di 1500 dan `UJI B` di 1510.

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 1.1 | + Add: kelompok Upper, nomor **1500**, nama `UJI X` | Tersimpan tanpa konfirmasi: `UJI X` = 1500, `UJI A` = 1510, `UJI B` = 1520 | |
| 1.2 | Hint nomor di form | `... A number already in use moves that component (and the ones right after it) down by 10.` | |
| 1.3 | Edit `UJI B` → nomor 1500 (pindah ke atas) | `UJI B` = 1500, `UJI X` = 1510, `UJI A` = 1520 | |
| 1.3b | Edit `UJI B` (1500) → nomor 1510 (pindah ke bawah, kasus laporan Anda) | `UJI X` naik ke **1500**, `UJI B` = 1510, `UJI A` tetap 1520 (tidak ada yang ke 1530) | |
| 1.3c | Edit `UJI X` (1500) → 1520 (turun 2 posisi) | `UJI B` = 1500, `UJI A` = 1510, `UJI X` = 1520 | |
| 1.3d | Hint nomor saat Edit (perlu import ulang build) | `... Moving to a number in use shifts the components in between by 10 (like the Order in Master Options).` | |
| 1.4 | Edit `UJI X` → nomor kosong (mis. 1540) | Hanya `UJI X` pindah; celah 1520 dibiarkan | |
| 1.5 | Edit komponen yang dipakai di specsheet terbit → ganti **nomor** | Tersimpan; nomor di specsheet terbit ikut berubah saat dibuka / di Excel | |
| 1.6 | Komponen yang sama → ganti **nama** | Ditolak: `Name and group of component ... cannot be changed ... The number can still be changed.` | |
| 1.7 | Nomor terpakai di ujung rentang (mis. 3990 bila sudah dipakai) | Ditolak: `Number 3990 is taken and the components after it cannot move down ...` | |

## 2. Nomor artikel boleh kosong (Model Detail + Specsheet)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 2.1 | Model Detail → + Article: Article No. **kosong**, Colorway `RED` | Tersimpan. Label `Article No.` tanpa bintang, ada catatan `Can stay empty ... Required to publish the Production specsheet` | |
| 2.2 | Tabel Articles | Kolom **Article No.** berisi `(no article no.)` | |
| 2.3 | + Article lagi: nomor kosong, Colorway `red` | Ditolak: `An article without article no. with colorway RED already exists ...` | |
| 2.4 | Home (Vendor Spec) | Angka **Articles without article no.** + bagian **Articles Without Article No.** (`Colorway: RED`); klik → Model Detail season itu | |
| 2.5 | Specsheet Preview: masukkan article tanpa nomor, isi warna, Publish | Checklist: `All articles have an article no.` = peringatan (bukan pemblokir); terbit | |
| 2.6 | Header grid BOM & Export Excel | `(no article no.)` (Excel: sel kuning) + colorway | |
| 2.7 | Edit article itu: isi nomor (sudah dipakai di specsheet terbit) | **Bisa** disimpan | |
| 2.8 | Edit lagi: ganti nomor (koreksi salah ketik) | **Bisa** (belum ada di Production terbit); specsheet Preview ikut tampil nomor baru | |
| 2.8b | Edit lagi: kosongkan nomor | Ditolak: `Article no. ... cannot be cleared because the article is used ... Type the correct number instead.` | |
| 2.9 | Article lain tanpa nomor → specsheet **SMS** → Publish | Peringatan `... Allowed before Production; required in Production`; tetap bisa terbit | |
| 2.10 | Next stage **Production** dengan article tanpa nomor → Publish | Checklist merah; terbit ditolak: `In Production every article needs an article no. ...`; Home draft: flag merah `... articles without article no.` | |
| 2.11 | Isi nomornya di Model Detail → kembali Publish Production | Terbit | |
| 2.11b | Model Detail → Edit article yang ada di Production terbit | Kotak nomor terkunci: `... is in a published Production specsheet/CBD.` | |
| 2.12 | CBD (Vendor CBD) untuk article tanpa nomor di Preview | Bisa dibuat; chip article `(no article no.) <colorway>` (dua article tanpa nomor bisa dibedakan); Tugas Saya CBD `(no article no.)` + colorway | |
| 2.13 | Export Excel CBD article tanpa nomor | Nama file & sheet memuat colorway | |
| 2.14 | Drop article tanpa nomor di revisi specsheet berikutnya | Hilang dari Tugas Saya **Articles Without Article No.** | |

## 3. Dimension di kolom sendiri + 6. saran terbaca penuh (grid BOM, draft)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 3.1 | Baris tambah: ketik sebagian nama material panjang | Daftar saran **membungkus**: nama lengkap + baris kecil `UOM · dimension: ...` | |
| 3.2 | Pilih dengan panah + Enter | Nama masuk kolom Material (Enter belum menyimpan baris); UoM terisi. Material dengan **satu** dimension: Dimension langsung terisi | |
| 3.3 | Material dengan beberapa dimension, Dimension kosong → + Add | Pesan `Fill in the Dimension of ... (registered: ...). A new dimension is also allowed.`; kotak Dimension merah | |
| 3.4 | Klik kotak Dimension, lalu ketik `1,4mm` | Saran dimension material itu + jumlah warna; ketikan jadi `1.4 MM` | |
| 3.5 | Ketik dimension baru | Catatan kecil `new dimension (cells stay yellow ...)` | |
| 3.6 | Ketik cara lama `NAMA · 1.2mm` atau `NAMA . 1,2 mm` di Material | Dipisah: nama ke Material, `1.2 MM` ke Dimension | |
| 3.7 | Ketik Material Code di Material | Nama + Dimension terisi, tawaran `Fill color ... into all articles` | |
| 3.7b | Baris tambah / sub: ganti Material ke material **lain** (Dimension terisi otomatis atau diketik sendiri) | Dimension mengikuti material baru: terdaftar juga di material baru = **tetap**; material baru satu dimension = **diganti** itu; beberapa dimension = **kosong** (pilih dari saran); tanpa dimension / Process = **kosong**. Nama sama diketik ulang = Dimension tidak berubah; setelah itu dimension baru tetap boleh diketik (catatan `new dimension`) | |
| 3.8 | Dua material bernama sama beda UoM | Saran `NAMA (YD)` / `NAMA (M)`; ketik nama saja → pesan pilih salah satu | |
| 3.9 | Baris yang ada: ubah **Dimension** | Material diganti ke dimension baru (Undo replace muncul) | |
| 3.10 | Baris yang ada: ganti **nama material** ke material yang punya beberapa dimension (dimension baris tidak terdaftar) | Belum disimpan; pesan `Now pick the dimension of ...`; kotak Dimension kuning muda & aktif. Pilih dimension → tersimpan sekali | |
| 3.11 | Sama seperti 3.10, lalu tekan **Esc** di Dimension | Batal, material lama kembali | |
| 3.12 | Header grid & sel Material panjang | Teks membungkus (tidak terpotong) | |

## 4. Material Process

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 4.1 | Master Material → + Add: centang **Process material (no Material Code)** | Metode harga otomatis Quotation (tombol terkunci); simpan → `Process material added.` | |
| 4.2 | Material Detail material itu | Info `Process material (no Material Code)`; tombol **+ Variant** tidak tampil; catatan harga `Process material: ... quotation per CBD line` | |
| 4.3 | Tabel Master Material | Price Method `Process (quotation)`, Variants `-` | |
| 4.4 | Specsheet → + New material (bar atas) → centang Process | Bisa langsung dari specsheet | |
| 4.5 | Pakai material Process di grid, isi warna | Badge **process**, sel **tidak kuning**, tanpa tombol Register; specsheet **SMS** tetap bisa terbit | |
| 4.6 | Excel specsheet | Sel material Process tidak kuning / tanpa `(no code)` | |
| 4.7 | CBD (Vendor CBD), stage SMS / Production | Baris Process = Quotation: isi harga + currency + referensi, **tanpa approval**; CBD tidak terblokir karena baris ini | |
| 4.8 | Material lain yang sudah punya varian → Edit → centang Process | Checkbox terkunci, catatan `This material has variants ...` | |
| 4.9 | Material Process yang sudah dipakai dokumen terbit → Edit | Checkbox terkunci, catatan `... used in a published specsheet / CBD.` | |
| 4.10 | Manager Costing / Vendor CBD: Edit material **belum dipakai** dokumen terbit → centang / lepas Process | **Bisa** (metode harga ikut Quotation; dilepas → bisa pilih Catalog / Quotation). Nama / kategori / UoM tetap terkunci | |
| 4.10b | Tim CBD: material Process yang sudah dipakai dokumen terbit | Checkbox terkunci (sama seperti Vendor Spec) | |

## 5. Ganti komponen (Specsheet draft)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 5.1 | Kolom Component baris induk | Ada tombol kecil **Change** (baris sub tidak) | |
| 5.2 | Dua baris dengan komponen sama (mis. 2× UPPER) → Change salah satu → ketik komponen master lain → Enter | **Hanya baris itu** (+ subnya `No-1`) pindah; baris UPPER lain tetap | |
| 5.3 | Change ke komponen yang sudah punya **material + dimension yang sama** di revisi ini | Ditolak: `Component ... already has this material with the same dimension in this revision.` (material beda = boleh) | |
| 5.3b | Ganti material baris → Change komponen → Undo replace | Komponen baru tetap | |
| 5.4 | Change ketik nama yang bukan master | Pesan `"..." is not in the component master. Pick a master component from the list.` | |
| 5.5 | Komponen lokal → Change ke komponen master | Berhasil, tanda `local` hilang | |
| 5.6 | Esc / klik di luar tanpa isian | Batal | |
| 5.7 | Buat CBD / Refresh dari specsheet setelah terbit | CBD tetap tersambung (Yield baris tidak hilang) | |

## 7. Reset filter

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 7.1 | Master Material: isi pencarian + filter kategori → klik baris → Material Detail → **Back** | Filter & pencarian **tetap** | |
| 7.2 | Dari Material Detail klik Home → buka Master Material lagi | Filter **kosong** | |
| 7.3 | Model List: isi pencarian → buka Model Detail → buka Specsheet → Back → Back | Model Detail & Model List: filter **tetap** | |
| 7.4 | Model List → buka model lain | Model Detail model lain mulai dari tab / tabel awal | |
| 7.5 | Isi filter di Master Supplier / Master Component / Master Options / Admin → tekan **F5** | Filter **kosong** | |
| 7.6 | Logout → login → buka page berfilter | Filter **kosong** | |

## 8. Semua field model wajib (Model List + Model Detail)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 8.1 | + Model: semua label bertanda `*` + catatan `All fields are required.` | | |
| 8.2 | Simpan dengan field kosong satu per satu | Pesan berurutan: `Category is required.`, `Gender ...`, `Construction ...`, `Last No. ...`, `Outsole Mould ...`, `At least one size is required.` (kotak ukuran merah), `Sample Size is required.` | |
| 8.3 | Edit model lama yang belum lengkap | Harus dilengkapi dulu sebelum tersimpan | |

## 9. Cek DB (opsional, DB Tools)

```sql
SELECT count(*) FILTER (WHERE code IS NULL) AS article_tanpa_nomor FROM article;
SELECT name, price_method FROM material WHERE is_process ORDER BY name;
SELECT kind, model_name, season, article_codes FROM v_worklist_spec WHERE kind = 'NO_ARTICLE_NO';
```
