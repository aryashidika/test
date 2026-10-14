# F4 - Model, Season, Article, lampiran: langkah di Appsmith

Urutan: **0** sisa F3 → **1** SQL → **2** Model List → **3** Model Detail → **4** uji → **5** export `export_v4.json`.

Setelan untuk **semua query baru** (datasource `Prestasi`): *Use prepared statements* **ON**, *Run behaviour* **Manual**.
Form modal = Custom Widget (pola sama dengan `cwMaterialForm`): modal tanpa judul/tombol bawaan, Custom Widget
mengisi modal, tempel HTML/CSS/JS dari `widgets/<cw>/`, isi Default model, buat event `onSave` & `onCancel`.
`cwHeader`: **salin dari Material Detail** (event `onLogout` sudah pola baru), ganti `pageTitle` saja.

Yang **belum** ada di F4 (tabelnya baru dibuat di fase berikut): ringkasan specsheet terakhir di Model List (F5),
status article di specsheet (F5) & CBD (F7). Kolomnya ditambahkan di fase itu. Tombol **Specsheet** / **CBD**
sudah dipasang, page tujuannya masih kosong sampai F5 / F7.

---

## 0. Sisa F3 / F3b

1. Kirim hasil **query cek skema** (PLAN.md §8) - untuk F3, F3b, dan sekalian F4 setelah langkah 1.
2. (Opsional, kosmetik T20) `Master Material`: label switch `swMaterialHargaPending` → `Harga menunggu approval`.

---

## 1. SQL

1. DB Tools → `z_run_sql` → tempel seluruh `sql/F4_model.sql` → Run.
2. Cek cepat:
   ```sql
   SELECT (SELECT count(*) FROM v_model_list) AS models, (SELECT count(*) FROM v_article_status) AS articles;
   ```
   Hasil `0 | 0` tanpa error.

---

## 2. Page `Model List`

### 2a. JSObject
- `Auth`: `requiredPerm: 'view_model'` dan
  ```js
  pageQueries() {
  	return [q_known_seasons, q_models];
  },
  ```
- Buat **`ModelCtrl`** → tempel `js/ModelCtrl.js`.

### 2b. Query

**`q_known_seasons`** (pilihan filter season)
```sql
SELECT DISTINCT season, season_sort
FROM specsheet
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_model')) IS NOT NULL
ORDER BY season_sort DESC;
```

**`q_models`** - tanpa filter season: satu baris per model dengan season terbarunya; dengan filter: model yang punya season itu.
```sql
SELECT id, code, name, category, factory, size_range, season_count::int AS season_count,
       specsheet_id, season, article_count::int AS article_count, updated_at
FROM v_model_list
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_model')) IS NOT NULL
  AND (CASE WHEN {{selModelSeason.selectedOptionValue || ''}} = '' THEN is_latest_season
            ELSE season = {{selModelSeason.selectedOptionValue || ''}} END)
  AND ({{inpModelCari.text || ''}} = ''
       OR code ILIKE '%' || {{inpModelCari.text || ''}} || '%'
       OR name ILIKE '%' || {{inpModelCari.text || ''}} || '%')
ORDER BY code
LIMIT 500;
```

**`a_model_add`**
```sql
INSERT INTO product_model (code, name, category, factory, outsole_mold, last_no, construction,
                           size_range, sample_size, updated_by)
SELECT {{this.params.code}}, {{this.params.name}}, {{this.params.category}}, {{this.params.factory}},
       {{this.params.outsole_mold}}, {{this.params.last_no}}, {{this.params.construction}},
       {{this.params.size_range}}, {{this.params.sample_size}}, fn_auth({{appsmith.store.token}}, 'edit_model')
RETURNING id;
```

### 2c. Widget

| Widget | Setelan |
|---|---|
| `cwHeader` | Salin dari **Material Detail**, `pageTitle: 'Model List'` |
| `inpModelCari` | Input, placeholder `Cari kode / nama model…` |
| `selModelSeason` | Select, placeholder `Season terbaru`, Default kosong, *Allow clearing* ON · Source data: `{{ModelCtrl.seasonOptions()}}` |
| `btnModelCari` | `Cari` · onClick: `{{q_models.run()}}` |
| `btnModelTambah` | `+ Tambah Model` · Visible: `{{ModelCtrl.canEdit()}}` · onClick: `{{ModelCtrl.openAdd()}}` |
| `tblModels` | Table data: `{{q_models.data}}` |

Kolom `tblModels` - sembunyikan `id`, `specsheet_id`, `season_count`, `article_count`:

| Kolom | Label | Setelan |
|---|---|---|
| `code` | Kode | bold |
| `name` | Nama | – |
| `category` | Kategori | – |
| `factory` | Factory | – |
| `size_range` | Size Range | – |
| `season` | Season | Column type Text · Computed value: `{{ModelCtrl.seasonSummary(currentRow)}}` |
| `updated_at` | Diubah | Computed value: `{{Util.fmtDateTime(currentRow.updated_at)}}` |
| *(baru)* Button `Buka` | – | onClick: `{{ModelCtrl.open(currentRow)}}` |
| *(baru)* Button `Specsheet` | – | onClick: `{{ModelCtrl.openSpecsheet(currentRow)}}` |
| *(baru)* Button `CBD` | – | onClick: `{{ModelCtrl.openCbd(currentRow)}}` · Visible (kolom): `{{ModelCtrl.canViewCbd()}}` |

### 2d. Modal `mdlModel` - Custom Widget `cwModelForm`

Modal lebar ±560 px; `cwModelForm` tinggi ±640 px. Kode: `widgets/cwModelForm/`.

Default model:
```js
{{ {
  key: ModelCtrl.formKey,
  mode: 'add',
  form: ModelCtrl.form,
  busy: ModelCtrl.busy,
  message: ModelCtrl.message
} }}
```

| Event | Action |
|---|---|
| `onSave` | `{{ModelCtrl.save()}}` |
| `onCancel` | `{{closeModal('mdlModel')}}` |

Setelah tersimpan, page pindah ke **Model Detail** model baru.

---

## 3. Page `Model Detail` (`?id=<model id>&season=<specsheet id>`)

### 3a. JSObject
- `Auth`: `requiredPerm: 'view_model'` dan (baris ketiga menjalankan `ModelDetailCtrl.init()` setelah season termuat: pilih season lalu muat article)
  ```js
  pageQueries() {
  	return [q_model, q_seasons, { run: () => ModelDetailCtrl.init() }];
  },
  ```
- Buat **`ModelDetailCtrl`** → tempel `js/ModelDetailCtrl.js`.

### 3b. Query

**`q_model`**
```sql
SELECT id, code, name, category, factory, outsole_mold, last_no, construction, size_range, sample_size,
       updated_at, updated_by
FROM product_model
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_model')) IS NOT NULL
  AND id::text = {{appsmith.URL.queryParams.id || ''}};
```

**`q_seasons`** (season terbaru dulu)
```sql
SELECT s.id, s.season, s.season_sort, count(a.id)::int AS article_count
FROM specsheet s
LEFT JOIN article a ON a.specsheet_id = s.id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_model')) IS NOT NULL
  AND s.model_id::text = {{appsmith.URL.queryParams.id || ''}}
GROUP BY s.id
ORDER BY s.season_sort DESC;
```

**`q_articles`** (dijalankan `ModelDetailCtrl.loadArticles()` dengan params)
```sql
SELECT id, specsheet_id, code, colorway, attachment_count::int AS attachment_count, is_used, updated_at, updated_by
FROM v_article_status
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_model')) IS NOT NULL
  AND specsheet_id::text = {{this.params.specsheet_id || ''}}
ORDER BY code;
```

**`q_attachments`** (dijalankan `ModelDetailCtrl.loadAttachments()`; isi file tidak ikut)
```sql
SELECT id, file_name, mime_type, size_bytes, note, created_at, created_by
FROM article_attachment
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_model')) IS NOT NULL
  AND article_id::text = {{this.params.article_id || ''}}
ORDER BY created_at DESC;
```

**`q_attachment_file`** (isi satu file, untuk Lihat / Unduh)
```sql
SELECT file_name, mime_type, translate(encode(content, 'base64'), E'\n', '') AS b64
FROM article_attachment
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_model')) IS NOT NULL
  AND id = {{this.params.id}}::uuid;
```

**`a_model_update`**
```sql
UPDATE product_model
   SET code = {{this.params.code}}, name = {{this.params.name}}, category = {{this.params.category}},
       factory = {{this.params.factory}}, outsole_mold = {{this.params.outsole_mold}},
       last_no = {{this.params.last_no}}, construction = {{this.params.construction}},
       size_range = {{this.params.size_range}}, sample_size = {{this.params.sample_size}},
       updated_by = fn_auth({{appsmith.store.token}}, 'edit_model')
 WHERE id = {{this.params.id}}::uuid
RETURNING id;
```

**`a_season_add`**
```sql
INSERT INTO specsheet (model_id, season, updated_by)
SELECT {{this.params.model_id}}::uuid, {{this.params.season}}, fn_auth({{appsmith.store.token}}, 'edit_model')
RETURNING id;
```

**`a_article_add`**
```sql
INSERT INTO article (specsheet_id, code, colorway, updated_by)
SELECT {{this.params.specsheet_id}}::uuid, {{this.params.code}}, {{this.params.colorway}},
       fn_auth({{appsmith.store.token}}, 'edit_model')
RETURNING id;
```

**`a_article_update`**
```sql
UPDATE article
   SET code = {{this.params.code}}, colorway = {{this.params.colorway}},
       updated_by = fn_auth({{appsmith.store.token}}, 'edit_model')
 WHERE id = {{this.params.id}}::uuid
RETURNING id;
```

**`a_article_delete`** - *Request confirmation before running* = **ON** (lampiran article ikut terhapus)
```sql
DELETE FROM article
 WHERE id = {{this.params.id}}::uuid
   AND fn_auth({{appsmith.store.token}}, 'edit_model') IS NOT NULL
RETURNING id;
```

**`a_attachment_add`** - *Query timeout* **30000** ms (file besar)
```sql
SELECT fn_attachment_add({{appsmith.store.token}}, {{this.params.article_id}}::uuid, {{this.params.file_name}},
                         {{this.params.b64}}, {{this.params.note}}) AS id;
```

**`a_attachment_delete`** - *Request confirmation before running* = **ON**
```sql
DELETE FROM article_attachment
 WHERE id = {{this.params.id}}::uuid
   AND fn_auth({{appsmith.store.token}}, 'edit_model') IS NOT NULL
RETURNING id;
```

### 3c. Widget (atas → bawah)

| Widget | Setelan |
|---|---|
| `cwHeader` | Salin dari **Material Detail**, `pageTitle: 'Model Detail'` |
| `btnKembali` | Label `← Model List`, style tertiary · onClick: `{{navigateTo('Model List')}}` |
| `txtModelJudul` | Text: `{{ModelDetailCtrl.headerText()}}` (HTML dirender) |
| `btnBukaSpecsheet` | Label `Buka Specsheet →`, style secondary · Visible: `{{!!ModelDetailCtrl.model()}}` · onClick: `{{ModelDetailCtrl.openSpecsheet()}}` |
| `btnBukaCbd` | Label `Buka CBD →`, style secondary · Visible: `{{ModelDetailCtrl.canViewCbd() && !!ModelDetailCtrl.model()}}` · onClick: `{{ModelDetailCtrl.openCbd()}}` |
| `tabModel` | Tabs: **Season & Article** (default), **Info Model** |

Tab **Season & Article**:

| Widget | Setelan |
|---|---|
| `selSeason` | Select, label `Season`, placeholder `Belum ada season`, *Allow clearing* OFF · Source data: `{{ModelDetailCtrl.seasonOptions()}}` · Default selected value: `{{ModelDetailCtrl.seasonId}}` · onOptionChange: `{{ModelDetailCtrl.pickSeason(selSeason.selectedOptionValue)}}` |
| `btnSeasonTambah` | `+ Season Baru`, style secondary · Visible: `{{ModelDetailCtrl.canEdit() && !!ModelDetailCtrl.model()}}` · onClick: `{{ModelDetailCtrl.openAddSeason()}}` |
| `btnArticleTambah` | Label: `{{'+ Article (' + ModelDetailCtrl.articles().length + '/5)'}}` · Visible: `{{ModelDetailCtrl.canEdit() && !!ModelDetailCtrl.seasonId}}` · Disabled: `{{!ModelDetailCtrl.canAddArticle()}}` · onClick: `{{ModelDetailCtrl.openAddArticle()}}` |
| `tblArticles` | Table data: `{{q_articles.data}}` |
| `txtArticleNote` | Text: `{{ModelDetailCtrl.articleNote()}}`, warna abu-abu, ukuran kecil |

Kolom `tblArticles` - sembunyikan `id`, `specsheet_id`, `is_used`, `updated_by`:

| Kolom | Label | Setelan |
|---|---|---|
| `code` | Kode | bold |
| `colorway` | Colorway | – |
| `attachment_count` | Lampiran | Column type Text · Computed value: `{{currentRow.attachment_count ? currentRow.attachment_count + ' file' : '-'}}` |
| `updated_at` | Diubah | Computed value: `{{Util.fmtDateTime(currentRow.updated_at)}}` |
| *(baru)* Button `Lampiran` | – | onClick: `{{ModelDetailCtrl.openAttachments(currentRow)}}` |
| *(baru)* Button `Ubah` | – | onClick: `{{ModelDetailCtrl.openEditArticle(currentRow)}}` · Visible (kolom): `{{ModelDetailCtrl.canEdit()}}` |
| *(baru)* Button `Hapus` | – | Warna merah · onClick: `{{ModelDetailCtrl.deleteArticle(currentRow)}}` · Visible (kolom): `{{ModelDetailCtrl.canEdit()}}` · Cell visible: `{{!currentRow.is_used}}` |

Tab **Info Model**:

| Widget | Setelan |
|---|---|
| `txtModelInfo` | Text: `{{ModelDetailCtrl.infoText()}}` (HTML dirender) |
| `btnModelUbah` | `Ubah Model` · Visible: `{{ModelDetailCtrl.canEdit() && !!ModelDetailCtrl.model()}}` · onClick: `{{ModelDetailCtrl.openEditModel()}}` |

### 3d. Tiga modal form (Custom Widget)

| Modal | Custom Widget | Ukuran | Default model | `onSave` | `onCancel` |
|---|---|---|---|---|---|
| `mdlModel` | `cwModelForm` | lebar ±560, widget ±640 px | `{{ModelDetailCtrl.modelFormModel()}}` | `{{ModelDetailCtrl.saveModel()}}` | `{{closeModal('mdlModel')}}` |
| `mdlSeason` | `cwSeasonForm` | lebar ±480, widget ±400 px | `{{ModelDetailCtrl.seasonFormModel()}}` | `{{ModelDetailCtrl.saveSeason()}}` | `{{closeModal('mdlSeason')}}` |
| `mdlArticle` | `cwArticleForm` | lebar ±480, widget ±360 px | `{{ModelDetailCtrl.articleFormModel()}}` | `{{ModelDetailCtrl.saveArticle()}}` | `{{closeModal('mdlArticle')}}` |

Kode di `widgets/cwModelForm/` (sama dengan Model List), `widgets/cwSeasonForm/`, `widgets/cwArticleForm/`.

### 3e. Modal `mdlLampiran` (widget bawaan)

Modal lebar ±760 px, tinggi ±680 px, *close on outside click* boleh ON (tidak ada isian yang hilang).

| Widget | Setelan |
|---|---|
| `txtLampiranJudul` | Text: `{{ModelDetailCtrl.attachmentTitle()}}`, bold |
| `btnLampiranTutup` | Label `✕`, style tertiary · onClick: `{{closeModal('mdlLampiran')}}` |
| `inpLampiranCatatan` | Input, placeholder `Catatan (opsional) - isi sebelum memilih file` · Visible: `{{ModelDetailCtrl.canEdit()}}` |
| `fpLampiran` | FilePicker, label `Pilih & unggah file` · *Allowed file types* (JS): `{{['.jpg', '.jpeg', '.png', '.pdf']}}` · *Data format* **Base64** · *Max no. of files* **1** · *Max file size* **5** MB · onFilesSelected: `{{ModelDetailCtrl.upload()}}` · Visible: `{{ModelDetailCtrl.canEdit()}}` · Disabled: `{{ModelDetailCtrl.fileBusy}}` |
| `txtLampiranInfo` | Text: `JPG, PNG, atau PDF, maks. 5 MB. Gambar: Lihat = pratinjau di bawah; PDF: diunduh.`, abu-abu kecil |
| `tblLampiran` | Table data: `{{q_attachments.data}}` |
| `txtPreviewNama` | Text: `{{ModelDetailCtrl.preview ? 'Pratinjau: ' + ModelDetailCtrl.preview.name : ''}}` · Visible: `{{!!ModelDetailCtrl.preview}}` |
| `imgLampiran` | Image, tinggi ±280 px · Image: `{{ModelDetailCtrl.preview ? ModelDetailCtrl.preview.url : ''}}` · Object fit **Contain** · Visible: `{{!!ModelDetailCtrl.preview}}` |

Kolom `tblLampiran` - sembunyikan `id`:

| Kolom | Label | Setelan |
|---|---|---|
| `file_name` | Nama file | – |
| `mime_type` | Jenis | Computed value: `{{ModelDetailCtrl.fileType(currentRow.mime_type)}}` |
| `size_bytes` | Ukuran | Column type Text · Computed value: `{{ModelDetailCtrl.fmtSize(currentRow.size_bytes)}}` |
| `note` | Catatan | – |
| `created_by` | Oleh | – |
| `created_at` | Diunggah | Computed value: `{{Util.fmtDateTime(currentRow.created_at)}}` |
| *(baru)* Button `Lihat` | – | onClick: `{{ModelDetailCtrl.view(currentRow)}}` |
| *(baru)* Button `Unduh` | – | onClick: `{{ModelDetailCtrl.download(currentRow)}}` |
| *(baru)* Button `Hapus` | – | Warna merah · onClick: `{{ModelDetailCtrl.deleteAttachment(currentRow)}}` · Visible (kolom): `{{ModelDetailCtrl.canEdit()}}` |

Lalu **Deploy**.

---

## 4. Uji

Akun: **Master Admin**, **Vendor – Specsheet**, **Vendor – CBD**, **Brand Viewer**. Siapkan 1 file JPG/PNG kecil, 1 PDF, 1 file > 5 MB, dan 1 file lain (mis. `.txt` yang di-rename jadi `.png`).

Model (Model List)
- [ ] Vendor Spec: **+ Tambah Model** kode `ILZ-01`, nama `Illuzion IV Elite FG`, factory `PT Unimitra` → pindah ke Model Detail
- [ ] Tambah lagi dengan kode `ilz-01` → ditolak di form: *Kode model ilz-01 sudah dipakai model "…"*
- [ ] Kode/nama kosong → ditolak di form
- [ ] Vendor CBD & Brand Viewer: tidak ada tombol Tambah; Vendor CBD & Brand melihat tombol **CBD**, Vendor Spec tidak
- [ ] Tab **Info Model** → **Ubah Model** (isi Outsole Mould, Size Range) → tersimpan; field dikosongkan → tampil `-`

Season & Article (Model Detail)
- [ ] Model baru: catatan *Belum ada season…*; **+ Season Baru** → form terisi musim & tahun berjalan; simpan `SS26` → terpilih otomatis
- [ ] Tambah `SS26` lagi → ditolak di form; tambah `FH26` → urutan pilihan: FH26 di atas SS26
- [ ] Di `SS26`: **+ Article** `GY1001` / `Core Black` → label tombol jadi `+ Article (1/5)`
- [ ] Kode `gy1001` di season yang sama → ditolak: *Kode article gy1001 sudah ada di season ini.*
- [ ] Tambah sampai 5 article → tombol **+ Article** nonaktif; coba lewat DB Tools insert article ke-6 → ditolak *Maksimal 5 article per season*
- [ ] **Ubah** article: ganti colorway & kode → tersimpan (belum dipakai, jadi kode boleh diubah)
- [ ] **Hapus** article (konfirmasi) → hilang, hitungan di pilihan season berkurang
- [ ] Buka link `Model Detail?id=…&season=<id FH26>` → FH26 langsung terpilih
- [ ] Brand Viewer: bisa lihat season & article, tidak ada tombol tambah/ubah/hapus/copy
- [ ] *Kode terkunci & tidak bisa dihapus setelah dipakai* → diuji di F5 (tabel revisi belum ada)

Lampiran
- [ ] **Lampiran** article → upload JPG dengan catatan → muncul di tabel (Jenis JPG, ukuran KB), kolom Lampiran di tabel article `1 file`
- [ ] **Lihat** → gambar tampil di bawah tabel; **Unduh** → file terunduh dan bisa dibuka
- [ ] Upload PDF → **Lihat** = terunduh, bisa dibuka
- [ ] File > 5 MB → ditolak (FilePicker / pesan *maksimal 5 MB*)
- [ ] File palsu (`.txt` di-rename `.png`) → ditolak DB: *Jenis file tidak didukung…*
- [ ] **Hapus** lampiran (konfirmasi) → hilang; hapus article yang punya lampiran → lampirannya ikut terhapus
- [ ] Brand Viewer: bisa Lihat & Unduh, tidak ada upload/hapus
- [ ] Admin → Audit Log: entri `product_model`, `specsheet`, `article`, `article_attachment` (tanpa isi file)

Cek DB (opsional, DB Tools):
```sql
SELECT file_name, mime_type, size_bytes FROM article_attachment ORDER BY created_at DESC LIMIT 5;
SELECT entity, action, after_data ? 'content' AS ada_isi FROM audit_log
 WHERE entity = 'article_attachment' ORDER BY id DESC LIMIT 5;
```
→ `ada_isi` harus `false`.

---

## 5. Perbaikan setelah review v4.7 - hapus Copy Article

Keputusan user (30 Sep 2026): article **tidak** di-copy antar season; article diisi per season. Yang di-copy
hanya **struktur specsheet** (baris BOM) dari season lain model yang sama - dibuat di F5.

1. DB Tools → `z_run_sql`:
   ```sql
   DROP FUNCTION IF EXISTS fn_article_copy(text, uuid, uuid);
   ```
2. Page `Model Detail`: hapus widget `selArticleSumber` dan `btnArticleCopy`, hapus query `a_article_copy`.
3. JSObject `ModelDetailCtrl` → tempel ulang `js/ModelDetailCtrl.js` (fungsi `copySourceOptions()` & `copyArticles()` dihapus).
4. Deploy → uji: tab Season & Article tidak punya Copy Article, tambah/ubah/hapus article tetap jalan, tidak ada error di console.

---

## 6. Export

Export app → `appsmith/exports/export_v4.json` → kirim di chat bersama hasil query cek skema (PLAN.md §8, untuk F3/F3b/F4) dan uji yang gagal (kalau ada).
