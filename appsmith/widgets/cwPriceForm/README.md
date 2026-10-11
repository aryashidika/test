# cwPriceForm

Form harga di modal `mdlHarga` (page `Material Detail`, R3). Hanya tampilan; simpan lewat
`MaterialDetailCtrl.savePrice()` → `fn_price_propose` / `fn_price_copy`. Semua hasil = **usulan PROPOSED**
yang baru dipakai setelah disetujui Manager Costing (page Persetujuan Harga).

- **mode `propose` (Ajukan Harga)**: supplier material (ACTIVE), **centang banyak varian** (cari, Pilih semua,
  Kosongkan; status per varian untuk supplier terpilih: berlaku / menunggu / belum ada harga — varian yang masih
  punya usulan menunggu tidak bisa dicentang), satu harga, **currency tanpa nilai awal — wajib diklik IDR/USD**,
  berlaku mulai (default hari ini WIB), referensi. Tanggal lebih awal dari harga yang sudah ada ditolak.
- **mode `copy` (Salin Harga)**: varian sumber (hanya yang punya harga BERLAKU dari supplier aktif) → centang
  varian tujuan; semua harga berlaku sumber (per supplier) diajukan untuk tiap tujuan. Pasangan yang masih punya
  usulan menunggu dilewati (dilaporkan). Referensi kosong = "Salin dari <kode>".
- Angka ambigu seperti `47.500` (titik ribuan) ditolak; desimal koma/titik, maks. 4 desimal.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |
| `extra.css` | tambahan R3 (sudah digabung ke `style.css`) |

Ukuran: modal kolom 14–50, tinggi 760 px; widget ±740 px.

## Model masuk (Default model)

```js
{{MaterialDetailCtrl.priceFormModel()}}
// { key, mode: 'propose' | 'copy', materialLabel,
//   links: [{ label, value }],                                   // supplier material ACTIVE
//   variants: [{ id, code, color, thickness_label }],            // varian ACTIVE
//   prices: [{ link_id, variant_id, supplier_name, price, currency, valid_from, state }],
//                                                                // BERLAKU / AKAN BERLAKU / MENUNGGU APPROVAL
//   preset: { link_id, variant_ids: [] },                        // dari tombol Ajukan di baris tabel
//   today: 'YYYY-MM-DD', busy, message }
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | propose: `.mode`, `.link_id`, `.variant_ids` (array), `.price` (teks angka, titik desimal), `.currency`, `.valid_from`, `.reference` · copy: `.mode`, `.source_id`, `.variant_ids`, `.valid_from`, `.reference` | `{{MaterialDetailCtrl.savePrice()}}` |
| `onCancel` | – | `{{closeModal('mdlHarga')}}` |
