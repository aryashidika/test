# R17: uji Remember me (Login) + Material Code wajib mulai SMS & harga ESTIMATE (CBD)

R17 punya dua bagian (satu SQL, satu import): **bagian 1** Remember me (bagian 1 s.d. 4 panduan ini), **bagian 2** Material Code wajib
mulai SMS + estimasi harga (bagian 5 s.d. 11).

Isi R17 (keputusan user 22 Okt 2026; app hanya bisa dibuka lewat VPN, jadi login app dikurangi):
- Checkbox **Remember me** di halaman Login, **tidak dicentang** secara default, dengan catatan
  `Stay logged in for 7 days (up to 30 days). Don't use on shared computers.`
- **Dicentang**: sesi habis bila app tidak dibuka **7 hari**. Setiap kali app dibuka, masa berlaku mundur lagi menjadi 7 hari,
  tetapi **paling lama 30 hari** sejak login. Setelah 30 hari wajib login ulang.
- **Tidak dicentang**: sesi **12 jam**, sama seperti sebelumnya (untuk PC bersama).
- **Email terakhir selalu diingat** di browser: saat login berikutnya cukup ketik password. Tetap diingat setelah Log out.
- Sesi tetap diputus seperti sebelumnya oleh: **Log out**, ganti password (perangkat lain), reset password / ubah role / ubah pabrik /
  nonaktifkan user oleh System Admin.
- Yang berubah hanya page **Login** (widget `cwLogin`, `LoginCtrl`, query `a_login`) dan 2 fungsi DB (`fn_login`, `fn_me`).

> Build ini dibuat dari export app Anda tanggal 22 Okt 2026 (`exports/export_r16.json`), jadi tata letak tabel yang Anda rapikan
> (Model List, Master Material, dst.) ikut terbawa.

Beri tanda di kolom **OK?** (v / x). Kalau ada yang beda, kirim tangkapan layar dan teks pesannya.
Ganti `spec@uji.test` di query di bawah dengan email akun uji yang Anda pakai.

## 0. Pasang

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 0.1 | DB Tools → jalankan `sql/R17_remember_estimate.sql` (prepared statements OFF) | `fn_login 3 parameter: true` · `fn_login lama (2 parameter) sudah hilang: true` · `sesi aktif: N, remember: 0` · `kode wajib mulai SMS: PULL=false PREV=false SMS=true GTM=true PROD=true` · `sumber harga ESTIMATE diterima: true` · `specsheet terbit dengan sel kuning (Pullover / Preview): 0` | |
| 0.2 | Jalankan lagi `sql/R17_remember_estimate.sql` | Aman: hasil sama | |
| 0.3 | DB Tools → jalankan `sql/R_selftest.sql` | **`SELFTEST LOLOS`** (di panel NOTICE ada 45 baris `ok  R17 ...`) | |
| 0.4 | Sebelum import: buka app R16 yang sekarang, login | Masih bisa login (app lama tetap jalan dengan SQL baru) | |
| 0.5 | Import `exports/build_r17.json` sebagai app baru → cek datasource *Prestasi* tersambung → Deploy → nyalakan akses publik | Nama app *Product Management R17* | |
| 0.6 | Di editor: page **Login** → JSObject **LoginCtrl** → fungsi **onPageLoad** → Settings | *Run on page load* = ON. Bila OFF: nyalakan, lalu Deploy | |

## 1. Tampilan

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 1.1 | Buka app (belum login) | Di bawah Password ada checkbox **Remember me** (tidak dicentang) dan catatan kecil 7 hari / 30 hari / shared computers | |
| 1.2 | Klik tulisan **Remember me** | Checkbox ikut tercentang / lepas (klik tulisan juga bisa) | |
| 1.3 | Tekan Enter di field Password dengan email / password salah | Pesan `Wrong email or password.`; centang Remember me tetap seperti sebelumnya | |

## 2. Login tanpa Remember me (sama seperti dulu)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 2.1 | Login **tanpa** mencentang Remember me | Masuk ke Home | |
| 2.2 | DB Tools: `SELECT remember, expires_at, max_expires_at FROM app_session WHERE email = 'spec@uji.test' ORDER BY created_at DESC LIMIT 1;` | `remember = false`, `expires_at` = 12 jam dari saat login, `max_expires_at` kosong | |
| 2.3 | Klik **Logout** di header | Kembali ke Login, pesan `You are logged out.`, **email sudah terisi** | |

## 3. Login dengan Remember me

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 3.1 | Centang **Remember me**, login | Masuk ke Home | |
| 3.2 | Query 2.2 lagi | `remember = true`, `expires_at` = 7 hari dari saat login, `max_expires_at` = 30 hari dari saat login | |
| 3.3 | Tutup **semua** jendela browser, buka lagi, buka URL app | Langsung masuk Home tanpa login | |
| 3.4 | Pura-pura app terakhir dibuka 5 hari lalu: `UPDATE app_session SET expires_at = now() + interval '2 days' WHERE email = 'spec@uji.test' AND remember;` lalu buka / refresh page mana saja di app | Page terbuka normal. Query 2.2: `expires_at` kembali **7 hari dari sekarang** | |
| 3.5 | Pura-pura tidak dibuka 7 hari: `UPDATE app_session SET expires_at = now() - interval '1 minute' WHERE email = 'spec@uji.test' AND remember;` lalu refresh page | Pesan `Session expired. Please log in again.`, pindah ke Login, email sudah terisi | |
| 3.6 | Login lagi dengan Remember me, lalu pura-pura sudah 30 hari: `UPDATE app_session SET expires_at = now() + interval '1 day', max_expires_at = now() + interval '1 day' WHERE email = 'spec@uji.test' AND remember;` lalu refresh page | Page terbuka. Query 2.2: `expires_at` **tidak** mundur ke 7 hari (tetap = `max_expires_at`), jadi besok wajib login ulang | |

## 4. Sesi tetap bisa diputus

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 4.1 | Login dengan Remember me → klik **Logout** → tombol **Back** browser | Tetap di Login, tidak masuk lagi | |
| 4.2 | Login dengan Remember me di browser A. Di browser B (atau jendela Incognito) login sebagai System Admin → Admin → **Reset password** user itu. Di browser A refresh page | Browser A: `Session expired. Please log in again.` | |
| 4.3 | Login dengan password sementara dari 4.2 + Remember me | Diminta ganti password dulu (form Change Password), lalu masuk Home | |
| 4.4 | Di browser B: Admin → ubah user itu jadi **nonaktif**, lalu refresh page di browser A | Browser A keluar ke Login. Aktifkan lagi user itu sesudahnya | |

## 5. Bagian 2: persiapan data uji

Bagian 2 menguji keputusan 22 Okt 2026: **Material Code wajib mulai SMS**, harga **ESTIMATE** untuk baris CBD tanpa kode di Pullover / Preview,
dan baris ber-Yield tanpa harga **memblokir mulai SMS**. Siapkan 3 akun: Vendor Spec, Vendor CBD, Manager Costing (pabrik yang sama).

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 5.1 | Pilih **material A**: sudah punya Material Code warna BLACK **dan** harga master yang disetujui untuk satu supplier | Catat nama, thickness, supplier | |
| 5.2 | Pilih **material B**: sudah punya Material Code warna BLACK tetapi **belum punya harga** untuk supplier-nya (Home Vendor CBD, bagian harga belum ada, atau daftarkan varian baru di Material Detail) | Catat nama, thickness, supplier | |
| 5.3 | Vendor Spec: Model List → buat model **UJI R17**, season apa saja, article **UJI-R17A** warna BLACK | Model & article tersimpan | |

## 6. Specsheet Preview boleh terbit tanpa kode (Vendor Spec)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 6.1 | Specsheet UJI R17 → Create revision → Empty, stage **Preview** | Draft Preview r0 | |
| 6.2 | Tambah baris material A dan material B (supplier sesuai 5.1 / 5.2), warna BLACK | Sel berisi warna + Material Code | |
| 6.3 | Tambah baris material baru lewat **+ New material**, misalnya `UJI R17 TOE PUFF`, thickness `0.8MM`, supplier yang sama dengan A, warna BLACK | Sel **kuning** (belum ada kode) | |
| 6.4 | Klik **Publish** | Checklist: baris `All colors have a Material Code (no yellow cells)` tampil sebagai **peringatan** (bukan merah), keterangan `... Allowed in Pullover and Preview; required from SMS`. Tombol publish **bisa** diklik | |
| 6.5 | Publish | Preview r0 **PUBLISHED** | |
| 6.6 | Export Excel specsheet | Sel toe puff kuning dengan `(no code)` (sama seperti R16) | |

## 7. CBD Preview dengan estimasi (Vendor CBD)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 7.1 | CBD → article UJI-R17A → Create CBD → stage **Preview** → isi Exchange rate, Yield 1 di semua baris | Baris A: harga master, badge **master**. Baris B: `no master price for this Material Code + supplier` + tombol **Propose master price**. Baris toe puff: di kolom Material ada tanda kuning **no Material Code**, di kolom Price `no Material Code yet. Enter an estimate` + tombol **Enter estimate** | |
| 7.2 | Lihat banner kuning di atas grid | `2 lines have a Yield but no price. They can still publish with cost 0. ...` dan `1 have no Material Code yet: click Enter estimate in the Price column.` | |
| 7.3 | Klik **Enter estimate** (baris toe puff) | Modal **Estimate Price**: kotak biru `No Material Code yet. Estimates are allowed in Pullover and Preview only; ...`. Belum ada kotak saran (belum pernah ada estimasi) | |
| 7.4 | Isi harga `12500`, currency IDR, referensi `perkiraan purchasing`, Save | Pesan `Estimate saved.` Kolom Price: 12.500 + badge kuning **estimate** (arahkan mouse: referensi tampil). Cost/pr terhitung | |
| 7.5 | Klik **Publish** | Checklist: `Lines with Yield have a price` = **peringatan** (baris B); `1 lines use an estimate price (no Material Code yet)` = ok, keterangan `Allowed in Pullover and Preview...`. Bisa publish | |
| 7.6 | Publish, lalu Export Excel CBD | CBD Preview r0 terbit. Di Excel baris toe puff **kuning**, material `UJI R17 TOE PUFF (no code)`, kolom sumber `estimate` | |
| 7.7 | Login Vendor Spec, buka CBD yang sama (draft lain bila ada) | Tidak ada tombol Enter estimate (hanya Vendor CBD) | |

## 8. Revisi berikutnya: estimasi ikut + saran (Vendor CBD)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 8.1 | Create CBD → **Next revision** (Preview r1) | Baris toe puff tetap 12.500 badge **estimate** (ikut terbawa) | |
| 8.2 | Klik **Edit estimate** | Isian terisi 12500 IDR + referensi. Kotak kuning `Last estimate: 12.500 IDR · UJI R17 · UJI-R17A · Preview r0, <tanggal>` + tombol **Use** | |
| 8.3 | Kosongkan harga → Save | `Estimate cleared.` Baris kembali `no Material Code yet. Enter an estimate` | |
| 8.4 | Klik **Enter estimate** → **Use** → Save | Harga 12500, IDR, referensi `perkiraan purchasing` terisi dari saran. Tersimpan | |
| 8.5 | Hapus draft Preview r1 (tombol **Delete Draft**) | Kembali ke Preview r0 terbit | |

## 9. Specsheet SMS: kode wajib (Vendor Spec)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 9.1 | Specsheet → Create revision → **Next stage** → SMS | Draft SMS r0, baris toe puff ikut, sel masih **kuning** | |
| 9.2 | Klik **Publish** | Checklist: baris sel kuning **merah** (memblokir), keterangan `... Required from SMS. Click Register in that cell` | |
| 9.3 | (Opsional) coba publish lewat DB Tools: `SELECT fn_revision_publish('<token>', '<id draft SMS>', 'OTHER', 'uji');` | Ditolak: `From SMS every color needs a Material Code. 1 color cell(s) have no Material Code (yellow cells): UJI R17 TOE PUFF 0.8 MM · BLACK. ...` | |
| 9.4 | Klik **Register** di sel kuning → isi Material Code (dari tim material) → Save | Sel tidak kuning lagi, berisi kode | |
| 9.5 | Publish SMS r0 | Terbit | |
| 9.6 | Buka lagi Preview r0 (stepper) | Sel toe puff di Preview r0 **tetap kuning** (revisi terbit tidak berubah) | |

## 10. CBD SMS: semua harga master (Vendor CBD, Manager Costing)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 10.1 | Create CBD → stage **SMS**, isi Exchange rate | Baris toe puff sekarang punya Material Code, Yield 1 ikut, **tidak** ada harga estimasi, **tidak** ada tombol Enter estimate; ada **Propose master price** | |
| 10.2 | Lihat banner | Banner **merah**: `2 lines have a Yield but no price. From SMS the CBD cannot be published until they have a price (or are marked No charge). ...` | |
| 10.3 | Klik **Publish** | `Lines with Yield have a price` **merah** (memblokir), keterangan `... From SMS every line with a Yield needs a price (or No charge)` | |
| 10.4 | Baris toe puff → **Propose master price** | Harga sudah terisi **12500** dan currency **IDR** dari estimasi Preview. Kotak biru: `... Price filled in from the estimate 12.500,00 IDR (UJI R17 · UJI-R17A · Preview r0, <tanggal>). Check it before saving.` Referensi **kosong** | |
| 10.5 | Ubah harga bila perlu, isi referensi penawaran supplier, Propose. Lakukan juga untuk baris B | Kedua baris menunggu approval (banner merah pending) | |
| 10.6 | Manager Costing: Price Approval → setujui keduanya. Vendor CBD: **Refresh Prices from Master** | Semua baris badge **master**, banner hilang | |
| 10.7 | Publish CBD SMS | Terbit. Baris PO = Actual FOB × 1,25 | |

## 11. Stage melompat (opsional)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 11.1 | Model lain / season lain: revisi Pullover dengan baris tanpa kode → Publish | Bisa terbit (peringatan) | |
| 11.2 | Next stage → pilih **GTM** langsung → Publish | Diblokir seperti SMS (kode wajib mulai SMS, termasuk lompatan) | |

Data uji (model UJI R17, material UJI R17 TOE PUFF) boleh dibiarkan atau di-INACTIVE-kan setelah selesai.

## 12. Selesai

Kirim hasil tabel di atas. Bila semua v, export app (*Product Management R17*) dan simpan sebagai base build berikutnya.
