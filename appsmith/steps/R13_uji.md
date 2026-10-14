# R13 - CBD per stage + bersih-bersih (13 Okt 2026)

Lanjut dari data yang ada (tanpa reset). Base build = `exports/export_r12.json` (= export app Anda "Product Management
R12"). Pemicu: draft CBD SMS r0 di-*Refresh dari Specsheet* setelah specsheet GTM r0 terbit → draft pindah jadi GTM r0,
CBD SMS (dan PO SMS) tidak pernah ada.

Isi R13:
- **Acuan CBD = specsheet terbit terakhir di stage CBD itu.** Draft SMS hanya perlu refresh bila ada specsheet **SMS**
  yang lebih baru (mis. SMS r1). Terbitnya GTM tidak memblokir CBD SMS, dan **Refresh tidak memindahkan stage**.
- **+ Buat CBD memilih stage** (tombol SMS / GTM / …): hanya stage yang specsheet-nya sudah terbit dan article aktif di
  sana. Default = stage terbaru.
- **Tidak boleh mundur**: setelah CBD GTM terbit, CBD SMS tidak bisa dibuat / diterbitkan lagi.
- **Satu draft per article** (tetap).
- CBD terbit terakhir yang stage-nya tertinggal → chip **PERLU CBD GTM · SMS r0** dan muncul di Tugas Saya Vendor CBD
  (*CBD Terbit Perlu Revisi*: "Specsheet sudah stage berikutnya - buat CBD-nya").
- Penandaan sinkron hanya membandingkan specsheet di stage yang sama. Data: CBD terbit yang acuannya dulu dipindah ke
  specsheet stage lain dikembalikan ke specsheet stage-nya sendiri (otomatis saat SQL dijalankan).
- **Bersih-bersih** (hasil scan app, DB & repo): `Util.fmtRp` & `Util.prettyJson` (13 page), `ModelDetailCtrl.attachments`,
  `CbdCtrl.STAGES`, dan 2 switch tersembunyi sisa F3 di Master Material (`swMaterialBelumHarga`, `swMaterialHargaPending`)
  dihapus - tidak dipakai di mana pun. Fungsi/view/kolom DB: tidak ada yang menganggur.

## 0. Pasang

| # | Langkah | Hasil |
|---|---|---|
| 0.1 | DB Tools → jalankan `sql/R13_cbd_stage.sql` (prepared statements OFF) | `R13 terpasang` · `acuan beda stage: 0` |
| 0.2 | DB Tools → jalankan `sql/R_selftest.sql` | **`SELFTEST LOLOS`** (190 cek, semua dibatalkan) |
| 0.3 | Import `exports/build_r13.json` sebagai app baru → cek datasource *Prestasi* tersambung → Deploy → nyalakan akses publik | Nama app *Product Management R13* |
| 0.4 | Rapikan tata letak (bila perlu): Master Material - bekas 2 switch tersembunyi di kanan atas filter; CBD - modal *Buat CBD* lebih tinggi (±540 px) | Tidak ada celah / scroll di modal |

Siapkan 1 model + season baru dengan **2 article** (A, B). Specsheet: buat revisi **SMS r0**, isi BOM, **Terbitkan**.

## A. Kasus semula: specsheet GTM terbit saat CBD SMS masih draft

| # | Langkah | Hasil |
|---|---|---|
| A1 | CBD → article A → **+ Buat CBD** | Modal punya baris **Stage CBD** dengan tombol **SMS** saja (terpilih); keterangan "specsheet SMS r0" |
| A2 | Buat → isi Exchange rate & Yield (jangan terbitkan) | Draft **SMS r0** |
| A3 | Specsheet → **+ Buat Revisi → Stage berikutnya** (GTM r0) → Terbitkan | - |
| A4 | Kembali ke CBD article A | Chip **DRAFT SMS r0** (tanpa "· specsheet baru"); **tidak ada** banner merah *Refresh dari Specsheet* |
| A5 | **Terbitkan…** | Checklist "Specsheet acuan = terbit terakhir di stage SMS" ✓ → terbit **SMS r0**; rekap ada baris **PO SMS** |
| A6 | Lihat chip article A & teks di bawah stepper | Chip **PERLU CBD GTM · SMS r0** (merah); teks "Specsheet sudah terbit GTM r0 - buat CBD GTM lewat "+ Buat CBD"." |
| A7 | Login Vendor CBD → Beranda | *CBD Terbit Perlu Revisi*: article A, keterangan "Specsheet sudah stage berikutnya - buat CBD-nya" |

## B. Pilih stage & tidak boleh mundur

| # | Langkah | Hasil |
|---|---|---|
| B1 | Article **B** (belum ada CBD) → **+ Buat CBD** | Tombol **SMS** dan **GTM**; **GTM** terpilih (default); keterangan "specsheet GTM r0" |
| B2 | Klik **SMS** | Keterangan & catatan acuan berganti ke "specsheet SMS r0" |
| B3 | Pilih **CBD baru dari specsheet** → Buat | Draft **SMS r0** (CBD SMS tetap bisa dibuat walau specsheet sudah GTM) |
| B4 | Article A → **+ Buat CBD** | Opsi **Revisi berikutnya: GTM r0** (GTM terpilih); klik **SMS** → judul jadi **Revisi berikutnya: SMS r1** |
| B5 | Pilih **GTM** → Buat → isi seperlunya → Terbitkan | **GTM r0** terbit; Yield dibawa dari SMS r0; chip **TERBIT GTM r0**; article A hilang dari Tugas Saya |
| B6 | Article A → **+ Buat CBD** | Tombol **SMS** nonaktif, di bawahnya "SMS: Sudah ada CBD GTM terbit"; GTM terpilih |
| B7 | Batal | - |

## C. Refresh di stage yang sama

| # | Langkah | Hasil |
|---|---|---|
| C1 | (Draft SMS r0 article B dari B3 masih ada.) Specsheet: revisi berikutnya **GTM r1**, ubah 1 baris BOM → Terbitkan | Draft SMS article B **tidak** ditandai "specsheet baru" (perubahan di GTM tidak memengaruhi CBD SMS) |
| C2 | CBD article A (GTM r0 terbit) | Chip **PERLU REVISI · GTM r0** (baris berubah di GTM r1 - sama seperti sebelum R13) |
| C3 | Article B → Terbitkan draft SMS r0 | Terbit SMS r0; chip **PERLU CBD GTM · SMS r0** |
| C4 | (Opsional, model lain yang masih di SMS) specsheet **SMS r1** terbit saat ada draft CBD SMS r0 → buka draft | Banner merah "Specsheet SMS sudah terbit SMS r1 - baris draft ini masih dari SMS r0 …" → **Refresh dari Specsheet** → tetap **SMS r0** (stage & nomor tidak berubah), acuan SMS r1 |

## D. Bersih-bersih (cek cepat)

| # | Langkah | Hasil |
|---|---|---|
| D1 | Master Material: Cari, filter, tambah material | Normal (2 switch yang dihapus memang tidak pernah tampil) |
| D2 | Model Detail → Lampiran article: lihat, unggah, hapus | Normal |
| D3 | Admin → Audit Log → klik satu baris UPDATE (fitur detail R14); halaman lain yang menampilkan tanggal & angka | Panel kanan menampilkan kolom yang berubah: nilai lama → nilai baru (uji lengkap: `steps/R14_uji.md` bagian A). Tanggal & angka di halaman lain normal |

Kirim export app setelah uji (base build berikutnya) + catatan bila ada yang tidak sesuai.
