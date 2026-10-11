# E2E-R — Pasang revisi R3–R7 sekaligus + uji end-to-end (2 pabrik)

Keputusan 11 Okt 2026: satu file SQL + satu import. Semua sudah saya uji di PostgreSQL 16 lokal (file gabungan dijalankan dari
skema R2b, 2× tanpa error, self-test 87 cek lolos, 135 query app lolos EXPLAIN). Yang belum bisa saya uji: tampilan & klik di
Appsmith sungguhan — itu bagian Anda di bawah.

## 0. Pasang

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| 0.1 | **Jangan ubah app** sampai build di-import (base = `export_r2.json`). | – |
| 0.2 | DB Tools → jalankan `sql/RESET_data_bisnis.sql` | Tabel material/supplier = 0; user & pabrik tetap |
| 0.3 | DB Tools → jalankan `sql/R_revisi_semua.sql` (Use prepared statements = OFF) | Baris terakhir `R3–R7 terpasang` · `variant_id harga: 1 · model tanpa kode: true · sel varian: 1 · PO SMS: 1.2500 · model induk: 1`. Kalau error: tidak ada yang tersimpan — kirim pesannya ke saya |
| 0.4 | DB Tools → jalankan `sql/R_selftest.sql` | Hasil **`SELFTEST LOLOS`** (data uji otomatis dibatalkan). Kalau `SELFTEST GAGAL: …` kirim pesannya |
| 0.5 | Import `exports/build_r7.json` sebagai **app baru** → hubungkan datasource `Prestasi` bila diminta → cek akses publik → **Deploy** | 13 page, termasuk page baru **Persetujuan Harga** |
| 0.6 | Login sebagai System Admin → **Keluar** | Kembali ke form login (bukan Beranda) |

## 1. Rapikan tampilan (sekali, di editor Appsmith)

Ukuran/posisi sudah saya isi, tapi cek dan geser bila perlu:
- **Material Detail** → tab **Harga**: `txtHargaInfo`, tombol **Salin Harga** & **+ Ajukan Harga**, switch *Tampilkan riwayat*, `tblPrices` (lebar kolom). Modal `mdlHarga` (760 px).
- **Persetujuan Harga**: tinggi `cwPriceApproval` (±860 px); urutan page di navigasi kiri.
- **Beranda**: tinggi `cwMenu` (ada item baru *Persetujuan Harga* untuk Manager Costing).
- **Model List**: dropdown **Pabrik** (`selModelPabrik`, hanya tampil untuk Brand/System Admin) di samping tombol Tambah; kolom `tblModels`. Modal `mdlModel` (720 px) di Model List & Model Detail.
- **Specsheet**: modal baru `mdlVarianBaru` & `mdlSupplierBaru`; `mdlRevisi` (lebih tinggi); tombol **+ Supplier baru** di bar atas grid BOM.
- **CBD**: bagian *Simulasi harga jual* (hanya Brand) di bawah Cost recapitulation.

## 2. Siapkan data (System Admin)

| # | Langkah | Hasil |
|---|---|---|
| 2.1 | Admin → Pabrik: pastikan ada **PABRIK A** & **PABRIK B** | – |
| 2.2 | Admin → User: per pabrik 1 user **Vendor Spec**, **Vendor CBD**, **Manager Costing**; plus 1 **Brand Viewer** (tanpa pabrik) | User role pabrik tanpa pabrik ditolak |

## 3. Master & varian (Vendor Spec A)

| # | Langkah | Hasil |
|---|---|---|
| 3.1 | Master Supplier/Komponen: tambah 2 supplier & komponen yang dipakai contoh FH26 | Nama mirip muncul saat mengetik |
| 3.2 | Master Material: material induk (mis. MESH) + varian per warna/thickness (kode ERP), supplier material (utama) | Seperti R2 |
| 3.3 | Master Pilihan: Kategori (mis. RUNNING), Last & Outsole mold pabrik A | GENDER & UKURAN 35–47 sudah ada |

## 4. Harga (R3)

| # | Langkah | Hasil |
|---|---|---|
| 4.1 | Vendor CBD A → Material Detail → tab **Harga** | Satu baris per varian × supplier; pasangan tanpa harga = **BELUM ADA HARGA** |
| 4.2 | **+ Ajukan Harga**: pilih supplier, centang 4 varian, harga, **klik IDR/USD**, Ajukan | 4 baris MENUNGGU APPROVAL; varian yang menunggu tidak bisa dicentang lagi |
| 4.3 | Login Manager Costing A → Beranda | 1 pengajuan → klik → page **Persetujuan Harga** (kartu disorot) |
| 4.4 | Centang 1 → **Tolak terpilih** + alasan; lalu **Setujui semua** (klik 2×) | 1 DITOLAK, 3 BERLAKU |
| 4.5 | Vendor CBD A → **Salin Harga** dari varian berharga ke varian lain | Usulan baru (referensi "Salin dari …"); MC menyetujui |
| 4.6 | Ajukan harga baru untuk varian yang sudah berharga (berlaku besok) → MC setujui | Harga lama tetap BERLAKU hari ini, ditutup per besok |
| 4.7 | MC: tombol **Akhiri** di baris BERLAKU · MC tidak punya tombol Ajukan · Vendor CBD tidak punya Setujui/Akhiri | Sesuai |
| 4.8 | Beranda Vendor CBD | Kartu **Usulan Harga Ditolak** + alasan |

## 5. Model & specsheet (R4)

| # | Langkah | Hasil |
|---|---|---|
| 5.1 | Vendor Spec A → Model List → **+ Tambah Model**: nama, Kategori, Gender, Last, Outsole mould, **ukuran** (klik 37 lalu 44, klik 41 untuk membuang), sample size | Kolom Ukuran "37–40, 42–44"; tanpa kolom Kode; nama model sama di pabrik A ditolak |
| 5.2 | Model Detail: season + 3 article | – |
| 5.3 | Specsheet → Buat Revisi (Mulai kosong) → baris tambah: ketik **Material Code** di kolom Material | Terisi NAMA · THICKNESS + tawaran "Isi warna X ke semua article" |
| 5.4 | Ketik warna yang belum terdaftar di satu sel | **Sel kuning** + "belum ada Material Code" + **Daftarkan** |
| 5.5 | Klik **Daftarkan** → isi Material Code (warna & thickness terkunci) → Simpan | Sel kuning tersambung (kode tampil di bawah warna) |
| 5.6 | Ketik Material Code di sel (material sama) / kode material lain | Berubah jadi warna / ditolak dengan pesan |
| 5.7 | **+ Supplier baru** → tambah → ketik di kolom Supplier | Supplier terdaftar ditandai "terdaftar/utama", lainnya "supplier lain" |
| 5.8 | Terbitkan selagi ada sel kuning / baris tanpa supplier / supplier material INACTIVE | Checklist merah & terbit ditolak |
| 5.9 | Beres → Terbitkan | PUBLISHED; Export Excel: sel = warna + Material Code |

## 6. CBD (R5)

| # | Langkah | Hasil |
|---|---|---|
| 6.1 | Vendor CBD A → CBD → Buat (baru) | Kolom Material menampilkan Material Code varian; harga dari harga varian × supplier |
| 6.2 | Ajukan harga untuk satu varian yang dipakai CBD (belum disetujui) | Banner merah "menunggu persetujuan"; checklist terbit memblokir |
| 6.3 | MC setujui → CBD: **Refresh Harga dari Master** → isi rate, Yield, LOP, Target FOB → Terbitkan | Terbit; rekap ada baris **PO SMS (× 1,25)** bila stage SMS; tidak ada Selling price/Margin |
| 6.4 | Export Excel CBD | Baris PO SMS (rumus), tanpa blok Harga jual |
| 6.5 | MC A buka CBD | Hanya baca |

## 7. Brand

| # | Langkah | Hasil |
|---|---|---|
| 7.1 | Beranda Brand | Terbit terbaru + nama pabrik |
| 7.2 | Model List → filter **Pabrik** | Hanya model pabrik terpilih |
| 7.3 | CBD terbit → **Simulasi harga jual**: isi selling price ↔ margin | Terhitung dari Actual FOB, tanpa tombol simpan; muat ulang → kosong lagi |

## 8. Copy lintas model (R7)

| # | Langkah | Hasil |
|---|---|---|
| 8.1 | Vendor Spec A: model kedua (mis. RUNNER IN, kategori sama) + season + article | – |
| 8.2 | Specsheet RUNNER IN → Buat Revisi → **Copy dari model lain** → pilih RUNNER X | Ringkasan "Akan menyalin N baris…"; model kategori lain tidak muncul |
| 8.3 | Ganti material outsole (ketik material lain), isi warna, terbitkan | Header: "disalin dari RUNNER X · …" |
| 8.4 | Vendor CBD A → CBD article RUNNER IN → Copy → pilih article RUNNER X "(model asal)" | Yield/Loss ikut kecuali baris outsole yang diganti; rate & LOP ikut; Amortisasi/Adjustment 0; Target FOB kosong |

## 9. Silang pabrik

| # | Langkah | Hasil |
|---|---|---|
| 9.1 | Login user pabrik B (Spec/CBD/MC) | Tidak melihat material, harga, model, specsheet, CBD, pengajuan harga pabrik A |
| 9.2 | Vendor Spec B membuat model bernama sama dengan pabrik A | Boleh |

Kirim hasil per bagian (cukup "lolos" atau nomor yang gagal + pesan/screenshot), lalu export app → `exports/export_r7.json`.
