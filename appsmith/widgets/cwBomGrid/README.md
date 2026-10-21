# cwBomGrid

Grid **BOM** page `Specsheet`: kolom No, Komponen, Material, Supplier, UoM, Remarks + satu kolom per article
aktif di revisi (maks. 5). Header & kolom No/Komponen menempel saat di-scroll.

Hanya tampilan & input. Setiap perubahan dikirim sebagai `model.action` + **satu** event `onAction`
(`BomCtrl.onAction()` menjalankan query, lalu memuat ulang grid). Aturan final di DB (`fn_bom_*`,
`fn_rev_article_set`, `trg_lock_published`); pesannya tampil di bar atas grid.

- **Hanya baca** (`editable: false` - revisi terbit, atau role tanpa `edit_specsheet`): teks biasa.
- **Draft**: setiap sel berupa input yang tersimpan saat berubah (Enter / Tab / klik di luar). Enter di kolom
  yang sama pindah ke baris berikutnya; Esc membatalkan ketikan.
  - **Material** diketik ulang = *Ganti material* (`replaceMaterial`).
  - **Supplier** = nama dari Master Supplier (kosong = tanpa supplier). Saran: supplier terdaftar untuk material itu
    dulu (utama paling atas), link INACTIVE tidak ditawarkan. Badge **usulan** (link PROPOSED) / **⚠ nonaktif**.
  - **Warna** per article dengan saran warna se-season.
  - **+ Sub** membuka baris form subkomponen di bawah induknya.
  - **Hapus** (kolom aksi) → **Yakin?** / **Hapus + sub?** → klik lagi = hapus baris (induk ikut menghapus subkomponennya; F5b).
  - Baris **+ Tambah** di bawah: komponen `10 - Vamp` / `10` / nama unik = komponen master APPROVED; teks lain =
    komponen **lokal** (No. wajib, bukan kelipatan 10). Material dipilih → supplier utama (atau satu-satunya) terisi.
  - Header article **✕** → **Drop?** → klik lagi = drop article (tanpa dialog, aman di iframe).
- Ketikan yang belum disimpan, fokus, dan posisi scroll dipertahankan saat data dimuat ulang.
  Form tambah/sub dikosongkan saat `okKey` berubah (tambah berhasil).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: lebar penuh, tinggi ±600 px (scroll di dalam widget).

## Model masuk (Default model) - `{{BomCtrl.gridModel()}}`

```js
{
  editable,     // true = revisi DRAFT dan role edit_specsheet
  articles,     // [{ id, code, colorway }] article ACTIVE di revisi
  lines,        // baris q_bom_grid (v_bom_grid): id, is_sub, display_no, display_name, is_local, material_id,
                //   material_code, material_name, thickness, uom, material_status, supplier_id, supplier_name,
                //   link_status, process, cells ({ "<article_id>": "warna" }, objek atau teks JSON)
  components,   // [{ id, number, name }] komponen APPROVED
  materials,    // [{ id, code, name, uom, thickness, status }] material non-INACTIVE
  suppliers,    // [{ id, name }] supplier aktif
  links,        // [{ material_id, supplier_id, is_preferred, status }]
  colors,       // ['Black', ...] saran warna se-season
  busy,         // ada aksi yang sedang disimpan
  message,      // null | { type, text }
  okKey,        // naik setelah tambah baris/sub berhasil
  doneSeq,      // seq aksi terakhir yang selesai di BomCtrl (ack antrean aksi)
  emptyText     // teks bila tidak ada baris (hanya baca)
}
```

## Nilai keluar & event

Satu event **`onAction`** → `{{BomCtrl.onAction()}}`. Sebelumnya widget mengisi `.action`:

| `action.type` | Isi | Query |
|---|---|---|
| `addLine` | `component_id` atau `local_no` + `local_name`, `material_id`, `supplier_id`, `process` | `a_bom_add_line` |
| `addSub` | `parent_id`, `sub_name`, `material_id`, `supplier_id`, `process` | `a_bom_add_sub` |
| `replaceMaterial` | `line_id`, `material_id` | `a_bom_replace_material` |
| `setSupplier` | `line_id`, `supplier_id` (`''` = kosongkan) | `a_bom_set_supplier` |
| `setProcess` | `line_id`, `process` | `a_bom_set_process` |
| `setCell` | `line_id`, `article_id`, `color` | `a_cell_save` |
| `dropArticle` | `article_id` | `a_rev_article_set` (`DROPPED`) |
| `deleteLine` | `line_id` | `a_bom_delete_line` (F5b) |

Setiap aksi membawa `seq` (naik terus, berbasis waktu). Aksi dikirim **satu per satu**: aksi berikutnya baru dikirim
setelah BomCtrl membalas `doneSeq >= seq` (sesudah query + muat ulang data). Tanpa balasan 5 detik, aksi dikirim ulang;
BomCtrl mengabaikan `seq` yang sudah selesai. Nilai yang sudah dikirim tetap tampil sampai antrean kosong. Sel juga
disimpan saat blur (nilai yang dipulihkan setelah render ulang tidak memicu `change`).

## Perubahan R3–R7 (11 Okt 2026)

R4 (specsheet per varian):
- `materials` = kombinasi **induk × thickness** `[{ material_id, name, uom, thickness, variant_count }]` (dari varian ACTIVE + induk tanpa varian); label "NAMA · THICKNESS".
- `variants` = `[{ id, code, material_id, material_name, thickness, color }]` varian ACTIVE pabrik user - dipakai untuk Material Code yang diketik di kolom Material (mengisi induk + thickness, baris tambah menawarkan isi warna ke semua article) atau di sel (diganti warnanya; kode material/thickness lain ditolak).
- `lines[]` + `cell_codes` (`{ article_id: kode }`), `yellow` (jumlah sel kuning); `thickness` dari baris.
- `canRegister`, `canAddSupplier` (izin `manage_master`).
- Sel berwarna tanpa varian = **kuning** + tombol **Daftarkan** → action `registerVariant` `{ line_id, material_id, material_name, uom, thickness, color }` → `BomCtrl.openRegister()` (modal `mdlVarianBaru` / `cwVariantForm` mode fixed).
- Tombol **+ Supplier baru** di bar → action `newSupplier` → `mdlSupplierBaru` / `cwSupplierForm`.
- `addLine` + `thickness`, `fill_color`; `addSub` + `thickness`; `replaceMaterial` + `thickness`. Badge usulan dihapus; badge ⚠ nonaktif untuk supplier / supplier material INACTIVE.

## R16: material baru tanpa kode + thickness baku

- **Kolom Material** menerima `NAMA · THICKNESS`. Thickness dibakukan di klien persis seperti DB (`canonThickness` = `fn_clean_thickness`:
  gaya berspasi tim material: huruf besar, koma jadi titik, `1.2MM` jadi `1.2 MM`, `44X69CM` jadi `44 X 69 CM`, tanpa spasi di sekitar `-`;
  20 Okt 2026: nol belakang dibuang `2.0` = `2`, kutip miring dan `INCH` / `IN` jadi `"`, rentang `1.4MM-1.6MM` jadi `1.4-1.6 MM`; salinan sama
  di `cwVariantForm`, ubah ketiganya bersamaan); thickness baru untuk induk yang ada =
  baris baru bertanda `(new)`. `NAMA ·` tanpa thickness = masih mengetik (dianggap nama saja).
- **Tidak ketemu**: pesan `Did you mean` (nama: typo sampai ±25% panjang atau kata-kata dalam urutan lain; kode: ≤ 2 salah ketik)
  + `lastNotFound` untuk isian awal modal.
- **Bar atas**: `+ New material` (action `newMaterial`, `{ name }`, butuh `canAddMaterial`), `+ New supplier`. Tidak menyusut saat pesan panjang.
  Sel kuning juga disorot di Export Excel (`SpecExportCtrl`), tanpa tombol terpisah.
- Model masuk: + `canAddMaterial`. Action baru: `newMaterial` (BomCtrl membuka `mdlMaterialBaru`), langsung di-ack seperti `registerVariant`.
- **Tanpa titik tengah** (21 Okt 2026, permintaan user): `NAMA . THICKNESS` / `- / | , ; :` / tanpa pemisah dibaca sebagai
  `NAMA · THICKNESS` bila bagian depan persis nama material yang ada (terpanjang dulu) dan sisanya mirip thickness (`altSplit`,
  `looksThick`: dengan pemisah cukup ada angka, tanpa pemisah harus angka + satuan). Nama yang cocok persis selalu menang. Material baru
  `NAMA . THICKNESS` (pemisah berspasi) dipisah untuk modal (`splitNewName`): Name tanpa thickness, thickness dipakai saat baris dilanjutkan.
- **Tombol di baris** (20 Okt 2026, permintaan user): material tidak ketemu saat Enter / **+ Add** (baris tambah), **Add** (sub) atau ganti
  material di sel → `Not in Master Material.` + tombol **+ New material** di sel Material itu (hilang bila isian diubah). Klik → `newMaterial`
  `{ name }` dan widget mencatat baris yang menunggu (`awaitNew`). Model masuk + `matAdded: { key, name }` (BomCtrl menaikkan `key` setelah
  material tersimpan **dan** daftar material dimuat ulang) → widget mengisi nama yang disimpan (+ thickness yang diketik) lalu mengulang
  aksi baris itu otomatis: `addLine`, `addSub`, atau `replaceMaterial`. Batal di modal = tidak ada aksi.
- **Skala**: saran dihitung hanya saat pesan error dibaca (sync isian tidak menghitung). Diukur dengan data tiruan: 5.000 material + 20.000 varian = 50 sampai 130 ms per salah ketik; 20.000 material + 80.000 varian = 120 sampai 380 ms. Kandidat disaring dulu (selisih panjang, 3 huruf awal / akhir kode) sebelum jarak ketik dihitung.
