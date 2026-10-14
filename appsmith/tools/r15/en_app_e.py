# R15 kamus bagian E: widget material / model / varian / header / menu / stepper / worklist / galeri.


def load(T, KEEP):
    T['*'].update({
        'gambar': 'image',
        'mengunduh': 'downloading',
        'lokal': 'local',
        'kosong': 'empty',
        'Tugas Saya': 'My Tasks',
        'Sistem Specsheet &amp; CBD': 'Specsheet &amp; CBD System',
        'Ganti Password': 'Change Password',
        'Keluar': 'Log out',
        'Warna': 'Color',
        'tanpa thickness': 'no thickness',
        'Nama Model': 'Model Name',
    })
    T['widgets/cwMaterialForm/script.js'] = {
        'Harga diambil dari master harga per varian × supplier (diajukan tim CBD).': 'Prices come from master prices per variant × supplier (proposed by the CBD team).',
        'Material proses (printing, molding, dst.): tidak ada harga master, harga diisi per CBD.':
            'Process material (printing, molding, etc.): no master price. The price is entered per CBD.',
        'Ubah Material': 'Edit Material',
        'Tambah Material': 'Add Material',
        'Data material diubah tim specsheet (Vendor Spec).': 'Material data is edited by the specsheet team (Vendor Spec).',
        'Metode harga ditentukan tim CBD (default Catalog).': 'The price method is set by the CBD team (default Catalog).',
        'Nama material': 'Material name',
    }
    T['widgets/cwMaterialForm/index.html'] = {
        'Tambah Material': 'Add Material',
        'Nama material': 'Material name',
        'Tanpa thickness &amp; warna — keduanya diisi per varian. Nama + Mea yang sama di pabrik Anda dianggap material yang sama.':
            'No thickness &amp; color here. Both are set per variant. The same Name + Mea in your factory is the same material.',
        'Material dengan nama mirip sudah ada di pabrik Anda — tambahkan varian di sana bila sama:':
            'A material with a similar name exists in your factory. Add the variant there if it is the same:',
        'Metode harga': 'Price method',
        'Setelah disimpan, halaman Material Detail terbuka untuk menambah varian (thickness × warna → Material Code).':
            'After saving, the Material Detail page opens to add variants (thickness × color → Material Code).',
        'mis. Leather': 'e.g. Leather',
        'mis. SYNTHETIC LEATHER PU': 'e.g. SYNTHETIC LEATHER PU',
    }
    T['widgets/cwLinkForm/script.js'] = {
        'Ubah Supplier Material': 'Edit Material Supplier',
        'Tambah Supplier Material': 'Add Material Supplier',
        '— Pilih supplier —': 'Select supplier',
        '— Semua supplier sudah terdaftar —': 'All suppliers are already added',
        'Supplier utama diatur tim specsheet.': 'The main supplier is set by the specsheet team.',
        'Pilih supplier.': 'Select a supplier.',
    }
    T['widgets/cwLinkForm/index.html'] = {
        'Tambah Supplier Material': 'Add Material Supplier',
        'Supplier harus sudah ada di Master Supplier.': 'The supplier must exist in Master Supplier.',
        'Supplier utama (otomatis terisi di BOM saat material dipilih)': 'Main supplier (filled in the BOM when the material is selected)',
        'Supplier langsung terhubung ke material ini (semua varian). Harga per varian diajukan tim CBD.':
            'The supplier is linked to this material (all variants). Prices per variant are proposed by the CBD team.',
    }
    T['widgets/cwModelForm/script.js'] = {
        ' ukuran)': ' sizes)',
        'Belum dipilih': 'None selected',
        '— pilih —': 'Select',
        '— pilih ukuran dulu —': 'Select sizes first',
        'Ubah Model': 'Edit Model',
        'Tambah Model': 'Add Model',
        '— pilih kategori —': 'Select category',
        '— kosong —': 'None',
        'Nama model wajib diisi.': 'Model name is required.',
        'Kategori wajib dipilih.': 'Category is required.',
    }
    T['widgets/cwModelForm/index.html'] = {
        'Tambah Model': 'Add Model',
        'Belum dipilih': 'None selected',
        'Kosongkan': 'Clear',
        'Klik ukuran awal lalu ukuran akhir untuk memilih rentang. Klik ukuran terpilih untuk membuangnya.':
            'Click the first size, then the last size to select a range. Click a selected size to remove it.',
        'Nama model unik di pabrik Anda. Pilihan dropdown baru ditambah di Master Pilihan.':
            'The model name is unique in your factory. New dropdown options are added in Master Options.',
        'Pilih ukuran': 'Select sizes',
    }
    T['widgets/cwVariantForm/script.js'] = {
        'Dari sel specsheet.': 'From the specsheet cell.',
        'Dari baris specsheet.': 'From the specsheet line.',
        ' Kode ': ' Code ',
        ' tercatat = ': ' is recorded as ',
        'Kode ': 'Code ',
        ' (tercatat di ': ' (recorded in ',
        'warna': 'color',
        ' baru — berikutnya terisi otomatis.': ' is new. It fills in automatically next time.',
        'Usulan dari kode yang sudah tercatat — cocokkan dengan ERP sebelum simpan:': 'Suggested from recorded codes. Check against ERP before saving:',
        'Awalan material': 'Material prefix',
        'belum ada varian lain di material ini — ketik 4 karakter': 'no other variants in this material yet. Type 4 characters',
        'belum pernah dipakai — ketik 3 karakter': 'never used yet. Type 3 characters',
        'warna baru — ketik 3 karakter terakhir': 'new color. Type the last 3 characters',
        '(kode lain: ': '(other codes: ',
        'Kode thickness ': 'Thickness code ',
        ' sudah tercatat sebagai ': ' is already recorded as ',
        ' (kode ': ' (code ',
        '), bukan ': '), not ',
        'Kode warna ': 'Color code ',
        'Material Code ERP biasanya 10 karakter (sekarang ': 'ERP Material Codes are usually 10 characters (now ',
        'Awalan ': 'Prefix ',
        ' berbeda dari varian lain di material ini (': ' differs from other variants of this material (',
        ' biasanya berkode ': ' usually has code ',
        ' — pastikan ': '. Make sure ',
        ' sesuai ERP.': ' matches ERP.',
        'Warna ': 'Color ',
        ' Periksa Material Code di ERP.': ' Check the Material Code in ERP.',
        'Ubah Varian': 'Edit Variant',
        'Tambah Varian': 'Add Variant',
        'Material Code dan warna wajib diisi.': 'Material Code and color are required.',
        'Material Code bertentangan dengan kode yang sudah tercatat. Periksa kodenya, atau centang konfirmasi bila memang sesuai ERP.':
            'The Material Code conflicts with recorded codes. Check the code, or tick the confirmation if it matches ERP.',
    }
    T['widgets/cwVariantForm/index.html'] = {
        'Tambah Varian': 'Add Variant',
        'Kode ERP 10 karakter: 4 jenis material · 3 thickness · 3 warna. Terisi otomatis dari warna &amp; thickness bila bagian kodenya sudah pernah dipakai (atau sebaliknya) — tetap cocokkan dengan ERP.':
            '10-character ERP code: 4 material type · 3 thickness · 3 color. Filled in from color &amp; thickness when those code parts were used before (or the other way round). Still check against ERP.',
        'Sudah saya cek, kode ini benar sesuai ERP': 'I checked it. This code matches ERP',
        'Simpan &amp; tambah lagi': 'Save &amp; add another',
        'mis. 205Q404A52 (dari ERP)': 'e.g. 205Q404A52 (from ERP)',
        'mis. WHITE': 'e.g. WHITE',
        'persis ERP, mis. 44&quot; atau 1.2MMX54&quot; — kosong / . = tidak ada': 'exactly as ERP, e.g. 44&quot; or 1.2MMX54&quot;. Empty / . = none',
    }
    T['widgets/cwMenu/script.js'] = {
        '</p>\n      <span class="open">Buka <span aria-hidden="true">→</span></span>':
            '</p>\n      <span class="open">Open <span aria-hidden="true">→</span></span>',
    }
    T['widgets/cwMenu/index.html'] = {
        'Pilih menu sesuai pekerjaan Anda.': 'Choose a menu for your work.',
        'Role Anda belum punya menu. Hubungi System Admin.': 'Your role has no menu yet. Contact the System Admin.',
    }
    T['widgets/cwStepper/script.js'] = {
        'DRAFT (belum terbit)': 'DRAFT (not published)',
        ' · perlu revisi': ' · needs revision',
    }
    T['widgets/cwStepper/index.html'] = {'Stage revisi': 'Revision stages'}
    T['widgets/cwWorklist/script.js'] = {
        'Tidak ada.': 'None.',
        'Tampilkan lebih sedikit': 'Show less',
        'Tampilkan semua (': 'Show all (',
        '↻ Muat ulang': '↻ Reload',
    }
    T['widgets/cwWorklist/index.html'] = {
        '↻ Muat ulang': '↻ Reload',
        'Belum ada tugas untuk role Anda.': 'No tasks for your role yet.',
        'Muat ulang daftar tugas': 'Reload the task list',
    }
    T['widgets/cwImageGallery/script.js'] = {
        ' gambar': ' image(s)',
        'Memuat gambar…': 'Loading images…',
        'Tidak ada gambar.': 'No images.',
        'Klik untuk memperbesar': 'Click to enlarge',
    }
    T['widgets/cwImageGallery/index.html'] = {'Unduh': 'Download', 'Sebelumnya': 'Previous', 'Berikutnya': 'Next'}
    KEEP |= {'#method button', 'Mea (UoM)', 'Catalog', 'Quotation', 'YD / KG / PCS', ' on', ' anchor', '#sizes .size',
             'Note', 'Thickness ', 'Material Code', 'Menu', ' active', 'badge ', ' current', ' draft', ' needs', 'Article',
             ' title="', 'Only technical fields.', 'Hide', 'Show', ' technical fields (', 'Select a row to see the details.',
             'ID', 'Escape', 'ArrowLeft', 'ArrowRight'}
