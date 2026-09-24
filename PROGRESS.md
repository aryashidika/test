# Progres Pembangunan — Sistem Specsheet & CBD — Appsmith

> File ini dibuat otomatis oleh `progress/update_progress.py`. Jangan diedit manual —
> ubah `progress/plan.toml` (rencana) atau `progress/status.toml` (status uji & catatan).

| | |
|---|---|
| Export Appsmith | _belum ada — taruh export JSON di `progress/exports/`_ |
| Dump skema DB | _belum ada — taruh dump skema di `progress/db/`_ |
| Diperbarui | 24 Sep 2026 · minggu berjalan **W0** (mulai 28 Sep 2026) |

## Ringkasan

| Fase | Target | Item | Dibuat | Diuji |
|---|---|---|---|---|
| MVP — alur inti Master → Model → Specsheet → CBD | W9 | 191 | ░░░░░░░░░░ 0% | ░░░░░░░░░░ 0% |
| Fase 2 — pelengkap (worklist, laporan, audit, export, copy, persetujuan) | W10 | 68 | ░░░░░░░░░░ 0% | ░░░░░░░░░░ 0% |
| **Total** | | **259** | ░░░░░░░░░░ 0% | ░░░░░░░░░░ 0% |

## Per modul

| Modul | Fase | Target | Dibuat | Diuji | Status |
|---|---|---|---|---|---|
| M0 Fondasi | MVP | W2 | 0/29 | 0/29 | ⬜ Belum mulai |
| M1 Master Data | MVP | W4 | 0/56 | 0/56 | ⬜ Belum mulai |
| M2 Model & Article | MVP | W5 | 0/22 | 0/22 | ⬜ Belum mulai |
| M3 Specsheet | MVP | W7 | 0/42 | 0/42 | ⬜ Belum mulai |
| M4 CBD | MVP | W9 | 0/42 | 0/42 | ⬜ Belum mulai |
| M0 Fondasi | F2 | W10 | 0/7 | 0/7 | ⬜ Belum mulai |
| M1 Master Data | F2 | W10 | 0/17 | 0/17 | ⬜ Belum mulai |
| M2 Model & Article | F2 | W10 | 0/2 | 0/2 | ⬜ Belum mulai |
| M3 Specsheet | F2 | W10 | 0/13 | 0/13 | ⬜ Belum mulai |
| M4 CBD | F2 | W10 | 0/6 | 0/6 | ⬜ Belum mulai |
| M5 Beranda & Laporan | F2 | W10 | 0/23 | 0/23 | ⬜ Belum mulai |

## Peringatan

_Tidak ada._

## Detail checklist

### MVP — alur inti Master → Model → Specsheet → CBD

<details><summary><b>M0 Fondasi</b> — 0/29 dibuat · 0/29 diuji</summary>

**Skema database (hasil migrasi dari SQLite)** · target W2 · 0/23

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Function DB | `fn_assert_perm` |  | ⬜ Belum |  |
| Function DB | `fn_audit` |  | ⬜ Belum |  |
| Tabel DB | `component_group` |  | ⬜ Belum |  |
| Tabel DB | `component` |  | ⬜ Belum |  |
| Tabel DB | `material` |  | ⬜ Belum |  |
| Tabel DB | `material_attachment` |  | ⬜ Belum |  |
| Tabel DB | `supplier` |  | ⬜ Belum |  |
| Tabel DB | `audit_log` |  | ⬜ Belum |  |
| Tabel DB | `product_model` |  | ⬜ Belum |  |
| Tabel DB | `specsheet` |  | ⬜ Belum |  |
| Tabel DB | `specsheet_revision` |  | ⬜ Belum |  |
| Tabel DB | `article` |  | ⬜ Belum |  |
| Tabel DB | `revision_article` |  | ⬜ Belum |  |
| Tabel DB | `bom_line` |  | ⬜ Belum |  |
| Tabel DB | `bom_cell` |  | ⬜ Belum |  |
| Tabel DB | `change_log` |  | ⬜ Belum |  |
| Tabel DB | `specsheet_photo` |  | ⬜ Belum |  |
| Tabel DB | `cbd_revision` |  | ⬜ Belum |  |
| Tabel DB | `cbd_line` |  | ⬜ Belum |  |
| Tabel DB | `material_supplier` |  | ⬜ Belum |  |
| Tabel DB | `material_price` |  | ⬜ Belum |  |
| Tabel DB | `app_user` |  | ⬜ Belum |  |
| Tabel DB | `role_permission` |  | ⬜ Belum |  |

**Kerangka aplikasi, login & hak akses per role** · target W2 · 0/6

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Beranda` |  | ⬜ Belum |  |
| Query | `q_me` | Beranda | ⬜ Belum |  |
| Query | `q_my_perms` | Beranda | ⬜ Belum |  |
| JS Object | `Auth` | Beranda | ⬜ Belum |  |
| JS Object | `Util` | Beranda | ⬜ Belum |  |
| View DB | `v_my_perms` |  | ⬜ Belum |  |

</details>

<details><summary><b>M1 Master Data</b> — 0/56 dibuat · 0/56 diuji</summary>

**Supplier** · target W3 · 0/10

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Master_Supplier` |  | ⬜ Belum |  |
| Query | `q_suppliers` | Master_Supplier | ⬜ Belum |  |
| Query | `a_supplier_create` | Master_Supplier | ⬜ Belum |  |
| Query | `a_supplier_update` | Master_Supplier | ⬜ Belum |  |
| Query | `a_supplier_set_status` | Master_Supplier | ⬜ Belum |  |
| JS Object | `SupplierCtrl` | Master_Supplier | ⬜ Belum |  |
| Function DB | `fn_supplier_create` |  | ⬜ Belum |  |
| Function DB | `fn_supplier_update` |  | ⬜ Belum |  |
| Function DB | `fn_supplier_set_status` |  | ⬜ Belum |  |
| View DB | `v_supplier_list` |  | ⬜ Belum |  |

**Komponen** · target W3 · 0/13

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Master_Komponen` |  | ⬜ Belum |  |
| Query | `q_component_groups` | Master_Komponen | ⬜ Belum |  |
| Query | `q_components` | Master_Komponen | ⬜ Belum |  |
| Query | `q_next_component_number` | Master_Komponen | ⬜ Belum |  |
| Query | `a_component_create` | Master_Komponen | ⬜ Belum |  |
| Query | `a_component_update` | Master_Komponen | ⬜ Belum |  |
| Query | `a_component_set_status` | Master_Komponen | ⬜ Belum |  |
| JS Object | `KomponenCtrl` | Master_Komponen | ⬜ Belum |  |
| Function DB | `fn_component_create` |  | ⬜ Belum |  |
| Function DB | `fn_component_update` |  | ⬜ Belum |  |
| Function DB | `fn_component_set_status` |  | ⬜ Belum |  |
| Function DB | `fn_next_component_number` |  | ⬜ Belum |  |
| View DB | `v_component_list` |  | ⬜ Belum |  |

**Daftar & buat Material** · target W3 · 0/8

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Master_Material` |  | ⬜ Belum |  |
| Query | `q_materials` | Master_Material | ⬜ Belum |  |
| Query | `q_next_material_code` | Master_Material | ⬜ Belum |  |
| Query | `a_material_create` | Master_Material | ⬜ Belum |  |
| JS Object | `MaterialCtrl` | Master_Material | ⬜ Belum |  |
| Function DB | `fn_material_create` |  | ⬜ Belum |  |
| Function DB | `fn_next_material_code` |  | ⬜ Belum |  |
| View DB | `v_material_list` |  | ⬜ Belum |  |

**Detail Material: info, supplier, harga, metode harga (format sesuai ERP)** · target W4 · 0/25

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Material_Detail` |  | ⬜ Belum |  |
| Query | `q_material` | Material_Detail | ⬜ Belum |  |
| Query | `q_material_suppliers` | Material_Detail | ⬜ Belum |  |
| Query | `q_material_prices` | Material_Detail | ⬜ Belum |  |
| Query | `a_material_update` | Material_Detail | ⬜ Belum |  |
| Query | `a_material_set_status` | Material_Detail | ⬜ Belum |  |
| Query | `a_material_set_price_method` | Material_Detail | ⬜ Belum |  |
| Query | `a_material_supplier_add` | Material_Detail | ⬜ Belum |  |
| Query | `a_material_supplier_set_code` | Material_Detail | ⬜ Belum |  |
| Query | `a_material_supplier_set_preferred` | Material_Detail | ⬜ Belum |  |
| Query | `a_material_supplier_set_status` | Material_Detail | ⬜ Belum |  |
| Query | `a_price_add` | Material_Detail | ⬜ Belum |  |
| Query | `a_price_end` | Material_Detail | ⬜ Belum |  |
| JS Object | `MaterialDetailCtrl` | Material_Detail | ⬜ Belum |  |
| Function DB | `fn_material_update` |  | ⬜ Belum |  |
| Function DB | `fn_material_set_status` |  | ⬜ Belum |  |
| Function DB | `fn_material_set_price_method` |  | ⬜ Belum |  |
| Function DB | `fn_material_supplier_add` |  | ⬜ Belum |  |
| Function DB | `fn_material_supplier_set_code` |  | ⬜ Belum |  |
| Function DB | `fn_material_supplier_set_preferred` |  | ⬜ Belum |  |
| Function DB | `fn_material_supplier_set_status` |  | ⬜ Belum |  |
| Function DB | `fn_price_add` |  | ⬜ Belum |  |
| Function DB | `fn_price_end` |  | ⬜ Belum |  |
| View DB | `v_material_suppliers` |  | ⬜ Belum |  |
| View DB | `v_material_prices` |  | ⬜ Belum |  |

</details>

<details><summary><b>M2 Model & Article</b> — 0/22 dibuat · 0/22 diuji</summary>

**Daftar Model** · target W5 · 0/6

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Model_List` |  | ⬜ Belum |  |
| Query | `q_models` | Model_List | ⬜ Belum |  |
| Query | `a_model_create` | Model_List | ⬜ Belum |  |
| JS Object | `ModelCtrl` | Model_List | ⬜ Belum |  |
| Function DB | `fn_model_create` |  | ⬜ Belum |  |
| View DB | `v_model_overview` |  | ⬜ Belum |  |

**Detail Model: season & article** · target W5 · 0/16

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Model_Detail` |  | ⬜ Belum |  |
| Query | `q_model` | Model_Detail | ⬜ Belum |  |
| Query | `q_seasons` | Model_Detail | ⬜ Belum |  |
| Query | `q_articles` | Model_Detail | ⬜ Belum |  |
| Query | `a_model_update` | Model_Detail | ⬜ Belum |  |
| Query | `a_season_create` | Model_Detail | ⬜ Belum |  |
| Query | `a_article_create` | Model_Detail | ⬜ Belum |  |
| Query | `a_article_update` | Model_Detail | ⬜ Belum |  |
| Query | `a_article_delete` | Model_Detail | ⬜ Belum |  |
| JS Object | `ModelDetailCtrl` | Model_Detail | ⬜ Belum |  |
| Function DB | `fn_model_update` |  | ⬜ Belum |  |
| Function DB | `fn_season_create` |  | ⬜ Belum |  |
| Function DB | `fn_article_create` |  | ⬜ Belum |  |
| Function DB | `fn_article_update` |  | ⬜ Belum |  |
| Function DB | `fn_article_delete` |  | ⬜ Belum |  |
| View DB | `v_articles` |  | ⬜ Belum |  |

</details>

<details><summary><b>M3 Specsheet</b> — 0/42 dibuat · 0/42 diuji</summary>

**Daftar Specsheet** · target W6 · 0/3

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Specsheet_List` |  | ⬜ Belum |  |
| Query | `q_specsheets` | Specsheet_List | ⬜ Belum |  |
| View DB | `v_specsheet_list` |  | ⬜ Belum |  |

**Revisi & stage: buat kosong, revisi stage sama/berikut, hapus draft** · target W6 · 0/17

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Specsheet_Detail` |  | ⬜ Belum |  |
| Query | `q_revisions` | Specsheet_Detail | ⬜ Belum |  |
| Query | `q_revision` | Specsheet_Detail | ⬜ Belum |  |
| Query | `q_revision_articles` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_revision_create_empty` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_revision_same_stage` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_revision_next_stage` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_revision_delete_draft` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_revision_include_article` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_article_set_status` | Specsheet_Detail | ⬜ Belum |  |
| JS Object | `SpecCtrl` | Specsheet_Detail | ⬜ Belum |  |
| Function DB | `fn_revision_create_empty` |  | ⬜ Belum |  |
| Function DB | `fn_revision_same_stage` |  | ⬜ Belum |  |
| Function DB | `fn_revision_next_stage` |  | ⬜ Belum |  |
| Function DB | `fn_revision_delete_draft` |  | ⬜ Belum |  |
| Function DB | `fn_revision_include_article` |  | ⬜ Belum |  |
| Function DB | `fn_article_set_status` |  | ⬜ Belum |  |

**Grid BOM (Custom Widget)** · target W7 · 0/17

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `q_bom_lines` | Specsheet_Detail | ⬜ Belum |  |
| Query | `q_component_all` | Specsheet_Detail | ⬜ Belum |  |
| Query | `q_material_all` | Specsheet_Detail | ⬜ Belum |  |
| Query | `q_supplier_all` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_bom_add_line` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_bom_replace_material` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_bom_update_process` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_bom_update_supplier` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_bom_update_cell` | Specsheet_Detail | ⬜ Belum |  |
| JS Object | `BomCtrl` | Specsheet_Detail | ⬜ Belum |  |
| Widget | `BomGrid` | Specsheet_Detail | ⬜ Belum |  |
| Function DB | `fn_bom_add_line` |  | ⬜ Belum |  |
| Function DB | `fn_bom_replace_material` |  | ⬜ Belum |  |
| Function DB | `fn_bom_update_process` |  | ⬜ Belum |  |
| Function DB | `fn_bom_update_supplier` |  | ⬜ Belum |  |
| Function DB | `fn_bom_update_cell` |  | ⬜ Belum |  |
| View DB | `v_bom_lines` |  | ⬜ Belum |  |

**Checklist & terbitkan specsheet (+ tandai CBD NEEDS_REVISION)** · target W7 · 0/5

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `q_publish_checklist` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_revision_publish` | Specsheet_Detail | ⬜ Belum |  |
| Function DB | `fn_publish_checklist` |  | ⬜ Belum |  |
| Function DB | `fn_revision_publish` |  | ⬜ Belum |  |
| Function DB | `fn_mark_cbd_sync_status` |  | ⬜ Belum |  |

</details>

<details><summary><b>M4 CBD</b> — 0/42 dibuat · 0/42 diuji</summary>

**Daftar CBD per article** · target W8 · 0/3

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `CBD_List` |  | ⬜ Belum |  |
| Query | `q_cbd_list` | CBD_List | ⬜ Belum |  |
| View DB | `v_cbd_list` |  | ⬜ Belum |  |

**Buat revisi CBD dari specsheet & grid baris (yield, loss, harga master)** · target W8 · 0/18

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `CBD_Detail` |  | ⬜ Belum |  |
| Query | `q_cbd_revisions` | CBD_Detail | ⬜ Belum |  |
| Query | `q_cbd_revision` | CBD_Detail | ⬜ Belum |  |
| Query | `q_cbd_lines` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_create_no_source` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_same_stage` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_next_stage` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_delete_draft` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_update_yield` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_update_loss` | CBD_Detail | ⬜ Belum |  |
| JS Object | `CbdCtrl` | CBD_Detail | ⬜ Belum |  |
| Function DB | `fn_cbd_create_no_source` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_same_stage` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_next_stage` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_delete_draft` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_update_yield` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_update_loss` |  | ⬜ Belum |  |
| View DB | `v_cbd_lines` |  | ⬜ Belum |  |

**Quotation, override harga, rekap biaya** · target W9 · 0/11

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `q_cbd_summary` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_set_quotation` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_override_price` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_clear_override` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_update_field` | CBD_Detail | ⬜ Belum |  |
| JS Object | `OverrideCtrl` | CBD_Detail | ⬜ Belum |  |
| Function DB | `fn_cbd_set_quotation` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_override_price` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_clear_override` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_update_field` |  | ⬜ Belum |  |
| View DB | `v_cbd_summary` |  | ⬜ Belum |  |

**Refresh (specsheet usang / harga master berubah), checklist & terbitkan CBD** · target W9 · 0/10

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `q_cbd_stale` | CBD_Detail | ⬜ Belum |  |
| Query | `q_cbd_checklist` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_refresh_draft` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_refresh_prices` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_publish` | CBD_Detail | ⬜ Belum |  |
| Function DB | `fn_cbd_stale_lines` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_checklist` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_refresh_draft` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_refresh_prices` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_publish` |  | ⬜ Belum |  |

</details>

### Fase 2 — pelengkap (worklist, laporan, audit, export, copy, persetujuan)

<details><summary><b>M0 Fondasi</b> — 0/7 dibuat · 0/7 diuji</summary>

**Kelola user & role (MVP: user diisi lewat SQL)** · target W10 · 0/7

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Admin_User` |  | ⬜ Belum |  |
| Query | `q_users` | Admin_User | ⬜ Belum |  |
| Query | `a_user_upsert` | Admin_User | ⬜ Belum |  |
| Query | `a_user_set_active` | Admin_User | ⬜ Belum |  |
| JS Object | `UserCtrl` | Admin_User | ⬜ Belum |  |
| Function DB | `fn_user_upsert` |  | ⬜ Belum |  |
| Function DB | `fn_user_set_active` |  | ⬜ Belum |  |

</details>

<details><summary><b>M1 Master Data</b> — 0/17 dibuat · 0/17 diuji</summary>

**Antrian persetujuan (MVP: approve dari Detail Material)** · target W10 · 0/6

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Persetujuan` |  | ⬜ Belum |  |
| Query | `q_approval_queue` | Persetujuan | ⬜ Belum |  |
| Query | `a_approve` | Persetujuan | ⬜ Belum |  |
| JS Object | `ApprovalCtrl` | Persetujuan | ⬜ Belum |  |
| Function DB | `fn_approve` |  | ⬜ Belum |  |
| View DB | `v_approval_queue` |  | ⬜ Belum |  |

**Deteksi duplikat & merge material** · target W10 · 0/4

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `q_similar_materials` | Master_Material | ⬜ Belum |  |
| Query | `a_material_merge` | Master_Material | ⬜ Belum |  |
| Function DB | `fn_similar_materials` |  | ⬜ Belum |  |
| Function DB | `fn_material_merge` |  | ⬜ Belum |  |

**Tab Dipakai di & Histori Harga di Detail Material** · target W10 · 0/4

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `q_where_used` | Material_Detail | ⬜ Belum |  |
| Query | `q_price_history` | Material_Detail | ⬜ Belum |  |
| View DB | `v_where_used` |  | ⬜ Belum |  |
| View DB | `v_price_history` |  | ⬜ Belum |  |

**Lampiran material** · target W10 · 0/3

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `q_material_attachments` | Material_Detail | ⬜ Belum |  |
| Query | `a_material_attachment_add` | Material_Detail | ⬜ Belum |  |
| Function DB | `fn_material_attachment_add` |  | ⬜ Belum |  |

</details>

<details><summary><b>M2 Model & Article</b> — 0/2 dibuat · 0/2 diuji</summary>

**Copy article dari season lain** · target W10 · 0/2

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `a_copy_articles` | Model_Detail | ⬜ Belum |  |
| Function DB | `fn_copy_articles` |  | ⬜ Belum |  |

</details>

<details><summary><b>M3 Specsheet</b> — 0/13 dibuat · 0/13 diuji</summary>

**Carryover season & copy lintas model** · target W10 · 0/5

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `q_copy_candidates` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_revision_carryover` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_revision_copy_cross_model` | Specsheet_Detail | ⬜ Belum |  |
| Function DB | `fn_revision_carryover` |  | ⬜ Belum |  |
| Function DB | `fn_revision_copy_cross_model` |  | ⬜ Belum |  |

**Sub-komponen, foto, change log & diff revisi** · target W10 · 0/8

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `a_bom_add_subcomponent` | Specsheet_Detail | ⬜ Belum |  |
| Query | `q_change_log` | Specsheet_Detail | ⬜ Belum |  |
| Query | `q_revision_diff` | Specsheet_Detail | ⬜ Belum |  |
| Query | `q_specsheet_photos` | Specsheet_Detail | ⬜ Belum |  |
| Query | `a_specsheet_photo_add` | Specsheet_Detail | ⬜ Belum |  |
| Function DB | `fn_bom_add_subcomponent` |  | ⬜ Belum |  |
| Function DB | `fn_revision_diff` |  | ⬜ Belum |  |
| Function DB | `fn_specsheet_photo_add` |  | ⬜ Belum |  |

</details>

<details><summary><b>M4 CBD</b> — 0/6 dibuat · 0/6 diuji</summary>

**Copy CBD dari article / season lain & change log** · target W10 · 0/6

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `q_copy_sources` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_from_article` | CBD_Detail | ⬜ Belum |  |
| Query | `a_cbd_from_season` | CBD_Detail | ⬜ Belum |  |
| Query | `q_cbd_change_log` | CBD_Detail | ⬜ Belum |  |
| Function DB | `fn_cbd_from_article` |  | ⬜ Belum |  |
| Function DB | `fn_cbd_from_season` |  | ⬜ Belum |  |

</details>

<details><summary><b>M5 Beranda & Laporan</b> — 0/23 dibuat · 0/23 diuji</summary>

**Beranda 'Tugas Saya' per role** · target W10 · 0/10

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Query | `q_spec_worklist` | Beranda | ⬜ Belum |  |
| Query | `q_cbd_worklist` | Beranda | ⬜ Belum |  |
| Query | `q_price_gaps` | Beranda | ⬜ Belum |  |
| Query | `q_recently_published` | Beranda | ⬜ Belum |  |
| Query | `q_system_summary` | Beranda | ⬜ Belum |  |
| JS Object | `BerandaCtrl` | Beranda | ⬜ Belum |  |
| View DB | `v_spec_worklist` |  | ⬜ Belum |  |
| View DB | `v_cbd_worklist` |  | ⬜ Belum |  |
| View DB | `v_price_gaps` |  | ⬜ Belum |  |
| View DB | `v_recently_published` |  | ⬜ Belum |  |

**Laporan: validasi CBD vs specsheet, penyimpangan loss** · target W10 · 0/5

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Laporan` |  | ⬜ Belum |  |
| Query | `q_validation_report` | Laporan | ⬜ Belum |  |
| Query | `q_loss_deviation` | Laporan | ⬜ Belum |  |
| Function DB | `fn_validation_report` |  | ⬜ Belum |  |
| View DB | `v_loss_deviation` |  | ⬜ Belum |  |

**Audit Log** · target W10 · 0/3

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Audit_Log` |  | ⬜ Belum |  |
| Query | `q_audit_log` | Audit_Log | ⬜ Belum |  |
| View DB | `v_audit_log` |  | ⬜ Belum |  |

**Export Excel specsheet & CBD** · target W10 · 0/2

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| JS Object | `ExportCtrl` | Specsheet_Detail | ⬜ Belum |  |
| Library | `xlsx` |  | ⬜ Belum |  |

**Export Excel CBD** · target W10 · 0/1

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| JS Object | `ExportCtrl` | CBD_Detail | ⬜ Belum |  |

**Halaman cetak** · target W10 · 0/2

| Jenis | Nama | Page | Status | Catatan |
|---|---|---|---|---|
| Page | `Print_Specsheet` |  | ⬜ Belum |  |
| Page | `Print_CBD` |  | ⬜ Belum |  |

</details>

## Di luar rencana

Ada di Appsmith/DB tapi tidak ada di `plan.toml`. Bisa jadi salah nama, atau item baru yang perlu ditambahkan ke rencana.

_Tidak ada._

## Riwayat

_Belum ada._

## Cara update

1. Appsmith: menu aplikasi → **Export** → simpan `.json` ke `progress/exports/`
2. `pg_dump --schema-only -f progress/db/schema_YYYYMMDD.sql <nama_db>` (pakai `-f`, bukan `>`)
3. Tandai item yang sudah dites di `progress/status.toml`
4. `python progress/update_progress.py`
