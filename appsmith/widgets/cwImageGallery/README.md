# cwImageGallery

Galeri gambar change log (F10b) di modal **Riwayat** page `Specsheet` (`mdlRiwayat`) dan `Cost Breakdown (CBD)`
(`mdlCbdRiwayat`). Pilih baris riwayat → gambarnya tampil di sini; klik gambar → diperbesar di dalam widget
(‹ › / panah kiri-kanan untuk pindah, Esc untuk tutup, **Unduh**).

Hanya tampilan. Gambar dimuat `q_change_log_images` (base64) oleh `SpecCtrl.showImages()` / `CbdCtrl.showImages()`.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: lebar penuh modal, tinggi ±220 px (gambar diperbesar memakai seluruh tinggi widget).

## Model masuk (Default model)

```js
{{SpecCtrl.galleryModel()}}   // atau {{CbdCtrl.galleryModel()}}
```

```js
{
  title,       // 'Gambar SMS r0'
  emptyText,   // teks bila belum dipilih / tidak ada gambar
  loading,     // true -> "Memuat gambar…"
  images: [{ id, name, mime, size, data }]   // data = base64 tanpa awalan
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onDownload` | `cwImageGallery.model.downloadId` | `{{SpecCtrl.downloadImage()}}` / `{{CbdCtrl.downloadImage()}}` |
