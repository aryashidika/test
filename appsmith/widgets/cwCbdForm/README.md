# cwCbdForm

Form **Buat CBD** — page `Cost Breakdown (CBD)`, modal `mdlCbdBaru` → `CbdCtrl.saveCreate()` → `a_cbd_create`
(`fn_cbd_create`).

Hanya tampilan. Pilihan disusun `CbdCtrl.createFormModel()` sesuai keadaan article:

| Keadaan article | Pilihan |
|---|---|
| Belum punya CBD | **CBD baru dari specsheet** (`NEW`) · **Copy dari article lain (model sama)** (`COPY`, pilih article sumber — CBD terbit terakhirnya) |
| Punya CBD terbit | **Revisi berikutnya** (`NEXT`) |
| Ada draft | Tidak ada pilihan (tombol Buat CBD disembunyikan; teks `emptyText` kalau tetap terbuka) |

Aturan final di DB (satu draft per article, article ACTIVE di specsheet terbit, sumber model sama & sudah terbit).

**R13 — stage dipilih:** `stages` dari `q_cbd_stages` (`fn_cbd_stage_options`): satu tombol per stage yang specsheet-nya
sudah terbit; nonaktif (dengan alasan di bawahnya) bila article tidak aktif di specsheet stage itu atau sudah ada CBD
terbit di stage lebih tinggi. Default = `isDefault` (stage tersedia tertinggi). `{spec}` / `{next}` di `title` opsi,
`desc`, dan `note` diganti widget dengan specsheet acuan / nomor revisi CBD stage terpilih.

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: modal lebar ±560 px; widget tinggi ±520 px (R13: baris stage + kotak article sumber).

## Model masuk (Default model)

```js
{
  key,          // naik setiap modal dibuka -> pilihan direset
  title,        // 'Buat CBD — A1 · Black/White'
  note,         // 'Acuan: specsheet SS27 {spec} (terbit terakhir di stage itu).'
  stages,       // R13: [{ v: 'SMS', spec: 'SMS r1', next: 'SMS r0', disabled, note, isDefault }]
  options,      // [{ v: 'NEW'|'COPY'|'NEXT', title, desc, disabled?, needsSource? }]  ({spec} / {next} boleh dipakai)
  sources,      // [{ id: <article id>, label }]  untuk pilihan needsSource
  emptyText,    // teks bila options kosong
  busy, message // message: null | { type, text }
}
```

## Nilai keluar & event

| Event | Sebelumnya widget mengisi | Action |
|---|---|---|
| `onSave` | `.mode`, `.source_article_id` (`''` bila tidak perlu sumber), `.stage` (R13) | `{{CbdCtrl.saveCreate()}}` |
| `onCancel` | – | `{{closeModal('mdlCbdBaru')}}` |
