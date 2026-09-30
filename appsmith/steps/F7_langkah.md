# F7 — CBD: buat revisi & grid baris: langkah di Appsmith

Urutan: **0** sisa F6 → **1** SQL → **2** Model Detail (kolom CBD) → **3** Specsheet (kecil) → **4** page CBD →
**5** uji → **6** export `export_v7.json`.

Setelan untuk **semua query baru** (datasource `Prestasi`): *Use prepared statements* **ON**, *Run behaviour* **Manual**
(⚠️ termasuk **7 query baca** page CBD — jangan dibiarkan *Automatic*, lihat T22/T28).
`cwHeader`: **salin dari Specsheet**, ganti `pageTitle` saja. Jangan membuat query uji (`Query1`) di app ini — pakai DB Tools (T21).

Aturan CBD (= Python `cbd_service.py`, disederhanakan sesuai PLAN §2):
- CBD dibuat **per article**. Acuan = revisi specsheet **terbit terakhir** season itu; article harus **ACTIVE** di
  revisi itu (article di-drop / belum ada di specsheet terbit → CBD hanya bisa dilihat, tidak bisa dibuat/diubah).
- **Buat CBD** (satu function `fn_cbd_create`):
  - article belum punya CBD → **CBD baru dari specsheet** atau **Copy dari article lain** (model sama, season apa pun;
    sumber = CBD terbit terakhir article itu);
  - article sudah punya CBD terbit → **Revisi berikutnya** (sumber = CBD terbit terakhir article ini).
  - Stage CBD = stage specsheet acuan; nomor = terakhir di stage itu + 1.
- Baris CBD = baris BOM aktif yang **dipakai** article (sel berwarna), termasuk subkomponen. Yang di-copy dari sumber:
  Yield, Loss %, harga quotation/override (F8), rekap (rate dll.). Harga master selalu diambil ulang (hanya APPROVED).
  Pencocokan baris: lineKey → originLineKey → identitas (komponen, no. lokal, nama sub, material); baris hasil
  **Ganti material** membawa Yield/Loss % baris lama. Revisi berikutnya: baris sumber yang tidak ada lagi di specsheet
  → **MISSING_IN_SPEC** (bagian merah, tidak dihitung).
- Grid: edit **Yield** & **Loss %** saja. Usage = 1/Yield, harga IDR/USD, cost/pair dihitung DB.
- **Belum di F7** (masuk F8): input harga quotation/override, rekap & exchange rate, refresh dari specsheet /
  harga master, terbitkan CBD, penandaan *perlu revisi*. Untuk menguji **Revisi berikutnya** & kunci terbit, CBD
  diterbitkan sementara lewat DB Tools (langkah 5D).

---

## 0. Sisa F6 (temuan review v6)

- **T33 (penting)**: uji F6 baru 1 kali terbit. Jalankan uji F6 §5 **B1, C1–C6, E2** lalu kirim hasil query E3
  (`change_log` harus ≥ 4 baris: satu *Revisi awal.* / OTHER, satu MATERIAL, satu stage berikutnya, satu dari E2).
  Specsheet terbit dari uji ini dipakai lagi di uji F7.
- T30: `mdlTerbit` → *close on outside click* **OFF**.
- T31: `tblRiwayat` kolom `category` → label **Kategori**; Search **OFF**.

---

## 1. SQL

1. DB Tools → `z_run_sql` → tempel seluruh `sql/F7_cbd.sql` → Run.
2. Cek cepat:
   ```sql
   SELECT (SELECT count(*) FROM cbd_revision) AS cbd, (SELECT count(*) FROM v_cbd_article) AS article,
          (SELECT count(*) FROM v_article_status) AS article_status;
   ```
   Hasil `0 | <jumlah article> | <jumlah article>` tanpa error.

---

## 2. Model Detail — kolom CBD per article

1. JSObject `ModelDetailCtrl` → tempel ulang `js/ModelDetailCtrl.js` (baru: `cbdText()`, `cbdColor()`).
2. Query **`q_articles`** — ganti seluruhnya (kolom CBD dikosongkan untuk role tanpa `view_cbd`; draft CBD hanya untuk `view_drafts`):
   ```sql
   SELECT v.id, v.specsheet_id, v.code, v.colorway, v.attachment_count::int AS attachment_count, v.is_used,
          v.updated_at, v.updated_by, v.pub_label, v.pub_status, v.draft_label, v.draft_status,
          CASE WHEN pr.cbd THEN v.cbd_pub_label END AS cbd_pub_label,
          CASE WHEN pr.cbd THEN v.cbd_pub_sync END AS cbd_pub_sync,
          CASE WHEN pr.cbd AND pr.drafts THEN v.cbd_draft_label END AS cbd_draft_label
   FROM v_article_status v
   CROSS JOIN (SELECT fn_has_perm(x.e, 'view_cbd') AS cbd, fn_has_perm(x.e, 'view_drafts') AS drafts
                 FROM (SELECT fn_auth({{appsmith.store.token}}, 'view_model') AS e) x) pr
   WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_model')) IS NOT NULL
     AND v.specsheet_id::text = {{this.params.specsheet_id || ''}}
   ORDER BY v.code;
   ```
3. `tblArticles`: sembunyikan `cbd_pub_label`, `cbd_pub_sync`, `cbd_draft_label`; tambah kolom **CBD** (setelah
   Specsheet): Column type Text · Computed value `{{ModelDetailCtrl.cbdText(currentRow)}}` ·
   Text color `{{ModelDetailCtrl.cbdColor(currentRow)}}` · bold. (Vendor – Specsheet melihat kolom kosong.)

---

## 3. Specsheet (kecil)

1. JSObject `SpecCtrl` → tempel ulang `js/SpecCtrl.js` (`openCbd()` meneruskan `from`, supaya tombol kembali di CBD
   mengarah ke page asal yang sama).
2. `cwStepper` → tempel ulang kode `widgets/cwStepper/` (HTML / Style / JavaScript). Tampilan Specsheet **tidak berubah**;
   kode baru dipakai juga di CBD, jadi keduanya sama.

---

## 4. Page `Cost Breakdown (CBD)` (`?model_id=&season=&from=`, semua opsional)

Dari Model List (**CBD**), Model Detail (**Buka CBD**), Specsheet (**Buka CBD →**) → model & season langsung terpilih.
Dari sidebar → pilih **Model** lalu **Season**. Page ini sekarang masih kosong (hanya `Auth`, `Util`, `q_me`).

### 4a. JSObject
- `Auth`: `requiredPerm: 'view_cbd'` dan
  ```js
  pageQueries() {
  	return [{ run: () => CbdCtrl.init() }];
  },
  ```
- Buat **`CbdCtrl`** → tempel `js/CbdCtrl.js`.
- Buat **`CbdGridCtrl`** → tempel `js/CbdGridCtrl.js`.

### 4b. Query baca (semua **Manual**)

**`q_cbd_models`**
```sql
SELECT id, code, name
FROM product_model
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
ORDER BY code;
```

**`q_cbd_model`**
```sql
SELECT id, code, name, category, factory, size_range, sample_size
FROM product_model
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
  AND id::text = {{this.params.model_id || ''}};
```

**`q_cbd_seasons`** (season terbaru dulu + revisi specsheet terbit terakhir)
```sql
SELECT s.id, s.season, s.season_sort, sp.stage || ' r' || sp.revision_no AS spec_pub_label
FROM specsheet s
LEFT JOIN specsheet_revision sp ON sp.id = fn_spec_latest_pub(s.id)
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
  AND s.model_id::text = {{this.params.model_id || ''}}
ORDER BY s.season_sort DESC;
```

**`q_cbd_articles`** (status CBD per article; draft hanya untuk `view_drafts`)
```sql
SELECT v.id, v.code, v.colorway, v.spec_status, v.spec_pub_id, v.spec_pub_label, v.spec_pub_stage,
       CASE WHEN pr.drafts THEN v.draft_id END AS draft_id,
       CASE WHEN pr.drafts THEN v.draft_label END AS draft_label,
       coalesce(pr.drafts AND v.draft_stale, false) AS draft_stale,
       v.pub_id, v.pub_label, v.pub_sync
FROM v_cbd_article v
CROSS JOIN (SELECT fn_has_perm(fn_auth({{appsmith.store.token}}, 'view_cbd'), 'view_drafts') AS drafts) pr
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
  AND v.specsheet_id::text = {{this.params.specsheet_id || ''}}
ORDER BY v.code;
```

**`q_cbd_revisions`** (Brand hanya revisi terbit)
```sql
SELECT r.id, r.stage, r.stage_order, r.revision_no, r.status, r.sync_status, r.specsheet_revision_id,
       sr.stage || ' r' || sr.revision_no AS spec_label, r.exchange_rate,
       r.published_at, r.published_by, r.created_at, r.created_by,
       src_a.code AS source_article, src_sp.season AS source_season, src.stage || ' r' || src.revision_no AS source_label
FROM cbd_revision r
JOIN specsheet_revision sr ON sr.id = r.specsheet_revision_id
LEFT JOIN cbd_revision src ON src.id = r.source_cbd_revision_id
LEFT JOIN article src_a ON src_a.id = src.article_id
LEFT JOIN specsheet src_sp ON src_sp.id = src_a.specsheet_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
  AND r.article_id::text = {{this.params.article_id || ''}}
  AND (r.status = 'PUBLISHED'
       OR (SELECT fn_has_perm(fn_auth({{appsmith.store.token}}, 'view_cbd'), 'view_drafts')))
ORDER BY r.stage_order, r.revision_no;
```

**`q_cbd_lines`** (draft tidak terbaca oleh Brand; ACTIVE dulu, lalu grup, nomor komponen, urutan)
```sql
SELECT g.*
FROM v_cbd_line g
JOIN cbd_revision r ON r.id = g.cbd_revision_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
  AND g.cbd_revision_id::text = {{this.params.revision_id || ''}}
  AND (r.status = 'PUBLISHED'
       OR (SELECT fn_has_perm(fn_auth({{appsmith.store.token}}, 'view_cbd'), 'view_drafts')))
ORDER BY (g.status <> 'ACTIVE'), g.group_sort, g.comp_no NULLS LAST, g.sort_order;
```

**`q_cbd_sources`** (sumber "Copy dari article lain": article model sama yang punya CBD terbit, kecuali article ini)
```sql
SELECT a.id, a.code, a.colorway, sh.season, p.stage || ' r' || p.revision_no AS label,
       fn_cbd_article_spec_status(a.id) = 'DROPPED' AS dropped
FROM article a
JOIN specsheet sh ON sh.id = a.specsheet_id
JOIN LATERAL (
  SELECT r.stage, r.revision_no FROM cbd_revision r
   WHERE r.article_id = a.id AND r.status = 'PUBLISHED'
   ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
) p ON true
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'edit_cbd')) IS NOT NULL
  AND sh.model_id::text = {{this.params.model_id || ''}}
  AND a.id::text <> {{this.params.article_id || ''}}
ORDER BY sh.season_sort DESC, a.code;
```

### 4c. Query tulis

**`a_cbd_create`**
```sql
SELECT fn_cbd_create({{appsmith.store.token}}, {{this.params.article_id}}::uuid, {{this.params.mode}},
                     nullif({{this.params.source_article_id}}, '')::uuid) AS id;
```

**`a_cbd_delete`** — *Request confirmation before running* = **ON**
```sql
SELECT fn_cbd_delete_draft({{appsmith.store.token}}, {{this.params.id}}::uuid) AS id;
```

**`a_cbd_line_set`**
```sql
SELECT fn_cbd_line_set({{appsmith.store.token}}, {{this.params.line_id}}::uuid, {{this.params.field}},
                       nullif({{this.params.value}}, '')::numeric) AS id;
```

### 4d. Widget (atas → bawah; susunan sama dengan page Specsheet)

| Widget | Setelan |
|---|---|
| `cwHeader` | Salin dari **Specsheet**, `pageTitle: 'Cost Breakdown (CBD)'` |
| `cntHeader` + `btnKembali` | Label `{{CbdCtrl.backLabel()}}`, style tertiary · onClick `{{CbdCtrl.openModel()}}` |
| `txtCbdJudul` (di `cntHeader`) | Text `{{CbdCtrl.headerText()}}` |
| `btnBukaSpec` (di `cntHeader`) | `Buka Specsheet →`, style secondary · Visible `{{CbdCtrl.canViewSpec() && !!CbdCtrl.model()}}` · onClick `{{CbdCtrl.openSpec()}}` |
| `selCbdModel` | Select, label `Model`, placeholder `Pilih model…`, *Filterable* **ON**, *Allow clearing* OFF · Source data `{{CbdCtrl.modelOptions()}}` · Default selected value `{{CbdCtrl.modelId}}` · onOptionChange `{{CbdCtrl.pickModel(selCbdModel.selectedOptionValue)}}` |
| `selCbdSeason` | Select, label `Season`, placeholder `Belum ada season`, *Allow clearing* OFF · Source data `{{CbdCtrl.seasonOptions()}}` · Default selected value `{{CbdCtrl.seasonId}}` · onOptionChange `{{CbdCtrl.pickSeason(selCbdSeason.selectedOptionValue)}}` |
| `btnBuatCbd` | Label `{{CbdCtrl.revisions().length ? '+ Buat Revisi CBD' : '+ Buat CBD'}}` · Visible `{{CbdCtrl.canCreate()}}` · onClick `{{CbdCtrl.openCreate()}}` |
| `cwStepper` | Custom Widget (kode `widgets/cwStepper/`), lebar penuh, tinggi **±130 px** · Default model `{{CbdCtrl.stepperModel()}}` · event `onSelect` `{{CbdCtrl.selectRevision()}}` · event **`onArticle`** `{{CbdCtrl.selectArticle()}}` |
| `txtCbdRevisi` | Text `{{CbdCtrl.revisionText()}}`, *Height* **Auto height** |
| `btnCbdHapusDraft` | `Hapus Draft`, warna merah, style secondary · Visible (atau Disabled `!…`, sesuai pola Anda) `{{CbdCtrl.canDeleteDraft()}}` · onClick `{{CbdCtrl.deleteDraft()}}` |
| `cwCbdGrid` | Custom Widget (kode `widgets/cwCbdGrid/`), lebar penuh, tinggi **±600 px** · Visible `{{!!CbdCtrl.revision()}}` · Default model `{{CbdGridCtrl.gridModel()}}` · event `onAction` `{{CbdGridCtrl.onAction()}}` |

Event Custom Widget ditambahkan di panel properti widget (**Events → + Add event**) dengan nama persis `onSelect`,
`onArticle`, `onAction`.

### 4e. Modal `mdlCbdBaru` — Custom Widget `cwCbdForm`

Modal lebar ±560 px, *close on outside click* **OFF**; widget tinggi ±420 px (kode `widgets/cwCbdForm/`).

| Default model | `onSave` | `onCancel` |
|---|---|---|
| `{{CbdCtrl.createFormModel()}}` | `{{CbdCtrl.saveCreate()}}` | `{{closeModal('mdlCbdBaru')}}` |

Lalu **Deploy**.

---

## 5. Uji

Akun: **Vendor – CBD** (mengisi), **Vendor – Specsheet**, **Master Admin**, **Brand Viewer**.
Persiapan (pakai data uji F6, mis. `ILZ-02` / `SS27`, article `A1`, `A2`):
- Specsheet `SS27` punya revisi **terbit** terakhir dengan: baris `10` (material CATALOG + supplier yang **punya harga
  APPROVED**), subkomponen `10-1`, baris lokal `35`, satu baris tanpa supplier; A1 memakai semua baris, A2 **tidak**
  memakai baris `35` (warna A2 kosong).
- Satu material QUOTATION di salah satu baris (harganya kosong di CBD — diisi di F8).

**Q-cbd** — query bantu di DB Tools (dipakai berulang):
```sql
SELECT a.code, r.stage, r.revision_no, r.status, r.exchange_rate,
       (SELECT count(*) FROM cbd_line l WHERE l.cbd_revision_id = r.id AND l.status = 'ACTIVE') AS aktif,
       (SELECT count(*) FROM cbd_line l WHERE l.cbd_revision_id = r.id AND l.status = 'MISSING_IN_SPEC') AS missing,
       (SELECT count(*) FROM cbd_line l WHERE l.cbd_revision_id = r.id AND l.yield_value IS NOT NULL) AS yield_terisi
FROM cbd_revision r JOIN article a ON a.id = r.article_id
JOIN specsheet s ON s.id = a.specsheet_id JOIN product_model m ON m.id = s.model_id
WHERE m.code = 'ILZ-02'
ORDER BY a.code, r.stage_order, r.revision_no;
```

### A. Navigasi & status

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| A1 | Buka **Cost Breakdown (CBD)** dari sidebar | Model kosong, *Pilih model dan season dahulu.*, chip *Pilih model dulu.*, tombol `← Model List` |
| A2 | Pilih `ILZ-02` | Season terbaru terpilih, label season `SS27 (specsheet … )`; chip `A1` & `A2` **BELUM ADA CBD** (biru); A1 terpilih; stepper *Belum ada CBD. Klik "+ Buat CBD".* |
| A3 | Model List → **CBD**; Model Detail → **Buka CBD**; Specsheet → **Buka CBD →** | Model & season sama langsung terpilih; tombol kembali `← Model List` / `← Model Detail` sesuai asal |
| A4 | Season yang specsheet-nya belum terbit | Label *specsheet belum terbit*; chip **SPECSHEET BELUM TERBIT**; tidak ada **+ Buat CBD**; teks *…terbitkan specsheet dulu* |
| A5 | Vendor – Specsheet buka page CBD lewat URL | Ditolak *Role … tidak punya akses*, kembali ke Beranda |

### B. CBD baru (Vendor – CBD, article A1)

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| B1 | **+ Buat CBD** | Modal: *Acuan: specsheet SS27 … (terbit terakhir)*; **CBD baru dari specsheet** terpilih; **Copy dari article lain** nonaktif (*Belum ada article lain … CBD terbit*) → **Buat** |
| B2 | — | Toast *CBD draft dibuat.*; chip A1 **DRAFT PULL r0** (kuning); stepper chip `r0` kuning di stage specsheet; `txtCbdRevisi` *A1 · … · DRAFT · acuan specsheet …* |
| B3 | Grid | Grup **A · Upper** berisi `10`, `10-1` (↳, nomor induk), `35` **lokal**; grup lain sesuai komponen. Thickness/Color/Supplier/UoM/Remarks sesuai specsheet |
| B4 | Kolom Harga | Baris `10`: harga master + badge **master** (hover: berlaku sejak …); baris tanpa supplier: *baris tanpa supplier di specsheet*; material QUOTATION: *material quotation …*; material tanpa harga: *belum ada harga master* |
| B5 | Yield baris `10` → `12,5` Enter | Tersimpan; fokus pindah ke Yield baris berikutnya; Usage `0,08`; Cost/pr = 0,08 × IDR × (1 + loss/100) |
| B6 | Loss % baris `10` → `3` | Cost/pr naik 3 %; Asal tetap *input* |
| B7 | Yield `0`, `abc`, `1.250,5`; Loss `100` | Pesan merah di bar grid, tidak tersimpan (Esc mengembalikan) |
| B8 | Kosongkan Yield baris `10` | Usage & Cost/pr `-`; kotak Yield kuning (baris berharga tanpa yield) |
| B9 | Baris harga USD | USD = harga asli; IDR & Cost/pr `-` (rate belum diisi — rekap F8); status bar *rate belum diisi* |
| B10 | **+ Buat CBD** tidak tampil selama ada draft; **Hapus Draft** → Cancel → Confirm | Draft terhapus, chip A1 kembali **BELUM ADA CBD**; buat lagi (B1) dan isi Yield beberapa baris |

### C. Hak akses

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| C1 | Brand Viewer → CBD `ILZ-02` / `SS27` | Chip A1 **BELUM ADA CBD** (draft tidak terlihat); stepper *Belum ada CBD yang terbit.*; tidak ada tombol buat / hapus |
| C2 | Master Admin | Bisa melihat draft A1 (hanya baca), tidak ada tombol buat / hapus |
| C3 | Model Detail `ILZ-02` / `SS27` (Vendor – CBD) | Kolom **CBD**: A1 *DRAFT · PULL r0* (oranye), A2 *BELUM ADA CBD*. Vendor – Specsheet: kolom CBD kosong |
| C4 | DB Tools: `SELECT fn_cbd_line_set('salah', gen_random_uuid(), 'YIELD', 1);` | Error *SESI_HABIS…* |

### D. Terbit sementara (DB Tools), copy, revisi berikutnya

Terbitkan draft A1 **sementara lewat DB Tools** (F8 membuat tombol Terbitkan):
```sql
UPDATE cbd_revision SET status = 'PUBLISHED', published_at = now(), published_by = 'uji'
 WHERE status = 'DRAFT' AND article_id = (SELECT a.id FROM article a JOIN specsheet s ON s.id = a.specsheet_id
                                            JOIN product_model m ON m.id = s.model_id
                                           WHERE m.code = 'ILZ-02' AND s.season = 'SS27' AND a.code = 'A1');
```

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| D1 | Reload page CBD, A1 | Chip **TERBIT PULL r0** (hijau); stepper `r0` biru; grid **hanya baca**; **Hapus Draft** tidak tampil; **+ Buat Revisi CBD** tampil |
| D2 | DB Tools: `UPDATE cbd_line SET loss_pct = 1 WHERE cbd_revision_id = (SELECT id FROM cbd_revision WHERE published_by = 'uji' LIMIT 1);` | Error *Revisi CBD ini sudah diterbitkan…* |
| D3 | DB Tools: `DELETE FROM cbd_revision WHERE published_by = 'uji';` | Error *…sudah diterbitkan dan tidak bisa dihapus.* |
| D4 | Pilih chip **A2** → **+ Buat CBD** → **Copy dari article lain** → sumber `A1 · SS27 · PULL r0 terbit` → **Buat** | Draft A2 `PULL r0`; baris = baris yang dipakai **A2** (tanpa `35`); Yield/Loss % baris yang sama dengan A1 ter-copy, Asal **copy** (hover: *Dari SS27 / A1 / PULL r0*); **tidak ada** bagian MISSING_IN_SPEC |
| D5 | Vendor – Specsheet: Specsheet `SS27` → **+ Buat Revisi** → Revisi berikutnya → **Ganti material** baris `10`, hapus satu baris lain (F5b), isi warna A1 di baris `35` kosongkan → **Terbitkan** (F6) | Revisi specsheet baru terbit |
| D6 | CBD A2 (masih draft) | Chip A2 **DRAFT PULL r0 · specsheet baru**; teks merah *Specsheet sudah terbit … refresh … F8* |
| D7 | CBD A1 → **+ Buat Revisi CBD** → **Revisi berikutnya** (`<stage> r1` atau `r0` stage baru) → **Buat** | Draft baru; baris `10` material baru membawa Yield/Loss % lama, Asal **ganti material**; baris yang dihapus / tidak dipakai lagi (`35`) ada di bagian merah **MISSING_IN_SPEC**, hanya baca; `txtCbdRevisi` *sumber: SS27 / A1 / PULL r0* |
| D8 | DB Tools: **Q-cbd** | A1: r0 PUBLISHED + draft baru (`missing` ≥ 1); A2: draft (yield_terisi > 0) |
| D9 | Vendor – Specsheet: drop A2 di draft specsheet berikutnya lalu terbitkan. CBD A2 | Chip **DI-DROP**; grid hanya baca; teks *…sudah di-drop… CBD hanya bisa dilihat*; **Hapus Draft** tetap bisa |

---

## 6. Export & cek skema

1. Export app → simpan sebagai `appsmith/exports/export_v7.json`.
2. Jalankan query cek skema (`PLAN.md` §8) di DB Tools, tempel hasilnya ke chat — harus ada `cbd_revision`, `cbd_line`
   (table), `v_cbd_line`, `v_cbd_article` (view), `fn_spec_latest_pub`, `fn_cbd_article_spec_status`, `fn_cbd_draft`,
   `fn_cbd_group_code`, `fn_cbd_identity`, `fn_cbd_expected_lines`, `fn_cbd_populate`, `fn_cbd_create`,
   `fn_cbd_delete_draft`, `fn_cbd_line_set`, `fn_cbd_revision_lock`, `fn_cbd_line_lock` (function), trigger
   `trg_cbd_revision_lock`, `trg_lock_published` (cbd_line).
3. Kirim juga hasil uji A–D (termasuk yang gagal) dan hasil **Q-cbd** setelah D8.
