# Isi manual task: model, season, article, lampiran.
from engine import Manual

FOLDER = '3 Model dan Article'
TASKS = []


def task(fn):
    TASKS.append(fn)
    return fn


@task
def model_baru():
    m = Manual('19', 'Membuat Model Baru',
               'Vendor - Specsheet',
               '**Model List**',
               'Pilihan Category, Gender, Construction, Last, Outsole mold, dan Size sudah ada di Master Options '
               '(manual 11).',
               'Mendaftarkan desain sepatu baru beserta data dasarnya.')
    m.h('Langkah-langkah')
    m.steps(
        'Dari Home, buka menu **Model, Specsheet & CBD**. Halaman **Model List** terbuka.',
        'Cari dulu nama model di kotak **Search code / model name...** untuk memastikan belum ada.',
        'Klik **+ Add Model**.',
        'Isi **Model Name**. Nama model tidak boleh sama dengan model lain di pabrik Anda.',
        'Pilih **Category**, **Gender**, **Construction**, **Last No.**, dan **Outsole Mould**.',
        'Pilih ukuran di **Size**: klik ukuran pertama, lalu klik ukuran terakhir untuk memilih rentang. Klik '
        'ukuran yang sudah terpilih untuk membuangnya, atau **Clear** untuk mengulang.',
        'Pilih **Sample Size** dari ukuran yang sudah terpilih.',
        ('shot', 'Form Add Model dengan pemilih ukuran'),
        'Klik **Save**. Model muncul di Model List.',
    )
    m.note('Semua kolom wajib diisi. Bila pilihan yang Anda cari belum ada di dropdown, tambahkan dulu di Master '
           'Options (manual 11).')
    m.messages([
        ['Category is required. (begitu juga Gender, Construction, Last No., Outsole Mould, Sample Size)',
         'Kolom tersebut masih kosong.', 'Isi kolom yang disebut, lalu Save lagi.'],
        ['At least one size is required.', 'Belum ada ukuran yang dipilih. Kotak ukuran bergaris merah.',
         'Pilih minimal satu ukuran.'],
    ])
    m.related('20 Mengubah Data Model', '21 Menambah Season', '22 Menambah dan Mengubah Article')
    return m


@task
def ubah_model():
    m = Manual('20', 'Mengubah Data Model',
               'Vendor - Specsheet',
               '**Model Detail**, tab **Model Info**',
               'Model sudah terdaftar.',
               'Memperbaiki data dasar model, misalnya Last, Outsole Mould, atau rentang ukuran.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka **Model List**, cari model, klik **Open** pada barisnya. Halaman **Model Detail** terbuka.',
        'Buka tab **Model Info**.',
        'Klik **Edit Model**.',
        'Ubah data yang perlu. Semua kolom tetap wajib diisi.',
        ('shot', 'Tab Model Info dan form Edit Model'),
        'Klik **Save**.',
    )
    m.note('Model lama yang datanya belum lengkap harus dilengkapi dulu sebelum perubahan bisa disimpan.',
           kind='Info')
    m.related('19 Membuat Model Baru')
    return m


@task
def season():
    m = Manual('21', 'Menambah Season',
               'Vendor - Specsheet',
               '**Model Detail**, tab **Season & Article**',
               'Model sudah terdaftar.',
               'Menambahkan musim produksi (misalnya SS27) ke sebuah model. Article dan specsheet selalu dibuat per '
               'season.')
    m.h('Langkah-langkah')
    m.steps(
        'Buka model di **Model Detail** (dari Model List, klik **Open**).',
        'Di tab **Season & Article**, klik **+ New Season**.',
        'Pilih **Season type**: SS (Spring/Summer) atau FH (Fall/Holiday).',
        'Isi **Year (2 digits)**, misalnya 27 untuk tahun 2027.',
        ('shot', 'Form New Season'),
        'Klik **Save**. Season baru langsung terpilih di dropdown season.',
    )
    m.note('Satu model tidak bisa punya dua season yang sama. Untuk berpindah season, pilih dari dropdown season '
           'di tab Season & Article.', kind='Info')
    m.related('22 Menambah dan Mengubah Article', '25 Membuat Specsheet Baru dari Kosong')
    return m


@task
def article():
    m = Manual('22', 'Menambah dan Mengubah Article',
               'Vendor - Specsheet',
               '**Model Detail**, tab **Season & Article**',
               'Season sudah ada (manual 21).',
               'Menambahkan colorway (article) ke season, memperbaiki nomor article, atau menghapus article yang '
               'belum dipakai.')
    m.h('Menambah article')
    m.steps(
        'Buka model di **Model Detail**, tab **Season & Article**.',
        'Pilih season di dropdown season.',
        'Klik **+ Article**. Angka di tombol menunjukkan jumlah article di season itu.',
        'Isi **Article No.** bila sudah ada. Boleh dikosongkan di tahap awal.',
        'Isi **Colorway**, misalnya BLACK/WHITE.',
        ('shot', 'Form Add Article'),
        'Klik **Save**. Ulangi untuk setiap colorway.',
    )
    m.h('Aturan nomor article')
    m.table(['Stage specsheet', 'Article tanpa nomor'], [
        ['Pullover, Preview', 'Boleh, tanpa peringatan.'],
        ['SMS, GTM', 'Boleh, tetapi muncul peringatan saat terbit.'],
        ['Production', 'Tidak boleh. Specsheet Production tidak bisa terbit sebelum semua article punya nomor.'],
    ], [5.0, 11.5])
    m.p('Article tanpa nomor ditampilkan sebagai **(no article no.)** dan muncul di My Tasks pada bagian '
        '**Articles Without Article No.**')
    m.h('Mengubah article')
    m.steps(
        'Klik **Edit** pada baris article.',
        'Isi atau perbaiki **Article No.** dan **Colorway**.',
        'Klik **Save**.',
    )
    m.h('Menghapus article')
    m.steps(
        'Klik **Delete** pada baris article, lalu konfirmasi.',
    )
    m.h('Yang perlu diperhatikan')
    m.bullets(
        'Satu season maksimal 5 article.',
        'Dua article tanpa nomor tidak boleh punya colorway yang sama.',
        'Nomor article yang salah ketik masih bisa diperbaiki sampai article masuk specsheet atau CBD Production '
        'yang terbit. Setelah itu nomor terkunci.',
        'Nomor yang sudah terisi tidak bisa dikosongkan lagi bila article sudah dipakai. Ketik nomor yang benar.',
        'Article yang sudah dipakai di specsheet atau CBD tidak bisa dihapus. Keluarkan dari specsheet dengan Drop '
        '(manual 34).',
    )
    m.messages([
        ['An article without article no. with colorway ... already exists ...', 'Sudah ada article tanpa nomor '
         'dengan colorway yang sama.', 'Isi nomor article, atau pakai article yang sudah ada.'],
        ['Article no. ... cannot be cleared because the article is used ...', 'Nomor tidak boleh dikosongkan.',
         'Ketik nomor yang benar.'],
    ])
    m.related('23 Mengunggah Lampiran Article', '34 Menambah atau Mengeluarkan Article dari Revisi')
    return m


@task
def lampiran():
    m = Manual('23', 'Mengunggah Lampiran Article',
               'Vendor - Specsheet',
               '**Model Detail**, tab **Season & Article**',
               'Article sudah ada. File gambar (JPG, PNG) atau PDF maksimal 3,5 MB.',
               'Menyimpan gambar atau dokumen pendukung article, misalnya foto sample atau gambar teknik.')
    m.h('Mengunggah file')
    m.steps(
        'Buka model di **Model Detail**, tab **Season & Article**, pilih season.',
        'Klik **Attachments** pada baris article.',
        'Isi catatan di kotak **Note** bila perlu. Catatan harus diisi sebelum memilih file.',
        'Klik **Choose & upload file**, lalu pilih file. File langsung terunggah.',
        ('shot', 'Jendela Attachments dengan daftar file'),
    )
    m.h('Melihat, mengunduh, dan menghapus')
    m.bullets(
        '**View**: menampilkan gambar di bawah daftar. File PDF akan terunduh.',
        '**Download**: mengunduh file ke komputer.',
        '**Delete**: menghapus lampiran.',
    )
    m.related('22 Menambah dan Mengubah Article')
    return m
