# cwTempPassword

Menampilkan **password sementara** (user baru / reset password) satu kali di modal
`mdlPasswordSementara` (page Admin). Hanya tampilan. Dibuat oleh user (export v1).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

## Model masuk (Default model)

```js
{{ { email: AdminCtrl.tempFor, password: AdminCtrl.tempPassword } }}
```

## Event

| Event | Action |
|---|---|
| `onCopy` | `{{copyToClipboard(AdminCtrl.tempPassword); showAlert('Password disalin.', 'success')}}` |
| `onClose` | `{{AdminCtrl.closeTempPassword()}}` |
