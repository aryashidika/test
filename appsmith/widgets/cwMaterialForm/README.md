# cwMaterialForm

Form **Tambah / Usulkan / Ubah Material** - dipakai di dua page:
- `Master Material` (modal `mdlMaterial`, mode `add`) → `MaterialCtrl.save()` → `fn_material_add`
- `Material Detail` (modal `mdlMaterial`, mode `edit`) → `MaterialDetailCtrl.saveMaterial()` → `fn_material_update`

Hanya tampilan. Field dikunci sesuai model: identitas (kode, nama, kategori, thickness, UoM) hanya kalau
`canIdentity`, metode harga hanya kalau `canPriceMethod`, status hanya saat edit + `canStatus`.
Material Code & UoM dikirim huruf besar. Aturan final (duplikat kode / nama+thickness+UoM) di DB
(`trg_material_check`); pesannya tampil di dalam widget.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±560 px; widget tinggi ±650 px.

## Model masuk (Default model)

```js
{
  key,                 // naik setiap modal dibuka -> field diisi ulang
  mode,                // 'add' | 'edit'
  form,                // { material_code, name, category, thickness, uom, price_method, status }
  nextCode,            // saran MTR-NNNN (add: terisi otomatis + tombol "Pakai saran")
  categories, uoms,    // saran isian (datalist)
  statusOptions,       // [{ label, value }]
  canManage,           // false = vendor (judul/tombol "Usulkan")
  canIdentity,         // boleh ubah identitas (add: true; edit: manage_master)
  canPriceMethod,      // boleh ubah metode harga (add: true; edit: manage_price)
  canStatus,           // tampilkan status (edit + manage_master)
  busy, message        // message: null | { type, text }
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `.material_code`, `.name`, `.category`, `.thickness`, `.uom`, `.price_method`, `.status` | Master Material: `{{MaterialCtrl.save()}}` · Material Detail: `{{MaterialDetailCtrl.saveMaterial()}}` |
| `onCancel` | – | `{{closeModal('mdlMaterial')}}` |
