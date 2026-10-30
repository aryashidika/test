# R21: kamus kode ERP per pabrik + halaman Code Dictionary

Isi R21 (rencana disetujui 30 Okt 2026, PLAN §6 R21):
1. **Kamus kode ERP di database** (pabrik UNIMITRA): 7.001 awalan material, 1.298 kode Dimension, 13.070 kode warna (baris MASUK
   dari review 29 Okt 2026). Satu kode = satu arti. Satu teks boleh punya beberapa kode (data ERP, mis. `BEECH` = `B3B` dan `B5G`).
   Kode yang sudah dipakai varian app memakai **teks varian app** (kamus mengikuti app). Varian, material, dan dokumen tidak diubah.
2. **Kamus dipakai untuk membaca kode** (kode -> arti) di Register / + Variant, susun kode otomatis, dan Use kode purchasing:
   - kode yang artinya beda dengan kamus ditolak, pesannya menyebut arti kamus, mis. `Color code B01 means BLACK (ERP dictionary), not WHITE.`
   - form Register mengisi Dimension / warna dari kamus: `Code W01 = WHITE (recorded in ERP dictionary).`
   - sel kuning tersusun otomatis juga dari kamus, **hanya bila teks itu punya tepat satu kode di kamus** (lebih dari satu = tetap Register)
   - arah arti -> kode tetap dari varian app (aturan R20), jadi kode ERP kembar yang sah tidak ditolak
3. **Register menambah kamus**: kode dengan bagian baru (awalan / kode Dimension / kode warna yang belum ada) otomatis masuk kamus
   dengan Source **Register**.
4. **Halaman Code Dictionary** = sub menu Master Material (revisi Anda 30 Okt 2026): tombol **Code Dictionary** di Master Material, tidak ada di menu samping / Home, seperti Material Detail. Baca saja, untuk Vendor Spec, Vendor CBD,
   Manager Costing. Brand tidak bisa membuka. Satu jenis kamus per pencarian, paling banyak **200 baris**; lebih dari itu tampil
   `Showing 200 of N codes. Narrow down with search.` Kamus utuh tidak pernah dikirim ke browser.
5. **Perbaikan Dimension `NO.1`**: dulu tersimpan `NO0.1`, sekarang tetap `NO.1` (DB, grid specsheet, form varian).

> Build dibuat dari `exports/build_r20.json` (export R20 dari Anda belum ada). Kalau Anda sempat mengubah app setelah import
> R20, kirim export-nya dulu supaya build dibuat ulang dari situ.

> **Kinerja (diukur di PostgreSQL lokal dengan kamus penuh):** query halaman Code Dictionary 25-50 ms untuk semua filter; cek aturan
> kode varian lebih cepat dari R20 (index baru per bagian kode); susun kode otomatis sama dengan R20; tiap file isi kamus < 1 detik.

Beri tanda di kolom **OK?** (v / x). Kalau ada yang beda, kirim tangkapan layar dan teks pesannya.

## 0. Pasang

Semua SQL lewat DB Tools → `z_run_sql` (prepared statements OFF), satu file per Run, urutan seperti tabel.

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 0.1 | Tempel isi `sql/R21_kamus.sql` → Run | Tanpa error | |
| 0.2 | Tempel isi `sql/R21_kamus_isi_1.sql` → Run. Ulangi untuk `_isi_2` sampai `_isi_6` (enam file, masing-masing 25-150 KB) | Tanpa error, tiap Run < 2 detik | |
| 0.3 | Jalankan query **K1** (bagian 1) | material **7001**, dimension **1298**, warna **13070**, register 0 | |
| 0.4 | Jalankan `sql/R_selftest.sql` (sudah diperbarui untuk R21) | **`SELFTEST LOLOS`** | |
| 0.5 | Import `exports/build_r21.json` (timpa app), lalu Deploy | Nama app `Product Management R21`; menu samping **tidak** ada Code Dictionary; Master Material ada tombol **Code Dictionary** di sebelah Search | |
| 0.6 | Page **Code Dictionary** → query `q_dict` **Run behaviour Manual**; **Auth** → `onPageLoad` **Run on page load ON** | Manual, ON | |

> **Sudah menjalankan versi pertama (30 Okt 2026) dan self-test gagal di `R16 kutip pintar ...`?** Penyebab: versi pertama
> `R21_kamus.sql` berisi karakter kutip miring asli, yang berubah jadi kutip biasa saat ditempel ke DB Tools. Versi sekarang
> hanya ASCII. Cukup: tempel lagi `sql/R21_kamus.sql` yang baru → Run, lalu jalankan **K4** dan `sql/R_selftest.sql` lagi.
> Data kamus dan varian tidak perlu diulang.

Menjalankan ulang file 0.1 atau 0.2 aman (kode yang sudah ada dilewati). Pesan `factory UNIMITRA not found` = nama pabrik di DB
berbeda: kirim nama pabriknya, file tidak mengubah apa pun.

## 1. Cek data (DB Tools, hanya membaca)

| # | Query | Yang diharapkan | OK? |
|---|---|---|---|
| 1.1 | **K1** jumlah kamus | Lihat 0.3. Kolom `tersambung` (awalan yang tersambung ke material app) sekitar 288: 284 material bervarian + 4 material tanpa varian yang namanya sama dengan ADF | |
| 1.2 | **K2** varian app yang melanggar aturan kode (sekarang dengan kamus) | **0 baris**. Ada baris? Kirim hasilnya, jangan diubah dulu | |
| 1.3 | **K3** Dimension yang sudah terlanjur tersimpan `NO0.1` | Kemungkinan 0 baris. Ada baris? Kirim hasilnya; perbaikan ditulis setelah itu | |
| 1.4 | **K4** tanda `±` di kamus dan kutip miring | `25 · 1 · 44" · (0.8 MM±0.1) X 54"`. Beda? Kirim hasilnya | |

### K1. Jumlah kamus

```sql
SELECT 'material' AS kamus, count(*) AS jumlah, count(material_id) AS tersambung,
       count(*) FILTER (WHERE source = 'REGISTER') AS register FROM code_dict_material
UNION ALL
SELECT 'dimension', count(*), NULL, count(*) FILTER (WHERE source = 'REGISTER') FROM code_dict_dimension
UNION ALL
SELECT 'warna', count(*), NULL, count(*) FILTER (WHERE source = 'REGISTER') FROM code_dict_color;
```

### K2. Varian yang melanggar aturan kode

```sql
SELECT v.code, m.name AS material, v.thickness AS dimension, v.color,
       array_to_string(fn_variant_code_problems(v.factory_id, v.material_id, v.code, v.color, v.thickness, v.id), ' ') AS masalah
FROM material_variant v JOIN material m ON m.id = v.material_id
WHERE length(v.code) = 10
  AND cardinality(fn_variant_code_problems(v.factory_id, v.material_id, v.code, v.color, v.thickness, v.id)) > 0
ORDER BY v.code;
```

### K4. Tanda `±` dan kutip miring

```sql
SELECT (SELECT count(*) FROM code_dict_material WHERE name LIKE '%' || chr(177) || '%') AS material_pm,
       (SELECT count(*) FROM code_dict_dimension WHERE thickness LIKE '%' || chr(177) || '%') AS dimension_pm,
       fn_clean_thickness('44' || chr(8221)) AS kutip_miring,
       (SELECT thickness FROM code_dict_dimension WHERE code = '519') AS contoh_519;
```

### K3. Dimension `NO0.1` (bug lama)

```sql
SELECT 'varian' AS tempat, v.code AS kode, v.thickness AS dimension, NULL AS status
FROM material_variant v WHERE v.thickness ~ '[A-Z]0\.[0-9]'
UNION ALL
SELECT 'baris specsheet', pm.name, l.thickness, r.status
FROM bom_line l JOIN specsheet_revision r ON r.id = l.revision_id
JOIN specsheet s ON s.id = r.specsheet_id JOIN product_model pm ON pm.id = s.model_id
WHERE l.is_active AND l.thickness ~ '[A-Z]0\.[0-9]'
ORDER BY 1, 2;
```

## 2. Halaman Code Dictionary

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 2.1 | Login **Vendor Spec** → Master Material | Tombol **Code Dictionary** di sebelah Search | |
| 2.2 | Isi cari Master Material (mis. `canvas`) → Search, lalu klik **Code Dictionary** | Halaman Code Dictionary: tombol **← Master Material**, jenis `Material prefix (first 4)`, kotak cari, Search. Tabel 200 baris urut kode, teks oranye `Showing 200 of 7,001 codes. Narrow down with search.` Terbuka secepat halaman master lain | |
| 2.3 | Klik **← Master Material** | Kembali ke Master Material, pencarian `canvas` dan hasilnya masih ada | |
| 2.4 | Buka lagi Code Dictionary. Ketik nama material app yang sudah punya varian (sebagian nama) → Enter | Baris awalan material itu; kolom **App material** = nama di app, **App variants** = jumlah varian, **Meaning** = nama ERP (bisa beda tulisan) | |
| 2.5 | Ganti jenis ke `Color code (last 3)` | Tabel langsung berganti ke kode warna (tanpa klik Search) | |
| 2.6 | Ketik `W01` → Enter | Baris `W01` · `WHITE` · Source `ERP`, App variants sesuai pemakaian | |
| 2.7 | Ketik `white` → klik **Search** | Semua warna yang memuat WHITE (kode dan teks), batas 200 + teks oranye bila lebih | |
| 2.8 | Jenis `Dimension code (middle 3)`, cari `none` | Kode tanpa dimension tampil `(None)` (mis. `800`, `K00`, `C00`) | |
| 2.9 | Tidak ada filter Source / Usage, tidak ada tombol tambah / ubah / hapus | Benar, baca saja | |
| 2.10 | Login **Brand** → Master Material | Tombol Code Dictionary **tidak ada**. Menu samping dan Home juga tidak punya Code Dictionary | |
| 2.11 | Login **Vendor CBD** / **Manager Costing** → Master Material → **Code Dictionary** | Bisa membuka (baca saja) | |

## 3. Kode memakai kamus (Vendor Spec)

Material uji baru: `UJI R21 KAIN` dan `UJI R21 KAIN SALAH` (kategori apa saja, UoM `ME`). Awalan uji `R21X` tidak ada di ERP.
Contoh kamus yang dipakai: `312` = `2 MM X 44"`, `W01` = `WHITE`, `B01` = `BLACK`, `60B` = `1.5 MM`, `A09` = `ACORN`,
`BEECH` = `B3B` dan `B5G` (dua kode), `G40` = `ALL GUM`. Kalau di app Anda `1.5 MM` atau `ACORN` sudah dipakai varian dengan kode
lain, 3.3 hasilnya bisa beda: jalankan query **H1** untuk contoh pengganti.

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 3.1 | Master Material → buat `UJI R21 KAIN` → **+ Variant** → ketik kode `R21X312W01` (Dimension dan Color belum diisi) | Dimension terisi `2 MM X 44"` dengan catatan `Code 312 = 2 MM X 44" (recorded in ERP dictionary).`; Color terisi `WHITE`, `Code W01 = WHITE (recorded in ERP dictionary).` → Save tersimpan | |
| 3.2 | **+ Variant** lagi → kode `R21X312B01`, Color ketik `WHITE` | Kotak merah memuat `Color code B01 means BLACK (ERP dictionary), not WHITE.`; Save ditolak | |
| 3.3 | Specsheet draft → baris tambah `UJI R21 KAIN` · Dimension `1.5 MM`. Sel article 1 ketik `acorn` | Sel **putih**, kode **`R21X60BA09`** tanpa Register (awalan dari varian 3.1, `60B` dan `A09` dari kamus, masing-masing satu-satunya kode) | |
| 3.4 | Sel article 2 baris itu ketik `beech` | **Kuning** (BEECH punya dua kode di kamus) | |
| 3.5 | Sel kuning 3.4 → **Register** → ketik `R21X60BB3B` | Dimension / Color terbaca dari kamus (`recorded in ERP dictionary`), tanpa kotak merah → Save, sel putih. (`R21X60BB5G` juga sah) | |
| 3.6 | Sel article 1 ganti ke `UJI R21 PELANGI` (kuning) → **Register** → kode `R21X60BZZ9` → Save | Tersimpan. Master Material → Code Dictionary → Color code → cari `ZZ9`: `UJI R21 PELANGI` · Source **Register** · Added by = email Anda | |
| 3.7 | Baris tambah `UJI R21 KAIN SALAH` · `(None)`, sel article 1 `UJI X` (kuning) → **Register** → ketik `R21X60BG40` | Tombol **Use R21X60BG40 (UJI R21 KAIN · 1.5 MM · ALL GUM) in the specsheet** (material dari awalan, dimension dan warna dari kamus). Jangan diklik, tutup modal | |
| 3.8 | Baris tambah `UJI R21 KAIN` dengan Dimension ketik `no.1` | Dimension baris tampil **`NO.1`** (bukan `NO0.1`) | |
| 3.9 | Buka revisi yang **sudah terbit** | Tidak berubah | |

### H1. Contoh pengganti untuk 3.3 (hanya membaca)

Dimension dan warna yang punya tepat satu kode di kamus dan belum dipakai varian app:

```sql
(SELECT 'dimension' AS jenis, d.code, d.thickness AS arti
FROM code_dict_dimension d
WHERE d.factory_id = fn_r21_import_factory() AND d.thickness ~ '^[0-9.]+ MM$'
  AND NOT EXISTS (SELECT 1 FROM code_dict_dimension x WHERE x.factory_id = d.factory_id AND x.thickness_key = d.thickness_key
                     AND x.code <> d.code)
  AND NOT EXISTS (SELECT 1 FROM material_variant v WHERE v.factory_id = d.factory_id AND v.thickness_key = d.thickness_key)
LIMIT 10)
UNION ALL
(SELECT 'warna', d.code, d.color
FROM code_dict_color d
WHERE d.factory_id = fn_r21_import_factory() AND d.color ~ '^[A-Z]+$'
  AND NOT EXISTS (SELECT 1 FROM code_dict_color x WHERE x.factory_id = d.factory_id AND x.color_key = d.color_key AND x.code <> d.code)
  AND NOT EXISTS (SELECT 1 FROM material_variant v WHERE v.factory_id = d.factory_id AND v.color_key = d.color_key)
LIMIT 10)
ORDER BY 1, 3;
```

## 4. Cek cepat yang tidak berubah

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 4.1 | Register / + Variant untuk material lama dengan kode yang sudah biasa dipakai | Sama seperti R20; catatan bisa berbunyi `recorded in ERP dictionary` | |
| 4.2 | Use kode yang sudah terdaftar (R20 bagian 5) | Sama seperti R20 | |
| 4.3 | Master Material, Specsheet, CBD dibuka | Kecepatan sama seperti sebelumnya | |

## 5. Bersih-bersih data uji (opsional)

Varian dan material `UJI R21 ...` bisa di-INACTIVE atau dihapus lewat aplikasi. Baris kamus yang ditambah Register uji (`ZZ9`,
awalan `R21X`) tetap ada setelah varian dihapus (aturan: kode di kamus tidak hilang). Kalau ingin dihapus juga:

```sql
DELETE FROM code_dict_color WHERE code = 'ZZ9' AND source = 'REGISTER';
DELETE FROM code_dict_material WHERE code = 'R21X' AND source = 'REGISTER';
```
