# R15 kamus bagian D: Custom Widget form sederhana + teks umum widget.


def load(T, KEEP):
    T['*'].update({
        'Simpan': 'Save',
        'Menyimpan…': 'Saving…',
        'Batal': 'Cancel',
        'Tutup': 'Close',
        'Status': 'Status',
        ' wajib diisi.': ' is required.',
        'Nama pabrik wajib diisi.': 'Factory name is required.',
        'Isi email dan password.': 'Enter email and password.',
        'Isi password lama dan password baru.': 'Enter the old and new password.',
        'Nilai wajib diisi.': 'Value is required.',
        'Alasan': 'Reason',
        'nama@perusahaan.com': 'name@company.com',
    })
    T['widgets/cwArticleForm/script.js'] = {
        'Ubah Article': 'Edit Article',
        'Tambah Article': 'Add Article',
        ' · article ke-': ' · article no. ',
        'Kode article': 'Article code',
    }
    T['widgets/cwArticleForm/index.html'] = {
        'Tambah Article': 'Add Article',
        'Kode Article': 'Article Code',
        'Kode tidak bisa diubah karena article sudah dipakai di specsheet/CBD.': 'The code cannot be changed because the article is used in a specsheet/CBD.',
        'mis. GY1234': 'e.g. GY1234',
        'mis. Core Black / Cloud White': 'e.g. Core Black / Cloud White',
    }
    T['widgets/cwSupplierForm/script.js'] = {'Ubah Supplier': 'Edit Supplier', 'Tambah Supplier': 'Add Supplier'}
    T['widgets/cwSupplierForm/index.html'] = {
        'Tambah Supplier': 'Add Supplier',
        'Nama supplier': 'Supplier name',
        'Nama yang hanya beda huruf besar/kecil atau spasi dianggap sama.': 'Names that differ only in case or spaces are treated as the same.',
        'Supplier dengan nama mirip sudah ada — pakai yang ini bila sama:': 'A supplier with a similar name exists. Use it if it is the same:',
        'Supplier dipakai bersama semua pabrik dan langsung bisa dipilih.': 'Suppliers are shared by all factories and can be selected right away.',
        'Nama tidak bisa diubah bila supplier sudah dipakai di dokumen terbit. INACTIVE ditolak selama masih dipakai di draft.':
            'The name cannot be changed once the supplier is used in a published document. INACTIVE is refused while it is used in a draft.',
        'mis. PT Maju Jaya': 'e.g. PT Maju Jaya',
    }
    T['widgets/cwKomponenForm/script.js'] = {
        'Pilih kelompok dulu.': 'Select a group first.',
        'Rentang ': 'Range ',
        ', kelipatan 10.': ', multiples of 10.',
        ' Rentang kelompok ini sudah penuh.': ' This group range is full.',
        ' Saran nomor berikutnya: ': ' Suggested next number: ',
        'Ubah Komponen': 'Edit Component',
        'Tambah Komponen': 'Add Component',
        '— Pilih kelompok —': 'Select group',
        'Kelompok wajib dipilih.': 'Group is required.',
        'Nomor wajib diisi dengan angka bulat.': 'Number must be a whole number.',
        'Nomor komponen harus kelipatan 10.': 'Component number must be a multiple of 10.',
        'Nomor harus berada di rentang ': 'Number must be in the range ',
        ' untuk kelompok ': ' for group ',
        'Nama komponen wajib diisi.': 'Component name is required.',
    }
    T['widgets/cwKomponenForm/index.html'] = {
        'Tambah Komponen': 'Add Component',
        'Kelompok': 'Group',
        'Nomor': 'Number',
        'Pakai saran': 'Use suggestion',
        'Nama komponen': 'Component name',
        'Komponen dengan nama mirip sudah ada — pakai yang ini bila sama:': 'A component with a similar name exists. Use it if it is the same:',
        'Komponen dipakai bersama semua pabrik dan langsung bisa dipilih.': 'Components are shared by all factories and can be selected right away.',
        'Nama, nomor, dan kelompok tidak bisa diubah bila komponen sudah dipakai di dokumen terbit. INACTIVE ditolak selama masih dipakai di draft.':
            'Name, number, and group cannot be changed once the component is used in a published document. INACTIVE is refused while it is used in a draft.',
        'mis. Vamp': 'e.g. Vamp',
    }
    T['widgets/cwFactoryForm/script.js'] = {'Ubah Pabrik': 'Edit Factory', 'Tambah Pabrik': 'Add Factory'}
    T['widgets/cwFactoryForm/index.html'] = {
        'Tambah Pabrik': 'Add Factory',
        'Nama pabrik': 'Factory name',
        'Pabrik tidak bisa dinonaktifkan selama masih punya user aktif.': 'A factory cannot be set inactive while it has active users.',
        'mis. PT PRESTASI': 'e.g. PT PRESTASI',
    }
    T['widgets/cwUserForm/script.js'] = {
        '— Pilih role —': 'Select role',
        '— Pilih pabrik —': 'Select factory',
        'Ubah User': 'Edit User',
        'Tambah User': 'Add User',
        'Format email tidak valid.': 'Invalid email format.',
        'Nama lengkap wajib diisi.': 'Full name is required.',
        'Role wajib dipilih.': 'Role is required.',
        'Pilih pabrik untuk role ini.': 'Select a factory for this role.',
    }
    T['widgets/cwUserForm/index.html'] = {
        'Tambah User': 'Add User',
        'Email tidak bisa diubah.': 'Email cannot be changed.',
        'Nama lengkap': 'Full name',
        'Vendor Spec, Vendor CBD, dan Manager Costing hanya melihat data pabriknya.': 'Vendor Spec, Vendor CBD, and Manager Costing only see their factory data.',
        'Role dan status akun sendiri tidak bisa diubah.': 'You cannot change your own role and status.',
        'Password sementara dibuat otomatis dan ditampilkan setelah disimpan.': 'A temporary password is created and shown after saving.',
    }
    T['widgets/cwTempPassword/script.js'] = {'Salin': 'Copy', 'Disalin ✓': 'Copied ✓'}
    T['widgets/cwTempPassword/index.html'] = {
        'Password Sementara': 'Temporary Password',
        'Untuk': 'For',
        'Berikan ke user. Password ini': 'Give it to the user. This password is',
        'hanya ditampilkan sekali': 'shown only once',
        ';\n    user wajib menggantinya saat login pertama.': ';\n    the user must change it at first login.',
        'Salin': 'Copy',
    }
    T['widgets/cwLogin/script.js'] = {
        'Memproses…': 'Processing…',
        'Masuk': 'Log in',
        'Keluar': 'Log out',
        'Anda masuk dengan password sementara. Buat password baru (minimal 8 karakter) sebelum melanjutkan.':
            'You logged in with a temporary password. Create a new password (at least 8 characters) to continue.',
        'Minimal 8 karakter.': 'At least 8 characters.',
        'Password baru minimal 8 karakter.': 'New password must be at least 8 characters.',
        'Konfirmasi password baru tidak sama.': 'New password confirmation does not match.',
        'Password baru harus berbeda dari password lama.': 'New password must differ from the old one.',
        'Sembunyikan': 'Hide',
        'Lihat': 'Show',
    }
    T['widgets/cwLogin/index.html'] = {
        'Sistem Specsheet &amp; CBD': 'Specsheet &amp; CBD System',
        'Masuk': 'Log in',
        'Lihat': 'Show',
        'Lupa password? Hubungi System Admin.': 'Forgot password? Contact the System Admin.',
        'Ganti Password': 'Change Password',
        'Minimal 8 karakter.': 'At least 8 characters.',
        'Password lama / sementara': 'Old / temporary password',
        'Password baru': 'New password',
        'Ulangi password baru': 'Repeat new password',
    }
    T['widgets/cwReasonForm/script.js'] = {' wajib diisi (min. ': ' is required (min. ', ' karakter).': ' characters).'}
    T['widgets/cwSeasonForm/script.js'] = {
        'Pilih musim dan isi 2 digit tahun.': 'Select a season and enter a 2-digit year.',
        ' sudah ada untuk model ini.': ' already exists for this model.',
        'Season yang sudah ada: ': 'Existing seasons: ',
        'Belum ada season untuk model ini.': 'This model has no seasons yet.',
        'Pilih musim SS atau FH.': 'Select SS or FH.',
        'Tahun harus 2 digit angka, mis. 26.': 'Year must be 2 digits, e.g. 26.',
    }
    T['widgets/cwSeasonForm/index.html'] = {
        'Season Baru': 'New Season',
        'Musim': 'Season type',
        'Tahun (2 digit)': 'Year (2 digits)',
        'mis. 26': 'e.g. 26',
    }
    T['widgets/cwOptionForm/script.js'] = {
        'Ubah': 'Edit',
        'Tambah': 'Add',
        'Pilihan': 'Option',
        'Berlaku untuk pabrik Anda saja': 'Applies to your factory only',
        'Dipakai bersama semua pabrik.': 'Shared by all factories.',
        'mis. 40 (angka bulat)': 'e.g. 40 (whole number)',
        'Ukuran harus angka bulat (mis. 40), tanpa setengah ukuran.': 'Size must be a whole number (e.g. 40), no half sizes.',
        'Urutan harus angka bulat.': 'Order must be a whole number.',
    }
    T['widgets/cwOptionForm/index.html'] = {
        'Tambah Pilihan': 'Add Option',
        'Jenis': 'Type',
        'Nilai': 'Value',
        'Pilihan mirip sudah ada — pakai yang ini bila sama:': 'A similar option exists. Use it if it is the same:',
        'Urutan': 'Order',
        'opsional': 'optional',
    }
    KEEP |= {'--primary', '--radius', 'System Default', '--font', ', "Segoe UI", Arial, sans-serif', 'msg ', 'Enter',
             'Colorway', 'ACTIVE', 'INACTIVE', 'Email', 'Role', 'SC', 'Master Data · Specsheet · CBD', 'Password',
             '#half button', 'btn-primary btn-danger', 'SS · Spring/Summer', 'FH · Fall/Holiday'}
