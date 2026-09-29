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

Hapus draft & copy
- [ ] **Hapus Draft** (konfirmasi) → stepper kosong lagi, article di Model Detail tetap ada
- [ ] Buat lagi draft FH25 berisi beberapa baris, lalu terbitkan lewat DB Tools (F6 belum ada):
  ```sql
  UPDATE specsheet_revision SET status = 'PUBLISHED', published_at = now(), published_by = 'uji'
   WHERE status = 'DRAFT' AND specsheet_id = (SELECT s.id FROM specsheet s JOIN product_model m ON m.id = s.model_id
                                               WHERE m.code = 'ILZ-01' AND s.season = 'FH25');
  ```
- [ ] Reload: chip `r0` FH25 biru (terbit), grid **hanya baca**; coba ubah via DB Tools `UPDATE bom_line SET process = 'x'` pada revisi itu → ditolak *Revisi ini sudah diterbitkan…*
- [ ] Season **SS26** → **+ Buat Revisi** → **Copy dari season lain** → sumber `FH25 — PULL r0 terbit`, stage PULL → baris BOM sama dengan FH25, kolom = 3 article SS26, **warna kosong**
- [ ] Model Detail SS26: kode article yang sudah masuk revisi → tombol Hapus hilang, form Ubah: kode terkunci (uji F4 yang ditunda)
- [ ] Kembali ke FH25 (sudah terbit) → **+ Buat Revisi** → pilihan **Revisi berikutnya: PULL r1** / **Stage berikutnya: SMS r0** → Revisi berikutnya → `r1` draft berisi baris + warna yang sama
- [ ] Brand: FH25 hanya `r0` (terbit), draft `r1` tidak terlihat; grid hanya baca; Model List kolom Specsheet menampilkan revisi terbit
- [ ] Master Admin: bisa melihat draft, tidak ada tombol ubah (hanya Vendor – Specsheet yang `edit_specsheet`)
- [ ] Admin → Audit Log: entri `specsheet_revision`, `revision_article`, `bom_line`, `bom_cell`

---

## 5. Export

Export app → `appsmith/exports/export_v5.json` → kirim di chat bersama hasil query cek skema (PLAN.md §8) dan uji yang gagal (kalau ada).
