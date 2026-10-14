# R9 - Material Code: isi otomatis + kamus kode tiga tingkat (12 Okt 2026)

Lanjut dari data yang ada (tanpa reset). Base build = `exports/build_r8.json` (app Anda setelah uji R8, tanpa perubahan -
kalau Anda sempat mengubah app setelah import R8, kirim export-nya dulu supaya build R9 saya ulang dari situ).

Contoh di bawah memakai material **HONEYLON MESH** (ME) · 44" - ganti dengan material Anda yang setara. Sebelum mulai, catat
varian yang sudah ada di material itu (Master Material → Material Detail → tab Varian), mis. `2003404W01` WHITE.

## 0. Pasang

| # | Langkah | Hasil |
|---|---|---|
| 0.1 | DB Tools → jalankan `sql/R9_kode_varian.sql` (prepared statements OFF) | `R9 terpasang` · `awalan ditolak: false · simpan varian + konfirmasi: true · usulan kode: true` |
| 0.2 | DB Tools → jalankan `sql/R_selftest.sql` | **`SELFTEST LOLOS`** |
| 0.3 | Import `exports/build_r9.json` sebagai app baru → Deploy | Modal varian (`mdlVarian`, `mdlVarianBaru`) tinggi 760 px |

## A. Isi otomatis

| # | Langkah | Hasil |
|---|---|---|
| A1 | Specsheet draft → baris HONEYLON MESH 44" → ketik warna yang **sudah punya kode di material lain** (mis. BLACK) → sel kuning → **Daftarkan** | Material Code langsung terisi lengkap (awalan HONEYLON + kode 44" + kode BLACK); kotak biru "Usulan…" menjelaskan asal tiap bagian → Simpan |
| A2 | Sama, warna **baru** (mis. NAVY) | Terisi 7 karakter, kursor di akhir, "warna baru - ketik 3 karakter terakhir" → ketik → Simpan |
| A3 | Warna yang punya >1 kode di pabrik | Terisi kode yang paling sering dipakai; "(kode lain: …)" tampil; ganti sendiri bila perlu |
| A4 | Master Material → material **baru** tanpa varian → + Varian → ketik warna & thickness | Kode kosong; kotak usulan menyebut kode thickness & warna; ketik 4 awalan + sisanya |
| A5 | Master Material → HONEYLON → + Varian → ketik warna & thickness dulu | Kode terisi seperti A1/A2; ubah kodenya → tidak ditimpa lagi walau warna diganti |
| A6 | + Varian → ketik **kode dulu** (kode yang bagian-bagiannya sudah dikenal) | Warna & thickness terisi dari arti kode (bisa diedit, tidak terkunci) |

## B. Info (kuning, tetap bisa simpan)

| # | Langkah | Hasil |
|---|---|---|
| B1 | Kode 9 karakter | "Material Code ERP biasanya 10 karakter" |
| B2 | Kode dengan awalan beda dari varian lain material ini | "Awalan … berbeda dari varian lain…" - tersimpan |
| B3 | Warna yang sudah berkode X diberi kode warna lain yang **belum dipakai** (mis. WHITE dengan W10) | "Warna WHITE biasanya berkode W01 - pastikan W10 sesuai ERP" - tersimpan |

## C. Konfirmasi (merah)

| # | Langkah | Hasil |
|---|---|---|
| C1 | Kode warna yang sudah berarti WHITE (mis. `…W01`) dipakai untuk **CREAM** | Kotak merah "Kode warna W01 sudah tercatat sebagai WHITE…"; Simpan tanpa centang → ditolak dengan pesan |
| C2 | Centang **Sudah saya cek, kode ini benar sesuai ERP** → Simpan | Tersimpan |
| C3 | Kode thickness yang sudah berarti 44" dipakai untuk thickness lain | Sama seperti C1–C2 |
| C4 | Varian C2 → ubah **status** saja | Tidak ditanya konfirmasi lagi |

## D. Tolak

| # | Langkah | Hasil |
|---|---|---|
| D1 | Material Code yang sudah dipakai varian lain | "Material Code … sudah dipakai: …" (walau dicentang) |
| D2 | Warna + thickness yang sudah ada di material itu, kode lain | "Varian … sudah ada di material ini (kode …). Bila ERP memang punya kode lain, bedakan nama warnanya…" |

Bersihkan varian uji yang tidak diperlukan (jadikan INACTIVE). Kirim hasil per bagian, lalu export app → `exports/export_r9.json`.
