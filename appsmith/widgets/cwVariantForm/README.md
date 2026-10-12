# cwVariantForm

Form satu varian material (Material Code, warna, thickness teks ERP) — R2b. Dipakai di **Material Detail** (`mdlVarian`,
`MaterialDetailCtrl`) dan, mulai R4, di **Specsheet** (`mdlVarianBaru`, `BomCtrl`, dari tombol *Daftarkan* di sel kuning).

Model masuk: `{ key, mode: 'add' | 'edit', materialLabel, form: { code, color, thickness, status }, statusOptions, hint, busy, message,
fixed }` — `hint` = hasil `q_code_hint` (arti 3 tengah / 3 akhir kode yang sudah tercatat), `fixed = { color, thickness }` (R4) mengunci
warna & thickness (dari sel specsheet); bila bagian kode tercatat dengan arti lain hanya muncul peringatan, DB menolak saat simpan.
**R9 (menggantikan aturan awalan R8)** — kamus kode per pabrik, tiga tingkat:
- **Tolak** (pesan DB): kode dobel; material + thickness + warna dobel.
- **Konfirmasi** (kotak merah + centang *Sudah saya cek, kode ini benar sesuai ERP*): kode thickness / warna sudah berarti lain
  (dari `hint`, atau pesan DB berawalan `Perlu konfirmasi:`). Simpan mengirim `confirm: true` → `fn_variant_save(..., p_confirm)`.
- **Info** (kotak kuning): warna / thickness biasanya berkode lain, awalan beda, kode bukan 10 karakter.
- **Isi otomatis**: warna + thickness → `onLookup` (`lookupKind: 'suggest'`, `suggestColor`, `suggestThickness`) →
  `model.suggest = { for: 'WARNA|THICKNESS', prefixes, thickness_codes, color_codes }` (daftar dipisah koma, paling sering
  dulu) → kode diisi dengan pilihan pertama; bagian yang belum diketahui dikosongkan. Kode yang diketik user tidak ditimpa.
  Arah sebaliknya (kode → warna/thickness) tetap lewat `lookupKind: 'code'` + `hint`; isian tidak lagi dikunci.
Model keluar `onSave`: + `confirm`. Modal 760 px.

Event: `onSave` (model `code, color, thickness, status, again`), `onCancel`, `onLookup` (model `lookupCode`).
