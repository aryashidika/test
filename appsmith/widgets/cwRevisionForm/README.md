# cwRevisionForm

Form **Buat Revisi** — page `Specsheet`, modal `mdlRevisi` → `SpecCtrl.saveRevision()` → `a_revision_create`
(`fn_revision_create`).

Hanya tampilan. Pilihan cara mengikuti keadaan season (dari model):

| Keadaan | Pilihan |
|---|---|
| Season belum punya revisi | **Mulai kosong** (`EMPTY`) · **Copy dari season lain (model sama)** (`COPY`, pilih season sumber — revisi terbit terakhirnya) · + stage awal |
| Ada revisi terbit | **Revisi berikutnya** (`NEXT_REVISION`, stage sama, nomor + 1) · **Stage berikutnya** (`NEXT_STAGE`, nonaktif kalau sudah PROD) |
| Ada draft | Tidak ada pilihan (tombol Buat Revisi disembunyikan; teks info kalau tetap terbuka) |

Aturan final di DB (satu draft per season, sumber harus terbit & model sama).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±560 px; widget tinggi ±460 px.

## Model masuk (Default model)

```js
{
  key,                 // naik setiap modal dibuka -> pilihan direset
  season,              // 'SS26' (judul)
  hasRevisions,        // season ini sudah punya revisi (yang terlihat)
  latestLabel,         // revisi terbit terakhir, mis. 'PULL r1' (null = belum ada)
  nextRevisionLabel,   // mis. 'PULL r2'
  nextStageLabel,      // mis. 'SMS r0' (null = sudah PROD)
  copySources,         // [{ id: <specsheet id>, season: 'FH25', label: 'PROD r0' }] season lain model ini yang punya revisi terbit
  busy, message        // message: null | { type, text }
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `.mode` (`EMPTY`/`COPY`/`NEXT_REVISION`/`NEXT_STAGE`), `.stage` (EMPTY/COPY), `.source_specsheet_id` (COPY) | `{{SpecCtrl.saveRevision()}}` |
| `onCancel` | – | `{{closeModal('mdlRevisi')}}` |

## Perubahan R3–R7 (11 Okt 2026)

R7: pilihan ketiga **Copy dari model lain (pabrik & kategori sama)** = mode `COPY_MODEL` (dikirim apa adanya; `SpecCtrl.saveRevision()` memanggil `fn_revision_create` mode `COPY`). Model masuk + `modelSources: [{ id: <specsheet id>, label, summary }]` (`q_copy_model_sources`); ringkasan "Akan menyalin N baris…" tampil untuk sumber terpilih.
