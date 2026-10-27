# cwArticleForm

Form **Tambah / Ubah Article** - page `Model Detail`, modal `mdlArticle` → `ModelDetailCtrl.saveArticle()`
→ `a_article_add` / `a_article_update`.

Hanya tampilan. Wajib: kode & colorway. Kode dikunci (`codeLocked`) kalau article sudah dipakai di
specsheet/CBD. Aturan final di DB (`trg_article_check`: kode unik per season tidak peka huruf besar/kecil,
maks. 5 article per season, kode terpakai terkunci); pesannya tampil di dalam widget. Enter = simpan.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±480 px; widget tinggi ±360 px.

## Model masuk (Default model)

```js
{
  key,          // naik setiap modal dibuka -> field diisi ulang
  mode,         // 'add' | 'edit'
  season,       // 'SS26' (info)
  count, max,   // jumlah article di season & batas (5) - info "article ke-n dari maks. 5"
  form,         // { code, colorway }
  codeLocked,   // true = kode tidak bisa diubah (article sudah dipakai)
  busy, message // message: null | { type, text }
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `.code`, `.colorway` | `{{ModelDetailCtrl.saveArticle()}}` |
| `onCancel` | – | `{{closeModal('mdlArticle')}}` |

## R19: nomor artikel boleh kosong (26 Okt 2026)

- Label **Article No.** tanpa tanda wajib + catatan (wajib untuk terbit Production, peringatan mulai SMS). Hanya Colorway yang wajib.
  `codeLocked` hanya bila article dipakai **dan** sudah punya nomor (nomor kosong boleh diisi belakangan).
