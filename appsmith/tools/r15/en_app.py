# R15: kamus terjemahan teks app (Indonesia -> Inggris sederhana). Kunci '*' berlaku di semua file;
# kunci file (relatif appsmith/) hanya untuk file itu dan menimpa '*'. Hanya literal string / teks HTML yang diganti.
PAGES = {   # nama page lama -> baru (Appsmith merujuk page lewat nama)
    'Beranda': 'Home',
    'Master Komponen': 'Master Component',
    'Master Pilihan': 'Master Options',
    'Persetujuan Harga': 'Price Approval',
}

T = {}
T['*'] = {
    'Sesi login habis. Silakan login lagi.': 'Session expired. Please log in again.',
    'Memuat…': 'Loading…',
    'Beranda': 'Home',
    'Master Komponen': 'Master Component',
    'Master Pilihan': 'Master Options',
    'Persetujuan Harga': 'Price Approval',
    '← Beranda': '← Home',
}

T['js/AdminCtrl.js'] = {
    ' (nonaktif)': ' (inactive)',
    'Lengkapi email, nama, dan role.': 'Fill in email, name, and role.',
    'Role ini wajib memilih pabrik.': 'This role needs a factory.',
    'User disimpan.': 'User saved.',
    'Password direset.': 'Password reset.',
    'Belum ganti password': 'Must change password',
    'Nama pabrik wajib diisi.': 'Factory name is required.',
    'Pabrik disimpan.': 'Factory saved.',
}
T['js/ApprovalCtrl.js'] = {
    ' harga disetujui. Harga lama ditutup per tanggal berlaku harga baru.':
        ' price(s) approved. The old price ends on the new price start date.',
    ' harga ditolak.': ' price(s) rejected.',
}
T['js/Auth.js'] = {
    'Gagal memuat profil: ': 'Could not load profile: ',
    ' tidak punya akses ke halaman ini.': ' has no access to this page.',
}
T['js/LoginCtrl.js'] = {
    'Isi email dan password.': 'Enter email and password.',
    'Login gagal.': 'Login failed.',
    'Isi password lama dan password baru.': 'Enter the old and new password.',
    'Password berhasil diganti.': 'Password changed.',
    'Anda sudah keluar.': 'You are logged out.',
}
T['js/Util.js'] = {
    'Email sudah terdaftar.': 'Email is already registered.',
    'Terjadi kesalahan.': 'Something went wrong.',
}
T['js/SupplierCtrl.js'] = {
    'Nama supplier wajib diisi.': 'Supplier name is required.',
    'Supplier ditambahkan.': 'Supplier added.',
    'Supplier disimpan.': 'Supplier saved.',
}
T['js/KomponenCtrl.js'] = {
    'Lengkapi kelompok, nomor, dan nama komponen.': 'Fill in group, number, and component name.',
    'Komponen ditambahkan.': 'Component added.',
    'Komponen disimpan.': 'Component saved.',
}
T['js/MaterialCtrl.js'] = {
    ' material — persempit dengan pencarian / filter.': ' materials. Narrow down with search / filter.',
    'Belum ada varian': 'No variants yet',
    'Belum ada supplier': 'No suppliers yet',
    'utama: ': 'main: ',
    'Lengkapi kategori, nama, dan Mea.': 'Fill in category, name, and Mea.',
    'Material ditambahkan. Lanjutkan dengan menambah varian.': 'Material added. Next, add its variants.',
}
T['js/OptionCtrl.js'] = {
    'Last (per pabrik)': 'Last (per factory)',
    'Outsole mold (per pabrik)': 'Outsole mold (per factory)',
    ' (per pabrik)': ' (per factory)',
    ' diisi per pabrik — tiap pabrik hanya melihat miliknya sendiri.': ' is set per factory. Each factory only sees its own.',
    ' dipakai bersama semua pabrik.': ' is shared by all factories.',
    'Nilai wajib diisi.': 'Value is required.',
    ' ditambahkan.': ' added.',
    ' disimpan.': ' saved.',
}
T['js/ModelCtrl.js'] = {
    ' model — persempit dengan pencarian / filter.': ' models. Narrow down with search / filter.',
    'Semua pabrik': 'All factories',
    'Belum ada season': 'No seasons yet',
    ' season lain)': ' other seasons)',
    ' article aktif': ' active articles',
    'Belum ada specsheet': 'No specsheet yet',
    'Nama model dan kategori wajib diisi.': 'Model name and category are required.',
    ' ditambahkan. Tambahkan season & article-nya.': ' added. Now add its seasons & articles.',
}
T['js/BerandaCtrl.js'] = {
    'Tugas Saya': 'My Tasks',
    ' article belum dipakai di BOM': ' articles not used in the BOM',
    ' baris tanpa supplier': ' lines without supplier',
    'Ada material INACTIVE': 'Has INACTIVE materials',
    ' sel kuning (belum ada Material Code)': ' yellow cells (no Material Code)',
    'Ada supplier nonaktif': 'Has inactive suppliers',
    'Belum ada article aktif': 'No active articles',
    'BOM masih kosong': 'BOM is empty',
    'Tidak ada penghambat terdeteksi': 'No blockers found',
    'Draft specsheet dan article yang menunggu Anda.': 'Specsheet drafts and articles waiting for you.',
    'Draft specsheet terbuka': 'Open specsheet drafts',
    'Article belum masuk specsheet': 'Articles not in a specsheet',
    'Sel kuning (Material Code belum terdaftar)': 'Yellow cells (Material Code not registered)',
    'Draft Specsheet': 'Specsheet Drafts',
    'Tidak ada draft specsheet yang terbuka.': 'No open specsheet drafts.',
    ' baris BOM · ': ' BOM lines · ',
    ' article aktif': ' active articles',
    'Article Belum Masuk Specsheet': 'Articles Not in a Specsheet',
    'Semua article sudah masuk specsheet.': 'All articles are in a specsheet.',
    'Pilih di revisi specsheet': 'Select it in the specsheet revision',
    'Specsheet belum dibuat': 'No specsheet yet',
    ' harga menunggu persetujuan': ' prices waiting for approval',
    'CBD belum bisa terbit': 'CBD cannot be published yet',
    'Specsheet acuan sudah direvisi': 'Reference specsheet was revised',
    'Harga master berubah': 'Master price changed',
    'Pekerjaan CBD dan harga material yang perlu ditindaklanjuti.': 'CBD and material price work to follow up.',
    'CBD perlu dibuat': 'CBD to create',
    'Draft perlu refresh': 'Drafts to refresh',
    'CBD terbit perlu revisi': 'Published CBD to revise',
    'Harga master belum ada': 'Missing master prices',
    'Usulan harga ditolak': 'Rejected price proposals',
    'CBD Perlu Dibuat': 'CBD to Create',
    'Semua article aktif sudah punya CBD.': 'All active articles have a CBD.',
    'Aktif di specsheet terbit': 'Active in published specsheet',
    'Draft CBD Perlu Refresh': 'CBD Drafts to Refresh',
    'Tidak ada draft yang tertinggal dari specsheet atau master harga.': 'No drafts behind the specsheet or master prices.',
    'CBD Terbit Perlu Revisi': 'Published CBD to Revise',
    'Semua CBD terbit masih sesuai specsheet.': 'All published CBDs match the specsheet.',
    'Specsheet sudah stage berikutnya — buat CBD-nya': 'Specsheet is at a later stage. Create its CBD',
    'PERLU REVISI': 'NEEDS REVISION',
    'Draft CBD Berjalan': 'CBD Drafts in Progress',
    'Harga Master Belum Ada': 'Missing Master Prices',
    'Varian material katalog + supplier yang dipakai di specsheet terbit tapi belum punya harga berlaku.':
        'Material variants + suppliers used in published specsheets without an active price.',
    'Semua material yang dipakai sudah punya harga master.': 'All used materials have a master price.',
    ' · dipakai di ': ' · used in ',
    ' Material Code tanpa harga': ' Material Codes without price',
    'Usulan harga menunggu approval': 'Price proposal waiting for approval',
    'Usulan Harga Ditolak': 'Rejected Price Proposals',
    'Ditolak Manager Costing dalam 30 hari terakhir dan belum diajukan ulang.':
        'Rejected by Manager Costing in the last 30 days and not proposed again.',
    'Tidak ada usulan harga yang ditolak.': 'No rejected price proposals.',
    ' · ditolak ': ' · rejected by ',
    'Alasan: ': 'Reason: ',
    'Usulan harga yang menunggu persetujuan Anda.': 'Price proposals waiting for your approval.',
    'Pengajuan harga': 'Price proposals',
    'Pengajuan Harga Menunggu Persetujuan': 'Price Proposals Waiting for Approval',
    'Tidak ada usulan harga.': 'No price proposals.',
    'Usulan Vendor CBD (per pengajuan). Harga lama tetap berlaku sampai usulan disetujui.':
        'Vendor CBD proposals (per submission). The old price stays active until approved.',
    'Specsheet dan CBD yang baru diterbitkan.': 'Recently published specsheets and CBDs.',
    'Specsheet Terbit Terbaru': 'Latest Published Specsheets',
    'Revisi terbit terakhir tiap season.': 'Latest published revision per season.',
    'Belum ada specsheet terbit.': 'No published specsheets yet.',
    ' · terbit ': ' · published ',
    'CBD Terbit Terbaru': 'Latest Published CBDs',
    'Revisi terbit terakhir tiap article.': 'Latest published revision per article.',
    'Belum ada CBD terbit.': 'No published CBDs yet.',
    'Ringkasan sistem.': 'System summary.',
    'Revisi CBD': 'CBD revisions',
    'Entri audit log (±)': 'Audit log entries (±)',
    'Ringkasan Sistem': 'System Summary',
    'Data ringkasan belum bisa dimuat.': 'Summary data could not be loaded.',
    ' material · ': ' materials · ',
    ' article · ': ' articles · ',
    ' user aktif': ' active users',
    'Aktivitas terakhir ': 'Last activity ',
    '. Buka menu Admin untuk user dan audit log.': '. Open the Admin menu for users and the audit log.',
    'Melewati 3 GB — saatnya mengarsipkan audit log lama (hubungi pengembang).':
        'Over 3 GB. Time to archive the old audit log (contact the developer).',
    'Batas peringatan 3 GB. Audit log tidak dihapus otomatis.': 'Warning limit 3 GB. The audit log is not deleted automatically.',
    'PERLU ARSIP': 'ARCHIVE NEEDED',
}
T['js/CbdCtrl.js'] = {
    'Material / harga material': 'Material / material price',
    'Komponen (ikut specsheet)': 'Component (from specsheet)',
    'Treatment / proses': 'Treatment / process',
    'Model tidak ditemukan. Pilih model di atas.': 'Model not found. Select a model above.',
    'specsheet belum terbit': 'specsheet not published',
    'Pilih model dan season dahulu.': 'Select a model and season first.',
    '<span style="color:#6b7280">Kategori: ': '<span style="color:#6b7280">Category: ',
    'DI-DROP · ': 'DROPPED · ',
    'DI-DROP': 'DROPPED',
    ' · specsheet baru': ' · new specsheet',
    'PERLU CBD ': 'NEEDS CBD ',
    'PERLU REVISI · ': 'NEEDS REVISION · ',
    'SPECSHEET BELUM TERBIT': 'SPECSHEET NOT PUBLISHED',
    'BELUM ADA CBD': 'NO CBD YET',
    'Pilih model dulu.': 'Select a model first.',
    'Model ini belum punya season.': 'This model has no seasons yet.',
    'Belum ada article di season ini.': 'No articles in this season yet.',
    'Belum ada CBD. Klik "+ Buat CBD".': 'No CBD yet. Click "+ Create CBD".',
    'Belum ada CBD yang terbit.': 'No published CBD yet.',
    ' sudah di-drop di specsheet terbit terakhir — CBD hanya bisa dilihat.</span><br>':
        ' is dropped in the latest published specsheet. The CBD is view only.</span><br>',
    ' belum ada di revisi specsheet yang terbit — terbitkan specsheet dulu.</span><br>':
        ' is not in a published specsheet revision. Publish the specsheet first.</span><br>',
    ' · terbit ': ' · published ',
    ' · dibuat ': ' · created ',
    ' oleh ': ' by ',
    ' · acuan specsheet ': ' · reference specsheet ',
    ' · sumber: ': ' · source: ',
    '<br><span style="color:#dc2626">Specsheet sudah terbit ': '<br><span style="color:#dc2626">Specsheet published ',
    '. Buat CBD ': '. Create the ',
    ' lewat "+ Buat CBD".</span>': ' CBD with "+ Create CBD".</span>',
    '<br><span style="color:#dc2626">Specsheet terbit ': '<br><span style="color:#dc2626">Specsheet ',
    ' mengubah baris / supplier / warna article ini — buat revisi CBD berikutnya.</span>':
        ' changed lines / suppliers / colors of this article. Create the next CBD revision.</span>',
    '<br><span style="color:#6b7280">Perubahan (': '<br><span style="color:#6b7280">Change (',
    ' (model asal) · ': ' (origin model) · ',
    ' terbit': ' published',
    ' · di-drop': ' · dropped',
    'CBD baru dari specsheet': 'New CBD from specsheet',
    'Baris dari specsheet ': 'Lines from specsheet ',
    '; harga dari master harga. Yield & Loss % diisi.': '; prices from master prices. Fill in Yield & Loss %.',
    'Copy dari article lain (model sama / model asal)': 'Copy from another article (same model / origin model)',
    'Baris, warna & supplier tetap dari specsheet article ini; yang di-copy Yield, Loss %, harga quotation, dan rekap. ':
        'Lines, colors & suppliers come from this article\'s specsheet; Yield, Loss %, quotation prices, and recap are copied. ',
    'Dari model asal (copy lintas model): Yield/Loss hanya baris asal dengan material + thickness sama; hanya rate & LOP yang ikut.':
        'From the origin model (cross-model copy): Yield/Loss only for origin lines with the same material + thickness; only rate & LOP are copied.',
    'Belum ada article lain model ini (atau model asalnya) yang punya CBD terbit.':
        'No other article of this model (or its origin model) has a published CBD.',
    'Revisi berikutnya: {next}': 'Next revision: {next}',
    '; Yield, Loss %, harga input & rekap dari ': '; Yield, Loss %, entered prices & recap from ',
    'Baris yang tidak ada lagi di specsheet ditandai MISSING_IN_SPEC.': 'Lines no longer in the specsheet are marked MISSING_IN_SPEC.',
    'Buat CBD — ': 'Create CBD: ',
    'Buat CBD': 'Create CBD',
    'Acuan: specsheet ': 'Reference: specsheet ',
    '{spec} (terbit terakhir di stage itu).': '{spec} (latest published in that stage).',
    'Terbitkan atau hapus draft yang ada dulu sebelum membuat revisi baru.': 'Publish or delete the current draft before creating a new revision.',
    'Tidak ada stage yang bisa dibuat CBD-nya (article tidak aktif di specsheet terbit).':
        'No stage is available for a CBD (article is not active in a published specsheet).',
    'CBD draft dibuat.': 'CBD draft created.',
    'Specsheet acuan = terbit terakhir di stage ': 'Reference specsheet = latest published in stage ',
    'Klik "Refresh dari Specsheet" di atas grid': 'Click "Refresh from Specsheet" above the grid',
    'Exchange rate terisi': 'Exchange rate filled in',
    'Isi Exchange rate di rekap': 'Fill in the Exchange rate in the recap',
    'Tidak ada harga yang menunggu persetujuan': 'No prices waiting for approval',
    ' baris menunggu Manager Costing: ': ' lines waiting for Manager Costing: ',
    'Harga master sama dengan master terkini': 'Master prices match the current master',
    ' baris berubah — klik "Refresh Harga dari Master"': ' lines changed. Click "Refresh Prices from Master"',
    'Baris berharga punya Yield': 'Priced lines have a Yield',
    ' baris belum diisi Yield (kotak kuning)': ' lines without Yield (yellow box)',
    'Baris ber-Yield sudah berharga': 'Lines with Yield have a price',
    ' baris akan terbit dengan cost 0: ': ' lines will publish with cost 0: ',
    ' — isi harganya bila terlupa': '. Fill in the price if it was missed',
    ' baris tanpa biaya (cost 0)': ' lines with no charge (cost 0)',
    'Alasannya tampil di grid & export Excel.': 'The reason shows in the grid & Excel export.',
    'Article aktif di specsheet terbit': 'Article active in the published specsheet',
    'Article di-drop / belum terbit — CBD ini tidak bisa diterbitkan': 'Article dropped / not published. This CBD cannot be published',
    'Terbitkan CBD ': 'Publish CBD ',
    'di grid / rekap CBD': 'in the CBD grid / recap',
    ' diterbitkan.': ' published.',
    ' gambar gagal dilampirkan.': ' image(s) could not be attached.',
    ' gambar dilampirkan.': ' image(s) attached.',
    ' gambar gagal dimuat.': ' image(s) could not be loaded.',
    'Pilih baris riwayat untuk melihat gambarnya.': 'Select a history row to see its images.',
    'Gambar tidak bisa dimuat.': 'Images could not be loaded.',
    'Tidak ada gambar di terbit ini.': 'No images in this publish.',
    'Draft CBD ': 'CBD draft ',
    ' dihapus.': ' deleted.',
}
T['js/CbdGridCtrl.js'] = {
    'Refresh dari Specsheet': 'Refresh from Specsheet',
    ' sudah terbit ': ' published ',
    '. Baris draft ini masih dari ': '. This draft still uses ',
    'Refresh dulu sebelum terbit (Yield, Loss % & harga input dibawa; baris yang hilang jadi MISSING_IN_SPEC).':
        'Refresh before publishing (Yield, Loss % & entered prices are kept; removed lines become MISSING_IN_SPEC).',
    'Refresh Harga dari Master': 'Refresh Prices from Master',
    'Harga master untuk ': 'Master prices for ',
    ' baris baru tersedia atau berubah sejak CBD ini dibuat. ': ' lines are new or changed since this CBD was created. ',
    'Samakan dulu sebelum terbit.': 'Update them before publishing.',
    ' baris punya usulan harga yang menunggu persetujuan Manager Costing — CBD belum bisa terbit. ':
        ' lines have price proposals waiting for Manager Costing. The CBD cannot be published yet. ',
    'Setelah disetujui, klik Refresh Harga dari Master.': 'After approval, click Refresh Prices from Master.',
    ' baris sudah ada Yield tapi belum berharga — tetap bisa terbit dengan cost 0. Isi harganya bila terlupa.':
        ' lines have a Yield but no price. They can still publish with cost 0. Fill in the price if it was missed.',
    ' di antaranya belum punya harga master untuk Material Code + supplier-nya (ajukan di Material Detail).':
        ' of them have no master price for their Material Code + supplier (propose it in Material Detail).',
    ' belum punya supplier di specsheet.': ' have no supplier in the specsheet.',
    ' baris berharga USD belum terhitung — isi Exchange rate di rekap.': ' USD-priced lines are not counted. Fill in the Exchange rate in the recap.',
    'Tidak ada baris — article ini tidak memakai baris BOM mana pun.': 'No lines. This article does not use any BOM line.',
    'Baris ditandai tanpa biaya (cost 0).': 'Line marked as no charge (cost 0).',
    'Tanda tanpa biaya dibatalkan.': 'No-charge mark removed.',
    ' baris disamakan dengan master.': ' line(s) updated from master.',
    'CBD di-refresh dari specsheet ': 'CBD refreshed from the latest published ',
    ' terbit terakhir.': ' specsheet.',
    'harga master': 'master price',
    'Harga di CBD ini: ': 'Price in this CBD: ',
    'Harga di CBD ini: kosong': 'Price in this CBD: empty',
    'Harga master berlaku sekarang: ': 'Current master price: ',
    'Belum ada harga master berlaku untuk Material Code + supplier ini.': 'No active master price for this Material Code + supplier.',
    'Harga Quotation': 'Quotation Price',
    'Harga Master Baru': 'New Master Price',
    'Ajukan Harga Master': 'Propose Master Price',
    'Harga quotation disimpan.': 'Quotation price saved.',
    'Harga quotation dikosongkan.': 'Quotation price cleared.',
    'Harga master disimpan dan langsung berlaku. Vendor CBD perlu klik Refresh Harga dari Master.':
        'Master price saved and active now. Vendor CBD needs to click Refresh Prices from Master.',
    'Usulan harga master dikirim ke Manager Costing. Setelah disetujui, klik Refresh Harga dari Master.':
        'Master price proposal sent to Manager Costing. After approval, click Refresh Prices from Master.',
}

# teks yang sudah diperiksa dan tidak perlu diubah (bahasa Inggris, nama page tetap, format, kode)
KEEP = {
    'Vendor - Specsheet', 'Vendor - CBD', 'Manager Costing', 'Brand Viewer', 'System Admin', 'Login',
    'password|token|secret|hash', 'Record created. New records are not copied to the audit log.',
    'No changed fields recorded.', 'No data recorded for this action.', 'DD MMM YYYY, HH:mm:ss', 'Changed fields',
    'Deleted record', 'Created record', 'Data', '(empty)', 'Material Detail', 'Role ', 'YYYY-MM-DD', 'DD MMM YYYY',
    'DD MMM YYYY HH:mm', 'Pullover', 'Preview', 'Production', 'Construction', 'Gender', 'OPTION:', 'Spring/Summer',
    'Fall/Holiday', ' (INACTIVE)', 'Model ', 'Model Detail', 'Specsheet', 'Cost Breakdown (CBD)', 'Supplier ', 'Model',
    'Specsheet (season)', 'Admin', 'Audit log ', 'Yield / Loss %', 'Exchange rate', '&amp;', '&lt;', '&gt;', '&quot;',
    ' · Factory: ', ' · Size Range: ', ' · Sample Size: ', '<span style="color:#6b7280">Article ', ' · <b style="color:',
    '← Model List', '← Model Detail', 'Model List', '{spec}', ';base64,', 'Specsheet ',
}
T['*'].update({
    'Menampilkan ': 'Showing ',
    ' dari ': ' of ',
    ' oleh ': ' by ',
    'Riwayat (': 'History (',
    'Riwayat': 'History',
    'Gambar ': 'Images ',
    'Gambar': 'Images',
    'Gagal': 'Failed',
    'Nonaktif': 'Inactive',
    'Aktif': 'Active',
    'Terkunci': 'Locked',
})
T['js/OptionCtrl.js'].update({'Kategori': 'Category', 'Ukuran': 'Size'})
T['js/CbdCtrl.js'].update({'Amortisasi': 'Amortization', 'Lainnya': 'Other'})
T['js/CbdGridCtrl.js'].update({'Harga ': 'Prices of '})
T['js/MaterialCtrl.js'].update({' varian': ' variant(s)', ' supplier': ' supplier(s)'})
T['js/ModelCtrl.js'].update({' article': ' article(s)'})
T['js/BerandaCtrl.js'].update({'diusulkan ': 'proposed by '})
KEEP |= {'specsheet '}

import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
import en_app_b
CODES = en_app_b.CODES
en_app_b.load(T, KEEP)
import en_app_c
en_app_c.load(T, KEEP)
import en_app_d
en_app_d.load(T, KEEP)
import en_app_e
en_app_e.load(T, KEEP)
import en_app_f
en_app_f.load(T, KEEP)
T['widgets/cwPriceForm/script.js'][' dipilih'] = ' selected'
T['widgets/cwCbdForm/index.html']['Stage CBD'] = 'CBD stage'
KEEP |= {'#list input'}
import en_app_g
en_app_g.load(T, KEEP)
