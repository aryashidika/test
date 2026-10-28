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

## R20 bagian 2: warna baku, daftar Dimension (28 Okt 2026)

- Warna dikirim / dicari dalam bentuk baku `cleanColor` (= `fn_clean_color`, salinan sama di `cwBomGrid`): `black / white` -> `BLACK/WHITE`.
- Model baru `dimensions: [{ thickness, n, own }]` (Material Detail: `q_dimensions`, dijalankan `MaterialDetailCtrl` saat form varian dibuka)
  -> datalist `dlDims` di kolom Dimension: dimension material ini (`this material · N colors`) dulu, lalu material lain di pabrik ini.
  Bila `fixed` (modal Register specsheet) daftar tidak dipasang. Ketik dimension baru tetap boleh.

## R20 bagian 3: Dimension wajib, (None), default (28 Okt 2026)

- Dimension wajib (tanda `*`): tanpa dimension = **`(None)`** (opsi pertama datalist, disimpan `''`; `canonThickness` membaca `NONE` /
  `(NONE)` = kosong). Dikosongkan lalu keluar dari kotak = `(None)`. Edit / Register (`fixed`) tanpa dimension tampil `(None)`.
- `dimensions` (Material Detail, `q_dimensions`) kini `{ thickness, n, n_own, own }`, termasuk baris `thickness: ''` milik material ini;
  urut material ini dulu, varian terbanyak, paling dulu. **Tambah** (bukan edit / Register): Dimension diisi default = baris `own`
  pertama dengan `n_own > 0`, selain itu `(None)` (`dimAuto`); daftar yang datang setelah form dibuka mengisi ulang default selama belum
  diubah user. Arti kode (hint) boleh menimpa default. `form.thickness` ada (Save & add another) = dipakai, bukan default.
- `suggest.thickness_free` (`fn_variant_code_suggest`): Dimension kosong yang belum ada di material ini -> baris Dimension usulan diberi
  keterangan `(no dimension in other materials, same UoM first ...)`, bukan "will be rejected".

## R20 bagian 4: Save menunggu cek kode (28 Okt 2026)

- Kode 10 karakter diketik / diubah (atau warna / dimension berubah) -> `requestLookup` mencatat `lookupAt`. Selama `hint` untuk
  kode + warna + dimension yang tampil belum datang (`checking()`), **Save** dan **Save & add another** terkunci dengan tulisan
  **Checking code...**; Enter memberi pesan `Checking the Material Code. Save again in a moment.`. Begitu hint datang, kotak merah /
  tombol **Use** sudah tampil sebelum Save bisa diklik. Tanpa jawaban 5 detik (`CHECK_WAIT`) Save dibuka lagi (DB tetap memeriksa).
  Edit tanpa mengubah kode / warna / dimension tidak menunggu (sama dengan `conflicts()`).
- **Use kode purchasing yang belum terdaftar** (Specsheet, `model.canUse`): `hint.decode = { material_id, label, thickness, color,
  problems }` (BomCtrl menjalankan `q_code_decode` bersama `q_code_hint`). Kode belum dipakai + `decode` tanpa `problems` -> kotak merah
  `Material Code KODE is not registered yet. It reads as LABEL, not this line.` + tombol **Use KODE (LABEL) in the specsheet** ->
  `onLookup` `lookupKind: 'useCode'`, `useCode` (BomCtrl -> `a_bom_use_code`: varian didaftarkan lalu dipakai seperti Use). Save tetap
  ditolak di form dengan pesan ke tombol itu.
