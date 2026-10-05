# F8 — CBD: harga, rekap, refresh, terbit, sinkron: langkah di Appsmith

Urutan: **1** SQL → **2** page CBD (JSObject, query, desain & langkah widget §2d–2i) → **3** Specsheet (kecil) → **4** uji →
**5** export `export_v8.json`.

Setelan untuk **semua query baru** (datasource `Prestasi`): *Use prepared statements* **ON**, *Run behaviour* **Manual**
(⚠️ termasuk **3 query baca** baru `q_cbd_recap`, `q_cbd_checklist`, `q_cbd_change_log` — jangan dibiarkan
*Automatic*, lihat T22/T28). Jangan membuat query uji (`Query1`) di app ini — pakai DB Tools (T21/T34).
Modal baru disalin dari pola lama boleh, tapi **event handler selalu ditempel dari panduan ini** (jangan membawa
handler page lain).

> **Diubah di F8b** (5 Okt 2026, `steps/F8b_langkah.md`): Amortisasi & Adjustment bukan lagi kolom rekap, tetapi baris
> di tabel **Cost recapitulation** di bawah grid (+ Direct Labour, Lainnya); Target FOB, Selling price & Margin % juga
> pindah ke bawah grid. Uji B3 di bawah memakai baris Amortisasi / Adjustment di tabel itu.

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

### 2d. Desain page (teks)

Grid Appsmith: lebar 64 kolom, 1 baris = 10 px. Posisi ditulis **baris atas–bawah · kolom kiri–kanan** (geser/tarik
widget sampai angka di panel mendekati; tidak harus persis). ★ = baru di F8, ✎ = diubah, lainnya tetap dari F7.

```
kolom:   0                                                   48     53        59    64
         ┌──────────────────────────────────────────────────────────────────────────┐
  0–  8  │ cwHeader   Cost Breakdown (CBD) · nama user · Keluar                      │
  8– 17  │ cntHeader  [← Model List]  ILZ-02 — Illuzion …           [Buka Specsheet →]│
 17– 24  │ [Model ▾ selCbdModel]  [Season ▾ selCbdSeason]  [+ Buat CBD]              │
 24– 36  │ cwStepper  (A1 · TERBIT PULL r0) (A2 · DRAFT PULL r0)                     │
         │            PULL ── r0 ── r1   │ SMS │ GTM │ PROD                          │
 36– 40  │ txtCbdRevisi                                 │★Riwayat│★Terbitkan│✎Hapus  │
         │ A1 · Black · PULL r1 · DRAFT · acuan …       │  (2)   │    …     │ Draft  │
         │ (auto height, bisa 2–3 baris)                │        │          │        │
 41–109  │✎cwCbdGrid  (±680 px)                                                     │
         │ ┌──────────────────────────────────────────────────────────────────────┐ │
         │ │ [pesan error / info ……………………]           4 baris · 1 tanpa harga     │ │ bar
         │ │ ▌Harga master untuk 1 baris berubah …  [Refresh Harga dari Master]   │ │ banner
         │ │ Exch.rate│Mat.cost│Amortisasi│Adjustment│Actual FOB│Target FOB│Selisih   │Selling│Margin%│ rekap
         │ │ [16250 ] │8.308,5 │[1500    ]│[-200    ]│ 9.608,5  │[9000    ]│608,5 OVER│[     ]│[    ]│ (menempel)
         │ ├──────────────────────────────────────────────────────────────────────┤ │
         │ │ No│Komponen│Material│Thk│Color│Supplier│UoM│Remarks│Yield│Usage│Loss%│Harga        │Cur│USD│IDR│Cost/pr│Asal
         │ │ A · Upper                                                            │ │
         │ │ 10│Vamp    │Mesh …  │   │Black│PT Maju │M  │       │[12,5]│0,08│[3] │45.000 master│IDR│ … │
         │ │   │        │        │   │     │        │   │       │      │    │    │Override…    │   │   │
         │ │ 35│Heel badge lokal │ … │Gold │   -    │PCS│       │[    ]│ -  │[0] │quotation —  │   │   │
         │ │   │        │        │   │     │        │   │       │      │    │    │belum diisi  │   │   │
         │ │   │        │        │   │     │        │   │       │      │    │    │Isi harga    │   │   │
         │ │ Hilang dari specsheet (MISSING_IN_SPEC) — 1 baris, tidak dihitung     │ │
         │ └──────────────────────────────────────────────────────────────────────┘ │
         └──────────────────────────────────────────────────────────────────────────┘
Modal (tidak terlihat di canvas): mdlCbdBaru (F7) · ★mdlCbdHarga · ★mdlCbdTerbit · ★mdlCbdRiwayat
```

```
★ mdlCbdHarga (±560 px)            ★ mdlCbdTerbit (±560 px)            ★ mdlCbdRiwayat (±900 px)
┌───────────────────────────────┐  ┌───────────────────────────────┐  ┌─────────────────────────────────────────┐
│ Override Harga              ✕ │  │ Terbitkan CBD A1 · PULL r1  ✕ │  │ Riwayat CBD                           ✕ │
│ 10 · Vamp · MTR-0001 … · Black│  │ ✓ Specsheet acuan = terbit …  │  │ Revisi │Kategori│Alasan     │Oleh │Waktu │
│ ┌ Harga sekarang: 45.000 IDR ┐│  │ ✓ Exchange rate terisi        │  │ PULL r1│YIELD   │Yield vamp │vcbd │01 Okt│
│ Harga *          Currency *   │  │ ✓ Harga master sama …         │  │ PULL r0│OTHER   │Revisi awal│vcbd │30 Sep│
│ [47000      ]    [IDR] [USD]  │  │ ✕ Baris berharga punya Yield  │  │                                         │
│ Terbaca: 47.000 IDR           │  │ ! Semua baris berharga        │  │                                         │
│ Alasan override *             │  │ Kategori * [— pilih — ▾]      │  │                                         │
│ [harga nego order ini       ] │  │ Alasan *   [              ]   │  │                                         │
│              [Batal] [Simpan] │  │          [Batal] [Terbitkan]  │  │                                         │
└───────────────────────────────┘  └───────────────────────────────┘  └─────────────────────────────────────────┘
  isi = Custom Widget                isi = Custom Widget                isi = Table tblCbdRiwayat
  cwCbdPriceForm                     cwPublishForm
```

Mode **Quotation** di `mdlCbdHarga`: judul *Harga Quotation*, harga boleh kosong (= tidak dihargai terpisah), kolom
bawah = *Referensi* (opsional).

### 2e. Langkah widget di page

Buka page **Cost Breakdown (CBD)** di editor. Pola tombol mengikuti page Specsheet Anda: tombol tetap tampil,
**Disabled** bila tidak boleh dipakai.

**Langkah 1 — ✎ `txtCbdRevisi`**
1. Klik `txtCbdRevisi` → tarik sisi kanan sampai kolom **48** (sekarang 59).
2. Properti tetap: Text `{{CbdCtrl.revisionText()}}` · *Height* **Auto height** · Font size **M**.

**Langkah 2 — `btnCbdHapusDraft`**: tetap di baris 36–40 · kolom **59–64**, properti tidak berubah
(Label `Hapus Draft`, variant Secondary, warna `#dc2626`, Disabled `{{!CbdCtrl.canDeleteDraft()}}`,
onClick `{{CbdCtrl.deleteDraft()}}`).

**Langkah 3 — ★ `btnCbdTerbitkan`** (klik `btnCbdHapusDraft` → Ctrl+C → Ctrl+V, lalu ubah)

| Bagian panel | Properti | Nilai |
|---|---|---|
| (judul panel) | Name | `btnCbdTerbitkan` |
| Posisi | baris · kolom | 36–40 · **53–59** |
| Basic | Label | `Terbitkan…` |
| Basic | onClick | `{{CbdCtrl.openPublish()}}` |
| General | Visible | ON |
| General | Disabled | klik **JS** di samping toggle → `{{!CbdCtrl.canPublish()}}` |
| Style | Button variant | **Primary** |
| Style | Button color | `{{appsmith.theme.colors.primaryColor}}` (ganti merah hasil salin) |

**Langkah 4 — ★ `btnCbdRiwayat`** (salin lagi, ubah)

| Bagian panel | Properti | Nilai |
|---|---|---|
| (judul panel) | Name | `btnCbdRiwayat` |
| Posisi | baris · kolom | 36–40 · **48–53** |
| Basic | Label | `{{CbdCtrl.historyLabel()}}` |
| Basic | onClick | `{{CbdCtrl.openHistory()}}` |
| General | Visible | klik **JS** → `{{!!CbdCtrl.articleId}}` |
| General | Disabled | OFF (hapus binding hasil salin) |
| Style | Button variant | **Secondary** · Button color `{{appsmith.theme.colors.primaryColor}}` |

**Langkah 5 — ✎ `cwCbdGrid`**
1. Klik `cwCbdGrid` → **Edit source** → tab **HTML**: hapus semua, tempel `widgets/cwCbdGrid/index.html`; tab
   **Style**: tempel `style.css`; tab **JavaScript**: tempel `script.js` → tutup editor.
2. Tarik tepi bawah sampai tinggi **±680 px** (baris 41–109). Kalau `txtCbdRevisi` jadi 2–3 baris, grid ikut turun.
3. Properti yang **tetap**: Default model `{{CbdGridCtrl.gridModel()}}` · Visible `{{!!CbdCtrl.revision()}}` ·
   *Height* **Fixed** · event **onAction** `{{CbdGridCtrl.onAction()}}`. Tidak ada event baru (semua aksi F8 lewat
   `onAction`).

### 2f. ★ Modal `mdlCbdHarga` — Custom Widget `cwCbdPriceForm`

1. Panel widget → seret **Modal** ke canvas → rename `mdlCbdHarga`.
2. Hapus isi bawaan modal: teks judul, tombol ikon ✕, tombol **Close** dan **Confirm** (judul & tombol sudah ada di
   Custom Widget).
3. Properti modal:

   | Properti | Nilai |
   |---|---|
   | *Quick dismiss* / Close on outside click | **OFF** |
   | Width | ±**560** px (tarik sisi modal) |
   | Height | **Auto height** |

4. Seret **Custom** widget ke dalam modal → rename `cwCbdPriceForm` → lebar penuh (kolom 0–64), tinggi **±520 px**.
5. **Edit source** → HTML / Style / JavaScript ← `widgets/cwCbdPriceForm/index.html`, `style.css`, `script.js`.
6. Properti widget:

   | Properti | Nilai |
   |---|---|
   | Default model | `{{CbdGridCtrl.priceFormModel()}}` |
   | Events → **+ Add event** `onSave` | `{{CbdGridCtrl.savePrice()}}` |
   | Events → **+ Add event** `onCancel` | `{{closeModal('mdlCbdHarga')}}` |
   | Height | **Fixed** |
   | Visible | ON |

### 2g. ★ Modal `mdlCbdTerbit` — Custom Widget `cwPublishForm`

1. Page **Specsheet** → Explorer → Widgets → klik `mdlTerbit` → Ctrl+C → page **CBD** → klik canvas kosong → Ctrl+V.
   (Atau buat Modal baru seperti 2f langkah 1–3 lalu seret Custom widget ke dalamnya.)
2. Rename modal `mdlCbdTerbit`. Widget di dalamnya tetap bernama **`cwPublishForm`** (nama sama di page lain tidak
   masalah; `CbdCtrl.publish()` membaca `cwPublishForm.model`).
3. Properti modal: *Close on outside click* **OFF** · Width ±**560** px · Height **Auto height**.
4. `cwPublishForm` → **Edit source** → tempel ulang kode `widgets/cwPublishForm/` (3 tab). Tinggi ±**520 px** (Fixed).
5. Ganti properti (⚠️ jangan biarkan handler Specsheet):

   | Properti | Nilai |
   |---|---|
   | Default model | `{{CbdCtrl.publishFormModel()}}` |
   | Event `onPublish` | `{{CbdCtrl.publish()}}` |
   | Event `onCancel` | `{{closeModal('mdlCbdTerbit')}}` |

### 2h. ★ Modal `mdlCbdRiwayat` + `tblCbdRiwayat`

1. Page **Specsheet** → salin `mdlRiwayat` → tempel di page CBD → rename modal `mdlCbdRiwayat`, tabel di dalamnya
   `tblCbdRiwayat`. (Atau Modal baru + seret **Table**, posisi baris 4–32 · kolom 0–64.)
2. Properti modal: Width ±**900** px · Height **Auto height** · Close on outside click boleh ON (hanya baca). Bila ada
   teks judul hasil salin, ganti jadi `Riwayat CBD`.
3. Properti `tblCbdRiwayat`:

   | Bagian panel | Properti | Nilai |
   |---|---|---|
   | Data | Table data | `{{CbdCtrl.changeLogs()}}` |
   | Data | Primary key column | `id` |
   | Search & filters | Allow searching | **OFF** |
   | Search & filters | Allow filtering · Allow download | OFF |
   | Pagination | Show pagination | ON |

4. Kolom (dari salinan Specsheet: **hapus** kolom `source_label` / *Sumber* — CBD tidak punya kolom itu):

   | Kolom | Label | Column type | Computed value | Lainnya |
   |---|---|---|---|---|
   | `id` | – | Text | (bawaan) | Visible **OFF** |
   | `revision_id` | – | Text | (bawaan) | Visible **OFF** |
   | `revision_label` | Revisi | Text | (bawaan) | – |
   | `category` | Kategori | Text | (bawaan) | – |
   | `reason` | Alasan | Text | (bawaan) | *Cell wrapping* **ON** |
   | `created_by` | Oleh | Text | (bawaan) | – |
   | `created_at` | Waktu | **Text** | `{{Util.fmtDateTime(currentRow.created_at)}}` | – |

### 2i. Cek akhir sebelum Deploy

- [ ] Explorer → Queries: 10 query F8 ada (3 baca **Manual**, 7 tulis); konfirmasi `a_cbd_clear_override` &
      `a_cbd_refresh_spec` **ON**, `a_cbd_publish` **OFF**; tidak ada `Query1`.
- [ ] Explorer → Widgets: `btnCbdRiwayat`, `btnCbdTerbitkan`, `mdlCbdHarga` (+ `cwCbdPriceForm`), `mdlCbdTerbit`
      (+ `cwPublishForm`), `mdlCbdRiwayat` (+ `tblCbdRiwayat`).
- [ ] Event Custom Widget sesuai tabel di atas: `cwCbdGrid.onAction`, `cwCbdPriceForm.onSave/onCancel`,
      `cwPublishForm.onPublish/onCancel` (bukan `SpecCtrl` / `mdlTerbit`).
- [ ] Preview sebagai Vendor – CBD: rekap tampil di atas grid; **Terbitkan…** aktif hanya di draft.

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
