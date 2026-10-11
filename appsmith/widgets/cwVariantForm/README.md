# cwVariantForm

Form satu varian material (Material Code, warna, thickness teks ERP) — R2b. Dipakai di **Material Detail** (`mdlVarian`,
`MaterialDetailCtrl`) dan, mulai R4, di **Specsheet** (`mdlVarianBaru`, `BomCtrl`, dari tombol *Daftarkan* di sel kuning).

Model masuk: `{ key, mode: 'add' | 'edit', materialLabel, form: { code, color, thickness, status }, statusOptions, hint, busy, message,
fixed }` — `hint` = hasil `q_code_hint` (arti 3 tengah / 3 akhir kode yang sudah tercatat), `fixed = { color, thickness }` (R4) mengunci
warna & thickness (dari sel specsheet); bila bagian kode tercatat dengan arti lain hanya muncul peringatan, DB menolak saat simpan.

Event: `onSave` (model `code, color, thickness, status, again`), `onCancel`, `onLookup` (model `lookupCode`).
