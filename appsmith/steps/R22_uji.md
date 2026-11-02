# R22: kamus ERP jadi sumber pilihan + kode terbentuk otomatis

Isi R22 (rencana disetujui 31 Okt 2026, PLAN §6 R22). Alur kerja Anda tidak berubah; yang berubah di belakang layar:
1. **Satu teks = satu kode** di kamus (material, Dimension, warna). Kode kembar dibuang dari kamus; yang dipertahankan: kode yang
   dipakai varian app terbanyak, lalu (material) yang sudah tersambung, lalu kode terkecil (= baris pertama Excel ERP).
   Dimension `(None)` tetap boleh beberapa kode (kode kosong per material, aturan R20 bagian 3). Varian, harga, dokumen tidak diubah.
2. **Dropdown specsheet** (grid): Material, Dimension, dan warna juga menawarkan isi kamus ERP (tanpa daftar penuh: dicari ke
   server saat mengetik, paling banyak 8 baris, di bawah judul **ERP dictionary**). Material kamus yang belum ada di app: dipilih
   → form **+ New material** terbuka sendiri dengan nama terisi; Anda isi Kategori dan UoM.
3. **Kode terbentuk otomatis** bila material + Dimension + warna ketiganya ada di kamus (atau varian app): tanpa Register.
   Salah satu belum ada → sel kuning, Register seperti biasa (bagian baru masuk kamus).
4. **Aturan baru**: teks yang sudah punya kode di kamus tidak boleh didaftarkan dengan kode lain, mis.
   `Color BLACK has code BLK in the ERP dictionary, not B01.`
5. **Master Material**: material baru dengan nama sama dengan nama kamus otomatis memakai awalan kamus itu.
6. Halaman **Code Dictionary** dan tombolnya dihapus dari UI (tabel kamus tetap di database).

Beri tanda di kolom **OK?** (v / x). Kalau ada yang beda, kirim tangkapan layar dan teks pesannya.

## 0. Pasang

Semua SQL lewat DB Tools → `z_run_sql` (prepared statements OFF), satu file per Run.

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 0.1 | Tempel isi `sql/R22_kamus.sql` → Run | Tanpa error; pesan `R22: kode kembar dibuang dari kamus: material ..., Dimension ..., warna ...` | |
| 0.2 | Jalankan `sql/CEK_R22_kode_tidak_sesuai.sql` | Daftar varian yang kodenya bukan kode kamus (varian tidak diubah). Hasil Anda 31 Okt 2026: 14 varian CARTON BOX SPECS (awalan 6717) dan INNER BOX SPECS (awalan 661O), karena di ERP awalan itu bernama `...NEWDESIGN` sedangkan nama app menggabung desain lama (6715 / 6613) dan baru; wajar, tidak perlu tindakan | |
| 0.3 | Jalankan `sql/R_selftest.sql` (sudah diperbarui untuk R22) | **`SELFTEST LOLOS`** | |
| 0.4 | Import `exports/build_r22.json` (timpa app), lalu Deploy | Nama app `Product Management R22`; Master Material **tidak** ada tombol Code Dictionary | |

## 1. Dropdown di Specsheet (draft)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 1.1 | Kolom **Material** baris tambah: ketik 3-4 huruf nama material ERP yang belum ada di app | Di bawah daftar material app muncul judul **ERP dictionary** dengan paling banyak 4 nama, keterangan `code XXXX · not in app yet` | |
| 1.2 | Pilih salah satu, lalu Enter / klik Add | Form **+ New material** terbuka, nama terisi; isi Kategori + UoM → Save; baris lanjut otomatis dengan material itu | |
| 1.3 | Master Material | Material tadi ada, awalan kamusnya tersambung (Material Detail: kode awalan sama dengan kamus) | |
| 1.4 | Kolom **Dimension**: ketik sebagian teks Dimension ERP yang belum dipakai material itu | Judul **ERP dictionary** dengan teks kamus; pilih = langsung tersimpan | |
| 1.5 | Sel **warna**: ketik sebagian nama warna ERP | Judul **ERP dictionary** dengan warna kamus; pilih → Enter | |
| 1.6 | Material (dengan awalan kamus) + Dimension kamus + warna kamus: ketiganya terisi | Sel **tidak kuning**, kode 10 digit terbentuk sendiri (lihat kode di sel / Material Detail) | |
| 1.7 | Ketik teks yang tidak ada di kamus | Tidak ada judul ERP dictionary; alur lama (+ New material / sel kuning) | |

## 2. Aturan satu teks satu kode

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 2.1 | Register sel kuning dengan warna yang sudah ada di kamus tetapi kode akhir lain | Ditolak: `Color X has code YYY in the ERP dictionary, not ZZZ.` | |
| 2.2 | Register dengan Dimension baru (belum ada di kamus) + kode tengah baru | Tersimpan; teks + kode itu muncul di saran berikutnya | |
| 2.3 | Master Material → + Add: nama = nama material kamus yang belum ada di app | Tersimpan; di Specsheet material itu langsung punya awalan kamus | |

## 3. Harga dan data lama

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 3.1 | Buka specsheet / CBD yang sudah ada | Kode, harga, dan approval sama seperti sebelum R22 | |
| 3.2 | Material baru dari kamus → Master Material → tambah supplier + harga seperti biasa | Harga bisa diisi untuk varian yang terbentuk otomatis | |
