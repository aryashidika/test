"""Baku warna: kelompokkan master warna jadi MASUK / RAGU / TIDAK, dengan nama baku."""
import pickle, re, collections
d = pickle.load(open('data.pkl', 'rb'))
used = d['used']
def ws(s): return re.sub(r'\s+', ' ', re.sub('(?i)_x000d_', '', s or '')).strip().upper()

# bagian sepatu sebelum ':' yang sudah dijelaskan user
PART = {'BS': 'BASE', 'BASE': 'BASE', 'ST': 'STUD', 'STD': 'STUD', 'STUD': 'STUD', 'LG': 'LOGO', 'LOGO': 'LOGO',
        'SPRAY': 'SPRAY', 'SPRY': 'SPRAY',
        # jawaban user di dokumen (B1-B78), 29 Okt 2026
        'B': 'BASE', 'S': 'STUD', 'ASK': 'ACCENT', 'ASKEN': 'ACCENT', 'AS': 'ACCENT', 'ACCENT': 'ACCENT', 'ASKN': 'ACCENT',
        'ACENT': 'ACCENT', 'DC': 'DECO', 'DECO': 'DECO', 'L': 'LOGO', 'OS': 'OUTSOLE', 'IN': 'INLAY', 'I': 'INLAY',
        'ILY': 'INLAY', 'IL': 'INLAY', 'INLY': 'INLAY', 'BSSTD': 'BASE+STUD', 'TIP': 'TIP', 'MDSL': 'MIDSOLE', 'MDS': 'MIDSOLE',
        'WORD': 'WORDING', 'WORDING': 'WORDING', 'BSTTP': 'BASE+STUD+TIP', 'SPRAY FULL': 'SPRAY FULL'}
# singkatan warna yang yakin
ABBR = {'WHT': 'WHITE', 'WH': 'WHITE', 'BLK': 'BLACK', 'YLW': 'YELLOW', 'GRN': 'GREEN', 'ORG': 'ORANGE', 'BLU': 'BLUE',
        'SLVR': 'SILVER', 'GRY': 'GREY', 'NVY': 'NAVY', 'DK': 'DARK', 'LT': 'LIGHT', 'METALIC': 'METALLIC',
        'ANODZED': 'ANODIZED', 'EFECT': 'EFFECT', 'SPRY': 'SPRAY', 'ASSYLUM': 'ASYLUM', 'LYR': 'LAYER', 'BRKN': 'BROKEN', 'MET': 'METALLIC'}
EXCL = re.compile(r'=|\bVAMP\b|\bTONGUE\b|\bCOLLAR\b|\bQUARTER\b|\bQTR\b|SUBLIM|\bPRINT|GRADATION|\bINSOLE\b|\bSOCK')

names = [(i, c.strip().upper(), ws(n)) for i, c, n in d['col']]
# kosakata: kata yang berdiri sendiri cukup sering
raw = collections.Counter(t for _, _, n in names for t in re.findall(r'[A-Z]+', n))
VOC = {t for t, k in raw.items() if k >= 3 and len(t) > 1} | set(ABBR.values()) | set(PART.values())
NOISE = {'C', 'U', 'TPG', 'TCX', 'TPX', 'TP', 'TN', 'B', 'X'}  # akhiran Pantone / penanda

def split_glued(t):
    if t in ABBR: return [t]
    for k in range(3, len(t) - 2):
        a, b = t[:k], t[k:]
        a2, b2 = ABBR.get(a, a), ABBR.get(b, b)
        if raw.get(a, 0) >= 10 and raw.get(b, 0) >= 10 and raw.get(t, 0) < raw.get(a, 0) and raw.get(t, 0) < raw.get(b, 0) or (a in ABBR and raw.get(b, 0) >= 10) or (b in ABBR and raw.get(a, 0) >= 10):
            return [a, b]
    return [t]

def pantone(s):
    s = re.sub(r'([A-Z])\(', r'\1 (', s)
    s = re.sub(r'(\d{2})-?(\d{4})\s*(TPG|TCX|TPX|TP|TN)\b', r'\1-\2 \3', s)
    s = re.sub(r'([A-Z])(\d{2}-\d{4})', r'\1 \2', s)
    s = re.sub(r'\b(\d{3,4})\s?(C|U)\b', r'\1 \2', s)
    s = re.sub(r'([A-Z]{2,})(\d{3,4} [CU])\b', r'\1 \2', s)
    if s.count('(') > s.count(')'): s += ')'
    return s

def baku(n):
    """-> (nama baku, set kata ragu, alasan tidak masuk atau None)"""
    if EXCL.search(n): return n, set(), 'menyebut bagian sepatu / print'
    if ',' in n or re.search(r'\([A-Z ]{1,3}\)', n): return n, set(), 'tidak bisa dibakukan'
    s = pantone(n)
    doubt = set()
    # bagian sebelum ':'
    def part(m):
        ps = [p.strip() for p in m.group(2).split('+')]
        out = []
        for p in ps:
            if p in PART: out.append(PART[p])
            else: doubt.add(f'bagian "{p}:"'); out.append(p)
        return m.group(1) + '+'.join(out) + ':'
    s = re.sub(r'(^|[/;]\s*)([A-Z0-9 .+&]+?)\s*:\s*', part, s)
    s = re.sub(r'\+(?![A-Z +]*:)', '/', s)
    words = []
    for t in re.findall(r'[A-Z]+|[^A-Z]+', s):
        if not t.isalpha(): words.append(t); continue
        if t in ABBR: words.append(ABBR[t]); continue
        parts = split_glued(t)
        parts = [ABBR.get(p, p) for p in parts]
        for p in parts:
            if p not in VOC and p not in NOISE and len(p) > 1 and (len(p) <= 3 or not re.search('[AEIOU]', p)):
                doubt.add(f'kata "{p}"')
        words.append(' '.join(parts))
    s = ''.join(words)
    s = re.sub(r'\s*/\s*', '/', s); s = re.sub(r'\s*:\s*', ':', s); s = re.sub(r'\s+', ' ', s).strip()
    s = re.sub(r'\s*\(\s*', ' (', s); s = re.sub(r'\s*\)', ')', s)
    s = re.sub(r'([A-Z]{2,})\.(?=[A-Z])', lambda m: m.group(1) + ' ', s)
    return s.strip(), doubt, None

rows = []
for i, c, n in names:
    if len(c) != 3 or not n:
        rows.append((i, c, n, '', 'TIDAK', 'kode tidak standar / nama kosong', set())); continue
    b, doubt, no = baku(n)
    if used[c]:   # A1: dipakai di daftar ERP / aplikasi selalu masuk
        rows.append((i, c, n, b, 'MASUK', 'dipakai di ERP', set())); continue
    if no:
        rows.append((i, c, n, '', 'TIDAK', no, set())); continue
    if doubt:
        # user: yang tidak dikomentari = tidak masuk
        rows.append((i, c, n, b, 'TIDAK', 'tidak dijelaskan: ' + '; '.join(sorted(doubt)), doubt)); continue
    rows.append((i, c, n, b, 'MASUK', 'dibakukan' if b != n else 'sudah baku', set()))
pickle.dump(rows, open('warna.pkl', 'wb'))
print(collections.Counter(r[4] for r in rows))
print(collections.Counter(r[5] for r in rows if r[4] != 'RAGU').most_common(8))
dc = collections.Counter(x for r in rows for x in r[6])
print('kata/bagian ragu berbeda', len(dc), 'muncul >=3:', sum(1 for k, v in dc.items() if v >= 3))
print(dc.most_common(70))
for r in rows[:0]: pass

part = collections.Counter(x for r in rows for x in r[6] if x.startswith('bagian'))
word = collections.Counter(x for r in rows for x in r[6] if x.startswith('kata'))
print('bagian', len(part), sum(1 for v in part.values() if v >= 5), 'kata', len(word), sum(1 for v in word.values() if v >= 5))
print(part.most_common(120)); print(word.most_common(80))
