# F3 — Master Material, supplier material, harga: langkah di Appsmith

Urutan: **0** T9 → **1** SQL → **2** Master Material → **3** Material Detail → **4** uji → **5** export `export_v3.json`.

Setelan untuk **semua query baru** (datasource `Prestasi`): *Use prepared statements* **ON**, *Run behaviour* **Manual**.
Semua form modal = Custom Widget (pola sama dengan `cwUserForm` / `cwSupplierForm`): modal tanpa judul/tombol bawaan,
Custom Widget mengisi modal, tempel HTML/CSS/JS dari `widgets/<cw>/`, isi Default model, buat event `onSave` & `onCancel`.

---

## 0. T9 (bug F2) — kerjakan dulu

Di `Master Supplier` dan `Master Komponen`, event `onLogout` pada `cwHeader`:
```
{{storeValue('doLogout', true).then(() => navigateTo('Login'))}}
```
Untuk page baru di F3, **salin `cwHeader` dari Beranda atau Admin** (bukan dari page Master lama).

---

## 1. SQL

1. DB Tools → `z_run_sql` → tempel seluruh `sql/F3_material.sql` → Run.
2. Cek cepat:
   ```sql
   SELECT count(*) FROM v_material_list;
   ```
   Hasil `0` (tabel baru kosong) tanpa error.

---

## 2. Page `Master Material`

### 2a. JSObject
- `Auth`: `requiredPerm: 'view_master'` dan
  ```js
  pageQueries() {
  	return [q_material_meta, q_materials];
  },
  ```
- Buat **`MaterialCtrl`** → tempel `js/MaterialCtrl.js`.

### 2b. Query

**`q_material_meta`** (saran kode `MTR-NNNN` + daftar kategori & UoM)
```sql
SELECT 'MTR-' || lpad((coalesce(max(substring(m.material_code from '^MTR-([0-9]+)$')::bigint), 0) + 1)::text, 4, '0') AS next_code,
       string_agg(DISTINCT m.category, '|' ORDER BY m.category) AS categories,
       string_agg(DISTINCT m.uom, '|' ORDER BY m.uom) AS uoms
FROM (SELECT fn_auth({{appsmith.store.token}}, 'view_master') AS u) a
LEFT JOIN material m ON true;
```

**`q_materials`**
```sql
SELECT id, material_code, name, category, thickness, uom, price_method, status,
       supplier_count, proposed_links, priced_links, preferred_supplier, missing_price, updated_at, updated_by
FROM v_material_list
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_master')) IS NOT NULL
  AND ({{inpMaterialCari.text || ''}} = ''
       OR material_code ILIKE '%' || {{inpMaterialCari.text || ''}} || '%'
       OR name ILIKE '%' || {{inpMaterialCari.text || ''}} || '%'
       OR category ILIKE '%' || {{inpMaterialCari.text || ''}} || '%')
  AND ({{selMaterialStatus.selectedOptionValue || ''}} = '' OR status = {{selMaterialStatus.selectedOptionValue || ''}})
  AND ({{selMaterialKategori.selectedOptionValue || ''}} = '' OR category = {{selMaterialKategori.selectedOptionValue || ''}})
  AND (NOT {{swMaterialBelumHarga.isSwitchedOn === true}}::boolean OR missing_price)
ORDER BY name_key, thickness, uom
LIMIT 500;
```

**`a_material_add`** (status ditentukan DB: admin → APPROVED, vendor → PROPOSED)
```sql
SELECT fn_material_add({{appsmith.store.token}}, {{this.params.code}}, {{this.params.name}},
                       {{this.params.category}}, {{this.params.thickness}}, {{this.params.uom}},
                       {{this.params.price_method}}) AS id;
```

**`a_material_set_status`**
```sql
UPDATE material
   SET status = {{this.params.status}},
       updated_by = fn_auth({{appsmith.store.token}}, 'manage_master')
 WHERE id = {{this.params.id}}::uuid
RETURNING id;
```

### 2c. Widget

| Widget | Setelan |
|---|---|
| `cwHeader` | Salin dari **Beranda/Admin**, `pageTitle: 'Master Material'` |
| `inpMaterialCari` | Input, placeholder `Cari kode / nama / kategori…` |
| `selMaterialStatus` | Select, placeholder `Semua status`, Default kosong, *Allow clearing* ON · Source data: `{{MaterialCtrl.statusOptions}}` |
| `selMaterialKategori` | Select, placeholder `Semua kategori`, Default kosong, *Allow clearing* ON · Source data: `{{MaterialCtrl.categoryOptions()}}` |
| `swMaterialBelumHarga` | Switch, label `Belum ada harga`, Default OFF · Visible: `{{MaterialCtrl.canViewPrice()}}` |
| `btnMaterialCari` | `Cari` · onClick: `{{q_materials.run()}}` |
| `btnMaterialTambah` | Label: `{{MaterialCtrl.canManage() ? '+ Tambah Material' : '+ Usulkan Material'}}` · Visible: `{{MaterialCtrl.canAdd()}}` · onClick: `{{MaterialCtrl.openAdd()}}` |
| `tblMaterials` | Table data: `{{q_materials.data}}` |

Kolom `tblMaterials` — sembunyikan `id`, `proposed_links`, `priced_links`, `preferred_supplier`, `missing_price`, `updated_by`:

| Kolom | Label | Setelan |
|---|---|---|
| `material_code` | Kode | – |
| `name` | Nama Material | – |
| `category` | Kategori | – |
| `thickness` | Thickness | – |
| `uom` | UoM | – |
| `price_method` | Metode Harga | Visible (kolom): `{{MaterialCtrl.canViewPrice()}}` |
| `status` | Status | Text color: `{{Util.statusColor(currentRow.status)}}`, bold |
| `supplier_count` | Supplier | Computed value: `{{MaterialCtrl.supplierSummary(currentRow)}}` · Text color: `{{currentRow.missing_price && MaterialCtrl.canViewPrice() ? '#dc2626' : ''}}` |
| `updated_at` | Diubah | Computed value: `{{Util.fmtDateTime(currentRow.updated_at)}}` |
| *(baru)* Button `Approve` | – | onClick: `{{MaterialCtrl.approve(currentRow)}}` · Visible (kolom): `{{MaterialCtrl.canManage()}}` · Cell visible: `{{currentRow.status === 'PROPOSED'}}` |
| *(baru)* Button `Buka` | – | onClick: `{{MaterialCtrl.open(currentRow)}}` |

### 2d. Modal `mdlMaterial` — Custom Widget `cwMaterialForm`

Modal lebar ±560 px; `cwMaterialForm` tinggi ±650 px. Kode: `widgets/cwMaterialForm/`.

Default model:
```js
{{ {
  key: MaterialCtrl.formKey,
  mode: 'add',
  form: MaterialCtrl.form,
  nextCode: MaterialCtrl.meta().nextCode,
  categories: MaterialCtrl.meta().categories,
  uoms: MaterialCtrl.meta().uoms,
  statusOptions: MaterialCtrl.statusOptions,
  canManage: MaterialCtrl.canManage(),
  canIdentity: true,
  canPriceMethod: true,
  canStatus: false,
  busy: MaterialCtrl.busy,
  message: MaterialCtrl.message
} }}
```

| Event | Action |
|---|---|
| `onSave` | `{{MaterialCtrl.save()}}` |
| `onCancel` | `{{closeModal('mdlMaterial')}}` |

---

## 3. Page `Material Detail` (`?id=<material id>`, dibuka dari tombol **Buka**)

### 3a. JSObject
- `Auth`: `requiredPerm: 'view_master'` dan
  ```js
  pageQueries() {
  	const q = [q_material, q_material_meta, q_links, q_link_supplier_options];
  	if (this.can('view_price')) q.push(q_prices);
  	return q;
  },
  ```
- Buat **`MaterialDetailCtrl`** → tempel `js/MaterialDetailCtrl.js`.

### 3b. Query

**`q_material`**
```sql
SELECT id, material_code, name, category, thickness, uom, price_method, status,
       supplier_count, proposed_links, priced_links, preferred_supplier, missing_price, updated_at, updated_by
FROM v_material_list
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_master')) IS NOT NULL
  AND id::text = {{appsmith.URL.queryParams.id || ''}};
```

**`q_material_meta`** — sama persis dengan di page Master Material (salin).

**`q_links`**
```sql
SELECT ms.id, ms.supplier_id, s.name AS supplier_name, s.status AS supplier_status,
       ms.supplier_material_code, ms.is_preferred, ms.status, ms.updated_at, ms.updated_by
FROM material_supplier ms
JOIN supplier s ON s.id = ms.supplier_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_master')) IS NOT NULL
  AND ms.material_id::text = {{appsmith.URL.queryParams.id || ''}}
ORDER BY ms.is_preferred DESC, ms.status = 'INACTIVE', s.name_key;
```

**`q_link_supplier_options`** (supplier aktif yang belum terdaftar untuk material ini)
```sql
SELECT s.id, s.name
FROM supplier s
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_master')) IS NOT NULL
  AND s.status <> 'INACTIVE'
  AND NOT EXISTS (SELECT 1 FROM material_supplier ms
                   WHERE ms.supplier_id = s.id AND ms.material_id::text = {{appsmith.URL.queryParams.id || ''}})
ORDER BY s.name_key;
```

**`q_prices`** (hanya role dengan `view_price`; Vendor Spec ditolak DB)
```sql
SELECT mp.id, mp.material_supplier_id AS link_id, s.name AS supplier_name, mp.color, mp.price, mp.currency,
       mp.valid_from, mp.valid_to, mp.reference, mp.created_by, mp.created_at,
       CASE WHEN mp.valid_to IS NOT NULL AND mp.valid_to <= fn_today() THEN 'RIWAYAT'
            WHEN mp.valid_from > fn_today() THEN 'AKAN BERLAKU'
            ELSE 'BERLAKU' END AS state
FROM material_price mp
JOIN material_supplier ms ON ms.id = mp.material_supplier_id
JOIN supplier s ON s.id = ms.supplier_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_price')) IS NOT NULL
  AND ms.material_id::text = {{appsmith.URL.queryParams.id || ''}}
ORDER BY mp.color_key, mp.valid_from DESC, mp.created_at DESC;
```

**`a_material_update`**
```sql
SELECT fn_material_update({{appsmith.store.token}}, {{this.params.id}}::uuid, {{this.params.code}},
                          {{this.params.name}}, {{this.params.category}}, {{this.params.thickness}},
                          {{this.params.uom}}, {{this.params.status}}, {{this.params.price_method}}) AS id;
```

**`a_link_save`**
```sql
SELECT fn_link_save({{appsmith.store.token}}, {{this.params.link_id}}::uuid, {{this.params.material_id}}::uuid,
                    {{this.params.supplier_id}}::uuid, {{this.params.code}},
                    {{this.params.is_preferred}}::boolean, {{this.params.status}}) AS id;
```

**`a_link_set_status`**
```sql
UPDATE material_supplier
   SET status = {{this.params.status}},
       updated_by = fn_auth({{appsmith.store.token}}, 'manage_master')
 WHERE id = {{this.params.id}}::uuid
RETURNING id;
```

**`a_price_add`**
```sql
SELECT fn_price_add({{appsmith.store.token}}, {{this.params.link_id}}::uuid, {{this.params.color}},
                    {{this.params.price}}::numeric, {{this.params.currency}},
                    {{this.params.valid_from}}::date, {{this.params.reference}}) AS id;
```

**`a_price_end`** — *Request confirmation before running* = **ON**
```sql
SELECT fn_price_end({{appsmith.store.token}}, {{this.params.id}}::uuid, NULL) AS id;
```

### 3c. Widget (atas → bawah)

| Widget | Setelan |
|---|---|
| `cwHeader` | Salin dari **Beranda/Admin**, `pageTitle: 'Material Detail'` |
| `btnKembali` | Label `← Master Material`, style tertiary · onClick: `{{navigateTo('Master Material')}}` |
| `txtMaterialInfo` | Text: `{{MaterialDetailCtrl.infoText()}}` (HTML dirender) |
| `btnMaterialUbah` | Label `Ubah Material` · Visible: `{{MaterialDetailCtrl.canEditMaterial() && !!MaterialDetailCtrl.material()}}` · onClick: `{{MaterialDetailCtrl.openEditMaterial()}}` |
| `txtSupplierJudul` | Text `Supplier`, bold |
| `btnLinkTambah` | Label `+ Tambah Supplier` · Visible: `{{MaterialDetailCtrl.canLink() && !!MaterialDetailCtrl.material()}}` · onClick: `{{MaterialDetailCtrl.openAddLink()}}` |
| `tblLinks` | Table data: `{{q_links.data}}` · **Default selected row**: `0` |
| `cntHarga` | Container untuk bagian harga · Visible: `{{MaterialDetailCtrl.canViewPrice()}}`. Isi di bawah |
| ↳ `txtHargaInfo` | Text: `{{MaterialDetailCtrl.priceNote()}}` |
| ↳ `swHargaRiwayat` | Switch, label `Tampilkan riwayat`, Default OFF |
| ↳ `btnHargaTambah` | Label `+ Tambah Harga` · Visible: `{{MaterialDetailCtrl.canAddPrice()}}` · onClick: `{{MaterialDetailCtrl.openAddPrice()}}` |
| ↳ `tblPrices` | Table data: `{{MaterialDetailCtrl.pricesForSelected()}}` |

Kolom `tblLinks` — sembunyikan `id`, `supplier_id`, `updated_by`:

| Kolom | Label | Setelan |
|---|---|---|
| `supplier_name` | Supplier | – |
| `supplier_material_code` | Kode di supplier | – |
| `is_preferred` | Utama | Column type Text · Computed value: `{{currentRow.is_preferred ? '★ Utama' : ''}}` |
| `status` | Status | Text color: `{{Util.statusColor(currentRow.status)}}`, bold |
| `supplier_status` | Status di Master | Text color: `{{Util.statusColor(currentRow.supplier_status)}}` |
| `updated_at` | Diubah | Computed value: `{{Util.fmtDateTime(currentRow.updated_at)}}` |
| *(baru)* Button `Approve` | – | onClick: `{{MaterialDetailCtrl.approveLink(currentRow)}}` · Visible (kolom): `{{MaterialDetailCtrl.canManageMaster()}}` · Cell visible: `{{currentRow.status === 'PROPOSED'}}` |
| *(baru)* Button `Ubah` | – | onClick: `{{MaterialDetailCtrl.openEditLink(currentRow)}}` · Visible (kolom): `{{MaterialDetailCtrl.canLink() \|\| MaterialDetailCtrl.canManageMaster()}}` |

Kolom `tblPrices` — sembunyikan `id`, `link_id`, `supplier_name`, `created_at`:

| Kolom | Label | Setelan |
|---|---|---|
| `color` | Warna | Computed value: `{{currentRow.color \|\| 'Semua warna'}}` |
| `price` | Harga | Column type Text · Computed value: `{{MaterialDetailCtrl.fmtPrice(currentRow.price)}}` · rata kanan |
| `currency` | Cur | – |
| `valid_from` | Berlaku mulai | Computed value: `{{Util.fmtDate(currentRow.valid_from)}}` |
| `valid_to` | Sampai | Computed value: `{{currentRow.valid_to ? Util.fmtDate(currentRow.valid_to) : '-'}}` |
| `state` | Keterangan | Text color: `{{({ BERLAKU: '#16a34a', 'AKAN BERLAKU': '#d97706' })[currentRow.state] \|\| '#6b7280'}}`, bold |
| `reference` | Referensi | – |
| `created_by` | Oleh | – |
| *(baru)* Button `Ganti harga` | – | onClick: `{{MaterialDetailCtrl.openAddPrice(currentRow.color)}}` · Visible (kolom): `{{MaterialDetailCtrl.canAddPrice()}}` · Cell visible: `{{!currentRow.valid_to}}` |
| *(baru)* Button `Akhiri` | – | onClick: `{{MaterialDetailCtrl.endPrice(currentRow)}}` · Visible (kolom): `{{MaterialDetailCtrl.canManagePrice()}}` · Cell visible: `{{!currentRow.valid_to}}` |

### 3d. Tiga modal (Custom Widget)

| Modal | Custom Widget | Ukuran | Default model | `onSave` | `onCancel` |
|---|---|---|---|---|---|
| `mdlMaterial` | `cwMaterialForm` | lebar ±560, widget ±650 px | `{{MaterialDetailCtrl.materialFormModel()}}` | `{{MaterialDetailCtrl.saveMaterial()}}` | `{{closeModal('mdlMaterial')}}` |
| `mdlLink` | `cwLinkForm` | lebar ±480, widget ±480 px | `{{MaterialDetailCtrl.linkFormModel()}}` | `{{MaterialDetailCtrl.saveLink()}}` | `{{closeModal('mdlLink')}}` |
| `mdlHarga` | `cwPriceForm` | lebar ±560, widget ±630 px | `{{MaterialDetailCtrl.priceFormModel()}}` | `{{MaterialDetailCtrl.savePrice()}}` | `{{closeModal('mdlHarga')}}` |

Kode masing-masing di `widgets/cwMaterialForm/` (sama dengan yang dipakai di Master Material), `widgets/cwLinkForm/`, `widgets/cwPriceForm/`.

Lalu **Deploy**.

---

## 4. Uji

Akun: **Master Admin**, **Vendor – Specsheet**, **Vendor – CBD**, **Brand Viewer**. Siapkan 2 supplier di Master Supplier (mis. `PT Maju Jaya`, `PT Sinar`).

Material (Master Material)
- [ ] Admin: Tambah → kode terisi `MTR-0001`; isi `Nappa Leather`, kategori `Leather`, thickness `1.2mm`, UoM `yd`, metode Catalog → APPROVED, UoM tersimpan `YD`
- [ ] Tambah lagi `nappa  LEATHER`, `1,2mm`, `YD` → ditolak di form: *…sudah ada: MTR-0001 — Nappa Leather.*
- [ ] Kode `MTR-0001` dipakai lagi → ditolak: *Material Code MTR-0001 sudah dipakai…*
- [ ] Tambah material Quotation (mis. `Printing Logo`, kategori `Process`, UoM `PCS`) → saran kode `MTR-0002`, kategori `Leather` muncul sebagai saran isian
- [ ] Vendor Spec: tombol **Usulkan Material** → PROPOSED; kolom Metode Harga & switch *Belum ada harga* tidak tampil; tidak ada tombol Approve
- [ ] Admin: filter status PROPOSED → **Approve**
- [ ] Filter kategori, cari, dan switch *Belum ada harga* berfungsi

Supplier material (Material Detail `MTR-0001`)
- [ ] Vendor Spec: **+ Tambah Supplier** `PT Maju Jaya`, centang utama → PROPOSED, ★ Utama; supplier itu hilang dari pilihan saat tambah lagi
- [ ] Tambah `PT Sinar` + centang utama → ★ pindah ke PT Sinar (hanya satu utama)
- [ ] Vendor Spec: form Ubah → status tidak tampil; Admin: **Approve** / ubah status INACTIVE → ★ hilang dari supplier itu
- [ ] Nonaktifkan `PT Sinar` di Master Supplier → tidak muncul lagi di pilihan tambah supplier material

Harga (Vendor CBD atau Admin, material Catalog)
- [ ] Vendor Spec: bagian harga tidak tampil sama sekali
- [ ] **+ Tambah Harga**: currency belum terpilih → Simpan ditolak *Pilih currency*; isi `45000` IDR hari ini → BERLAKU
- [ ] Ketik `47.500` → ditolak (ambigu); `47500` diterima
- [ ] **Ganti harga** (semua warna) `47500` IDR tanggal hari ini → harga lama jadi RIWAYAT (nyalakan *Tampilkan riwayat*), harga baru BERLAKU
- [ ] Harga dengan tanggal lebih awal dari harga berlaku → ditolak
- [ ] Harga warna `Black` 50000 → baris terpisah; **Akhiri** (konfirmasi) → pindah ke riwayat
- [ ] Supplier INACTIVE tidak ada di pilihan supplier form harga
- [ ] Material Quotation: tombol Tambah Harga tidak ada, info *harga diisi per CBD*
- [ ] Vendor CBD: **Ubah Material** → hanya metode harga yang bisa diubah; ubah ke Quotation → tersimpan
- [ ] Brand Viewer: bisa lihat material, supplier, harga; tidak ada tombol ubah
- [ ] Admin → Audit Log: entri `material`, `material_supplier`, `material_price`

Cek DB (opsional, di DB Tools) — lookup harga dipakai CBD nanti:
```sql
SELECT * FROM fn_price_lookup(
  (SELECT id FROM material WHERE material_code = 'MTR-0001'),
  (SELECT id FROM supplier WHERE name = 'PT Maju Jaya'), 'black');
```
→ harga warna Black kalau masih berlaku, kalau tidak harga semua warna (`tier` = `COLOR` / `ALL_COLORS`).

---

## 5. Export

Export app → `appsmith/exports/export_v3.json` → kirim di chat bersama hasil query cek skema (PLAN.md §8) dan uji yang gagal (kalau ada).
