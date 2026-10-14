# R1 - Fondasi: pabrik, role baru, matriks izin

File: `sql/R1_fondasi.sql`, `exports/build_r1.json` (salinan `export_v11.json` yang diedit), alat build di `tools/`.

> **Penting:** sejak `export_v11` dijadikan base, app lama jangan diubah dulu. Kalau sempat ada perubahan di app setelah 6 Okt 2026, kirim export terbaru - saya ulang build dari situ.

## 1. Database (DB Tools)
1. Jalankan **`sql/RESET_data_uji.sql`** - ⚠️ menghapus semua data uji & user selain System Admin (sudah disetujui).
2. Jalankan **`sql/R1_fondasi.sql`**. Hasil akhir harus 5 baris cek:
   | cek | hasil |
   |---|---|
   | role_permission | 32 |
   | role tanpa Master Admin | BRAND_VIEWER, MANAGER_COSTING, SYSTEM_ADMIN, VENDOR_CBD, VENDOR_SPEC |
   | kolom app_user.factory_id | 1 |
   | tabel factory | factory |
   | fn_price_approve pakai approve_price | true |

## 2. Import app
1. Workspace → **Create new → Import** → pilih `exports/build_r1.json`. Nama app: **Product Management R1**.
2. Bila diminta, hubungkan datasource **Prestasi** (sama seperti app lama).
3. Pastikan app **publik** (Share → Make application public), lalu **Deploy**.
4. App lama biarkan dulu; diarsipkan setelah uji di bawah lolos.

## 3. Yang berubah di app
| Page | Perubahan |
|---|---|
| Admin | Tab baru **Pabrik** (tabel + `+ Tambah Pabrik`, modal `mdlPabrik` / `cwFactoryForm`); form user punya pilihan **Pabrik** (muncul untuk Vendor Spec, Vendor CBD, Manager Costing); role **Master Admin** hilang, **Manager Costing** ada; kolom **Pabrik** di tabel user |
| Semua page | Header menampilkan role + pabrik (mis. *Vendor - Specsheet · PABRIK A*) |
| Beranda | Manager Costing melihat antrian **usulan harga** |
| Material Detail | Approve / Tolak / Akhiri harga hanya Manager Costing; Batalkan usulan = Vendor CBD |
| Specsheet / CBD | T49–T52: query gambar CBD Manual, titik di `onRowSelected` dihapus, kolom Gambar teks, modal Terbit lebih tinggi |

Belum berubah (fase berikut): pemisahan data per pabrik (R2+), material varian (R2), harga baru (R3). Di R1 semua user masih melihat semua data.

**Rapikan di UI bila perlu:** posisi tabel di tab Pabrik dan tinggi `mdlUser` / `mdlPabrik` (sudah disesuaikan, cek saja tidak terpotong).

## 4. Uji
| # | Langkah | Harapan |
|---|---|---|
| A1 | System Admin → Admin → tab **Pabrik** → tambah `pabrik a`, `Pabrik B` | Tersimpan sebagai **PABRIK A**, **PABRIK B** |
| A2 | Tambah pabrik `pabrik  a` lagi | Ditolak: *Pabrik "PABRIK A" sudah ada.* |
| A3 | Tambah user Vendor Spec tanpa memilih pabrik | Form menolak: *Pilih pabrik untuk role ini.* |
| A4 | Tambah user: Vendor Spec A, Vendor CBD A, Manager Costing A (PABRIK A), Vendor Spec B (PABRIK B), Brand Viewer | Pilihan Pabrik **tidak muncul** untuk Brand Viewer; kolom Pabrik terisi di tabel |
| A5 | Ubah PABRIK A → INACTIVE | Ditolak: masih punya user aktif |
| A6 | Login Vendor Spec A | Header *Vendor - Specsheet · PABRIK A* |
| A7 | Vendor Spec A tambah supplier, komponen, material, supplier material | Langsung **APPROVED** (tanpa usulan) |
| A8 | Login Vendor CBD A → Master Material | Tidak bisa menambah material/supplier |
| A9 | Vendor CBD A → Material Detail → tambah harga | Status **MENUNGGU APPROVAL**; tombol Approve/Tolak/Akhiri **tidak ada**, Batalkan ada |
| A10 | Login Manager Costing A → Beranda | Antrian usulan harga tampil; klik → Material Detail |
| A11 | Manager Costing → Approve harga, lalu **Akhiri** | Berhasil; Manager Costing tidak punya tombol tambah harga |
| A12 | System Admin ubah pabrik Vendor Spec B → PABRIK A | Sesi Vendor Spec B langsung habis (harus login ulang) |
| A13 | Specsheet / CBD: buka page CBD, Terbitkan, Riwayat | Tidak ada error saat page dibuka; modal Terbit tidak terpotong; kolom Gambar berisi "2 gambar" / "-" |

## 5. Kirim balik
Export app R1 → simpan sebagai `exports/export_r1.json`, kirim hasil uji A1–A13 (dan baris cek SQL).
