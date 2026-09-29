# cwReasonForm

Form **alasan** umum di dalam modal (dipakai ulang). Pertama dipakai di F3b: modal `mdlTolakHarga`
(page `Material Detail`) untuk **Tolak usulan harga** → `MaterialDetailCtrl.saveReject()` → `fn_price_reject`.
Nanti bisa dipakai lagi untuk alasan override harga CBD / alasan terbit revisi.

Hanya tampilan; semua teks dari model. Validasi: alasan minimal `minLength` karakter (default 3).
Ctrl+Enter = simpan.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±480 px; widget tinggi ±400 px.

## Model masuk (Default model)

```js
{
  key,            // naik setiap modal dibuka -> isian dikosongkan
  title,          // mis. 'Tolak Usulan Harga'
  summary,        // teks ringkasan di atas (boleh multi-baris), opsional
  label,          // label field, mis. 'Alasan penolakan'
  placeholder, hint,
  confirmLabel,   // teks tombol simpan, mis. 'Tolak'
  danger,         // true = tombol merah
  minLength,      // opsional, default 3
  busy, message   // message: null | { type, text }
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action (contoh F3b) |
|---|---|---|
| `onSave` | `.reason` | `{{MaterialDetailCtrl.saveReject()}}` |
| `onCancel` | – | `{{closeModal('mdlTolakHarga')}}` |
