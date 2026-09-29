# F3b — Approval harga oleh Master Admin: langkah di Appsmith

Keputusan user (29 Sep 2026):
- Harga dari **Vendor CBD** = usulan (PROPOSED); harga dari **Master Admin** langsung APPROVED.
- Harga lama **tetap berlaku sampai usulan di-approve**, lalu ditutup per tanggal berlaku harga baru.
- **Tolak** = status DITOLAK + alasan wajib (tetap tersimpan, terlihat tim CBD).
- **Akhiri** harga tetap langsung, tanpa approval.
- Maks. satu usulan per supplier + warna; Vendor CBD bisa **Batalkan** usulannya.

Urutan: **1** SQL → **2** Master Material → **3** Material Detail → **4** uji → **5** export `export_v3b.json`.
Setelan query baru: *prepared statements* **ON**, *Run behaviour* **Manual**.

---

## 1. SQL

DB Tools → `z_run_sql` → tempel seluruh `sql/F3b_price_approval.sql` → Run. Harga yang sudah ada otomatis dianggap APPROVED.

Cek:
```sql
SELECT status, count(*) FROM material_price GROUP BY status;
```
→ semua harga lama `APPROVED`.

---

## 2. Page `Master Material`

1. JSObject `MaterialCtrl` → tempel ulang `js/MaterialCtrl.js` (ringkasan kolom Supplier menampilkan *n harga menunggu approval*).
2. Query **`q_materials`** — ganti seluruhnya:
   ```sql
   SELECT id, material_code, name, category, thickness, uom, price_method, status,
          supplier_count, proposed_links, priced_links, preferred_supplier, missing_price, pending_prices,
          updated_at, updated_by
   FROM v_material_list
   WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_master')) IS NOT NULL
     AND ({{inpMaterialCari.text || ''}} = ''
          OR material_code ILIKE '%' || {{inpMaterialCari.text || ''}} || '%'
          OR name ILIKE '%' || {{inpMaterialCari.text || ''}} || '%'
          OR category ILIKE '%' || {{inpMaterialCari.text || ''}} || '%')
     AND ({{selMaterialStatus.selectedOptionValue || ''}} = '' OR status = {{selMaterialStatus.selectedOptionValue || ''}})
     AND ({{selMaterialKategori.selectedOptionValue || ''}} = '' OR category = {{selMaterialKategori.selectedOptionValue || ''}})
     AND (NOT {{swMaterialBelumHarga.isSwitchedOn === true}}::boolean OR missing_price)
     AND (NOT {{swMaterialHargaPending.isSwitchedOn === true}}::boolean OR pending_prices > 0)
   ORDER BY name_key, thickness, uom
   LIMIT 500;
   ```
3. Widget baru **`swMaterialHargaPending`** (Switch, di sebelah *Belum ada harga*): label `Harga menunggu approval`, Default OFF · Visible: `{{MaterialCtrl.canViewPrice()}}`.
4. `tblMaterials`: sembunyikan kolom baru `pending_prices`.

---

## 3. Page `Material Detail`

### 3a. JSObject
`MaterialDetailCtrl` → tempel ulang `js/MaterialDetailCtrl.js`.

### 3b. Query

**`q_prices`** — ganti seluruhnya (tambah status, alasan tolak, diproses oleh):
```sql
SELECT mp.id, mp.material_supplier_id AS link_id, s.name AS supplier_name, mp.color, mp.price, mp.currency,
       mp.valid_from, mp.valid_to, mp.reference, mp.created_by, mp.created_at,
       mp.status, mp.reject_reason, mp.decided_by, mp.decided_at,
       CASE WHEN mp.status = 'PROPOSED' THEN 'MENUNGGU APPROVAL'
            WHEN mp.status = 'REJECTED' THEN 'DITOLAK'
            WHEN mp.valid_to IS NOT NULL AND mp.valid_to <= fn_today() THEN 'RIWAYAT'
            WHEN mp.valid_from > fn_today() THEN 'AKAN BERLAKU'
            ELSE 'BERLAKU' END AS state
FROM material_price mp
JOIN material_supplier ms ON ms.id = mp.material_supplier_id
JOIN supplier s ON s.id = ms.supplier_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'view_price')) IS NOT NULL
  AND ms.material_id::text = {{appsmith.URL.queryParams.id || ''}}
ORDER BY mp.status = 'PROPOSED' DESC, mp.color_key, mp.valid_from DESC, mp.created_at DESC;
```

Query baru:

**`a_price_approve`**
```sql
SELECT fn_price_approve({{appsmith.store.token}}, {{this.params.id}}::uuid) AS id;
```

**`a_price_reject`**
```sql
SELECT fn_price_reject({{appsmith.store.token}}, {{this.params.id}}::uuid, {{this.params.reason}}) AS id;
```

**`a_price_cancel`** — *Request confirmation before running* = **ON**
```sql
SELECT fn_price_cancel({{appsmith.store.token}}, {{this.params.id}}::uuid) AS id;
```

### 3c. Tabel `tblPrices`

- Sembunyikan kolom baru: `status`, `reject_reason`, `decided_at`.
- Kolom `decided_by`: label `Diproses oleh`.
- Kolom `state` (Keterangan):
  - Computed value: `{{MaterialDetailCtrl.stateText(currentRow)}}`
  - Text color: `{{MaterialDetailCtrl.stateColor(currentRow.state)}}`
- Kolom tombol yang sudah ada — ubah **Cell visible** supaya hanya untuk harga yang sudah APPROVED:
  - `Ganti harga`: `{{!currentRow.valid_to && currentRow.status === 'APPROVED'}}`
  - `Akhiri`: `{{!currentRow.valid_to && currentRow.status === 'APPROVED'}}`
- Kolom tombol **baru**:

| Button | onClick | Visible (kolom) | Cell visible |
|---|---|---|---|
| `Approve` | `{{MaterialDetailCtrl.approvePrice(currentRow)}}` | `{{MaterialDetailCtrl.canManageMaster()}}` | `{{currentRow.status === 'PROPOSED'}}` |
| `Tolak` (warna merah) | `{{MaterialDetailCtrl.openReject(currentRow)}}` | `{{MaterialDetailCtrl.canManageMaster()}}` | `{{currentRow.status === 'PROPOSED'}}` |
| `Batalkan` | `{{MaterialDetailCtrl.cancelPrice(currentRow)}}` | `{{MaterialDetailCtrl.canManagePrice()}}` | `{{currentRow.status === 'PROPOSED'}}` |

### 3d. Modal `mdlTolakHarga` — Custom Widget `cwReasonForm` (baru, dipakai ulang di fase berikutnya)

Modal lebar ±480 px; `cwReasonForm` tinggi ±400 px. Kode: `widgets/cwReasonForm/`.

| Setelan | Isi |
|---|---|
| Default model | `{{MaterialDetailCtrl.rejectFormModel()}}` |
| `onSave` | `{{MaterialDetailCtrl.saveReject()}}` |
| `onCancel` | `{{closeModal('mdlTolakHarga')}}` |

### 3e. `cwPriceForm` (modal `mdlHarga`)

Tempel ulang HTML, Style, dan JavaScript dari `widgets/cwPriceForm/` (tambahan: judul/tombol **Usulkan** untuk Vendor CBD, peringatan usulan yang masih menunggu). Default model tetap `{{MaterialDetailCtrl.priceFormModel()}}`. Tinggi widget ±700 px.

Lalu **Deploy**.

---

## 4. Uji

Material Catalog dengan supplier `PT Maju Jaya` yang sudah punya harga semua warna 45.000 IDR (BERLAKU).

Vendor CBD
- [ ] **+ Tambah Harga** → judul **Usulkan Harga**, info "tersimpan sebagai usulan… harga lama tetap berlaku"; usulkan 47.500 IDR hari ini → baris **MENUNGGU APPROVAL**, harga 45.000 tetap **BERLAKU**
- [ ] Selagi usulan 47.500 masih **menunggu approval**, usulkan lagi untuk supplier + warna yang sama → form memperingatkan & menolak
- [ ] Tidak ada tombol Approve/Tolak; ada **Batalkan** → konfirmasi → usulan hilang
- [ ] Usulkan lagi 47.500 (untuk diuji admin)

Master Admin
- [ ] Master Material: switch **Harga menunggu approval** → material itu muncul; kolom Supplier menampilkan *1 harga menunggu approval*
- [ ] Material Detail: **Approve** → 47.500 BERLAKU, 45.000 pindah ke riwayat (nyalakan *Tampilkan riwayat*)
- [ ] Vendor CBD usulkan harga warna `Black` 50.000 → Admin **Tolak** tanpa alasan → ditolak di form; dengan alasan → baris **DITOLAK: <alasan>** (merah), Diproses oleh = email admin
- [ ] Admin **+ Tambah Harga** sendiri → judul **Tambah Harga**, langsung BERLAKU
- [ ] **Akhiri** masih berfungsi langsung (dengan konfirmasi) untuk harga BERLAKU; tidak muncul di baris usulan / ditolak
- [ ] Audit Log: entri `material_price` UPDATE (status PROPOSED → APPROVED/REJECTED) dan DELETE (batal)

Cek DB (opsional, untuk semua material yang sudah punya harga): harga yang akan dipakai CBD per supplier + warna
```sql
SELECT m.material_code, s.name AS supplier, coalesce(c.color, '(semua warna)') AS warna,
       (SELECT string_agg(mp.status || ' ' || mp.price || ' ' || mp.currency, ', ' ORDER BY mp.created_at)
          FROM material_price mp
         WHERE mp.material_supplier_id = ms.id AND mp.color IS NOT DISTINCT FROM c.color) AS semua_harga_warna_ini,
       l.price AS dipakai_cbd, l.currency, l.tier
FROM material_supplier ms
JOIN material m ON m.id = ms.material_id
JOIN supplier s ON s.id = ms.supplier_id
CROSS JOIN LATERAL (SELECT DISTINCT color FROM material_price WHERE material_supplier_id = ms.id
                    UNION SELECT NULL) c
LEFT JOIN LATERAL fn_price_lookup(ms.material_id, ms.supplier_id, c.color) l ON true
ORDER BY 1, 2, 3;
```
→ `dipakai_cbd` selalu berasal dari harga **APPROVED** yang berlaku. Warna yang hanya punya harga PROPOSED/REJECTED
memakai harga semua warna (`tier` = `ALL_COLORS`), atau kosong kalau belum ada harga semua warna yang APPROVED.

---

## 5. Export

Export app → `appsmith/exports/export_v3b.json` → kirim di chat bersama hasil query cek skema (PLAN.md §8, **sekalian untuk F3**) dan uji yang gagal (kalau ada).
