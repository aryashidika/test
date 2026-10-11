# cwPriceApproval

Page **Persetujuan Harga** (R3, Manager Costing — izin `approve_price`). Usulan harga material yang menunggu,
dikelompokkan per **pengajuan** (satu kali Ajukan / Salin harga oleh Vendor CBD). Per pengajuan: tabel varian ×
supplier dengan harga berlaku sekarang, usulan, selisih %, tombol **Setujui semua / Setujui terpilih / Tolak terpilih**.

Hanya tampilan. Keputusan dijalankan `ApprovalCtrl.decide()` → `fn_price_decide` (semua baris atau tidak sama sekali).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: lebar penuh (kolom 0–64), tinggi ±860 px (isi lebih panjang → scroll di dalam widget).

## Model masuk (Default model)

```js
{{ApprovalCtrl.model()}}
```

```js
{
  loaded, loading, busy,
  message,          // { type: 'success' | 'error' | 'info', text } — hasil keputusan terakhir
  focusBatch,       // batch_id dari URL ?batch= (Beranda) -> kartu itu paling atas + disorot
  batches: [{
    batch_id, material_id, material_name, uom, proposed_by, proposed_at,
    items: [{ id, code, color, thickness_label, supplier_name, price, currency, valid_from, reference,
              cur_price, cur_currency, cur_valid_from,   // harga APPROVED terbuka yang akan ditutup (null = baru)
              problem }]                                 // teks alasan tidak bisa disetujui (null = bisa)
  }]
}
```

## Perilaku
- Setujui (semua / terpilih) = **dua klik** (klik pertama mengubah teks tombol, berlaku 5 detik).
- "Setujui semua" hanya mengirim usulan tanpa `problem`; "Setujui terpilih" nonaktif bila pilihan berisi usulan ber-`problem`.
- Tolak terpilih membuka kotak alasan (wajib) di bawah kartu.
- Pilihan & teks alasan tetap tersimpan saat model berubah; baris yang sudah diproses otomatis keluar dari pilihan.

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onDecide` | `model.action = { decision: 'APPROVE' \| 'REJECT', ids: [...], reason, batch_id }` | `{{ApprovalCtrl.decide()}}` |
| `onOpenMaterial` | `model.material_id` | `{{ApprovalCtrl.openMaterial()}}` |
| `onRefresh` | – | `{{ApprovalCtrl.reload()}}` |
