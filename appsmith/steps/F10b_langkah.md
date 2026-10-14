# F10b - Revisi dari uji end-to-end (laporan user 5 Okt 2026): langkah di Appsmith

Urutan: **1** SQL (F10b lalu **F10c**) → **2** page per page (query, JSObject, widget) → **3** Deploy → **4** uji lanjut mulai **G8**
→ **5** export `export_v11.json`.

Semua query **baru**: *Use prepared statements* **ON**, *Run behaviour* **Manual**. Jangan membuat `Query1`.
Custom Widget yang berubah: tempel ulang **ketiga tab** (HTML / Style / JavaScript) dari folder `widgets/<nama>/`.

## Ringkasan perubahan

| # | Keluhan | Perbaikan |
|---|---|---|
| 1 | Warna di specsheet tidak terbaca semua | Sel warna = kotak teks yang membungkus (tinggi mengikuti isi), kolom article lebih lebar |
| 2 | ~~Width~~ **Thickness** di specsheet (koreksi 6 Okt) | Grid BOM: kolom **Thickness** (dari master material, sebelah UoM). Excel specsheet: kolom **THICKNESS** antara UNIT OF MSRMNT dan PROCESS; MATERIAL DESCRIPTION berisi nama material saja. Kolom Width material **dibatalkan** (F10c). CBD sudah punya kolom Thickness |
| 3 | Vendor Spec tidak bisa menambah supplier | Vendor (Spec & CBD) bisa **mengusulkan** supplier → PROPOSED → Master Admin approve (muncul di Beranda admin) |
| 4 | Warna menyimpan ketikan setengah jadi ("clea") | Saran warna = daftar sendiri: ↑/↓ lalu **Enter** memilih saran; saran hanya dari revisi draft + terbit terakhir (baris aktif) |
| 5 | Remarks lebih dari satu baris (lace, inner box per size) | Remarks = kotak teks; **Shift+Enter** / **Alt+Enter** = baris baru; Enter = simpan |
| 6 | Specsheet masih bisa terbit | Diblokir bila ada **baris tanpa supplier** atau **usulan belum di-approve** (material / komponen / supplier / supplier material) |
| 7 | Paste gambar saat terbit | Modal Terbitkan (Specsheet & CBD): tempel **Ctrl+V** / pilih / seret gambar (PNG/JPG ≤ 5 MB, maks. 5); lihat di **Riwayat** |
| 8 | Override harga katalog tidak perlu | Tombol **Override…** dihapus (DB juga menolak); override tidak ikut ke revisi berikutnya |
| 9 | Loss CBD default kosong | Baris baru: Loss kosong (dihitung 0 %, tidak memblokir terbit) |
| 10 | Rate dikosongkan tetap bisa terbit | Rate boleh dikosongkan → checklist memblokir terbit |
| 11 | Revisi awal tidak bisa untuk article lain di model yang sama | Alasan tidak wajib selama article (CBD) / season (specsheet) belum punya revisi terbit |
| 12 | Tolak usulan harga: "harga NaN USD" | Ringkasan memakai angka asli dari query |
| 13 | Huruf kapital otomatis | Nama & kategori material, nama komponen, nama supplier, kode & nama model, kode article & colorway, nama komponen lokal & subkomponen BOM - data lama ikut diubah |
| 14 | Terbit GTM ditolak: "Revisi CBD SMS r0 sudah diterbitkan…" | **Bug trigger** kunci CBD (kolom generated `stage_order`) - diperbaiki |
| T46 | Keluar → muncul ganti password | `LoginCtrl.onPageLoad` = **On page load** + `LoginCtrl` baru (bila belum dikerjakan) |

---

## 1. SQL

1. DB Tools → `z_run_sql` → tempel seluruh `sql/F10b_revisi_uji.sql` → Run. Aman diulang.
   *(Sudah dijalankan 6 Okt - versi lama yang masih berisi Width; tidak perlu diulang.)*
2. **F10c** - tempel seluruh `sql/F10c_hapus_width.sql` → Run. Menghapus kolom Width material, mengembalikan
   `fn_material_add` / `fn_material_update` ke parameter lama, dan membuat ulang view yang bergantung.
   Baris terakhir menampilkan hasil cek, harus: `kolom_width 0 · fungsi_lama 0 · arg_add 7 · arg_update 9 · view_ok true`.
   Bila muncul error "Ada material yang hanya beda Width", tempel pesannya di chat.

Cek cepat F10b:
```sql
SELECT (SELECT is_nullable FROM information_schema.columns WHERE table_name = 'cbd_line' AND column_name = 'loss_pct') AS loss_boleh_kosong,
       (SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_aa_upper') AS trigger_kapital,
       to_regclass('public.change_log_attachment') IS NOT NULL AS tabel_gambar,
       (SELECT count(*) FROM supplier WHERE name <> upper(name)) AS supplier_belum_kapital;
```
Hasil: `YES · 6 · true · 0`.

---

## 2. Appsmith

### 2a. Page `Login` (T46 - lewati bila sudah)
- JSObject `LoginCtrl` → tempel `js/LoginCtrl.js`; fungsi `onPageLoad` → *Run behaviour* **On page load**.

### 2b. Page `Master Supplier`
1. **`a_supplier_insert`** - ganti seluruhnya:
   ```sql
   INSERT INTO supplier (name, status, updated_by)
   SELECT {{this.params.name}},
          CASE WHEN fn_has_perm(u.email, 'manage_master') THEN 'APPROVED' ELSE 'PROPOSED' END,
          u.email
   FROM (SELECT fn_auth_any({{appsmith.store.token}}, ARRAY['manage_master', 'propose_master']) AS email) u
   RETURNING id, status;
   ```
2. JSObject `SupplierCtrl` → tempel `js/SupplierCtrl.js`.
3. `btnSupplierTambah` → Visible `{{SupplierCtrl.canAdd()}}`.
4. `cwSupplierForm` → tempel tab JavaScript `widgets/cwSupplierForm/script.js`; Default model tambah satu baris:
   `canManage: SupplierCtrl.canManage(),`

### 2c. Page `Master Material`
1. **`a_material_add`** - **kembalikan** ke versi F3 (tanpa width; langkah lama 2c-1 dibatalkan):
   ```sql
   SELECT fn_material_add({{appsmith.store.token}}, {{this.params.code}}, {{this.params.name}},
                          {{this.params.category}}, {{this.params.thickness}}, {{this.params.uom}},
                          {{this.params.price_method}}) AS id;
   ```
   `q_materials`, `MaterialCtrl`, `cwMaterialForm` **tidak diubah** (biarkan seperti sebelum F10b).

### 2d. Page `Material Detail`
1. JSObject `MaterialDetailCtrl` → tempel `js/MaterialDetailCtrl.js` (perbaikan NaN & daftar supplier dimuat ulang).
   `a_material_update`, `q_material`, `cwMaterialForm` **tidak diubah**.

### 2e. Page `Specsheet`
   *(`q_bom_options` tidak diubah - thickness sudah ada.)*
2. **`q_season_colors`** - ganti seluruhnya (saran warna hanya dari revisi draft & terbit terakhir, baris aktif, article aktif):
   ```sql
   SELECT min(btrim(regexp_replace(bc.color, '\s+', ' ', 'g'))) AS color
   FROM bom_cell bc
   JOIN bom_line bl ON bl.id = bc.bom_line_id AND bl.is_active
   JOIN specsheet_revision sr ON sr.id = bl.revision_id
   JOIN specsheet sp ON sp.id = sr.specsheet_id
   JOIN revision_article ra ON ra.revision_id = sr.id AND ra.article_id = bc.article_id AND ra.status = 'ACTIVE'
   WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_specsheet')) IS NOT NULL
     AND sp.season = {{this.params.season || ''}} AND bc.is_used
     AND (sr.status = 'DRAFT' OR sr.id = fn_spec_latest_pub(sp.id))
   GROUP BY fn_normalize(bc.color)
   ORDER BY 1;
   ```
3. **`q_change_log`** - tambah kolom jumlah gambar: ganti `cl.category, cl.reason, cl.created_by, cl.created_at` menjadi
   `cl.category, cl.reason, cl.created_by, cl.created_at,`
   `(SELECT count(*)::int FROM change_log_attachment a WHERE a.change_log_id = cl.id) AS image_count`
4. Query baru **`q_change_log_images`** (Manual):
   ```sql
   SELECT a.id, a.file_name, a.mime_type, a.size_bytes,
          translate(encode(a.content, 'base64'), E'\n', '') AS data
   FROM change_log_attachment a
   JOIN change_log cl ON cl.id = a.change_log_id
   WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_specsheet')) IS NOT NULL
     AND cl.doc_type = 'SPECSHEET'
     AND cl.id::text = {{this.params.log_id || ''}}
   ORDER BY a.created_at;
   ```
5. Query baru **`a_change_log_attach`** - Settings → *Query timeout* **30000**:
   ```sql
   SELECT fn_change_log_attach({{appsmith.store.token}}, {{this.params.log_id}}::uuid,
                               {{this.params.file_name}}, {{this.params.data}}) AS id;
   ```
6. JSObject `SpecCtrl` → tempel `js/SpecCtrl.js`; `SpecExportCtrl` → tempel `js/SpecExportCtrl.js`.
7. `cwBomGrid` → tempel ketiga tab (`widgets/cwBomGrid/`).
8. `cwPublishForm` (di `mdlTerbit`) → tempel ketiga tab (`widgets/cwPublishForm/`); tinggi widget & `mdlTerbit` **+160 px**
   (bagian Gambar).
9. Modal `mdlRiwayat`:
   - `tblRiwayat`: kolom baru dari data `image_count`, label **Gambar**, tipe Text, Computed value
     `{{currentRow.image_count ? currentRow.image_count + ' gambar' : '-'}}`; event **onRowSelected**
     `{{SpecCtrl.showImages(tblRiwayat.selectedRow)}}`.
   - Tambah **Custom Widget `cwImageGallery`** di bawah tabel (lebar penuh, tinggi ±220 px; modal ditinggikan) -
     kode `widgets/cwImageGallery/`, Default model `{{SpecCtrl.galleryModel()}}`, event **`onDownload`**
     `{{SpecCtrl.downloadImage()}}`.

### 2f. Page `Cost Breakdown (CBD)`
1. **`q_cbd_change_log`** - ganti `cl.category, cl.reason, cl.created_by, cl.created_at` menjadi
   `cl.category, cl.reason, cl.created_by, cl.created_at,`
   `(SELECT count(*)::int FROM change_log_attachment a WHERE a.change_log_id = cl.id) AS image_count`
2. Query baru **`q_change_log_images`** (Manual) - sama dengan 2e.4, tetapi `'view_cbd'` dan `cl.doc_type = 'CBD'`.
3. Query baru **`a_change_log_attach`** - sama persis dengan 2e.5 (timeout 30000).
4. JSObject `CbdCtrl` → tempel `js/CbdCtrl.js`; `CbdGridCtrl` → tempel `js/CbdGridCtrl.js`.
5. `cwCbdGrid` → tempel tab JavaScript (`widgets/cwCbdGrid/script.js`).
6. `cwPublishForm` (di `mdlCbdTerbit`) → tempel ketiga tab; tinggi +160 px.
7. Modal `mdlCbdRiwayat`: sama dengan 2e.9 memakai `tblCbdRiwayat`, `CbdCtrl.showImages(tblCbdRiwayat.selectedRow)`,
   `CbdCtrl.galleryModel()`, `CbdCtrl.downloadImage()`.
8. (Opsional) Query `a_cbd_override_price` boleh dihapus (tidak dipanggil lagi).

### 2g. Page `Beranda`
1. **`q_worklist_proposals`** - ganti `kind IN ('MATERIAL', 'COMPONENT', 'LINK')` menjadi
   `kind IN ('SUPPLIER', 'MATERIAL', 'COMPONENT', 'LINK')`.
2. JSObject `BerandaCtrl` → tempel `js/BerandaCtrl.js`.

Lalu **Deploy**.

---

## 3. Uji lanjut mulai G8 (data uji yang sudah ada)

Aturan baru membuat GTM r0 **belum bisa terbit**: baris **8015 Cement** belum punya supplier. Langkah G8a–G8f
sekaligus menguji usulan supplier, blokir terbit, dan gambar.

| # | Akun | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|---|
| G8a | Vendor – Spec | Master Supplier → **Usulkan Supplier** `nanpao` | Tersimpan **NANPAO** (kapital), status PROPOSED; toast *Usulan supplier terkirim…* | |
| G8b | Vendor – Spec | Specsheet GTM r0 (draft) → baris 8015 Cement → Supplier **NANPAO** | Lencana **supplier usulan** di sel supplier | |
| G8c | Vendor – Spec | **Terbitkan** | Diblokir: *Tidak ada usulan yang belum di-approve* - *supplier NANPAO, supplier material MTR-… / NANPAO*; Beranda draft: lencana *Usulan belum di-approve* | |
| G8d | Master Admin | Beranda | Bagian **Supplier Menunggu Persetujuan** (NANPAO) + supplier material Cement Upper / NANPAO | |
| G8e | Master Admin | Master Supplier → NANPAO → Ubah → status APPROVED · Material Detail Cement Upper → approve NANPAO → **tambah harga IDR 2.600** | Beranda admin kosong lagi (Muat ulang) | |
| G8f | Vendor – Spec | Terbitkan GTM r0: kategori Material, alasan sesuai E2E G8, **tempel 1 screenshot (Ctrl+V)** + pilih 1 file jpg | Terbit **tanpa error** (bug #14); toast *… 2 gambar dilampirkan*; Riwayat (2) → baris GTM r0 kolom *2 gambar* → klik baris → gambar tampil, klik → besar, **Unduh** | |
| G8g | Vendor – CBD | Beranda | SPE1010566 & SPE1010567 di **CBD Terbit Perlu Revisi** (CBD SMS jadi NEEDS_REVISION - sebelumnya gagal karena bug #14) | |

Lanjutkan **H1–H13** di `steps/E2E_uji.md` dengan catatan:
- H3: baris **8015 Cement** sekarang harga **master IDR 2.600** (bukan override); Loss/Yield tetap dibawa dari SMS.
  Angka GTM yang diharapkan **tidak berubah** (material cost 192.695,51 · FOB 280.935,51).
- Tidak ada tombol **Override…** di grid (#8).
- Setelah H8, uji **R10** di bawah sebelum H11 (terbit).

### Uji keluhan lain

| # | Akun | Langkah | Hasil yang diharapkan | Hasil |
|---|---|---|---|---|
| R1 | Vendor – Spec | Buat draft GTM r1 (Revisi berikutnya) → sel warna panjang mis. `Base : White C / RIB + Deco True Red 19-1664 TPG` | Teks terbungkus, terbaca semua | |
| R2 | Vendor Spec | Specsheet ACC ILLUZION IV ELITE FG → grid BOM · Export Excel | Kolom **Thickness** tampil setelah UoM (nilai dari master material, `-` bila kosong); tidak ada kolom Width. Baris tambah: pilih material → Thickness & UoM terisi otomatis. Excel: kolom **THICKNESS** antara UNIT OF MSRMNT dan PROCESS; MATERIAL DESCRIPTION = nama material saja | |
| R4 | Vendor – Spec | Di sel warna ketik `cle` → ↓ → Enter | Tersimpan **Clear** (bukan "cle"); daftar saran hanya warna yang masih dipakai | |
| R5 | Vendor – Spec | Remarks baris Shoe Lace: `Size 37-40: 115 cm` **Shift+Enter** `Size 41-44: 120 cm` → Enter | Dua baris tersimpan; tampil dua baris di grid (draft & terbit) dan di Excel | |
| R6 | Vendor – Spec | Kosongkan supplier satu baris di draft → Terbitkan | Diblokir: *Semua baris punya supplier* | |
| R9 | Vendor – CBD | CBD baru / revisi baru: baris tanpa nilai Loss | Kolom Loss kosong; cost dihitung dengan Loss 0 | |
| R10 | Vendor – CBD | Draft CBD: kosongkan **Exchange rate** → Terbitkan | Rate tersimpan kosong; checklist *Exchange rate terisi* ✕, tombol Terbitkan hilang. Isi lagi 17.789 | |
| R11 | Vendor – CBD | (Bila ada article yang belum punya CBD terbit) buat CBD lewat **Copy dari article lain** → Terbitkan tanpa alasan | Terbit dengan *Revisi awal.* | |
| R12 | Vendor – CBD + Master Admin | Usulkan harga, lalu Master Admin **Tolak** | Ringkasan di form tolak menampilkan harga yang benar (bukan NaN) | |
| R13 | Master Admin / Vendor | Tambah material / komponen / supplier / model / article / subkomponen dengan huruf kecil | Tersimpan huruf kapital | |
| R14 | - | (G8f) | Terbit GTM berhasil, CBD lama jadi NEEDS_REVISION | |

Saran warna "clea" lama: bila masih muncul, cari asalnya (DB Tools):
```sql
SELECT sp.season, sr.stage || ' r' || sr.revision_no AS rev, sr.status, bl.is_active, a.code AS article, bc.color
FROM bom_cell bc JOIN bom_line bl ON bl.id = bc.bom_line_id
JOIN specsheet_revision sr ON sr.id = bl.revision_id JOIN specsheet sp ON sp.id = sr.specsheet_id
JOIN article a ON a.id = bc.article_id
WHERE fn_normalize(bc.color) LIKE 'clea%' ORDER BY 1, 2;
```
Kirim hasilnya bila "clea" ada di revisi **terbit** (tidak bisa diubah, akan tetap muncul sebagai saran).

---

## 4. Export

Export app → `appsmith/exports/export_v11.json`. Kirim tabel uji (✅/❌ + pesan error bila ada).
