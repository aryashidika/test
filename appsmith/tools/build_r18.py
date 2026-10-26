# Build R18: salin exports/export_r17.json (export user 26 Okt 2026 = build_r17, hanya format ulang Appsmith) -> edit di tempat
# -> exports/build_r18.json. SQL: sql/R18_dimension.sql (pesan DB). Hanya teks yang terlihat user:
#  - Specsheet: tombol btnBuatRevisi "+ Create Revision" -> "+ Create" + pesan kosong SpecCtrl ikut (judul form / catatan Publish tetap)
#  - Thickness -> Dimension di label, kolom, pesan, placeholder, header Excel (specsheet & CBD)
#  - nama kolom DB, fungsi SQL (fn_clean_thickness ...), variabel / id JS TIDAK diganti
# Pakai: python -X utf8 -I tools/build_r18.py --repo   (sekali: terapkan PAIRS ke file repo js/ & widgets/)
#        python -X utf8 -I tools/build_r18.py [base.json]   (default base = exports/export_r17.json)
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, rd, wr, lock_manual_queries, sub1

# file repo -> [(lama, baru)]; tiap 'lama' harus muncul tepat 1x
PAIRS = {
    'widgets/cwBomGrid/script.js': [
        ("${x.v.thickness || 'no thickness'} · ${x.v.color})`)", "${x.v.thickness || 'no dimension'} · ${x.v.color})`)"),
        ('has several thicknesses. Pick from the list (NAME · THICKNESS)', 'has several dimensions. Pick from the list (NAME · DIMENSION)'),
        ("${v.thickness || 'no thickness'} · ${v.color}. It does not match the material / thickness of this line.",
         "${v.thickness || 'no dimension'} · ${v.color}. It does not match the material / dimension of this line."),
        ("placeholder: 'Name · thickness / Material Code…'", "placeholder: 'Name · dimension / Material Code…'"),
        ("'New thickness for this material: no variants yet.", "'New dimension for this material: no variants yet."),
        ('Type another material / thickness (or Material Code)', 'Type another material / dimension (or Material Code)'),
        ('a variant of this material + thickness. The specsheet', 'a variant of this material + dimension. The specsheet'),
        ("${line.thickness || 'no thickness'} · ${v}`", "${line.thickness || 'no dimension'} · ${v}`"),
        ("['c-thk', 'Thickness'], ['c-rem', 'Remarks']", "['c-thk', 'Dimension'], ['c-rem', 'Remarks']"),
    ],
    'widgets/cwVariantForm/script.js': [
        ("cleanThick(s) || 'no thickness';", "cleanThick(s) || 'no dimension';"),
        ("${field === 'thickness' ? 'Thickness' : 'Color'} code", "${field === 'thickness' ? 'Dimension' : 'Color'} code"),
        ("['t', 'Thickness', 'never used yet.", "['t', 'Dimension', 'never used yet."),
        ('out.push(`Thickness code ${code.substr(4, 3)}', 'out.push(`Dimension code ${code.substr(4, 3)}'),
        ("out.push(`Thickness ${thickLabel(", "out.push(`Dimension ${thickLabel("),
    ],
    'widgets/cwVariantForm/index.html': [
        ('4 material type · 3 thickness · 3 color. Filled in from color &amp; thickness',
         '4 material type · 3 dimension · 3 color. Filled in from color &amp; dimension'),
        ('<label for="thickness">Thickness</label>', '<label for="thickness">Dimension</label>'),
    ],
    'widgets/cwMaterialForm/index.html': [
        ('No thickness &amp; color here.', 'No dimension &amp; color here.'),
        ('(thickness × color → Material Code)', '(dimension × color → Material Code)'),
    ],
    'widgets/cwCbdGrid/script.js': [
        ("['c-thk', 'Thickness']", "['c-thk', 'Dimension']"),
    ],
    'widgets/cwPriceApproval/script.js': [
        ("[['Material Code'], ['Color'], ['Thickness'],", "[['Material Code'], ['Color'], ['Dimension'],"),
    ],
    'widgets/cwPriceForm/index.html': [
        ('placeholder="Search code / color / thickness"', 'placeholder="Search code / color / dimension"'),
    ],
    'widgets/cwRevisionForm/script.js': [
        ('are copied (material, thickness, supplier).', 'are copied (material, dimension, supplier).'),
    ],
    'js/BomCtrl.js': [
        ("${c.thickness || 'no thickness'}`", "${c.thickness || 'no dimension'}`"),
    ],
    'js/CbdCtrl.js': [
        ('for origin lines with the same material + thickness;', 'for origin lines with the same material + dimension;'),
    ],
    'js/CbdExportCtrl.js': [
        ("'Material description', 'Thickness', 'Unit'", "'Material description', 'Dimension', 'Unit'"),
    ],
    'js/SpecCtrl.js': [        # 26 Okt 2026 (user): pesan kosong ikut nama tombol baru
        ('No revisions yet. Click "+ Create Revision".', 'No revisions yet. Click "+ Create".'),
    ],
    'js/SpecExportCtrl.js': [
        ("['THICKNESS', THK]", "['DIMENSION', THK]"),
    ],
}
PART = {'index.html': 'html', 'style.css': 'css', 'script.js': 'js'}


def apply(text, pairs, where):
    for old, new in pairs:
        text = sub1(text, old, new, where)
    return text


def squash(s):
    return ''.join(s.split())


if '--repo' in sys.argv:
    for path, pairs in PAIRS.items():
        wr(path, apply(rd(path), pairs, path))
        print('repo', path)
    sys.exit(0)

BASE = sys.argv[1] if len(sys.argv) > 1 else f'{ROOT}/exports/export_r17.json'
OUT = f'{ROOT}/exports/build_r18.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R18'
PAGES = [p['unpublishedPage']['name'] for p in d['pageList']]

# ---------------------------------------------------------------- Custom Widget & JSObject: PAIRS pada isi app, hasil = repo
for path, pairs in PAIRS.items():
    kind, name, fn = (path.split('/') + [''])[:3]
    hits = 0
    for pg in PAGES:
        if kind == 'js':
            n = name[:-3]
            try:
                body = app.js_body(pg, n)
            except Exception:
                continue
            new = apply(body, pairs, f'{pg}/{n}')
            r = rd(path)
            assert squash(new) == squash(r[r.index('export default'):]), f'{pg}/{n}: hasil beda dengan repo (jalankan --repo dulu?)'
            app.set_js(pg, n, new)
        else:
            try:
                w = app.widget(pg, name)
            except KeyError:
                continue
            new = apply(w['uncompiledSrcDoc'][PART[fn]], pairs, f'{pg}/{name}/{fn}')
            assert squash(new) == squash(rd(path)), f'{pg}/{name}/{fn}: hasil beda dengan repo (jalankan --repo dulu?)'
            app.set_cw_source(pg, name, **{PART[fn]: new})
        hits += 1
    assert hits, f'{path}: tidak ditemukan di app'

# ---------------------------------------------------------------- tabel: label kolom
for pg, t in (('Material Detail', 'tblVariants'), ('Material Detail', 'tblPrices')):
    col = app.widget(pg, t)['primaryColumns']['thickness_label']
    assert col['label'] == 'Thickness', f'{t}.thickness_label label = {col["label"]!r}'
    col['label'] = 'Dimension'
app.note('Tabel tblVariants, tblPrices: kolom Thickness -> Dimension')

# ---------------------------------------------------------------- tombol Specsheet
w = app.widget('Specsheet', 'btnBuatRevisi')
assert w['text'] == '+ Create Revision', w['text']
w['text'] = '+ Create'
app.note('Specsheet: btnBuatRevisi "+ Create Revision" -> "+ Create"')

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
for n in app.log:
    print(n)
