# R12 — Perbaikan pra-UAT dari review go-live (13 Okt 2026)

Lanjut dari data yang ada (tanpa reset). Base build = `exports/export_r11b.json` (= export app Anda "Product Management
R11 (1)", identik dengan `build_r11b.json`). Rincian temuan & keputusan: `PLAN.md` §9 T60–T70.

Isi R12:
- **Gambar & lampiran (T60)**: gambar Terbit > 1 MB otomatis diperkecil di browser · galeri Riwayat memuat gambar satu
  per satu · batas lampiran article & gambar change log **3,5 MB** (sebelumnya 5 MB)
- **Index harga di baris CBD (T61)**: Batal usulan / Hapus varian tetap cepat walau data bertahun-tahun (uji data 5 tahun:
  1,1 detik → 5 ms)
- **Klik cepat di Specsheet & CBD (T62)**: pemuatan model / season / article / revisi berurutan; grid hanya menampilkan
  baris revisi yang dipilih dan terkunci sebentar ("Memuat…") selama memuat
- **Sesi habis (T64)**: tombol Cari / filter dan query halaman mengarahkan ke Login
- **Bersih-bersih (T65, T66)**: tombol & fungsi *Hapus override* CBD dihapus · library ExcelJS (tidak dipakai) dilepas
- **Jam WIB (T67)**: tanggal/jam di tabel, header & export Excel selalu WIB, tidak ikut zona waktu PC
- **Keseragaman (T68)**: modal berisi form tidak tertutup bila klik di luar · kotak cari & tombol download tabel diseragamkan

Tidak dikerjakan (keputusan Anda 13 Okt 2026): T63 token login tetap tersimpan (PC tidak dipakai bersama) · T70 pengaman
DB harga tumpang tindih (nanti). Batas respons server Appsmith tidak bisa diubah (tidak ada akses server) → diatasi dari
sisi app (T60); menaikkan `APPSMITH_PLUGIN_MAX_RESPONSE_SIZE_MB` tetap disarankan ke tim IT.

## 0. Pasang

| # | Langkah | Hasil |
|---|---|---|
| 0.1 | DB Tools → jalankan `sql/R12_golive.sql` (prepared statements OFF) | `R12 terpasang`. Bila ada pesan *Info: N lampiran article dan N gambar change log berukuran > 3,5 MB* → catat, buka file itu sekali di uji A |
| 0.2 | DB Tools → jalankan `sql/R_selftest.sql` | **`SELFTEST LOLOS`** (171 cek, semua dibatalkan) |
| 0.3 | Import `exports/build_r12.json` sebagai app baru → cek datasource *Prestasi* tersambung → Deploy → nyalakan akses publik | Nama app *Product Management R12*; panel **Libraries** kosong (ExcelJS sudah dilepas) |

## A. Gambar & lampiran (T60)

| # | Langkah | Hasil |
|---|---|---|
| A1 | Specsheet → draft → **Terbitkan** → tempel (Ctrl+V) 1 screenshot layar penuh + pilih 1 foto HP (> 3 MB) | Keduanya muncul sebagai thumbnail; arahkan mouse → nama `.jpg` dan ukuran ± 200–1.500 KB (foto & screenshot besar diperkecil) |
| A2 | Tempel 1 screenshot kecil (mis. potongan tabel) | Tetap `.png`, ukuran tidak berubah |
| A3 | Pilih file > 20 MB atau file bukan gambar yang di-rename `.png` | Ditolak: "… lebih dari 20 MB." / "… tidak bisa dibaca sebagai gambar."; thumbnail tidak bertambah |
| A4 | Terbitkan dengan 5 gambar | "Revisi … diterbitkan. 5 gambar dilampirkan." |
| A5 | **Riwayat** → klik baris terbit tadi | "Memuat gambar…" lalu gambar muncul **satu per satu**; klik gambar → perbesar; **Unduh** berfungsi |
| A6 | Saat gambar masih dimuat, klik baris riwayat lain | Galeri pindah ke baris itu (gambar baris lama tidak ikut tampil) |
| A7 | Ulangi A1–A6 di **CBD** (Terbitkan CBD & Riwayat CBD) | Sama |
| A8 | Model Detail → Lampiran → unggah PDF/gambar **3–3,5 MB** → **Lihat** / unduh | Tersimpan & bisa dibuka |
| A9 | Unggah file > 3,5 MB | Ditolak: "Ukuran file … MB, maksimal 3,5 MB." |
| A10 | (Bila 0.1 menyebut file lama > 3,5 MB) buka file itu | Bila gagal dimuat → unggah ulang versi yang lebih kecil, lalu hapus yang lama |

## B. Klik cepat di Specsheet & CBD (T62)

| # | Langkah | Hasil |
|---|---|---|
| B1 | CBD → season dengan ≥ 2 article yang punya draft → klik chip article A lalu **langsung** chip B (cepat, 2–3 kali bolak-balik) | Akhirnya: chip B terpilih, stepper menampilkan revisi **B**, judul di bawah stepper = article B, grid = baris B |
| B2 | Selama memuat (sesaat setelah klik) | Grid sebentar menampilkan "Memuat…" / tidak bisa diedit; setelah selesai bisa diedit lagi |
| B3 | Ketik Yield di draft, lalu langsung klik revisi terbit di stepper | Grid menampilkan revisi terbit (read-only); kembali ke draft → Yield tadi tersimpan |
| B4 | Specsheet → klik cepat bolak-balik antar revisi di stepper | Grid selalu sesuai revisi yang tersorot; draft bisa diedit, revisi terbit tidak |
| B5 | Specsheet → **+ Buat Revisi** / **Terbitkan** / **Hapus Draft** seperti biasa | Setelah selesai, stepper & grid memuat ulang ke revisi yang benar (sama dengan sebelum R12) |
| B6 | CBD → **+ Buat CBD**, **Refresh dari Specsheet**, **Terbitkan**, **Hapus Draft** | Sama dengan sebelum R12; chip article ikut berubah status |

## C. Sesi habis (T64)

Cara cepat memaksa sesi habis: buka app di 2 tab (login sekali), lalu di tab ke-2 klik **Keluar** — sesi di DB dihapus,
tab pertama masih menampilkan halaman tetapi sesinya sudah tidak berlaku. (Atau: System Admin **Reset password** user itu.)

| # | Langkah (di tab pertama) | Hasil |
|---|---|---|
| C1 | Master Supplier → **Cari** | Pesan "Sesi login habis. Silakan login lagi." → pindah ke Login |
| C2 | Ulangi untuk Master Komponen / Material / Pilihan (ganti Jenis), Model List (Cari / ganti Pabrik), Admin (Cari audit) | Sama |
| C3 | Login lagi → semua tombol Cari bekerja normal | Daftar termuat seperti biasa |

## D. Lain-lain (T65–T68)

| # | Langkah | Hasil |
|---|---|---|
| D1 | CBD → kolom Harga baris material katalog | Tidak ada tombol *Hapus override* |
| D2 | Export Excel Specsheet & CBD | File terunduh normal (tanpa ExcelJS); tanggal di header = tanggal WIB |
| D3 | Ubah zona waktu Windows sementara ke UTC → buka Admin (audit), Material Detail (harga), Riwayat | Jam tetap WIB (sama dengan sebelum zona diubah); tanggal *Berlaku dari* tidak bergeser. Kembalikan zona waktu |
| D4 | Buka modal form (Tambah User, Pabrik, Supplier, Komponen, Material, Supplier material, **Tolak harga**, Pilihan, Season, Article) → ketik sesuatu → klik di luar modal | Modal **tidak** tertutup, isian tetap ada; tutup lewat Batal / ✕ |
| D5 | Model List | Tidak ada kotak cari bawaan tabel (pakai kotak Cari di atas); Riwayat CBD punya kotak cari seperti Riwayat Specsheet; tabel Lampiran tanpa tombol download tabel |

## Checklist go-live (bukan uji fitur)

1. Setelah import: akses publik app **ON**; app **DB Tools** tetap privat.
2. DB produksi: jangan sediakan / jalankan `RESET_data_*.sql` dan `R_selftest.sql` setelah go-live.
3. Datasource memakai user DB khusus app ini (bukan superuser / owner tabel `master_store*`).
4. Backup `pg_dump` harian + uji restore sekali.
5. Minimal **2 akun System Admin**.
6. Sarankan ke tim IT: `APPSMITH_PLUGIN_MAX_RESPONSE_SIZE_MB` dinaikkan (mis. 20) di server Appsmith.

Kirim export app setelah uji (base build berikutnya) + daftar langkah yang gagal.
