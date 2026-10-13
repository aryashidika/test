# cwStepper

Stepper stage **Pullover → Preview → SMS → GTM → Production** (R14; kode di model tetap `PULL`, `PREV`, `SMS`, `GTM`, `PROD`); di tiap stage ada chip revisi (`r0`, `r1`, …).
Dipakai di page `Specsheet` (F5) dan `Cost Breakdown (CBD)` (F7 — dengan baris chip article di atasnya).

Hanya tampilan. Chip DRAFT kuning bergaris putus, chip terpilih terisi, stage revisi terpilih bergaris bawah,
chip `needsRevision` (CBD terbit yang perlu revisi) bergaris merah. Revisi yang boleh dilihat ditentukan query
(Brand hanya menerima PUBLISHED).

Baris chip article hanya tampil bila model berisi `articles` (array) — Specsheet tidak mengirimnya, jadi tampilan
Specsheet tidak berubah (kode F7 boleh ditempel juga di Specsheet).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: lebar penuh, tinggi ±80 px (Specsheet) / ±130 px (CBD, dengan chip article).

## Model masuk (Default model)

```js
{
  revisions,          // [{ id, stage, revision_no, status, needsRevision? }]
  selectedId,         // id revisi yang sedang dibuka
  emptyText,          // teks bila belum ada revisi
  // opsional (CBD):
  articles,           // [{ id, code, colorway, badge, tone }]  tone: ok | draft | danger | info | muted
  selectedArticleId,
  articleEmptyText    // teks bila articles kosong
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSelect` | `.selectedId` | `{{SpecCtrl.selectRevision()}}` / `{{CbdCtrl.selectRevision()}}` |
| `onArticle` (CBD) | `.selectedArticleId` | `{{CbdCtrl.selectArticle()}}` |
