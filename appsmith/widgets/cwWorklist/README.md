# cwWorklist

Daftar **Tugas Saya** di page `Beranda` (F10): baris ringkasan (angka yang bisa diklik → loncat ke bagiannya) dan bagian
berisi tugas. Satu widget dipakai semua role — isi per role disusun `BerandaCtrl.model()`; widget tidak tahu role.

Hanya tampilan. Tiap bagian menampilkan **6 tugas pertama** + tombol *Tampilkan semua (n)*. Tugas yang punya `target`
bisa diklik (tombol `→`), yang tidak punya tampil sebagai teks. Tombol **↻ Muat ulang** menjalankan ulang query role itu.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: lebar penuh (kolom 0–64), tinggi ±640 px (isi lebih panjang → scroll di dalam widget).

## Model masuk (Default model)

```js
{{BerandaCtrl.model()}}
```

```js
{
  loaded,            // false -> kerangka (skeleton)
  loading,           // true -> tombol Muat ulang nonaktif ("Memuat…")
  title,             // 'Tugas Saya'
  subtitle,          // teks pendek di bawah judul
  columns,           // 1 (default) | 2 — jumlah kolom bagian (Brand: 2)
  stats: [{ key, value, label, tone }],
                     // key = key bagian tujuan (klik -> scroll); tone: info | warn | ok — hanya berwarna bila value > 0
  sections: [{
    key, title, note, // note = teks kecil di bawah judul (opsional)
    empty,           // teks bila tidak ada tugas
    hideWhenEmpty,   // true -> bagian disembunyikan bila kosong
    items: [{
      title, meta,   // baris utama & keterangan kecil
      flags: [{ text, tone, hint }],   // lencana di kanan; tone: info | warn | danger | ok (kosong = abu-abu); hint = tooltip
      target,        // NAMA PAGE persis untuk navigateTo (kosong = tidak bisa diklik)
      params         // objek parameter URL, mis. { model_id, season, from: 'home' }
    }]
  }]
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onOpen` | `cwWorklist.model.target`, `cwWorklist.model.params` | `{{BerandaCtrl.open()}}` |
| `onRefresh` | – | `{{BerandaCtrl.reload()}}` |

`BerandaCtrl.open()` membaca `target` & `params` dari model **sebelum** state JSObject berubah (model di-reset saat
Default model berubah), lalu `navigateTo(target, params)`.
