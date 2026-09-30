# F8 — CBD: harga, rekap, refresh, terbit, sinkron: langkah di Appsmith

Urutan: **1** SQL → **2** page CBD (JSObject, query, widget, modal) → **3** Specsheet (kecil) → **4** uji →
**5** export `export_v8.json`.

Setelan untuk **semua query baru** (datasource `Prestasi`): *Use prepared statements* **ON**, *Run behaviour* **Manual**
(⚠️ termasuk **3 query baca** baru `q_cbd_recap`, `q_cbd_checklist`, `q_cbd_change_log` — jangan dibiarkan
*Automatic*, lihat T22/T28). Jangan membuat query uji (`Query1`) di app ini — pakai DB Tools (T21/T34).
Modal baru disalin dari pola lama boleh, tapi **event handler selalu ditempel dari panduan ini** (jangan membawa
handler page lain).

Aturan F8 (= Python `cbd_service.py` / `cbd_calc.py`):
- **Harga** (hanya draft, baris ACTIVE):
  - material **Quotation** → harga quotation diisi di CBD (**Isi harga**); kosong = baris tidak dihargai terpisah (cost 0);
    referensi opsional.
  - material **katalog** → harga master (hanya APPROVED, F3b) atau **Override…** khusus baris ini (alasan wajib);
    **Hapus override** → kembali ke harga master. Harga untuk semua CBD (termasuk harga khusus warna) diisi di Master
    Material, bukan override.
  - Currency **IDR/USD wajib diklik setiap input** (tanpa nilai awal).
- **Harga master berubah** (harga baru / diganti / diakhiri / harga warna / metode harga berubah) → baris ditandai, banner
  **Refresh Harga dari Master** menyamakan semua (override tidak ikut).
- **Refresh dari Specsheet**: draft yang specsheet acuannya sudah terbit revisi baru → baris dibangun ulang dari specsheet
  terbit terakhir; Yield / Loss % / harga input dibawa; baris yang hilang → MISSING_IN_SPEC. Stage ikut specsheet.
- **Rekap** (Rupiah): Material cost = Σ cost/pair baris ACTIVE (belum lengkap = 0) · Actual FOB = material cost +
  amortisasi + adjustment · Selisih = Actual FOB − Target FOB (**OVER** / **UNDER** / **SESUAI**) · Margin % =
  (Selling price − Actual FOB) / Selling price × 100 · isi Margin % → Selling price = Actual FOB / (1 − m/100).
- **Terbit** ditolak bila: specsheet acuan bukan terbit terakhir · exchange rate kosong · ada harga master berubah ·
  ada baris berharga tanpa Yield. Baris tanpa harga = peringatan (cost 0). Kategori wajib; alasan wajib kecuali
  revisi awal (r0 tanpa sumber → *Revisi awal.*). Setelah terbit revisi terkunci.
- **Sinkron**: saat specsheet terbit, CBD terbit terakhir tiap article aktif dibandingkan (baris, supplier, warna)
  dengan specsheet acuannya: sama → tetap **IN_SYNC** (acuan dipindah ke revisi baru); beda → **NEEDS_REVISION**
  (chip merah *PERLU REVISI*).

Penyederhanaan (bisa diubah kalau tidak setuju):
- **Riwayat** CBD = tombol **Riwayat (n)** + modal (sama dengan Specsheet F6), bukan tab.
- Harga quotation diisi lewat modal (bukan input langsung di sel seperti Python) supaya currency bisa wajib diklik.
- Sinkron dibandingkan dengan **acuan CBD itu sendiri** (Python: dengan specsheet terbit sebelumnya) — CBD yang sudah
  *perlu revisi* tidak kembali *sinkron* tanpa sebab (P5).

---

## 1. SQL

1. DB Tools → `z_run_sql` → tempel seluruh `sql/F8_cbd_price.sql` → Run.
2. Cek cepat:
   ```sql
   SELECT (SELECT count(*) FROM v_cbd_recap) AS recap, (SELECT count(*) FROM v_cbd_checklist) AS checklist,
          (SELECT count(*) FROM v_cbd_price_check) AS price_check, (SELECT count(*) FROM cbd_revision) AS cbd;
   ```
   Hasil `recap = checklist = cbd`, tanpa error.

---

## 2. Page `Cost Breakdown (CBD)`

### 2a. JSObject
- `CbdCtrl` → tempel ulang seluruh `js/CbdCtrl.js`. Baru: `CATEGORIES`, `changeLogs()`, `logFor()`, `canPublish()`,
  `openPublish()`, `publishFormModel()`, `publish()`, `historyLabel()`, `openHistory()`; `loadArticle()` ikut
  menjalankan `q_cbd_change_log`; `revisionText()` menampilkan *perlu revisi* & change log.
- `CbdGridCtrl` → tempel ulang seluruh `js/CbdGridCtrl.js`. Baru: `recap()`, `banners()`, `exec()`, aksi rekap / harga /
  refresh di `onAction()`, `openPrice()`, `priceFormModel()`, `savePrice()`.
- `Auth`, `Util`: tidak berubah.

### 2b. Query baca (semua **Manual**)

**`q_cbd_lines`** — ganti seluruhnya (tambah kolom cek harga dari `v_cbd_price_check`):
```sql
SELECT g.*, coalesce(pc.master_stale, false) AS master_stale, pc.price_gap, pc.other_colors,
       pc.master_price, pc.master_currency
FROM v_cbd_line g
JOIN cbd_revision r ON r.id = g.cbd_revision_id
LEFT JOIN v_cbd_price_check pc ON pc.line_id = g.id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
  AND g.cbd_revision_id::text = {{this.params.revision_id || ''}}
  AND (r.status = 'PUBLISHED'
       OR (SELECT fn_has_perm(fn_auth({{appsmith.store.token}}, 'view_cbd'), 'view_drafts')))
ORDER BY (g.status <> 'ACTIVE'), g.group_sort, g.comp_no NULLS LAST, g.sort_order;
```

**`q_cbd_recap`** (dijalankan `CbdGridCtrl.reload()`)
```sql
SELECT v.*
FROM v_cbd_recap v
JOIN cbd_revision r ON r.id = v.cbd_revision_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
  AND v.cbd_revision_id::text = {{this.params.revision_id || ''}}
  AND (r.status = 'PUBLISHED'
       OR (SELECT fn_has_perm(fn_auth({{appsmith.store.token}}, 'view_cbd'), 'view_drafts')));
```

**`q_cbd_checklist`** (dijalankan `CbdCtrl.openPublish()`)
```sql
SELECT *
FROM v_cbd_checklist
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'edit_cbd')) IS NOT NULL
  AND cbd_revision_id::text = {{this.params.revision_id || ''}};
```

**`q_cbd_change_log`** (dijalankan `CbdCtrl.loadArticle()`; semua terbit CBD article ini, terbaru dulu)
```sql
SELECT cl.id, cl.revision_id, r.stage || ' r' || r.revision_no AS revision_label,
       cl.category, cl.reason, cl.created_by, cl.created_at
FROM change_log cl
JOIN cbd_revision r ON r.id = cl.revision_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
  AND cl.doc_type = 'CBD'
  AND r.article_id::text = {{this.params.article_id || ''}}
ORDER BY cl.created_at DESC;
```

### 2c. Query tulis

**`a_cbd_header_set`**
```sql
SELECT fn_cbd_header_set({{appsmith.store.token}}, {{this.params.revision_id}}::uuid, {{this.params.field}},
                         nullif({{this.params.value}}, '')::numeric) AS id;
```

**`a_cbd_set_quotation`**
```sql
SELECT fn_cbd_set_quotation({{appsmith.store.token}}, {{this.params.line_id}}::uuid,
                            nullif({{this.params.price}}, '')::numeric, nullif({{this.params.currency}}, ''),
                            {{this.params.reference}}) AS id;
```

**`a_cbd_override_price`**
```sql
SELECT fn_cbd_override_price({{appsmith.store.token}}, {{this.params.line_id}}::uuid,
                             nullif({{this.params.price}}, '')::numeric, nullif({{this.params.currency}}, ''),
                             {{this.params.reason}}) AS id;
```

**`a_cbd_clear_override`** — *Request confirmation before running* = **ON**
```sql
SELECT fn_cbd_clear_override({{appsmith.store.token}}, {{this.params.line_id}}::uuid) AS id;
```

**`a_cbd_refresh_prices`** (konfirmasi OFF)
```sql
SELECT fn_cbd_refresh_prices({{appsmith.store.token}}, {{this.params.revision_id}}::uuid) AS n;
```

**`a_cbd_refresh_spec`** — *Request confirmation before running* = **ON**
```sql
SELECT fn_cbd_refresh_from_spec({{appsmith.store.token}}, {{this.params.revision_id}}::uuid) AS n;
```

**`a_cbd_publish`** — konfirmasi **OFF** (modal Terbitkan sudah menjadi konfirmasi)
```sql
SELECT fn_cbd_publish({{appsmith.store.token}}, {{this.params.revision_id}}::uuid,
                      {{this.params.category}}, {{this.params.reason}}) AS id;
```

### 2d. Widget di page

Baris revisi (di bawah `cwStepper`), kiri → kanan — perkecil `txtCbdRevisi` supaya muat 3 tombol:

| Widget | Setelan |
|---|---|
| `txtCbdRevisi` | Lebar ±kolom 0–40 · *Height* **Auto height** (bisa 3 baris: info + perlu revisi + change log) |
| `btnCbdRiwayat` *(baru)* | Button, style **secondary** · Label `{{CbdCtrl.historyLabel()}}` · Visible `{{!!CbdCtrl.articleId}}` · onClick `{{CbdCtrl.openHistory()}}` |
| `btnCbdTerbitkan` *(baru)* | Button, style **primary** · Label `Terbitkan…` · Visible (atau Disabled `!…`, sesuai pola Anda) `{{CbdCtrl.canPublish()}}` · onClick `{{CbdCtrl.openPublish()}}` |
| `btnCbdHapusDraft` | tetap |

`cwCbdGrid`:
1. Tempel ulang kode `widgets/cwCbdGrid/` (HTML / Style / JavaScript — ketiganya berubah).
2. Tinggi **±680 px** (tambah banner + rekap di atas grid).
3. Default model & event `onAction` **tetap** (`{{CbdGridCtrl.gridModel()}}`, `{{CbdGridCtrl.onAction()}}`).

### 2e. Modal `mdlCbdHarga` — Custom Widget `cwCbdPriceForm` *(baru)*

Modal lebar ±560 px, *close on outside click* **OFF**; widget tinggi ±520 px (kode `widgets/cwCbdPriceForm/`).

| Default model | `onSave` | `onCancel` |
|---|---|---|
| `{{CbdGridCtrl.priceFormModel()}}` | `{{CbdGridCtrl.savePrice()}}` | `{{closeModal('mdlCbdHarga')}}` |

### 2f. Modal `mdlCbdTerbit` — Custom Widget `cwPublishForm`

Modal lebar ±560 px, *close on outside click* **OFF**; widget `cwPublishForm` tinggi ±520 px. Boleh disalin dari
modal `mdlTerbit` page Specsheet, lalu **tempel ulang kode** `widgets/cwPublishForm/` (ada opsi baru `blockedWhere`)
dan ganti isi berikut:

| Default model | `onPublish` | `onCancel` |
|---|---|---|
| `{{CbdCtrl.publishFormModel()}}` | `{{CbdCtrl.publish()}}` | `{{closeModal('mdlCbdTerbit')}}` |

### 2g. Modal `mdlCbdRiwayat` + `tblCbdRiwayat`

Modal lebar ±900 px. `tblCbdRiwayat`: Table Data `{{CbdCtrl.changeLogs()}}`, **Search OFF**, kolom:

| Kolom | Label | Setelan |
|---|---|---|
| `revision_label` | Revisi | – |
| `category` | Kategori | – |
| `reason` | Alasan | *Cell wrapping* ON |
| `created_by` | Oleh | – |
| `created_at` | Waktu | Computed value `{{Util.fmtDateTime(currentRow.created_at)}}`, Column type **Text** |
| `id`, `revision_id` | – | disembunyikan |

Lalu **Deploy**.

---

## 3. Specsheet (kecil)

- `cwPublishForm` di `mdlTerbit`: tempel ulang kode `widgets/cwPublishForm/` supaya kode di kedua page sama
  (tampilan Specsheet **tidak berubah**).
- Tidak ada query / JSObject yang berubah: `fn_revision_publish` sudah diperbarui di DB (penandaan sinkron CBD).

---

## 4. Uji

Akun: **Vendor – CBD** (mengisi), **Vendor – Specsheet**, **Master Admin**, **Brand Viewer**.
Persiapan: pakai data uji F7 (`ILZ-02` / `SS27`, article `A1`, `A2`). Siapkan (Master Admin, Master Material):
- material katalog `M-IDR` dengan harga **APPROVED** `45000 IDR` (supplier baris `10`, semua warna);
- material katalog `M-USD` dengan harga **APPROVED** `2,5 USD` (supplier baris lain);
- satu material **Quotation** di salah satu baris (dari F7).

**Q-cbd** (DB Tools, dipakai berulang):
```sql
SELECT a.code, r.stage, r.revision_no, r.status, r.sync_status, r.exchange_rate,
       rc.material_cost, rc.actual_fob, rc.variance_label, round(rc.margin_pct, 2) AS margin,
       ck.stale_prices, ck.no_yield_count, ck.unpriced_count, ck.missing_count, ck.blocked
FROM cbd_revision r JOIN article a ON a.id = r.article_id
JOIN specsheet s ON s.id = a.specsheet_id JOIN product_model m ON m.id = s.model_id
JOIN v_cbd_recap rc ON rc.cbd_revision_id = r.id
JOIN v_cbd_checklist ck ON ck.cbd_revision_id = r.id
WHERE m.code = 'ILZ-02'
ORDER BY a.code, r.stage_order, r.revision_no;
```

### A. Harga (Vendor – CBD, draft A1 — buat baru bila belum ada)

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| A1 | Buka CBD A1 draft | Di atas grid: panel rekap (Exchange rate kotak kuning), banner info baris tanpa harga (bila ada) |
| A2 | Baris Quotation → **Isi harga** → isi `125000` tanpa klik currency → Simpan | Pesan *Pilih currency…*; klik **IDR** → Simpan → toast *Harga quotation disimpan.*; badge **quotation** (hover: referensi) |
| A3 | Baris Quotation → **Ubah harga** → kosongkan harga → Simpan | *Harga quotation dikosongkan.*; keterangan *material quotation — belum diisi (cost 0)* |
| A4 | Baris katalog `10` → **Override…** → `47.500` | Pesan *ambigu*; `47000`, klik **IDR**, alasan kosong → *Alasan override wajib diisi.*; isi alasan → Simpan → badge **override** (hover: alasan) |
| A5 | Baris `10` → **Hapus override** → Cancel lalu Confirm | Kembali ke harga master `45.000` badge **master** |
| A6 | Master Admin: Master Material `M-IDR` → **Ganti harga** jadi `46000 IDR` berlaku hari ini. Vendor – CBD reload CBD A1 | Baris `10`: *harga master berubah — klik Refresh Harga*; banner kuning **Refresh Harga dari Master** |
| A7 | Klik **Refresh Harga dari Master** | Toast *Harga 1 baris disamakan…*; baris `10` = `46.000`, banner hilang |
| A8 | Vendor – CBD usulkan harga untuk material/supplier yang belum punya harga (F3b, PROPOSED). CBD | Keterangan *harga master menunggu approval Master Admin*. Master Admin **Approve** → reload CBD → *harga master tersedia — klik Refresh Harga* + banner → Refresh → berharga |
| A9 | Harga khusus warna lain (mis. `Red`) di material yang baris CBD-nya `Black` tanpa harga semua warna | Keterangan *belum ada harga untuk warna ini (ada: Red)* |
| A10 | DB Tools: `SELECT fn_cbd_override_price('salah', gen_random_uuid(), 1, 'IDR', 'x');` | Error *SESI_HABIS…* |

### B. Rekap (cek 1 contoh manual)

Contoh: baris `10` harga `45000 IDR`, Yield `12,5`, Loss `3` → cost 45000 × 0,08 × 1,03 = **3.708**;
baris USD `2,5 USD`, Yield `20`, Loss `0`, rate `16250` → IDR 40.625, cost **2.031,25**; baris lain tanpa harga
atau Yield kosong. (Harga `M-IDR` sudah `46000` sejak A6 → pakai **Override…** `45000 IDR` di baris `10` dulu.)

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| B1 | Exchange rate `16.250` | Pesan *ambigu*; `16250` → tersimpan, IDR & Cost/pr baris USD terisi, kotak tidak kuning |
| B2 | Kosongkan Exchange rate | Pesan *Exchange rate harus diisi…* (tidak tersimpan) |
| B3 | Amortisasi `1500`, Adjustment `-200` | Material cost **5.739,25**; Actual FOB **7.039,25** |
| B4 | Target FOB `7000` | Selisih **39,25 OVER** (merah); Target `8000` → **-960,75 UNDER** (hijau) |
| B5 | Margin % `25` | Selling price **9.385,67**, Margin % **25,00 %** |
| B6 | Selling price `10000` | Margin % **29,61 %** |
| B7 | Margin % `100` | Pesan *Margin harus kurang dari 100%.* |
| B8 | DB Tools: **Q-cbd** | Angka A1 draft sama dengan layar (material_cost, actual_fob, margin) |

### C. Terbit & riwayat

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| C1 | Kosongkan Yield satu baris berharga → **Terbitkan…** | Checklist ✕ *Baris berharga punya Yield (1 baris…)*; form & tombol Terbitkan tidak tampil (*Perbaiki 1 hal di atas di grid / rekap CBD…*) |
| C2 | Isi Yield; buat harga master berubah (A6) tanpa refresh → **Terbitkan…** | ✕ *Harga master sama…* → Refresh → buka lagi → semua ✓ (baris tanpa harga = **!** peringatan) |
| C3 | Revisi awal (r0 **CBD baru**) → alasan kosong → **Terbitkan** | Terbit, kategori terpilih *Lainnya*; chip **TERBIT**; grid & rekap hanya baca; tombol Terbitkan / Hapus Draft hilang; `txtCbdRevisi` *Perubahan (OTHER): Revisi awal.* |
| C4 | **Riwayat (1)** | Modal: 1 baris (Revisi, Kategori, Alasan, Oleh, Waktu) |
| C5 | **+ Buat Revisi CBD** → Revisi berikutnya → ubah Yield → Terbitkan, alasan kosong | Pesan *Alasan perubahan wajib diisi…*; isi kategori **Yield / Loss %** + alasan → terbit; Riwayat (2) |
| C6 | Dua tab: tab 1 buka **Terbitkan…** draft; tab 2 hapus draft itu; tab 1 klik Terbitkan | Pesan error dari DB (*Revisi CBD tidak ditemukan.*), tidak terbit |
| C7 | DB Tools: `UPDATE cbd_revision SET exchange_rate = 1 WHERE status = 'PUBLISHED';` | Error *…sudah diterbitkan dan tidak bisa diubah…* |

### D. Refresh dari specsheet & sinkron

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| D1 | A1 punya CBD terbit (C5). A2: buat draft CBD. Vendor – Specsheet: revisi specsheet berikutnya **tanpa** mengubah baris A1 (mis. hanya ubah warna A2 di satu baris) → Terbitkan | CBD A1 tetap **TERBIT** (IN_SYNC), `txtCbdRevisi` acuan specsheet = revisi baru. CBD A2 draft: chip *· specsheet baru*, banner merah **Refresh dari Specsheet** |
| D2 | A2 → **Refresh dari Specsheet** → Cancel lalu Confirm | Toast *CBD di-refresh…*; banner hilang; Yield/Loss/harga input tetap; baris yang tidak dipakai A2 lagi → MISSING_IN_SPEC |
| D3 | Sebelum refresh, coba **Terbitkan…** A2 (ulangi D1 bila perlu) | ✕ *Specsheet acuan = terbit terakhir* |
| D4 | Vendor – Specsheet: revisi berikutnya → ganti supplier / warna A1 di satu baris → Terbitkan | CBD A1: chip **PERLU REVISI** (merah), stepper revisi terbit bertanda; `txtCbdRevisi` *Specsheet terbit … mengubah baris…*; Model Detail kolom CBD merah |
| D5 | Specsheet revisi berikutnya lagi tanpa perubahan A1 → Terbitkan | CBD A1 **tetap PERLU REVISI** (P5) |
| D6 | A1 → **+ Buat Revisi CBD** → Revisi berikutnya → isi → Terbitkan | Chip **TERBIT** (hijau) revisi baru; revisi lama tetap bertanda perlu revisi di stepper |
| D7 | DB Tools: **Q-cbd** | Sesuai langkah di atas (sync_status, missing) |

### E. Hak akses

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| E1 | Brand Viewer → CBD A1 | Hanya revisi terbit; rekap hanya baca (Selling price & Margin % tampil); tidak ada banner, link harga, tombol Terbitkan; **Riwayat** bisa dibuka |
| E2 | Master Admin → CBD draft | Grid & rekap hanya baca, tidak ada link harga / banner / Terbitkan |
| E3 | Vendor – Specsheet | Page CBD tetap ditolak (F7 A5) |

---

## 5. Export & cek skema

1. Export app → simpan sebagai `appsmith/exports/export_v8.json`.
2. Jalankan query cek skema (`PLAN.md` §8) di DB Tools, tempel hasilnya ke chat — harus ada view `v_cbd_price_check`,
   `v_cbd_recap`, `v_cbd_checklist`, function `fn_cbd_populate`, `fn_cbd_price_line`, `fn_cbd_check_price`,
   `fn_cbd_set_quotation`, `fn_cbd_override_price`, `fn_cbd_clear_override`, `fn_cbd_refresh_prices`,
   `fn_cbd_refresh_from_spec`, `fn_cbd_header_set`, `fn_cbd_publish`, `fn_cbd_sync_spec`, `fn_revision_publish`.
   Cek juga hanya ada **satu** `fn_cbd_populate`:
   ```sql
   SELECT oid::regprocedure FROM pg_proc WHERE proname = 'fn_cbd_populate';
   ```
   Hasil: `fn_cbd_populate(uuid,uuid,uuid,cbd_line[],boolean,text,text)`.
3. Kirim juga hasil uji A–E (termasuk yang gagal) dan hasil **Q-cbd** setelah D7.
