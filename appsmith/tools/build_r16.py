# Build R16: salin exports/build_r15.json (app R15 user tidak diubah, hanya di-deploy) -> edit di tempat ->
# exports/build_r16.json. SQL: sql/R16_baku_thickness.sql (jalankan dulu).
# Isi: page Specsheet + teks isian Order di form Master Options (cwOptionForm).
#  - tombol "+ New material" (induk baru tanpa kode, cari nama mirip dulu) = modal mdlMaterialBaru (salinan modal Master Material)
#  - thickness baru untuk induk yang ada diketik langsung ("NAMA · THICKNESS"), dibakukan seperti DB (canonThickness)
#  - saran "Did you mean" bila nama material typo
#  - Export Excel specsheet: sel tanpa kode kuning (SpecExportCtrl)
#  - Order master option = posisi (isian Order di form; logika di SQL)
#  - (20 Okt 2026, review) thickness baku diperluas (2.0 = 2, kutip pintar, INCH, rentang) di cwBomGrid + cwVariantForm
#    (Specsheet & Material Detail; cwVariantForm sebelumnya masih memakai pembakuan lama -> konfirmasi merah palsu),
#    BomCtrl: tombol + New material tampil (canAddMaterial) + saran Category / Mea, SpecExportCtrl: baris revisi yang
#    dibuka saja, CbdCtrl: chip "TERBIT" -> "PUBLISHED"
#  - (20 Okt 2026, review ke-2) Master Options q_options: urut menurut Order saja (INACTIVE tidak lagi dipindah ke bawah,
#    Order = posisi), kolom Factory "Bersama" -> "Shared"; cwCbdGrid: simulasi Selling price tanpa pemisah ribuan
#  - (review ke-2) Login: LoginCtrl.onPageLoad kembali "Run on page load" (sejak export R1 tercatat Manual + layoutOnLoadActions
#    kosong -> Logout tidak menghapus token / menutup sesi, tombol Change password di header membuka form login). Disalin dari
#    pola Auth.onPageLoad di page lain (runBehaviour ON_PAGE_LOAD, userSetOnLoad true, entri layoutOnLoadActions).
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, TOKEN, rd, lock_manual_queries, copy_widget_to_page, set_binding, add_event, resize_modal


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


def git_head(path):
    return subprocess.run(['git', '-C', ROOT, 'show', f'HEAD:appsmith/{path}'], capture_output=True, text=True,
                          encoding='utf-8', check=True).stdout


def squash(s):
    return ''.join(s.split())


BASE = f'{ROOT}/exports/build_r15.json'
OUT = f'{ROOT}/exports/build_r16.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R16'
PG = 'Specsheet'

# ---------------------------------------------------------------- cek: app = repo R15 (git HEAD) untuk yang akan ditimpa
CBD = 'Cost Breakdown (CBD)'
for pg, n in ((PG, 'BomCtrl'), (PG, 'SpecExportCtrl'), (CBD, 'CbdCtrl')):
    head = git_head(f'js/{n}.js')
    head = head[head.index('export default'):]
    assert squash(app.js_body(pg, n)) == squash(head), f'{n}: isi di app beda dengan repo R15 (git HEAD), cek dulu'
for part, fn in (('html', 'index.html'), ('css', 'style.css'), ('js', 'script.js')):
    w = app.widget(PG, 'cwBomGrid')
    assert squash(w['uncompiledSrcDoc'][part]) == squash(git_head(f'widgets/cwBomGrid/{fn}')), f'cwBomGrid {part} beda dengan repo R15'
w = app.widget(CBD, 'cwCbdGrid')
assert squash(w['uncompiledSrcDoc']['js']) == squash(git_head('widgets/cwCbdGrid/script.js')), 'cwCbdGrid js beda dengan repo R15'
for pg in (PG, 'Material Detail'):
    w = app.widget(pg, 'cwVariantForm')
    assert squash(w['uncompiledSrcDoc']['js']) == squash(git_head('widgets/cwVariantForm/script.js')), f'{pg}/cwVariantForm js beda dengan repo R15'

# ---------------------------------------------------------------- query
q = app.action(PG, 'q_bom_options')['unpublishedAction']['actionConfiguration']['body']
old = "AS links\nFROM (SELECT fn_auth("
assert q.count(old) == 1
q = q.replace(old, """AS links,
  (SELECT coalesce(jsonb_agg(DISTINCT m.category ORDER BY m.category), '[]'::jsonb)
     FROM material m WHERE m.factory_id = fn_user_factory(a.me)) AS categories,
  (SELECT coalesce(jsonb_agg(DISTINCT m.uom ORDER BY m.uom), '[]'::jsonb)
     FROM material m WHERE m.factory_id = fn_user_factory(a.me)) AS uoms
FROM (SELECT fn_auth(""")
app.set_query(PG, 'q_bom_options', body=q)
app.add_query(PG, 'a_material_add', 'a_cell_save',
              app.action('Master Material', 'a_material_add')['unpublishedAction']['actionConfiguration']['body'])

# ---------------------------------------------------------------- JSObject & widget
for pg, n in ((PG, 'BomCtrl'), (PG, 'SpecExportCtrl'), (CBD, 'CbdCtrl')):
    app.set_js(pg, n, js(f'js/{n}.js'))
app.set_cw_source(PG, 'cwBomGrid', html=rd('widgets/cwBomGrid/index.html'), css=rd('widgets/cwBomGrid/style.css'),
                  js=rd('widgets/cwBomGrid/script.js'))
app.set_cw_source(CBD, 'cwCbdGrid', js=rd('widgets/cwCbdGrid/script.js'))   # hanya JS; HTML & CSS dari app
q = app.action('Master Options', 'q_options')['unpublishedAction']['actionConfiguration']['body']
for old, new in (("coalesce(f.name, 'Bersama')", "coalesce(f.name, 'Shared')"),
                 ("ORDER BY f.name NULLS FIRST, o.status = 'INACTIVE', o.sort_order NULLS LAST, o.value_key",
                  "ORDER BY f.name NULLS FIRST, o.sort_order NULLS LAST, o.value_key")):
    assert q.count(old) == 1, old
    q = q.replace(old, new)
app.set_query('Master Options', 'q_options', body=q)
for pg in (PG, 'Material Detail'):       # hanya JS yang berubah (canonThickness); HTML & CSS dari app
    app.set_cw_source(pg, 'cwVariantForm', js=rd('widgets/cwVariantForm/script.js'))

# modal + New material (salinan mdlMaterial Master Material, mode add)
copy_widget_to_page(app, 'Master Material', 'mdlMaterial', PG,
                    {'mdlMaterial': 'mdlMaterialBaru', 'Canvas1': 'CanvasMaterialBaru'})
w = app.widget(PG, 'cwMaterialForm')
set_binding(w, 'defaultModel', '{{BomCtrl.materialFormModel()}}')
w['onSave'] = '{{BomCtrl.saveMaterial()}}'
w['onCancel'] = "{{closeModal('mdlMaterialBaru')}}"
add_event(w, 'onSearch', '{{BomCtrl.searchSimilarMaterial()}}')
app.widget(PG, 'mdlMaterialBaru')['canOutsideClickClose'] = False

# Master Options: isian Order = posisi (SQL: fn_option_renumber). Hanya HTML form yang berubah; CSS & JS dari app.
w = app.widget('Master Options', 'cwOptionForm')
assert squash(w['uncompiledSrcDoc']['html']) == squash(git_head('widgets/cwOptionForm/index.html')), 'cwOptionForm html beda dengan repo R15'
app.set_cw_source('Master Options', 'cwOptionForm', html=rd('widgets/cwOptionForm/index.html'))

# Login: LoginCtrl.onPageLoad dijalankan saat page dibuka
lg = next(a for a in d['actionList'] if a['unpublishedAction'].get('pageId') == 'Login'
          and a['unpublishedAction'].get('fullyQualifiedName') == 'LoginCtrl.onPageLoad')
u = lg['unpublishedAction']
assert u['runBehaviour'] == 'MANUAL', 'LoginCtrl.onPageLoad sudah bukan Manual, cek dulu'
u['runBehaviour'] = 'ON_PAGE_LOAD'
u['userSetOnLoad'] = True
u['actionConfiguration']['timeoutInMillisecond'] = 10000.0
lay = next(p for p in d['pageList'] if p['unpublishedPage']['name'] == 'Login')['unpublishedPage']['layouts'][0]
assert not lay.get('layoutOnLoadActions'), 'layoutOnLoadActions Login tidak kosong, cek dulu'
lay['layoutOnLoadActions'] = [[{
    'id': lg['id'], 'name': 'LoginCtrl.onPageLoad', 'collectionId': u['collectionId'], 'confirmBeforeExecute': False,
    'pluginType': 'JS', 'jsonPathKeys': list(u.get('jsonPathKeys') or []), 'timeoutInMillisecond': 10000.0,
}]]
app.note('Login: LoginCtrl.onPageLoad = Run on page load')

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
for n in app.log:
    print(n)
