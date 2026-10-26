# Build R17: salin exports/export_r16.json (export user 22 Okt 2026 = build_r16 + tata letak tabel) -> edit di tempat -> exports/build_r17.json.
# SQL: sql/R17_remember_estimate.sql (jalankan dulu). Bagian 1 = page Login; bagian 2 = estimasi CBD + kode wajib mulai SMS (lihat bawah). Login:
#  - cwLogin: checkbox "Remember me" + catatan (HTML, CSS, JS dari repo); email tersimpan diisikan walau datang setelah render
#  - LoginCtrl: kirim remember ke a_login, simpan email terakhir (appsmith.store.lastEmail, persist)
#  - a_login: fn_login(email, password, remember)
#  - Default model cwLogin: email = LoginCtrl.lastEmail atau email tersimpan
# Pakai: python -X utf8 -I tools/build_r17.py [base.json]   (default base = exports/export_r16.json)
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, rd, lock_manual_queries, set_binding, sub1


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


def git_head(path):
    return subprocess.run(['git', '-C', ROOT, 'show', f'HEAD:appsmith/{path}'], capture_output=True, text=True,
                          encoding='utf-8', check=True).stdout


def squash(s):
    return ''.join(s.split())


BASE = sys.argv[1] if len(sys.argv) > 1 else f'{ROOT}/exports/export_r16.json'
OUT = f'{ROOT}/exports/build_r17.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R17'
PG = 'Login'

# ---------------------------------------------------------------- cek: app = repo R16 (git HEAD) untuk yang akan ditimpa
head = git_head('js/LoginCtrl.js')
assert squash(app.js_body(PG, 'LoginCtrl')) == squash(head[head.index('export default'):]), 'LoginCtrl: isi di app beda dengan repo R16'
w = app.widget(PG, 'cwLogin')
for part, fn in (('html', 'index.html'), ('css', 'style.css'), ('js', 'script.js')):
    assert squash(w['uncompiledSrcDoc'][part]) == squash(git_head(f'widgets/cwLogin/{fn}')), f'cwLogin {part} beda dengan repo R16'

# ---------------------------------------------------------------- query login
q = app.action(PG, 'a_login')['unpublishedAction']['actionConfiguration']['body']
q = sub1(q, '{{this.params.password}})',
         "{{this.params.password}}, {{this.params.remember === true ? 'true' : 'false'}}::boolean)", 'a_login')
app.set_query(PG, 'a_login', body=q)

# ---------------------------------------------------------------- JSObject + widget
app.set_js(PG, 'LoginCtrl', js('js/LoginCtrl.js'))
app.set_cw_source(PG, 'cwLogin', html=rd('widgets/cwLogin/index.html'), css=rd('widgets/cwLogin/style.css'),
                  js=rd('widgets/cwLogin/script.js'))
w = app.widget(PG, 'cwLogin')
set_binding(w, 'defaultModel', sub1(w['defaultModel'], 'email: LoginCtrl.lastEmail',
                                    "email: LoginCtrl.lastEmail || appsmith.store.lastEmail || ''", 'cwLogin defaultModel'))
app.note('Login: Remember me (cwLogin, LoginCtrl, a_login)')

# ================================================================ R17 bagian 2: kode wajib mulai SMS + harga ESTIMATE
CBD = 'Cost Breakdown (CBD)'
SPEC = 'Specsheet'
for pg, n in ((CBD, 'CbdGridCtrl'), (CBD, 'CbdCtrl'), (CBD, 'CbdExportCtrl'), (SPEC, 'SpecCtrl')):
    head = git_head(f'js/{n}.js')
    assert squash(app.js_body(pg, n)) == squash(head[head.index('export default'):]), f'{n}: isi di app beda dengan repo R16'
for wn in ('cwCbdGrid', 'cwCbdPriceForm'):
    w = app.widget(CBD, wn)
    for part, fn in (('html', 'index.html'), ('css', 'style.css'), ('js', 'script.js')):
        assert squash(w['uncompiledSrcDoc'][part]) == squash(git_head(f'widgets/{wn}/{fn}')), f'{wn} {part} beda dengan repo R16'

# q_cbd_lines: + can_estimate (baris Catalog tanpa Material Code di Pullover / Preview)
q = app.action(CBD, 'q_cbd_lines')['unpublishedAction']['actionConfiguration']['body']
app.set_query(CBD, 'q_cbd_lines', body=sub1(q, 'coalesce(pc.pending, false) AS pending\n',
                                            'coalesce(pc.pending, false) AS pending,\n       coalesce(pc.can_estimate, false) AS can_estimate\n',
                                            'q_cbd_lines'))
# saran estimasi terakhir (form Estimate: tombol Use; Propose master price: isian awal)
app.add_query(CBD, 'q_cbd_estimate_hint', 'q_cbd_checklist',
              "SELECT * FROM fn_cbd_estimate_hint({{appsmith.store.token}}, nullif({{this.params.line_id || ''}}, '')::uuid);")

for pg, n in ((CBD, 'CbdGridCtrl'), (CBD, 'CbdCtrl'), (CBD, 'CbdExportCtrl'), (SPEC, 'SpecCtrl')):
    app.set_js(pg, n, js(f'js/{n}.js'))
for wn in ('cwCbdGrid', 'cwCbdPriceForm'):
    app.set_cw_source(CBD, wn, html=rd(f'widgets/{wn}/index.html'), css=rd(f'widgets/{wn}/style.css'),
                      js=rd(f'widgets/{wn}/script.js'))
app.note('CBD: estimasi (cwCbdGrid, cwCbdPriceForm, CbdGridCtrl, CbdCtrl, CbdExportCtrl, q_cbd_lines, q_cbd_estimate_hint); '
         'Specsheet: checklist sel kuning per stage (SpecCtrl)')

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
for n in app.log:
    print(n)
