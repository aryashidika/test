# R14: detail audit + stage Preview (13 Okt 2026)

Lanjut dari data yang ada (tanpa reset). Base build = `exports/build_r13.json` (app R13 Anda tidak diubah, hanya
di-deploy). Teks baru di app memakai bahasa Inggris; teks lama diterjemahkan di R15.

Isi R14:
- **Detail audit** (Admin, tab Audit Log): panel di kanan tabel mengikuti baris yang dipilih. Kepala: aksi, entitas,
  waktu (WIB), user, ID. Isi:
  - UPDATE: hanya kolom yang berubah, nilai lama (merah, dicoret) → nilai baru (hijau).
  - INSERT: keterangan data dibuat (audit ramping R11 tidak menyimpan isi data baru; isi tampil bila ada di audit lama).
  - DELETE: isi lengkap data yang dihapus.
  - Kolom teknis (`id`, `created_at`, `created_by`, `updated_at`, `updated_by`) disembunyikan di bawah tombol
    **Show technical fields**. UUID diringkas 8 karakter, nilai panjang dipotong (arahkan mouse = nilai lengkap).
    Password / token / hash tidak pernah dikirim ke browser.
- **T71**: kolom **Waktu** di tabel audit selama ini menampilkan jam sekarang untuk semua baris (membaca kolom yang tidak
  ada). Diperbaiki.
- **5 stage**: Pullover, Preview, SMS, GTM, Production. Kode di DB tetap pendek (`PULL`, `PREV`, `SMS`, `GTM`, `PROD`);
  data lama tidak berubah. Label baru tampil di stepper, chip, Model List / Detail, Tugas Saya, riwayat, export Excel.
- **Stage berikutnya boleh melompat**: form Buat Revisi punya pilihan **Target stage** (default stage berikutnya).
  Tidak bisa mundur atau memilih stage yang sama.
- CBD bisa dibuat di kelima stage. Preview tidak punya PO (PO hanya SMS).
- Export specsheet: form PURPOSE tetap 3 kotak; Pullover dan Preview sama-sama mencentang **Preview Sample**.

## 0. Pasang

| # | Langkah | Hasil |
|---|---|---|
| 0.1 | DB Tools → jalankan `sql/R14_audit_stage.sql` (prepared statements OFF) | `R14 terpasang` · `stages: PULL,PREV,SMS,GTM,PROD` · `labels: Pullover,Preview,SMS,GTM,Production` · `stage_order generated: 0` · `stage_order wrong: 0` |
| 0.2 | DB Tools → jalankan `sql/R_selftest.sql` | **`SELFTEST LOLOS`** (204 cek, semua dibatalkan) |
| 0.3 | Import `exports/build_r14.json` sebagai app baru → cek datasource *Prestasi* tersambung → Deploy → nyalakan akses publik | Nama app *Product Management R14* |
| 0.4 | Rapikan tata letak (bila perlu): Admin → tab Audit Log: `tblAudit` sekarang kolom 0–38, panel `cwAuditDetail` kolom 39–64 (tinggi sama dengan tabel) | Tabel & panel berdampingan, tanpa celah |

## A. Detail audit (login System Admin)

| # | Langkah | Hasil |
|---|---|---|
| A1 | Admin → tab **Audit Log** | Kolom **Waktu** berbeda per baris (bukan jam sekarang semua). Baris pertama terpilih, panel kanan langsung berisi detailnya |
| A2 | Lihat kepala panel | Badge aksi + entitas; waktu WIB **sama** dengan kolom Waktu baris itu; email user; ID lengkap |
| A3 | Master Supplier → **Ubah** satu supplier: ganti nama → Simpan. Kembali ke Audit Log → **Cari** → klik baris `UPDATE supplier` | Judul **Changed fields (n)**; `name`: nama lama (merah, dicoret) → nama baru (hijau). Kolom yang tidak diubah tidak tampil |
| A4 | Master Supplier → tambah supplier baru. Audit Log → klik baris `INSERT supplier` | **Created record** + keterangan *Record created. New records are not copied to the audit log.* |
| A5 | Specsheet → **+ Buat Revisi** (draft) → **Hapus draft**. Audit Log → klik baris `DELETE specsheet_revision` | **Deleted record** dengan isi lengkap (`stage`, `revision_no`, `status`, …); nilai kosong tampil *(empty)*; ID uuid diringkas `1a2b3c4d…` (arahkan mouse = lengkap) |
| A6 | Di baris A5 klik **Show technical fields (5)** | Muncul `created_at`, `created_by`, `id`, `updated_at`, `updated_by` (waktu dalam WIB). Klik lagi → tertutup. Pindah baris → tertutup lagi |
| A7 | Admin → tab User → **Reset password** satu user (yang sudah pernah ganti password). Audit Log → klik baris `UPDATE app_user`, lalu baris `PASSWORD_RESET` | `UPDATE`: hanya `must_change_password` false → true; **tidak ada** password / hash. `PASSWORD_RESET`: *No data recorded for this action.* |
| A8 | Klik baris yang sedang terpilih (tidak terpilih lagi) | Panel: *Select a row to see the details.* Klik baris lain → panel berganti |
| A9 | Pilih entitas di filter / ketik kata di Cari → Cari → klik baris hasil | Panel mengikuti baris hasil pencarian |

## B. 5 stage (login Vendor Specsheet / Vendor CBD)

Siapkan 1 model + season baru dengan 1 article.

| # | Langkah | Hasil |
|---|---|---|
| B1 | Specsheet → **+ Buat Revisi** → Mulai kosong | **Stage awal** berisi Pullover, Preview, SMS, GTM, Production (default Pullover) |
| B2 | Buat (Pullover) → isi BOM → Terbitkan | Stepper 5 kolom: **Pullover · Preview · SMS · GTM · Production**; chip r0 di Pullover. Info revisi "Pullover r0" |
| B3 | Model List & Model Detail | Label specsheet **Pullover r0 · PUBLISHED** |
| B4 | **+ Buat Revisi** | Opsi **Stage berikutnya: Preview r0**. Pilih opsi itu → muncul **Target stage** (Preview r0, SMS r0, GTM r0, Production r0), default Preview r0 |
| B5 | Buat (Preview) → Terbitkan | Chip r0 di kolom Preview |
| B6 | CBD → article → **+ Buat CBD** | Tombol stage **Pullover** dan **Preview** (Preview terpilih) |
| B7 | Buat (Preview) → isi Exchange rate & Yield → Terbitkan | Chip **TERBIT Preview r0**; rekap tanpa baris PO |
| B8 | Specsheet → **+ Buat Revisi → Stage berikutnya** → Target stage **GTM r0** (lompat SMS) → Buat → Terbitkan | Revisi **GTM r0**; kolom SMS di stepper kosong (–) |
| B9 | **+ Buat Revisi → Stage berikutnya** | Target stage hanya **Production r0** (tidak bisa kembali ke SMS / Preview) |
| B10 | CBD → article yang sama | Chip **PERLU CBD GTM · Preview r0**. Beranda Vendor CBD: article ada di *CBD Terbit Perlu Revisi* |
| B11 | **+ Buat CBD** | Tombol Pullover nonaktif (keterangan *Pullover: Sudah ada CBD Preview terbit*), Preview & GTM aktif, tidak ada SMS |
| B12 | Specsheet Preview r0 → **Export Excel** | PURPOSE **Preview Sample** dicentang; baris "STAGE PREVIEW · REVISI 0"; nama file berisi `Preview-r0` |
| B13 | CBD Preview r0 → **Export Excel** | Nama sheet `<article> Preview r0`; baris Season / Revisi "… · Preview r0 · PUBLISHED" |
| B14 | Buka model lama (sudah SMS / GTM) | Data sama seperti sebelumnya; label SMS / GTM tidak berubah; kolom Pullover / Preview kosong bila memang tidak ada |

Catatan: sebagian pesan error lama masih Bahasa Indonesia dan masih menyebut kode stage (mis. `PROD`); semua teks
diterjemahkan ke bahasa Inggris di R15.

Kirim export app setelah uji (base build R15) + catatan bila ada yang tidak sesuai.
