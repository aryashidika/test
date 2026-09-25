# cwMenu

Kartu menu di **Beranda**, difilter sesuai izin role. Hanya tampilan. Dibuat oleh user (export v1).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

## Model masuk (Default model)

```js
{{ {
  loaded: Auth.loaded && !!Auth.me,
  title: 'Menu',
  subtitle: 'Pilih menu sesuai pekerjaan Anda.',
  items: [
    { key: 'master', title: 'Master Data', desc: '…', target: '<nama page>', icon: 'database', show: Auth.can('view_master') },
    // …
  ].filter(item => item.show)
} }}
```

`items[]`: `key`, `title`, `desc`, `target` (**nama page persis** untuk `navigateTo`), `icon`
(`database` · `layers` · `users` · `list` · `file`), `badge` (opsional, mis. jumlah tugas).

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onOpen` | `cwMenu.model.target`, `cwMenu.model.key` | `{{navigateTo(cwMenu.model.target)}}` |
