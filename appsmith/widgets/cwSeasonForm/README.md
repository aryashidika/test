# cwSeasonForm

Form **Season Baru** - page `Model Detail`, modal `mdlSeason` → `ModelDetailCtrl.saveSeason()` → `a_season_add`.

Hanya tampilan. Pilih musim **SS** (Spring/Summer) / **FH** (Fall/Holiday) + 2 digit tahun → `SS26`.
Awal terisi musim & tahun berjalan (Jan–Jun = SS). Season yang sudah ada untuk model ini ditolak di form;
aturan final di DB (`trg_specsheet_check`). Enter = simpan.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±480 px; widget tinggi ±400 px.

## Model masuk (Default model)

```js
{
  key,        // naik setiap modal dibuka -> isian direset
  existing,   // ['SS26', 'FH25'] season yang sudah ada untuk model ini
  busy, message   // message: null | { type, text }
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `.season` (mis. `SS26`) | `{{ModelDetailCtrl.saveSeason()}}` |
| `onCancel` | – | `{{closeModal('mdlSeason')}}` |
