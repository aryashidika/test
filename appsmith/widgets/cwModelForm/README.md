# cwModelForm

Form **Tambah / Ubah Model** — dipakai di dua page:
- `Model List` (modal `mdlModel`, mode `add`) → `ModelCtrl.save()` → `a_model_add`
- `Model Detail` (modal `mdlModel`, mode `edit`) → `ModelDetailCtrl.saveModel()` → `a_model_update`

Hanya tampilan. Wajib: kode & nama model; field lain opsional (kosong disimpan NULL). Aturan final
(kode unik tidak peka huruf besar/kecil) di DB (`trg_model_check`); pesannya tampil di dalam widget.
Enter di field mana pun = simpan.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±560 px; widget tinggi ±640 px.

## Model masuk (Default model)

```js
{
  key,       // naik setiap modal dibuka -> field diisi ulang
  mode,      // 'add' | 'edit'
  form,      // { code, name, category, factory, outsole_mold, last_no, construction, size_range, sample_size }
  busy, message   // message: null | { type, text }
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `.code`, `.name`, `.category`, `.factory`, `.outsole_mold`, `.last_no`, `.construction`, `.size_range`, `.sample_size` | Model List: `{{ModelCtrl.save()}}` · Model Detail: `{{ModelDetailCtrl.saveModel()}}` |
| `onCancel` | – | `{{closeModal('mdlModel')}}` |
