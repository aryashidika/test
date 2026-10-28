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

## R19: Dimension di kolom sendiri, saran terbaca penuh, ganti komponen, Process (26 Okt 2026)

- **Kolom Material = nama saja** (atau Material Code: mengisi nama + Dimension + tawaran warna). **Kolom Dimension = input** dengan saran
  dimension terdaftar material itu (jumlah warna), boleh dimension baru (catatan `new dimension`). Baris tambah / sub: Material diganti ke
  material LAIN -> Dimension mengikuti material baru (terdaftar juga = tetap; satu dimension = itu; beberapa = kosong; tanpa dimension /
  Process = kosong), tanpa membedakan terisi otomatis atau diketik (revisi user 27 Okt 2026). Nama sama diketik ulang = tidak disentuh. Ketikan lama `NAMA · DIMENSION` /
  `NAMA . 1,5 mm` / `NAMA 1,5mm` tetap dibaca lalu dipisah ke dua kolom. Dimension dibakukan seperti DB (`1,4mm` -> `1.4 MM`).
- Baris tambah / sub: material punya beberapa dimension dan Dimension kosong -> pesan `Fill in the Dimension of ...` (satu dimension saja ->
  langsung terisi). Baris yang ada: ubah Dimension = `replaceMaterial` (material sama); ganti nama material -> dimension baris dipakai bila
  terdaftar di material baru, material dengan satu dimension -> itu, selain itu **dimension dipilih dulu** (`pendingDim`: sel Dimension
  kuning muda + fokus, pesan info; Esc = batal), lalu satu `replaceMaterial`.
- **Saran Material / Dimension** = daftar sendiri (`#suggest`, bukan datalist browser), teks membungkus, maks 12, yang diawali ketikan dulu:
  `NAMA` + `UOM · dimension: ...` (Process: `Process (no Material Code)`). Nama sama beda UoM ditulis `NAMA (UOM)` (juga diterima saat
  diketik). Sel Material & Dimension = kotak teks yang membungkus. Enter di baris tambah memilih saran saja (belum menyimpan).
- **Ganti komponen**: tombol **Change** di kolom Component baris induk -> input komponen master (datalist) -> Enter -> action
  `changeComponent` `{ line_id, component_id }` (`BomCtrl` -> `a_bom_change_component` / `fn_bom_change_component`: HANYA baris itu
  + subkomponennya pindah, koreksi user 27 Okt 2026; ditolak bila komponen tujuan sudah punya material + dimension yang sama). Esc / klik
  di luar tanpa isian = batal.
- **Material Process** (`lines[].is_process`, `materials[].is_process`): badge **process**, sel tidak kuning, tanpa tombol Register.
- Header article tanpa nomor: `(no article no.)` miring (`articles[].no_code`).

## R20: Material Code hanya di Register, nama rapat (27 Okt 2026)

- **Material Code tidak dibaca di grid** (revisi user setelah hasil cek data): kolom Material menolak kode (`... is a Material Code ...
  Type the material name here; Material Codes are entered with Register.`, tanpa + New material); sel warna menyimpan kode sebagai
  teks warna biasa (kuning). Tawaran `Fill color ... into all articles` dan saran typo kode di "Did you mean" dihapus. Warna yang
  terdaftar untuk material + dimension baris tetap langsung tersambung ke kodenya (DB). Tidak ada Pick code / Use di sel.
- `registerVariant` membawa `article_id` (tombol **Use KODE in the specsheet** di modal Register, `BomCtrl.useFromRegister`).
- **Nama rapat** (`tightKey` = `fn_tight_key`): `resolveName` mencocokkan nama yang hanya beda spasi / tanda baca ke material master tanpa
  bertanya (lebih dari satu beda UoM -> pesan pilih). **`nearName`** (salinan di `BomCtrl.nearMaterialNames`): saran "Did you mean" hanya
  untuk nama yang angkanya sama; urutan: beda tanda baca, kata sama urutan lain, typo 1 huruf di kata 5 huruf ke atas, nama memuat ketikan.

## R20 bagian 2: warna seragam, Dimension seperti dropdown (28 Okt 2026)

- **Warna**: `cleanColor` (= `fn_clean_color`: huruf besar, tanpa spasi di sekitar `/ - & + ,`) dipakai saat sel disimpan; `colorKey`
  (= `fn_color_key` = `tightKey`) untuk saran warna unik. DB menyambungkan warna yang hanya beda spasi / tanda baca ke varian dan menulis
  sel seperti varian terdaftar. Sel kuning dengan kata sama tapi urutan lain dari warna terdaftar baris itu (`colorWords`) -> tombol
  **Did you mean WARNA?** (`setCell` dengan warna terdaftar); tidak diganti otomatis. Salinan `cleanColor` sama di `cwVariantForm`.
- **Dimension** (`cellInput` opsi `dropdown`: kelas `dd` = tanda panah, `_sugFull`, `_sugKey = thickKey`): fokus / klik = semua dimension
  material itu (yang terisi dicentang, klik lagi = tutup); mengetik = disaring dalam bentuk baku, termasuk yang sama persis (dicentang),
  lalu dimension material lain (`ALL_DIMS` dari `M.materials`, item `other`) di bawah judul **Other materials**
  (`new for this material · used by N materials`). `markSuggest` hanya menghitung `.opt` (judul grup dilewati).

## R20 bagian 3: Dimension wajib, (None), default (28 Okt 2026)

- **`(None)`** (`NONE`) = tanpa dimension: tampil di sel Dimension (juga read only) bila `thickness` kosong, selalu **paling atas** di daftar
  Dimension (item `none`, miring, dicari dengan ketikan "none"). `canonThickness` membaca `NONE` / `(NONE)` = kosong (sama dengan
  `fn_clean_thickness`), jadi yang dikirim ke BomCtrl tetap `''`. Kotak dikosongkan = `(None)`. Fokus pada `(None)` = teks terpilih.
- **Default**: `M.materials` kini membawa `first_at` (`q_bom_options`). `buildMats` mengurutkan `dims` per material: varian terbanyak, sama
  banyak = paling dulu didaftarkan. `defaultDim(materialId)` = dimension pertama (`''` = `(None)`, juga material tanpa varian).
  `dimFor(materialId, current)` = dimension sekarang bila terdaftar juga di material itu, selain itu default.
- Baris tambah / sub: Material dipilih -> Dimension = default; Material diganti -> `dimFor`. `resolveMaterial`: Dimension yang belum diisi =
  default, `(None)` / `.` = kosong. Baris yang ada: Ganti material -> `replaceMaterial` dengan `dimFor` langsung. Alur R19 `pendingDim`
  ("Now pick the dimension ...", kelas `.cell.need`) dan `needDim` dihapus.
