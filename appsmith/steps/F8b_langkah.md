# F8b - CBD: Cost recapitulation & Harga jual (tabel di bawah grid): langkah di Appsmith

Permintaan user 5 Okt 2026, mengikuti contoh Excel `FH26_CBD PRODUCTION_ACC ILLUZION IV ELITE FG PRM 097.xlsx`
(blok *Cost recapitulation*). Urutan: **1** SQL → **2** query → **3** JSObject → **4** widget → **5** uji → **6** export
`export_v8b.json`.

Setelan **query baru**: *Use prepared statements* **ON**, *Run behaviour* **Manual** (⚠️ termasuk `q_cbd_cost_items`
- jangan *Automatic*, lihat T37). Jangan membuat `Query1` di app ini.

Keputusan user:
- **Tabel baris CBD tetap** seperti sekarang, ditambah **baris Subtotal per grup** (A Upper, B Bottom unit, …).
- **Cost recapitulation** (tabel sendiri di bawah grid):
  - `a.` **Material cost** - otomatis (jumlah subtotal grup).
  - Baris biaya dengan **jenis tetap**: Direct Labour (LOP) · Amortisasi · Adjustment · Lainnya. Nilai Rupiah;
    hanya **Adjustment** yang boleh minus.
  - **Direct Labour, Amortisasi, Adjustment selalu ada** (baris default, tidak bisa dihapus; isi 0 bila tidak dipakai;
    uraian & keterangan boleh diubah). Baris tambahan (mis. *Amortisasi Mold Upper*) bisa ditambah & dihapus.
  - **ACTUAL FOB** = material cost + semua baris biaya · **Target FOB** · **Selisih** (OVER / UNDER / SESUAI).
- **Harga jual** (tabel terpisah di bawah): Selling price ⇄ Margin % - sama seperti F8, hanya dipindah.
- Di atas grid (menempel) tinggal **Exchange rate** + ringkasan hanya baca: Material cost, Actual FOB, Target FOB, Selisih.
- Kolom `amortization` & `adjustment` di `cbd_revision` **dihapus**; nilainya dipindah ke baris default (data uji tetap aman).
- Revisi berikutnya / copy dari article lain: baris biaya **ikut ter-copy**. Revisi terbit: baris biaya **terkunci**.
- Tidak dibuat (keputusan user): simulasi FOB tanpa treatment, PO = FOB × markup, tabel dampak perubahan per kategori
  (masuk fase Opsional).

---

## 1. SQL

1. DB Tools → `z_run_sql` → tempel seluruh `sql/F8b_cbd_cost.sql` → Run.
   ⚠️ Setelah ini **jangan menjalankan ulang `F8_cbd_price.sql`** (masih memakai kolom yang sudah dihapus).
2. Cek cepat:
   ```sql
   SELECT (SELECT count(*) FROM cbd_revision) AS revisi,
          (SELECT count(*) FROM cbd_cost_item WHERE is_default) AS baris_default,
          (SELECT count(*) FROM information_schema.columns
            WHERE table_name = 'cbd_revision' AND column_name IN ('amortization', 'adjustment')) AS kolom_lama;
   ```
   Hasil: `baris_default = revisi × 3`, `kolom_lama = 0`.

---

## 2. Query (page `Cost Breakdown (CBD)`)

**`q_cbd_cost_items`** (baca - **Manual**; dijalankan `CbdGridCtrl.reload()`)
```sql
SELECT c.id, c.item_type, c.name, c.amount, c.remarks, c.is_default, c.sort_order
FROM cbd_cost_item c
JOIN cbd_revision r ON r.id = c.cbd_revision_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
  AND c.cbd_revision_id::text = {{this.params.revision_id || ''}}
  AND (r.status = 'PUBLISHED'
       OR (SELECT fn_has_perm(fn_auth({{appsmith.store.token}}, 'view_cbd'), 'view_drafts')))
ORDER BY CASE c.item_type WHEN 'LABOUR' THEN 1 WHEN 'AMORTIZATION' THEN 2 WHEN 'ADJUSTMENT' THEN 3 ELSE 4 END,
         NOT c.is_default, c.sort_order;
```

**`a_cbd_cost_add`**
```sql
SELECT fn_cbd_cost_add({{appsmith.store.token}}, {{this.params.revision_id}}::uuid, {{this.params.item_type}},
                       {{this.params.name}}, nullif({{this.params.amount}}, '')::numeric, {{this.params.remarks}}) AS id;
```

**`a_cbd_cost_set`**
```sql
SELECT fn_cbd_cost_set({{appsmith.store.token}}, {{this.params.item_id}}::uuid, {{this.params.field}},
                       {{this.params.value}}) AS id;
```

**`a_cbd_cost_delete`** - *Request confirmation before running* = **ON**
```sql
SELECT fn_cbd_cost_delete({{appsmith.store.token}}, {{this.params.item_id}}::uuid) AS id;
```

Query lain **tidak berubah** (`q_cbd_recap` memakai `SELECT v.*`, kolom baru ikut otomatis; `a_cbd_header_set` sama -
hanya isian AMORTIZATION/ADJUSTMENT yang tidak dipakai lagi).

---

## 3. JSObject

- `CbdGridCtrl` → tempel ulang seluruh `js/CbdGridCtrl.js`. Baru: `costOkKey`, `costItems()`, `reload()` ikut
  menjalankan `q_cbd_cost_items`, `gridModel()` + `costItems`/`costOkKey`, aksi `addCost` / `setCost` / `deleteCost`.
- `CbdCtrl`, `Auth`, `Util`: tidak berubah.

---

## 4. Widget

### 4a. Desain (teks) - isi `cwCbdGrid`

```
┌ cwCbdGrid ───────────────────────────────────────────────────────────────────────────┐
│ [pesan …]                                                    4 baris · 1 tanpa harga   │ bar
│ ▌banner refresh (bila ada)                                    [Refresh …]              │
│ Exchange rate (Rp/1 USD) │ Material cost │ Actual FOB │ Target FOB │ Selisih           │ ← menempel
│ [ 18078 ]                │ 361.250,00    │ 449.490,00 │ 365.308,00 │ 84.182,00 OVER    │   (hanya rate yg diisi)
├────────────────────────────────────────────────────────────────── scroll ─────────────┤
│ No │ Komponen │ Material │ … │ Yield │ Usage │ Loss % │ Harga │ … │ Cost/pr │ Asal      │
│ A · Upper                                                                              │
│ 10 │ Vamp …                                                         3.708,00           │
│ Subtotal A · Upper                                                 5.739,25           │ ← baru
│ B · Bottom unit …                                                                      │
│ Subtotal B · Bottom unit                                              0,00            │
│ Hilang dari specsheet (MISSING_IN_SPEC) …                                              │
│                                                                                        │
│ Cost recapitulation                                         Harga jual                 │
│ ┌No─Jenis──────────┬Uraian──────────────┬Nilai (Rp)┬Keterangan──┬─────┐ ┌─────────────────────┐│
│ │a. Material       │Material cost       │361.250,00│otomatis    │     │ │Selling price [     ]││
│ │b. Direct Labour  │[Direct Labour     ]│[ 83740  ]│[LOP 2026  ]│     │ │Margin %      [     ]││
│ │c. Amortisasi     │[Amortisasi winfait]│[     0  ]│[          ]│     │ └─────────────────────┘│
│ │d. Adjustment     │[Adjustment Piero  ]│[   500  ]│[          ]│     │ Selling price dan Margin│
│ │e. Amortisasi     │[Amortisasi Mold Up]│[  4000  ]│[          ]│Hapus│ saling terhubung …     │
│ │+ [- jenis - ▾]   │[Uraian           ]│[     0  ]│[Keterangan]│[Tambah]│                     │
│ │  ACTUAL FOB                           │449.490,00│material + biaya │                       │
│ │  Target FOB                           │[365308  ]│            │     │                        │
│ │  Selisih (Actual − Target)            │84.182 OVER│           │     │                        │
│ └──────────────────────────────────────────────────────────────────┘                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
```
- Kedua tabel bawah ikut di-scroll vertikal bersama grid, tetapi **tidak bergeser** saat grid di-scroll ke kanan.
- Baris default (b, c, d pertama) tidak punya tombol **Hapus**. Isian baris + **Tambah** tidak hilang saat grid
  dimuat ulang; dikosongkan setelah tambah berhasil.
- Revisi terbit / Brand / Master Admin: semua tabel hanya baca, tanpa baris **+**.

### 4b. Langkah

1. Klik `cwCbdGrid` → **Edit source** → tempel ulang **ketiga tab** (`widgets/cwCbdGrid/index.html`, `style.css`,
   `script.js`) → tutup editor.
2. Tinggi `cwCbdGrid` → **±800 px** (baris 41–121; sekaligus menutup T40 - tabel bawah ada di dalam widget).
3. Properti lain **tetap**: Default model `{{CbdGridCtrl.gridModel()}}` · Visible `{{!!CbdCtrl.revision()}}` ·
   Height **Fixed** · event **onAction** `{{CbdGridCtrl.onAction()}}` (aksi biaya juga lewat `onAction`, tidak ada event baru).
4. Sisa T41: `tblCbdRiwayat` → *Allow searching* **OFF**.
5. **Deploy**.

---

## 5. Uji (boleh digabung ke uji end-to-end di akhir)

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| G1 | Buka CBD yang sudah ada sebelum F8b (draft / terbit) | Cost recapitulation berisi Direct Labour 0, Amortisasi & Adjustment = nilai lama; Actual FOB sama dengan sebelum F8b |
| G2 | Draft: Direct Labour `83740`, keterangan `LOP 2026` | Tersimpan; Actual FOB naik 83.740 (atas & bawah) |
| G3 | Amortisasi `-5` | Pesan *Nilai tidak boleh minus.*; Adjustment `-200` → tersimpan |
| G4 | **+** jenis Amortisasi, uraian `Amortisasi Mold Upper`, `4000` → **Tambah** | Baris `e.` baru, form kosong; Actual FOB +4.000 |
| G5 | **Tambah** tanpa jenis; nilai `4.000` | *Pilih jenis biaya.*; *ambigu…* |
| G6 | **Hapus** baris `e.` → Cancel → Confirm | Baris hilang; baris default tidak punya Hapus |
| G7 | DB Tools: `SELECT fn_cbd_cost_delete('salah', gen_random_uuid());` | Error *SESI_HABIS…* |
| G8 | Subtotal grup | Jumlah Cost/pr tiap grup = subtotal; total subtotal = Material cost |
| G9 | Target FOB & Selling price / Margin % di tabel bawah | Sama seperti uji F8 B4–B7 |
| G10 | Terbitkan → **+ Buat Revisi CBD** → Revisi berikutnya | Baris biaya (termasuk tambahan) ikut ter-copy; revisi terbit hanya baca |
| G11 | DB Tools: `UPDATE cbd_cost_item SET amount = 1 WHERE cbd_revision_id IN (SELECT id FROM cbd_revision WHERE status = 'PUBLISHED');` | Error *…sudah diterbitkan…* |
| G12 | Copy dari article lain (CBD baru A2) | Baris biaya sama dengan CBD terbit sumber |

---

## 6. Export & cek skema

1. Export app → `appsmith/exports/export_v8b.json`.
2. Cek skema (`PLAN.md` §8) - harus ada table `cbd_cost_item`, view `v_cbd_recap`, `v_cbd_checklist`, function
   `fn_cbd_cost_label`, `fn_cbd_cost_defaults`, `fn_cbd_check_cost`, `fn_cbd_cost_item`, `fn_cbd_cost_add`,
   `fn_cbd_cost_set`, `fn_cbd_cost_delete`, trigger `trg_lock_published` (cbd_cost_item).
