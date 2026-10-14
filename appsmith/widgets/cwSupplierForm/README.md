# cwSupplierForm

Form **Tambah/Ubah Supplier** (tanpa currency - currency dipilih per harga) di dalam modal `mdlSupplier` (page Master Supplier). Hanya tampilan;
validasi ringan (nama wajib), simpan lewat `SupplierCtrl.save()` → `a_supplier_insert` / `a_supplier_update`.
Aturan final (nama beda kapital/spasi ditolak) ada di DB (`trg_supplier_check`); pesannya tampil di dalam widget.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±480 px; widget mengisi modal, tinggi ±320 px.

## Model masuk (Default model)

```js
{{ {
  key: SupplierCtrl.formKey,                  // naik setiap modal dibuka -> field diisi ulang
  mode: SupplierCtrl.isNew ? 'add' : 'edit',  // status hanya tampil saat edit
  form: SupplierCtrl.form,                    // { id, name, status }
  statusOptions: SupplierCtrl.statusOptions,  // [{ label, value }]
  busy: SupplierCtrl.busy,
  message: SupplierCtrl.message               // null | { type, text }
} }}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `cwSupplierForm.model.name`, `.status` | `{{SupplierCtrl.save()}}` |
| `onCancel` | – | `{{closeModal('mdlSupplier')}}` |
