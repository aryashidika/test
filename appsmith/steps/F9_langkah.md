# F9 — Export Excel specsheet & CBD: langkah di Appsmith

Urutan: **0** sisa F8b → **1** cek library → **2** page Specsheet → **3** page CBD → **4** uji → **5** export `export_v9.json`.

Tidak ada SQL baru. Data diambil dari query yang **sudah dimuat** di page (isi file = isi layar; Brand hanya bisa
mengekspor revisi terbit karena draft memang tidak terbaca query). Satu query diubah: `q_cbd_model` (+3 kolom untuk
header CBD). Jangan membuat `Query1` di app ini.

Isi file:
- **Specsheet** (`Specsheet_<model>_<season>_<stage>-r<n>[_DRAFT].xlsx`, mengikuti contoh PDF user
  *SS_SPECS_FH26_FOOTBALL_ACC ILLUZION IV ELITE FG_PROD.pdf*, **tanpa** kotak validasi Dibuat/Diketahui/Divalidasi,
  tanpa logo/gambar, tanpa highlight):
  - judul hitam *SPECIFICATION SHEET OF MATERIAL & COMPONENT*; FACTORY · REVISION (tanggal terbit) · season besar ·
    PURPOSE ☑ otomatis dari stage (PULL → Preview Sample, SMS → Salesman Sample, GTM/PROD → Production Process);
  - MODEL NAME · CATEGORY · OUTSOLE MOULD · LAST No. · CONSTRUCTION · SIZE RANGE · SAMPLE SIZE; di kanan (pengganti kotak
    validasi) kode model, stage · revisi · status (merah bila belum terbit), change log revisi terbit;
  - tabel NO. · COMPONENT NAME · MATERIAL DESCRIPTION (thickness + material; subkomponen: `nama — material`) ·
    SOURCE OF MATERIAL · ARTICLE NO. (kode + colorway, satu kolom warna per article aktif, nilai apa adanya mis. `None`) ·
    UNIT OF MSRMNT · PROCESS; NO & COMPONENT NAME di-merge untuk komponen + subkomponennya;
  - baris 1–11 diulang tiap halaman cetak, footer `Page x / y`, landscape A4 muat 1 halaman lebar.
  - *Komposisi Material* (bagian bawah PDF) belum ada datanya di DB → tidak ikut.
- **CBD** (`CBD_<model>_<season>_<article>_<stage>-r<n>[_DRAFT].xlsx`, mengikuti contoh Excel user
  *FH26_CBD PRODUCTION_ACC ILLUZION IV ELITE FG PRM 097.xlsx*):
  - header *Cost Breakdown Sheet* · *Confidential Information* · tanggal · **1 $ = kurs** · Model Name (+ Mold, Last,
    Size Range) · Article # · Construction · Color · season/revisi/status;
  - tabel per grup (a. Upper, b. Bottom unit, …): No · Component Name · Material description · Thickness · Unit · Color ·
    Yield · Usage · Loss % · Unit Price USD / IDR · Cost/pr (Rp) · Supplier · Remarks · Asal (master / override + alasan /
    quotation, copy / ganti material) + **Subtotal** per grup; baris MISSING_IN_SPEC abu-abu, tidak dihitung;
  - **Cost recapitulation**: a. Material Cost + baris biaya (b, c, …) + **ACTUAL FOB**; **TARGET FOB** + OVER/UNDER +
    selisih; **Harga jual** (Selling price, Margin %); change log revisi terbit.
  - Sel hitungan berisi **rumus Excel** seperti contoh user (Usage `=1/G`, IDR `=J*$L$3`, Cost/pr `=H*(1+I/100)*K`,
    `SUM` subtotal, Material Cost, Actual FOB, selisih, margin) **beserta hasil dari DB** — angka langsung tampil sama
    dengan layar, dan tetap hidup bila kurs/yield diubah di Excel. Format Rupiah / Dollar seperti contoh.

---

## 0. Sisa F8b

- **T42**: `q_cbd_cost_items` → *Run behaviour* **Manual**.

---

## 1. Library — tidak dipakai lagi (T43)

File Excel ditulis JSObject **`XlsxWriter`** (tanpa library), karena ExcelJS memicu *Maximum call stack size exceeded*
di Appsmith. Library ExcelJS boleh dibiarkan terpasang atau dihapus (Libraries → ikon tempat sampah); tidak dipakai.

---

## 2. Page `Specsheet`

### 2a. JSObject
1. Buat **`XlsxWriter`** → tempel `js/XlsxWriter.js`.
2. Buat **`SpecExportCtrl`** → tempel `js/SpecExportCtrl.js`.

### 2b. Widget

```
kolom:  0                    20 21                   41 42              58 59    64
 16–23  [Model ▾ selSpecModel] [Season ▾ selSpecSeason] [+ Buat Revisi ]  [Export ]   ← ★ btnSpecExport
                                                                          [ Excel ]
```

| Bagian panel | Properti | Nilai |
|---|---|---|
| (nama) | Name | `btnSpecExport` |
| Posisi | baris · kolom | 19–23 · **58–64** (sejajar `btnBuatRevisi`) |
| Basic | Label | `{{SpecExportCtrl.busy ? 'Menyiapkan…' : 'Export Excel'}}` |
| Basic | onClick | `{{SpecExportCtrl.exportExcel()}}` |
| General | Visible | `{{!!SpecCtrl.revision()}}` |
| General | Disabled | `{{!SpecExportCtrl.canExport()}}` |
| Style | Button variant | **Secondary** · color `{{appsmith.theme.colors.primaryColor}}` · icon (opsional) `download` |

Bila kolom 58–64 terlalu sempit untuk label, perkecil `btnBuatRevisi` jadi 42–57.

---

## 3. Page `Cost Breakdown (CBD)`

### 3a. Query `q_cbd_model` — ganti seluruhnya (+ `outsole_mold`, `last_no`, `construction` untuk header Excel)
```sql
SELECT id, code, name, category, factory, outsole_mold, last_no, construction, size_range, sample_size
FROM product_model
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
  AND id::text = {{this.params.model_id || ''}};
```
(tetap **Manual**)

### 3b. JSObject
1. Buat **`XlsxWriter`** → tempel `js/XlsxWriter.js` (sama dengan page Specsheet; JSObject hanya berlaku per page).
2. Buat **`CbdExportCtrl`** → tempel `js/CbdExportCtrl.js`. (`CbdCtrl`, `CbdGridCtrl` tidak berubah.)

### 3c. Widget

```
kolom:  0                    20 21                   41 42              58 59    64
 17–24  [Model ▾ selCbdModel ] [Season ▾ selCbdSeason ] [+ Buat CBD    ]  [Export ]   ← ★ btnCbdExport
                                                                          [ Excel ]
```

| Bagian panel | Properti | Nilai |
|---|---|---|
| (nama) | Name | `btnCbdExport` (paling mudah: salin `btnSpecExport` dari Specsheet, lalu ubah) |
| Posisi | baris · kolom | 20–24 · **58–64** (sejajar `btnBuatCbd`) |
| Basic | Label | `{{CbdExportCtrl.busy ? 'Menyiapkan…' : 'Export Excel'}}` |
| Basic | onClick | `{{CbdExportCtrl.exportExcel()}}` |
| General | Visible | `{{!!CbdCtrl.revision()}}` |
| General | Disabled | `{{!CbdExportCtrl.canExport()}}` |
| Style | Button variant | **Secondary** · color `{{appsmith.theme.colors.primaryColor}}` |

⚠️ Bila menyalin dari Specsheet, pastikan **semua** binding diganti ke `CbdExportCtrl` / `CbdCtrl`.

Lalu **Deploy**.

---

## 4. Uji (boleh digabung ke uji end-to-end)

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| X1 | Specsheet revisi terbit → **Export Excel** | Toast *File Excel specsheet diunduh.*; file `Specsheet_<model>_<season>_<stage>-r<n>.xlsx` |
| X2 | Buka file | Layout seperti PDF contoh; baris & warna per article sama dengan grid; NO/COMPONENT NAME ter-merge untuk subkomponen; PURPOSE tercentang sesuai stage; status hijau; change log tampil; tidak ada kotak validasi |
| X3 | Export revisi **draft** | Nama file berakhiran `_DRAFT`; status merah *BELUM TERBIT* |
| X4 | CBD revisi terbit → **Export Excel** | File `CBD_<model>_<season>_<article>_<stage>-r<n>.xlsx` |
| X5 | Buka file CBD | Header (kurs `1 $ =`), grup + Subtotal, Cost recapitulation, Actual FOB, Target FOB + OVER/UNDER, Selling price & Margin % **sama dengan layar** |
| X6 | Di Excel ubah kurs `L3` atau satu Yield | Usage, IDR, Cost/pr, Subtotal, Material Cost, Actual FOB, Selisih ikut berubah (rumus) |
| X7 | CBD dengan baris MISSING_IN_SPEC | Bagian kuning *Hilang dari specsheet*, abu-abu, tidak masuk subtotal |
| X8 | Brand Viewer | Tombol hanya untuk revisi terbit (draft tidak terlihat); file sama |
| X9 | Cetak (Print preview Excel) | Landscape A4, lebar 1 halaman; specsheet: header baris 1–11 berulang tiap halaman + `Page x / y` |

---

## 5. Export

Export app → `appsmith/exports/export_v9.json`.
