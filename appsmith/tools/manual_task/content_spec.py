# Isi manual task: specsheet sampai terbit.
from engine import Manual

FOLDER = '4 Specsheet'
TASKS = []


def task(fn):
    TASKS.append(fn)
    return fn


STAGE_ROWS = [
    ['Pullover, Preview', 'Boleh terbit walau masih ada sel kuning (hanya peringatan).'],
    ['SMS, GTM, Production', 'Semua warna wajib punya Material Code. Sel kuning menghalangi terbit.'],
]


@task
def buka_specsheet():
    m = Manual('24', 'Membuka Specsheet dan Membaca Tampilannya',
               'Semua role yang punya akses specsheet (Vendor - Specsheet, Vendor - CBD, Manager Costing, Brand '
               'Viewer)',
               '**Specsheet**',
               'Model dan season sudah ada.',
               'Menemukan specsheet sebuah model dan memahami bagian-bagian halamannya.')
    m.h('Membuka specsheet')
    m.p('Ada tiga cara:')
    m.bullets(
        'Dari **Model List**: klik **Specsheet** pada baris model.',
        'Dari **Model Detail**: klik **Open Specsheet →**.',
        'Dari **Home**: klik baris di My Tasks, misalnya **Specsheet Drafts** atau **Latest Published Specsheets**.',
    )
    m.p('Di halaman Specsheet, Anda juga bisa berpindah model dan season lewat dropdown **Select model...** dan '
        'dropdown season di bagian atas.')
    m.h('Bagian halaman')
    m.shot('Halaman Specsheet: header, stepper stage, tombol, dan grid BOM')
    m.table(['Bagian', 'Fungsinya'], [
        ['Header', 'Nama model, season, dan informasi revisi yang sedang dibuka.'],
        ['Stepper stage', 'Pullover, Preview, SMS, GTM, Production. Klik revisi untuk membukanya.'],
        ['**+ Create**', 'Membuat revisi baru (manual 25 sampai 28). Tidak tampil bila masih ada draft.'],
        ['**Export Excel**', 'Mengunduh specsheet ke Excel (manual 38).'],
        ['**Delete Draft**', 'Menghapus revisi draft (manual 36).'],
        ['**Add to Revision**', 'Menambah article ke revisi draft (manual 34).'],
        ['**Publish...**', 'Menerbitkan revisi draft (manual 35).'],
        ['**History**', 'Riwayat terbit season ini (manual 37).'],
        ['Grid BOM', 'Daftar komponen, material, Dimension, supplier, Remarks, dan satu kolom warna per article.'],
        ['**Open CBD →**', 'Membuka CBD model ini (untuk role yang punya akses CBD).'],
    ], [4.0, 12.5])
    m.h('Siapa bisa mengubah')
    m.bullets(
        'Hanya Vendor - Specsheet yang bisa mengubah, dan hanya pada revisi berstatus DRAFT.',
        'Revisi PUBLISHED terkunci untuk semua orang.',
        'Brand Viewer hanya melihat revisi yang sudah terbit dari semua pabrik. Pilih pabrik di Model List lewat '
        'dropdown **All factories** bila ingin melihat satu pabrik saja.',
    )
    m.h('Tombol kembali')
    m.p('Tombol di kiri atas (**← Model List**, **← Model Detail**, atau **← Home**) membawa Anda '
        'kembali ke halaman asal dengan filter yang masih tersimpan.')
    m.related('25 Membuat Specsheet Baru dari Kosong', '38 Export Specsheet ke Excel')
    return m


@task
def spec_kosong():
    m = Manual('25', 'Membuat Specsheet Baru dari Kosong',
               'Vendor - Specsheet',
               '**Specsheet**, tombol **+ Create**',
               'Model, season, dan article sudah ada. Season ini belum punya revisi specsheet.',
               'Membuat specsheet pertama sebuah season dengan BOM kosong.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka **Model Detail**, pilih season, lalu klik **Open Specsheet →**.',
        'Klik **+ Create**. Form **Create Revision** terbuka.',
        'Pilih **Start empty**.',
        'Pilih stage awal, biasanya Pullover. Anda boleh mulai dari stage lain bila model langsung masuk stage '
        'itu.',
        ('shot', 'Form Create Revision dengan pilihan Start empty'),
        'Klik **Create**. Muncul pesan **Draft revision created.** dan revisi baru berstatus DRAFT, misalnya '
        'Pullover r0.',
        'Semua article di season itu sudah masuk ke revisi. Lanjutkan dengan mengisi BOM (manual 29).',
    )
    m.note('Satu season hanya boleh punya satu draft. Terbitkan atau hapus draft lama sebelum membuat revisi baru.')
    m.related('26 Copy Specsheet dari Season Lain', '27 Copy Specsheet dari Model Lain', '29 Menambah Baris BOM')
    return m


@task
def copy_season():
    m = Manual('26', 'Copy Specsheet dari Season Lain',
               'Vendor - Specsheet',
               '**Specsheet**, tombol **+ Create**',
               'Season baru sudah dibuat di model yang sama (manual 21) dan article-nya sudah ada. Season lain dari '
               'model ini sudah punya revisi yang terbit.',
               'Memakai ulang BOM dari season lain model yang sama, supaya tidak mulai dari nol. Contoh: model '
               'RUNNER X sudah punya specsheet SS27, lalu dibuat season FH27.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka **Model Detail**, pilih season baru, lalu klik **Open Specsheet →**.',
        'Klik **+ Create**.',
        'Pilih **Copy from another season (same model)**.',
        'Pilih **Source season**. Yang bisa dipilih hanya season yang punya revisi terbit, dan yang disalin adalah '
        'revisi terbit terakhirnya.',
        'Pilih stage awal untuk season baru.',
        ('shot', 'Form Create Revision dengan pilihan Copy from another season'),
        'Klik **Create**. Revisi DRAFT baru terbentuk.',
    )
    m.h('Yang disalin dan yang tidak')
    m.table(['Disalin', 'Tidak disalin'], [
        ['Baris BOM: komponen, material, Dimension, supplier.', 'Warna di sel article. Article season baru masuk '
         'dengan warna kosong.'],
    ], [8.25, 8.25])
    m.h('Setelah copy')
    m.steps(
        'Periksa setiap baris BOM. Hapus atau ganti material yang tidak dipakai di season baru (manual 31).',
        'Isi warna setiap article (manual 30).',
        'Daftarkan Material Code untuk sel kuning (manual 33).',
        'Terbitkan bila sudah lengkap (manual 35).',
    )
    m.note('Pilihan ini hanya muncul bila season tujuan belum punya revisi sama sekali. Bila season sudah punya '
           'revisi, pakai Next revision atau Next stage (manual 28).', kind='Info')
    m.messages([
        ['No other season of this model has a published revision.', 'Belum ada season lain yang terbit.',
         'Pakai Start empty, atau terbitkan dulu specsheet season sumber.'],
        ['Select a source season.', 'Source season belum dipilih.', 'Pilih season sumber, lalu klik Create lagi.'],
    ])
    m.related('25 Membuat Specsheet Baru dari Kosong', '27 Copy Specsheet dari Model Lain')
    return m


@task
def copy_model():
    m = Manual('27', 'Copy Specsheet dari Model Lain',
               'Vendor - Specsheet',
               '**Specsheet**, tombol **+ Create**',
               'Model baru sudah dibuat dengan Category yang sama dengan model sumber (manual 19), beserta season '
               'dan article-nya. Model sumber sudah punya revisi yang terbit.',
               'Membuat specsheet untuk model turunan, misalnya versi IN dan FG yang hanya beda outsole atau beberapa '
               'bagian, dengan menyalin BOM model lain.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka **Model Detail** model baru, pilih season, lalu klik **Open Specsheet →**.',
        'Klik **+ Create**.',
        'Pilih **Copy from another model (same factory & category)**.',
        'Pilih **Source model & season**. Daftar hanya berisi model di pabrik Anda dengan Category yang sama.',
        'Baca ringkasan yang tampil di bawah pilihan (jumlah baris yang akan disalin dan data sumber). Pastikan '
        'model sumbernya benar.',
        'Pilih stage awal.',
        ('shot', 'Form Create Revision dengan pilihan Copy from another model dan ringkasan sumber'),
        'Klik **Create**. Revisi DRAFT baru terbentuk.',
    )
    m.h('Yang terjadi saat copy')
    m.bullets(
        'Baris BOM dari revisi terbit terakhir model sumber disalin: komponen, material, Dimension, supplier.',
        'Article model baru masuk dengan warna kosong.',
        'Model sumber otomatis tercatat sebagai model induk (parent model) dari model baru.',
        'Tidak ada sinkron otomatis. Perubahan di model sumber setelah ini tidak ikut ke model baru.',
    )
    m.h('Setelah copy')
    m.steps(
        'Ganti baris yang berbeda dari model sumber, misalnya outsole (manual 31).',
        'Isi warna setiap article (manual 30).',
        'Daftarkan Material Code untuk sel kuning (manual 33), lalu terbitkan (manual 35).',
    )
    m.note('Pilihan ini hanya muncul bila season model baru belum punya revisi. Bila model yang Anda cari tidak '
           'ada di daftar, periksa Category kedua model dan pastikan model sumber sudah punya specsheet terbit.')
    m.messages([
        ['Select a source model & season.', 'Sumber belum dipilih.', 'Pilih model dan season sumber.'],
    ])
    m.related('26 Copy Specsheet dari Season Lain', '19 Membuat Model Baru')
    return m


@task
def revisi_stage():
    m = Manual('28', 'Membuat Revisi Berikutnya atau Naik Stage',
               'Vendor - Specsheet',
               '**Specsheet**, tombol **+ Create**',
               'Season sudah punya revisi yang terbit dan tidak ada draft.',
               'Memperbaiki specsheet yang sudah terbit (revisi baru di stage yang sama) atau melanjutkan ke stage '
               'berikutnya.')
    m.h('Pilih jenis revisi')
    m.table(['Pilihan', 'Kapan dipakai', 'Contoh'], [
        ['**Next revision**', 'Ada perubahan di stage yang sama.', 'SMS r0 menjadi SMS r1'],
        ['**Next stage**', 'Model naik ke tahap berikutnya. Boleh melompat stage.', 'Preview r1 menjadi SMS r0, '
         'atau Pullover langsung ke SMS'],
    ], [3.5, 7.5, 5.5])
    m.h('Langkah-langkah')
    m.steps(
        'Buka specsheet season tersebut.',
        'Klik **+ Create**.',
        'Pilih **Next revision** atau **Next stage**.',
        'Untuk Next stage, pilih **Target stage**. Pilihan awalnya adalah stage berikutnya.',
        ('shot', 'Form Create Revision dengan pilihan Next revision dan Next stage'),
        'Klik **Create**. Revisi DRAFT baru terbentuk berisi salinan revisi terbit terakhir (baris BOM, article, '
        'dan warna).',
        'Lakukan perubahan, lalu terbitkan (manual 35).',
    )
    m.h('Aturan stage')
    m.table(['Stage', 'Aturan sel kuning'], STAGE_ROWS, [5.0, 11.5])
    m.bullets(
        'Stage hanya bisa maju, tidak bisa kembali ke stage sebelumnya.',
        'Next stage tidak tersedia bila sudah di Production.',
        'Tombol **+ Create** tidak tampil selama masih ada draft. Terbitkan atau hapus draft dulu.',
    )
    m.related('35 Menerbitkan Specsheet (Publish)', '36 Menghapus Draft Specsheet')
    return m


@task
def tambah_baris():
    m = Manual('29', 'Menambah Baris BOM',
               'Vendor - Specsheet',
               '**Specsheet**, grid BOM (revisi DRAFT)',
               'Revisi DRAFT sudah dibuat (manual 25 sampai 28).',
               'Menambahkan komponen beserta material, Dimension, dan supplier ke specsheet, termasuk subkomponen.')
    m.h('Menambah baris')
    m.p('Baris baru selalu ditambahkan dari baris paling bawah grid.')
    m.steps(
        'Di kolom **Component**, ketik nomor atau nama komponen, misalnya 10 atau VAMP, lalu pilih dari daftar.',
        'Di kolom **Material**, ketik nama material (bukan Material Code). Daftar saran tampil lengkap dengan '
        'satuan dan Dimension yang terdaftar. Pilih dengan klik, atau panah lalu Enter.',
        'Periksa kolom **Dimension**. Isinya otomatis Dimension yang paling banyak dipakai material itu, atau '
        '**(None)** bila material belum punya varian. Klik kotaknya untuk memilih Dimension lain dari daftar.',
        'Periksa kolom **Supplier**. Supplier utama material terisi otomatis. Untuk mengganti, ketik sebagian nama '
        'lalu pilih.',
        ('shot', 'Baris tambah di bawah grid BOM dengan saran material'),
        'Klik **+ Add**. Baris tersimpan dan muncul di grid sesuai urutan nomor komponen.',
        'Isi warna setiap article (manual 30).',
    )
    m.h('Daftar Dimension')
    m.bullets(
        '**(None)** selalu di paling atas dan berarti bahan tanpa ukuran.',
        'Dimension material itu tampil dengan jumlah warnanya. Dimension yang sedang terisi dicentang.',
        'Saat mengetik, Dimension dari material lain ikut tampil di bawah judul **Other materials**, supaya '
        'penulisan Dimension baru seragam.',
        'Dimension baru boleh diketik, misalnya 1,4mm (otomatis menjadi 1.4 MM). Sel warnanya akan kuning sampai '
        'varian didaftarkan.',
        'Kotak Dimension yang dikosongkan kembali menjadi **(None)**.',
    )
    m.h('Menambah subkomponen')
    m.steps(
        'Klik **+ Sub** pada baris induk.',
        'Isi nama subkomponen, material, Dimension, dan supplier di baris form yang muncul di bawah induk.',
        'Klik **Add**.',
    )
    m.h('Komponen lokal')
    m.p('Bila nama komponen yang diketik tidak ada di Master Component, baris dibuat sebagai komponen lokal (tanda '
        '**local**). Komponen lokal wajib diberi nomor yang bukan kelipatan 10. Sebaiknya daftarkan komponen di '
        'Master Component (manual 10), lalu ganti lewat **Change** (manual 31).')
    m.h('Tips mengetik')
    m.bullets(
        'Enter atau Tab menyimpan isian sel. Esc membatalkan ketikan.',
        'Nama material yang hanya beda spasi atau tanda baca langsung dikenali sebagai material master.',
        'Cara lama mengetik nama dan Dimension sekaligus di kolom Material (misalnya HONEYLON MESH 1,5mm) tetap '
        'dibaca dan otomatis dipisah ke kolom Dimension.',
        'Bila material punya nama sama dengan satuan berbeda, saran ditulis seperti NAMA (YD) dan NAMA (M). Pilih '
        'salah satu.',
        'Kolom **Remarks** bisa diisi catatan bebas untuk baris itu.',
    )
    m.messages([
        ['Not in Master Material. (dengan tombol + New material)', 'Material belum terdaftar.',
         'Periksa ketikan, atau klik + New material (manual 32).'],
        ['Did you mean ...?', 'Nama mirip material yang ada.', 'Klik saran yang benar, atau perbaiki ketikan.'],
        ['... is a Material Code (...). Type the material name here; Material Codes are entered with Register.',
         'Anda mengetik Material Code di kolom Material.', 'Ketik nama material. Material Code diisi lewat Register '
         '(manual 33).'],
        ['Component ... already has this material with the same dimension in this revision.',
         'Komponen itu sudah punya material dan Dimension yang sama.', 'Pakai baris yang sudah ada.'],
    ])
    m.related('30 Mengisi Warna Article', '31 Mengubah dan Menghapus Baris BOM',
              '32 Material dan Supplier Baru dari Specsheet')
    return m


@task
def isi_warna():
    m = Manual('30', 'Mengisi Warna Article',
               'Vendor - Specsheet',
               '**Specsheet**, grid BOM (revisi DRAFT)',
               'Baris BOM sudah ada (manual 29).',
               'Mengisi warna bahan untuk setiap article dan memahami arti warna sel.')
    m.h('Langkah-langkah')
    m.steps(
        'Klik sel di kolom article pada baris material.',
        'Ketik warna, misalnya black / white. Saran warna yang sudah dipakai di season ini ikut tampil.',
        'Tekan Enter, Tab, atau klik di luar sel. Warna tersimpan dalam bentuk baku, misalnya BLACK/WHITE.',
        ('shot', 'Sel warna putih berkode dan sel kuning dengan tombol Register'),
        'Kosongkan sel bila article itu tidak memakai bahan ini.',
    )
    m.h('Arti tampilan sel')
    m.table(['Tampilan', 'Artinya', 'Yang perlu dilakukan'], [
        ['Putih dengan Material Code di bawah warna', 'Warna sudah terdaftar sebagai varian, atau kodenya bisa '
         'disusun otomatis.', 'Tidak ada.'],
        ['Kuning dengan tombol **Register**', 'Warna belum punya Material Code.', 'Daftarkan kode (manual 33).'],
        ['Kuning dengan tombol **Did you mean ...?**', 'Warna mirip varian terdaftar tetapi urutan katanya beda, '
         'misalnya RED/NAVY padahal yang terdaftar NAVY/RED.', 'Klik tombol bila memang warna itu. Bila memang '
         'warna lain, biarkan dan daftarkan kodenya.'],
        ['Tanda **process** di baris', 'Material Process. Sel tidak pernah kuning.', 'Tidak ada.'],
    ], [4.5, 6.0, 6.0])
    m.h('Kode yang tersusun otomatis')
    m.p('Sel langsung mendapat Material Code tanpa Register bila ketiga bagian kodenya sudah dikenal: awalan '
        'material itu, kode tengah Dimension itu, dan kode akhir warna itu (dari material yang sama, atau dari '
        'material lain bila warna itu hanya punya satu kode di pabrik). Contoh: COCOTEX 2MM dengan Dimension '
        '2 MM X 44" dan warna BLACK langsung menjadi 20NK312B01.')
    m.h('Aturan penulisan warna')
    m.bullets(
        'Warna yang hanya beda spasi atau tanda baca dianggap sama: BLACK/WHITE = BLACK-WHITE = BLACK WHITE. Sel '
        'otomatis ditulis seperti varian terdaftar.',
        'Urutan kata yang berbeda dianggap warna lain: WHITE/BLACK tidak sama dengan BLACK/WHITE.',
        'Singkatan tidak diubah: BLK tetap BLK.',
        'Material Code yang diketik di sel dianggap teks warna biasa dan selnya kuning. Material Code hanya diisi '
        'lewat Register.',
    )
    m.h('Aturan per stage')
    m.table(['Stage', 'Sel kuning'], STAGE_ROWS, [5.0, 11.5])
    m.related('33 Mengisi Material Code dari Sel Kuning (Register dan Use)', '35 Menerbitkan Specsheet (Publish)')
    return m


@task
def ubah_baris():
    m = Manual('31', 'Mengubah dan Menghapus Baris BOM',
               'Vendor - Specsheet',
               '**Specsheet**, grid BOM (revisi DRAFT)',
               'Revisi DRAFT berisi baris BOM.',
               'Mengganti material, Dimension, supplier, atau komponen pada baris yang sudah ada, membatalkan '
               'penggantian, dan menghapus baris.')
    m.h('Mengganti material')
    m.steps(
        'Klik sel **Material** pada baris, ketik nama material pengganti, lalu tekan Enter.',
        'Dimension baris tetap dipakai bila Dimension itu juga terdaftar di material baru. Bila tidak, Dimension '
        'diganti dengan Dimension utama material baru.',
        'Warna di sel ikut menyesuaikan. Sel menjadi kuning bila varian belum terdaftar.',
        'Tombol **Undo replace** muncul di baris itu.',
    )
    m.h('Mengganti Dimension')
    m.steps(
        'Klik sel **Dimension**. Daftar Dimension material itu tampil.',
        'Pilih Dimension lain, pilih **(None)**, atau ketik Dimension baru, lalu tekan Enter.',
        'Baris diganti ke Dimension baru, dan tombol **Undo replace** muncul.',
    )
    m.h('Membatalkan penggantian')
    m.steps(
        'Klik **Undo replace** pada baris.',
        'Klik sekali lagi untuk memastikan. Baris kembali ke material dan Dimension sebelumnya.',
    )
    m.h('Mengganti supplier')
    m.steps(
        'Klik sel **Supplier**, ketik sebagian nama, lalu pilih. Supplier yang terhubung ke material tampil di '
        'atas, supplier utama paling atas.',
        'Kosongkan sel bila baris belum punya supplier.',
    )
    m.h('Mengganti komponen')
    m.steps(
        'Klik **Change** di kolom **Component** pada baris induk.',
        'Ketik komponen master tujuan, lalu tekan Enter. Esc atau klik di luar untuk batal.',
        ('shot', 'Tombol Change di kolom Component'),
        'Hanya baris itu dan subkomponennya yang pindah. Baris lain dengan komponen yang sama tidak berubah.',
    )
    m.h('Menghapus baris')
    m.steps(
        'Klik tombol hapus di kolom paling kanan baris.',
        'Tombol berubah meminta konfirmasi. Klik sekali lagi untuk menghapus. Menghapus baris induk ikut '
        'menghapus subkomponennya.',
    )
    m.messages([
        ['"..." is not in the component master. Pick a master component from the list.',
         'Komponen tujuan Change tidak ada di Master Component.', 'Pilih dari daftar, atau daftarkan dulu di Master '
         'Component (manual 10).'],
        ['Component ... already has this material with the same dimension in this revision.',
         'Komponen tujuan sudah punya material dan Dimension yang sama.', 'Ganti material, atau hapus baris yang '
         'dobel.'],
    ])
    m.related('29 Menambah Baris BOM', '30 Mengisi Warna Article')
    return m


@task
def material_dari_spec():
    m = Manual('32', 'Material dan Supplier Baru dari Specsheet',
               'Vendor - Specsheet',
               '**Specsheet**, grid BOM (revisi DRAFT)',
               'Revisi DRAFT sedang dibuka.',
               'Menambah material atau supplier baru, dan memperbaiki data material, langsung dari specsheet tanpa '
               'pindah halaman.')
    m.h('Menambah material baru dari baris')
    m.steps(
        'Ketik nama material di baris tambah, lalu klik **+ Add** (atau ganti material di baris yang ada).',
        'Bila material belum terdaftar, muncul **Not in Master Material.** dan tombol **+ New material** di sel '
        'itu.',
        'Klik **+ New material**. Form **Add Material** terbuka dengan nama yang Anda ketik.',
        'Lengkapi **Category** dan **Mea (UoM)**. Centang **Process material (no Material Code)** bila material '
        'berupa proses.',
        ('shot', 'Tombol + New material di sel Material dan form Add Material'),
        'Klik **Save**. Baris langsung ditambahkan dengan material baru.',
    )
    m.p('Tombol **+ New material** juga ada di bar atas grid untuk menambah material tanpa langsung membuat baris.')
    m.h('Memperbaiki material (Edit material)')
    m.steps(
        'Klik **Edit material** di bawah nama material pada baris.',
        'Form **Edit Material** terbuka. Kotak biru menyebut berapa specsheet draft yang memakai material ini, '
        'karena perubahan berlaku di Master Material.',
        'Ubah nama, kategori, Mea, tanda **Process**, atau status.',
        ('shot', 'Link Edit material dan form Edit Material'),
        'Klik **Save**. Muncul **Material saved.** dan grid diperbarui.',
    )
    m.p('Contoh penggunaan: Anda lupa mencentang Process saat menambah material printing. Centang Process lewat Edit '
        'material, maka sel warnanya tidak kuning lagi.')
    m.h('Menambah supplier baru')
    m.steps(
        'Klik **+ New supplier** di bar atas grid.',
        'Isi **Supplier name**, lalu **Save** (aturan sama dengan manual 09).',
        'Pilih supplier tersebut di kolom **Supplier** baris.',
    )
    m.note('Varian (Material Code, Dimension, warna) tidak diubah lewat Edit material. Pakai Register (manual 33) '
           'atau Material Detail (manual 14 dan 15). Aturan kunci sama seperti di Master Material: data yang sudah '
           'dipakai dokumen terbit tidak bisa diubah.')
    m.related('12 Menambah Material Baru', '13 Mengubah atau Menonaktifkan Material',
              '33 Mengisi Material Code dari Sel Kuning (Register dan Use)')
    return m


@task
def register_use():
    m = Manual('33', 'Mengisi Material Code dari Sel Kuning (Register dan Use)',
               'Vendor - Specsheet',
               '**Specsheet**, grid BOM (revisi DRAFT)',
               'Ada sel kuning. Material Code dari ERP atau tim purchasing.',
               'Mendaftarkan Material Code untuk warna yang belum punya kode, langsung dari specsheet, supaya '
               'specsheet bisa terbit di stage SMS ke atas.')
    m.h('Mendaftarkan kode baru (Register)')
    m.steps(
        'Klik **Register** di sel kuning. Form varian terbuka. Material, Dimension, dan warna terkunci sesuai baris '
        'dan sel.',
        'Ketik **Material Code** dari ERP.',
        'Tunggu sampai tulisan **Checking code...** berubah menjadi **Save**. Aplikasi sedang memeriksa kode.',
        ('shot', 'Form Register dari sel kuning'),
        'Bila tidak ada kotak merah, klik **Save**. Sel menjadi putih dan menampilkan kode.',
    )
    m.p('Sel kuning lain dengan material, Dimension, dan warna yang sama di semua draft ikut tersambung. Sel di '
        'baris lain yang kodenya kini bisa disusun juga otomatis mendapat kode.')
    m.h('Kode sudah dipakai varian lain (Use)')
    m.p('Kadang kode dari purchasing ternyata sudah terdaftar untuk material, Dimension, atau warna lain. Artinya '
        'isian di specsheet yang keliru, misalnya nama material salah ketik.')
    m.steps(
        'Setelah kode diketik, muncul kotak merah **Material Code ... is already used: ...** beserta tombol '
        '**Use ... in the specsheet**.',
        'Periksa keterangan material, Dimension, dan warna di kotak merah. Pastikan itu memang bahan yang dimaksud.',
        ('shot', 'Kotak merah dengan tombol Use'),
        'Klik tombol **Use ... in the specsheet**. Form tertutup dan pesan hijau menjelaskan hasilnya.',
    )
    m.p('Akibat Use:')
    m.bullets(
        'Sel tersebut memakai varian itu. Material dan Dimension baris ikut diganti bila perlu.',
        'Sel kuning yang sama (material, Dimension, dan warna sama) di semua draft ikut pindah.',
        'Material salah ketik yang sudah tidak dipakai di draft mana pun otomatis menjadi INACTIVE.',
        'Bila article lain di baris itu memakai warna berbeda, sel tersebut dipindah ke baris baru dengan komponen '
        'yang sama.',
        'Revisi yang sudah terbit tidak berubah.',
        'Tombol **Undo replace** di baris bisa membatalkan, dan material lama aktif kembali.',
    )
    m.h('Kode belum terdaftar tetapi artinya lain (Use kode purchasing)')
    m.p('Bila kode belum terdaftar tetapi bagian-bagiannya berarti material, Dimension, atau warna lain, kotak merah '
        'menulis **Material Code ... is not registered yet. It reads as ..., not this line.** beserta tombol '
        '**Use KODE (MATERIAL, DIMENSION, WARNA) in the specsheet**. Klik tombol itu bila arti kode tersebut benar. '
        'Varian baru didaftarkan lalu dipakai seperti Use biasa. Awalan yang benar-benar baru dianggap milik '
        'material baris itu.')
    m.note('Tombol **Save** ditolak selama kotak merah tampil. Bila arti kode di kotak merah tidak cocok dengan '
           'bahan Anda, jangan klik Use. Periksa kembali kode ke tim purchasing.')
    m.messages([
        ['This Material Code cannot be saved: ...', 'Kode melanggar aturan kode (awalan, kode tengah, atau kode '
         'akhir sudah berarti lain).', 'Lihat tabel arti kotak merah di manual 14 dan cocokkan dengan ERP.'],
        ['Checking the Material Code. Save again in a moment.', 'Pemeriksaan kode belum selesai.',
         'Tunggu sebentar, lalu klik Save lagi.'],
        ['... Use the button in the red box.', 'Kode belum terdaftar dan artinya bukan baris ini.',
         'Klik tombol Use bila arti kode benar.'],
    ])
    m.related('14 Mendaftarkan Varian dan Material Code', '30 Mengisi Warna Article',
              '35 Menerbitkan Specsheet (Publish)')
    return m


@task
def article_revisi():
    m = Manual('34', 'Menambah atau Mengeluarkan Article dari Revisi',
               'Vendor - Specsheet',
               '**Specsheet**, revisi DRAFT',
               'Article sudah dibuat di Model Detail (manual 22).',
               'Memasukkan article baru ke revisi draft, atau mengeluarkan (drop) article yang tidak dilanjutkan.')
    m.h('Menambah article ke revisi')
    m.steps(
        'Buka revisi DRAFT. Keterangan di atas grid menyebut jumlah article aktif dan article yang belum masuk '
        'revisi (not in revision).',
        'Pilih article di kotak **Add articles to the revision...**. Bisa beberapa sekaligus.',
        'Klik **Add to Revision**. Kolom article baru muncul di grid.',
        'Isi warna untuk article baru (manual 30).',
    )
    m.h('Mengeluarkan article (Drop)')
    m.steps(
        'Klik tanda silang di judul kolom article pada grid.',
        'Tanda berubah menjadi **Drop?**. Klik sekali lagi untuk memastikan.',
        ('shot', 'Judul kolom article dengan tombol Drop'),
        'Article keluar dari revisi dan tercatat sebagai dropped di keterangan atas grid.',
    )
    m.note('Article yang sudah pernah dipakai tidak bisa dihapus di Model Detail. Drop adalah cara menghentikan '
           'article tersebut. Article yang di-drop tidak lagi muncul di My Tasks Articles Without Article No.',
           kind='Info')
    m.related('22 Menambah dan Mengubah Article', '35 Menerbitkan Specsheet (Publish)')
    return m


@task
def publish():
    m = Manual('35', 'Menerbitkan Specsheet (Publish)',
               'Vendor - Specsheet',
               '**Specsheet**, tombol **Publish...**',
               'Revisi DRAFT sudah diisi lengkap.',
               'Menerbitkan revisi specsheet supaya menjadi versi final yang terkunci, dan supaya tim CBD bisa mulai '
               'menyusun CBD untuk stage tersebut.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka revisi DRAFT, lalu klik **Publish...**. Form **Publish Revision** tampil dengan checklist.',
        'Periksa checklist. Baris merah harus diperbaiki dulu. Baris dengan tanda seru hanya peringatan.',
        ('shot', 'Form Publish Revision dengan checklist'),
        'Periksa **Change breakdown** yang dihitung otomatis dari revisi terbit sebelumnya. Kategori dan deskripsi '
        'boleh diubah.',
        'Pilih **Change category**.',
        'Isi **Change reason**. Untuk revisi pertama boleh dikosongkan.',
        'Tambahkan gambar bila perlu: tempel dengan Ctrl+V atau klik **choose files** (PNG atau JPG, maksimal 5 '
        'gambar, maksimal 3,5 MB per gambar setelah diperkecil otomatis).',
        'Klik **Publish**. Muncul pesan **Revision ... published.** dan revisi menjadi PUBLISHED.',
    )
    m.h('Isi checklist')
    m.table(['Item checklist', 'Cara memperbaiki bila gagal'], [
        ['All lines have a supplier', 'Isi kolom Supplier di setiap baris (manual 31).'],
        ['Every active article is used in the BOM', 'Isi warna article tersebut di minimal satu baris, atau drop '
         'article bila tidak dipakai (manual 34).'],
        ['All colors have a Material Code (no yellow cells)', 'Daftarkan kode di setiap sel kuning (manual 33). '
         'Hanya peringatan di Pullover dan Preview.'],
        ['No INACTIVE materials', 'Ganti material INACTIVE dengan material aktif (manual 31).'],
        ['All articles have an article no.', 'Isi nomor article di Model Detail (manual 22). Peringatan di SMS dan '
         'GTM, wajib di Production.'],
    ], [6.5, 10.0])
    m.note('Publish bersifat final. Revisi terkunci dan tidak bisa diubah atau dihapus. Perubahan berikutnya dibuat '
           'lewat + Create (manual 28).')
    m.messages([
        ['Select a change category.', 'Change category belum dipilih.', 'Pilih kategori.'],
        ['A change reason is required for this revision.', 'Change reason kosong, padahal ini bukan revisi pertama.',
         'Isi alasan perubahan.'],
        ['Change breakdown descriptions cannot be empty.', 'Ada deskripsi Change breakdown yang kosong.',
         'Isi deskripsinya.'],
        ['In Production every article needs an article no. ...', 'Ada article tanpa nomor di stage Production.',
         'Isi nomor article di Model Detail.'],
        ['Images are still loading. Try again in a moment.', 'Gambar belum selesai dimuat.', 'Tunggu sebentar, lalu '
         'klik Publish lagi.'],
    ])
    m.related('28 Membuat Revisi Berikutnya atau Naik Stage', '37 Melihat Riwayat Terbit',
              '38 Export Specsheet ke Excel')
    return m


@task
def hapus_draft():
    m = Manual('36', 'Menghapus Draft Specsheet',
               'Vendor - Specsheet',
               '**Specsheet**, tombol **Delete Draft**',
               'Ada revisi DRAFT yang tidak jadi dipakai.',
               'Membuang revisi draft, misalnya karena salah memilih cara membuat revisi atau salah stage.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka revisi DRAFT yang ingin dihapus.',
        'Klik **Delete Draft**.',
        'Konfirmasi di kotak yang muncul.',
        'Muncul pesan **Draft ... deleted.** Tombol **+ Create** tersedia lagi.',
    )
    m.note('Semua isian di draft (baris, warna, Remarks) ikut terhapus. Varian dan material yang sudah didaftarkan '
           'tetap ada di Master Material. Revisi PUBLISHED tidak bisa dihapus.')
    m.related('28 Membuat Revisi Berikutnya atau Naik Stage')
    return m


@task
def riwayat():
    m = Manual('37', 'Melihat Riwayat Terbit',
               'Semua role yang punya akses specsheet',
               '**Specsheet**, tombol **History**',
               'Season sudah punya revisi terbit.',
               'Melihat daftar revisi yang pernah terbit beserta alasan perubahan dan gambarnya.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka specsheet season tersebut.',
        'Klik **History** di samping tombol Publish. Angka di tombol menunjukkan jumlah catatan.',
        'Tabel **Publish history** menampilkan Revision, Source, Category, Reason, By, Time, dan Images.',
        'Klik satu baris untuk menampilkan gambarnya.',
        'Klik gambar untuk memperbesar. Pakai tombol panah untuk pindah gambar, Esc untuk menutup, dan **Unduh** '
        'untuk menyimpan gambar.',
        ('shot', 'Jendela Publish history dengan galeri gambar'),
        'Klik **Close** untuk menutup.',
    )
    m.related('35 Menerbitkan Specsheet (Publish)')
    return m


@task
def export_excel():
    m = Manual('38', 'Export Specsheet ke Excel',
               'Semua role yang punya akses specsheet',
               '**Specsheet**, tombol **Export Excel**',
               'Revisi specsheet sudah ada (draft atau terbit).',
               'Mengunduh specsheet dalam format Excel untuk dicetak atau dikirim.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka revisi yang ingin diunduh.',
        'Klik **Export Excel**. Tombol berubah menjadi **Preparing...** sebentar, lalu file terunduh.',
        ('shot', 'Contoh hasil Export Excel specsheet'),
    )
    m.h('Isi file Excel')
    m.bullets(
        'Setiap sel warna berisi warna dan Material Code.',
        'Sel tanpa kode berlatar kuning dengan tulisan (no code), dan header menyebut jumlahnya.',
        'Kolom Dimension untuk bahan tanpa ukuran dibiarkan kosong (tidak tertulis (None)).',
        'Article tanpa nomor ditulis (no article no.) dengan latar kuning.',
        'Kotak PURPOSE mencentang stage revisi tersebut.',
        'Nama file memuat nama model, season, stage, dan nomor revisi.',
    )
    m.related('24 Membuka Specsheet dan Membaca Tampilannya')
    return m
