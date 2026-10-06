# F10 — Beranda "Tugas Saya": langkah di Appsmith

Urutan: **1** SQL → **2** query (page `Beranda`) → **3** JSObject → **4** widget → **5** Specsheet & CBD (tombol kembali,
buka article) → **6** uji → **7** export `export_v10.json`.

Tidak ada tabel baru, hanya 6 view. Satu Custom Widget baru **`cwWorklist`** (pengganti ±12 tabel/teks bawaan; satu
widget dipakai semua role). Semua query: *Use prepared statements* **ON**, *Run behaviour* **Manual** (⚠️ jangan
*Automatic* — lihat T22/T28/T37/T42; di Beranda query dijalankan `BerandaCtrl.load()` setelah login valid). Jangan membuat
`Query1` di app ini.

Isi tiap role (satu daftar saja, sama dengan Python):

| Role | Tampil di Beranda |
|---|---|
| Vendor – Specsheet | Draft specsheet terbuka (+ lencana penghambat terbit) · article belum masuk specsheet · usulan master data (jumlah) |
| Vendor – CBD | CBD perlu dibuat · draft perlu refresh (specsheet acuan direvisi / harga master berubah) · CBD terbit perlu revisi · draft berjalan · harga master belum ada (+ lencana *usulan harga menunggu approval*) |
| Master Admin | Antrian usulan: material · komponen · supplier material · **harga** (F3b) |
| Brand Viewer | Specsheet terbit terbaru · CBD terbit terbaru (10 teratas, 2 kolom) |
| System Admin | Ringkasan: jumlah model, season, revisi CBD, entri audit log, material, article, user aktif, aktivitas terakhir |

Klik tugas → page tujuan dengan model / season / article sudah terpilih; tombol kembali di Specsheet & CBD jadi
**← Beranda**.

---

## 1. SQL

1. DB Tools → `z_run_sql` → tempel seluruh `sql/F10_worklist.sql` → Run (aman diulang; membuat view saja).
2. Cek cepat (semua harus jalan tanpa error; angka sesuai data Anda):
   ```sql
   SELECT (SELECT count(*) FROM v_worklist_spec)        AS spec,
          (SELECT count(*) FROM v_worklist_cbd)         AS cbd,
          (SELECT count(*) FROM v_worklist_price_gap)   AS price_gap,
          (SELECT count(*) FROM v_worklist_admin)       AS admin,
          (SELECT count(*) FROM v_recent_published)     AS published,
          (SELECT audit_entries FROM v_system_summary)  AS audit;
   ```

---

## 2. Query (page `Beranda`)

Buat 8 query (+ New → pilih datasource Anda), nama persis:

**`q_worklist_spec`** — Vendor Specsheet
```sql
SELECT * FROM v_worklist_spec
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'edit_specsheet')) IS NOT NULL
ORDER BY model_code, season;
```

**`q_worklist_proposals`** — Vendor Specsheet (jumlah usulan; **tanpa** data harga)
```sql
SELECT kind, count(*)::integer AS n
FROM v_worklist_admin
WHERE kind IN ('MATERIAL', 'COMPONENT', 'LINK')
  AND (SELECT fn_auth({{appsmith.store.token}}, 'view_master')) IS NOT NULL
GROUP BY kind;
```

**`q_worklist_cbd`** — Vendor CBD
```sql
SELECT * FROM v_worklist_cbd
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'edit_cbd')) IS NOT NULL
ORDER BY model_code, season, article_code;
```

**`q_worklist_gap`** — Vendor CBD
```sql
SELECT * FROM v_worklist_price_gap
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'edit_cbd')) IS NOT NULL
ORDER BY material_code, supplier_name;
```

**`q_worklist_admin`** — Master Admin
```sql
SELECT * FROM v_worklist_admin
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'manage_master')) IS NOT NULL
ORDER BY kind, proposed_at DESC;
```

**`q_worklist_pub_spec`** — Brand
```sql
SELECT * FROM v_recent_published
WHERE doc_type = 'SPECSHEET'
  AND (SELECT fn_auth({{appsmith.store.token}}, 'view_specsheet')) IS NOT NULL
ORDER BY published_at DESC
LIMIT 10;
```

**`q_worklist_pub_cbd`** — Brand
```sql
SELECT * FROM v_recent_published
WHERE doc_type = 'CBD'
  AND (SELECT fn_auth({{appsmith.store.token}}, 'view_cbd')) IS NOT NULL
ORDER BY published_at DESC
LIMIT 10;
```

**`q_worklist_system`** — System Admin
```sql
SELECT * FROM v_system_summary
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_audit')) IS NOT NULL;
```

---

## 3. JSObject (page `Beranda`)

1. Buat **`BerandaCtrl`** → tempel seluruh `js/BerandaCtrl.js`.
2. Di JSObject **`Auth`** (page Beranda) ganti isi `pageQueries()` saja:
   ```js
   pageQueries() {
   	return [{ run: () => BerandaCtrl.load() }];
   },
   ```
   (`requiredPerm` tetap `''`; fungsi lain di `Auth` tidak berubah.)

---

## 4. Widget (page `Beranda`)

Susunan atas → bawah: `cwHeader` → **`cwWorklist`** → `cwMenu`.

| Widget | Setelan |
|---|---|
| `cwHeader` | Tidak berubah |
| **`cwWorklist`** | Custom Widget baru (kode `widgets/cwWorklist/`: tab HTML / Style / JavaScript), lebar penuh (kolom 0–64), tinggi **±640 px** · Default model `{{BerandaCtrl.model()}}` · event **`onOpen`** `{{BerandaCtrl.open()}}` · event **`onRefresh`** `{{BerandaCtrl.reload()}}` |
| `cwMenu` | Geser ke bawah `cwWorklist` (kode & model tidak berubah) |

Event ditambahkan di panel properti widget (**Events → + Add event**) dengan nama persis `onOpen` dan `onRefresh`.
Tinggi widget boleh disesuaikan; isi yang lebih panjang menggulir di dalam widget.

---

## 5. Page `Specsheet` & `Cost Breakdown (CBD)`

Dua perubahan kecil supaya klik dari Beranda membuka tujuan yang pas (tidak ada query / widget baru):

1. **Specsheet** — tempel ulang seluruh JSObject `SpecCtrl` dari `js/SpecCtrl.js` (parameter `from=home`: tombol
   kembali berlabel *← Beranda* dan menuju Beranda).
2. **Cost Breakdown (CBD)** — tempel ulang seluruh JSObject `CbdCtrl` dari `js/CbdCtrl.js` (parameter `from=home`
   dan **`article`**: article langsung terpilih).

---

## 6. Uji

Persiapan: pakai data uji F5–F9 (model, season, article, specsheet terbit & draft, CBD). Untuk menyiapkan keadaan
tertentu boleh memakai DB Tools. Akun: tiap role (Vendor – Specsheet, Vendor – CBD, Master Admin, Brand Viewer,
System Admin).

| # | Akun | Langkah | Hasil yang diharapkan |
|---|---|---|---|
| H1 | Vendor – Specsheet | Buka Beranda | Judul *Tugas Saya*; 3 angka (draft, article belum masuk, usulan); bagian Draft Specsheet berisi draft yang ada: `MODEL · SEASON — STAGE rN`, jumlah baris BOM & article aktif |
| H2 | Vendor – Specsheet | Draft dengan article aktif yang belum dipakai di BOM / baris tanpa supplier | Lencana *N article belum dipakai di BOM* (arahkan kursor → kode article), *N baris tanpa supplier*; draft rapi → *Tidak ada penghambat terdeteksi*; draft kosong → *BOM masih kosong* |
| H3 | Vendor – Specsheet | Season yang punya article belum masuk revisi mana pun | Muncul di *Article Belum Masuk Specsheet* dengan daftar kode; lencana *Specsheet belum dibuat* bila season belum punya revisi, selain itu *Pilih di revisi specsheet* |
| H4 | Vendor – Specsheet | Klik sebuah draft | Page Specsheet terbuka dengan model & season terpilih, **revisi draft** terbuka; tombol kembali = **← Beranda** dan benar-benar kembali ke Beranda |
| H5 | Vendor – Specsheet | Ada material / komponen / supplier material PROPOSED (mis. dari Vendor CBD) | Bagian *Usulan Master Data*: `N material · N komponen · N supplier material`; klik → Master Material. **Tidak** ada angka harga di mana pun |
| H6 | Vendor – CBD | Buka Beranda | 4 angka; article aktif di specsheet terbit tanpa CBD muncul di *CBD Perlu Dibuat* |
| H7 | Vendor – CBD | Terbitkan specsheet baru yang mengubah baris/supplier/warna article yang CBD-nya sudah terbit | Article itu pindah ke *CBD Terbit Perlu Revisi* (lencana PERLU REVISI) |
| H8 | Vendor – CBD | Draft CBD yang specsheet acuannya sudah direvisi / harga master untuk salah satu barisnya diubah (harga baru disetujui) | *Draft CBD Perlu Refresh* dengan lencana *Specsheet acuan sudah direvisi* / *Harga master berubah*; setelah Refresh di page CBD & muat ulang → pindah ke *Draft CBD Berjalan* (bagian itu hanya tampil bila ada isinya) |
| H9 | Vendor – CBD | Klik sebuah article | Page CBD terbuka dengan model, season, **article itu** terpilih, revisi yang relevan terbuka (draft, atau CBD terbit terakhir); tombol kembali = **← Beranda** |
| H10 | Vendor – CBD | Material katalog + supplier di specsheet terbit tanpa harga APPROVED | Muncul di *Harga Master Belum Ada* dengan `N warna tanpa harga` (tooltip: daftar warna); material QUOTATION tidak muncul; ada usulan harga menunggu → lencana *Usulan harga menunggu approval*; klik → Material Detail |
| H11 | Master Admin | Buka Beranda | 4 angka + 4 bagian: material, komponen, supplier material, **harga** usulan (`Supplier X · warna Y · USD 12.5`); klik material/supplier/harga → Material Detail; komponen → Master Komponen |
| H12 | Master Admin | Setujui / tolak satu usulan → kembali ke Beranda | Item hilang dari daftar (angka berkurang) |
| H13 | Brand Viewer | Buka Beranda | Dua kolom: Specsheet Terbit Terbaru & CBD Terbit Terbaru (maks. 10); **tidak ada draft**; CBD yang NEEDS_REVISION berlabel PERLU REVISI; klik → page terkait membuka revisi terbit |
| H14 | System Admin | Buka Beranda | Empat angka (Model, Specsheet, Revisi CBD, Audit log) + bagian *Ringkasan Sistem* (material · article · user aktif, aktivitas terakhir); klik → Admin |
| H15 | Semua | Tombol **↻ Muat ulang** | Daftar dimuat ulang tanpa pindah halaman |
| H16 | Semua | Hapus token (Application → Local storage) / sesi habis, muat ulang Beranda | Kembali ke Login |
| H17 | Semua | Kecilkan jendela ke ±1280 px | Ringkasan & bagian tetap terbaca (kartu menyesuaikan lebar) |

Bila kolom `unused_articles` / angka tampak tidak cocok, cocokkan dengan `SELECT * FROM v_revision_checklist` (draft) atau
`SELECT * FROM v_cbd_article` (CBD) untuk article / revisi yang sama.

Lalu **Deploy**.

---

## 7. Export

Export app → `appsmith/exports/export_v10.json`.
