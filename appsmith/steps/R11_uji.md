# R11 - Skalabilitas, bug, dan kesesuaian alur (12 Okt 2026)

Lanjut dari data yang ada (tanpa reset). Base build = `exports/export_r10.json` (= export app Anda "Product Management R9"
yang sudah berisi tempelan manual R10). Kalau Anda mengubah app setelah export itu, kirim export terbaru dulu supaya build
R11 saya ulang dari situ.

Isi R11 (rincian di `PLAN.md` §6 R11 dan §9 T54–T59, A1–A9):
- **CBD**: baris *Tanpa biaya* (alasan wajib, cost 0) · **peringatan** (tidak memblokir) untuk baris ber-Yield yang belum
  berharga; baris tanpa harga & tanpa Yield tidak didaftar ·
  **Rincian perubahan** (cost bridge) otomatis saat terbit, tersimpan di riwayat & export Excel
- **Harga**: Akhiri harga *AKAN BERLAKU* = batal, harga sebelumnya berlaku lagi · proses usulan bersamaan aman
- **Master**: nama / kategori / UoM material dan nama model dikunci bila sudah dipakai dokumen terbit
- **Specsheet**: hapus baris hasil *Ganti material* = **Batal ganti** (material lama aktif lagi)
- **Skalabilitas**: Tugas Saya Vendor CBD, daftar "belum ada harga" (2 season terakhir), daftar varian, grid CBD/BOM,
  audit log (cari 90 hari, audit ramping, ukuran di Beranda System Admin), "500 dari N" di Model List / Master Material

## 0. Pasang

| # | Langkah | Hasil |
|---|---|---|
| 0.1 | DB Tools → jalankan `sql/R11_perbaikan.sql` (prepared statements OFF) | `R11 terpasang` · `tanpa biaya: true · rincian perubahan: true · terbit CBD 5 argumen: true · index varian CBD: true` |
| 0.1b | DB Tools → jalankan `sql/R11b_harga_batal.sql` (perbaikan uji C, 13 Okt 2026) | `R11b terpasang` · `dipulihkan: N · harga dibatalkan: N · masih AKAN BERLAKU: N` (dipulihkan = harga dibatalkan yang sempat hidup lagi karena bug; di DB Anda kemungkinan 1) |
| 0.2 | DB Tools → jalankan `sql/R_selftest.sql` | **`SELFTEST LOLOS`** (166 cek, semua dibatalkan) |
| 0.3 | Import `exports/build_r11b.json` sebagai app baru → Deploy (atau: tempel `js/MaterialDetailCtrl.js` ke JSObject *MaterialDetailCtrl* di app R11 - hanya itu yang berubah dari R11) | Nama app *Product Management R11b*; modal Terbit CBD (`mdlCbdTerbit`) tinggi 900 px |

Catatan: CBD yang terbit **sebelum** R11 tidak punya rincian tersimpan (riwayatnya tetap seperti dulu). Rincian dihitung
untuk setiap terbit setelah R11 - termasuk revisi pertama setelah pemasangan (dibanding revisi terbit sebelumnya).

## A. Baris belum berharga & Tanpa biaya (A1/T56)

Keputusan 13 Okt 2026: baris belum berharga **tidak memblokir** terbit (dihitung 0). Peringatan + daftar baris hanya untuk
baris yang **sudah ada Yield** tapi belum berharga (kemungkinan lupa). Baris yang harga **dan** Yield-nya kosong
dianggap memang tanpa biaya - tidak diperingatkan / tidak didaftar.

Pakai draft CBD yang punya baris **belum berharga** (mis. material Quotation yang belum diisi, atau baris printing /
dekorasi yang harganya ikut baris lain).

| # | Langkah | Hasil |
|---|---|---|
| A1 | Buka draft dengan baris ber-Yield tanpa harga → banner kuning | "N baris sudah ada Yield tapi belum berharga - tetap bisa terbit dengan cost 0. Isi harganya bila terlupa." |
| A2 | Klik **Terbitkan** | Checklist "Baris ber-Yield sudah berharga" bertanda **!** + daftar barisnya; tombol **Terbitkan tetap muncul** (bila tidak ada pemblokir lain) |
| A2b | Baris yang harga **dan** Yield-nya kosong | Tidak ada di banner maupun daftar checklist; status bawah grid tidak menghitungnya; Cost/pr kosong (0) |
| A3 | Kolom Harga baris itu → **Tanpa biaya** → kosongkan alasan → Simpan | Ditolak "Isi alasan tanpa biaya…" |
| A4 | Isi alasan (mis. *termasuk harga baris 10*) → Simpan / Enter | Badge "tanpa biaya" + alasannya; Cost/pr 0; status bawah "… · 1 tanpa biaya"; banner hilang bila tidak ada baris lain |
| A5 | Terbitkan → checklist | Baris tadi tidak memblokir; info "1 baris tanpa biaya (cost 0)" |
| A6 | Baris lain → Tanpa biaya → **Esc** | Form tertutup, tidak tersimpan |
| A7 | Baris A4 → **Batalkan tanpa biaya** | Kembali dihitung dengan harganya (atau kembali "belum berharga") |
| A8 | Material Quotation bertanda tanpa biaya → **Ubah harga** → isi harga | Tanda tanpa biaya hilang, baris dihitung dengan harga quotation |
| A9 | Export Excel draft | Baris tanpa biaya: Cost/pr 0, kolom Asal "tanpa biaya: <alasan>" |
| A10 | Revisi CBD berikutnya dari CBD yang punya baris tanpa biaya | Tanda & alasannya ikut |

## B. Rincian perubahan (A4)

Pakai article yang sudah punya CBD **terbit**. Buat revisi berikutnya lalu ubah beberapa hal: exchange rate, Yield satu
baris, LOP, tambah baris biaya Lainnya (mis. *Assembling*).

| # | Langkah | Hasil |
|---|---|---|
| B1 | Terbitkan | Tabel **Rincian perubahan (dibanding … terbit)**: baris Exchange rate, Yield / Loss %, LOP, Lainnya - nilai Rp per baris, total = **Selisih Actual FOB (lama → baru)**; pilihan Kategori perubahan tidak tampil; "Ringkasan" opsional |
| B2 | Ganti kategori satu baris (mis. Yield → Komponen) dan ubah uraiannya | Bisa; nilai tidak bisa diubah |
| B3 | Kosongkan uraian satu baris → Terbitkan | Ditolak "Uraian rincian perubahan tidak boleh kosong." |
| B4 | Isi lagi → Terbitkan (Ringkasan kosong) | Terbit; Riwayat: kategori = kategori bernilai terbesar, alasan = ringkasan per kategori (mis. "Exchange rate +…; LOP +…") |
| B5 | Export Excel revisi terbit tadi | Di bawah change log: **Rincian perubahan dibanding …** - kategori, uraian (versi yang Anda ubah), nilai, total = selisih Actual FOB |
| B6 | Login Brand → buka CBD terbit itu → Export | Rincian yang sama ikut |
| B7 | Revisi CBD pertama sebuah article (belum ada yang terbit) → Terbitkan | Tanpa tabel rincian; pilihan kategori + alasan seperti dulu |
| B8 | Revisi yang tidak mengubah biaya apa pun → Terbitkan | Tanpa tabel rincian; kategori & alasan seperti dulu |

## C. Akhiri harga (T54)

| # | Langkah | Hasil |
|---|---|---|
| C1 | Manager Costing → Material Detail → varian berharga BERLAKU → **Tambah Harga** (berlaku mulai **bulan depan**) | Harga lama tetap BERLAKU sampai tanggal itu, harga baru AKAN BERLAKU |
| C2 | Harga AKAN BERLAKU → **Akhiri** → konfirmasi | Pesan "Harga yang akan berlaku dibatalkan - harga sebelumnya tetap berlaku."; harga lama BERLAKU lagi tanpa tanggal akhir; harga yang diakhiri **hilang dari tabel** (Tampilkan riwayat ON: *DIBATALKAN (tidak jadi berlaku)*, tanpa tombol Ajukan) |
| C2b | **Tambah Harga** → supplier yang sama | Varian itu: "Berlaku: <harga lama> sejak …" (bukan harga yang dibatalkan) |
| C2c | Tambah lagi harga dengan **tanggal mulai sama** → Akhiri lagi | Kedua harga DIBATALKAN (riwayat ON); tidak ada yang AKAN BERLAKU; harga lama BERLAKU tanpa tanggal akhir |
| C3 | Harga BERLAKU → Akhiri | "Harga diakhiri per hari ini." (seperti dulu) |

## D. Material & model dikunci setelah terbit (T57)

| # | Langkah | Hasil |
|---|---|---|
| D1 | Vendor Spec → material yang dipakai specsheet / CBD terbit → ubah **nama** / **UoM** / **kategori** → Simpan | Ditolak "Nama, kategori, dan UoM material … tidak bisa diubah: sudah dipakai di specsheet / CBD terbit…" |
| D2 | Material yang sama → ubah **status** saja | Bisa |
| D3 | Material yang belum dipakai dokumen terbit → ubah nama | Bisa |
| D4 | Model yang punya specsheet terbit → ubah **nama** | Ditolak "Nama model … tidak bisa diubah: sudah dipakai di specsheet terbit." (field lain tetap bisa) |

## E. Batal ganti material (T58)

| # | Langkah | Hasil |
|---|---|---|
| E1 | Specsheet draft → baris dengan subkomponen → **Ganti material** | Baris baru; tombol hapusnya bertuliskan **Batal ganti** (tooltip "kembali ke <material lama>") |
| E2 | Klik **Batal ganti** dua kali | Material lama kembali beserta subkomponen & warna/Material Code-nya |
| E3 | Baris yang diganti di revisi **sebelumnya** (sudah terbit) | Tombol tetap **Hapus** (hapus biasa) |

## F. Admin & Beranda (S5–S8)

| # | Langkah | Hasil |
|---|---|---|
| F1 | Admin → Audit | Teks "N catatan terbaru dalam 90 hari terakhir (maks. 200)"; dropdown entitas terisi |
| F2 | Ubah nama supplier uji → Audit → buka catatan UPDATE | *before* / *after* hanya kolom yang berubah (nama) |
| F3 | Tambah data baru → catatan INSERT | *before* & *after* kosong (isi ada di datanya sendiri) |
| F4 | Beranda System Admin | Kartu "Audit log … MB/GB" + "Batas peringatan 3 GB"; jumlah entri audit bertanda (±) |
| F5 | Beranda Vendor CBD | Kartu "material belum ada harga" hanya dari specsheet 2 season terakhir |
| F6 | Beranda | Tidak ada query `Query1` lagi |

## G. Daftar terpotong (S9)

Hanya terlihat bila data > 500 (mis. setelah bertahun-tahun): Model List / Master Material menampilkan teks oranye
"Menampilkan 500 dari N … - persempit dengan pencarian / filter." Dengan data sekarang teks itu kosong (benar).

Kirim hasil per bagian, lalu export app → `exports/export_r11.json`.
