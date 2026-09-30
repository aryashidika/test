# cwCbdGrid

Grid **baris CBD** page `Cost Breakdown (CBD)`: No, Komponen, Material, Thickness, Color, Supplier, UoM, Remarks,
**Yield**, Usage, **Loss %**, Harga, Cur, USD, IDR, Cost/pr (Rp), Asal. Dikelompokkan per grup komponen
(A Upper · B Bottom unit · C Packaging · D Miscellaneous); baris **MISSING_IN_SPEC** (tidak ada lagi di specsheet)
di bagian merah paling bawah, hanya baca dan tidak dihitung. Header & kolom No/Komponen menempel saat di-scroll.

Hanya tampilan & input. Usage (= 1 / Yield), harga IDR/USD, dan cost/pair dihitung di DB (`v_cbd_line`); widget
hanya memformat (format Indonesia). Aturan final di DB (`fn_cbd_line_set`, `trg_lock_published`); pesannya tampil
di bar atas grid.

- **Hanya baca** (`editable: false` — revisi terbit, article di-drop / belum terbit, atau role tanpa `edit_cbd`).
- **Draft**: Yield & Loss % berupa input yang tersimpan saat berubah (Enter / Tab / klik di luar). Enter pindah ke
  baris berikutnya di kolom yang sama; Esc membatalkan. Desimal pakai koma atau titik, tanpa pemisah ribuan.
  Yield kosong = dikosongkan; Loss % kosong = 0. Yield kosong di baris berharga ditandai kuning (wajib sebelum terbit, F8).
- Harga kosong diberi keterangan: *baris tanpa supplier*, *material quotation*, atau *belum ada harga master*.
  Input harga (quotation / override) ditambahkan di F8.
- Ketikan yang belum disimpan, fokus, dan posisi scroll dipertahankan saat data dimuat ulang.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: lebar penuh, tinggi ±600 px (scroll di dalam widget).

## Model masuk (Default model) — `{{CbdGridCtrl.gridModel()}}`

```js
{
  editable,       // true = revisi DRAFT, article ACTIVE di specsheet terbit, role edit_cbd
  lines,          // baris q_cbd_lines (v_cbd_line), urut: ACTIVE dulu, grup, nomor komponen, urutan
  exchangeRate,   // rate revisi (null = belum diisi)
  busy,           // ada aksi yang sedang disimpan
  message,        // null | { type, text }
  emptyText
}
```

## Nilai keluar & event

Satu event **`onAction`** → `{{CbdGridCtrl.onAction()}}`. Sebelumnya widget mengisi `.action`:

| `action.type` | Isi | Query |
|---|---|---|
| `setYield` | `line_id`, `value` (`'1.25'`, `''` = kosongkan) | `a_cbd_line_set` (`YIELD`) |
| `setLoss` | `line_id`, `value` (`'3.5'`, `''` = 0) | `a_cbd_line_set` (`LOSS`) |

Setiap aksi juga membawa `seq` (nomor urut) supaya dua aksi berurutan yang sama tetap terbaca berbeda.
