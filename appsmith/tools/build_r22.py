# Build R22: salin exports/build_r21.json (belum ada export user setelah R21) -> edit di tempat -> exports/build_r22.json.
# SQL R22: sql/R22_kamus.sql (tools/kamus/gen_r22.py). PLAN §6 R22: kamus ERP = sumber pilihan + pembentuk kode.
#  1. cwBomGrid + BomCtrl: saran material / Dimension / warna juga dari kamus ERP (dicari ke server, maksimal 8 baris, event
#     onSearch + query q_dict_search). Material dari kamus yang belum ada di app: dipilih -> form + New material terbuka sendiri.
#  2. Halaman Code Dictionary + tombol di Master Material + DictCtrl dihapus dari UI (tabel kamus tetap di database).
# Custom Widget / JSObject yang ditimpa dicek dulu: isi di app = repo di commit R21 (d00a8ac), lalu diganti isi repo sekarang.
# Pakai: python -X utf8 -I tools/build_r22.py [base.json]   (default base = exports/build_r21.json)
import json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, rd, add_event, lock_manual_queries

R21_COMMIT = 'd00a8ac'


def js(path):
    s = rd(path)
    return s[s.index('export default'):]


def git_head(path):
    return subprocess.run(['git', '-C', ROOT, 'show', f'{R21_COMMIT}:appsmith/{path}'], capture_output=True, text=True,
                          encoding='utf-8', check=True).stdout


def squash(s):
    return ''.join(s.split())


BASE = sys.argv[1] if len(sys.argv) > 1 else f'{ROOT}/exports/build_r21.json'
OUT = f'{ROOT}/exports/build_r22.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R22'
SPEC, MM, DICT_PG = 'Specsheet', 'Master Material', 'Code Dictionary'

# ---------------------------------------------------------------- 1. cwBomGrid + BomCtrl + q_dict_search
w = app.widget(SPEC, 'cwBomGrid')
for part, fn in (('html', 'index.html'), ('css', 'style.css'), ('js', 'script.js')):
    assert squash(w['uncompiledSrcDoc'][part]) == squash(git_head(f'widgets/cwBomGrid/{fn}')), f'cwBomGrid {part} beda dengan repo R21'
app.set_cw_source(SPEC, 'cwBomGrid', html=rd('widgets/cwBomGrid/index.html'), css=rd('widgets/cwBomGrid/style.css'),
                  js=rd('widgets/cwBomGrid/script.js'))
add_event(w, 'onSearch', '{{BomCtrl.onSearch()}}')
app.note('cwBomGrid: event onSearch')

old_ctrl = app.js_body(SPEC, 'BomCtrl')
assert squash(old_ctrl) == squash(js('js/BomCtrl.js').replace(js('js/BomCtrl.js'), git_head('js/BomCtrl.js')[git_head('js/BomCtrl.js').index('export default'):])), 'BomCtrl beda dengan repo R21'
app.set_js(SPEC, 'BomCtrl', js('js/BomCtrl.js'))
app.add_query(SPEC, 'q_dict_search', 'q_similar',
              "SELECT label, code FROM fn_dict_search({{appsmith.store.token}}, {{this.params.kind}}, {{this.params.q}});")

# ---------------------------------------------------------------- 2. hapus Code Dictionary dari UI
kb, parent = app.widget(MM, 'btnMaterialKamus', with_parent=True)
parent['children'].remove(kb)
d['pageList'] = [p for p in d['pageList'] if p['unpublishedPage']['name'] != DICT_PG]
for key in ('pages', 'publishedPages'):
    pages = d['exportedApplication'].get(key)
    if pages:
        d['exportedApplication'][key] = [p for p in pages if p['id'] != DICT_PG]
d['actionList'] = [a for a in d['actionList'] if a['unpublishedAction']['pageId'] != DICT_PG]
d['actionCollectionList'] = [c for c in d['actionCollectionList'] if c['unpublishedCollection']['pageId'] != DICT_PG]
app.note('Code Dictionary: page, query, JSObject, dan tombol di Master Material dihapus')

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
for n in app.log:
    print(n)
