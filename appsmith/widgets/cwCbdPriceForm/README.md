# cwCbdPriceForm

Form **harga baris CBD** di modal `mdlCbdHarga` (page `Cost Breakdown (CBD)`). Dibuka dari tombol **Isi harga** /
**Override…** di kolom Harga `cwCbdGrid`. Hanya tampilan; simpan lewat `CbdGridCtrl.savePrice()`.

- **QUOTATION** (material metode Quotation): harga + currency, referensi opsional. Harga **kosong** = baris tidak
  dihargai terpisah (cost 0) → `fn_cbd_set_quotation` mengosongkan harga.
- **OVERRIDE** (material katalog): harga khusus baris ini, **alasan wajib** → `fn_cbd_override_price`.
  Harga untuk semua CBD (termasuk harga khusus warna) diisi di Master Material, bukan override.
- **Currency tanpa nilai awal — wajib diklik IDR/USD setiap input** (keputusan user 27 Sep 2026).
- Angka ambigu seperti `47.500` ditolak; widget menampilkan "Terbaca: …".

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±560 px, *close on outside click* OFF; widget tinggi ±520 px.

## Model masuk (Default model) — `{{CbdGridCtrl.priceFormModel()}}`

```js
{
  key,          // naik setiap modal dibuka -> isian direset
  mode,         // 'QUOTATION' | 'OVERRIDE'
  title,        // 'Harga Quotation' / 'Override Harga'
  lineLabel,    // '10 · Upper · MTR-0001 Kulit … · Black · PT Maju Jaya'
  current,      // teks harga sekarang ('' = tidak tampil)
  form,         // { price: '45000' (teks, titik desimal), text: 'referensi / alasan' } — currency tidak diisi
  info,         // teks info tambahan ('' = tidak tampil)
  busy, message // message: null | { type, text }
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `.price` (teks angka titik desimal, `''` = kosong), `.currency` (`''` bila harga kosong), `.text` (referensi / alasan, di-trim) | `{{CbdGridCtrl.savePrice()}}` |
| `onCancel` | – | `{{closeModal('mdlCbdHarga')}}` |
