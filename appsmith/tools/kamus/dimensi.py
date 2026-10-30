"""Baku Dimension: MASUK / RAGU / TIDAK dengan nama baku."""
import pickle, re, collections
exec(open('an.py').read().split('# ---- report')[0].split("erp=[r")[0])   # ws_, clean_th
_ct = clean_th
def clean_th(n): return _ct(re.sub(r'([A-Z])\.(\d)', lambda m: m.group(1) + '#' + m.group(2), ws_(n))).replace('#', '.')
d = pickle.load(open('data.pkl', 'rb'))
usedm = d['usedm']

UNIT = r'(MM|CM|UM|ME|M|"|OZ|GSM|GR|G|KG|D|MIC|MICRON|YD|YARD|L|ML)'
NUM = r'\d+(\.\d+)?'
ONE = rf'{NUM}(-{NUM})?( ?{UNIT})?'
DIM = rf'{ONE}( X {ONE})*'
RX_DIM = re.compile(rf'^(\()?{DIM}(\))?( X)?( \({DIM}\))?( X {DIM})?$')
RX_SIZE = re.compile(r'^SIZE \d+(-\d+)?$')

def baku(n):
    k = clean_th(re.sub('(?i)_x000d_', '', n))
    k = re.sub(r'^(SZ|SIZE|S)\.? ?(?=\d)', 'SIZE ', k)
    k = re.sub(r'\b(LBR|LEBAR) ?=? ?', 'WIDTH ', k)
    k = re.sub(r'(\d) ?(GR|GSM|KG|CM|MM|")X ?(?=[\d(])', r'\1 \2 X ', k)
    k = re.sub(r'\)X ?(?=\d)', ') X ', k)
    k = re.sub(r'(\d)(ME|M)\b', r'\1 \2', k)
    return re.sub(r'\s+', ' ', k).strip()

def group(k):
    if '=' in k: return 'ada tanda = (ukuran per size)'
    if re.search(r'\d+T\b', k): return 'ukuran anak (T)'
    if re.match(r'^NO\.', k): return 'nomor (NO.x)'
    if re.match(r'^[A-Z]\d+', k) or re.match(r'^[A-Z]+$', k): return 'kode huruf (B6, P00, ...)'
    if re.search(r'\d', k) and not re.search(r'MM|CM|"|OZ|GSM|KG|GR|\bM\b|\bD\b|\bG\b|SIZE', k): return 'angka tanpa satuan'
    if 'WIDTH' in k: return 'lebar (LBR / LEBAR)'
    return 'lainnya'

rows = []
for i, c, n in d['th']:
    C = c.strip().upper()
    k = baku(n)
    if len(C) != 3:
        rows.append((i, C, n, k, 'TIDAK', 'kode tidak standar')); continue
    if k == '':
        rows.append((i, C, n, '(None)', 'MASUK' if usedm[C] else 'TIDAK', 'kosong, dipakai di ERP' if usedm[C] else 'kosong, tidak dipakai')); continue
    if RX_DIM.match(k) and re.search(r'MM|CM|"|OZ|GSM|KG|GR|\bM\b|\bD\b|\bG\b', k):
        rows.append((i, C, n, k, 'MASUK', 'ukuran dengan satuan')); continue
    if re.match(r'^WIDTH \d+(\.\d+)? ?(CM|M|MM|")$', k):
        rows.append((i, C, n, k, 'MASUK', 'lebar')); continue
    if RX_SIZE.match(k):
        rows.append((i, C, n, k, 'MASUK', 'SIZE')); continue
    # jawaban user D8-D13 (29 Okt 2026): nomor tidak, kode huruf hanya yang ada ukurannya, sisanya masuk
    g = group(k)
    if g == 'nomor (NO.x)' or (g.startswith('kode huruf') and not re.search(r'\d+ ?(MM|CM)', k)):
        rows.append((i, C, n, k, 'TIDAK', g)); continue
    if g.startswith('ada tanda ='):
        m = re.match(r'^(\d+(?:-\d+)?)=(.+)$', k) or re.match(r'^(.+?)=(\d+(?:-\d+)?)$', k)
        if m:
            sz, dim = (m.group(1), m.group(2)) if re.fullmatch(r'\d+(-\d+)?', m.group(1)) else (m.group(2), m.group(1))
            k = f'SIZE {sz}: {dim}'
    rows.append((i, C, n, k, 'MASUK', g))
pickle.dump(rows, open('dimensi.pkl', 'wb'))
print(collections.Counter(r[4] for r in rows))
print(collections.Counter(r[5] for r in rows if r[4] == 'RAGU').most_common())
g = collections.defaultdict(list)
for r in rows:
    if r[4] == 'RAGU': g[r[5]].append(r)
for k, v in g.items():
    print('##', k, len(v)); print('   ', ' | '.join(f'{r[1]}={r[3]}' for r in v[:12]))
