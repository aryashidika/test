# cwLinkForm

Form **Tambah / Ubah Supplier Material** di modal `mdlLink` (page `Material Detail`). Hanya tampilan;
simpan lewat `MaterialDetailCtrl.saveLink()` → `fn_link_save`.

- Tambah: pilih supplier (yang aktif & belum terdaftar), kode di supplier, supplier utama.
  Tim specsheet → PROPOSED, Master Admin → APPROVED (ditentukan DB).
- Ubah: supplier tampil read-only; kode & supplier utama (`canLink`), status (`canStatus`, Master Admin).
- Maks. satu supplier utama per material; status INACTIVE otomatis melepas tanda utama (di DB).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±480 px; widget tinggi ±480 px.

## Model masuk (Default model)

```js
{{ MaterialDetailCtrl.linkFormModel() }}
// { key, mode: 'add'|'edit', form: { id, supplier_id, supplier_name, supplier_material_code, is_preferred, status },
//   materialLabel, supplierOptions: [{ label, value }], statusOptions, canLink, canStatus, busy, message }
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `.supplier_id`, `.supplier_material_code`, `.is_preferred`, `.status` | `{{MaterialDetailCtrl.saveLink()}}` |
| `onCancel` | – | `{{closeModal('mdlLink')}}` |
