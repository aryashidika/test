# R8 — Uji lanjutan dari data E2E-R (12 Okt 2026)

**Tanpa reset**: memakai data yang sudah ada dari E2E-R (`steps/E2E_R_uji.md`): PABRIK A & B, user per role, material
**MESH** + varian, model **RUNNER X** & **RUNNER IN** (FH26), CBD article RUNNER X & RUNNER IN. Nama di bawah mengikuti
panduan E2E-R; kalau di data Anda namanya lain, pakai yang setara.

Base build = `exports/export_r7.json` (app Anda setelah E2E-R + perbaikan manual). SQL R8 sudah saya jalankan di
PostgreSQL 16 lokal (2× tanpa error, self-test 102 cek lolos, 137 query lolos EXPLAIN).

## 0. Pasang

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| 0.1 | **Jangan ubah app** sampai build di-import | – |
| 0.2 | DB Tools → jalankan `sql/R8_catatan_uji.sql` (Use prepared statements = OFF). **Jangan** jalankan RESET | Baris terakhir `R8 terpasang` · `MC manage_price: true · auto-approve: true · batas 5 article masih ada: false · awalan kode: true · ajukan dari CBD: true` |
| 0.3 | DB Tools → jalankan `sql/R_selftest.sql` | **`SELFTEST LOLOS`** (data uji dibatalkan otomatis, data Anda tidak tersentuh) |
| 0.4 | Import `exports/build_r8.json` sebagai **app baru** → datasource `Prestasi` → **Deploy** | 13 page; page CBD punya query baru `a_cbd_price_propose` |
| 0.5 | Editor, page CBD: modal `mdlCbdHarga` (sekarang ada isian tanggal, tinggi 520 px) | Tombol Simpan tidak terpotong |
| 0.6 | Siapkan CBD **draft**: Vendor CBD A → CBD article **RUNNER IN** (dari uji 8.4). Kalau sudah terbit → **Buat CBD** revisi berikutnya | Ada 1 CBD draft untuk bagian 5 |

## 1. Manager Costing — harga langsung berlaku (material MESH)

| # | Langkah | Hasil |
|---|---|---|
| 1.1 | Login **MC A** → Master Material → **MESH** → tab Harga | Tombol **+ Tambah Harga** (dulu: tidak ada tombol Ajukan untuk MC) & **Salin Harga** |
| 1.2 | + Tambah Harga → supplier MESH, centang 1 varian yang masih **BELUM ADA HARGA** (atau yang berharga, berlaku besok) → harga, klik IDR → **Simpan** | Pesan "… disimpan dan langsung berlaku"; baris **BERLAKU** / AKAN BERLAKU, bukan MENUNGGU APPROVAL |
| 1.3 | Salin Harga dari varian berharga ke 1 varian lain → **Simpan salinan** | Langsung BERLAKU |
| 1.4 | Beranda MC & page Persetujuan Harga | Harga 1.2–1.3 **tidak** muncul sebagai usulan |
| 1.5 | Login **Vendor CBD A** → MESH → + Ajukan Harga untuk 1 varian | Tetap **MENUNGGU APPROVAL** (biarkan untuk bagian 2) |
| 1.6 | Login **MC B** → material pabrik A | Tidak terlihat (pemisahan pabrik tetap) |

## 2. Riwayat harga (MESH)

| # | Langkah | Hasil |
|---|---|---|
| 2.1 | MC A **tolak** usulan 1.5 (alasan bebas) | Baris DITOLAK tampil (switch *Tampilkan riwayat* OFF) |
| 2.2 | Vendor CBD A ajukan lagi varian + supplier yang sama → MC A setujui | Switch OFF: baris DITOLAK **hilang**; ON: muncul lagi. Beranda Vendor CBD: kartu Usulan Ditolak untuk varian itu juga hilang |
| 2.3 | Penolakan lama dari uji E2E-R 4.4 (varian yang belum diajukan ulang) | Masih tampil (switch OFF) — hilang otomatis setelah 30 hari |

## 3. Article tanpa batas (RUNNER X · FH26)

| # | Langkah | Hasil |
|---|---|---|
| 3.1 | Vendor Spec A → Model Detail RUNNER X → season FH26 (sudah 3 article) → tambah article sampai **6** | Tersimpan; tombol **+ Article (6)**, teks "6 article di season FH26" tanpa "maks. 5" |
| 3.2 | Specsheet RUNNER X FH26 → Buat Revisi (revisi berikutnya) | Article baru bisa ditambahkan ke revisi; grid BOM 6 kolom article; **Export Excel** 6 kolom |
| 3.3 | Hapus Draft revisi itu (bila tidak ingin dilanjutkan) & hapus article tambahan yang belum dipakai | Bisa dihapus |

## 4. Awalan Material Code (MESH)

| # | Langkah | Hasil |
|---|---|---|
| 4.1 | Vendor Spec A → MESH → + Varian dengan Material Code yang **4 karakter depannya beda** dari varian MESH lain (warna baru) | Kotak kuning "Awalan … berbeda … harus berawalan sama" dan **Simpan ditolak** |
| 4.2 | Specsheet draft (dari 3.2) baris MESH → ketik warna baru → sel kuning → **Daftarkan** → kode dengan awalan beda | Ditolak juga |
| 4.3 | Ulangi dengan awalan sama | Tersimpan; sel kuning tersambung |
| 4.4 | Ubah **status** varian MESH lama (INACTIVE lalu ACTIVE lagi) tanpa mengubah kode | Tetap bisa |

## 5. Ajukan harga master dari CBD (CBD draft RUNNER IN dari 0.6)

| # | Langkah | Hasil |
|---|---|---|
| 5.1 | Vendor CBD A → CBD draft → kolom Harga | Tautan **Ajukan harga master** di baris katalog yang punya Material Code + supplier; **tidak ada** di baris quotation / tanpa supplier / sedang menunggu |
| 5.2 | Klik di baris MESH → modal **Ajukan Harga Master**: lihat "Harga master berlaku sekarang", isi harga baru, currency, berlaku mulai, referensi → **Ajukan** | Pesan "Usulan harga master dikirim…"; banner merah *menunggu persetujuan*; baris "harga master menunggu…"; checklist Terbitkan memblokir |
| 5.3 | MC A → Persetujuan Harga: usulan itu ada → setujui. Material Detail MESH tab Harga | Harga baru BERLAKU (atau AKAN BERLAKU) |
| 5.4 | Vendor CBD A → CBD draft → **Refresh Harga dari Master** | Harga baris MESH = harga baru (sumber *master*) |
| 5.5 | Login **MC A** → buka CBD draft yang sama → baris lain → **Harga master baru** → Simpan | Langsung berlaku; pesan minta Vendor CBD klik Refresh Harga |
| 5.6 | Vendor CBD A → baris **quotation** → **Isi harga** → simpan | Tersimpan tanpa error (bug `q is not defined` sudah diperbaiki) |
| 5.7 | Vendor CBD B → CBD pabrik A | Tidak terlihat |

## 6. Regresi singkat (perbaikan manual sebelumnya)

| # | Langkah | Hasil |
|---|---|---|
| 6.1 | Specsheet draft (3.2): ketik warna cepat pindah-pindah sel → tunggu "Menyimpan…" hilang → refresh | Semua warna tetap |
| 6.2 | CBD draft: isi Yield/Loss % beberapa baris dengan Enter, ubah Exchange rate → refresh | Semua nilai tetap |

Kirim hasil per bagian (cukup "lolos" atau nomor yang gagal + pesannya), lalu export app → `exports/export_r8.json`.
