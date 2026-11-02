# Isi manual task: data master (supplier, komponen, pilihan, material, varian, harga).
from engine import Manual

FOLDER = '2 Master Data'
TASKS = []


def task(fn):
    TASKS.append(fn)
    return fn


@task
def supplier():
    m = Manual('09', 'Menambah dan Mengubah Supplier',
               'Vendor - Specsheet',
               '**Master Supplier**',
               'Nama supplier sesuai data pembelian.',
               'Mendaftarkan supplier baru, mengganti nama, atau menonaktifkan supplier. Supplier dipakai bersama '
               'oleh semua pabrik.')
    m.h('Menambah supplier')
    m.steps(
        'Dari Home, buka menu **Master Data**, lalu halaman **Master Supplier**.',
        'Cari dulu nama supplier di kotak **Search supplier name...**, lalu klik **Search**. Bila sudah ada, '
        'tidak perlu ditambah.',
        'Klik **+ Add Supplier**.',
        'Isi **Supplier name**.',
        'Bila muncul **A supplier with a similar name exists**, periksa daftar yang tampil. Pakai supplier yang ada '
        'bila memang sama, lalu klik **Cancel**.',
        ('shot', 'Form Add Supplier dengan peringatan nama mirip'),
        'Klik **Save**.',
    )
    m.h('Mengubah atau menonaktifkan supplier')
    m.steps(
        'Klik **Edit** pada baris supplier.',
        'Ganti **Supplier name** atau ubah **Status** menjadi INACTIVE.',
        'Klik **Save**.',
    )
    m.h('Yang perlu diperhatikan')
    m.bullets(
        'Nama yang hanya beda huruf besar kecil atau spasi dianggap sama, jadi tidak bisa didaftarkan dua kali.',
        'Nama supplier tidak bisa diubah setelah dipakai di dokumen terbit.',
        'Supplier tidak bisa dibuat INACTIVE selama masih dipakai di specsheet draft.',
        'Supplier juga bisa ditambahkan langsung dari specsheet lewat **+ New supplier** (manual 32).',
    )
    m.related('16 Menghubungkan Supplier ke Material', '32 Material dan Supplier Baru dari Specsheet')
    return m


@task
def komponen():
    m = Manual('10', 'Menambah dan Mengubah Komponen',
               'Vendor - Specsheet',
               '**Master Component**',
               'Nama komponen dan kelompoknya (misalnya Upper atau Bottom).',
               'Mendaftarkan komponen sepatu, misalnya VAMP atau OUTSOLE, dan mengatur urutannya. Komponen dipakai '
               'bersama oleh semua pabrik, dan nomornya menentukan urutan baris di specsheet.')
    m.h('Menambah komponen')
    m.steps(
        'Dari Home, buka **Master Data**, lalu halaman **Master Component**.',
        'Cari dulu nama komponen untuk memastikan belum ada.',
        'Klik **+ Add Component**.',
        'Pilih **Group**. **Number** langsung terisi nomor saran (nomor terakhir kelompok itu ditambah 10).',
        'Bila ingin menaruh komponen di posisi tertentu, ketik nomor sendiri (kelipatan 10, di dalam rentang '
        'kelompok). Klik **Use suggestion** untuk kembali ke nomor saran.',
        'Isi **Component name**.',
        ('shot', 'Form Add Component'),
        'Klik **Save**.',
    )
    m.h('Arti nomor komponen')
    m.p('Nomor komponen adalah posisinya di dalam kelompok. Bila Anda memakai nomor yang sudah dipakai, komponen '
        'pemilik nomor itu (dan komponen yang menempel di bawahnya) otomatis bergeser 10. Contoh: VAMP di 1500, '
        'Anda menambah komponen baru di 1500, maka VAMP pindah ke 1510.')
    m.h('Mengubah komponen')
    m.steps(
        'Klik **Edit** pada baris komponen.',
        'Ubah **Number** untuk memindahkan posisi. Komponen di antara nomor lama dan nomor baru ikut bergeser 10, '
        'sama seperti mengatur urutan di Master Options.',
        'Ubah **Component name** atau **Status** bila perlu.',
        'Klik **Save**.',
    )
    m.note('Nama dan kelompok komponen tidak bisa diubah setelah dipakai di dokumen terbit, tetapi nomornya tetap '
           'bisa. Nomor di specsheet lama ikut berubah. Komponen tidak bisa dibuat INACTIVE selama dipakai di '
           'specsheet draft.')
    m.messages([
        ['Name and group of component ... cannot be changed ...', 'Komponen sudah dipakai dokumen terbit.',
         'Ubah nomornya saja, atau buat komponen baru.'],
        ['Number ... is taken and the components after it cannot move down ...', 'Nomor di ujung rentang kelompok '
         'sudah penuh.', 'Pilih nomor lain yang masih kosong.'],
    ])
    m.related('31 Mengubah dan Menghapus Baris BOM (ganti komponen di specsheet)')
    return m


@task
def options():
    m = Manual('11', 'Mengelola Pilihan Dropdown (Master Options)',
               'Vendor - Specsheet',
               '**Master Options**',
               'Tidak ada',
               'Menambah atau mengatur urutan pilihan dropdown yang dipakai di form model: Category, Construction, '
               'Gender, Last, Outsole mold, dan Size.')
    m.h('Menambah pilihan')
    m.steps(
        'Dari Home, buka **Master Data**, lalu halaman **Master Options**.',
        'Pilih jenisnya di dropdown **Select type**: Category, Construction, Gender, Last (per factory), Outsole '
        'mold (per factory), atau Size.',
        'Klik **+ Add Option**.',
        'Isi **Value**. Bila muncul **A similar option exists**, pakai yang sudah ada bila sama.',
        'Isi **Order (position)** untuk menentukan urutan di dropdown. Kosongkan untuk menaruhnya paling bawah. '
        'Bila nomor sudah dipakai, pilihan baru mengambil posisi itu dan yang lain turun satu.',
        ('shot', 'Halaman Master Options dan form Add Option'),
        'Klik **Save**.',
    )
    m.h('Mengubah pilihan')
    m.steps(
        'Klik **Edit** pada baris pilihan.',
        'Ubah **Value**, **Order (position)**, atau **Status**.',
        'Klik **Save**.',
    )
    m.note('Category, Construction, Gender, dan Size berlaku untuk semua pabrik. Last dan Outsole mold hanya untuk '
           'pabrik Anda.', kind='Info')
    m.related('19 Membuat Model Baru')
    return m


@task
def material_baru():
    m = Manual('12', 'Menambah Material Baru',
               'Vendor - Specsheet',
               '**Master Material**',
               'Nama material, kategori, dan satuan (Mea) sesuai ERP.',
               'Mendaftarkan material (bahan) baru. Warna dan Dimension tidak diisi di sini, tetapi di varian '
               '(manual 14).')
    m.h('Langkah-langkah')
    m.steps(
        'Dari Home, buka **Master Data**, lalu halaman **Master Material**.',
        'Cari dulu nama material di kotak **Search name / category / Material Code...** untuk memastikan belum ada.',
        'Klik **+ Add Material**.',
        'Pilih atau ketik **Category**.',
        'Pilih atau ketik **Mea (UoM)**, misalnya ME, YD, KG, PRS, PCS.',
        'Isi **Material name** tanpa Dimension dan tanpa warna. Contoh: tulis HONEYLON MESH, bukan '
        'HONEYLON MESH 1.5MM BLACK.',
        'Bila muncul **A material with a similar name exists in your factory**, periksa daftarnya. Bila sama, '
        'batalkan dan tambahkan varian di material yang sudah ada.',
        'Centang **Process material (no Material Code)** hanya untuk proses seperti printing, embossing, atau '
        'painting (lihat penjelasan di bawah).',
        'Biarkan **Price method** dan **Status** sesuai isian awal, kecuali diminta tim CBD.',
        ('shot', 'Form Add Material'),
        'Klik **Save**. Halaman **Material Detail** terbuka otomatis untuk menambah varian.',
    )
    m.h('Aturan penulisan nama')
    m.bullets(
        'Nama + Mea yang sama di pabrik Anda adalah material yang sama.',
        'Nama yang hanya beda spasi atau tanda baca dianggap sama. PU-LEATHER, PU LEATHER, dan P.U LEATHER '
        'dengan Mea yang sama tidak bisa didaftarkan dua kali.',
        'Nama sama dengan Mea berbeda dianggap material berbeda.',
        'Untuk benang, daftarkan satu material tanpa nomor shade, misalnya BONDED THREAD(210D/3P). Warnanya '
        'diisi di varian.',
    )
    m.h('Kapan memakai Process material')
    m.p('Material Process dipakai untuk pekerjaan proses yang tidak punya Material Code. Akibatnya:')
    m.bullets(
        'Material ini tidak punya varian dan tidak punya Material Code.',
        'Sel warnanya di specsheet tidak pernah kuning, jadi tidak menghalangi terbit di stage SMS ke atas.',
        'Harganya diisi sebagai quotation di setiap CBD, tanpa persetujuan harga.',
    )
    m.note('Lupa mencentang Process? Ubah lewat Edit Material (manual 13) atau langsung dari specsheet lewat '
           '**Edit material** (manual 32), selama material belum punya varian.')
    m.messages([
        ['Material "..." (...) already exists in this factory (only spaces or punctuation differ). Use that '
         'material.', 'Material dengan nama dan Mea yang sama sudah ada.', 'Pakai material yang sudah ada.'],
    ])
    m.related('13 Mengubah atau Menonaktifkan Material', '14 Mendaftarkan Varian dan Material Code',
              '32 Material dan Supplier Baru dari Specsheet')
    return m


@task
def ubah_material():
    m = Manual('13', 'Mengubah atau Menonaktifkan Material',
               'Vendor - Specsheet (Vendor - CBD dan Manager Costing untuk Price method)',
               '**Master Material** lalu **Material Detail**',
               'Material sudah terdaftar.',
               'Memperbaiki nama, kategori, atau Mea material, mengubah tanda Process, dan menonaktifkan material '
               'yang tidak dipakai lagi.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka **Master Material**, cari material, lalu klik **Open** pada barisnya.',
        'Di halaman **Material Detail**, klik **Edit Material**.',
        'Ubah data yang perlu: **Material name**, **Category**, **Mea (UoM)**, **Process material (no Material '
        'Code)**, atau **Status**.',
        ('shot', 'Halaman Material Detail dengan tombol Edit Material'),
        'Klik **Save**.',
        'Klik **← Master Material** untuk kembali ke daftar.',
    )
    m.h('Yang tidak bisa diubah')
    m.bullets(
        'Nama, kategori, Mea, dan tanda Process terkunci bila material sudah dipakai di specsheet atau CBD terbit.',
        'Process tidak bisa dicentang bila material sudah punya varian (Material Code).',
        'Material yang sudah tidak dipakai cukup diubah **Status** menjadi INACTIVE. Material INACTIVE tidak '
        'muncul lagi di pilihan specsheet.',
    )
    m.messages([
        ['Name, category, and UoM of material ... cannot be changed: it is used in a published specsheet / CBD ...',
         'Material sudah dipakai dokumen terbit.', 'Biarkan data lama. Bila memang salah, buat material baru dan '
         'ganti material di specsheet draft.'],
        ['This material has variants (Material Codes), so it cannot be a Process material.',
         'Material sudah punya varian.', 'Material Process harus material baru tanpa varian.'],
    ])
    m.related('12 Menambah Material Baru', '32 Material dan Supplier Baru dari Specsheet')
    return m


@task
def varian():
    m = Manual('14', 'Mendaftarkan Varian dan Material Code',
               'Vendor - Specsheet',
               '**Material Detail**, tab **Variants**',
               'Material sudah terdaftar (manual 12). Material Code dari ERP atau tim purchasing.',
               'Mendaftarkan kombinasi Dimension dan warna sebuah material beserta Material Code-nya, supaya sel '
               'warna di specsheet tidak kuning.')
    m.h('Arti Material Code')
    m.p('Material Code terdiri dari 10 karakter, dan setiap bagian punya satu arti di pabrik Anda:')
    m.table(['Bagian', 'Contoh', 'Artinya'], [
        ['4 karakter awal', '20NK', 'Material. Satu material memakai satu awalan.'],
        ['3 karakter tengah', '312', 'Dimension. Satu Dimension memakai satu kode tengah. Varian tanpa Dimension '
         'di satu material memakai satu kode tengah yang sama.'],
        ['3 karakter akhir', 'B01', 'Warna. Satu warna di satu material memakai satu kode akhir.'],
    ], [3.5, 2.5, 10.5])
    m.h('Langkah-langkah')
    m.steps(
        'Buka **Master Material**, cari material, klik **Open**.',
        'Di **Material Detail**, buka tab **Variants**, lalu klik **+ Add Variant**.',
        'Isi **Color**. Warna otomatis ditulis baku: huruf besar, tanpa spasi di sekitar tanda / - & + , '
        '(contoh: black / white menjadi BLACK/WHITE).',
        'Periksa **Dimension**. Isian awalnya adalah Dimension yang paling banyak dipakai material ini, atau '
        '**(None)** bila material belum punya varian. Klik kotaknya untuk memilih dari daftar: Dimension material '
        'ini di atas, lalu Dimension material lain. Pilih **(None)** untuk bahan tanpa ukuran. Dimension baru '
        'boleh diketik.',
        'Isi **Material Code**. Bila bagian kodenya sudah dikenal, kode terisi otomatis dari warna dan Dimension. '
        'Tetap cocokkan dengan ERP.',
        'Tunggu sebentar. Selama kode diperiksa, tombol bertuliskan **Checking code...** dan belum bisa diklik.',
        'Bila muncul kotak merah, baca pesannya dan perbaiki kode, warna, atau Dimension (lihat tabel di bawah).',
        ('shot', 'Form Add Variant dengan usulan kode'),
        'Klik **Save**, atau **Save & add another** untuk langsung mengisi varian berikutnya. Dimension terakhir '
        'tetap terisi untuk varian berikutnya.',
    )
    m.h('Penulisan Dimension')
    m.p('Dimension dirapikan otomatis supaya seragam. Contoh: 1,5mm menjadi 1.5 MM, 44X69CM menjadi 44 X 69 CM, '
        '2.0 menjadi 2.')
    m.h('Arti kotak merah')
    m.table(['Pesan di kotak merah', 'Artinya'], [
        ['Prefix ... belongs to material ...', 'Awalan kode sudah dipakai material lain.'],
        ['Material ... uses prefix ...', 'Material ini sudah memakai awalan lain.'],
        ['Dimension code ... means ..., not ...', 'Kode tengah sudah berarti Dimension lain.'],
        ['Dimension ... uses dimension code ...', 'Dimension ini sudah punya kode tengah lain.'],
        ['Color code ... means ...', 'Kode akhir sudah berarti warna lain di material ini.'],
        ['Color ... in material ... uses color code ...', 'Warna ini sudah punya kode akhir lain di material ini.'],
        ['Material Code ... is already used: ...', 'Kode sudah dipakai varian lain.'],
        ['Variant ... already exists in this material (code ...)', 'Warna dan Dimension yang sama sudah punya kode. '
         'Warna yang hanya beda spasi atau tanda baca dianggap sama (BLACK/WHITE = BLACK-WHITE).'],
    ], [7.5, 9.0])
    m.note('Selama ada kotak merah, varian tidak bisa disimpan. Cocokkan lagi dengan ERP. Bila ERP memang memakai '
           'kode itu, hubungi tim material, karena kemungkinan ada data lama yang salah.')
    m.note('Urutan warna yang berbeda dianggap warna lain. WHITE/BLACK tidak sama dengan BLACK/WHITE. Singkatan '
           'seperti BLK tidak diubah menjadi BLACK.', kind='Info')
    m.related('15 Mengubah atau Menghapus Varian', '33 Mengisi Material Code dari Sel Kuning (Register dan Use)')
    return m


@task
def ubah_varian():
    m = Manual('15', 'Mengubah atau Menghapus Varian',
               'Vendor - Specsheet',
               '**Material Detail**, tab **Variants**',
               'Varian sudah terdaftar.',
               'Memperbaiki kode, warna, atau Dimension varian yang salah ketik, menonaktifkan varian, atau '
               'menghapus varian yang belum pernah dipakai.')
    m.h('Mengubah varian')
    m.steps(
        'Buka material di **Material Detail**, tab **Variants**.',
        'Klik **Edit** pada baris varian.',
        'Ubah **Material Code**, **Color**, **Dimension**, atau **Status**. Aturan kode sama dengan saat '
        'mendaftarkan varian (manual 14).',
        'Klik **Save**.',
    )
    m.h('Menghapus varian')
    m.steps(
        'Klik **Delete** pada baris varian.',
        'Konfirmasi penghapusan.',
    )
    m.note('Varian yang sudah dipakai di dokumen terbit tidak bisa diubah kode, warna, atau Dimension-nya, dan tidak '
           'bisa dihapus. Ubah statusnya menjadi INACTIVE, lalu daftarkan varian baru bila perlu.')
    m.messages([
        ['Variant ... cannot be deleted: ... Set it INACTIVE if no longer used.', 'Varian sudah dipakai dokumen.',
         'Ubah Status menjadi INACTIVE lewat Edit.'],
        ['... used in published documents', 'Varian dipakai dokumen terbit, jadi kode, warna, dan Dimension terkunci.',
         'Ubah Status saja, atau daftarkan varian baru.'],
    ])
    m.related('14 Mendaftarkan Varian dan Material Code')
    return m


@task
def link_supplier():
    m = Manual('16', 'Menghubungkan Supplier ke Material',
               'Vendor - Specsheet',
               '**Material Detail**, tab **Supplier**',
               'Material dan supplier sudah terdaftar (manual 09 dan 12).',
               'Mencatat supplier yang menjual sebuah material dan menentukan supplier utama, supaya kolom Supplier '
               'di specsheet terisi otomatis.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka material di **Material Detail**, lalu tab **Supplier**.',
        'Klik **+ Add Supplier**.',
        'Pilih **Supplier**. Supplier harus sudah ada di Master Supplier.',
        'Centang **Main supplier** bila supplier ini otomatis diisi saat material dipilih di specsheet.',
        'Pastikan **Status** = ACTIVE.',
        ('shot', 'Tab Supplier dan form Add Material Supplier'),
        'Klik **Save**.',
    )
    m.h('Mengubah atau melepas supplier')
    m.steps(
        'Klik **Edit** pada baris supplier.',
        'Ubah tanda **Main supplier** atau ubah **Status** menjadi INACTIVE.',
        'Klik **Save**.',
    )
    m.bullets(
        'Satu material hanya boleh punya satu supplier utama.',
        'Supplier yang dibuat INACTIVE otomatis kehilangan tanda utama.',
        'Supplier berlaku untuk semua varian material. Harga per varian diajukan oleh tim CBD (manual 17).',
    )
    m.related('09 Menambah dan Mengubah Supplier', '29 Menambah Baris BOM')
    return m


@task
def ajukan_harga():
    m = Manual('17', 'Mengajukan Harga Material',
               'Vendor - CBD',
               '**Material Detail**, tab **Prices**',
               'Material sudah punya varian dan supplier. Penawaran harga dari supplier.',
               'Mengajukan harga material per varian dan per supplier. Harga baru berlaku setelah disetujui Manager '
               'Costing.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka **Master Material**, cari material, klik **Open**.',
        'Buka tab **Prices**. Setiap baris adalah satu varian dengan satu supplier. Kolom **Remarks** menunjukkan '
        'statusnya.',
        'Klik **+ Propose Price**.',
        'Pilih **Supplier**.',
        'Centang varian yang harganya sama di **Variants**. Bisa beberapa sekaligus, atau klik **Select all**.',
        'Isi **Price** tanpa titik ribuan, misalnya 45000 atau 3,25.',
        'Pilih **Currency** (IDR atau USD).',
        'Isi **Valid from** (tanggal mulai berlaku) dan **Reference** (misalnya nomor penawaran atau PO).',
        ('shot', 'Form Propose Price dengan daftar varian yang dicentang'),
        'Klik **Propose**. Status baris menjadi PENDING APPROVAL.',
    )
    m.h('Arti status di kolom Remarks')
    m.table(['Status', 'Artinya'], [
        ['ACTIVE', 'Harga berlaku sekarang.'],
        ['UPCOMING', 'Sudah disetujui, berlaku mulai tanggal Valid from.'],
        ['PENDING APPROVAL', 'Menunggu persetujuan Manager Costing.'],
        ['REJECTED', 'Ditolak. Alasannya tertulis di sebelahnya.'],
        ['NO PRICE', 'Belum ada harga untuk varian dan supplier ini.'],
        ['EXPIRED, CANCELLED', 'Harga lama. Hanya terlihat bila **Show history** dinyalakan.'],
    ], [4.5, 12.0])
    m.h('Tips')
    m.bullets(
        '**Copy Price** menyalin harga ACTIVE dari varian lain ke varian yang harganya sama. Hasilnya tetap berupa '
        'usulan.',
        'Tombol **Propose** di baris NO PRICE langsung membuka form untuk varian itu.',
        'Tombol **Cancel** di baris usulan membatalkan usulan yang belum diproses.',
        'Harga lama tetap dipakai sampai harga baru disetujui dan tanggal Valid from tiba.',
        'Usulan yang ditolak muncul di My Tasks pada bagian **Rejected Price Proposals** beserta alasannya.',
        'Material Process tidak punya harga master. Harganya diisi langsung di CBD.',
    )
    m.related('18 Menyetujui atau Menolak Harga Material')
    return m


@task
def setujui_harga():
    m = Manual('18', 'Menyetujui atau Menolak Harga Material',
               'Manager Costing',
               '**Price Approval** dan **Material Detail**, tab **Prices**',
               'Ada usulan harga dari Vendor - CBD (terlihat di My Tasks).',
               'Memeriksa usulan harga lalu menyetujui atau menolaknya. Harga yang disetujui menjadi harga master.')
    m.h('Menyetujui atau menolak di Price Approval')
    m.steps(
        'Di Home, klik tugas di My Tasks, atau klik kartu menu **Price Approval**.',
        'Periksa setiap usulan: Material Code, harga usulan, harga lama (Active price), selisihnya, dan Valid from.',
        'Klik **Open material →** bila ingin melihat detail material sebelum memutuskan.',
        'Centang usulan yang ingin diproses, atau **Select all**.',
        ('shot', 'Halaman Price Approval dengan kartu usulan'),
        'Untuk menyetujui, klik **Approve selected** atau **Approve all**, lalu klik sekali lagi untuk memastikan.',
        'Untuk menolak, klik **Reject selected**, isi **Reject reason**, lalu simpan. Alasan dikirim ke tim CBD.',
        ('shot', 'Form Reject reason'),
    )
    m.h('Mengisi harga langsung')
    m.steps(
        'Buka material di **Material Detail**, tab **Prices**.',
        'Klik **+ Add Price**, isi seperti usulan biasa (supplier, varian, harga, currency, tanggal, reference).',
        'Klik **Save**. Harga langsung ACTIVE tanpa proses persetujuan.',
    )
    m.h('Tombol di tab Prices')
    m.bullets(
        '**Approve** dan **Reject**: memproses satu usulan langsung dari barisnya.',
        '**End**: mengakhiri harga yang sedang ACTIVE.',
    )
    m.note('Harga lama tetap aktif sampai usulan disetujui. Bila Valid from usulan ada di masa depan, harga lama '
           'berakhir tepat pada tanggal itu.', kind='Info')
    m.related('17 Mengajukan Harga Material')
    return m
