# Build R21: salin exports/build_r20.json (R20 belum ada export user, app belum diubah) -> edit di tempat -> exports/build_r21.json.
# SQL R21: sql/R21_kamus.sql + sql/R21_kamus_isi_1..6.sql (tools/kamus/gen_sql.py). PLAN §6 R21: kamus kode ERP per pabrik.
#  1. page baru Code Dictionary (salinan Master Options): baca saja, izin view_drafts (Vendor Spec, Vendor CBD, Manager
#     Costing; Brand tidak). Satu jenis kamus per pencarian (Material prefix / Dimension code / Color code), cari kode atau
#     teks. q_dict paling banyak 200 baris (+ total_count), jumlah varian dihitung dengan satu kali baca varian pabrik.
#     Hanya jenis yang dipilih yang dimuat.
#  2. (revisi user 30 Okt 2026) Code Dictionary = sub menu Master Material: page tersembunyi dari menu samping (seperti
#     Material Detail), tombol Code Dictionary di Master Material, tombol <- Master Material di page ini. Tanpa kartu Home,
#     tanpa filter Source / Usage.
#  3. cwBomGrid + cwVariantForm: canonThickness "NO.1" tidak jadi "NO0.1" (sama dengan fn_clean_thickness R21)
#  Hint kode (q_code_hint) tidak berubah: arti dari kamus tampil "recorded in ERP dictionary" (ref dari DB).
# Custom Widget yang ditimpa dicek dulu: isi di app = repo di commit R20 (11a8935), lalu diganti isi repo sekarang.
# Pakai: python -X utf8 -I tools/build_r21.py [base.json]   (default base = exports/build_r20.json)
import copy, json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, TOKEN, rd, sub1, add_event, set_binding, col_cv, text_col_from, table_set_columns, lock_manual_queries

R20_COMMIT = '11a8935'     # R20 bagian 4-7; build_r20.json = isi repo di commit ini


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


def git_head(path):
    return subprocess.run(['git', '-C', ROOT, 'show', f'{R20_COMMIT}:appsmith/{path}'], capture_output=True, text=True,
                          encoding='utf-8', check=True).stdout


def squash(s):
    return ''.join(s.split())


BASE = sys.argv[1] if len(sys.argv) > 1 else f'{ROOT}/exports/build_r20.json'
OUT = f'{ROOT}/exports/build_r21.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R21'
SPEC, MD, HOME = 'Specsheet', 'Material Detail', 'Home'

# ---------------------------------------------------------------- 3. Custom Widget dari repo (cek dulu = commit R20)
CW = {'cwBomGrid': [SPEC], 'cwVariantForm': [MD, SPEC]}
PART = (('html', 'index.html'), ('css', 'style.css'), ('js', 'script.js'))
for n, pages in CW.items():
    for pg in pages:
        w = app.widget(pg, n)
        for part, fn in PART:
            assert squash(w['uncompiledSrcDoc'][part]) == squash(git_head(f'widgets/{n}/{fn}')), f'{pg}/{n} {part} beda dengan repo R20'
for n, pages in CW.items():
    for pg in pages:
        app.set_cw_source(pg, n, html=rd(f'widgets/{n}/index.html'), css=rd(f'widgets/{n}/style.css'),
                          js=rd(f'widgets/{n}/script.js'))
app.note('Custom Widget dari repo: ' + ', '.join(CW))

# ---------------------------------------------------------------- 1. page baru Code Dictionary (salinan Master Options)
SRC_PG, NEW_PG = 'Master Options', 'Code Dictionary'
new_page = copy.deepcopy(app.page(SRC_PG))
new_page['gitSyncId'] = app.new_git()
up = new_page['unpublishedPage']
up['name'] = NEW_PG
up['slug'] = 'code-dictionary'
up['isHidden'] = True                 # sub menu Master Material (revisi user 30 Okt 2026)
lay = up['layouts'][0]
lay['id'] = NEW_PG
lay['layoutOnLoadActions'] = json.loads(json.dumps(lay['layoutOnLoadActions']).replace(f'"{SRC_PG}_', f'"{NEW_PG}_'))
WREN = {'inpPilihanCari': 'inpKamusCari', 'selPilihanJenis': 'selKamusJenis', 'btnPilihanCari': 'btnKamusCari',
        'tblPilihan': 'tblKamus', 'txtPilihanInfo': 'txtKamusInfo'}


def regen(node, parent_id):
    if node['widgetId'] != '0':
        node['widgetId'] = app.new_wid()
        node['parentId'] = parent_id
    node['key'] = app.new_wid()
    node['widgetName'] = WREN.get(node['widgetName'], node['widgetName'])
    for ch in node.get('children', []) or []:
        regen(ch, node['widgetId'])


regen(lay['dsl'], None)
lay['dsl']['children'] = [c for c in lay['dsl']['children'] if c['widgetName'] not in ('btnPilihanTambah', 'mdlPilihan')]
pos = next(i for i, p in enumerate(d['pageList']) if p['unpublishedPage']['name'] == MD) + 1
d['pageList'].insert(pos, new_page)
for key in ('pages', 'publishedPages'):
    pages = d['exportedApplication'].get(key)
    if pages:
        pos2 = next(i for i, p in enumerate(pages) if p['id'] == MD) + 1
        pages.insert(pos2, {'id': NEW_PG, 'isDefault': False})


def clone_action(a, new_name=None, coll=None):
    a2 = json.loads(json.dumps(a).replace(f'"{SRC_PG}_', f'"{NEW_PG}_'))
    a2['gitSyncId'] = app.new_git()
    for k in ('unpublishedAction', 'publishedAction'):
        if k in a2 and a2[k]:
            a2[k]['pageId'] = NEW_PG
    u = a2['unpublishedAction']
    if new_name:
        u['name'] = new_name
        a2['id'] = f'{NEW_PG}_{new_name}'
    if coll:                                       # fungsi JSObject pindah ke koleksi lain (OptionCtrl -> DictCtrl)
        u['collectionId'] = f'{NEW_PG}_{coll}'
        u['fullyQualifiedName'] = f'{coll}.{u["name"]}'
        a2['id'] = f'{NEW_PG}_{coll}.{u["name"]}'
    return a2


for a in [x for x in d['actionList'] if x['unpublishedAction']['pageId'] == SRC_PG]:
    u = a['unpublishedAction']
    cid = u.get('collectionId') or ''
    if cid == f'{SRC_PG}_OptionCtrl':
        d['actionList'].append(clone_action(a, coll='DictCtrl'))
    elif cid or u['name'] == 'q_me':
        d['actionList'].append(clone_action(a))
    elif u['name'] == 'q_options':
        d['actionList'].append(clone_action(a, 'q_dict'))
for c in [x for x in d['actionCollectionList'] if x['unpublishedCollection']['pageId'] == SRC_PG]:
    nm = c['unpublishedCollection']['name']
    c2 = json.loads(json.dumps(c).replace(f'"{SRC_PG}_', f'"{NEW_PG}_'))
    c2['gitSyncId'] = app.new_git()
    for k in ('unpublishedCollection', 'publishedCollection'):
        if k in c2 and c2[k]:
            c2[k]['pageId'] = NEW_PG
            if nm == 'OptionCtrl':
                c2[k]['name'] = 'DictCtrl'
    if nm == 'OptionCtrl':
        c2['id'] = f'{NEW_PG}_DictCtrl'
    d['actionCollectionList'].append(c2)
app.note(f'page baru {NEW_PG} (salinan {SRC_PG}, tanpa modal / tombol Add, OptionCtrl -> DictCtrl, q_options -> q_dict)')

PG = NEW_PG
app.set_js(PG, 'DictCtrl', js('js/DictCtrl.js'))
app.replace_js(PG, 'Auth', [
    ("\trequiredPerm: 'view_master',", "\trequiredPerm: 'view_drafts',      // R21: Brand tidak melihat kamus pabrik"),
    ('\t\treturn [q_options];', '\t\treturn [q_dict];'),
    ("\tpageName: 'Master Options',", "\tpageName: 'Code Dictionary',"),
    ("\t\treturn ['inpPilihanCari', 'selPilihanJenis', 'tblPilihan'];",
     "\t\treturn ['inpKamusCari', 'selKamusJenis', 'tblKamus'];"),
])
app.set_query(PG, 'q_dict', run_behaviour='MANUAL', body=f'''WITH a AS (SELECT fn_user_factory(fn_auth({TOKEN}, 'view_drafts')) AS fac),
p AS (SELECT coalesce(nullif({{{{selKamusJenis.selectedOptionValue || 'MATERIAL'}}}}, ''), 'MATERIAL') AS kind,
             upper(regexp_replace({{{{inpKamusCari.text || ''}}}}, '\\s+', '', 'g')) AS q_code,
             fn_tight_key({{{{inpKamusCari.text || ''}}}}) AS q_key),
-- R21: pemakaian per bagian kode, satu kali baca varian pabrik ini
u AS (SELECT v.factory_id, CASE p.kind WHEN 'MATERIAL' THEN left(v.code, 4) WHEN 'DIMENSION' THEN substr(v.code, 5, 3)
                                       ELSE substr(v.code, 8, 3) END AS code, count(*)::int AS variants
        FROM p, a JOIN material_variant v ON a.fac IS NULL OR v.factory_id = a.fac
       WHERE length(v.code) = 10
       GROUP BY 1, 2),
d AS (SELECT d.factory_id, d.code, d.name AS meaning, d.source, m.name AS app_material,
             d.created_at, d.created_by, d.name_key || ' ' || coalesce(fn_tight_key(m.name), '') AS k
        FROM p JOIN code_dict_material d ON p.kind = 'MATERIAL' LEFT JOIN material m ON m.id = d.material_id
      UNION ALL
      SELECT d.factory_id, d.code, coalesce(nullif(d.thickness, ''), '(None)'), d.source, NULL,
             d.created_at, d.created_by, coalesce(nullif(d.search_key, ''), 'none')
        FROM p JOIN code_dict_dimension d ON p.kind = 'DIMENSION'
      UNION ALL
      SELECT d.factory_id, d.code, d.color, d.source, NULL, d.created_at, d.created_by, d.color_key
        FROM p JOIN code_dict_color d ON p.kind = 'COLOR')
SELECT d.code, d.meaning, d.app_material, d.source, coalesce(u.variants, 0) AS variants, d.created_at, d.created_by,
       count(*) OVER () AS total_count
  FROM d CROSS JOIN a CROSS JOIN p
  LEFT JOIN u ON u.factory_id = d.factory_id AND u.code = d.code
 WHERE (a.fac IS NULL OR d.factory_id = a.fac)
   AND (p.q_key = '' OR d.code LIKE p.q_code || '%' OR d.k LIKE '%' || p.q_key || '%')
 ORDER BY d.code
 LIMIT 200;''')

# widget: header, filter, info, tabel
hdr = app.widget(PG, 'cwHeader')
hdr['defaultModel'] = sub1(hdr['defaultModel'], "pageTitle: 'Master Options'", "pageTitle: 'Code Dictionary'", 'cwHeader')
LOAD = '{{Util.load(q_dict)}}'


def place(w, top, bottom, left, right):
    w.update(topRow=float(top), bottomRow=float(bottom), leftColumn=float(left), rightColumn=float(right),
             mobileTopRow=float(top), mobileBottomRow=float(bottom), mobileLeftColumn=float(left), mobileRightColumn=float(right))


sel = app.widget(PG, 'selKamusJenis')
set_binding(sel, 'sourceData', '{{DictCtrl.kindOptions}}')
sel.update(defaultOptionValue='MATERIAL', placeholderText='Select type', onOptionChange=LOAD)
place(sel, 10, 14, 11, 27)
inp = app.widget(PG, 'inpKamusCari')
inp['placeholderText'] = 'Search code or meaning…'
add_event(inp, 'onSubmit', LOAD) if 'events' in inp else None
if 'events' not in inp:                        # INPUT_WIDGET_V2 tanpa daftar events: onSubmit sebagai trigger biasa
    inp['onSubmit'] = LOAD
    for lk in ('dynamicTriggerPathList', 'dynamicPropertyPathList'):
        lst = inp.setdefault(lk, [])
        if not any(x['key'] == 'onSubmit' for x in lst):
            lst.append({'key': 'onSubmit'})
place(inp, 10, 14, 27, 53)
btn = app.widget(PG, 'btnKamusCari')
btn['onClick'] = LOAD
place(btn, 10, 14, 53, 64)
back = app.clone_widget(PG, 'btnKamusCari', 'btnKamusKembali')
back.update(text='\u2190 Master Material', onClick="{{navigateTo('Master Material')}}")
place(back, 10, 14, 0, 11)
info = app.widget(PG, 'txtKamusInfo')
set_binding(info, 'text', '{{DictCtrl.note()}}')
place(info, 15, 19, 0, 64)
lim = app.clone_widget(PG, 'txtKamusInfo', 'txtKamusLimit')
set_binding(lim, 'text', '{{DictCtrl.limitNote()}}')
lim['textColor'] = '#B45309'
place(lim, 19, 23, 0, 64)

t = app.widget(PG, 'tblKamus')
tpl = t['primaryColumns']['value']
cols = {
    'code': text_col_from(tpl, 'tblKamus', 'code', 'Code', 90.0),
    'meaning': text_col_from(tpl, 'tblKamus', 'meaning', 'Meaning (ERP name / dimension / color)', 380.0),
    'app_material': text_col_from(tpl, 'tblKamus', 'app_material', 'App material', 260.0),
    'source': text_col_from(tpl, 'tblKamus', 'source', 'Source', 110.0),
    'variants': text_col_from(tpl, 'tblKamus', 'variants', 'App variants', 110.0),
    'created_at': text_col_from(tpl, 'tblKamus', 'created_at', 'Added', 150.0),
    'created_by': text_col_from(tpl, 'tblKamus', 'created_by', 'Added by', 200.0),
    'total_count': text_col_from(tpl, 'tblKamus', 'total_count', 'total_count', 100.0, visible=False),
}
cols['created_at']['computedValue'] = col_cv('tblKamus', 'created_at', 'Util.fmtDateTime(currentRow.created_at)')
cols['variants']['horizontalAlignment'] = 'CENTER'
cols['source']['horizontalAlignment'] = 'CENTER'
t['primaryColumns'] = cols
t['primaryColumnId'] = 'code'
t['tableData'] = '{{q_dict.data}}'
t['label'] = 'Codes'
t['dynamicPropertyPathList'] = [x for x in t.get('dynamicPropertyPathList', []) if not x['key'].startswith('primaryColumns.')]
table_set_columns(t, list(cols))
place(t, 24, 99, 0, 64)
app.note('Code Dictionary: btnKamusKembali / selKamusJenis / inpKamusCari / btnKamusCari, txtKamusInfo + txtKamusLimit, '
         'tblKamus (Code, Meaning, App material, Source, App variants, Added, Added by)')

# ---------------------------------------------------------------- 2. Master Material: tombol Code Dictionary (sub menu)
MM = 'Master Material'
kb = app.clone_widget(MM, 'btnMaterialCari', 'btnMaterialKamus')
kb.update(text='Code Dictionary', onClick="{{Util.goDetail('Master Material', 'Code Dictionary')}}")
set_binding(kb, 'isVisible', "{{Auth.can('view_drafts')}}")
place(kb, 14, 18, 17, 33)
app.note('Master Material: tombol Code Dictionary (view_drafts, filter Master Material tetap saat kembali)')

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
for n in app.log:
    print(n)
