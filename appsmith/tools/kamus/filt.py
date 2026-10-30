import pickle, re, collections, sys
exec(open('an.py').read().split('# ---- report')[0].split("erp=[r")[0])   # ws_, clean_color, tight, clean_th
_ct = clean_th
def clean_th(n): return _ct(re.sub(r'([A-Z])\.(\d)', lambda m: m.group(1) + '#' + m.group(2), ws_(n))).replace('#', '.')
d = pickle.load(open('data.pkl', 'rb'))
used, usedm, usedp = d['used'], d['usedm'], d['usedp']

# ------------------------------------------------------------------ warna
BASE = set('''BLACK WHITE RED BLUE NAVY GREY GRAY GREEN YELLOW ORANGE PINK PURPLE BROWN BEIGE CREAM SILVER GOLD
KHAKI OLIVE MAROON TAN IVORY CHARCOAL NATURAL CLEAR TRANSPARENT TRANSPARANT MINT LIME TEAL TURQUOISE TOSCA CORAL
PEACH BURGUNDY MAGENTA VIOLET LAVENDER LILAC CAMEL CHOCOLATE COFFEE MOCCA MOCHA SAND STONE OFF NUDE FUCHSIA FUSCHIA
CYAN AQUA SALMON ROSE PLUM WINE ARMY AMBER MUSTARD COPPER BRONZE OCHRE RUST INDIGO COBALT SAPPHIRE EMERALD JADE
SKY ROYAL NEON LIGHT DARK LT DK DEEP PALE BRIGHT SOFT DUSTY SUPER METALLIC GLOSSY DOFF MATTE MULTI MULTICOLOR
BLK WHT GRY GRN NVY YLW ORG BLU BRN RD SLV GLD'''.split())
SUFFIX = set('C U TPG TCX TPX TP CP PC'.split())
def color_ok(name):
    n = ws_(name)
    if not n or re.search(r'[:;+=]|SPRAY|EFFECT|VAMP|COLLAR|SOLE|TONGUE|LOGO|PRINT|LACE|STUD|BODY|LINING|\bIN\b|\bOUT\b', n):
        return False
    words = re.findall(r'[A-Z]+', re.sub(r'\b\d+[A-Z]?\b|\d+-\d+(TPG|TCX|TPX|TP)?|\d+[A-Z]{1,3}\b', ' ', n))
    words = [w for w in words if w not in SUFFIX]
    return bool(words) and all(w in BASE for w in words)
col_keep, col_drop = [], []
for i, c, n in d['col']:
    C = c.strip().upper()
    if len(C) != 3 or not ws_(n):
        col_drop.append((i, C, n, 'kode tidak standar / nama kosong')); continue
    if used[C]:
        col_keep.append((i, C, n, 'dipakai di daftar ERP')); continue
    if color_ok(n):
        col_keep.append((i, C, n, 'warna umum')); continue
    col_drop.append((i, C, n, 'nama tidak jelas / warna tidak umum'))

# ------------------------------------------------------------------ Dimension
UNIT = r'(MM|CM|M|"|INCH|OZ|GSM|GR|G|KG|D|MIC|MICRON|YD|YARD)'
NUM = r'\d+(\.\d+)?'
ONE = rf'{NUM}(-{NUM})?( ?{UNIT})?'
DIM_RX = re.compile(rf'^{ONE}( X {ONE})*( \({ONE}( X {ONE})*\))?$')
dim_keep, dim_drop = [], []
for i, c, n in d['th']:
    C = c.strip().upper()
    k = clean_th(n)
    if len(C) != 3:
        dim_drop.append((i, C, n, k, 'kode tidak standar')); continue
    if k == '':
        if usedm[C]: dim_keep.append((i, C, n, '(None)', 'kosong, dipakai di ERP'))
        else: dim_drop.append((i, C, n, '(None)', 'kosong, tidak dipakai'))
        continue
    if usedm[C]:
        dim_keep.append((i, C, n, k, 'dipakai di daftar ERP')); continue
    if DIM_RX.match(k) and re.search(r'MM|CM|"|OZ|GSM|KG|\bM\b|\bD\b|GR', k):
        dim_keep.append((i, C, n, k, 'ukuran jelas')); continue
    dim_drop.append((i, C, n, k, 'bukan ukuran yang jelas'))

# ------------------------------------------------------------------ material
PROCESS = re.compile(r'^(COATING|PRINTING|PRINT|SCREEN PRINTING|PUFF PRINTING|LAMINATING|LAMINASI|HF WELDING|PRESS WELDING|WELDING|PUNCH|TRANSFER ?PAPER|TRANFERPAPER|WORDING|SUBLIMASI|SINGLE STICKER|S\.? ?STICKER|DEBOSS)')
UNCLEAR = {  # kata yang user minta jangan dimasukkan (N1, N2, N6-N10, N12-N34) + SWERVO / SUPREME / MOTIF
 'N1 C/B': [r'C/B', r'(?<![A-Z])CB(?![A-Z])'],
 'N2 SI': [r'(?<![A-Z])S ?I(?![A-Z])', r'(?<![A-Z])ST I(?![A-Z])'],
 'N6 W di akhir': [r'(?<![A-Z/])W$'],
 'N7 SW': [r'(SZ ?LBL|SZLBL|SZ LB|C/B|HS LBL|HTSL SZ) SW '],
 'N8 HS': [r'(?<![A-Z])HS (?!SZ|LBL)'],
 'N9 HD NON WOVEN': [r'HD NON ?WOVEN'],
 'N10 MM di depan': [r'(^|\+)MM(?=[ +])'],
 'N12 CLR': [r'(?<![A-Z])CLR(?![A-Z])'],
 'N13 CL': [r'(?<![A-Z])CL(?![A-Z])'],
 'N14 DC': [r'(?<![A-Z])DC'],
 'N15 DB': [r'(?<![A-Z])DB(?![A-Z])'],
 'N16 MT': [r'(?<![A-Z])MTA?(?= CR)'],
 'N17 MK': [r'MK(?![A-Z])'],
 'N18 GA': [r'(?<![A-Z])GAE?(?![A-Z])'],
 'N19 E': [r'(?<![A-Z])E (FG|IN|PE)'],
 'N20 FT/FS/FB': [r'(SZ|LBL|LB|C/B|HEATSEAL).*(?<![A-Z])(FT|FS|FB|FF|SB|RK|CH|BTS)$'],
 'N21 TNDR': [r'(?<![A-Z])(TNDR|TDR|BLT)(?![A-Z])'],
 'N22 CNDP': [r'CNDP'],
 'N23 VB': [r'(?<![A-Z])(VB|VBOW|VCTRYBOW)(?![A-Z])'],
 'N24 OL': [r'(?<![A-Z])OL\d?(?![A-Z])'],
 'N25 KA/KI': [r'(?<![A-Z])(KA|KI)(?![A-Z])'],
 'N26 MFOAM': [r'(?<![A-Z])(MFOAM|MFOM|MLTFM|MLTFOAM)'],
 'N27 PROLTFM': [r'P(RO|NEO)LTFM'],
 'N28 SLMOLD': [r'SLMOLD'],
 'N29 VTERY': [r'(?<![A-Z])(VTERY|VTRY|VTERYN)(?![A-Z])'],
 'N30 OP dll': [r'(?<![A-Z])(OP|DECOP)(?![A-Z])', r'SPCRCS|SPHILLS|OCLFOMD|WCLFIT|PRINOSPRM|SPKIL|LGRUNING'],
 'N31 BS': [r'(?<![A-Z])BS(?![A-Z])'],
 'N32 N MESH': [r'(?<![A-Z/])N MESH'],
 'N33 P di akhir': [r'(?<![A-Z])P$'],
 'N34 NP/NV/XR...': [r'(?<![A-Z])(NP|NV|XR|RX|LX|XT|SV|EVR|MWP|TNT|QC|BPR|BEPE|AE|EF|LFGR|KLOK|GRD)(?![A-Z])'],
 'SWERVO': [r'SWERVO|SWRVO|SWRV'],
 'SUPREME': [r'SUPREME|SPRM'],
 'MOTIF': [r'MOTIF|(?<![A-Z])MTF(?![A-Z])'],
 # tabel singkatan, jawaban 29 Okt: "gausah dimasukkin"
 'BACK (BCK/BK)': [r'(?<![A-Z])(BCK|BK)(?![A-Z])'],
 'JOGGER': [r'JOGGER|JOGER|(?<![A-Z])(JGR|JGGR|JG)(?![A-Z])|JGRPRM|JGGRPRM'],
 'PREMIUM': [r'PREMIUM|(?<![A-Z])PRM(?![A-Z]|-?\d)'],
 'VISATERRY': [r'VISATER|VISSATER|VSTERY'],
}
UNCLEAR = {k: re.compile('|'.join(f'(?:{p})' for p in v)) for k, v in UNCLEAR.items()}
mat_keep, mat_drop = [], []
for i, c, n in d['mat']:
    C = c.strip().upper(); N = ws_(n)
    if len(c.strip()) != 4 or c != c.strip() or not N:
        mat_drop.append((i, C, n, 'kode tidak standar / nama kosong')); continue
    if re.search(r'\+(?!\d)|(?<!\d)\+', N):
        mat_drop.append((i, C, n, 'material gabungan (+)')); continue
    if PROCESS.search(N):
        mat_drop.append((i, C, n, 'material process')); continue
    hit = [k for k, rx in UNCLEAR.items() if rx.search(N)]
    if hit and usedp[C]:   # A1: dipakai di daftar ERP / aplikasi selalu masuk
        mat_keep.append((i, C, n, 'dipakai di ERP (kata: ' + ', '.join(hit) + ')')); continue
    if hit:
        mat_drop.append((i, C, n, 'kata tidak jelas: ' + ', '.join(hit))); continue
    mat_keep.append((i, C, n, ''))

pickle.dump(dict(col_keep=col_keep, col_drop=col_drop, dim_keep=dim_keep, dim_drop=dim_drop, mat_keep=mat_keep, mat_drop=mat_drop), open('filt.pkl', 'wb'))
def summ(name, keep, drop, ri):
    print(f'== {name}: masuk {len(keep)}, tidak {len(drop)}')
    print('   alasan keluar:', collections.Counter(r[ri].split(':')[0] for r in drop).most_common())
    print('   alasan masuk:', collections.Counter(r[-1] for r in keep).most_common())
summ('warna', col_keep, col_drop, 3); summ('dimension', dim_keep, dim_drop, 4); summ('material', mat_keep, mat_drop, 3)
