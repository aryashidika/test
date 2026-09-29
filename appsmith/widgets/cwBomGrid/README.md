# cwBomGrid

Grid **BOM** page `Specsheet`: kolom No, Komponen, Material, Supplier, UoM, Remarks + satu kolom per article
aktif di revisi (maks. 5). Header & kolom No/Komponen menempel saat di-scroll.

Hanya tampilan & input. Setiap perubahan dikirim sebagai `model.action` + **satu** event `onAction`
(`BomCtrl.onAction()` menjalankan query, lalu memuat ulang grid). Aturan final di DB (`fn_bom_*`,
`fn_rev_article_set`, `trg_lock_published`); pesannya tampil di bar atas grid.

- **Hanya baca** (`editable: false` — revisi terbit, atau role tanpa `edit_specsheet`): teks biasa.
- **Draft**: setiap sel berupa input yang tersimpan saat berubah (Enter / Tab / klik di luar). Enter di kolom
  yang sama pindah ke baris berikutnya; Esc membatalkan ketikan.
  - **Material** diketik ulang = *Ganti material* (`replaceMaterial`).
  - **Supplier** = nama dari Master Supplier (kosong = tanpa supplier). Saran: supplier terdaftar untuk material itu
    dulu (utama paling atas), link INACTIVE tidak ditawarkan. Badge **usulan** (link PROPOSED) / **⚠ nonaktif**.
  - **Warna** per article dengan saran warna se-season.
  - **+ Sub** membuka baris form subkomponen di bawah induknya.
  - Baris **+ Tambah** di bawah: komponen `10 - Vamp` / `10` / nama unik = komponen master APPROVED; teks lain =
    komponen **lokal** (No. wajib, bukan kelipatan 10). Material dipilih → supplier utama (atau satu-satunya) terisi.
  - Header article **✕** → **Drop?** → klik lagi = drop article (tanpa dialog, aman di iframe).
- Ketikan yang belum disimpan, fokus, dan posisi scroll dipertahankan saat data dimuat ulang.
  Form tambah/sub dikosongkan saat `okKey` berubah (tambah berhasil).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: lebar penuh, tinggi ±600 px (scroll di dalam widget).

## Model masuk (Default model) — `{{BomCtrl.gridModel()}}`

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

Setiap aksi juga membawa `seq` (nomor urut) supaya dua aksi berurutan yang sama tetap terbaca berbeda.
