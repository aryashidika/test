# F5 — Specsheet: revisi & grid BOM: langkah di Appsmith

Urutan: **0** sisa F4 → **1** SQL → **2** Model List & Model Detail (kolom status specsheet) → **3** page Specsheet → **4** uji → **5** export `export_v5.json`.

Setelan untuk **semua query baru** (datasource `Prestasi`): *Use prepared statements* **ON**, *Run behaviour* **Manual**.
`cwHeader`: **salin dari Model Detail**, ganti `pageTitle` saja. Jangan membuat query uji (`Query1`) di app ini — pakai DB Tools (T21).

Keputusan yang dipakai (30 Sep 2026):
- **Copy specsheet** hanya dari **season lain model yang sama** (development NC / New Color), sumbernya revisi **terbit**
  terakhir (urut stage lalu nomor — P1). Yang di-copy baris BOM; article = article season tujuan, warna kosong.
  Copy lintas model tidak dibawa.
- **Ganti material** memindahkan subkomponen ke baris baru (P4 — di Python subkomponen hilang dari grid).
- Terbitkan revisi = **F6**. Di F5 revisi dibuat, diisi, dan dihapus (draft); untuk menguji "revisi berikutnya"
  dan kunci revisi terbit, terbitkan lewat DB Tools (langkah 4).

---

## 0. Sisa F4

Kalau belum: hapus Copy Article (`steps/F4_langkah.md` §5).

---

## 1. SQL

1. DB Tools → `z_run_sql` → tempel seluruh `sql/F5_specsheet.sql` → Run.
2. Cek cepat:
   ```sql
   SELECT (SELECT count(*) FROM specsheet_revision) AS revisi, (SELECT count(*) FROM v_bom_grid) AS baris,
          (SELECT count(*) FROM v_model_list) AS model_season;
   ```
   Hasil `0 | 0 | <jumlah>` tanpa error.

---

## 2. Model List & Model Detail — kolom status specsheet

### 2a. Model List
1. JSObject `ModelCtrl` → tempel ulang `js/ModelCtrl.js` (fungsi baru `specSummary()`).
2. Query **`q_models`** — ganti baris `SELECT … FROM v_model_list` menjadi:
   ```sql
   SELECT id, code, name, category, factory, size_range, season_count::int AS season_count,
          specsheet_id, season, article_count::int AS article_count, updated_at,
          spec_label, spec_active_articles::int AS spec_active_articles,
          spec_label_pub, spec_active_articles_pub::int AS spec_active_articles_pub
   FROM v_model_list
   ```
   (bagian `WHERE … ORDER BY … LIMIT` tetap).
3. `tblModels`: sembunyikan kolom baru `spec_label`, `spec_active_articles`, `spec_label_pub`, `spec_active_articles_pub`;
   tambah kolom **Specsheet** (Add column, setelah Season): Column type Text · Computed value `{{ModelCtrl.specSummary(currentRow)}}`.

### 2b. Model Detail
1. JSObject `ModelDetailCtrl` → tempel ulang `js/ModelDetailCtrl.js` (fungsi baru `specText()`, `specColor()`).
2. Query **`q_articles`** — ganti baris SELECT menjadi:
   ```sql
   SELECT id, specsheet_id, code, colorway, attachment_count::int AS attachment_count, is_used, updated_at, updated_by,
          pub_label, pub_status, draft_label, draft_status
   FROM v_article_status
   ```
3. `tblArticles`: sembunyikan `pub_label`, `pub_status`, `draft_label`, `draft_status`; tambah kolom **Specsheet**
   (setelah Colorway): Column type Text · Computed value `{{ModelDetailCtrl.specText(currentRow)}}` ·
   Text color `{{ModelDetailCtrl.specColor(currentRow)}}` · bold.

---

## 3. Page `Specsheet` (`?model_id=<model id>&season=<specsheet id>`, keduanya opsional)

Dari tombol **Specsheet** (Model List) / **Buka Specsheet** (Model Detail) → model & season langsung terpilih.
Dari sidebar (tanpa parameter) → pilih **Model** lalu **Season** di bagian atas page.

### 3a. JSObject
- `Auth`: `requiredPerm: 'view_specsheet'` dan
  ```js
  pageQueries() {
  	return [{ run: () => SpecCtrl.init() }];
  },
  ```
  (`SpecCtrl.init()` memuat daftar model, model & season dari URL kalau ada, lalu revisinya.)
- Buat **`SpecCtrl`** → tempel `js/SpecCtrl.js`.
- Buat **`BomCtrl`** → tempel `js/BomCtrl.js`.

### 3b. Query baca

**`q_spec_models`** (pilihan model)
```sql
SELECT id, code, name
FROM product_model
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_specsheet')) IS NOT NULL
ORDER BY code;
```

**`q_spec_model`** (dijalankan `SpecCtrl.loadModel()` dengan params)
```sql
SELECT id, code, name, category, factory, outsole_mold, last_no, construction, size_range, sample_size
FROM product_model
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_specsheet')) IS NOT NULL
  AND id::text = {{this.params.model_id || ''}};
```

**`q_spec_seasons`** (season terbaru dulu; jumlah revisi yang boleh dilihat; revisi terbit terakhir = sumber copy)
```sql
SELECT s.id, s.season, s.season_sort,
       (SELECT count(*)::int FROM specsheet_revision r
         WHERE r.specsheet_id = s.id
           AND (r.status = 'PUBLISHED'
                OR (SELECT fn_has_perm(fn_auth({{appsmith.store.token}}, 'view_specsheet'), 'view_drafts')))) AS revision_count,
       lp.id AS latest_pub_id, lp.stage || ' r' || lp.revision_no AS latest_pub_label
FROM specsheet s
LEFT JOIN LATERAL (
  SELECT r.id, r.stage, r.revision_no FROM specsheet_revision r
   WHERE r.specsheet_id = s.id AND r.status = 'PUBLISHED'
   ORDER BY r.stage_order DESC, r.revision_no DESC LIMIT 1
) lp ON true
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_specsheet')) IS NOT NULL
  AND s.model_id::text = {{this.params.model_id || ''}}
ORDER BY s.season_sort DESC;
```

**`q_revisions`** (Brand hanya revisi terbit)
```sql
SELECT r.id, r.stage, r.stage_order, r.revision_no, r.status, r.source_revision_id,
       r.published_at, r.published_by, r.created_at, r.created_by,
       src.stage || ' r' || src.revision_no AS source_label, srcsp.season AS source_season
FROM specsheet_revision r
LEFT JOIN specsheet_revision src ON src.id = r.source_revision_id
LEFT JOIN specsheet srcsp ON srcsp.id = src.specsheet_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_specsheet')) IS NOT NULL
  AND r.specsheet_id::text = {{this.params.specsheet_id || ''}}
  AND (r.status = 'PUBLISHED'
       OR (SELECT fn_has_perm(fn_auth({{appsmith.store.token}}, 'view_specsheet'), 'view_drafts')))
ORDER BY r.stage_order, r.revision_no;
```

**`q_rev_articles`** (semua article season + statusnya di revisi: ACTIVE / DROPPED / kosong = belum masuk)
```sql
SELECT a.id, a.code, a.colorway, ra.status AS rev_status
FROM article a
LEFT JOIN revision_article ra ON ra.article_id = a.id AND ra.revision_id::text = {{this.params.revision_id || ''}}
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_specsheet')) IS NOT NULL
  AND a.specsheet_id::text = {{this.params.specsheet_id || ''}}
ORDER BY a.code;
```

**`q_bom_grid`** (draft tidak terbaca oleh Brand)
```sql
SELECT g.*
FROM v_bom_grid g
JOIN specsheet_revision r ON r.id = g.revision_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_specsheet')) IS NOT NULL
  AND g.revision_id::text = {{this.params.revision_id || ''}}
  AND (r.status = 'PUBLISHED'
       OR (SELECT fn_has_perm(fn_auth({{appsmith.store.token}}, 'view_specsheet'), 'view_drafts')))
ORDER BY g.group_no NULLS LAST, g.group_sort, g.is_sub, g.sub_seq;
```

**`q_bom_options`** (saran isian grid: komponen APPROVED, material non-INACTIVE, supplier aktif, link material-supplier)
```sql
SELECT
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'number', c.number, 'name', c.name) ORDER BY c.number), '[]'::jsonb)
     FROM component c WHERE c.status = 'APPROVED') AS components,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'code', m.material_code, 'name', m.name, 'uom', m.uom,
                                                'thickness', m.thickness, 'status', m.status) ORDER BY m.material_code), '[]'::jsonb)
     FROM material m WHERE m.status <> 'INACTIVE') AS materials,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) ORDER BY s.name_key), '[]'::jsonb)
     FROM supplier s WHERE s.status <> 'INACTIVE') AS suppliers,
  (SELECT coalesce(jsonb_agg(jsonb_build_object('material_id', ms.material_id, 'supplier_id', ms.supplier_id,
                                                'is_preferred', ms.is_preferred, 'status', ms.status)), '[]'::jsonb)
     FROM material_supplier ms) AS links
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'edit_specsheet')) IS NOT NULL;
```

**`q_season_colors`** (saran warna: semua warna yang pernah dipakai di season yang sama)
```sql
SELECT min(btrim(regexp_replace(bc.color, '\s+', ' ', 'g'))) AS color
FROM bom_cell bc
JOIN bom_line bl ON bl.id = bc.bom_line_id
JOIN specsheet_revision sr ON sr.id = bl.revision_id
JOIN specsheet sp ON sp.id = sr.specsheet_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_specsheet')) IS NOT NULL
  AND sp.season = {{this.params.season || ''}} AND bc.is_used
GROUP BY fn_normalize(bc.color)
ORDER BY 1;
```

### 3c. Query tulis

**`a_revision_create`**
```sql
SELECT fn_revision_create({{appsmith.store.token}}, {{this.params.specsheet_id}}::uuid, {{this.params.mode}},
                          {{this.params.stage}}, nullif({{this.params.source_id}}, '')::uuid) AS id;
```

**`a_revision_delete`** — *Request confirmation before running* = **ON**
```sql
SELECT fn_revision_delete_draft({{appsmith.store.token}}, {{this.params.id}}::uuid) AS id;
```

**`a_bom_add_line`**
```sql
SELECT fn_bom_add_line({{appsmith.store.token}}, {{this.params.revision_id}}::uuid,
                       nullif({{this.params.component_id}}, '')::uuid, nullif({{this.params.local_no}}, '')::integer,
                       {{this.params.local_name}}, {{this.params.material_id}}::uuid,
                       nullif({{this.params.supplier_id}}, '')::uuid, {{this.params.process}}) AS id;
```

**`a_bom_add_sub`**
```sql
SELECT fn_bom_add_sub({{appsmith.store.token}}, {{this.params.parent_id}}::uuid, {{this.params.sub_name}},
                      {{this.params.material_id}}::uuid, nullif({{this.params.supplier_id}}, '')::uuid,
                      {{this.params.process}}) AS id;
```

**`a_bom_replace_material`**
```sql
SELECT fn_bom_replace_material({{appsmith.store.token}}, {{this.params.line_id}}::uuid,
                               {{this.params.material_id}}::uuid) AS id;
```

**`a_bom_set_supplier`**
```sql
SELECT fn_bom_set_supplier({{appsmith.store.token}}, {{this.params.line_id}}::uuid,
                           nullif({{this.params.supplier_id}}, '')::uuid) AS id;
```

**`a_bom_set_process`**
```sql
UPDATE bom_line
   SET process = nullif(btrim({{this.params.process || ''}}), ''),
       updated_by = fn_auth({{appsmith.store.token}}, 'edit_specsheet')
 WHERE id = {{this.params.line_id}}::uuid AND is_active
RETURNING id;
```

**`a_cell_save`**
```sql
SELECT fn_bom_cell_set({{appsmith.store.token}}, {{this.params.line_id}}::uuid, {{this.params.article_id}}::uuid,
                       {{this.params.color}}) AS id;
```

**`a_rev_article_set`**
```sql
SELECT fn_rev_article_set({{appsmith.store.token}}, {{this.params.revision_id}}::uuid,
                          {{this.params.article_id}}::uuid, {{this.params.status}}) AS id;
```

### 3d. Widget (atas → bawah)

| Widget | Setelan |
|---|---|
| `cwHeader` | Salin dari **Model Detail**, `pageTitle: 'Specsheet'` |
| `btnKembali` | Label: `{{SpecCtrl.model() ? '← Model Detail' : '← Model List'}}`, style tertiary · onClick: `{{SpecCtrl.openModel()}}` |
| `selSpecModel` | Select, label `Model`, placeholder `Pilih model…`, *Filterable* **ON**, *Allow clearing* OFF · Source data: `{{SpecCtrl.modelOptions()}}` · Default selected value: `{{SpecCtrl.modelId}}` · onOptionChange: `{{SpecCtrl.pickModel(selSpecModel.selectedOptionValue)}}` |
| `txtSpecJudul` | Text: `{{SpecCtrl.headerText()}}` (HTML dirender) |
| `btnBukaCbd` | `Buka CBD →`, style secondary · Visible: `{{SpecCtrl.canViewCbd() && !!SpecCtrl.model()}}` · onClick: `{{SpecCtrl.openCbd()}}` |
| `selSpecSeason` | Select, label `Season`, placeholder `Belum ada season`, *Allow clearing* OFF · Source data: `{{SpecCtrl.seasonOptions()}}` · Default selected value: `{{SpecCtrl.seasonId}}` · onOptionChange: `{{SpecCtrl.pickSeason(selSpecSeason.selectedOptionValue)}}` |
| `btnBuatRevisi` | `+ Buat Revisi` · Visible: `{{SpecCtrl.canCreate()}}` · onClick: `{{SpecCtrl.openCreate()}}` |
| `cwStepper` | Custom Widget, lebar penuh, tinggi ±80 px · Default model: `{{SpecCtrl.stepperModel()}}` · event `onSelect`: `{{SpecCtrl.selectRevision()}}` · kode `widgets/cwStepper/` |
| `txtRevisi` | Text: `{{SpecCtrl.revisionText()}}` (HTML dirender) |
| `btnHapusDraft` | `Hapus Draft`, warna merah, style secondary · Visible: `{{SpecCtrl.editable()}}` · onClick: `{{SpecCtrl.deleteDraft()}}` |
| `msArticleTambah` | MultiSelect, placeholder `Masukkan article ke revisi…` · Source data: `{{BomCtrl.addableOptions()}}` · Visible: `{{SpecCtrl.editable() && BomCtrl.addableOptions().length > 0}}` |
| `btnArticleTambah` | `Masukkan ke Revisi`, style secondary · Visible: sama dengan `msArticleTambah` · onClick: `{{BomCtrl.addArticles()}}` |
| `txtArticleInfo` | Text: `{{BomCtrl.articleNote()}}`, abu-abu kecil |
| `cwBomGrid` | Custom Widget, lebar penuh, tinggi **±600 px** (grid punya scroll sendiri) · Default model: `{{BomCtrl.gridModel()}}` · event `onAction`: `{{BomCtrl.onAction()}}` · kode `widgets/cwBomGrid/` |

Semua isian grid (tambah baris, subkomponen, ganti material, supplier, remarks, warna, drop article) lewat
`cwBomGrid` — lihat `widgets/cwBomGrid/README.md`. Tidak ada tombol Simpan: tiap sel tersimpan saat Enter/Tab/klik di luar.

### 3e. Modal `mdlRevisi` — Custom Widget `cwRevisionForm`

Modal lebar ±560 px, widget tinggi ±460 px. Kode `widgets/cwRevisionForm/`.

| Default model | `onSave` | `onCancel` |
|---|---|---|
| `{{SpecCtrl.revisionFormModel()}}` | `{{SpecCtrl.saveRevision()}}` | `{{closeModal('mdlRevisi')}}` |

### 3f. Navigasi (sidebar)

`Specsheet` **tetap tampil** di sidebar (keputusan user 30 Sep 2026): dibuka dari sidebar → pilih model & season di page.

Lalu **Deploy**.

---

## 4. Uji

Akun: **Vendor – Specsheet** (mengisi), **Master Admin**, **Brand Viewer**. Siapkan di Master: komponen APPROVED
`10 - Vamp`, `20 - Quarter`; material APPROVED 2–3 buah (satu dengan supplier utama); satu material INACTIVE.
Model `ILZ-01` dengan season `FH25` (2 article) dan `SS26` (3 article).

Navigasi
- [ ] Buka **Specsheet** dari sidebar → Model kosong, teks *Pilih model dan season di atas.*, stepper *Pilih model dulu.*, tombol kembali `← Model List`
- [ ] Pilih model (ketik untuk mencari) → season terbaru terpilih otomatis, revisinya terbuka; ganti Season → revisi season itu
- [ ] Dari Model List tombol **Specsheet** / Model Detail **Buka Specsheet** → model & season yang sama langsung terpilih
- [ ] URL dengan `model_id` yang salah → peringatan *Model tidak ditemukan…*, pilihan model kosong

Status di Model List / Model Detail
- [ ] Sebelum ada revisi: Model List kolom Specsheet *Belum ada specsheet*; Model Detail kolom Specsheet *BELUM MASUK SPECSHEET*

Revisi pertama (Specsheet, season FH25)
- [ ] Brand: stepper kosong *Belum ada revisi yang terbit*, tidak ada tombol Buat Revisi
- [ ] Vendor Spec: **+ Buat Revisi** → pilihan **Mulai kosong** / **Copy dari season lain** (nonaktif: belum ada sumber) → Mulai kosong, stage PULL → chip `r0` kuning (draft) di PULL, 2 kolom article
- [ ] **+ Buat Revisi** tidak tampil lagi selama ada draft

Grid BOM (draft FH25 PULL r0)
- [ ] Baris tambah: ketik `10` → komponen master (No. nonaktif); material pilih dari daftar → supplier utama terisi otomatis → **+ Tambah** → baris `10 Vamp`, form kosong lagi
- [ ] Komponen + material yang sama lagi → pesan merah *Komponen 10 + material ini sudah ada…*
- [ ] Komponen `Heel badge` (tidak ada di master) → No. aktif; No. `30` → *tidak boleh kelipatan 10*; `35` → baris `35 Heel badge` label **lokal**
- [ ] Komponen `99` → *Komponen nomor 99 tidak ada di master…*; material `xyz` → *…tidak ada di master*
- [ ] **+ Sub** di baris 10 → nama `Lining`, material → baris `10-1 ↳ Lining` di bawah baris 10
- [ ] Sel warna: ketik `Black` + Enter → tersimpan, fokus turun ke baris berikutnya; ketik `bl` → saran `Black` muncul
- [ ] Supplier diganti ke supplier yang belum terdaftar untuk material itu → badge **usulan**; di Material Detail supplier itu muncul PROPOSED
- [ ] Supplier yang link-nya INACTIVE → ditolak *…sudah dinonaktifkan untuk material…*
- [ ] Remarks diisi → tersimpan (muat ulang page, masih ada)
- [ ] **Ganti material** baris 10 (ketik material lain di kolom Material) → baris tetap `10 Vamp` dengan material baru, warna & supplier ikut, subkomponen `10-1` tetap di bawahnya (P4)
- [ ] Material INACTIVE tidak ada di saran; diketik manual → ditolak
- [ ] Header article **✕** → berubah **Drop?** → klik lagi → kolom hilang, info *di-drop: …*; **Masukkan ke Revisi** article itu → kolom kembali (warna lama tetap)

Hapus draft & copy — langkah lengkap ada di **§4b** di bawah.

---

## 4b. Uji lengkap: hapus draft, terbit (sementara lewat DB Tools), copy, revisi berikutnya

**Keadaan awal** (setelah uji Grid BOM di atas): model `ILZ-01`, season **FH25** punya draft `PULL r0` berisi beberapa
baris; season **SS26** belum punya revisi. Login sebagai **Vendor – Specsheet** kecuali disebut lain.
Semua query di bawah dijalankan di app **DB Tools** (`z_run_sql`).

**Q-cek** — query bantu untuk melihat isi semua revisi `ILZ-01` (dipakai berulang):
```sql
SELECT s.season, r.stage, r.revision_no, r.status,
       src_s.season || ' ' || src.stage || ' r' || src.revision_no AS sumber,
       (SELECT count(*) FROM bom_line l WHERE l.revision_id = r.id AND l.is_active) AS baris,
       (SELECT count(*) FROM revision_article a WHERE a.revision_id = r.id AND a.status = 'ACTIVE') AS article_aktif,
       (SELECT count(*) FROM bom_cell c JOIN bom_line l ON l.id = c.bom_line_id
         WHERE l.revision_id = r.id AND l.is_active AND c.color IS NOT NULL) AS sel_berwarna
FROM specsheet_revision r
JOIN specsheet s ON s.id = r.specsheet_id
JOIN product_model m ON m.id = s.model_id
LEFT JOIN specsheet_revision src ON src.id = r.source_revision_id
LEFT JOIN specsheet src_s ON src_s.id = src.specsheet_id
WHERE m.code = 'ILZ-01'
ORDER BY s.season_sort, r.stage_order, r.revision_no;
```

### A. Hapus draft

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| A1 | DB Tools: jalankan **Q-cek** | 1 baris: `FH25 · PULL · 0 · DRAFT`, `baris` > 0 |
| A2 | Specsheet → model `ILZ-01`, season `FH25` → **Hapus Draft** → di dialog konfirmasi pilih **Cancel** | Tidak ada yang berubah, draft masih ada (boleh muncul toast "dibatalkan") |
| A3 | **Hapus Draft** lagi → **Confirm** | Toast *Draft PULL r0 dihapus.*; stepper *Belum ada revisi. Klik "+ Buat Revisi".*; grid kosong; **Hapus Draft** hilang; **+ Buat Revisi** muncul |
| A4 | DB Tools: **Q-cek** | 0 baris |
| A5 | Model Detail `ILZ-01` → season `FH25` | 2 article tetap ada; kolom Specsheet *BELUM MASUK SPECSHEET*; tombol **Hapus** article muncul lagi (article belum dipakai) |

### B. Siapkan revisi sumber di FH25 lalu terbitkan

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| B1 | Specsheet `FH25` → **+ Buat Revisi** → **Mulai kosong**, stage `PULL` → **Buat** | Chip `r0` kuning bergaris putus di PULL; grid kosong dengan 2 kolom article |
| B2 | Isi grid: baris `10` (material A + supplier); **+ Sub** di baris 10, nama `Lining` (material B); baris lokal `Heel badge` No. `35` (material C). Warna: baris 10 → `Black` / `White`, baris 10-1 → `Black` / `Black`, baris 35 → `Gold` / kosong. Remarks baris 10 → `Emboss` | Urutan `10`, `10-1`, `35`; reload page → isi sama |
| B3 | Pindah ke season `SS26` → **+ Buat Revisi** | **Copy dari season lain** **nonaktif**, teks *Belum ada season lain model ini yang punya revisi terbit* (FH25 masih draft) → **Batal** |
| B4 | DB Tools: terbitkan draft FH25 (query di bawah; F6 belum ada) | `1 row affected` |

```sql
UPDATE specsheet_revision SET status = 'PUBLISHED', published_at = now(), published_by = 'uji'
 WHERE status = 'DRAFT' AND specsheet_id = (SELECT s.id FROM specsheet s JOIN product_model m ON m.id = s.model_id
                                             WHERE m.code = 'ILZ-01' AND s.season = 'FH25');
```

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| B5 | Reload page Specsheet, pilih `ILZ-01` / `FH25` | Chip `r0` biru terisi (terbit); info *PUBLISHED · terbit … oleh uji*; grid **hanya baca** (tidak ada input, baris **+ Tambah**, **+ Sub**, **✕** di header article); **Hapus Draft** & **Masukkan ke Revisi** tidak tampil; **+ Buat Revisi** tampil |
| B6 | DB Tools: coba ubah baris revisi terbit (query di bawah) — **harus error** | *Revisi ini sudah diterbitkan dan tidak bisa diubah…* |

```sql
UPDATE bom_line SET process = 'x'
 WHERE revision_id = (SELECT r.id FROM specsheet_revision r JOIN specsheet s ON s.id = r.specsheet_id
                       JOIN product_model m ON m.id = s.model_id
                      WHERE m.code = 'ILZ-01' AND s.season = 'FH25' AND r.status = 'PUBLISHED' LIMIT 1);
```

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| B7 | DB Tools: coba hapus revisi terbit (query di bawah) — **harus error** | *Revisi PULL r0 sudah diterbitkan dan tidak bisa diubah atau dihapus.* |

```sql
DELETE FROM specsheet_revision
 WHERE id = (SELECT r.id FROM specsheet_revision r JOIN specsheet s ON s.id = r.specsheet_id
              JOIN product_model m ON m.id = s.model_id
             WHERE m.code = 'ILZ-01' AND s.season = 'FH25' AND r.status = 'PUBLISHED' LIMIT 1);
```

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| B8 | Model Detail `FH25` | Kolom Specsheet kedua article *AKTIF · PULL r0 terbit* (hijau); tombol **Hapus** article tidak tampil; **Ubah** article → kode **terkunci** dengan catatan *Kode tidak bisa diubah…*, colorway tetap bisa diubah (uji F4 yang ditunda) |
| B9 | Model List → filter season `FH25` → **Cari** | Kolom Specsheet `PULL r0 · PUBLISHED · 2 article aktif` |

### C. Copy specsheet ke SS26 (model sama)

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| C1 | Specsheet `SS26` → **+ Buat Revisi** | **Mulai kosong** dan **Copy dari season lain (model sama)** (aktif); tidak ada Revisi/Stage berikutnya |
| C2 | Pilih **Copy…**, ubah Season sumber ke `— pilih season —` → **Buat** | Pesan merah *Pilih season sumber.*, modal tetap terbuka |
| C3 | Season sumber `FH25 — PULL r0 terbit`, stage `PULL` → **Buat** | Toast *Revisi draft dibuat.*; chip `r0` kuning di PULL; info *… DRAFT … sumber: FH25 PULL r0* |
| C4 | Lihat grid SS26 | Baris sama dengan FH25: `10` (material A, supplier sama, remarks `Emboss`), `10-1 ↳ Lining`, `35 Heel badge` **lokal**; kolom = **3 article SS26**; **semua warna kosong** |
| C5 | DB Tools: **Q-cek** | `SS26 · PULL · 0 · DRAFT`, sumber `FH25 PULL r0`, `baris` = 3, `article_aktif` = 3, `sel_berwarna` = 0 |
| C6 | DB Tools: cek line_key baru & induk subkomponen (query di bawah) | 3 baris; semua `key_baru` = true, `origin_ok` = true; baris `Lining`: `induk_baru` = true |

```sql
SELECT coalesce(n.sub_name, n.local_component_name, '(komponen master)') AS baris,
       n.line_key <> o.line_key AS key_baru, n.origin_line_key = o.line_key AS origin_ok,
       CASE WHEN n.parent_line_key IS NULL THEN NULL
            ELSE EXISTS (SELECT 1 FROM bom_line p WHERE p.revision_id = n.revision_id AND p.line_key = n.parent_line_key) END AS induk_baru
FROM bom_line n
JOIN bom_line o ON o.line_key = n.origin_line_key
WHERE n.revision_id = (SELECT r.id FROM specsheet_revision r JOIN specsheet s ON s.id = r.specsheet_id
                        JOIN product_model m ON m.id = s.model_id
                       WHERE m.code = 'ILZ-01' AND s.season = 'SS26' AND r.status = 'DRAFT');
```

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| C7 | Isi warna `Navy` di baris 10, article pertama SS26 → pindah ke season `FH25` | FH25 `r0` tidak berubah (baris 10 tetap `Black` / `White`) — hasil copy tidak terhubung ke sumber |
| C8 | Kembali ke `SS26` | **+ Buat Revisi** tidak tampil (sudah ada draft) |
| C9 | Model Detail `SS26` | 3 article *DI DRAFT · PULL r0* (kuning); tombol **Hapus** tidak tampil; kode terkunci di form Ubah |

### D. Revisi berikutnya & stage berikutnya (FH25)

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| D1 | Specsheet `FH25` → **+ Buat Revisi** | **Revisi berikutnya: PULL r1** (*Salin PULL r0 …*) dan **Stage berikutnya: SMS r0**; tidak ada Mulai kosong / Copy |
| D2 | Pilih **Revisi berikutnya** → **Buat** | Chip `r1` kuning di PULL sebelah `r0`; grid bisa diedit, baris + **warna sama** dengan r0; info *sumber: FH25 PULL r0* |
| D3 | DB Tools: **Q-cek** | `FH25 · PULL · 1 · DRAFT`, `baris` = 3, `article_aktif` = 2, `sel_berwarna` sama dengan `FH25 PULL 0` |
| D4 | Di r1 ganti warna baris 10 → `Red` → klik chip `r0` | r0 (hanya baca) tetap `Black`; klik chip `r1` → `Red` |
| D5 | Di r1 → **Hapus Draft** → **Confirm** | Chip `r1` hilang, `r0` otomatis terbuka |
| D6 | **+ Buat Revisi** → **Stage berikutnya: SMS r0** → **Buat** | Stage SMS punya chip `r0` kuning dan bergaris bawah (stage aktif); chip PULL `r0` tetap |
| D7 | DB Tools: **Q-cek** | `FH25 · SMS · 0 · DRAFT`, sumber `FH25 PULL r0`, isi sama dengan PULL r0 |

Biarkan draft **FH25 SMS r0** dan **SS26 PULL r0** — dipakai untuk uji role di bawah dan uji Terbitkan di F6.

### E. Hak akses per role

| # | Akun | Langkah | Hasil yang diharapkan |
|---|---|---|---|
| E1 | Brand Viewer | Specsheet `ILZ-01` / `FH25` | Pilihan season `FH25 (1 revisi)`, `SS26 (0 revisi)`; stepper hanya `PULL r0` (draft SMS **tidak** terlihat); grid hanya baca; tidak ada tombol ubah |
| E2 | Brand Viewer | Season `SS26` | Stepper *Belum ada revisi yang terbit.*; grid kosong |
| E3 | Brand Viewer | Model List (tanpa filter) · lalu filter `FH25` | Tanpa filter (season terbaru SS26): *Belum ada specsheet* · filter FH25: `PULL r0 · PUBLISHED · 2 article aktif` |
| E4 | Brand Viewer | Model Detail `FH25` | Kolom Specsheet *AKTIF · PULL r0 terbit* (draft SMS tidak disebut) |
| E5 | Vendor – Specsheet | Model List filter `FH25` | `SMS r0 · DRAFT · 2 article aktif` (revisi terakhir = urut stage, P2) |
| E6 | Master Admin | Specsheet `FH25` | Chip `PULL r0` dan `SMS r0` (draft terlihat); grid hanya baca; **+ Buat Revisi** / **Hapus Draft** tidak tampil |
| E7 | Vendor – CBD | Specsheet `FH25` | Sama dengan Master Admin; tombol **Buka CBD →** tampil |

### F. Audit log

| # | Akun | Langkah | Hasil yang diharapkan |
|---|---|---|---|
| F1 | System Admin | Admin → Audit Log → entitas `specsheet_revision` | `INSERT` untuk setiap revisi yang dibuat (FH25 PULL r0 ×2, SS26 PULL r0, FH25 PULL r1, FH25 SMS r0); `DELETE` untuk dua draft yang dihapus; `UPDATE` status DRAFT → PUBLISHED dari DB Tools (user tercatat = pengubah terakhir revisi itu, karena query DB Tools tidak lewat login; di F6 terbit lewat app mencatat user yang menerbitkan) |
| F2 | System Admin | Entitas `bom_line` / `bom_cell` | `INSERT` / `UPDATE` oleh email Vendor – Specsheet; `DELETE` saat draft dihapus |
| F3 | System Admin | Entitas `revision_article` | `INSERT` saat revisi dibuat; `UPDATE` saat article di-drop / diaktifkan lagi |

---

## 5. Export

Export app → `appsmith/exports/export_v5.json` → kirim di chat bersama hasil query cek skema (PLAN.md §8) dan uji yang gagal (kalau ada).

---

## 6. Perbaikan setelah review export v5 (30 Sep 2026)

### 6a. T28 — query baca Specsheet ke Manual
Page `Specsheet`: `q_spec_models`, `q_spec_model`, `q_spec_seasons`, `q_revisions`, `q_rev_articles`, `q_bom_grid`,
`q_bom_options`, `q_season_colors` → *Run behaviour* **Manual** (sekarang *Automatic*: ikut jalan tanpa params saat
page dibuka dan bisa mengosongkan grid/stepper setelah `SpecCtrl.init()` selesai — sama dengan T22).

### 6b. Grid BOM hanya tampil kalau ada revisi yang dibuka
`cwBomGrid` → Visible: `{{!!SpecCtrl.revision()}}`

### 6c. Tombol kembali sesuai asal halaman
- JSObject `ModelCtrl` (Model List) dan `ModelDetailCtrl` (Model Detail) → tempel ulang dari `js/`
  (tombol Specsheet/CBD mengirim `from: 'list'` / `from: 'detail'`).
- JSObject `SpecCtrl` → tempel ulang `js/SpecCtrl.js` (fungsi baru `backLabel()`, teks *Pilih model dan season dahulu.* sudah ikut).
- `btnKembali` → Label: `{{SpecCtrl.backLabel()}}` (hapus juga karakter Tab di akhir label lama).

| Dibuka dari | Tombol kembali |
|---|---|
| Model List (tombol **Specsheet**) | `← Model List` |
| Model Detail (**Buka Specsheet**) | `← Model Detail` |
| Sidebar, model sudah dipilih | `← Model Detail` |
| Sidebar, model belum dipilih | `← Model List` |

### 6d. F5b — hapus baris BOM (permintaan user; tidak ada di Python)
1. DB Tools → `z_run_sql` → tempel `sql/F5b_bom_delete.sql` → Run.
2. Query baru **`a_bom_delete_line`** (prepared ON, Manual):
   ```sql
   SELECT fn_bom_delete_line({{appsmith.store.token}}, {{this.params.line_id}}::uuid) AS deleted;
   ```
3. JSObject `BomCtrl` → tempel ulang `js/BomCtrl.js` (aksi `deleteLine`).
4. `cwBomGrid` → tempel ulang **JavaScript** dan **Style** dari `widgets/cwBomGrid/` (tombol **Hapus** di kolom aksi,
   konfirmasi klik dua kali: **Yakin?** / **Hapus + sub?**).

Lalu **Deploy**.

### 6e. Uji
- [ ] Specsheet dibuka dari sidebar tanpa model → grid tidak tampil; pilih model yang belum punya revisi → grid tetap tidak tampil; buka revisi → grid tampil
- [ ] Reload page Specsheet berkali-kali → stepper & grid selalu terisi (tidak kosong mendadak) — T28
- [ ] Model List → **Specsheet** → tombol `← Model List` → kembali ke Model List
- [ ] Model Detail → **Buka Specsheet** → tombol `← Model Detail` → kembali ke model & season yang sama
- [ ] Sidebar → Specsheet → pilih model → tombol `← Model Detail`
- [ ] Draft: klik **Hapus** di baris tanpa subkomponen → **Yakin?** → tunggu 3 detik → kembali **Hapus** (batal); klik dua kali → baris hilang
- [ ] Baris induk yang punya subkomponen → **Hapus + sub?** → klik lagi → induk & subkomponennya hilang
- [ ] Hapus subkomponen saja → induk tetap
- [ ] Hapus baris komponen lokal No. `35`, lalu tambah lagi komponen lokal No. `35` → berhasil (nomor bebas lagi)
- [ ] Revisi terbit: grid hanya baca, tidak ada tombol Hapus (DB juga menolak lewat `trg_lock_published`, sudah diuji di B6)
- [ ] Audit Log `bom_line`: `DELETE` oleh email Vendor – Specsheet

Export ulang → simpan sebagai `export_v5.json` (menimpa) → kirim di chat.
