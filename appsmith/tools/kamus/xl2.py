import pickle, openpyxl, collections
from openpyxl.styles import Font, PatternFill
W = pickle.load(open('warna.pkl', 'rb')); D = pickle.load(open('dimensi.pkl', 'rb'))
p = r'D:/OJT_PM/Mock Up/document/Kamus Kode/Review_Kamus_Kode.xlsx'
wb = openpyxl.load_workbook(p)
order = {'RAGU': 0, 'TIDAK': 1, 'MASUK': 2}
def sheet(name, head, rows, widths):
    idx = wb.sheetnames.index(name) if name in wb.sheetnames else None
    if idx is not None: del wb[name]
    ws = wb.create_sheet(name, idx)
    ws.append(head)
    for c in ws[1]: c.font = Font(bold=True, color='FFFFFF'); c.fill = PatternFill('solid', fgColor='305496')
    for r in rows: ws.append(r)
    ws.freeze_panes = 'A2'; ws.auto_filter.ref = ws.dimensions
    for i, w in enumerate(widths, 1): ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width = w
sheet('Warna baku', ['Kode', 'Nama di master', 'Nama baku (usulan)', 'Hasil', 'Alasan / yang diragukan', 'Baris Excel', 'Koreksi (Masuk / Tidak / nama baku lain)'],
      [[r[1], r[2], r[3], r[4], r[5], r[0], ''] for r in sorted(W, key=lambda r: (order[r[4]], r[2]))], [8, 42, 42, 8, 45, 10, 30])
sheet('Dimension baku', ['Kode', 'Nama di master', 'Nama baku (usulan)', 'Hasil', 'Alasan / kelompok', 'Baris Excel', 'Koreksi (Masuk / Tidak / nama baku lain)'],
      [[r[1], r[2], r[3], r[4], r[5], r[0], ''] for r in sorted(D, key=lambda r: (order[r[4]], r[5], r[3]))], [8, 30, 32, 8, 30, 10, 30])
wb.save(p)
print(collections.Counter(r[4] for r in W), collections.Counter(r[4] for r in D))
print(collections.Counter(r[5] for r in D if r[4] == 'RAGU'))
