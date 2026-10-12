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
· **ringkasan menempel** (Exchange rate — satu-satunya yang diisi di sini; Material cost, Actual FOB, Target FOB,
Selisih + OVER/UNDER/SESUAI hanya baca) · area scroll: grid (+ baris **Subtotal** per grup, F8b) lalu di bawahnya
**Cost recapitulation** dan **Harga jual** (F8b; tidak ikut bergeser saat grid di-scroll ke kanan).

- **Hanya baca** (`editable: false` — revisi terbit, article di-drop / belum terbit, atau role tanpa `edit_cbd`).
- **Draft**: Yield & Loss % berupa input yang tersimpan saat berubah (Enter / Tab / klik di luar). Enter pindah ke
  baris berikutnya di kolom yang sama; Esc membatalkan. Desimal pakai koma atau titik, tanpa pemisah ribuan.
  Yield kosong = dikosongkan; Loss % kosong = 0. Yield kosong di baris berharga ditandai kuning (wajib sebelum terbit).
- **Exchange rate** (draft, panel atas): wajib, kotak kuning bila kosong. Angka uang ambigu seperti `16.250` ditolak.
- **Cost recapitulation** (F8b, keputusan user 5 Okt 2026): `a.` Material cost (otomatis) + baris biaya `q_cbd_cost_items`
  dengan jenis tetap Direct Labour (LOP) / Amortisasi / Adjustment / Lainnya. Draft: uraian, nilai (Rp; hanya
  Adjustment boleh minus), keterangan diedit di sel; baris default (Direct Labour, Amortisasi, Adjustment) tidak bisa
  dihapus; baris **+** untuk menambah (isian tetap saat render ulang, dikosongkan saat `costOkKey` berubah). Lalu
  ACTUAL FOB, Target FOB (input), Selisih.
- **Harga jual** (F8b): Selling price ⇄ Margin % saling terhubung (dihitung DB).
- **Harga** (draft, baris ACTIVE): material Quotation → **Isi harga / Ubah harga**; material katalog → **Override…**
  atau **Hapus override**. Harga kosong diberi keterangan (`price_gap`): material quotation belum diisi, supplier belum
  dipilih, harga master tersedia (refresh), menunggu approval, belum ada harga untuk warna ini (ada: …), belum ada
  harga master. Harga master yang berubah ditandai *harga master berubah — klik Refresh Harga*.
- Ketikan yang belum disimpan, fokus, dan posisi scroll dipertahankan saat data dimuat ulang.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: lebar penuh, tinggi ±800 px (F8b: tabel Cost recapitulation & Harga jual di bawah grid, ikut scroll di dalam widget).

## Model masuk (Default model) — `{{CbdGridCtrl.gridModel()}}`

```js
{
  editable,       // true = revisi DRAFT, article ACTIVE di specsheet terbit, role edit_cbd
  lines,          // baris q_cbd_lines (v_cbd_line + master_stale, price_gap, other_colors, master_price, master_currency)
                  // urut: ACTIVE dulu, grup, nomor komponen, urutan
  recap,          // baris q_cbd_recap (v_cbd_recap, + group_costs { a: subtotal, … }) atau null
  costItems,      // baris q_cbd_cost_items [{ id, item_type, name, amount, remarks, is_default }] (F8b)
  costOkKey,      // naik setelah tambah biaya berhasil -> form tambah dikosongkan (F8b)
  doneSeq,        // seq aksi terakhir yang selesai di CbdGridCtrl (ack antrean aksi)
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
| `setHeader` | `field` (`RATE`/`TARGET_FOB`/`SELLING_PRICE`/`MARGIN`), `value` | `a_cbd_header_set` |
| `addCost` | `item_type`, `name`, `amount` (`''` = 0), `remarks` | `a_cbd_cost_add` (F8b) |
| `setCost` | `item_id`, `field` (`NAME`/`AMOUNT`/`REMARKS`), `value` | `a_cbd_cost_set` (F8b) |
| `deleteCost` | `item_id` | `a_cbd_cost_delete` (konfirmasi ON, F8b) |
| `editPrice` | `line_id`, `mode` (`QUOTATION`/`OVERRIDE`) | buka modal `mdlCbdHarga` (`cwCbdPriceForm`) |
| `clearOverride` | `line_id` | `a_cbd_clear_override` (konfirmasi ON) |
| `refreshPrices` | – | `a_cbd_refresh_prices` |
| `refreshSpec` | – | `a_cbd_refresh_spec` (konfirmasi ON) |

Setiap aksi membawa `seq` (naik terus, berbasis waktu). Aksi dikirim **satu per satu**: berikutnya baru dikirim setelah
CbdGridCtrl membalas `doneSeq >= seq` (sesudah query + muat ulang data). Tanpa balasan 5 detik, aksi dikirim ulang;
CbdGridCtrl mengabaikan `seq` yang sudah selesai. Nilai yang sudah dikirim tetap tampil sampai antrean kosong. Sel juga
disimpan saat blur (nilai yang dipulihkan setelah render ulang tidak memicu `change`).

## Perubahan R3–R7 (11 Okt 2026)

R5: `recap` tanpa `selling_price`/`margin_pct`, + `stage`, `po_factor`, `po_price` → baris **PO <stage> (× faktor)** di panel atas & Cost recapitulation (kosong bila stage tanpa faktor). `lines[]` + `pending` (usulan harga menunggu → CBD tidak bisa terbit); `price_gap` NO_COLOR_PRICE dihapus. Tabel Harga jual diganti **Simulasi harga jual** (hanya bila `canSimulate` = izin `simulate_margin`): dihitung di layar dari Actual FOB, tidak mengirim event, tidak disimpan.
