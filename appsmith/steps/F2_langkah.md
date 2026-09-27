# F2 — Master Supplier & Komponen: langkah di Appsmith

Urutan: **0** temuan v1 → **1** SQL → **2** Master Supplier → **3** Master Komponen → **4** uji → **5** export `export_v2.json`.

Setelan yang berlaku untuk **semua query baru** di bawah (datasource `Prestasi`):
- *Use prepared statements* = **ON**
- *Run behaviour* = **Manual** (query baca dijalankan oleh `Auth.pageQueries()`, bukan otomatis — lihat T3)

---

## 0. Temuan review v1 (T1–T8)

Kalau belum, kerjakan dulu (detail di `PLAN.md` §9). Paling penting: **T1** (target `cwMenu` → `'Master Material'`, `'Model List'`) — tanpa ini menu Master dari Beranda tidak bisa dibuka.

---

## 1. SQL

1. Buka app **DB Tools** → query `z_run_sql` → tempel seluruh isi `sql/F2_master.sql` → Run.
   Kalau versi awal F2 (dengan currency default) sudah telanjur dijalankan, jalankan ulang saja — kolom `default_currency` otomatis dihapus.
   Satu transaksi: kalau ada error (mis. bentrok nama tabel), tidak ada yang tersimpan — kirim pesan errornya ke chat.
2. Cek cepat:
   ```sql
   SELECT code, name, range_start, range_end FROM component_group ORDER BY sort_order;
   ```
   Harus 4 baris: a Upper 0–3990 · b Bottom unit 4000–5990 · c Packaging 6000–7990 · d Miscellaneous 8000–9990.

---

## 2. Page `Master Supplier`

### 2a. JSObject
- `Auth` (sudah ada): ubah `requiredPerm: 'view_master'` dan
  ```js
  pageQueries() {
  	return [q_suppliers];
  },
  ```
- Buat JSObject **`SupplierCtrl`** → tempel `js/SupplierCtrl.js`.

### 2b. Query

**`q_suppliers`**
```sql
SELECT id, name, status, updated_at, updated_by
FROM supplier
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_master')) IS NOT NULL
  AND ({{inpSupplierCari.text || ''}} = '' OR name ILIKE '%' || {{inpSupplierCari.text || ''}} || '%')
  AND ({{selSupplierFilterStatus.selectedOptionValue || ''}} = ''
       OR status = {{selSupplierFilterStatus.selectedOptionValue || ''}})
ORDER BY name_key;
```

**`a_supplier_insert`**
```sql
INSERT INTO supplier (name, status, updated_by)
SELECT {{this.params.name}}, 'APPROVED',
       fn_auth({{appsmith.store.token}}, 'manage_master')
RETURNING id;
```

**`a_supplier_update`**
```sql
UPDATE supplier
   SET name = {{this.params.name}},
       status = {{this.params.status}},
       updated_by = fn_auth({{appsmith.store.token}}, 'manage_master')
 WHERE id = {{this.params.id}}::uuid
RETURNING id;
```

### 2c. Widget (atas → bawah)

| Widget | Setelan |
|---|---|
| `cwHeader` | Salin dari page Admin (copy–paste widget). Default model: sama, hanya `pageTitle: 'Master Supplier'`. Event `onHome` / `onChangePassword` / `onLogout` sama seperti Admin |
| `inpSupplierCari` | Input, placeholder `Cari nama supplier…` · onTextChanged: `{{q_suppliers.run()}}` |
| `selSupplierFilterStatus` | Select, placeholder `Semua status`, Default value **kosong**, *Allow clearing value* ON · Options: `{{SupplierCtrl.statusOptions}}` · onOptionChange: `{{q_suppliers.run()}}` |
| `btnSupplierTambah` | Label `+ Tambah Supplier` · Visible: `{{SupplierCtrl.canManage()}}` · onClick: `{{SupplierCtrl.openAdd()}}` |
| `tblSuppliers` | Table data: `{{q_suppliers.data}}` · kolom di bawah |

Kolom `tblSuppliers` (sembunyikan `id`, `updated_by` boleh tampil):

| Kolom | Label | Setelan |
|---|---|---|
| `name` | Nama Supplier | – |
| `status` | Status | Text color: `{{Util.statusColor(currentRow.status)}}`, font bold |
| `updated_at` | Diubah | Computed value: `{{Util.fmtDateTime(currentRow.updated_at)}}` (**pakai nama kolom data**, bukan label — T2) |
| `updated_by` | Oleh | – |
| *(kolom baru)* `aksi` | – | Column type **Button**, label `Ubah`, onClick: `{{SupplierCtrl.openEdit(currentRow)}}` · Visible (kolom): `{{SupplierCtrl.canManage()}}` |

### 2d. Modal `mdlSupplier` — Custom Widget `cwSupplierForm`

Sama seperti `mdlUser` + `cwUserForm` di page Admin (isi form = Custom Widget, tanpa widget bawaan lain di modal).

1. Tambah **Modal** `mdlSupplier`, lebar ±480 px. Hapus judul/tombol bawaan modal (judul & tombol ada di widget).
2. Di dalamnya tambah **Custom Widget** `cwSupplierForm`, isi seluruh modal, tinggi ±320 px.
3. **Edit source**: tempel `widgets/cwSupplierForm/index.html` → tab HTML, `style.css` → Style, `script.js` → JavaScript.
4. **Default model**:
   ```js
   {{ {
     key: SupplierCtrl.formKey,
     mode: SupplierCtrl.isNew ? 'add' : 'edit',
     form: SupplierCtrl.form,
     statusOptions: SupplierCtrl.statusOptions,
     busy: SupplierCtrl.busy,
     message: SupplierCtrl.message
   } }}
   ```
5. **Events** (tambah dengan nama persis):
   | Event | Action |
   |---|---|
   | `onSave` | `{{SupplierCtrl.save()}}` |
   | `onCancel` | `{{closeModal('mdlSupplier')}}` |

Pesan error dari DB (mis. *Supplier "PT Maju Jaya" sudah ada.*) tampil di dalam form; modal tetap terbuka dan isian tidak hilang.

---

## 3. Page `Master Komponen`

### 3a. JSObject
- `Auth`: `requiredPerm: 'view_master'` dan
  ```js
  pageQueries() {
  	return [q_component_groups, q_components];
  },
  ```
- Buat JSObject **`KomponenCtrl`** → tempel `js/KomponenCtrl.js`.

### 3b. Query

**`q_component_groups`** (sekaligus saran nomor berikutnya per kelompok)
```sql
SELECT g.code, g.name, g.range_start, g.range_end, g.sort_order,
       count(c.id)::int AS total,
       CASE WHEN max(c.number) IS NULL THEN g.range_start
            WHEN max(c.number) + 10 <= g.range_end THEN max(c.number) + 10
       END AS next_no
FROM component_group g
LEFT JOIN component c ON c.group_code = g.code
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_master')) IS NOT NULL
GROUP BY g.code
ORDER BY g.sort_order;
```

**`q_components`**
```sql
SELECT c.id, c.number, c.name, c.group_code, g.name AS group_name, c.status, c.updated_at, c.updated_by
FROM component c
JOIN component_group g ON g.code = c.group_code
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_master')) IS NOT NULL
  AND ({{selKomponenGrup.selectedOptionValue || ''}} = '' OR c.group_code = {{selKomponenGrup.selectedOptionValue || ''}})
  AND ({{selKomponenFilterStatus.selectedOptionValue || ''}} = ''
       OR c.status = {{selKomponenFilterStatus.selectedOptionValue || ''}})
  AND ({{inpKomponenCari.text || ''}} = ''
       OR c.name ILIKE '%' || {{inpKomponenCari.text || ''}} || '%'
       OR c.number::text LIKE {{inpKomponenCari.text || ''}} || '%')
ORDER BY c.number;
```

**`a_component_add`** (status ditentukan DB: admin → APPROVED, vendor → PROPOSED)
```sql
SELECT fn_component_add({{appsmith.store.token}}, {{this.params.group_code}},
                        {{this.params.number}}::integer, {{this.params.name}}) AS id;
```

**`a_component_update`**
```sql
UPDATE component
   SET group_code = {{this.params.group_code}},
       number = {{this.params.number}}::integer,
       name = {{this.params.name}},
       status = {{this.params.status}},
       updated_by = fn_auth({{appsmith.store.token}}, 'manage_master')
 WHERE id = {{this.params.id}}::uuid
RETURNING id;
```

**`a_component_set_status`**
```sql
UPDATE component
   SET status = {{this.params.status}},
       updated_by = fn_auth({{appsmith.store.token}}, 'manage_master')
 WHERE id = {{this.params.id}}::uuid
RETURNING id;
```

### 3c. Widget

| Widget | Setelan |
|---|---|
| `cwHeader` | Salin dari Admin, `pageTitle: 'Master Komponen'` |
| `selKomponenGrup` | Select, placeholder `Semua kelompok`, Default value kosong, *Allow clearing value* ON · Options: `{{KomponenCtrl.groupOptions()}}` · onOptionChange: `{{q_components.run()}}` |
| `selKomponenFilterStatus` | Select, placeholder `Semua status`, Default kosong, *Allow clearing value* ON · Options: `{{KomponenCtrl.statusOptions}}` · onOptionChange: `{{q_components.run()}}` |
| `inpKomponenCari` | Input, placeholder `Cari nomor / nama…` · onTextChanged: `{{q_components.run()}}` |
| `btnKomponenTambah` | Label: `{{KomponenCtrl.canManage() ? '+ Tambah Komponen' : '+ Usulkan Komponen'}}` · Visible: `{{KomponenCtrl.canAdd()}}` · onClick: `{{KomponenCtrl.openAdd()}}` |
| `tblComponents` | Table data: `{{q_components.data}}` |

Kolom `tblComponents` (sembunyikan `id`, `group_code`):

| Kolom | Label | Setelan |
|---|---|---|
| `number` | No. | – |
| `name` | Nama Komponen | – |
| `group_name` | Kelompok | – |
| `status` | Status | Text color: `{{Util.statusColor(currentRow.status)}}`, bold |
| `updated_at` | Diubah | Computed value: `{{Util.fmtDateTime(currentRow.updated_at)}}` |
| `updated_by` | Oleh | – |
| *(baru)* `approve` | – | Button `Approve` · onClick: `{{KomponenCtrl.approve(currentRow)}}` · Visible (kolom): `{{KomponenCtrl.canManage()}}` · **Cell visible** (atau *Disabled* bila opsi itu tidak ada): `{{currentRow.status === 'PROPOSED'}}` / `{{currentRow.status !== 'PROPOSED'}}` |
| *(baru)* `aksi` | – | Button `Ubah` · onClick: `{{KomponenCtrl.openEdit(currentRow)}}` · Visible (kolom): `{{KomponenCtrl.canManage()}}` |

### 3d. Modal `mdlKomponen` — Custom Widget `cwKomponenForm`

1. Tambah **Modal** `mdlKomponen`, lebar ±480 px, tanpa judul/tombol bawaan.
2. Di dalamnya **Custom Widget** `cwKomponenForm`, isi seluruh modal, tinggi ±520 px.
3. **Edit source**: tempel `widgets/cwKomponenForm/index.html` / `style.css` / `script.js`.
4. **Default model**:
   ```js
   {{ {
     key: KomponenCtrl.formKey,
     mode: KomponenCtrl.isNew ? 'add' : 'edit',
     form: KomponenCtrl.form,
     groups: KomponenCtrl.groups(),
     statusOptions: KomponenCtrl.statusOptions,
     canManage: KomponenCtrl.canManage(),
     busy: KomponenCtrl.busy,
     message: KomponenCtrl.message
   } }}
   ```
5. **Events**:
   | Event | Action |
   |---|---|
   | `onSave` | `{{KomponenCtrl.save()}}` |
   | `onCancel` | `{{closeModal('mdlKomponen')}}` |

Di dalam form: pilih kelompok → nomor terisi saran berikutnya; nomor yang sudah diketik sendiri tidak ditimpa (tombol **Pakai saran** untuk mengisi lagi). Judul/tombol otomatis **Usulkan** untuk vendor.

Lalu **Deploy**.

---

## 4. Uji (centang semua, kirim hasil yang gagal ke chat)

Pakai 2 akun: **Master Admin** dan **Vendor – Specsheet** (buat di Admin kalau belum ada).

Supplier (Master Admin)
- [ ] Tambah `PT Maju Jaya` → muncul di tabel, status APPROVED
- [ ] Tambah `pt  maju JAYA` → ditolak di dalam form: *Supplier "PT Maju Jaya" sudah ada.*
- [ ] Ubah nama, status INACTIVE → tersimpan; filter status & cari berfungsi
- [ ] Vendor Spec: tabel terlihat, tombol Tambah/Ubah tidak ada

Komponen
- [ ] Admin, kelompok **a**: saran nomor `0` (tabel kosong) → simpan nama `Vamp` → APPROVED; buka Tambah lagi → saran `10`
- [ ] Nomor `15` → *harus kelipatan 10* · nomor `4000` di kelompok a → *rentang 0–3990 untuk kelompok Upper* · nomor `0` lagi → *sudah dipakai komponen "Vamp"*
- [ ] Ganti kelompok di modal ke **b** → saran nomor berubah ke `4000`; ketik nomor sendiri lalu ganti kelompok → nomor tidak ditimpa
- [ ] Error DB (mis. nomor sudah dipakai) tampil di dalam form, modal tetap terbuka
- [ ] Vendor Spec: tombol **Usulkan Komponen** → tersimpan PROPOSED, tidak ada tombol Ubah/Approve
- [ ] Admin: filter status PROPOSED → **Approve** → jadi APPROVED
- [ ] Admin: Ubah nomor/nama/kelompok komponen → aturan nomor sama seperti tambah
- [ ] Brand Viewer: kedua page bisa dibuka, hanya lihat
- [ ] Admin → tab Audit Log: ada entri `supplier` dan `component` (INSERT/UPDATE) dengan email pelaku

Keamanan (opsional, lewat `z_run_sql` di DB Tools)
- [ ] `SELECT fn_component_add('token-palsu', 'a', 990, 'X');` → error `SESI_HABIS`

---

## 5. Export

Export app → simpan sebagai `appsmith/exports/export_v2.json` → bilang di chat. Sertakan juga hasil query cek skema (PLAN.md §8) dari DB Tools.
