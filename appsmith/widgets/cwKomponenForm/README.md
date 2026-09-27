# cwKomponenForm

Form **Tambah / Usulkan / Ubah Komponen** di dalam modal `mdlKomponen` (page Master Komponen). Hanya tampilan;
simpan lewat `KomponenCtrl.save()` → `a_component_add` (`fn_component_add`) / `a_component_update`.

- Pilih kelompok → nomor terisi saran berikutnya (max + 10 atau awal rentang) dari `q_component_groups.next_no`.
  Kalau user sudah mengetik nomor sendiri, nomor tidak ditimpa; tombol **Pakai saran** mengisinya lagi.
- Cek ringan sebelum kirim: kelompok, nomor bulat, kelipatan 10, di rentang kelompok, nama wajib.
  Aturan final (termasuk nomor sudah dipakai) di DB (`trg_component_check`); pesannya tampil di dalam widget.
- Judul & tombol: Master Admin **Tambah/Simpan**, vendor **Usulkan** (+ info status PROPOSED). Status hanya tampil saat edit.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±480 px; widget mengisi modal, tinggi ±520 px (termasuk pesan error + info usulan).

## Model masuk (Default model)

```js
{{ {
  key: KomponenCtrl.formKey,                  // naik setiap modal dibuka -> field diisi ulang
  mode: KomponenCtrl.isNew ? 'add' : 'edit',
  form: KomponenCtrl.form,                    // { id, group_code, number, name, status }
  groups: KomponenCtrl.groups(),              // [{ code, name, range_start, range_end, next_no }]
  statusOptions: KomponenCtrl.statusOptions,  // [{ label, value }]
  canManage: KomponenCtrl.canManage(),        // false = vendor (usulan)
  busy: KomponenCtrl.busy,
  message: KomponenCtrl.message               // null | { type, text }
} }}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `cwKomponenForm.model.group_code`, `.number` (angka), `.name`, `.status` | `{{KomponenCtrl.save()}}` |
| `onCancel` | – | `{{closeModal('mdlKomponen')}}` |
