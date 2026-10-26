# cwCbdPriceForm

Form **harga baris CBD** di modal `mdlCbdHarga` (page `Cost Breakdown (CBD)`). Dibuka dari tombol **Isi harga** /
**Ajukan harga master** (R8) di kolom Harga `cwCbdGrid`. Hanya tampilan; simpan lewat `CbdGridCtrl.savePrice()`.

- **QUOTATION** (material metode Quotation): harga + currency, referensi opsional. Harga **kosong** = baris tidak
  dihargai terpisah (cost 0) → `fn_cbd_set_quotation` mengosongkan harga.
- **PROPOSE** (R8, material katalog; mengganti OVERRIDE yang dihapus F10b): ajukan **harga master** untuk Material Code
  + supplier baris itu - harga, currency & **berlaku mulai** (default hari ini) wajib, referensi opsional →
  `fn_cbd_price_propose` → `fn_price_propose` (usulan PROPOSED, disetujui di page Persetujuan Harga; berlaku untuk
  semua CBD setelah Refresh Harga). `direct = true` (Manager Costing): langsung berlaku, tombol **Simpan**.
- **ESTIMATE** (R17, baris katalog **tanpa Material Code** di Pullover / Preview): isian sama dengan QUOTATION (kosong =
  hapus estimasi) → `fn_cbd_set_quotation` menyimpan sumber `ESTIMATE`. Kotak kuning **Last estimate** + tombol **Use**
  (`model.suggestion`) mengisi harga, currency, dan referensi (bila masih kosong).
- **Currency tanpa nilai awal - wajib diklik IDR/USD setiap input** (keputusan user 27 Sep 2026). R17: kecuali
  `form.currency` diisi (estimasi yang sedang diubah, atau isian awal PROPOSE dari estimasi terakhir).
- Angka ambigu seperti `47.500` ditolak; widget menampilkan "Terbaca: …".

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±560 px, *close on outside click* OFF; widget tinggi ±520 px.

## Model masuk (Default model) - `{{CbdGridCtrl.priceFormModel()}}`

```js
{
  key,          // naik setiap modal dibuka -> isian direset
  mode,         // 'QUOTATION' | 'ESTIMATE' (R17) | 'PROPOSE'
  direct,       // R8: true = Manager Costing (harga master langsung berlaku)
  today,        // 'YYYY-MM-DD' (default berlaku mulai, mode PROPOSE)
  title,        // 'Harga Quotation' / 'Ajukan Harga Master' / 'Harga Master Baru'
  lineLabel,    // '10 · Upper · MTR-0001 Kulit … · Black · PT Maju Jaya'
  current,      // teks harga sekarang ('' = tidak tampil)
  form,         // { price: '45000' (teks, titik desimal), currency: '' | 'IDR' | 'USD' (R17), text: 'referensi' }
  suggestion,   // R17, mode ESTIMATE: null | { price, currency, label, reference } estimasi terakhir
  info,         // teks info tambahan ('' = tidak tampil)
  busy, message // message: null | { type, text }
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `.price` (teks angka titik desimal, `''` = kosong), `.currency` (`''` bila harga kosong), `.text` (referensi, di-trim), `.valid_from` (PROPOSE, `''` di QUOTATION) | `{{CbdGridCtrl.savePrice()}}` |
| `onCancel` | – | `{{closeModal('mdlCbdHarga')}}` |
