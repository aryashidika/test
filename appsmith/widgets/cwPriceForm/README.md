# cwPriceForm

Form **Tambah Harga** di modal `mdlHarga` (page `Material Detail`). Hanya tampilan; simpan lewat
`MaterialDetailCtrl.savePrice()` → `fn_price_add`.

- Supplier (link aktif), warna (kosong = semua warna, saran dari warna yang pernah diberi harga), harga,
  **currency tanpa nilai awal — wajib diklik IDR/USD setiap input** (keputusan user 27 Sep 2026),
  berlaku mulai (default hari ini WIB), referensi.
- Angka ambigu seperti `47.500` / `1.250.000` (titik ribuan) ditolak supaya tidak terbaca 47,5.
- Harga: angka tanpa titik ribuan, desimal koma/titik, maks. 4 desimal; widget menampilkan "Terbaca: …".
- Kalau supplier + warna sudah punya harga yang masih berlaku, widget menampilkan info bahwa harga itu
  akan ditutup, dan menolak tanggal yang lebih awal (aturan final di DB).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±560 px; widget tinggi ±630 px.

## Model masuk (Default model)

```js
{{ MaterialDetailCtrl.priceFormModel() }}
// { key, materialLabel, links: [{ label, value }], form: { link_id, color }, colorSuggestions: [],
//   openPrices: [{ link_id, color, price, currency, valid_from }], today: 'YYYY-MM-DD', busy, message }
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `.link_id`, `.color`, `.price` (teks angka, titik desimal), `.currency`, `.valid_from` (YYYY-MM-DD), `.reference` | `{{MaterialDetailCtrl.savePrice()}}` |
| `onCancel` | – | `{{closeModal('mdlHarga')}}` |
