# Build R13: salin exports/export_r12.json (= export user "Product Management R12", 13 Okt 2026; sama dengan build_r12
# kecuali tata letak kecil) -> edit di tempat -> exports/build_r13.json. SQL: sql/R13_cbd_stage.sql (jalankan dulu).
# Isi: CBD per stage — stage dipilih saat Buat CBD, refresh tidak memindahkan stage, chip/Tugas Saya "perlu CBD <stage>".
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, TOKEN, rd, lock_manual_queries


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


def cw(app, page, name):
    app.set_cw_source(page, name, html=rd(f'widgets/{name}/index.html'), css=rd(f'widgets/{name}/style.css'),
                      js=rd(f'widgets/{name}/script.js'))


BASE = f'{ROOT}/exports/export_r12.json'
OUT = f'{ROOT}/exports/build_r13.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R13'
CBD = 'Cost Breakdown (CBD)'

# ---------------------------------------------------------------- query
# chip article: label specsheet stage draft + CBD terbit tertinggal stage
q = app.action(CBD, 'q_cbd_articles')['unpublishedAction']['actionConfiguration']['body']
old = '       v.pub_id, v.pub_label, v.pub_sync\n'
assert q.count(old) == 1
app.set_query(CBD, 'q_cbd_articles', body=q.replace(old, '''       v.pub_id, v.pub_label, v.pub_sync,
       CASE WHEN pr.drafts THEN v.draft_spec_label END AS draft_spec_label,
       v.pub_behind
'''))

# Buat CBD: stage dipilih
q = app.action(CBD, 'a_cbd_create')['unpublishedAction']['actionConfiguration']['body']
old = "nullif({{this.params.source_article_id}}, '')::uuid) AS id;"
assert q.count(old) == 1
app.set_query(CBD, 'a_cbd_create', body=q.replace(old, "nullif({{this.params.source_article_id}}, '')::uuid,\n"
                                                       "                     nullif({{this.params.stage || ''}}, '')) AS id;"))

app.add_query(CBD, 'q_cbd_stages', 'q_cbd_sources', f'''-- R13: pilihan stage di form Buat CBD
SELECT stage, stage_order, spec_label, next_no, next_label, available, note, is_default
FROM fn_cbd_stage_options({TOKEN}, nullif({{{{this.params.article_id || ''}}}}, '')::uuid)
ORDER BY stage_order;''')

# ---------------------------------------------------------------- JSObject & Custom Widget
app.set_js(CBD, 'CbdCtrl', js('js/CbdCtrl.js'))
app.set_js(CBD, 'CbdGridCtrl', js('js/CbdGridCtrl.js'))
app.set_js('Beranda', 'BerandaCtrl', js('js/BerandaCtrl.js'))
cw(app, CBD, 'cwCbdForm')

# form lebih tinggi (baris pilihan stage + kotak article sumber): 34 -> 52 baris
w, canvas = app.widget(CBD, 'cwCbdForm', with_parent=True)
assert (w['topRow'], w['bottomRow']) == (0, 34), (w['topRow'], w['bottomRow'])
w['bottomRow'] = 52
m = app.widget(CBD, 'mdlCbdBaru')
canvas['bottomRow'] = max(canvas['bottomRow'], 540)
m['height'] = max(m.get('height') or 0, 540)
m['bottomRow'] = m['topRow'] + 54

# ---------------------------------------------------------------- bersih-bersih (scan R13: tidak dipakai di mana pun)
# Util.fmtRp / Util.prettyJson (13 page), ModelDetailCtrl.attachments, CbdCtrl.STAGES
for pg in [p['unpublishedPage']['name'] for p in d['pageList']]:
    app.set_js(pg, 'Util', js('js/Util.js'))
app.set_js('Model Detail', 'ModelDetailCtrl', js('js/ModelDetailCtrl.js'))
# switch filter sisa F3 (tersembunyi permanen, tanpa onChange, tidak dirujuk query/JS)
for n in ('swMaterialBelumHarga', 'swMaterialHargaPending'):
    w, parent = app.widget('Master Material', n, with_parent=True)
    assert w['isVisible'] is False and not w.get('onChange')
    parent['children'].remove(w)
    app.note(f'widget Master Material/{n} dihapus')

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
for n in app.log:
    print(n)
