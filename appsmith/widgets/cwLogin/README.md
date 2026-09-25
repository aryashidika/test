# cwLogin

Custom Widget di page **Login**: form *Masuk* dan *Ganti Password* (wajib setelah password sementara,
atau dibuka dari Beranda lewat `?mode=ganti`). Hanya tampilan — keputusan ada di JSObject `LoginCtrl`
dan function DB (`fn_login`, `fn_change_password`).

| File | Tab di editor Custom Widget |
|---|---|
| `index.html` | HTML |
| `style.css` | Style |
| `script.js` | JavaScript |

## Model masuk (properti **Default model**)

```js
{{ {
  appName: 'Sistem Specsheet & CBD',
  view: LoginCtrl.view,         // 'login' | 'change'
  busy: LoginCtrl.busy,         // true saat query berjalan -> tombol nonaktif
  forced: LoginCtrl.forced,     // true = wajib ganti password (tombol Batal jadi "Keluar")
  message: LoginCtrl.message,   // null | { type: 'error' | 'info' | 'success', text }
  email: LoginCtrl.lastEmail    // isi awal field email
} }}
```

## Nilai keluar (ditulis widget lewat `appsmith.updateModel`)

| Field | Diisi saat | Dibaca oleh |
|---|---|---|
| `cwLogin.model.email`, `cwLogin.model.password` | klik **Masuk** / Enter | `LoginCtrl.login()` |
| `cwLogin.model.oldPass`, `cwLogin.model.newPass` | klik **Simpan** di Ganti Password | `LoginCtrl.changePassword()` |

## Event (tambahkan di property pane → Events)

| Event | Action |
|---|---|
| `onLogin` | `{{LoginCtrl.login()}}` |
| `onChangePassword` | `{{LoginCtrl.changePassword()}}` |
| `onCancelChange` | `{{LoginCtrl.cancelChange()}}` |

## Validasi di widget (sebelum event dikirim)

Email & password wajib; password baru ≥ 8 karakter, sama dengan konfirmasi, dan berbeda dari password lama.
Aturan yang sama dicek ulang di `fn_change_password`.

## Catatan

- Password dikosongkan dari layar setiap kali `busy` kembali `false`.
- Warna utama, radius, dan font mengikuti tema app (`appsmith.theme`); nilai default = palet mockup.
- Mengubah teks/tampilan: edit file di sini, tempel ulang ke tab yang sesuai, lalu commit.
