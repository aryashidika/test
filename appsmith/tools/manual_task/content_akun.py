# Isi manual task: akun, Home, dan System Admin.
from engine import Manual

FOLDER = '1 Akun dan Admin'
TASKS = []


def task(fn):
    TASKS.append(fn)
    return fn


@task
def baca_dulu():
    m = Manual('00', 'Baca Dulu Sebelum Memakai Manual',
               'Semua pengguna',
               'Tidak ada (bacaan pengantar)',
               'Tidak ada',
               'Manual ini menjelaskan cara mengerjakan setiap task di Sistem Specsheet & CBD, mulai dari login, '
               'menyiapkan data master, membuat model, sampai menerbitkan specsheet. Setiap file Word membahas satu '
               'task, jadi Anda cukup membuka file yang sesuai dengan pekerjaan Anda. Alur CBD dibahas di manual '
               'terpisah.')
    m.h('Siapa memakai apa')
    m.p('Setiap orang mendapat satu role dari System Admin. Role menentukan menu yang muncul dan tombol yang bisa '
        'diklik. Di bagian atas setiap manual tertulis role yang mengerjakan task tersebut.')
    m.table(['Role (nama di layar)', 'Tugas utama di manual ini'], [
        ['**Vendor - Specsheet**', 'Mengisi supplier, komponen, pilihan dropdown, material dan varian, membuat model '
         'dan article, lalu menyusun dan menerbitkan specsheet.'],
        ['**Vendor - CBD**', 'Mengajukan harga material (dibahas di manual 17). Penyusunan CBD ada di manual CBD.'],
        ['**Manager Costing**', 'Menyetujui atau menolak usulan harga material.'],
        ['**Brand Viewer**', 'Melihat specsheet yang sudah terbit dan mengunduhnya ke Excel.'],
        ['**System Admin**', 'Mengelola pabrik dan akun user, reset password, dan melihat Audit Log.'],
    ], [4.5, 12.0])
    m.h('Istilah yang sering muncul')
    m.table(['Istilah', 'Artinya'], [
        ['Model', 'Satu desain sepatu, misalnya RUNNER X. Nama model tidak boleh kembar di satu pabrik.'],
        ['Season', 'Musim produksi, misalnya SS27 (Spring/Summer 2027) atau FH26 (Fall/Holiday 2026).'],
        ['Article', 'Satu varian warna (colorway) dari model di season tertentu. Maksimal 5 article per season.'],
        ['Material', 'Nama bahan beserta Category dan Mea (satuan), misalnya HONEYLON MESH, satuan ME.'],
        ['Varian', 'Pecahan material per Dimension dan warna. Setiap varian punya satu Material Code.'],
        ['Material Code', 'Kode 10 karakter dari ERP: 4 karakter awal = material, 3 tengah = Dimension, '
         '3 akhir = warna.'],
        ['Dimension', 'Ukuran bahan, misalnya 1.5 MM atau 44". Bahan tanpa ukuran ditulis (None).'],
        ['Material Process', 'Material berupa proses (printing, embossing, painting). Tidak punya varian dan '
         'Material Code, sel warnanya tidak pernah kuning.'],
        ['Specsheet (BOM)', 'Daftar komponen, material, Dimension, supplier, dan warna untuk setiap article.'],
        ['Stage', 'Tahap pengembangan: Pullover, Preview, SMS, GTM, Production. Stage hanya bisa maju.'],
        ['Revisi', 'Versi specsheet di satu stage, ditulis seperti SMS r0, SMS r1.'],
        ['DRAFT', 'Revisi yang masih dikerjakan dan masih bisa diubah. Satu season hanya boleh punya satu draft.'],
        ['PUBLISHED', 'Revisi yang sudah diterbitkan. Terkunci, tidak bisa diubah atau dihapus.'],
        ['Sel kuning', 'Sel warna di specsheet yang belum punya Material Code.'],
        ['INACTIVE', 'Data yang tidak dipakai lagi. Tidak muncul di pilihan, tetapi riwayatnya tetap ada.'],
    ], [4.0, 12.5])
    m.h('Urutan kerja sampai specsheet terbit')
    m.steps(
        'System Admin membuat akun Anda (manual 05 dan 06).',
        'Anda login dan mengganti password sementara (manual 01).',
        'Vendor - Specsheet menyiapkan data master: supplier, komponen, pilihan dropdown, material, varian '
        '(manual 09 sampai 16). Data master tidak harus lengkap di awal, karena material dan supplier baru bisa '
        'ditambahkan langsung dari specsheet.',
        'Vendor - Specsheet membuat model, season, dan article (manual 19 sampai 23).',
        'Vendor - Specsheet membuat specsheet, baik dari kosong maupun copy dari season atau model lain '
        '(manual 25 sampai 27), lalu mengisi BOM (manual 29 sampai 34).',
        'Vendor - Specsheet menerbitkan specsheet (manual 35). Untuk stage berikutnya, buat revisi baru '
        '(manual 28) lalu terbitkan lagi.',
        'Setelah specsheet terbit, tim CBD mulai menyusun CBD (manual CBD).',
    )
    m.h('Cara membaca manual')
    m.bullets(
        'Tulisan **tebal** adalah teks yang tampil persis di layar, misalnya tombol **Save** atau menu '
        '**Master Material**. Tampilan aplikasi memakai bahasa Inggris.',
        'Langkah bernomor dikerjakan berurutan dari atas ke bawah.',
        'Kotak bergaris putus-putus adalah tempat screenshot tampilan layar.',
        'Kotak kuning **Penting** berisi hal yang sering terlewat.',
        'Bagian **Jika muncul pesan ini** menjelaskan pesan yang mungkin tampil dan cara mengatasinya.',
    )
    m.h('Kebiasaan yang membantu')
    m.bullets(
        'Aplikasi hanya bisa dibuka lewat jaringan kantor atau VPN.',
        'Hampir setiap daftar punya kotak cari dan tombol **Search**. Ketik sebagian nama lalu klik **Search**.',
        'Nama material, warna, kategori, dan kode otomatis disimpan dalam huruf besar.',
        'Saat menambah data baru, aplikasi menampilkan nama yang mirip. Pakai data yang sudah ada bila memang sama, '
        'supaya tidak ada data kembar.',
        'Angka ditulis tanpa titik ribuan. Pakai koma atau titik untuk desimal, misalnya 12500 atau 12500,50.',
        'Filter dan kotak cari dikosongkan setiap kali halaman dibuka dari Home. Filter tetap tersimpan bila Anda '
        'kembali dari halaman detail dengan tombol kembali.',
    )
    return m


@task
def login_pertama():
    m = Manual('01', 'Login Pertama Kali dan Mengganti Password Sementara',
               'Semua pengguna',
               '**Login**',
               'Email dan password sementara dari System Admin. Pastikan VPN atau jaringan kantor tersambung.',
               'Masuk ke aplikasi untuk pertama kali dan mengganti password sementara dengan password Anda sendiri.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka alamat aplikasi di browser (Google Chrome atau Microsoft Edge).',
        'Halaman **Login** tampil. Isi **Email** dengan email kantor Anda.',
        'Isi **Password** dengan password sementara dari System Admin.',
        ('shot', 'Halaman Login dengan kotak Email, Password, dan Remember me'),
        'Klik **Log in**.',
        'Karena memakai password sementara, aplikasi langsung membuka form **Change Password**.',
        'Isi **Old / temporary password** dengan password sementara tadi.',
        'Isi **New password**. Password baru minimal 8 karakter dan harus berbeda dari password lama.',
        'Ketik ulang password baru di **Repeat new password**.',
        ('shot', 'Form Change Password saat login pertama'),
        'Klik **Save**. Anda masuk ke halaman **Home**.',
    )
    m.note('Password sementara hanya berlaku untuk login pertama. Simpan password baru Anda baik-baik dan jangan '
           'berikan ke orang lain.')
    m.messages([
        ['Wrong email or password.', 'Email atau password salah ketik.',
         'Periksa ketikan, termasuk huruf besar dan kecil pada password. Bila tetap gagal, minta System Admin '
         'melakukan reset password.'],
        ['Pesan bahwa password baru kurang dari 8 karakter', 'Password baru terlalu pendek.',
         'Buat password minimal 8 karakter.'],
        ['Pesan bahwa password tidak sama', 'Isi New password dan Repeat new password berbeda.',
         'Ketik ulang kedua kotak dengan password yang sama.'],
    ])
    m.related('02 Login Harian dan Remember Me', '03 Mengganti Password', '04 Mengenal Home dan My Tasks')
    return m


@task
def login_harian():
    m = Manual('02', 'Login Harian dan Remember Me',
               'Semua pengguna',
               '**Login**',
               'Akun Anda sudah aktif dan password sementara sudah diganti (manual 01).',
               'Masuk ke aplikasi setiap hari, memakai pilihan Remember me dengan benar, dan keluar dengan aman.')
    m.h('Login')
    m.steps(
        'Buka alamat aplikasi. Email terakhir yang dipakai di browser ini sudah terisi.',
        'Isi **Password**.',
        'Centang **Remember me** bila Anda memakai komputer sendiri (lihat penjelasan di bawah).',
        'Klik **Log in** atau tekan Enter. Halaman **Home** terbuka.',
    )
    m.h('Arti pilihan Remember me')
    m.table(['Pilihan', 'Lama sesi'], [
        ['Dicentang', 'Anda tetap masuk selama aplikasi dibuka minimal sekali dalam 7 hari. Setelah 30 hari sejak '
         'login, Anda tetap wajib login ulang.'],
        ['Tidak dicentang', 'Sesi berakhir setelah 12 jam.'],
    ], [4.0, 12.5])
    m.note('Jangan centang Remember me di komputer yang dipakai bersama.')
    m.h('Keluar dari aplikasi')
    m.steps(
        'Klik **Log out** di header bagian atas halaman.',
        'Halaman **Login** tampil kembali.',
    )
    m.messages([
        ['Session expired. Please log in again.', 'Sesi habis, atau akun Anda baru saja diubah atau direset oleh '
         'System Admin.', 'Login ulang.'],
        ['Wrong email or password.', 'Email atau password salah.', 'Periksa ketikan. Bila lupa password, hubungi '
         'System Admin untuk reset (manual 07).'],
    ])
    m.related('01 Login Pertama Kali dan Mengganti Password Sementara', '03 Mengganti Password')
    return m


@task
def ganti_password():
    m = Manual('03', 'Mengganti Password',
               'Semua pengguna',
               'Header di semua halaman, tombol **Change Password**',
               'Anda sudah login.',
               'Mengganti password kapan saja, misalnya bila password pernah dilihat orang lain.')
    m.h('Langkah-langkah')
    m.steps(
        'Klik **Change Password** di header bagian atas halaman.',
        ('shot', 'Header dengan tombol Home, Change Password, dan Log out'),
        'Isi **Old / temporary password** dengan password yang sekarang.',
        'Isi **New password** (minimal 8 karakter, berbeda dari password lama).',
        'Ketik ulang di **Repeat new password**.',
        'Klik **Save**.',
    )
    m.note('Lupa password lama? Anda tidak bisa menggantinya sendiri. Minta System Admin melakukan Reset Password, '
           'lalu login dengan password sementara yang diberikan (manual 01).')
    m.related('01 Login Pertama Kali dan Mengganti Password Sementara', '07 Mengubah User dan Reset Password')
    return m


@task
def home():
    m = Manual('04', 'Mengenal Home dan My Tasks',
               'Semua pengguna',
               '**Home**',
               'Anda sudah login.',
               'Memahami isi halaman Home, membuka menu, dan memakai My Tasks sebagai daftar pekerjaan harian.')
    m.h('Bagian halaman Home')
    m.p('Home adalah halaman pertama setelah login. Isinya:')
    m.bullets(
        '**Menu**: kartu menu sesuai role Anda, misalnya Master Data, Model, Specsheet & CBD, Price Approval, '
        'atau Admin.',
        '**My Tasks**: daftar pekerjaan yang menunggu Anda, lengkap dengan angka ringkasan di bagian atas.',
    )
    m.shot('Halaman Home: kartu Menu di atas, My Tasks di bawah')
    m.h('Membuka pekerjaan dari My Tasks')
    m.steps(
        'Lihat angka ringkasan di atas My Tasks. Klik angka untuk melompat ke bagiannya.',
        'Klik satu baris tugas. Aplikasi langsung membuka halaman yang dimaksud, misalnya specsheet draft.',
        'Bila daftar panjang, klik tombol tampilkan semua di bawah bagian tersebut.',
        'Klik **Reload** untuk memperbarui daftar setelah Anda menyelesaikan pekerjaan.',
    )
    m.h('Isi My Tasks per role')
    m.table(['Role', 'Bagian yang muncul'], [
        ['Vendor - Specsheet', '**Specsheet Drafts** (draft yang belum terbit beserta tanda masalahnya), '
         '**Articles Not in a Specsheet**, **Articles Without Article No.**'],
        ['Vendor - CBD', 'Pekerjaan CBD dan harga material, termasuk **Missing Master Prices** dan '
         '**Rejected Price Proposals**.'],
        ['Manager Costing', 'Usulan harga yang menunggu persetujuan.'],
        ['Brand Viewer', '**Latest Published Specsheets** dan **Latest Published CBDs**.'],
        ['System Admin', '**System Summary** (jumlah model, specsheet, CBD, user aktif, ukuran audit log).'],
    ], [4.0, 12.5])
    m.h('Header dan navigasi')
    m.bullets(
        '**Home**: kembali ke halaman Home dari halaman mana pun.',
        '**Change Password**: mengganti password (manual 03).',
        '**Log out**: keluar dari aplikasi.',
        'Tombol dengan tanda panah kiri, misalnya **← Model List**, membawa Anda kembali ke halaman sebelumnya '
        'dengan filter yang masih tersimpan.',
    )
    m.messages([
        ['Role ... has no access to this page.', 'Halaman itu bukan untuk role Anda.',
         'Buka menu dari Home. Bila role Anda keliru, hubungi System Admin.'],
    ])
    m.related('00 Baca Dulu Sebelum Memakai Manual')
    return m


@task
def pabrik():
    m = Manual('05', 'Menambah dan Mengubah Pabrik',
               'System Admin',
               '**Admin**, tab **Factory**',
               'Nama pabrik yang akan didaftarkan.',
               'Mendaftarkan pabrik baru, mengganti nama pabrik, atau menonaktifkan pabrik yang tidak dipakai lagi. '
               'Pabrik harus ada sebelum user vendor bisa dibuat.')
    m.h('Menambah pabrik')
    m.steps(
        'Dari Home, buka menu **Admin**, lalu klik tab **Factory**.',
        'Klik **+ Add Factory**.',
        'Isi **Factory name**.',
        'Pastikan **Status** = ACTIVE.',
        ('shot', 'Tab Factory dan form Add Factory'),
        'Klik **Save**. Pabrik muncul di tabel.',
    )
    m.h('Mengubah atau menonaktifkan pabrik')
    m.steps(
        'Di tab **Factory**, klik **Edit** pada baris pabrik.',
        'Ganti **Factory name** atau ubah **Status** menjadi INACTIVE.',
        'Klik **Save**.',
    )
    m.note('Pabrik tidak bisa dinonaktifkan selama masih punya user aktif. Nonaktifkan atau pindahkan user-nya '
           'terlebih dahulu (manual 07).')
    m.related('06 Menambah User Baru', '07 Mengubah User dan Reset Password')
    return m


@task
def user_baru():
    m = Manual('06', 'Menambah User Baru',
               'System Admin',
               '**Admin**, tab **User**',
               'Email kantor, nama lengkap, role, dan pabrik user. Pabrik sudah terdaftar (manual 05).',
               'Membuat akun untuk pengguna baru dan memberikan password sementara.')
    m.h('Langkah-langkah')
    m.steps(
        'Dari Home, buka menu **Admin**, tab **User**.',
        'Klik **+ Add User**.',
        'Isi **Email**. Email tidak bisa diubah setelah disimpan, jadi periksa ketikannya.',
        'Isi **Full name**.',
        'Pilih **Role** sesuai pekerjaan user (lihat tabel di bawah).',
        'Untuk Vendor - Specsheet, Vendor - CBD, dan Manager Costing, pilih **Factory**. Brand Viewer dan System '
        'Admin tidak perlu pabrik.',
        ('shot', 'Form Add User'),
        'Klik **Save**. Kotak **Temporary Password** tampil.',
        'Klik **Copy**, lalu berikan password itu ke user lewat jalur yang aman.',
        ('shot', 'Kotak Temporary Password setelah user disimpan'),
    )
    m.table(['Role', 'Untuk siapa'], [
        ['Vendor - Specsheet', 'Tim pabrik yang menyusun data master, model, dan specsheet.'],
        ['Vendor - CBD', 'Tim pabrik yang menyusun CBD dan mengajukan harga material.'],
        ['Manager Costing', 'Orang pabrik yang menyetujui harga material.'],
        ['Brand Viewer', 'Tim brand yang hanya melihat dokumen terbit.'],
        ['System Admin', 'Pengelola akun dan sistem.'],
    ], [4.5, 12.0])
    m.note('Password sementara hanya tampil sekali. Bila terlewat, lakukan Reset Password (manual 07). User wajib '
           'mengganti password ini saat login pertama.')
    m.related('07 Mengubah User dan Reset Password', '01 Login Pertama Kali dan Mengganti Password Sementara')
    return m


@task
def ubah_user():
    m = Manual('07', 'Mengubah User dan Reset Password',
               'System Admin',
               '**Admin**, tab **User**',
               'User yang akan diubah sudah terdaftar.',
               'Mengubah nama, role, pabrik, atau status user, dan membuat password sementara baru untuk user yang '
               'lupa password.')
    m.h('Mengubah data user')
    m.steps(
        'Buka **Admin**, tab **User**. Cari user di tabel.',
        'Klik **Edit** pada baris user.',
        'Ubah **Full name**, **Role**, **Factory**, atau hilangkan centang **Active** untuk menonaktifkan.',
        'Klik **Save**.',
    )
    m.h('Reset password')
    m.steps(
        'Di tab **User**, klik **Reset Password** pada baris user.',
        'Kotak **Temporary Password** tampil. Klik **Copy** dan berikan ke user.',
        'User login dengan password sementara itu dan langsung diminta membuat password baru.',
    )
    m.note('Reset password, perubahan role, perubahan pabrik, atau penonaktifan langsung mengeluarkan user tersebut '
           'dari semua perangkat. Email tidak bisa diubah, dan Anda tidak bisa mengubah role dan status akun Anda '
           'sendiri.')
    m.related('06 Menambah User Baru', '08 Melihat Audit Log')
    return m


@task
def audit_log():
    m = Manual('08', 'Melihat Audit Log',
               'System Admin',
               '**Admin**, tab **Audit Log**',
               'Tidak ada',
               'Mencari tahu siapa mengubah data apa dan kapan, misalnya saat ada pertanyaan tentang perubahan '
               'material atau specsheet.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka **Admin**, tab **Audit Log**.',
        'Pilih jenis data di filter (pilihan awal **All entities**) dan/atau ketik kata kunci di kotak '
        '**Search email / action / ID**.',
        'Klik **Search**. Tabel menampilkan catatan terbaru (90 hari terakhir, maksimal 200 baris).',
        'Klik satu baris. Panel kanan menampilkan detailnya.',
        ('shot', 'Tab Audit Log dengan panel detail di kanan'),
    )
    m.table(['Jenis catatan', 'Yang ditampilkan'], [
        ['UPDATE', 'Hanya kolom yang berubah: nilai lama (merah, dicoret) dan nilai baru (hijau).'],
        ['INSERT', 'Keterangan bahwa data dibuat.'],
        ['DELETE', 'Isi lengkap data yang dihapus.'],
    ], [4.0, 12.5])
    m.p('Klik **Show technical fields** bila perlu melihat kolom teknis seperti waktu dibuat dan pembuatnya. '
        'Password tidak pernah tampil di Audit Log.')
    m.related('07 Mengubah User dan Reset Password')
    return m
