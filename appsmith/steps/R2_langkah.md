# R2 - Master tanpa approval, Material Induk + Varian, Master Pilihan

> **Revisi R2b (8 Okt 2026)** setelah melihat `MATERIAL CODE.xlsx`: varian ditambah **satu per satu** seperti ERP (Material Code, warna, thickness teks), tanpa kombinasi. Bila R2 sudah terpasang: jalankan **`sql/R2b_varian.sql`** lalu import **`exports/build_r2b.json`** (salinan `export_r2a.json` = R2 yang sudah Anda rapikan). Uji B5–B8 di bawah sudah versi R2b.

File: `sql/RESET_data_bisnis.sql`, `sql/R2_master.sql`, `sql/R2b_varian.sql`, `exports/build_r2b.json` (`tools/build_r2.py` → `tools/build_r2b.py`).

> Sejak `export_r1.json` dijadikan base, app R1 jangan diubah lagi. Kalau terlanjur ada perubahan, kirim export terbaru - build diulang dari situ.

## 1. Database (DB Tools)
1. Jalankan **`sql/RESET_data_bisnis.sql`** - ⚠️ menghapus data master & dokumen uji R1 (supplier, komponen, material, harga, model, specsheet, CBD, audit). **User, password, dan pabrik tetap ada.**
2. Jalankan **`sql/R2_master.sql`**. Hasil akhir 7 baris cek:
   | cek | hasil |
   |---|---|
   | status supplier/komponen/material/link | `CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'INACTIVE'::text])))` |
   | izin lama (harus 0) | 0 |
   | kolom supplier_material_code (harus 0) | 0 |
   | kolom material.factory_id | 1 |
   | tabel material_variant | material_variant |
   | pilihan GENDER / UKURAN | 3 / 13 |
   | uji nama mirip | majujaya |
3. Jalankan **`sql/R2b_varian.sql`** (varian uji yang sudah ada tetap disimpan; thickness angka jadi teks, mis. `1.2MM`). Hasil 5 baris cek:
   | cek | hasil |
   |---|---|
   | kolom thickness (teks) | text |
   | kolom thickness_mm (harus 0) | 0 |
   | fn_variant_save | 1 |
   | fn_variant_add (harus 0) | 0 |
   | uji thickness "." | (kosong) |

## 2. Import app
1. Workspace → **Create new → Import** → `exports/build_r2b.json`. Nama app: **Product Management R2b**.
2. Hubungkan datasource **Prestasi** bila diminta → **Share → Make application public** → **Deploy**.
3. App R1 / R2 lama dibiarkan dulu; diarsipkan setelah uji di bawah lolos.

## 3. Yang berubah
| Page | Perubahan |
|---|---|
| Master Supplier / Komponen | Status hanya **ACTIVE / INACTIVE**, tombol Approve & teks "usulan" hilang. Saat mengetik nama muncul **daftar nama mirip** (abaikan PT/CV/Tbk, titik, spasi). Ubah nama / INACTIVE dicek ke pemakaian di dokumen (terbit / draft) |
| Master Material | Daftar **material induk** (nama, kategori, UoM) milik pabrik Anda; kolom **Pabrik** dan **Varian**. Cari juga per Material Code. Form tambah tanpa kode/thickness; setelah simpan langsung ke Material Detail |
| Material Detail | Tab **Varian**: kolom Material Code · Warna · Thickness; form **satu baris** (Material Code, warna, thickness teks ERP) + **Simpan & tambah lagi**. Ketik kode 10 karakter → thickness (3 tengah) & warna (3 akhir) terisi dan terkunci bila bagian kodenya sudah tercatat di pabrik; awalan (4 depan) beda dari varian lain = peringatan saja. Tab **Supplier** tanpa "Kode di supplier". **Harga disembunyikan** sampai R3. Label UoM → **Mea (UoM)** |
| **Master Pilihan** (page baru) | Pilih jenis → tabel + form: Kategori, Construction, Gender, Ukuran (bersama), **Last, Outsole mold (per pabrik)** |
| Beranda | Kartu "usulan master" hilang (Vendor Spec & Manager Costing) |
| Admin / CBD | T53: `q_factories` & `q_change_log_images` dikunci *Manual* (di R1 kembali *Automatic* setelah import) |

**Belum bisa dipakai (masa transisi):** Specsheet & CBD untuk material baru (R4/R5), harga material (R3), dropdown model (R4). Jangan uji page itu di R2.

**Rapikan di UI bila perlu:** tinggi `mdlVarian` (sekarang 560 px, lebar sama dengan modal lain). Catatan: `mdlSupplier` 314 px & `mdlKomponen` 464 px (hasil rapikan Anda) - bila daftar nama mirip muncul, form bisa perlu di-scroll; tinggikan ±120 px bila mengganggu.

## 4. Uji
Pakai user R1: Vendor Spec A, Vendor CBD A, Manager Costing A (PABRIK A), Vendor Spec B (PABRIK B), Brand Viewer.

| # | Langkah | Harapan |
|---|---|---|
| B1 | Vendor Spec A → Master Supplier → tambah `PT. Maju Jaya` | Tersimpan **ACTIVE**, tanpa tombol Approve |
| B2 | Tambah supplier, ketik `maju jaya cv` | Muncul *Supplier dengan nama mirip sudah ada: PT. MAJU JAYA*; tetap bisa disimpan |
| B3 | Master Komponen → tambah `10 Vamp`, lalu ketik `vamp lining` | Daftar mirip menampilkan VAMP (No. 10) |
| B4 | Master Material → tambah *MESH* / `Merry Mesh (HASI 052)` / Mea `ME` | Tersimpan (huruf besar), Material Detail langsung terbuka di tab **Varian** |
| B5 | Tambah Varian: `205Q404A52` · `APPLE CINNAMON (17-1045 TPG)` · `44"` → **Simpan & tambah lagi** | Tersimpan; modal tetap terbuka, form kosong, pesan *Varian 205Q404A52 tersimpan* |
| B6 | Lanjut ketik kode `205Q404A57` | Thickness langsung terisi `44"` dan terkunci (*Kode 404 = 44"…*); warna diketik `ASPARAGUS (12-0104 TPG)` → Simpan |
| B7 | Tambah varian `205Q404W01` · `WHITE`; lalu buat material lain `Honeylon Mesh` / `ME` dan ketik kode `2003404W01` | Di material kedua thickness `44"` **dan** warna `WHITE` langsung terisi & terkunci (kode 404 dan W01 sudah tercatat di pabrik ini) |
| B8 | (a) Tambah `205Q404X99` dengan warna `APPLE CINNAMON (17-1045 TPG)` (warna + thickness sama dengan 205Q404A52); (b) kode `205Q404A52` lagi; (c) di material lain ketik `205Q...` dengan awalan beda dari varian di sana; (d) thickness `.`; (e) ubah satu varian → INACTIVE | (a) ditolak *Varian … sudah ada di material ini (kode 205Q404A52)*; (b) ditolak *Material Code … sudah dipakai*; (c) muncul peringatan awalan kuning, tetap bisa disimpan; (d) tersimpan sebagai *tanpa thickness*; (e) kolom Varian di Master Material menulis "1 INACTIVE" |
| B9 | Tab **Supplier** → tambah PT. MAJU JAYA (centang supplier utama) | Tidak ada field "Kode di supplier"; status ACTIVE |
| B10 | Tambah material `merry mesh (hasi 052)` / `ME` lagi; lalu dengan Mea `YD` | Pertama ditolak (sudah ada di pabrik ini); kedua boleh |
| B11 | Login **Vendor Spec B** → Master Material | Material pabrik A **tidak terlihat**; boleh membuat `Merry Mesh (HASI 052)` / `ME` dan memakai kode `205Q404A52` (kode unik per pabrik; thickness/warna pabrik A tidak ikut terisi) |
| B12 | Login **Vendor CBD A** → Master Material → Material Detail → Ubah Material | Tidak ada tombol tambah material/varian/supplier; di form hanya **Metode harga** yang bisa diubah |
| B13 | Vendor Spec A → **Master Pilihan**: Kategori `Running`, Construction `Cementing`, Last `L-100`, Ukuran `40.5` lalu `48` | `40.5` ditolak; lainnya tersimpan; Gender sudah berisi 3 pilihan, Ukuran 35–47 |
| B14 | Vendor Spec B → Master Pilihan → jenis **Last** | `L-100` (pabrik A) **tidak** terlihat; Kategori `RUNNING` terlihat (bersama) |
| B15 | **Brand Viewer** → Master Material & Master Pilihan | Melihat material semua pabrik (kolom Pabrik); tidak ada tombol tambah |
| B16 | Beranda: Vendor Spec A & Manager Costing A | Tidak ada kartu/angka "usulan master"; Manager Costing hanya *Harga Menunggu Approval* (kosong) |
| B17 | Di editor app: query `q_factories` (Admin) & `q_change_log_images` (CBD) | *Run behaviour* tetap **Manual** |

## 5. Kirim balik
Export app R2b → simpan sebagai `exports/export_r2.json`, kirim hasil uji B1–B17 + baris cek SQL (R2 & R2b).
