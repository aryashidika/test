# cwStepper

Stepper stage **PULL → SMS → GTM → PROD**; di tiap stage ada chip revisi (`r0`, `r1`, …).
Dipakai di page `Specsheet` (F5), nanti juga `Cost Breakdown (CBD)` (F7 — ditambah baris chip article).

Hanya tampilan. Chip DRAFT kuning bergaris putus, chip terpilih terisi, stage revisi terpilih bergaris bawah.
Revisi yang boleh dilihat ditentukan query (Brand hanya menerima PUBLISHED).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: lebar penuh, tinggi ±80 px.

## Model masuk (Default model)

```js
{
  revisions,    // [{ id, stage, revision_no, status }]  (q_revisions)
  selectedId,   // id revisi yang sedang dibuka
  emptyText     // teks bila belum ada revisi, mis. 'Belum ada revisi. Klik + Buat Revisi.'
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSelect` | `.selectedId` | `{{SpecCtrl.selectRevision()}}` |
