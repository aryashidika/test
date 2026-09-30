# cwPublishForm

Form **Terbitkan** revisi specsheet — page `Specsheet`, modal `mdlTerbit` → `SpecCtrl.publish()` →
`a_revision_publish` (`fn_revision_publish`). Dipakai ulang untuk terbit CBD di F8 (checklist & kategori dari model).

Hanya tampilan. Checklist dihitung di DB (`v_revision_checklist`, query `q_publish_checklist`) dan disusun
`SpecCtrl.publishFormModel()`. Item penolak yang gagal → form & tombol **Terbitkan** disembunyikan, tampil
*Perbaiki N hal di atas…*. Aturan final di DB (checklist, kategori, alasan dicek lagi saat terbit).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±560 px; widget tinggi ±520 px.

## Model masuk (Default model)

```js
{
  key,               // naik setiap modal dibuka -> kategori & alasan direset
  title,             // 'Terbitkan FH25 · PULL r0'
  checks,            // [{ label, ok, blocking, detail }]  blocking=false -> peringatan (ikon !)
  blocked,           // true = ada item penolak gagal
  requiresReason,    // false = revisi awal (alasan opsional, kosong -> "Revisi awal.")
  categories,        // [{ value: 'MATERIAL', label: 'Material' }, …]
  defaultCategory,   // kategori terpilih saat dibuka ('' = belum dipilih)
  busy, message      // message: null | { type, text }
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onPublish` | `.category`, `.reason` (sudah di-trim) | `{{SpecCtrl.publish()}}` |
| `onCancel` | – | `{{closeModal('mdlTerbit')}}` |
