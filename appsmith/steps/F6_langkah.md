# F6 - Specsheet: checklist & terbit: langkah di Appsmith

Urutan: **1** SQL → **2** query → **3** JSObject → **4** widget → **5** uji → **6** export `export_v6.json`.

Setelan untuk **semua query baru** (datasource `Prestasi`): *Use prepared statements* **ON**, *Run behaviour* **Manual**
(⚠️ termasuk query **baca** `q_publish_checklist` & `q_change_log` - jangan dibiarkan *Automatic*, lihat T22/T28).
Jangan membuat query uji (`Query1`) di app ini - pakai DB Tools (T21).

Aturan terbit (= Python `publish_checklist` / `publish_revision`):
- **Penolak** (Terbitkan tidak bisa): tidak ada article aktif · ada article aktif yang tidak dipakai di baris mana pun
  (tidak ada warna) · ada baris dengan material **INACTIVE**.
- **Peringatan** (boleh terbit): baris tanpa supplier (harga CBD-nya nanti tidak bisa diambil).
- **Kategori** wajib. **Alasan** wajib, kecuali revisi awal (r0 **Mulai kosong**) → kosong = *Revisi awal.*
- Setelah terbit revisi terkunci (trigger F5). Penandaan CBD *perlu revisi* ditambahkan di F8.

Penyederhanaan (bisa diubah kalau tidak setuju):
- **Riwayat** dibuka lewat tombol **Riwayat (n)** → modal berisi tabel semua terbit season ini, bukan tab
  (grid BOM tidak perlu dipindah ke dalam Tabs). Change log revisi yang sedang dibuka juga tampil di `txtRevisi`.
- Pilihan kategori specsheet: Material, Komponen, Treatment/proses, Lainnya. EX_RATE / LOP / AMORTIZATION / YIELD
  dipakai CBD (F8) - DB tetap menerima semuanya.

---

## 1. SQL

1. DB Tools → `z_run_sql` → tempel seluruh `sql/F6_publish.sql` → Run.
2. Cek cepat:
   ```sql
   SELECT (SELECT count(*) FROM change_log) AS log, (SELECT count(*) FROM v_revision_checklist) AS revisi;
   ```
   Hasil `0 | <jumlah revisi>` tanpa error.

Catatan: revisi yang di-terbitkan lewat DB Tools saat uji F5 (`published_by = 'uji'`) **tidak punya change log**, jadi
tidak muncul di Riwayat. Boleh dibiarkan, atau mulai uji F6 dengan model/season baru.

---

## 2. Query (page `Specsheet`)

**`q_publish_checklist`** (baca - Manual; dijalankan `SpecCtrl.openPublish()`)
```sql
SELECT *
FROM v_revision_checklist
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'edit_specsheet')) IS NOT NULL
  AND revision_id::text = {{this.params.revision_id || ''}};
```

**`q_change_log`** (baca - Manual; dijalankan `SpecCtrl.loadSeason()`; semua terbit season ini, terbaru dulu)
```sql
SELECT cl.id, cl.revision_id, r.stage || ' r' || r.revision_no AS revision_label,
       CASE WHEN src.id IS NULL THEN NULL
            WHEN src.specsheet_id = r.specsheet_id THEN src.stage || ' r' || src.revision_no
            ELSE srcsp.season || ' ' || src.stage || ' r' || src.revision_no END AS source_label,
       cl.category, cl.reason, cl.created_by, cl.created_at
FROM change_log cl
JOIN specsheet_revision r ON r.id = cl.revision_id
LEFT JOIN specsheet_revision src ON src.id = r.source_revision_id
LEFT JOIN specsheet srcsp ON srcsp.id = src.specsheet_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_specsheet')) IS NOT NULL
  AND cl.doc_type = 'SPECSHEET'
  AND r.specsheet_id::text = {{this.params.specsheet_id || ''}}
ORDER BY cl.created_at DESC;
```

**`a_revision_publish`** (tulis - *Request confirmation* **OFF**: modal Terbitkan sudah menjadi konfirmasi)
```sql
SELECT fn_revision_publish({{appsmith.store.token}}, {{this.params.revision_id}}::uuid,
                           {{this.params.category}}, {{this.params.reason}}) AS id;
```

---

## 3. JSObject

- `SpecCtrl` → tempel ulang seluruh `js/SpecCtrl.js`. Yang baru: `CATEGORIES`, `changeLogs()`, `logFor()`,
  `openPublish()`, `publishFormModel()`, `publish()`, `historyLabel()`, `openHistory()`; `loadSeason()` ikut
  menjalankan `q_change_log`; `revisionText()` menampilkan change log revisi terbit.
- `Auth`, `BomCtrl`: tidak berubah.

---

## 4. Widget

### 4a. Baris revisi (`txtRevisi` … `btnHapusDraft`)

Perkecil `txtRevisi` supaya muat 3 tombol di kanannya (urutan kiri → kanan):

| Widget | Setelan |
|---|---|
| `txtRevisi` | Lebar ±kolom 0–44 · *Height* **Auto height** (teks bisa 2 baris: info revisi + change log) |
| `btnRiwayat` *(baru)* | Button, style **secondary** · Label: `{{SpecCtrl.historyLabel()}}` · Visible: `{{!!SpecCtrl.seasonId}}` · onClick: `{{SpecCtrl.openHistory()}}` |
| `btnTerbitkan` *(baru)* | Button, style **primary** · Label: `Terbitkan…` · Visible: `{{SpecCtrl.editable()}}` · onClick: `{{SpecCtrl.openPublish()}}` |
| `btnHapusDraft` | Tetap (Visible `{{SpecCtrl.editable()}}`) |

### 4b. Modal `mdlTerbit` - Custom Widget `cwPublishForm`

Modal lebar ±560 px, *close on outside click* **OFF**. Di dalamnya Custom Widget **`cwPublishForm`** tinggi ±520 px
(kode `widgets/cwPublishForm/`: tab HTML / Style / JavaScript).

| Default model | `onPublish` | `onCancel` |
|---|---|---|
| `{{SpecCtrl.publishFormModel()}}` | `{{SpecCtrl.publish()}}` | `{{closeModal('mdlTerbit')}}` |

### 4c. Modal `mdlRiwayat`

Modal lebar ±900 px.

| Widget | Setelan |
|---|---|
| `txtRiwayatJudul` | Text: `{{'Riwayat terbit - ' + ((SpecCtrl.season() || {}).season || '')}}`, bold 16 |
| `tblRiwayat` | Table data: `{{SpecCtrl.changeLogs()}}` · Search, filter, download **OFF** · kolom di bawah |
| `btnRiwayatTutup` | `Tutup`, style secondary · onClick: `{{closeModal('mdlRiwayat')}}` |

Kolom `tblRiwayat` (sembunyikan `id`, `revision_id`):

| Kolom | Label | Setelan |
|---|---|---|
| `revision_label` | Revisi | bold |
| `source_label` | Sumber | – |
| `category` | Kategori | – |
| `reason` | Alasan | *Cell wrapping* **ON**, lebar terbesar |
| `created_by` | Oleh | – |
| `created_at` | Waktu | Column type **Text** · Computed value `{{Util.fmtDateTime(currentRow.created_at)}}` |

Lalu **Deploy**.

---

## 5. Uji

Akun: **Vendor – Specsheet** (menerbitkan), **Master Admin**, **Brand Viewer**. Siapkan model baru, mis. `ILZ-02`,
season `SS27` dengan 2 article (`A1`, `A2`), dan material APPROVED `MTR-X` **tanpa supplier** (khusus uji;
nanti sementara dijadikan INACTIVE).

### A. Checklist (Vendor – Specsheet)

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| A1 | Specsheet `ILZ-02` / `SS27` → **+ Buat Revisi** → Mulai kosong, PULL | Draft `PULL r0`; tombol **Terbitkan…**, **Hapus Draft**, **Riwayat** (tanpa angka) tampil |
| A2 | Tanpa baris BOM → **Terbitkan…** | Checklist: ✓ *Minimal satu article aktif (2 article aktif)*, ✕ *Setiap article aktif dipakai… Belum dipakai: A1, A2*, ✓ INACTIVE, ✓ supplier; teks merah *Perbaiki 1 hal…*; **tidak ada** kategori/alasan/tombol Terbitkan → **Batal** |
| A3 | Tambah baris `10` material `MTR-X` **tanpa supplier**, warna A1 = `Black` (A2 kosong) → **Terbitkan…** | ✕ *Belum dipakai: A2*; ⚠ oranye *1 baris tanpa supplier - boleh terbit…* |
| A4 | Isi warna A2 = `White` → **Terbitkan…** | Semua ✓ kecuali ⚠ supplier; form tampil: kategori **Lainnya** sudah terpilih, alasan tanpa tanda * dengan catatan *Opsional untuk revisi awal.* → **Batal** |
| A5 | Master Admin: Master Material → `MTR-X` → status **INACTIVE**. Vendor Spec: **Terbitkan…** | ✕ *Tidak ada material INACTIVE - MTR-X - …*; form tersembunyi → Batal. Master Admin: kembalikan `MTR-X` ke **APPROVED** |
| A6 | Drop A1 dan A2 (✕ → Drop? di header) → **Terbitkan…** | ✕ *Minimal satu article aktif (0 article aktif)* → Batal. **Masukkan ke Revisi** A1 & A2 lagi |

### B. Terbit revisi awal

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| B1 | **Terbitkan…** → kosongkan alasan, kategori Lainnya → **Terbitkan** | Modal tertutup, toast *Revisi PULL r0 diterbitkan.*; chip `r0` biru; `txtRevisi` *PUBLISHED · terbit … oleh <email Anda>* dan baris *Perubahan (OTHER): Revisi awal.*; grid hanya baca; **Terbitkan…** & **Hapus Draft** hilang; **+ Buat Revisi** tampil; tombol **Riwayat (1)** |
| B2 | **Riwayat (1)** | 1 baris: `PULL r0`, sumber kosong, `OTHER`, *Revisi awal.*, email Anda, waktu sekarang (WIB) |
| B3 | Model List (filter `SS27`) / Model Detail `ILZ-02` | Specsheet `PULL r0 · PUBLISHED · 2 article aktif`; article *AKTIF · PULL r0 terbit* (hijau) |

### C. Revisi berikutnya - alasan wajib

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| C1 | **+ Buat Revisi** → Revisi berikutnya `PULL r1` → ganti warna A1 baris 10 → **Terbitkan…** | Kategori **belum** terpilih; alasan bertanda * |
| C2 | **Terbitkan** tanpa memilih kategori | Pesan merah di modal *Pilih kategori perubahan.* |
| C3 | Pilih **Material**, alasan kosong → **Terbitkan** | *Alasan perubahan wajib diisi untuk revisi ini.* |
| C4 | Alasan `Ganti warna A1` → **Terbitkan** | Toast; `txtRevisi` *Perubahan (MATERIAL): Ganti warna A1*; **Riwayat (2)**: `PULL r1` di atas dengan sumber `PULL r0` |
| C5 | **+ Buat Revisi** → Stage berikutnya `SMS r0` → **Terbitkan…** | Alasan **wajib** (bukan revisi awal karena ada sumber) → isi → terbit; Riwayat (3) |
| C6 | Klik chip `PULL r0` di stepper | `txtRevisi` menampilkan change log r0 (*Revisi awal.*) |

### D. Role lain

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| D1 | Brand Viewer → Specsheet `ILZ-02` / `SS27` | Hanya revisi terbit; **Riwayat (3)** bisa dibuka; tidak ada **Terbitkan…** |
| D2 | Master Admin → Specsheet | Bisa melihat draft (kalau ada) tetapi tidak ada **Terbitkan…** / **Hapus Draft** |

### E. Penjagaan DB (DB Tools)

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| E1 | `SELECT fn_revision_publish('salah', gen_random_uuid(), 'OTHER', 'x');` | Error *SESI_HABIS…* |
| E2 | Dua tab browser (Vendor Spec), draft baru `SMS r1` dengan semua checklist ✓. Tab 1: buka **Terbitkan…** (biarkan terbuka). Tab 2: kosongkan semua warna A2. Tab 1: isi kategori & alasan → **Terbitkan** | Ditolak di modal: *Article A2 belum memakai baris BOM mana pun…* (DB menghitung ulang checklist). Lalu isi lagi warna A2 dan terbitkan |
| E3 | Cek audit & log: | Baris `UPDATE` `specsheet_revision` dengan `after_data ->> 'status' = 'PUBLISHED'` untuk setiap terbit; jumlah `change_log` = jumlah terbit di F6 |

```sql
SELECT a.created_at, a.user_email, a.entity_id, a.before_data ->> 'status' AS dari, a.after_data ->> 'status' AS ke
FROM audit_log a
WHERE a.entity = 'specsheet_revision' AND a.action = 'UPDATE'
ORDER BY a.created_at DESC LIMIT 10;

SELECT doc_type, category, reason, created_by, created_at FROM change_log ORDER BY created_at DESC;
```

---

## 6. Export & cek skema

1. Export app → simpan sebagai `appsmith/exports/export_v6.json`.
2. Jalankan query cek skema (`PLAN.md` §8) di DB Tools, tempel hasilnya ke chat - harus ada `change_log`
   (table), `v_revision_checklist` (view), `fn_revision_publish` (function).
3. Kirim juga hasil uji (A–E), termasuk yang gagal.
