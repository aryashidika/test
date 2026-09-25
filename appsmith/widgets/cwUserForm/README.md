# cwUserForm

Form **Tambah/Ubah User** di dalam modal `mdlUser` (page Admin). Hanya tampilan; validasi ringan
(email, nama, role wajib), simpan lewat `AdminCtrl.save()` → `fn_user_save`. Dibuat oleh user (export v1).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

## Model masuk (Default model)

```js
{{ {
  key: AdminCtrl.formKey,             // naik setiap modal dibuka -> field diisi ulang
  mode: AdminCtrl.isNew ? 'add' : 'edit',
  form: AdminCtrl.form,               // { email, full_name, role, is_active }
  roleOptions: AdminCtrl.roleOptions, // [{ label, value }]
  selfEmail: Auth.me ? Auth.me.email : '',   // akun sendiri: role & status dikunci
  busy: AdminCtrl.busy,
  message: AdminCtrl.message          // null | { type, text }
} }}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `cwUserForm.model.email`, `.full_name`, `.role`, `.is_active` | `{{AdminCtrl.save()}}` |
| `onCancel` | – | `{{closeModal('mdlUser')}}` |
