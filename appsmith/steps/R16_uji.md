# R16: uji lengkap (material tanpa kode di specsheet, thickness baku, Order master option)

> **21 Okt 2026: R16 sudah lolos uji user.** Untuk build terbaru cukup jalankan **bagian 11** (uji tambahan: Material diketik tanpa
> titik tengah `·`). Bagian 0-10 tidak perlu diulang.

Skenario ini ditulis untuk database **tanpa material dan tanpa model** (Master Options, supplier, komponen, user tetap ada).
Semua data uji dibuat dari nol di dalam skenario, memakai baris asli dari file tim material `MATERIAL_CODE_KLASIFIKASI_v8.xlsx`.
Beri tanda di kolom **OK?** (v / x) dan catat apa yang berbeda. Kalau ada yang beda, kirim tangkapan layar dan teks pesannya.

Isi R16:
- **Specsheet boleh disusun tanpa Material Code.** Material yang belum ada di master dibuat dari grid (**+ New material**), thickness baru untuk
  material yang ada cukup diketik `NAMA · THICKNESS`. Sel warna tanpa kode berwarna **kuning**. Specsheet **tidak bisa terbit** selama ada sel kuning.
- **Export Excel** menyorot sel tanpa kode: latar kuning, tulisan `(no code)`, dan satu baris keterangan di header (satu sheet, tanpa tombol baru).
- **Thickness dibakukan** (database dan grid) ke gaya berspasi **sama dengan standar tim material**: `1,2mm` / `1.2 MM` / `1.2mm` semuanya menjadi
  `1.2 MM`; `1.2MMX44"` menjadi `1.2 MM X 44"`; `1.4 - 1.6MM` menjadi `1.4-1.6 MM`; `4MM(110X200CM)` menjadi `4 MM (110 X 200 CM)`.
  Dulu `1.2 MM` dan `1.2MM` dianggap dua thickness berbeda (varian dobel bisa lolos). `SZ` tidak diubah jadi `SIZE` (itu isi, bukan penulisan).
- **Tambahan 20 Okt 2026 (hasil review)**: angka setara satu bentuk, nol di belakang koma dibuang (`2.0 MM` = `2 MM`, `1.50 mm` = `1.5 MM`,
  `.5mm` = `0.5 MM`; jadi `1.0MMX44"` menjadi `1 MM X 44"`), kutip miring dari Word/WhatsApp (`44”`, `44″`) dan `44 inch` / `44 IN` menjadi `44"`,
  rentang dengan satuan di kedua sisi `1.4MM-1.6MM` menjadi `1.4-1.6 MM`. Dari nilai di file tim material hanya 4 yang berubah (yang ber-`.0`).
- **Salah ketik**: nama material atau Material Code yang salah ketik menampilkan **Did you mean**.
- **Master Options: Order = posisi di daftar** (Category, Construction, Gender, Last, Outsole Mold). Tidak bisa kembar dan tidak bisa kosong:
  angka yang sudah dipakai menyisip (yang lain turun satu), kosong = paling akhir (saat edit: tidak pindah). Data lama dinomori ulang
  1..n dengan urutan yang sama. Size tidak berubah (Order = angka ukuran).

Akun: pakai akun uji Anda untuk **Vendor Specsheet** (mis. `spec@uji.test`, pabrik terisi), **Vendor CBD** (`cbd@uji.test`) dan **Brand Viewer**
(`brand@uji.test`). Bahasa tampilan: Inggris.

## 0. Pasang

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 0.1 | DB Tools → jalankan query cek ini (hanya baca): `SELECT (SELECT count(*) FROM material) mat, (SELECT count(*) FROM product_model) model, (SELECT count(*) FROM supplier) sup, (SELECT count(*) FROM component) komp, (SELECT count(*) FROM model_option) opt;` | `mat = 0`, `model = 0`, `sup > 0`, `komp > 0`, `opt > 0`. Bila `sup` atau `komp` = 0: jalankan dulu `sql/R_impor_supplier.sql` dan `sql/R_impor_komponen.sql` | |
| 0.2 | DB Tools → jalankan `sql/R16_baku_thickness.sql` (prepared statements OFF). **Versi 20 Okt 2026: jalankan lagi walau versi sebelumnya sudah pernah dijalankan** (aman diulang) | `R16 terpasang` · `thickness baku: 1.2 MM \| 1 MM X 44" \| 1.4-1.6 MM X 44"` · `varian belum baku: 0` · `Order option kembar / kosong: 0` · `trigger kunci aktif: 2`. Panel NOTICE: `varian dibakukan 0 (dilewati 0) ... sel kuning tersambung 0` (belum ada varian) dan `urutan master option dinomori ulang untuk N kelompok` | |
| 0.3 | Jalankan lagi `sql/R16_baku_thickness.sql` | Aman: hasil sama (idempoten) | |
| 0.4 | DB Tools → jalankan `sql/R_selftest.sql` | **`SELFTEST LOLOS`** (semua dibatalkan, tidak ada data tersimpan) | |
| 0.5 | Import `exports/build_r16.json` **versi 20 Okt 2026** sebagai app baru (app dari build R16 lama, bila ada, jangan dipakai lagi) → cek datasource *Prestasi* tersambung → Deploy → nyalakan akses publik | Nama app *Product Management R16*. Page yang berubah: **Specsheet** dan form di **Master Options** | |
| 0.5b | Di editor app: page **Login** → JSObject **LoginCtrl** → fungsi **onPageLoad** → Settings | *Run on page load* = ON (build ini menyalakannya; export lama Manual). Bila OFF: nyalakan, lalu Deploy | |
| 0.6 | Login Vendor Specsheet, buka tiap menu sekilas | Semua page terbuka tanpa error, bahasa Inggris | |
| 0.7 | Klik **Logout** di header, lalu tombol **Back** browser | Kembali ke Login dengan pesan `You are logged out.`; Back **tidak** masuk lagi ke page tanpa login (build lama: masih masuk) | |
| 0.8 | Login lagi, klik **Change password** di header | Form ganti password tampil (build lama: form login biasa). Klik Cancel = kembali ke Home | |

## 1. Siapkan master (Vendor Specsheet)

Buat material lewat **Master Material → + Add Material** (Category, Name, Mea), lalu buka materialnya → tab **Variants** → **+ Add Variant**
(Material Code, Color, Thickness). Ketik **apa adanya seperti tabel**; kolom "Tersimpan" adalah hasil yang harus Anda lihat di tabel.

| # | Material (Category · Mea) | Kode | Color | Thickness yang diketik | Tersimpan (thickness) | OK? |
|---|---|---|---|---|---|---|
| 1.1 | `HONEYLON MESH` (`fabric` · `me`) | `2003404W01` | `white` | `44"` | `44"` | |
| 1.2 | `TRICOT 28 GR` (`fabric` · `me`) | `201A404B01` | `Black` | `44 "` | `44"`, tanpa kotak konfirmasi merah (build lama keliru meminta konfirmasi di sini) | |
| 1.3 | (material sama) | `201A404W01` | `WHITE` | `44"` | `44"` | |
| 1.4 | `CHEMI SHEET` (`fabric` · `me`) | `2013236N01` | `NATURAL` | `1,8mmx36"` | `1.8 MM X 36"` | |
| 1.5 | `FOAM 50 KG (SH-18)` (`foam` · `me`) | `4005307B01` | `BLACK` | `6mm x 44 inch` | `6 MM X 44"` | |
| 1.6 | (material sama) | `4005306W0F` | `WHITE BLUE` | `4,0 mm X 44”` (kutip miring, salin dari Word) | `4 MM X 44"` | |
| 1.7 | `COMPOUND SHEET ORS-001 HARDNESS 60±3` (`chemical` · `kg`) | `751FK00B01` | `BLACK` | (kosongkan) | `no thickness` | |
| 1.8 | (material sama) | `751FK00W01` | `WHITE` | `.` | `no thickness` | |
| 1.9 | `HEATSEAL SIZE LABEL 104B` (`label` · `prs`) | `5721800WA2` | `WHITE/BLACK` | `-` | `no thickness` | |
| 1.10 | `SM-300 (COOL MELT)` (`chemical` · `kg`) | `754ZK00000` | `NO COLOUR` | (kosongkan) | `no thickness` | |
| 1.11 | `T-160 GRAMASI 160 GSM (BHS)` (`fabric` · `me`) | `20N6404W01` | `WHITE` | `44"` | `44"` | |

Pemeriksaan di tahap ini:

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 1.12 | Lihat nama dan kategori di Master Material | Nama dan Category huruf besar semua (`HONEYLON MESH`, `FABRIC`), Mea `ME` | |
| 1.13 | Material Code diketik huruf kecil (mis. `2003404w01` untuk material baru) | Tersimpan huruf besar | |
| 1.14 | Pada baris 1.11 tambahkan varian kedua: kode `20N6404W10`, color `WHITE`, thickness `44"` | **Ditolak**: `Variant WHITE · 44" already exists in this material (code 20N6404W01). If ERP really has another code, make the color name differ as in ERP (e.g. WHITE C).` (ini salah satu dari 4 pasangan kode bentrok di file tim) | |
| 1.15 | Ulangi 1.14 dengan color `WHITE B` | Diterima (dua kode berbeda karena warnanya dibedakan) | |
| 1.16 | Tambah varian HONEYLON MESH: kode `2003404BLK`, `BLACK`, thickness `58"` | Kotak merah `Thickness code 404 is already recorded as 44" (code ...), not 58". Check the Material Code in ERP.` dengan centang konfirmasi. Simpan tanpa centang: ditolak. Centang konfirmasi lalu simpan: diterima (kode thickness 404 sudah berarti `44"`, di sini sengaja dilanggar untuk menguji konfirmasi) | |
| 1.16b | Tambah varian HONEYLON MESH: kode `2003404GRY`, `GREY`, thickness `44”` (kutip miring) | Tidak ada kotak merah (`44”` = `44"`; pengecualian `58"` di 1.16 tidak mengubah arti kode 404), tersimpan `44"`. Butuh `R16_baku_thickness.sql` versi 20 Okt sore (T86) | |
| 1.17 | Tambah varian TRICOT: kode `201A404W01` (kode sudah dipakai) | Ditolak: kode sudah dipakai | |
| 1.18 | Tambah varian dengan kode 9 karakter (mis. `201A404NV`) di TRICOT, color `NAVY`, thickness `44"` | Kotak kuning info "bukan 10 karakter" tapi tetap bisa disimpan; **batalkan** (jangan simpan) supaya NAVY tetap tanpa kode untuk tahap 3 | |
| 1.19 | Tambah material `honeylon  mesh` (spasi ganda, huruf kecil) dengan Category `fabric` dan Mea **`me`** (Mea lain = material lain yang sah, lalu tahap 3 akan menampilkan `Several materials are named ...`) | Ditolak: `Material "HONEYLON MESH" (ME) already exists in this factory...` | |
| 1.20 | Di **+ Add Material** ketik `honeylon` di kolom Name | Daftar nama mirip menampilkan `HONEYLON MESH` (di halaman ini hanya nama yang memuat teks yang diketik; salah ketik seperti `honylon` baru dikenali di modal **+ New material** pada tahap 3) | |

## 2. Model, season, article, revisi

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 2.1 | **Model List → + Add Model**: Model Name `uji r16 runner`, Category `RUNNING` (atau yang ada), Gender, Construction, Last `PRL-014`, Outsole Mould (salah satu), ukuran 40, Sample Size 40 | Model tersimpan, nama huruf besar | |
| 2.2 | Buka model → **+ New Season** `FH27` → **+ Article**: `R16-A1` colorway `BLACK`, `R16-A2` `WHITE`, `R16-A3` `NAVY` | 3 article | |
| 2.3 | **Open Specsheet →** → **+ Create Revision** (First stage default, mode kosong) | Draft revisi baru, grid kosong: `No BOM lines yet` | |
| 2.4 | Lihat bar atas grid | Tombol **+ New material** dan **+ New supplier** tampil (build lama keliru: **+ New material** tidak pernah tampil). Tidak ada tombol Code request | |

## 3. Menyusun specsheet (inti R16)

Setiap baris dibuat di baris **+ Add** paling bawah: kolom Component, Material, Supplier, lalu **+ Add**; warna diisi di sel article.
Komponen dipilih dari daftar (ketik nomor atau nama). Supplier cukup diketik sebagian nama dan dipilih.

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 3.1 | Komponen `300` (VAMP), Material ketik `tricot 28 gr · 44 "` (huruf kecil, spasi), supplier `BUKIT HIJAU SENTOSA,PD` → **+ Add** | Baris dibuat: `TRICOT 28 GR`, Thickness `44"`, UoM `ME` | |
| 3.2 | Isi sel R16-A1 = `black`, R16-A2 = `white` | Tersimpan `BLACK` dan `WHITE`, di bawahnya tampil kode `201A404B01` dan `201A404W01` | |
| 3.3 | Isi sel R16-A3 = `Navy` | `NAVY`, sel **kuning** dengan tulisan `no Material Code` dan tombol **Register** | |
| 3.4 | Status bar | `... 1 yellow cells` | |
| 3.5 | Komponen `310`, Material ketik **kode** `2003404W01` (kosongkan supplier), Tab | Material berubah menjadi `HONEYLON MESH · 44"`, muncul centang `Fill color WHITE into all articles` | |
| 3.6 | Biarkan centang, isi supplier `BUKIT HIJAU SENTOSA,PD`, **+ Add** | Baris dibuat, sel semua article terisi `WHITE` dengan kode `2003404W01` | |
| 3.7 | Komponen `4080`, Material ketik `foam 50 kg (sh-18) · 6mm x 44 "`, supplier `SERIM INDONESIA,PT`, **+ Add**, isi A1 `BLACK` | Baris dengan thickness `6 MM X 44"` (bukan "new", sudah ada); A1 menampilkan kode `4005307B01` | |
| 3.8 | Komponen `100`, Material ketik **nama saja** `compound sheet ors-001 hardness 60±3`, supplier `KUMKANG TECH INDONESIA,PT`, isi A1 `BLACK`, A2 `WHITE` | Thickness `-` (tanpa thickness); kode `751FK00B01` dan `751FK00W01` tampil | |
| 3.9 | Komponen `270`, Material `SM-300 (COOL MELT)`, supplier `GRAND CHEMICAL INDONESIA`; isi A1 = `no colour`, A2 dan A3 dikosongkan | A1 `NO COLOUR` dengan kode `754ZK00000`. A2 dan A3 kosong = tidak dipakai (tidak kuning) | |
| 3.10 | Komponen `40`, Material ketik `honeylon mesh · 1,5 mm`, Tab | Kolom Thickness `1.5 MM (new)` (tooltip: new thickness, no variants yet) | |
| 3.11 | Supplier `BUKIT HIJAU SENTOSA,PD`, **+ Add**, isi A1 = `white` | Baris dibuat, sel A1 **kuning** (belum ada varian 1.5 MM) | |
| 3.12 | Komponen `50`, Material `HONEYLON MESH · 1.5MM` (penulisan lain dari 3.10), supplier sama, **+ Add** | Thickness tetap `1.5 MM` (satu thickness, bukan dua). Baris dibuat; hapus baris ini setelah diperiksa agar jumlah kuning tidak bertambah | |
| 3.13 | Komponen `40` + material `HONEYLON MESH · 1.50 mm` (komponen dan material sama dengan 3.11, ditulis `1.50`) | Ditolak: `Component 40 with this material (same thickness) is already in this revision.` (`1.50` = `1.5`) | |
| 3.13b | Di baris **+ Add** ketik Material `honeylon mesh · 44 inch`, Tab | Kolom Thickness `44"` **tanpa** `(new)` (sama dengan varian yang sudah ada). Ulangi dengan `honeylon mesh · 44”` (kutip miring): sama. Kosongkan lagi | |
| 3.13c | Ketik `honeylon mesh · 1.4mm-1.6mm`, Tab | Thickness `1.4-1.6 MM (new)`. Kosongkan lagi (tidak perlu ditambahkan) | |
| 3.14 | Komponen `330`, Material ketik `kain baru spacer 3d · 4,0 mm`, supplier `SUMBER KREASI MANDIRI, PT`, tekan **Enter** | Pesan merah di atas: `Material "kain baru spacer 3d · 4,0 mm" is not in this factory's Master Material (or INACTIVE). Check the spelling, or click "+ New material" to add it.` (tanpa saran karena tidak ada yang mirip). **Di bawah kolom Material baris itu** muncul `Not in Master Material.` + tombol **+ New material** | |
| 3.15 | Klik **+ New material** di baris itu | Modal **Add Material**, kolom Name terisi `kain baru spacer 3d` (tanpa thickness). Kolom Category / Mea menawarkan isian yang sudah ada (`FABRIC`, `ME`, ...) | |
| 3.16 | Hapus nama lalu ketik `honylon` | Setelah jeda sebentar daftar "similar option exists" menampilkan `HONEYLON MESH` (bantuan, boleh diabaikan) | |
| 3.17 | Kembalikan nama `KAIN BARU SPACER 3D`, Category `fabric`, Mea `me`, **Save** | Alert `Material KAIN BARU SPACER 3D added.` Modal tertutup dan **baris langsung ditambahkan otomatis** (tanpa Enter lagi): komponen 330, `KAIN BARU SPACER 3D`, Thickness `4 MM (new)`, supplier tadi | |
| 3.18 | Isi A1 baris itu = `cream` | Sel **kuning** (`4,0 mm` dibakukan jadi `4 MM`) | |
| 3.18b | Di baris **+ Add** ketik Material `leather kd baru`, lalu ubah isian Material lagi sebelum klik tombolnya | Tombol **+ New material** di baris hilang begitu isian diubah (pesan atas tetap sampai aksi berikutnya). Kosongkan baris | |
| 3.18c | Pada baris komponen 270 (`SM-300 (COOL MELT)`) ketik di sel Material `kain uji ganti`, Tab | Pesan merah + tombol **+ New material** di sel Material baris itu. Klik → modal Name `kain uji ganti`, Category `fabric`, Mea `kg`, **Save** → material baris itu langsung **diganti** (tombol **Undo replace** muncul). Klik **Undo replace** dua kali: kembali ke SM-300 | |
| 3.18d | Klik **+ Sub** di salah satu baris: nama `uji sub`, Material `busa uji sub · 3mm`, klik **Add** | Tombol **+ New material** di sel Material form sub. Klik → **Save** (Category `foam`, Mea `me`) → subkomponen langsung ditambahkan dengan Thickness `3 MM (new)`. Hapus subkomponen itu setelah diperiksa | |
| 3.18e | Klik **Cancel** di modal **+ New material** (dari tombol baris mana pun) | Tidak ada baris ditambahkan / diganti; isian baris tetap | |
| 3.19 | Status bar | `... 3 yellow cells` (NAVY tricot, WHITE honeylon 1.5 MM, CREAM spacer 4 MM) | |
| 3.20 | Di baris komponen 270 ganti kolom Material dengan `sm-300 cool melt` (kurung hilang), Tab / Enter | Pesan `... not in this factory's Master Material ... Did you mean: SM-300 (COOL MELT)?`, nilai lama dikembalikan | |
| 3.21 | Di baris **+ Add** ketik Material `2003404W0l` (huruf L kecil di akhir), lalu **+ Add** | Pesan `Did you mean: 2003404W01 (HONEYLON MESH · 44" · WHITE)?` | |
| 3.22 | Ketik `honeylon mesh ·` (titik tengah tanpa thickness) lalu **+ Add** | Pesan `Material ... has several thicknesses. Pick from the list ...`, **bukan** baris tanpa thickness | |
| 3.23 | Kosongkan baris **+ Add** lalu **+ Add** | Pesan wajib isi, tidak ada baris dibuat | |
| 3.24 | Isi komponen `20`, material `chemi sheet`, supplier `SUMBER KREASI MANDIRI, PT`, klik **+ Add** dua kali cepat | Hanya **satu** baris dibuat (aksi diantre, yang kedua ditolak sebagai dobel), tidak ada error aneh | |
| 3.25 | Ganti material sebuah baris lewat kolom Material (mis. baris komponen 100 diganti ke `chemi sheet`) | Baris menjadi material baru; sel warna lama terhubung ulang bila varian ada, kuning bila tidak ada | |
| 3.26 | Pada baris tadi klik **Undo replace** (dua kali: `Sure?`) | Baris kembali ke COMPOUND SHEET dan warnanya kembali seperti 3.8 | |
| 3.27 | Buat material `HONEYLON MESH` dengan Mea `yd` (**+ Add Material**), lalu di baris **+ Add** ketik `honeylon mesh · 1.5 mm` | Pesan `Several materials are named "honeylon mesh" (different UoM). Pick one from the list.` Setelah itu **Edit Material** yang `YD` menjadi INACTIVE dan ulangi: kini dikenali `1.5 MM (new)` pada material `ME` | |

## 4. Export Excel (revisi draft dengan sel kuning)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 4.1 | Klik **Export Excel** | Terunduh `Specsheet_UJI-R16-RUNNER_FH27_..._DRAFT.xlsx`, satu sheet | |
| 4.2 | Buka sel yang punya kode | Warna dan kode di bawahnya (mis. `WHITE` / `2003404W01`), tanpa latar | |
| 4.3 | Buka sel yang belum punya kode | Latar **kuning**, isi `NAVY` lalu baris baru `(no code)`; begitu juga `WHITE` (1.5 MM) dan `CREAM` | |
| 4.4 | Lihat blok header kanan (di bawah baris stage, baris ke-7) | `YELLOW = no Material Code yet (3 cell(s)). Ask the Material team for these codes.` | |
| 4.5 | Kolom THICKNESS | Berspasi: `44"`, `1.5 MM`, `4 MM`, `6 MM X 44"`; kosong untuk material tanpa thickness | |
| 4.6 | Jumlah sel kuning di file | Sama dengan layar (3) | |

## 5. Kode datang belakangan, lalu terbit

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 5.1 | Klik **Publish...**, isi kategori perubahan | Ditolak: `3 color cell(s) have no Material Code (yellow cells): ...` dengan daftar NAVY tricot, WHITE honeylon 1.5 MM, CREAM spacer 4 MM | |
| 5.2 | Klik **Register** di sel NAVY tricot | Modal Register: material, thickness, warna terkunci. Ketik kode `201A404NVY` | |
| 5.3 | Lihat usulan kode di modal | Muncul usulan bagian kode (awalan `201A`, kode thickness `404`) dari varian yang sudah ada | |
| 5.4 | Simpan | Alert `Variant 201A404NVY registered. Cell NAVY linked automatically.` Sel menjadi normal dan menampilkan kode; sisa 2 kuning | |
| 5.5 | Register sel WHITE honeylon 1.5 MM dengan kode `2003015W01` | Sel tersambung. Info "kode thickness 015 baru" boleh muncul | |
| 5.6 | Register sel CREAM spacer 4 MM dengan kode `9X0A040CRM` | Sel tersambung, tidak ada sel kuning tersisa | |
| 5.7 | Status bar | Tidak lagi menyebut yellow cells | |
| 5.8 | **Export Excel** lagi | Tidak ada latar kuning, tidak ada `(no code)`, baris keterangan hilang | |
| 5.9 | **Publish...** (isi kategori dan alasan bila diminta) | Berhasil: status PUBLISHED, grid terkunci | |
| 5.10 | Material Detail → varian `201A404NVY` → Edit, ubah thickness atau kode | Ditolak: `Variant 201A404NVY is used in published documents. Its Material Code, color, and thickness cannot be changed. Set it INACTIVE and register a new variant.` | |
| 5.11 | Ubah status varian itu menjadi INACTIVE, lalu kembalikan ACTIVE | Keduanya diperbolehkan | |

## 6. Revisi berikutnya (kuning muncul lagi)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 6.1 | **+ Create Revision**: next stage (Preview) dari revisi terbit | Draft baru berisi semua baris dan warna yang sama, tidak ada sel kuning | |
| 6.2 | Tambah baris baru: komponen `60`, material `honeylon mesh · 2 mm`, A1 `white` | `2 MM (new)`, sel kuning, **Publish** ditolak | |
| 6.3 | Hapus baris itu | Kuning hilang, **Publish** boleh | |
| 6.4 | Ganti material baris tricot ke `tricot 28 gr · 54"` | Thickness `54" (new)`, semua selnya kuning (BLACK, WHITE, NAVY) | |
| 6.5 | Batalkan penggantian (**Undo replace**) | Kembali ke `44"`, kuning hilang | |
| 6.6 | **Delete Draft** | Draft hilang, revisi terbit tetap | |

## 7. CBD dan peran lain

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 7.1 | **Open CBD →**, buat CBD revisi baru untuk article R16-A1 | Baris CBD membawa Material Code dan thickness berspasi (`6 MM X 44"`, `1.5 MM`), tidak ada konsep sel kuning. Setelah CBD terbit, chip article `PUBLISHED ...` (build lama: `TERBIT ...`) | |
| 7.2 | **Export Excel** CBD | Thickness tampil berspasi, kode ada di semua baris | |
| 7.2b | Login Brand Viewer, buka CBD terbit tadi → tabel **Selling price simulation**: isi Margin `20`, lalu ubah Selling price yang muncul (mis. angka terakhir) | Selling price tampil tanpa titik ribuan (mis. `319730`); setelah diubah Margin ikut terhitung (build lama: Margin kosong) | |
| 7.3 | Login Vendor CBD, buka Specsheet model yang sama | Mode baca saja: tidak ada tombol **+ New material** dan **+ New supplier**, sel tidak bisa diedit | |
| 7.4 | Login Brand Viewer | Hanya revisi terbit yang terlihat; tidak ada tombol tambah | |

## 8. Master Options: Order = posisi

Mulai dari kondisi setelah 0.2 (data lama sudah dinomori ulang). Pakai **Master Options**, pilih jenis di dropdown atas. Catat urutan awal tiap jenis.

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 8.1 | Pilih **Last (per factory)** | Kolom No berurutan 1, 2, 3 ... tanpa angka kembar dan tanpa kosong; dua "10" lama (bila ada) kini berurutan, nama lebih awal di atas | |
| 8.2 | **+ Add Option**: `PRL-050`, Order dikosongkan | Masuk paling bawah, No = jumlah baris | |
| 8.3 | **+ Add Option**: `PRL-051`, Order `1` | Tampil paling atas (No 1); semua yang lain turun satu | |
| 8.4 | **+ Add Option**: `PRL-052`, Order `5` padahal 5 sudah dipakai | `PRL-052` di No 5; yang tadinya 5 menjadi 6 dan seterusnya; tidak ada dua baris No 5 | |
| 8.5 | **+ Add Option**: `PRL-053`, Order `999` | Paling bawah, No = jumlah baris (bukan 999) | |
| 8.6 | **Edit** `PRL-050`: kosongkan Order, Save | Posisinya tidak berubah | |
| 8.7 | **Edit** `PRL-050`: Order `2` | Pindah ke No 2, yang lain menyesuaikan | |
| 8.7b | **Edit** nilai di No 1: Order `4` (pindah ke **bawah**) | Nilai itu tepat di No 4; yang tadinya No 2, 3, 4 naik menjadi 1, 2, 3 (build lama keliru: berhenti di No 3) | |
| 8.8 | **Edit** satu nilai: ubah status ke INACTIVE | Posisi tetap, urutan tidak berubah (baris tetap di tempatnya, Status INACTIVE; build lama memindahkannya ke paling bawah) | |
| 8.9 | **Edit**: isi Order dengan angka yang sama dengan posisinya sekarang | Tidak ada perubahan urutan | |
| 8.10 | Ulangi 8.2, 8.3, 8.4 untuk **Category**, **Construction**, **Gender**, **Outsole Mold** (nama uji `UJI A`, `UJI B`, `UJI C`) | Perilaku sama; Category / Construction / Gender dipakai bersama semua pabrik (kolom Factory `Shared`, build lama `Bersama`), Last dan Outsole Mold per pabrik | |
| 8.11 | Pilih **Size**, tambah ukuran yang belum ada | Kolom Order tidak tampil di form; urutan menurut angka ukuran | |
| 8.12 | Tambah nilai yang sama dengan yang ada (huruf beda), mis. `prl-051` | Ditolak: `Last "PRL-051" already exists.` | |
| 8.13 | Login pabrik lain (bila ada akunnya), buka Last | Hanya Last pabrik itu; urutan pabrik lain tidak terpengaruh oleh 8.2 sampai 8.9 | |
| 8.14 | Model Detail → **Edit Model**: dropdown Last dan Category | Mengikuti urutan baru | |
| 8.15 | Nilai uji `UJI ...` dan `PRL-05x`: set INACTIVE atau biarkan | | |

## 9. Perilaku manusia (acak dan tidak rapi)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 9.1 | Ketik material dengan jeda lama (3 detik antar huruf), lalu Tab | Hasil sama dengan mengetik cepat; tidak ada kedipan atau nilai hilang | |
| 9.2 | Ketik cepat, tekan Enter langsung | Mengikuti aturan yang sama (nilai yang sudah dikenali dipakai) | |
| 9.3 | Ketik, hapus sebagian, ketik lagi, **+ Add** | Isian terakhir yang dipakai; tidak ada baris ganda | |
| 9.4 | Salin nama dari Excel (spasi di awal / akhir, huruf campur), tempel di Material | Dibersihkan dan dikenali seperti 3.1 | |
| 9.5 | Tempel `HONEYLON MESH - 1.5 MM` (pemisah `-`, bukan titik tengah) | **Diubah 21 Okt 2026, lihat bagian 11**: kini dibaca sebagai `HONEYLON MESH · 1.5 MM` (bagian depan = nama material yang ada, sisanya thickness) | |
| 9.6 | Isi sebagian baris **+ Add**, klik di tempat lain / pindah tab browser / kembali | Isian tetap ada | |
| 9.7 | Isi sebagian lalu muat ulang halaman (F5) | Isian hilang (belum disimpan), data yang sudah disimpan tetap | |
| 9.8 | Pindah revisi / model saat ada pesan error di bar | Pesan tidak menempel ke revisi lain | |
| 9.9 | Buka dua tab, kedua-duanya membuat material `UJI GANDA` | Yang kedua ditolak `already exists`; tidak ada dobel | |
| 9.10 | Buka dua tab, di keduanya menambah Last dengan Order `1` bergantian | Tidak ada Order kembar (periksa dengan 10.2) | |
| 9.11 | Tekan Esc di sel yang sedang diketik | Perubahan yang belum disimpan dibatalkan | |
| 9.12 | Modal **+ New material**: klik di luar modal | Modal tidak tertutup (harus Cancel / Save) | |
| 9.13 | Nama material dengan karakter khusus (`±`, `%`, `"`, `/`) | Tersimpan dan tampil benar di grid dan Excel | |
| 9.14 | Klik **Save** dua kali cepat di modal **+ New material** | Hanya satu material dibuat; tombol menjadi `Saving…` | |

## 10. Cek akhir di database (hanya baca)

| # | Query (DB Tools) | Hasil yang diharapkan | OK? |
|---|---|---|---|
| 10.1 | `SELECT thickness, count(*) FROM material_variant WHERE thickness IS DISTINCT FROM fn_clean_thickness(thickness) GROUP BY 1;` | Tidak ada baris | |
| 10.2 | `SELECT kind, factory_id, sort_order, count(*) FROM model_option WHERE kind <> 'UKURAN' GROUP BY 1, 2, 3 HAVING count(*) > 1 OR sort_order IS NULL;` | Tidak ada baris | |
| 10.3 | `SELECT m.name, v.thickness, v.color, v.code FROM material_variant v JOIN material m ON m.id = v.material_id ORDER BY 1, 2, 3;` | Semua thickness berspasi baku, warna dan kode huruf besar | |
| 10.4 | `SELECT l.thickness, count(*) FROM bom_line l WHERE l.thickness IS DISTINCT FROM fn_clean_thickness(l.thickness) GROUP BY 1;` | Tidak ada baris | |
| 10.5 | `SELECT kind, factory_id, count(*), min(sort_order), max(sort_order) FROM model_option WHERE kind <> 'UKURAN' GROUP BY kind, factory_id;` | `min = 1` dan `max = count` untuk tiap kelompok | |

## 11. 🆕 Uji tambahan 21 Okt 2026: Material tanpa titik tengah `·` (hanya bagian ini yang perlu diuji)

Titik tengah `·` tidak ada di keyboard. Sekarang Material juga boleh diketik dengan pemisah `.` `-` `/` `|` `,` atau tanpa pemisah:
bagian depan harus **persis nama material yang sudah ada** (yang terpanjang dipakai) dan sisanya **mirip thickness** (dengan pemisah:
berisi angka; tanpa pemisah: angka + satuan `MM` / `CM` / `"` / `INCH`). Setelah Tab / Enter, isian ditulis ulang menjadi `NAMA · THICKNESS`.
Nama yang cocok persis selalu menang (`SM-300 (COOL MELT)` tidak dipecah).

Persiapan: **import `exports/build_r16.json` versi 21 Okt 2026 sebagai app baru** (SQL tidak perlu dijalankan lagi). Login Vendor Specsheet,
buka Specsheet `UJI R16 RUNNER` FH27, **+ Create Revision** (Next revision) supaya ada draft. Data master dari uji sebelumnya dipakai.
Untuk setiap langkah, ketik di kolom Material baris **+ Add**, lalu tekan **Tab** (kecuali disebut lain).

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 11.1 | Material `honeylon mesh . 1,5 mm` | Isian berubah menjadi `HONEYLON MESH · 1.5 MM`, Thickness `1.5 MM` (tanpa `(new)`: varian 1.5 MM sudah didaftarkan di 5.5) | |
| 11.2 | Komponen `60`, supplier `BUKIT HIJAU SENTOSA,PD`, Material `honeylon mesh - 2,0mm`, **+ Add** | Baris dibuat: `HONEYLON MESH`, Thickness `2 MM` (thickness baru, sel nanti kuning) | |
| 11.3 | Material `honeylon mesh 44 inch` (tanpa pemisah) | `HONEYLON MESH · 44"`, Thickness `44"` (tanpa `(new)`). Kosongkan | |
| 11.4 | Material `honeylon mesh / 44”` (kutip miring) | Sama dengan 11.3. Kosongkan | |
| 11.5 | Material `honeylon mesh blue`, Enter | **Tidak** dipecah (`blue` bukan thickness): pesan material tidak ditemukan + tombol **+ New material** di baris. Kosongkan | |
| 11.6 | Material `sm-300 (cool melt)` | Dikenali utuh sebagai `SM-300 (COOL MELT)` (nama berisi `-` dan kurung tidak dipecah). Kosongkan | |
| 11.7 | Material `foam 50 kg (sh-18) - 6mm x 44 inch` | `FOAM 50 KG (SH-18) · 6 MM X 44"`, Thickness `6 MM X 44"` (tanpa `(new)`). Kosongkan | |
| 11.8 | Komponen `70`, supplier `SUMBER KREASI MANDIRI, PT`, Material `kain uji titik . 2,5 mm` (material baru), Enter | Pesan tidak ditemukan + tombol **+ New material** di baris | |
| 11.9 | Klik **+ New material** di baris itu | Modal: Name `kain uji titik` (**tanpa** `2,5 mm`) | |
| 11.10 | Category `fabric`, Mea `me`, **Save** | Baris langsung ditambahkan: `KAIN UJI TITIK`, Thickness `2.5 MM (new)` | |
| 11.11 | Di baris komponen 300 (TRICOT) ketik di sel Material `tricot 28 gr - 54"`, Tab | Material baris diganti ke thickness `54"` (sel warna kuning, tombol **Undo replace**). Klik **Undo replace** dua kali: kembali ke `44"` | |
| 11.12 | **Delete Draft** | Draft uji hilang, revisi terbit tetap | |

## Catatan

- Kode **tidak** dibuat app. Kode untuk NAVY, 1.5 MM, dan 4 MM di atas hanyalah kode uji; kode asli dari tim material.
- Sel kuning memblokir **terbit** saja. Menyusun, mengubah, dan mengekspor draft tetap bebas.
- Nama material, kategori, warna, dan kode otomatis huruf besar sejak versi lama (jadi `honeylon` tersimpan `HONEYLON`).
- Typo di **nama** hanya terdeteksi dari nama yang ada di master pabrik Anda.
- Daftar usulan kode, tombol Code request, dan sheet kedua sengaja tidak ada: yang penting jelas sel mana yang belum punya kode.
- Impor 845 kode ERP, impor balik Excel kode dari tim material, dan Gabungkan varian dobel tidak termasuk di R16.
- Empat pasang kode bentrok di file tim (`W01`/`W10`, `P88`/`P9F`, dan INJECTION PHYLON `700E`/`940K`) ditolak oleh aturan satu kode per
  material + thickness + warna; jalan keluarnya membedakan nama warna sesuai ERP (langkah 1.14 dan 1.15), atau tim material memutuskan.
- Bila pada tahap 5 modal Register tidak menampilkan usulan kode, itu bukan kegagalan: usulan hanya muncul bila ada varian lain sebagai acuan.
