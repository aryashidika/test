# cwCbdGrid

Grid **baris CBD** + **rekap** + **banner refresh** page `Cost Breakdown (CBD)`: No, Komponen, Material, Thickness, Color, Supplier, UoM, Remarks,
**Yield**, Usage, **Loss %**, Harga, Cur, USD, IDR, Cost/pr (Rp), Asal. Dikelompokkan per grup komponen
(A Upper · B Bottom unit · C Packaging · D Miscellaneous); baris **MISSING_IN_SPEC** (tidak ada lagi di specsheet)
di bagian merah paling bawah, hanya baca dan tidak dihitung. Header & kolom No/Komponen menempel saat di-scroll.

Hanya tampilan & input. Usage (= 1 / Yield), harga IDR/USD, cost/pair, dan rekap dihitung di DB (`v_cbd_line`,
`v_cbd_recap`, `v_cbd_price_check`); widget hanya memformat (format Indonesia). Aturan final di DB (`fn_cbd_*`,
`trg_lock_published`); pesannya tampil di bar atas grid.

Susunan (atas → bawah): bar pesan + status · **banner** (dari `CbdGridCtrl.banners()`: specsheet baru → tombol
**Refresh dari Specsheet**; harga master berubah → **Refresh Harga dari Master**; info baris tanpa harga / supplier)
· **rekap menempel** (Exchange rate, Material cost, Amortisasi, Adjustment, Actual FOB, Target FOB, Selisih +
OVER/UNDER/SESUAI, Selling price, Margin %) · grid (scroll di dalam widget).

- **Hanya baca** (`editable: false` — revisi terbit, article di-drop / belum terbit, atau role tanpa `edit_cbd`).
- **Draft**: Yield & Loss % berupa input yang tersimpan saat berubah (Enter / Tab / klik di luar). Enter pindah ke
  baris berikutnya di kolom yang sama; Esc membatalkan. Desimal pakai koma atau titik, tanpa pemisah ribuan.
  Yield kosong = dikosongkan; Loss % kosong = 0. Yield kosong di baris berharga ditandai kuning (wajib sebelum terbit).
- **Rekap** (draft): Exchange rate (wajib, kotak kuning bila kosong), Amortisasi, Adjustment (boleh minus), Target FOB,
  Selling price, Margin % diedit langsung; Selling price ⇄ Margin % saling terhubung (dihitung DB). Angka uang
  ambigu seperti `16.250` ditolak.
- **Harga** (draft, baris ACTIVE): material Quotation → **Isi harga / Ubah harga**; material katalog → **Override…**
  atau **Hapus override**. Harga kosong diberi keterangan (`price_gap`): material quotation belum diisi, supplier belum
  dipilih, harga master tersedia (refresh), menunggu approval, belum ada harga untuk warna ini (ada: …), belum ada
  harga master. Harga master yang berubah ditandai *harga master berubah — klik Refresh Harga*.
- Ketikan yang belum disimpan, fokus, dan posisi scroll dipertahankan saat data dimuat ulang.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: lebar penuh, tinggi ±680 px (F8: + banner & rekap; grid scroll di dalam widget).

## Model masuk (Default model) — `{{CbdGridCtrl.gridModel()}}`

```js
{
  editable,       // true = revisi DRAFT, article ACTIVE di specsheet terbit, role edit_cbd
  lines,          // baris q_cbd_lines (v_cbd_line + master_stale, price_gap, other_colors, master_price, master_currency)
                  // urut: ACTIVE dulu, grup, nomor komponen, urutan
  recap,          // baris q_cbd_recap (v_cbd_recap) atau null
  banners,        // [{ tone: 'danger'|'warn'|'info', text, action?: 'refreshSpec'|'refreshPrices', actionLabel? }]
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
| `setHeader` | `field` (`RATE`/`AMORTIZATION`/`ADJUSTMENT`/`TARGET_FOB`/`SELLING_PRICE`/`MARGIN`), `value` | `a_cbd_header_set` |
| `editPrice` | `line_id`, `mode` (`QUOTATION`/`OVERRIDE`) | buka modal `mdlCbdHarga` (`cwCbdPriceForm`) |
| `clearOverride` | `line_id` | `a_cbd_clear_override` (konfirmasi ON) |
| `refreshPrices` | – | `a_cbd_refresh_prices` |
| `refreshSpec` | – | `a_cbd_refresh_spec` (konfirmasi ON) |

Setiap aksi juga membawa `seq` (nomor urut) supaya dua aksi berurutan yang sama tetap terbaca berbeda.
