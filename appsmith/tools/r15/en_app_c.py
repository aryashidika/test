# R15 kamus bagian C: export Excel (SpecExportCtrl, CbdExportCtrl, XlsxWriter).


def load(T, KEEP):
    T['*'].update({
        'menulis file': 'writing the file',
        'menyusun isi': 'building the content',
        'Export gagal saat ': 'Export failed while ',
        ' · terbit oleh ': ' · published by ',
        ' · BELUM TERBIT': ' · NOT PUBLISHED',
        ' (lokal)': ' (local)',
        'Belum ada baris BOM.': 'No BOM lines yet.',
        'Belum ada article aktif': 'No active articles',
        ' · acuan specsheet ': ' · reference specsheet ',
        'Amortisasi': 'Amortization',
        'harga master': 'master price',
    })
    T['js/SpecExportCtrl.js'] = {
        'Buka revisi specsheet dulu.': 'Open a specsheet revision first.',
        'File Excel specsheet diunduh.': 'Specsheet Excel file downloaded.',
        'belum terbit': 'not published',
        ' · REVISI ': ' · REVISION ',
        'Perubahan (': 'Change (',
    }
    T['js/CbdExportCtrl.js'] = {
        'Buka revisi CBD dulu.': 'Open a CBD revision first.',
        'memuat rincian perubahan': 'loading the change breakdown',
        'File Excel CBD diunduh.': 'CBD Excel file downloaded.',
        'Tanggal': 'Date',
        'Season / Revisi': 'Season / Revision',
        'Asal': 'Source',
        'tanpa harga': 'no price',
        ' · ganti material': ' · replaced material',
        'tanpa biaya: ': 'no charge: ',
        'Belum ada baris CBD.': 'No CBD lines yet.',
        'Hilang dari specsheet (MISSING_IN_SPEC) — ': 'Missing from specsheet (MISSING_IN_SPEC): ',
        ' baris, tidak dihitung': ' lines, not counted',
        'material cost + semua biaya': 'material cost + all costs',
        ',"UNDER","SESUAI"))': ',"UNDER","MATCH"))',
        'harga PO ke brand': 'PO price to brand',
        'Oleh': 'By',
        'Alasan': 'Reason',
        'Rincian perubahan dibanding ': 'Change breakdown vs ',
        'revisi sebelumnya': 'previous revision',
        'Uraian': 'Description',
        'Nilai (Rp)': 'Value (Rp)',
        'Selisih Actual FOB': 'Actual FOB difference',
    }
    T['js/XlsxWriter.js'] = {'Alamat sel tidak valid: ': 'Invalid cell address: '}
    KEEP |= {
        '_-"Rp"* #,##0.00_-;\\\\-"Rp"* #,##0.00_-;_-"Rp"* "-"??_-;_-@_-', 'Direct Labour', 'Adjustment',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'Cost Breakdown Sheet',
        'Confidential Information', 'Model Name', '); Mold: ', '; Last: ', '; Size Range: ', 'Article #', 'Color', 'No',
        'Component Name', 'Material description', 'Thickness', 'Unit', 'Yield', 'Usage', 'Loss %', 'Unit Price',
        'Cost/pr (Rp)', 'Supplier', 'Remarks', ' · copy', 'Subtotal ', 'SUM(L', 'Cost recapitulation', ' Material Cost',
        'SUM(', 'ACTUAL FOB', 'TARGET FOB', 'IF(L', ',"OVER",IF(L', ' (Actual FOB × ', 'ROUND(L', 'Change log',
        'DD-MM-YYYY HH:mm', 'SPECIFICATION SHEET OF MATERIAL & COMPONENT', 'DD/MM/YYYY', 'PURPOSE :', 'MODEL NAME  :',
        'CATEGORY  :  ', 'OUTSOLE MOULD  :  ', 'LAST No.', 'SIZE RANGE', 'SAMPLE SIZE', 'GENDER  :  ', 'NO.',
        'COMPONENT NAME', 'MATERIAL DESCRIPTION', 'SOURCE OF MATERIAL', 'UNIT OF MSRMNT', 'ARTICLE NO.', ' · Page &P / &N',
    }
