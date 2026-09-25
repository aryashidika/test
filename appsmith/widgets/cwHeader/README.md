# cwHeader

Header aplikasi di atas setiap page (kecuali Login): nama app, judul page, nama + role user, tombol
**Beranda**, **Ganti Password**, **Keluar**. Hanya tampilan. Dibuat oleh user (export v1), dipakai di
`Beranda` dan `Admin`; akan dipasang juga di page lain.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

## Model masuk (Default model) — yang berbeda per page hanya `pageTitle` dan `showHome`

```js
{{ {
  appName: 'Sistem Specsheet & CBD',
  pageTitle: 'Admin',                 // judul page
  name: Auth.me?.full_name ?? '',
  email: Auth.me?.email ?? '',
  role: Auth.me?.role_label ?? '',
  showHome: true                      // false di Beranda
} }}
```

## Event

| Event | Action |
|---|---|
| `onHome` | `{{navigateTo('Beranda')}}` |
| `onChangePassword` | `{{navigateTo('Login', { mode: 'ganti' })}}` |
| `onLogout` | `{{navigateTo('Login', { mode: 'keluar' })}}` |
