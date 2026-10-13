# Build R14: salin exports/build_r13.json (app user R13 tidak diubah, hanya di-deploy; keputusan user 13 Okt 2026)
# -> edit di tempat -> exports/build_r14.json. SQL: sql/R14_audit_stage.sql (jalankan dulu).
# Isi: panel detail audit (cwAuditDetail) + stage Preview & label stage (Pullover, Preview, SMS, GTM, Production).
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, rd, lock_manual_queries


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


def cw(app, page, name, src=None):
    src = src or name
    app.set_cw_source(page, name, html=rd(f'widgets/{src}/index.html'), css=rd(f'widgets/{src}/style.css'),
                      js=rd(f'widgets/{src}/script.js'))


BASE = f'{ROOT}/exports/build_r13.json'
OUT = f'{ROOT}/exports/build_r14.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R14'
CBD = 'Cost Breakdown (CBD)'
PAGES = [p['unpublishedPage']['name'] for p in d['pageList']]

# ---------------------------------------------------------------- query: label stage lewat fn_rev_label
LBL = re.compile(r"\b(\w+)\.stage \|\| ' r' \|\| \1\.revision_no")
n_lbl = 0
for a in d['actionList']:
    u = a['unpublishedAction']
    body = (u.get('actionConfiguration') or {}).get('body') or ''
    if a.get('pluginType') != 'DB' or u.get('collectionId') or not LBL.search(body):
        continue
    new, n = LBL.subn(r'fn_rev_label(\1.stage, \1.revision_no)', body)
    app.set_query(u['pageId'], u['name'], body=new)
    n_lbl += n
    app.note(f'label stage: {u["pageId"]}/{u["name"]} ({n}x)')
assert n_lbl == 11, n_lbl

# ---------------------------------------------------------------- Admin: detail audit
q = app.action('Admin', 'q_audit')['unpublishedAction']['actionConfiguration']['body']
old = 'SELECT id, created_at, user_email, entity, entity_id, action, before_data, after_data\n'
assert q.count(old) == 1
app.set_query('Admin', 'q_audit', body=q.replace(old, '''-- R14: kunci rahasia dibuang sebelum dikirim ke browser (panel detail cwAuditDetail)
SELECT id, created_at, user_email, entity, entity_id, action,
       (SELECT jsonb_object_agg(e.k, e.v) FROM jsonb_each(before_data) e(k, v)
         WHERE e.k !~* 'password|token|secret|hash') AS before_data,
       (SELECT jsonb_object_agg(e.k, e.v) FROM jsonb_each(after_data) e(k, v)
         WHERE e.k !~* 'password|token|secret|hash') AS after_data
'''))
app.set_js('Admin', 'AdminCtrl', js('js/AdminCtrl.js'))

t, canvas = app.widget('Admin', 'tblAudit', with_parent=True)
assert (t['leftColumn'], t['rightColumn'], t['topRow'], t['bottomRow']) == (0, 64, 10, 67)
t['rightColumn'] = 38.0
t['mobileRightColumn'] = 38.0
# T71: kolom Waktu membaca kunci "Created At" yang tidak ada -> semua baris tampil jam sekarang
c = t['primaryColumns']['created_at']
assert c['computedValue'].count('currentRow["Created At"]') == 2
c['computedValue'] = c['computedValue'].replace('currentRow["Created At"]', 'currentRow["created_at"]')

w = app.clone_widget('Admin', 'cwTempPassword', 'cwAuditDetail', parent_name=canvas['widgetName'])
w.update(topRow=10.0, bottomRow=67.0, leftColumn=39.0, rightColumn=64.0,
         mobileTopRow=10.0, mobileBottomRow=67.0, mobileLeftColumn=39.0, mobileRightColumn=64.0,
         parentColumnSpace=t.get('parentColumnSpace', w.get('parentColumnSpace')))
for ev in ('onCopy', 'onClose'):
    w.pop(ev, None)
w['events'] = []
w['dynamicTriggerPathList'] = []
w['dynamicPropertyPathList'] = []
w['defaultModel'] = '{{AdminCtrl.auditModel(tblAudit.selectedRow.id)}}'
cw(app, 'Admin', 'cwAuditDetail')

# ---------------------------------------------------------------- 5 stage: JSObject & Custom Widget
for pg in PAGES:
    app.set_js(pg, 'Util', js('js/Util.js'))
app.set_js('Specsheet', 'SpecCtrl', js('js/SpecCtrl.js'))
app.set_js('Specsheet', 'SpecExportCtrl', js('js/SpecExportCtrl.js'))
app.set_js(CBD, 'CbdCtrl', js('js/CbdCtrl.js'))
app.set_js(CBD, 'CbdGridCtrl', js('js/CbdGridCtrl.js'))
app.set_js(CBD, 'CbdExportCtrl', js('js/CbdExportCtrl.js'))
app.set_js('Beranda', 'BerandaCtrl', js('js/BerandaCtrl.js'))
cw(app, 'Specsheet', 'cwStepper')
cw(app, CBD, 'cwStepper')
cw(app, 'Specsheet', 'cwRevisionForm')
cw(app, CBD, 'cwCbdForm')

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
for n in app.log:
    print(n)
