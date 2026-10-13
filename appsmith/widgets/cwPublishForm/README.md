# cwPublishForm

Form **Terbitkan** revisi — page `Specsheet`, modal `mdlTerbit` → `SpecCtrl.publish()` → `a_revision_publish`
(`fn_revision_publish`); page `Cost Breakdown (CBD)`, modal `mdlCbdTerbit` → `CbdCtrl.publish()` → `a_cbd_publish`
(`fn_cbd_publish`, F8). Kode widget sama di kedua page; checklist, kategori & teks dari model.

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
  blockedWhere,      // opsional (F8): lokasi perbaikan di teks 'Perbaiki N hal di atas … sebelum terbit.'
                     //   default 'di grid BOM'; CBD: 'di grid / rekap CBD'
  busy, message      // message: null | { type, text }
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onPublish` | `.category`, `.reason` (sudah di-trim) | `{{SpecCtrl.publish()}}` / `{{CbdCtrl.publish()}}` |
| `onCancel` | – | `{{closeModal('mdlTerbit')}}` / `{{closeModal('mdlCbdTerbit')}}` |

## Gambar (F10b, R12)

- `.images` = `[{ name, data }]` (base64 tanpa awalan) ikut dikirim bersama `onPublish`; dilampirkan oleh
  `<Page>Ctrl.attachImages()` setelah terbit (`fn_change_log_attach`, maks. 5 gambar, maks. **3,5 MB** per gambar).
- R12 (T60): file asli boleh sampai 20 MB; gambar > 1 MB diperkecil di browser (sisi terpanjang maks. 2000 px,
  JPEG 85%, latar putih) sebelum dikirim. Hasil > 3,5 MB ditolak di form.
