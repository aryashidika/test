# cwAuditDetail

Panel detail audit (R14) di page `Admin`, tab **Audit Log**, di sebelah kanan `tblAudit`. Klik baris audit → panel
menampilkan waktu (WIB), user, entitas, aksi, ID, lalu daftar perubahan:

| Aksi | Isi panel |
|---|---|
| `UPDATE` | kolom yang berubah saja: nilai lama (merah, dicoret) → nilai baru (hijau) |
| `INSERT` | isi data bila tersimpan; audit ramping (R11) tidak menyimpan isi → keterangan "Record created…" |
| `DELETE` | isi lengkap data yang dihapus |
| lain (`LOGIN`, `REFRESH_FROM_SPEC`, …) | data yang tersimpan, bila ada |

Kolom teknis (`id`, `created_at`, `created_by`, `updated_at`, `updated_by`) dipisah di bawah tombol
**Show technical fields (N)**. UUID diringkas 8 karakter, waktu ke WIB, teks > 160 karakter dipotong (nilai lengkap di
tooltip). Kunci rahasia (`password|token|secret|hash`) dibuang di `q_audit` dan lagi di `AdminCtrl.auditModel()`.

Hanya tampilan; logika format di `AdminCtrl` (`auditModel`, `auditJson`, `auditValue`).

| File | Tab |
|---|---|
| `index.html` / `style.css` / `script.js` | HTML / Style / JavaScript |

Ukuran: tab Audit Log kolom 39–64, baris 10–67 (sama tinggi dengan `tblAudit`); isi bergulir di dalam widget.

## Model masuk (Default model)

```js
{{AdminCtrl.auditModel(tblAudit.selectedRow.id)}}
```

```js
{
  empty,                 // true = tidak ada baris terpilih
  key,                   // id audit (ganti baris -> daftar kolom teknis ditutup lagi)
  action, entity, entityId, time, user,
  kind,                  // 'diff' (lama -> baru) | 'before' (DELETE) | 'after' (INSERT)
  title, note,
  rows: [{ field, tech, before: { text, full, empty }, after: { text, full, empty } }]
}
```

## Nilai keluar & event

Tidak ada.
