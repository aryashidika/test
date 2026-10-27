# cwVariantForm

Form satu varian material (Material Code, warna, thickness teks ERP) - R2b. Dipakai di **Material Detail** (`mdlVarian`,
`MaterialDetailCtrl`) dan, mulai R4, di **Specsheet** (`mdlVarianBaru`, `BomCtrl`, dari tombol *Daftarkan* di sel kuning).

Model masuk: `{ key, mode: 'add' | 'edit', materialLabel, form: { code, color, thickness, status }, statusOptions, hint, busy, message,
fixed }` - `hint` = hasil `q_code_hint` (arti 3 tengah / 3 akhir kode yang sudah tercatat), `fixed = { color, thickness }` (R4) mengunci
warna & thickness (dari sel specsheet); bila bagian kode tercatat dengan arti lain hanya muncul peringatan, DB menolak saat simpan.
**R9 (menggantikan aturan awalan R8)** - kamus kode per pabrik, tiga tingkat:
- **Tolak** (pesan DB): kode dobel; material + thickness + warna dobel.
- **Konfirmasi** (kotak merah + centang *Sudah saya cek, kode ini benar sesuai ERP*): kode thickness / warna sudah berarti lain
  (dari `hint`, atau pesan DB berawalan `Confirmation needed:`, sejak R15). Simpan mengirim `confirm: true` → `fn_variant_save(..., p_confirm)`.
  R16: thickness dibandingkan dalam bentuk baku (`canonThickness`, salinan sama dengan `cwBomGrid` = `fn_clean_thickness`), jadi `44 "` = `44"`.
- **Info** (kotak kuning): warna / thickness biasanya berkode lain, awalan beda, kode bukan 10 karakter.
- **Isi otomatis**: warna + thickness → `onLookup` (`lookupKind: 'suggest'`, `suggestColor`, `suggestThickness`) →
  `model.suggest = { for: 'WARNA|THICKNESS', prefixes, thickness_codes, color_codes }` (daftar dipisah koma, paling sering
  dulu) → kode diisi dengan pilihan pertama; bagian yang belum diketahui dikosongkan. Kode yang diketik user tidak ditimpa.
  Arah sebaliknya (kode → warna/thickness) tetap lewat `lookupKind: 'code'` + `hint`; isian tidak lagi dikunci.
Model keluar `onSave`: + `confirm`. Modal 760 px.

Event: `onSave` (model `code, color, thickness, status, again`), `onCancel`, `onLookup` (model `lookupCode`).

**R20 (27 Okt 2026, menggantikan tingkat Konfirmasi & Info awalan R9)** - kode 10 karakter ketat dua arah, tanpa centang:
- `onLookup` `lookupKind: 'code'` kini juga mengirim `lookupColor`, `lookupThickness` (diulang saat warna / dimension diubah). Controller
  mengisi `hint = { for: 'KODE|WARNA|DIMENSION', ..., used_id, used_label, used_active, problems }` (`q_code_hint`, `problems` = satu masalah
  per baris dari `fn_variant_code_problems`). Hint hanya berlaku bila `for` sama dengan isian sekarang.
- Kotak merah: `This Material Code cannot be saved: ...` atau `Material Code ... is already used: ...`; Save ditolak di form (DB juga).
  Edit tanpa mengubah kode / warna / dimension = tidak dicek (ubah status saja boleh, sama dengan DB).
- `model.canUse` (Specsheet) + kode sudah dipakai varian ACTIVE -> tombol **Use KODE in the specsheet** -> `onLookup` `lookupKind: 'use'`,
  `useId`, `useCode` (`BomCtrl.useFromRegister`).
- Centang konfirmasi dan `confirm` di `onSave` dihapus. Info kuning tinggal: kode bukan 10 karakter.
