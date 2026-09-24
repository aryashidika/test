# Sistem Specsheet & CBD — Mockup Lokal (Web)

Implementasi PRD `PRD_Specsheet_CBD_ClaudeCode.md` sebagai aplikasi web lokal:
**Python (Flask) + SQLite (database file lokal) + htmx**. Tidak perlu instalasi
database eksternal maupun internet — semua berjalan dari satu file
`data/app.db` di folder ini, dan server Flask hanya mendengarkan di
`127.0.0.1` (tidak diekspos ke jaringan).

> Versi awal proyek ini dibangun dengan Tkinter (desktop). Setelah dicoba,
> UI Tkinter dirasa kaku, sehingga proyek dipindah sepenuhnya ke web
> (Flask + htmx) agar terasa lebih fluid — layout, tema, dan alur kerja tetap
> sama, hanya lapisan tampilannya yang diganti. Business logic (`app/domain/`)
> tidak berubah.

## Penyesuaian dari PRD asli

PRD asli menspesifikasikan Next.js/PostgreSQL/Prisma/Auth.js. Atas permintaan,
versi ini dibangun sebagai aplikasi web lokal-only, dengan beberapa penyesuaian
lanjutan setelah review terhadap contoh specsheet nyata (PDF referensi):

- **Tanpa login berpassword.** Saat masuk, user memilih role dari dropdown
  (tanpa password) — cocok untuk kebutuhan mockup/presentasi.
- **Single-user, satu komputer.** Satu file SQLite lokal, tidak ada penanganan
  concurrent-write untuk banyak user berbagi file yang sama.
- **Menu utama disaring per role:** "Beranda", "Master Data", "Model",
  "Specsheet", "CBD", dan "Admin" — tiap role hanya melihat menu yang boleh diaksesnya (lihat "Hak
  akses per role" di bawah).
- **Hak akses per role ditegakkan di server**, bukan hanya dengan
  menyembunyikan tombol: setiap route aksi memakai `require_permission(...)` dan
  setiap menu memakai `guard_blueprint(...)` (`app/web/auth.py`), dengan aturan
  di `app/domain/permissions.py`. Request dari role yang tidak berhak ditolak
  403.
- **Supplier dipilih per baris BOM, link material–supplier terbentuk otomatis.**
  Supplier dipilih langsung per baris BOM di specsheet ("Source of Material").
  Baris CBD SELALU mengikuti `bom_line.supplier_id` (bukan
  `MaterialSupplier.isDefault` seperti di PRD asli) — supplier tidak bisa
  di-override di CBD, kalau salah/kosong harus diperbaiki di specsheet. Setiap
  kombinasi material + supplier baru yang dipakai di BOM otomatis tercatat di
  tabel `material_supplier` (status `PROPOSED`, langsung bisa dipakai, di-approve
  Master Admin); satu kode material bisa punya banyak supplier. Lihat "Master
  harga" di bawah.
- **Master harga (tambahan di luar PRD).** Harga material disimpan di Master
  Material, per supplier, bukan diketik ulang di setiap CBD:
  - `material_supplier` (dimiliki tim specsheet): supplier resmi sebuah material,
    kode material versi supplier, dan satu supplier utama (otomatis terisi di BOM).
  - `material_price` (dimiliki tim CBD, bisa juga diisi/dikoreksi Master Admin):
    harga per link material–supplier,
    **berbasis periode** — harga baru menutup harga lama (`valid_to`), tidak
    menimpanya, jadi riwayat utuh. Warna kosong = harga semua warna; harga dengan
    warna hanya untuk warna itu dan selalu menang atas harga semua warna.
  - CBD mengambil harga dari master saat generate/refresh (material + supplier +
    warna → material + supplier semua warna, tidak ada fallback lintas supplier)
    dan menyimpannya sebagai **snapshot** (`cbd_line.price_source='MASTER'` +
    `material_price_id`) — CBD terbit tidak ikut berubah saat harga master berubah.
  - **Metode harga per material** (`material.price_method`, diatur tim CBD / Master Admin di
    detail material): **Katalog** (default — harga dari master harga) atau
    **Quotation per CBD** untuk material proses (printing, laminating, HF
    welding, upper molded, coating) yang harganya beda tiap desain/warna,
    sehingga tidak masuk akal disimpan di master. Material berkategori
    "Proses ..." otomatis Quotation (seed & migrasi).
  - **Tidak ada input harga master dari grid CBD.** Input harga di CBD hanya:
    harga **quotation** (material Quotation: harga + currency saja, tanpa
    alasan, `price_source='QUOTATION'`), dan **override** (material Katalog:
    harga sekali pakai, alasan wajib, `price_source='OVERRIDE'` — form-nya di
    popup kecil "Override…" supaya sel harga tetap ringkas). Keduanya ikut
    ter-copy ke revisi berikutnya article yang sama maupun lewat "Copy dari
    Article Lain".
  - **No. quotation tidak diinput lagi** (baik di CBD maupun di Master Material
    › Harga). Kolom `price_reference` / `material_price.reference` tetap ada di
    database, jadi data lama tidak hilang.
  - **Baris tanpa harga boleh terbit** (cost 0), tanpa perlu ditandai — mis.
    beberapa baris proses yang harganya diwakili satu baris proses saja.
  - CBD DRAFT yang harga masternya berubah/baru tersedia menampilkan tombol
    **"Refresh Harga dari Master"**, dan publish ditolak sampai di-refresh (sama
    seperti aturan specsheet usang).
  - Penandaan sinkronisasi (PRD 6.6) sekarang juga menandai CBD terbit
    `NEEDS_REVISION` bila supplier atau warna baris berubah di specsheet (keduanya
    menentukan harga), walau lineKey-nya sama.
  - Migrasi database lama: link material–supplier dibentuk dari BOM yang sudah
    ada (langsung `APPROVED`); harga yang dulu diketik manual di CBD dianggap
    override dengan alasan "Diinput manual sebelum ada master harga".
- **Input ketik + saran di grid BOM** (bukan dropdown): komponen yang cocok
  dengan master (label "10 - Vamp", nomor, atau nama) jadi baris komponen
  master, yang tidak cocok jadi komponen lokal dan kolom No. wajib diisi (aturan
  nomor lokal tetap). Material wajib ada di master (ketik kode atau nama).
  Supplier wajib ada di Master Supplier; saran supplier untuk material itu
  tampil paling atas. Saran warna = semua warna yang pernah diinput di specsheet
  mana pun pada season yang sama.
- **Supplier master data hanya berisi nama + currency default** (tanpa asal).
- **Factory pada Model adalah teks bebas** (bukan master data/vendor terpisah).
- **Model punya field lengkap sesuai alur kerja nyata:** nama, kategori, outsole
  mold, last no., construction, size range, sample size, dan factory. Satu Model
  bisa hidup di lebih dari satu season; colorway/SKU (Article) ada per season.
- **Season berformat `SS[tahun]` / `FH[tahun]`** (mis. `SS26`, `FH26`); SS selalu
  diurutkan sebelum FH pada tahun yang sama.
- **Grid BOM meniru contoh PDF referensi:** satu kolom per article/colorway
  langsung di grid (tambah lewat "+ Article" di toolbar BOM, drop lewat tombol
  "×" di header kolom) — bukan tab/daftar terpisah. Kolom "Remarks" (dulu
  "Process") dan "Source of Material" (Supplier) ada per baris.
- **Pengisian komponen digabung jadi satu alur ("+ Komponen"):** pilih dari
  dropdown master untuk komponen global, atau pilih "+ Komponen Baru" untuk
  ketik nomor manual yang belum ada di master (komponen lokal) — tidak ada lagi
  pemisahan tombol/istilah "master" vs "lokal".
- **Tidak ada konsep sub-komponen di master Komponen** — baris tambahan
  (proses/dekorasi/varian material) di specsheet selalu diketik bebas ("+
  Subkomponen"), tidak perlu terdaftar di master. Nomor tampilnya otomatis
  mengikuti format `[nomor komponen induk]-[urutan subkomponen]`, mis. `10-1`,
  `10-2`.
- **Baris specsheet & CBD selalu urut menurut nomor komponen** (master maupun
  lokal), bukan urutan input — baris baru mis. komponen 15 langsung masuk di
  antara 10 dan 20, subkomponen tetap tepat di bawah induknya; nomor sama
  (komponen sama, material beda) urut sesuai waktu input. Berlaku juga untuk
  data lama, cetak, dan Excel.
- **Stage awal specsheet bisa dipilih**, bukan selalu `PULL` — specsheet tidak
  selalu mulai dari tahap Pullover (mis. article yang baru masuk di tahap SMS
  atau GTM). Berlaku untuk "Mulai Baru (Kosong)", carryover, dan "Copy dari
  Model Lain"; default tetap `PULL` kalau tidak dipilih.
- **Usage tidak diinput langsung** — Usage = 1 / Yield (Yield = jumlah pasang
  yang dihasilkan satu unit material). Pengguna hanya mengisi Yield; Usage
  selalu turunan dan tampil read-only.
- **Loss % default `0.00`** saat baris CBD baru dibuat (bisa diedit), bukan
  kosong.
- **Tidak ada aksi "Batalkan baris" di CBD.** Status baris CBD murni mengikuti
  specsheet: `ACTIVE` selama komponennya masih dipakai, `MISSING_IN_SPEC` kalau
  sudah tidak ada lagi di specsheet. Status `CANCELLED` di PRD 6.4 langkah 4
  dengan demikian tidak pernah terjadi dan tidak diimplementasikan di app ini.
- **Tidak ada Aturan Transformasi.** PRD 6.4/5.4 punya tahap EXCLUDE (buang
  komponen dari CBD) dan MERGE (gabung beberapa komponen master jadi satu baris
  CBD) yang dikelola di master data — dihapus sepenuhnya atas permintaan
  lanjutan. Generate/merge CBD sekarang murni 1:1: setiap baris BOM `isUsed`
  di specsheet selalu terrefleksi apa adanya sebagai satu baris CBD, tanpa
  pengecualian atau penggabungan komponen.
- **Specsheet wajib punya minimal satu Article aktif, dan tiap Article wajib
  dipakai di minimal satu baris BOM (ada warna/nilai terisi)**, sebelum revisi
  bisa diterbitkan — dua pengecekan terpisah, keduanya wajib.
- **Exchange rate tidak wajib diisi saat membuat revisi CBD** — boleh dibuat
  kosong dulu, baru wajib diisi (>0) saat revisinya diterbitkan.
- **Rupiah adalah mata uang utama CBD, termasuk Rekap Biaya** (Material Cost,
  Actual FOB, dst dihitung dalam Rupiah). Kolom **USD** di grid editor
  bersifat sekunder — hanya terisi kalau exchange rate sudah diisi; baris
  berharga IDR tidak pernah butuh exchange rate sama sekali.
- **Rekap CBD dipecah jadi dua panel**: **Rekap Biaya** (Exchange Rate,
  Amortisasi, Adjustment, Target FOB, Actual FOB — dihitung dari total cost/pair
  yang sudah dalam Rupiah, dan Selisih dengan label kualitatif OVER/UNDER) dan
  **Rekap Margin** (Selling Price dan Margin %, saling terhubung dua arah:
  mengubah salah satu menghitung ulang yang lain terhadap Actual FOB saat ini;
  terkunci begitu revisi CBD terbit, sama seperti field rekap lain).
  Kedua panel ini tambahan di luar PRD (permintaan lanjutan) — PRD hanya
  menyebut satu panel rekap dengan Selisih/Selisih % antara Selling Price dan
  Target FOB.
- **Data dummy di-seed otomatis** saat database masih kosong (Material, Komponen,
  Supplier), dan bisa direset kapan saja lewat menu "Admin" › Reset Data
  Prototipe (khusus role System Admin, dengan konfirmasi ketik `RESET`).
- **Satu specsheet nyata ikut di-seed sebagai contoh lengkap**: Model
  `PRM-097` — "ACC Illuzion IV Elite FG" (FH26, stage PROD, revisi r0,
  **DRAFT — belum diterbitkan**, 2 article/colorway: White/True Red dan Safety
  Yellow/Ice Flow; karena belum terbit, CBD-nya belum ada sama sekali) —
  hasil digitalisasi langsung dari specsheet PDF referensi asli (62 baris BOM
  termasuk subkomponen), lengkap dengan material/komponen/supplier
  pendukungnya yang otomatis ditambahkan ke master data bila belum ada
  (`app/domain/seed_specsheet_illuzion.py`). Kode material seed seragam
  `MTR-NNNN`: dummy MTR-0001..0020, material Illuzion MTR-0021..0059. Diseed lewat jalur yang sama
  dengan data dummy (`create_app()` saat DB kosong/baru, dan "Reset Data
  Prototipe") — idempoten, tidak dobel bila dijalankan ulang. CBD-nya
  sengaja TIDAK ikut di-seed (PDF sumber murni specsheet, tanpa data harga);
  generate & isi CBD-nya sendiri lewat menu "CBD" saat harga sudah tersedia.
  Beberapa penyesuaian digitalisasi didokumentasikan sebagai komentar di
  bagian atas file seed tsb (mis. baris proses/dekorasi disederhanakan jadi
  5 material generik — Printing, Laminating, HF Welding, Upper Molded,
  Coating FA 7300/50 Micron + Sticker — dengan detail spesifik dipindah ke
  nama subkomponen).
- **Navigasi fluid:** halaman pakai `hx-boost` (AJAX, tanpa reload penuh) dan
  grid BOM/CBD edit-inline (klik sel langsung ketik, autosave saat pindah fokus).
- **Tema visual:** aksen biru tua (navy), lihat `app/web/static/style.css`.
- **Uang/kuantitas di CBD disimpan sebagai TEXT berisi Decimal**, bukan REAL,
  sesuai instruksi PRD "jangan pakai float" — dikonversi ke `decimal.Decimal`
  di `app/domain/cbd_calc.py` saat dihitung.
- **Dua kasus "copy dari article lain" di PRD 6.4 (season sama / season lalu)
  digabung jadi satu aksi wizard** ("Copy dari Article Lain"): keduanya
  sama-sama "ambil CBD terbit terakhir article yang dipilih user", beda hanya
  season-nya — dibedakan lewat label season di pilihan, bukan lewat tombol
  terpisah.
- **CBD DRAFT wajib di-refresh dulu kalau specsheet acuannya sudah direvisi
  ulang** (tambahan di luar PRD, lihat "CBD DRAFT yang ketinggalan revisi
  specsheet" di bawah) — mencegah CBD terbit dari BOM yang sudah usang tanpa
  disadari user, karena PRD 6.6 (penandaan sinkronisasi) sendiri hanya
  menjangkau CBD yang sudah terbit, bukan yang masih draft.
- **Laporan Validasi CBD vs Specsheet (PRD 7.4) dibandingkan terhadap revisi
  specsheet TERBIT TERKINI**, bukan hanya `specsheet_revision_id` yang dipakai
  saat CBD itu terakhir digenerate/refresh — supaya laporan juga menangkap
  drift yang belum ter-refresh (bukan cuma mengulang apa yang sudah
  tersimpan). Ditampilkan sebagai tab "Validasi" di halaman detail CBD,
  bukan halaman laporan terpisah, karena laporan ini per-revisi (butuh
  Model/Season/Article/Revisi yang sudah dipilih di sana).
- **Where-Used (PRD 7.4) melihat revisi TERBARU tiap specsheet (DRAFT atau
  PUBLISHED)**, bukan hanya yang sudah terbit — supaya berguna juga untuk
  mengecek dampak sebelum sebuah revisi diterbitkan (mis. sebelum
  menonaktifkan/mengganti material). Kalau specsheet punya draft yang
  menghapus pemakaian sebuah material, where-used langsung mencerminkan itu.
- **Dashboard sinkronisasi agregat dan laporan penyimpangan Loss % (PRD 7.4)
  sengaja tidak dibangun** atas permintaan lanjutan — dianggap tidak perlu
  untuk versi ini. Penandaan sinkronisasi per-CBD (PRD 6.6) sendiri tetap ada
  (badge `IN_SYNC`/`NEEDS_REVISION` di halaman detail CBD), yang dihapus
  hanya laporan agregatnya.
- **Ekspor Excel dipakai `openpyxl`, bukan `exceljs`** (library JS, tidak relevan
  untuk stack Python/Flask ini) — hasilnya tetap file `.xlsx` standar.
- **Test e2e (PRD M5) memakai Flask test client, bukan Playwright.** PRD
  mengasumsikan stack Next.js (SPA) sehingga menspesifikasikan Playwright untuk
  menguji browser sungguhan. Aplikasi ini server-rendered (Flask + htmx) tanpa
  SPA, jadi alur utama (`tests/test_e2e_web.py`) diverifikasi lewat request HTTP
  langsung ke seluruh blueprint + database SQLite asli — mencakup hal yang sama
  (routing, validasi, publish, generate CBD, penandaan sinkronisasi, ekspor)
  tanpa perlu install browser/dependency tambahan yang bertentangan dengan
  prinsip "100% lokal, tanpa internet" aplikasi ini. Interaksi client-side
  murni (edit-inline, autosave) sudah dilatih manual lewat pratinjau browser
  selama pengembangan, bukan lewat automated browser test.
- **Harga Referensi di specsheet (tambahan di luar PRD)**: khusus role
  `BRAND_VIEWER` melihat revisi specsheet yang sudah **PUBLISHED**, tiap sel
  BOM yang terpakai (`is_used`) menampilkan perkiraan harga material terakhir
  — walau CBD article itu sendiri belum pernah dibuat. Harga master yang
  berlaku untuk material + supplier (+ warna) sel itu selalu didahulukan; kalau
  master belum punya harganya, baru mengambil
  histori dari CBD PUBLISHED mana pun (article/model/stage lain), dicari
  bertingkat per sel (bukan per baris, karena warna berbeda tiap
  article/colorway): `material + warna + supplier` → `material + supplier` →
  `material + warna` → `material` saja. Berhenti di tingkat pertama yang ada
  hasilnya, lalu ambil histori PUBLISHED yang **paling baru terbit** di
  tingkat itu (stage apa pun — tidak diprioritaskan sama dengan stage
  specsheet yang sedang dilihat). Tidak tampil untuk role vendor
  (`VENDOR_SPEC`/`VENDOR_CBD`) maupun untuk revisi DRAFT — ini murni
  perkiraan, bukan harga pasti article tsb, jadi ditandai dengan "≈" dan info
  tooltip (stage/revisi/tanggal sumbernya).

## Status pembangunan (per milestone PRD Bagian 10)

- [x] **M1 — Fondasi & Master Data**
- [x] **M2 — Specsheet** (Master Data + Model/BOM; lihat catatan "Belum
  dibangun di web" di bawah untuk beberapa sub-fitur M1/M2 yang belum diporting)
- [x] **M3 — CBD** (generate/merge dari specsheet, editor, rekap, publish,
  penandaan sinkronisasi)
- [x] **M4 — Sinkronisasi & Laporan** (penandaan sinkronisasi per PRD 6.6 sudah
  ada sejak M3 — lihat menu "CBD"; laporan validasi ada di tab CBD, where-used
  + histori harga di tab detail Material. Dashboard sinkronisasi agregat dan
  laporan penyimpangan Loss % sengaja tidak dibangun, lihat "Penyesuaian dari
  PRD asli")
- [x] **M5 — Ekspor & Penyelesaian** (ekspor Excel + halaman cetak untuk
  specsheet dan CBD, test e2e alur utama, dokumentasi setup. Antrian Usulan &
  Merge, Impor CSV, dan upload foto tetap di luar lingkup — lihat "Belum
  dibangun di web" di bawah)

### Beranda "Tugas Saya"

Halaman pertama setelah masuk untuk semua role (`/`), isinya sesuai pekerjaan
role tsb (`app/domain/worklist_service.py`). Setiap item langsung menuju layar
yang tepat.

- **Vendor Spec**: draft specsheet terbuka beserta penghambat terbitnya
  (belum ada article aktif, article aktif belum dipakai di BOM, baris tanpa
  supplier, BOM kosong), article di halaman Model yang belum masuk specsheet,
  dan jumlah usulan master data yang menunggu persetujuan.
- **Vendor CBD**: article aktif di specsheet terbit yang belum punya CBD, draft
  CBD yang harus di-refresh (specsheet acuan sudah direvisi / harga master
  berubah), CBD terbit `NEEDS_REVISION`, draft yang sedang berjalan, dan
  material katalog + supplier di specsheet terbit yang belum punya harga master
  (dengan jumlah warna yang belum berharga).
- **Master Admin**: antrian persetujuan material, komponen, dan supplier
  material berstatus `PROPOSED`.
- **Brand Viewer**: revisi terbit terakhir tiap specsheet (season) dan tiap
  CBD article.
- **System Admin**: ringkasan jumlah data dan audit log, link ke menu Admin.

### Menu "Master Data"

Sub-tab: **Material**, **Komponen**, **Supplier**, dan **Persetujuan** (khusus
Master Admin, dengan badge jumlah usulan). Form tambah material/komponen/supplier
dibuka lewat tombol "+ Tambah …" (modal). Daftar material bisa difilter status.

- **Persetujuan**: satu antrian untuk material, komponen, dan supplier material
  berstatus `PROPOSED`, dengan tombol Setujui (→ `APPROVED`) / Tolak
  (→ `INACTIVE`).
- **Detail Material** punya tab (tersimpan di URL `?tab=`): **Supplier & Harga**
  (default), **Info Material** (edit data & metode harga), **Dipakai di**
  (where-used, dulu menu Laporan), dan **Histori Harga CBD** (dulu menu Laporan;
  tidak tampil untuk Vendor Spec).

- **Material**: Material Code, Material Name, Material Category, Thickness, Unit
  of Measurement, Material Status, Created by/date, Updated by/date — semua isi
  manual kecuali Created/Updated by-date (otomatis dari actor & waktu simpan).
  Material Code wajib unik, dan di form tambah terisi otomatis nomor berikutnya
  (`MTR-NNNN` terbesar + 1) yang tetap bisa diedit. Pengecekan duplikat
  (nama+thickness+UoM, dinormalisasi).
  Daftar material menampilkan jumlah supplier (dan usulan), serta — untuk role
  selain Vendor Spec — status harga ("2/3 berharga") dengan filter "Ada supplier
  belum berharga".
  Master Admin bisa **mengedit** Material Code, Name, Category, Thickness, dan
  UoM (tombol Edit di daftar atau di kartu "Info Material" halaman detail),
  dengan pengecekan duplikat yang sama seperti saat menambah.
- **Detail Material › Supplier & Harga** (klik kode/nama material):
  - Supplier material (Vendor Spec & Master Admin): tambah supplier, kode di
    supplier, jadikan utama. Master Admin approve/nonaktifkan link.
  - Harga (Vendor CBD dan Master Admin yang bisa mengisi; Vendor Spec tidak
    melihat harga): "+ Harga" per supplier (warna opsional, currency, berlaku
    mulai, no. quotation), **Ubah** (form terisi supplier/warna/harga/currency
    harga itu — disimpan sebagai harga baru yang menutup harga lama), **Duplikat** (form terisi supplier/currency yang sama —
    tinggal isi warna & harga khusus), **Akhiri** (mis. harga khusus warna yang
    tidak berlaku lagi), dan riwayat harga per supplier.
- **Komponen**: nomor kelipatan 10, rentang per kelompok (a/c/d/e), saran nomor
  berikutnya otomatis. Master Admin bisa mengedit nomor, nama, dan kelompok
  (aturan nomor sama seperti saat menambah).
- **Supplier**: nama + currency default (IDR/USD, dipakai sebagai default
  currency baris CBD baru). Dipilih per baris BOM di specsheet sebagai "Source
  of Material". Hanya role Master Admin yang bisa menambah, mengganti nama,
  mengubah currency, dan mengubah status.

### Menu "Model"

Sumber data sebelum specsheet: data Model, Season, dan Article/colorway.
Dikelola Vendor Spec dan Master Admin; role lain hanya melihat.

- Daftar Model dengan pencarian (kode/nama) dan filter Season.
- **+ Tambah Model**: nama, kategori, outsole mold, last no., construction, size
  range, sample size, factory (teks bebas).
- Detail Model punya dua tab (tersimpan di URL, `?tab=`):
  - **Season & Article**: chip season (+ jumlah article), "+ Season Baru", lalu
    tabel article season terpilih dengan status specsheet (Aktif/Di-drop di
    revisi terbit terakhir, Di draft, atau Belum masuk specsheet) dan status CBD
    terakhir (kolom CBD tidak tampil untuk Vendor Spec). Aksi: "+ Article"
    (kode + colorway), "Copy Article" dari season lain model yang sama (kode
    yang sudah ada dilewati), Edit, dan Hapus.
  - **Info Model**: semua field model, bisa diedit ("Edit Info").
- Aturan article: kode unik per season. Colorway selalu bisa diubah; kode dan
  hapus hanya selama article belum pernah dipakai di revisi specsheet, sel BOM,
  atau CBD — setelah itu pemakaiannya dihentikan dengan drop di specsheet.
- Tombol "Buka Specsheet" / "Buka CBD" di header langsung ke season yang sama.

### Menu "Specsheet"

- Daftar model yang sama dengan menu Model; klik untuk membuka revisi & BOM
  (`/specsheet/<model>`). URL lama `/model/<id>?revision_id=...` diarahkan ke
  sini.
- Season dibuat di halaman Model (tombol "Kelola Season & Article"); revisi bisa
  dibuat carryover dari specsheet season lain yang sudah punya revisi terbit
  (BOM ikut, colorway/Article season sumber tidak).
- **Copy dari Model Lain**: untuk specsheet pertama pada Model yang benar-benar
  baru, BOM bisa di-copy dari specsheet Model lain (cari kode/nama/season lewat
  modal pencarian) memakai mekanisme carryover yang sama — colorway/Article
  tetap tidak ikut disalin.
- Pembuatan revisi sesuai PRD 6.1: kosong (r0, stage bisa dipilih — default
  `PULL`), carryover, revisi baru di stage sama (lineKey dipertahankan), lanjut
  ke stage berikutnya. Hanya satu revisi `DRAFT` per specsheet pada satu waktu.
  Revisi pertama sebuah season (kosong, carryover, atau copy dari model lain)
  langsung memuat semua article season itu dari halaman Model.
  Revisi DRAFT bisa dihapus lewat tombol "Hapus Draft" (dengan konfirmasi):
  baris BOM dan sel ikut terhapus, article-nya tetap ada (milik Model);
  revisi terbit tidak bisa dihapus.
  Hanya role Vendor - Specsheet yang bisa membuat/mengedit revisi.
- **Grid BOM** (No, Komponen, Deskripsi Material, Source of Material, UoM,
  Remarks, lalu satu kolom per Article): edit inline langsung di sel (material,
  supplier, remarks, nilai per colorway) — tidak perlu dialog terpisah.
  Kosong/"none" pada sel = tidak dipakai pada colorway tsb.
- **+ Komponen**: satu form untuk tambah baris — pilih dari master, atau
  "+ Komponen Baru" untuk nomor manual (komponen lokal).
- **+ Subkomponen**: baris tambahan (proses/dekorasi/varian material) di bawah
  baris komponen, nama diketik bebas. Nomor tampil otomatis
  `[no komponen]-[urutan]`, mis. `10-1`, `10-2`.
- **Ganti Material** (PRD 6.2): pilih material baru langsung dari dropdown di
  sel Deskripsi Material — baris lama dinonaktifkan, baris baru dibuat dengan
  `replacesLineKey`, BomCell disalin.
- **Pilih Article**: memasukkan article season ini (yang dibuat di halaman
  Model tapi belum ada di revisi) sebagai kolom baru di grid BOM — article baru
  tidak dibuat dari sini. Drop lewat tombol "×" di header kolom; article yang
  di-drop bisa diaktifkan lagi lewat panel "Article Di-drop" di toolbar. Drop
  tetap per revisi dan berlaku untuk CBD setelah revisinya terbit.
- **Navigasi**: pilih season lewat dropdown; revisi tampil sebagai stepper
  PULL → SMS → GTM → PROD (chip `rN`, draft bergaris putus). Grid BOM memakai
  lebar penuh (tanpa sidebar). "+ Buat Revisi" membuka wizard yang hanya
  menampilkan opsi valid: kosong / carryover / copy dari model lain untuk revisi
  pertama season, atau revisi baru di stage sama / lanjut ke stage berikutnya.
  Tab BOM / Riwayat tersimpan di URL (`?tab=riwayat`).
- Terbitkan revisi (PRD 6.3): tombol "Terbitkan…" membuka modal **checklist**
  (`revision_service.publish_checklist`, aturan yang sama dipakai
  `publish_revision`): minimal satu article aktif, setiap article aktif
  terpakai di BOM, material tidak `INACTIVE` (penghambat), dan peringatan baris
  tanpa supplier (tidak menghambat). Modal juga menampilkan ringkasan diff dari
  revisi sumber; wajib isi change log (kategori + alasan) untuk revisi selain r0
  pertama. Tab "Riwayat" menampilkan detail baris ditambah/dihapus/berubah
  (termasuk perubahan warna per article).
- **Harga Referensi** (tambahan di luar PRD): khusus role Brand Viewer
  melihat revisi yang sudah `PUBLISHED`, tiap sel BOM yang terpakai
  menampilkan perkiraan harga material terakhir dari histori CBD `PUBLISHED`
  mana pun (bertingkat: material+warna+supplier → material+supplier →
  material+warna → material saja, ambil yang paling baru terbit) — lihat
  "Penyesuaian dari PRD asli" untuk detail lengkap.
- **Ekspor** (PRD 7.5, M5): tombol "Cetak / PDF" dan "Ekspor Excel" di header
  revisi (semua role, termasuk DRAFT — berguna untuk review sebelum terbit).
  "Cetak / PDF" membuka halaman cetak khusus (tanpa topbar/nav) dengan tombol
  `window.print()`; browser menyimpannya sebagai PDF lewat dialog cetak
  bawaan. "Ekspor Excel" mengunduh file `.xlsx` satu sheet: header
  Model/Season/Stage/Revisi, grid BOM (kolom sama seperti editor, satu kolom
  per article aktif), dan area tanda tangan kosong (Dibuat/Diperiksa/Disetujui
  oleh).

### Menu "CBD"

- Navigasi: dropdown **Season** → **chip Article** berstatus (Belum ada CBD /
  draft / terbit / perlu revisi / di-drop) → **stepper revisi CBD** per stage
  (chip kuning = `NEEDS_REVISION`). Tab **Editor · Rekap · Validasi · Riwayat**
  tersimpan di URL; **ringkasan biaya** (Material Cost, Actual FOB, Target FOB,
  Selisih, Selling Price, Margin) menempel di atas saat menggulir; kolom No &
  Komponen di grid editor dibekukan saat digulir ke samping. Header menautkan ke
  revisi specsheet acuan CBD tsb. Satu CBD per Article. Article diambil dari
  yang sudah dibuat di halaman Model — CBD tidak membuat Article baru. Hanya
  article yang **aktif di revisi specsheet terbit terakhir** yang bisa dipilih
  untuk membuat/mengubah CBD; article yang di-drop (atau baru ditambahkan di
  revisi specsheet yang belum terbit) pindah ke bagian "Article tidak aktif" —
  CBD lamanya hanya bisa dilihat, dan CBD DRAFT-nya tidak bisa diubah/diterbitkan.
  Drop/aktifkan article baru berlaku untuk CBD setelah revisi specsheet-nya
  terbit; article yang diaktifkan lagi bisa dibuatkan CBD lagi.
- **Wizard pembuatan revisi** (PRD 6.4 usage table): "Buat CBD" (tanpa
  sumber, article pertama kali), "Copy dari Article Lain" (article manapun di
  Model yang sama, season sama atau lain, yang sudah punya CBD terbit),
  "Revisi Baru (Stage Sama)", "Lanjut ke Stage Berikutnya". "Copy dari Article
  Lain" hanya muncul untuk CBD pertama article (stage awal) dan mengambil
  revisi CBD **terbit terakhir** article sumber (label pilihannya menyebut
  season · stage · revisi). Baris, warna, dan supplier selalu dari specsheet
  article tujuan; yang di-copy hanya Yield, Loss %, dan harga
  quotation/override baris yang cocok. Baris sumber yang tidak ada di specsheet
  tujuan diabaikan (tidak jadi `MISSING_IN_SPEC` — status itu hanya untuk
  revisi lanjutan article yang sama). Semua pembuatan CBD dari sumber (copy,
  revisi baru, lanjut stage) juga menyalin **Rekap Biaya & Rekap Margin**:
  Exchange Rate, Amortisasi, Adjustment, Target FOB, dan Selling Price (tetap
  bisa diedit; Actual FOB & Margin % dihitung ulang).
- **Hapus Draft**: revisi CBD DRAFT bisa dihapus (tombol "Hapus Draft",
  dengan konfirmasi) seakan belum pernah dibuat, termasuk draft article yang
  sudah di-drop. Revisi terbit tidak bisa dihapus. Tidak ada input
  Exchange Rate saat membuat revisi baru tanpa sumber/copy — rate diisi
  belakangan lewat Rekap Biaya, baru wajib diisi (>0) saat publish; revisi
  lanjutan mewarisi rate dari revisi sebelumnya
  (bisa diubah).
- Satu algoritma generate/merge dipakai untuk semua kasus di atas
  (`app/domain/cbd_service.generate_or_merge_cbd`): ambil baris BOM yang
  `isUsed` untuk Article itu (1:1, tanpa Aturan Transformasi) →
  cocokkan ke baris CBD sumber (by lineKey → originLineKey → identitas
  komponen+material; subkomponen dicocokkan lewat **nama** subkomponen +
  material, bukan nomor urutnya) untuk menyalin Yield/Loss%/Harga/Currency (Supplier
  selalu diambil ulang dari specsheet, tidak ikut disalin dari sumber CBD);
  baris sumber yang sudah tak terpakai muncul sebagai `MISSING_IN_SPEC`
  (bukan dihapus, mengikuti status specsheet — tidak ada aksi batalkan manual).
- **Editor grid** dikelompokkan a/c/d/e seperti contoh CBD referensi. Kolom
  **Thickness** (live dari Master Material) dan **Remarks** (read-only, live
  dari baris specsheet acuan) ikut tampil, juga di cetak & Excel. Kolom
  Yield/Loss% edit-inline; Harga asli/Currency terisi dari master harga
  (label "master · semua warna" / "master · warna X"), atau "Override…" per baris
  dengan alasan wajib; baris tanpa harga menjelaskan sebabnya (supplier belum
  dipilih di specsheet / belum ada harga untuk supplier ini / hanya ada harga
  warna lain) dengan link ke Master Material; Supplier, Usage (= 1/Yield),
  USD*/IDR*/Cost per pair (Rp)* read-only/turunan. Rupiah adalah mata uang
  utama — Cost per pair dan IDR* dihitung langsung untuk baris berharga IDR
  tanpa perlu exchange rate; hanya kolom USD* dan baris berharga USD yang
  butuh rate (kosong/"-" kalau rate belum diisi). Loss % default `0.00`. Tidak
  ada aksi "Batalkan baris" — baris hilang otomatis pindah ke bagian "Baris
  Hilang dari Specsheet" (`MISSING_IN_SPEC`) begitu specsheet-nya berubah.
- **Rekap Biaya**: Exchange Rate, Amortisasi, Adjustment, Target FOB, Actual
  FOB (Rupiah, = Material Cost + Amortisasi + Adjustment), dan Selisih dengan
  label OVER/UNDER (Actual FOB dibanding Target FOB).
- **Rekap Margin**: Selling Price dan Margin %, saling terhubung dua arah —
  mengedit salah satu menghitung ulang yang lain terhadap Actual FOB saat ini
  (`app/domain/cbd_calc.margin_pct` / `selling_price_from_margin`). Hanya bisa
  diedit selama revisi DRAFT; setelah terbit, ubah lewat revisi baru. Kedua
  panel rekap ini tambahan di luar PRD, lihat "Penyesuaian dari PRD asli".
- **Terbitkan revisi** (PRD 6.5): modal checklist
  (`cbd_service.cbd_publish_checklist`, dipakai juga oleh `publish_cbd_revision`)
  menampilkan semua syarat sebelum diklik. Validasi Exchange Rate > 0 (meski boleh
  kosong saat draft) dan baris yang berharga sudah punya yield. **Baris tanpa
  harga boleh ikut terbit** (cost-nya 0) — mis. proses yang harganya sudah
  termasuk di baris lain, tanpa perlu ditandai; panel Terbitkan hanya
  menampilkan jumlahnya sebagai pengingat,
  wajib change log untuk revisi selain r0 pertama, hitung & simpan
  diff (`app/domain/cbd_diff_service.py`). Supplier tidak ikut divalidasi di
  sini — supplier selalu mengikuti specsheet (lihat "Penyesuaian dari PRD
  asli"), jadi tidak bisa/tidak perlu dilengkapi lagi dari CBD.
- **Penandaan sinkronisasi** (PRD 6.6): otomatis jalan setiap kali revisi
  specsheet diterbitkan (`revision_service.publish_revision` memanggil
  `cbd_service.mark_cbd_sync_status`). Badge `IN_SYNC`/`NEEDS_REVISION`
  tampil di daftar revisi CBD dan header revisi — hanya CBD article yang
  memang terdampak perubahan BOM-nya yang ditandai. Penandaan ini hanya
  berlaku untuk CBD berstatus **PUBLISHED**.
- **CBD DRAFT yang ketinggalan revisi specsheet.** Baris CBD DRAFT adalah
  snapshot beku dari revisi specsheet terbit terakhir saat CBD itu dibuat —
  tidak otomatis ikut berubah kalau specsheet-nya diterbitkan revisi baru
  lagi selagi CBD masih DRAFT (badge sinkronisasi di atas juga tidak
  menyentuh DRAFT). Untuk mencegah CBD terbit dengan BOM yang sudah usang,
  `publish_cbd_revision` menolak terbit selama `specsheet_revision_id` CBD
  bukan revisi terbit terkini specsheet-nya — muncul tombol
  **"Refresh dari Specsheet Terbaru"** (`cbd_service.refresh_cbd_draft`) di
  halaman CBD untuk regenerasi baris dari BOM terbaru, memakai baris lama
  sebagai sumber (yield/harga yang sudah diisi tidak hilang, dicocokkan
  seperti generate/merge biasa: lineKey → originLineKey → identitas).
- **Ekspor** (PRD 7.5, M5): tombol "Cetak / PDF" dan "Ekspor Excel" di header
  revisi. Keduanya menampilkan grid dikelompokkan a/c/d/e, bagian terpisah
  untuk baris `MISSING_IN_SPEC`, panel Rekap Biaya + Rekap Margin, dan Change
  Log — persis seperti tab "Editor"/"Riwayat" di layar, hanya dalam format
  siap cetak/unduh. "Ekspor Excel" mengunduh satu file `.xlsx` per revisi CBD.

### Laporan (di detail Material)

Menu "Laporan" terpisah sudah dihapus; laporan per material ada di tab detail
Material, dan URL lama `/laporan/...` diarahkan ke sana. Dashboard sinkronisasi
agregat dan laporan penyimpangan Loss % (PRD 7.4) sengaja tidak dibangun — lihat
"Penyesuaian dari PRD asli".

- **Dipakai di / Where-Used** (PRD 7.4): Model, Season, Article, Komponen,
  Stage, Revisi yang memakai material — melihat revisi TERBARU tiap specsheet
  (DRAFT atau PUBLISHED; Brand hanya revisi terbit).
- **Histori Harga CBD** (PRD 7.4): dikelompokkan
  `color + supplier + uom + stage + currency`, mata uang asli, hanya baris
  `ACTIVE` dari revisi CBD `PUBLISHED`, default stage `PROD` (bisa diganti).
  Tidak tampil untuk Vendor Spec.
- **Laporan Validasi CBD vs Specsheet** (PRD 7.4): tab "Validasi" di halaman
  CBD (badge jumlah selisih), dibandingkan terhadap revisi specsheet TERBIT
  TERKINI.
- **Harga Referensi**: di grid BOM Specsheet untuk role Brand Viewer, lihat
  "Penyesuaian dari PRD asli".

### Menu "Admin" (System Admin)

- **Audit Log**: 200 entri terbaru, filter per entitas dan pencarian teks,
  detail sebelum/sesudah per entri.
- **Reset Data**: kosongkan & seed ulang data prototipe (konfirmasi ketik
  `RESET`).

**Belum dibangun di web** (business logic-nya ada di `app/domain/` tapi belum
ada UI web-nya): Antrian Usulan & Merge, Impor CSV, upload foto sepatu.

## Menjalankan aplikasi

Butuh Python 3.10+.

```bash
pip install -r requirements.txt
python run_web.py
```

Browser default akan otomatis terbuka ke `http://127.0.0.1:5000`. Database
SQLite otomatis dibuat di `data/app.db` saat pertama kali dijalankan, lengkap
dengan seed data kelompok komponen dan data dummy Material/Komponen/Supplier.
Menu "Admin" › Reset Data Prototipe (role System Admin) akan mengosongkan
lalu menyeed ulang data tsb kapan saja.

## Hak akses per role

| Menu / Aksi | Master Admin | Vendor Spec | Vendor CBD | Brand Viewer | System Admin |
| --- | --- | --- | --- | --- | --- |
| Halaman pertama setelah masuk | Beranda | Beranda | Beranda | Beranda | Beranda |
| Master Material, Komponen, Supplier | edit & approve | usul | usul | lihat | – |
| Master Harga & metode harga | edit | tersembunyi | edit | lihat | – |
| Model, Season & Article | edit | edit | lihat | lihat | – |
| Specsheet (BOM, article, terbit) | lihat | edit & terbit | lihat terbit | lihat terbit | – |
| CBD (termasuk Selling Price & Margin) | lihat | tersembunyi | edit & terbit | lihat terbit | – |
| Material › Dipakai di | ✓ | ✓ | ✓ | ✓ (terbit saja) | – |
| Material › Histori Harga CBD | ✓ | – | ✓ | ✓ | – |
| Master › Persetujuan | ✓ | – | – | – | – |
| Admin (Audit Log, Reset Data) | – | – | – | – | ✓ |

Brand Viewer hanya melihat revisi PUBLISHED (specsheet maupun CBD), termasuk
cetak/ekspor. Angka di tampilan CBD diformat Indonesia (titik ribuan, koma
desimal, Rupiah tanpa desimal di rekap); input tetap memakai angka biasa
(mis. `18078` atau `12.6`).

## Menjalankan test

```bash
pytest
```

Test mencakup kriteria penerimaan M1, M2 & M3 di PRD (lewat `app/domain/`,
tidak tergantung UI):
- Material dengan nama+thickness+UoM sama (setelah normalisasi) ditolak; Material
  Code wajib diisi dan wajib unik.
- Nomor komponen non-kelipatan 10 atau di luar rentang kelompok ditolak, dan
  nomor tidak bisa dipakai ulang meski komponennya `INACTIVE`.
- Merge duplikat memindahkan semua referensi dan menulis `AuditLog`.
- Revisi `PUBLISHED` tidak bisa diubah lewat service layer.
- Carryover menyalin baris dengan `originLineKey` terisi dan tanpa article/BomCell.
- Ganti material menghasilkan baris baru dengan `replacesLineKey`, baris lama nonaktif.
- Nomor komponen lokal & penomoran subkomponen sesuai aturan (bukan kelipatan 10,
  unik per revisi, `subSeq` naik terus, `display_no` tampil `[no induk]-[urutan]`).
- Diff menampilkan tambah, hapus, dan perubahan dengan benar.
- Specsheet baru bisa dibuat di stage manapun (default `PULL`), stage tidak
  valid ditolak.
- Publish specsheet ditolak kalau revisi tidak punya article aktif sama
  sekali, atau kalau ada article aktif yang belum dipakai di baris BOM manapun
  (belum ada warna/nilai terisi) — dua pengecekan terpisah.
- CBD dari specsheet hanya memuat baris `isUsed=true` (1:1, tanpa Aturan
  Transformasi), dan mengikuti stage revisi specsheet sumbernya (bukan selalu
  `PULL`).
- Copy CBD antar article/season/revisi/stage mengisi nilai sesuai urutan
  pencocokan (lineKey → originLineKey → identitas komponen+material).
- Baris pengganti (ganti material) membawa Yield/Loss% tanpa harga/currency.
- Baris yang hilang dari specsheet jadi `MISSING_IN_SPEC`, bukan terhapus.
- Usage selalu turunan dari Yield (`usage = 1/yield`), Yield=0 ditolak; Loss %
  default `0.00` saat baris baru dibuat.
- Membuat revisi CBD dengan Exchange Rate kosong berhasil; publish dengan rate
  masih kosong ditolak, publish setelah rate diisi berhasil.
- Baris berharga IDR menghitung Cost per pair/IDR tanpa exchange rate; baris
  USD baru terhitung setelah rate diisi (USD*/harga IDR baris tsb kosong
  sebelum rate ada).
- Publish CBD membolehkan baris tanpa harga, tapi baris berharga wajib punya
  yield, & wajib change log; diff CBD terhitung benar.
- Article yang di-drop di specsheet terbit (`tests/test_cbd_dropped_article.py`):
  tidak bisa dibuatkan CBD, baris CBD-nya tidak terbentuk walau sel BOM-nya
  masih terisi, CBD DRAFT-nya jadi read-only, bisa dibuatkan CBD lagi setelah
  diaktifkan kembali; article yang baru ada di revisi DRAFT belum tersedia untuk
  CBD; where-used tidak menghitung article yang di-drop.
- Penandaan sinkronisasi hanya menandai CBD article yang benar-benar terdampak
  perubahan BOM.
- Publish CBD DRAFT ditolak kalau specsheet acuannya sudah diterbitkan revisi
  baru sejak CBD itu dibuat; `refresh_cbd_draft` menyalin baris dari revisi
  specsheet terkini sambil mempertahankan yield/harga baris yang cocok, dan
  publish berhasil setelahnya.
- Margin % dan Selling Price saling terhubung dua arah: `selling_price_from_margin`
  adalah kebalikan `margin_pct` (`update_margin_pct` menulis ulang kolom
  `selling_price` yang sama dipakai `update_selling_price`).
- Selisih Actual FOB vs Target FOB memberi label `OVER`/`UNDER`/`SESUAI`.

Test M4 (`tests/test_report_service.py`, mengacu ke PRD 7.4):
- Laporan validasi: sesuai/hilang/tidak diharapkan lagi terhitung benar
  setelah specsheet berubah tanpa CBD-nya di-refresh.
- Where-used mengikuti revisi TERBARU tiap specsheet (bukan hanya yang
  terbit) dan menolak material yang tidak ditemukan.
- Histori harga default stage PROD, dikelompokkan color/supplier/uom/currency,
  mengecualikan revisi CBD DRAFT dan stage lain, menolak stage tidak valid.
- Harga referensi: tingkat paling spesifik (material+warna+supplier) yang
  cocok selalu menang meski ada histori lain yang lebih baru di tingkat lebih
  longgar; turun bertingkat sampai material-saja kalau tidak ada yang cocok;
  di tingkat yang sama, histori paling baru terbit yang dipakai; warna
  dicocokkan case-insensitive & trim spasi; revisi CBD yang belum terbit
  (DRAFT) tidak pernah ikut dihitung.

Test metode harga Quotation (`tests/test_quotation_price.py`): material proses
tidak punya harga master; harga quotation diisi di CBD tanpa alasan dan bisa
dikosongkan; override & quotation tidak bisa dipertukarkan; baris proses kosong
boleh terbit; quotation ikut ter-copy ke article yang sama maupun article lain; pindah metode ke
Quotation mengosongkan harga master CBD DRAFT saat di-refresh; migrasi menandai
kategori "Proses ..." sebagai Quotation.

Test urutan & copy (`tests/test_cbd_copy_and_order.py`): baris BOM/CBD urut
menurut nomor komponen dengan subkomponen di bawah induknya; Thickness & Remarks
CBD dibaca live; saran Material Code `MTR-NNNN` berikutnya; copy lintas season
mencocokkan subkomponen lewat nama dan tidak membawa baris sumber yang tak
terpakai.

Test master harga (`tests/test_material_price.py`) & input ketik BOM
(`tests/test_bom_text_input.py`):
- Memilih supplier di BOM membuat link material–supplier PROPOSED; link yang
  dinonaktifkan dan supplier nonaktif tidak bisa dipilih; supplier utama unik.
- Harga baru menutup harga lama (bukan menimpa), tidak boleh mulai lebih awal
  dari harga yang ditutupnya, tanggal sama = koreksi, harga masa depan belum
  dipakai; harga warna menang atas harga semua warna; tidak ada fallback
  lintas supplier.
- CBD mengambil harga dari master; perubahan master harus di-refresh sebelum
  publish; CBD terbit tetap memakai snapshot-nya; override wajib alasan, bisa
  dihapus, dan ikut ter-copy (juga lewat "Copy dari Article Lain"); ganti supplier di specsheet
  menandai CBD `NEEDS_REVISION`; harga referensi mendahulukan master.
- Komponen diketik: label/nomor/nama master → baris master, selain itu komponen
  lokal (No. wajib, aturan nomor tetap); material & supplier wajib ada di master;
  saran warna per season.

Test halaman Model (`tests/test_model_articles.py`): article dibuat tanpa
revisi (kode unik per season); revisi pertama & carryover memuat article season
tujuan; "Pilih Article" ke draft lanjutan; aturan edit/hapus article; copy
article antar season; status specsheet/CBD per article (draft disembunyikan
untuk Brand); edit info model; hak akses halaman Model; hapus draft tidak
menghapus article; redirect URL lama.

Test menu & tab (`tests/test_menu_tabs.py`): checklist terbit specsheet & CBD
sama dengan aturan publish; antrian persetujuan (hanya Master Admin, setujui);
tab detail Material & redirect URL Laporan lama; tab di URL untuk Specsheet &
CBD; audit log System Admin.

Test Beranda (`tests/test_worklist.py`): worklist CBD mengikuti siklus article
(perlu dibuat → draft berjalan → perlu refresh karena harga master / specsheet
berubah → NEEDS_REVISION), gap harga master per material+supplier+warna,
penghambat draft specsheet & article belum masuk specsheet, antrian persetujuan,
dan feed terbit untuk Brand.

Test hak akses (`tests/test_role_access.py`): semua role mendarat di Beranda
dengan isi sesuai role; Vendor
Spec tidak bisa membuka CBD/Histori Harga; aksi dari role yang salah ditolak
403 (Brand, Vendor CBD, Master Admin di specsheet/CBD); Brand tidak melihat
revisi DRAFT (daftar, detail, cetak, ekspor); System Admin hanya menu Admin dan
reset butuh konfirmasi `RESET`.

Test e2e M5 (`tests/test_e2e_web.py`, mengacu ke kriteria penerimaan M5):
alur penuh lewat HTTP request nyata ke seluruh blueprint Flask + database
SQLite asli (beda dari test lain yang memanggil `app/domain/` langsung) —
buat master (material, komponen, supplier) → specsheet dengan 2 article →
terbit → generate CBD kedua article → revisi specsheet yang hanya mengubah
pemakaian satu article → CBD article itu saja yang ditandai `NEEDS_REVISION`
(article lain tetap `IN_SYNC`) → revisi CBD → ekspor Excel dan halaman cetak
untuk specsheet maupun CBD. Menggantikan Playwright (lihat "Penyesuaian dari
PRD asli" untuk alasannya).

## Format CSV impor

Contoh file ada di folder `sample_csv/` (format untuk `app/domain/csv_import.py`
— belum ada UI web untuk memakainya, lihat catatan di atas).

- **Material**: `material_code,name,category,thickness,uom,status`
- **Supplier**: `name,status`
- **Komponen**: `number,name,group_code,status` (group_code: a/c/d/e)

Kolom `status` opsional — default `PROPOSED` untuk material & komponen,
`APPROVED` untuk supplier.

## Struktur folder

```
app/
  schema.sql               # skema SQLite (M1 + M2 + M3 + M4)
  db.py                    # koneksi & inisialisasi database (+ migrasi kolom supplier)
  ids.py, normalize.py     # util umum
  domain/                  # business logic, tervalidasi lewat tests/
    seed_data.py             # data dummy Material/Komponen/Supplier
    seed_specsheet_illuzion.py # seed specsheet nyata PRM-097 (digitalisasi PDF referensi), lihat catatan di atas
    reset_service.py         # "Reset Data Prototipe"
    worklist_service.py       # Beranda "Tugas Saya": daftar pekerjaan per role
    material_price_service.py # master harga: link material–supplier, harga per supplier/warna, lookup untuk CBD
    cbd_calc.py               # kalkulasi turunan CBD (Decimal murni, tanpa DB)
    cbd_service.py             # generate/merge, edit baris, publish, sync-marking CBD
    cbd_diff_service.py        # diff antar revisi CBD
    report_service.py          # M4: validasi CBD vs specsheet, where-used, histori harga, harga referensi
    export_service.py          # M5: konteks + workbook ekspor Excel (specsheet & CBD), dipakai juga oleh halaman cetak
    csv_import.py, merge_service.py, photo_service.py
                              # ada logicnya, belum ada UI web (lihat README di atas)
  web/                      # UI web (Flask + htmx)
    __init__.py               # create_app(): factory, koneksi per-request, seeding
    auth.py                    # require_session, require_permission, guard_blueprint (hak akses per role)
    formatting.py               # format angka tampilan (filter Jinja `angka`/`rupiah`)
    user_session.py             # dataclass Session (role + operator_name)
    blueprints/                # main (login, Beranda), admin (audit log, reset data), master, model (model/season/article),
                               # specsheet (revisi & BOM), cbd, laporan (M4)
    templates/                  # halaman Jinja2 + partial htmx (termasuk _print.html: halaman cetak M5)
    static/                      # style.css (+ print stylesheet M5) + vendor/htmx.min.js (lokal, bukan CDN)
tests/                      # pytest, mengacu ke kriteria penerimaan PRD (termasuk test_e2e_web.py, M5)
sample_csv/                  # contoh file untuk fitur impor CSV (belum ada UI web)
data/                        # dibuat otomatis saat run; berisi app.db (di-gitignore)
uploads/                     # dibuat otomatis saat upload foto (fitur belum ada di web)
run_web.py                   # entry point: python run_web.py
```
