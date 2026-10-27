# Build R19: salin exports/export_r18.json (export user 26 Okt 2026 = build_r18, hanya format ulang Appsmith) -> edit di tempat
# -> exports/build_r19.json. SQL: sql/R19_catatan_uji.sql (jalankan dulu). Catatan uji user 26 Okt 2026 (PLAN §6 R19):
#  1. nomor komponen = posisi (cwKomponenForm: teks)          5. ganti komponen di specsheet (cwBomGrid, BomCtrl, a_bom_change_component)
#  2. nomor artikel boleh kosong (cwArticleForm, ModelDetailCtrl, SpecCtrl, BerandaCtrl, query yang menampilkan nomor)
#  3. Dimension di kolom sendiri + 6. saran material terbaca penuh (cwBomGrid)
#  4. material Process (cwMaterialForm, MaterialCtrl, MaterialDetailCtrl, BomCtrl, SpecExportCtrl, query material)
#  7. filter di-reset saat page dibuka (Auth per page + Util)  8. semua field model wajib (cwModelForm)
# JSObject / Custom Widget yang ditimpa dicek dulu: isi di app = repo di git HEAD (R18), lalu diganti isi repo sekarang.
# Pakai: python -X utf8 -I tools/build_r19.py [base.json]   (default base = exports/export_r18.json)
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, rd, lock_manual_queries, sub1, col_cv


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


def git_head(path):
    return subprocess.run(['git', '-C', ROOT, 'show', f'HEAD:appsmith/{path}'], capture_output=True, text=True,
                          encoding='utf-8', check=True).stdout


def squash(s):
    return ''.join(s.split())


BASE = sys.argv[1] if len(sys.argv) > 1 else f'{ROOT}/exports/export_r18.json'
OUT = f'{ROOT}/exports/build_r19.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R19'
PAGES = [p['unpublishedPage']['name'] for p in d['pageList']]
SPEC, CBD, MM, MD, ML, MDL, HOME = 'Specsheet', 'Cost Breakdown (CBD)', 'Master Material', 'Material Detail', 'Model List', 'Model Detail', 'Home'

# ---------------------------------------------------------------- JSObject & Custom Widget dari repo (cek dulu = git HEAD)
JS = {
    'Util': PAGES,
    'BomCtrl': [SPEC], 'SpecCtrl': [SPEC], 'SpecExportCtrl': [SPEC],
    'MaterialCtrl': [MM], 'MaterialDetailCtrl': [MD],
    'ModelCtrl': [ML], 'ModelDetailCtrl': [MDL], 'BerandaCtrl': [HOME],
    'CbdCtrl': [CBD], 'CbdExportCtrl': [CBD],          # R19: label article tanpa nomor di chip / Excel CBD
}
CW = {
    'cwBomGrid': [SPEC], 'cwMaterialForm': [MM, MD, SPEC], 'cwModelForm': [ML, MDL],
    'cwArticleForm': [MDL], 'cwKomponenForm': ['Master Component'],
}
PART = (('html', 'index.html'), ('css', 'style.css'), ('js', 'script.js'))
for n, pages in JS.items():
    head = git_head(f'js/{n}.js')
    for pg in pages:
        assert squash(app.js_body(pg, n)) == squash(head[head.index('export default'):]), f'{pg}/{n}: isi di app beda dengan repo R18'
for n, pages in CW.items():
    for pg in pages:
        w = app.widget(pg, n)
        for part, fn in PART:
            assert squash(w['uncompiledSrcDoc'][part]) == squash(git_head(f'widgets/{n}/{fn}')), f'{pg}/{n} {part} beda dengan repo R18'
for n, pages in JS.items():
    for pg in pages:
        app.set_js(pg, n, js(f'js/{n}.js'))
for n, pages in CW.items():
    for pg in pages:
        app.set_cw_source(pg, n, html=rd(f'widgets/{n}/index.html'), css=rd(f'widgets/{n}/style.css'),
                          js=rd(f'widgets/{n}/script.js'))
app.note('JSObject dari repo: ' + ', '.join(JS) + ' · Custom Widget dari repo: ' + ', '.join(CW))


def query(pg, name, pairs):
    q = app.action(pg, name)['unpublishedAction']['actionConfiguration']['body']
    for old, new in pairs:
        q = sub1(q, old, new, f'{pg}/{name}')
    app.set_query(pg, name, body=q)


PROC = "{{this.params.is_process === true ? 'true' : 'false'}}::boolean"

# ---------------------------------------------------------------- 2. nomor artikel kosong: label "(no article no.)"
query(SPEC, 'q_rev_articles', [
    ('SELECT a.id, a.code, a.colorway,', "SELECT a.id, fn_article_code_label(a.code) AS code, a.colorway, a.code IS NULL AS no_code,"),
    ('ORDER BY a.code;', 'ORDER BY a.code NULLS LAST, a.colorway;'),
])
query(CBD, 'q_cbd_articles', [
    ('SELECT v.id, v.code, v.colorway,', 'SELECT v.id, fn_article_code_label(v.code) AS code, v.colorway, v.code IS NULL AS no_code,'),
    ('ORDER BY v.code;', 'ORDER BY v.code NULLS LAST, v.colorway;'),
])
query(CBD, 'q_cbd_sources', [
    ('SELECT a.id, a.code, a.colorway,', 'SELECT a.id, fn_article_label(a.code, a.colorway) AS code, a.colorway,'),
])
query(CBD, 'q_cbd_revisions', [
    ('src_a.code AS source_article', 'CASE WHEN src_a.id IS NOT NULL THEN fn_article_label(src_a.code, src_a.colorway) END AS source_article'),
])
query(MDL, 'q_articles', [('ORDER BY v.code;', 'ORDER BY v.code NULLS LAST, v.colorway;'),
                          ('v.updated_at, v.updated_by, v.pub_label,', 'v.updated_at, v.updated_by, fn_article_prod_published(v.id) AS code_locked, v.pub_label,')])
t = app.widget(MDL, 'tblArticles')
t['primaryColumns']['code'].update(label='Article No.', computedValue=col_cv('tblArticles', 'code', "currentRow.code || '(no article no.)'"))
pc = t['primaryColumns']                               # code_locked: kolom tersembunyi (kalau tidak, Appsmith menambah kolom terlihat)
pc['code_locked'] = dict(pc['is_used'], id='code_locked', originalId='code_locked', alias='code_locked', label='code_locked',
                         computedValue=col_cv('tblArticles', 'code_locked'), isVisible=False)
t['columnOrder'].append('code_locked')
pc['code_locked']['index'] = float(len(t['columnOrder']) - 1)
t['dynamicBindingPathList'].append({'key': 'primaryColumns.code_locked.computedValue'})
app.note('Nomor artikel kosong: q_rev_articles (+ no_code), q_cbd_articles, q_cbd_sources, q_cbd_revisions, q_articles, kolom tblArticles')

# ---------------------------------------------------------------- 4. material Process
for pg in (MM, SPEC):
    query(pg, 'a_material_add', [('{{this.params.uom}}) AS id;', '{{this.params.uom}}, ' + PROC + ') AS id;')])
query(MD, 'a_material_update', [('{{this.params.price_method}}) AS id;', '{{this.params.price_method}}, ' + PROC + ') AS id;')])
query(MD, 'q_material', [('m.updated_at, m.updated_by\nFROM', 'm.updated_at, m.updated_by,\n       m.is_process, fn_material_used_published(m.id) AS used_published\nFROM')])
query(MM, 'q_materials', [('m.updated_at, m.updated_by, count(*) OVER () AS total_count', 'm.updated_at, m.updated_by, m.is_process, count(*) OVER () AS total_count')])
query(SPEC, 'q_bom_options', [
    ("'thickness', x.thickness, 'variant_count', x.n)", "'thickness', x.thickness, 'variant_count', x.n, 'is_process', x.is_process)"),
    ('(SELECT m.id AS material_id, m.name, m.uom, v.thickness, count(v.id) AS n', '(SELECT m.id AS material_id, m.name, m.uom, m.is_process, v.thickness, count(v.id) AS n'),
    ('GROUP BY m.id, m.name, m.uom, v.thickness) x) AS materials,', 'GROUP BY m.id, m.name, m.uom, m.is_process, v.thickness) x) AS materials,'),
])
t = app.widget(MM, 'tblMaterials')
pc = t['primaryColumns']
pc['is_process'] = dict(pc['active_variant_count'], id='is_process', originalId='is_process', alias='is_process', label='is_process',
                        computedValue=col_cv('tblMaterials', 'is_process'), isVisible=False)
t['columnOrder'].append('is_process')
pc['is_process']['index'] = float(len(t['columnOrder']) - 1)
pc['price_method']['computedValue'] = col_cv('tblMaterials', 'price_method',
                                             "currentRow.is_process ? 'Process (quotation)' : currentRow.price_method === 'QUOTATION' ? 'Quotation' : 'Catalog'")
pc['variant_count']['computedValue'] = col_cv('tblMaterials', 'variant_count', "currentRow.is_process ? '-' : currentRow.variant_count")
t['dynamicBindingPathList'].append({'key': 'primaryColumns.is_process.computedValue'})
w = app.widget(MD, 'btnVarianTambah')
assert w['isVisible'] == '{{MaterialDetailCtrl.canManageMaster() && !!MaterialDetailCtrl.material()}}', w['isVisible']
w['isVisible'] = '{{MaterialDetailCtrl.canAddVariant()}}'
app.note('Material Process: a_material_add (2 page), a_material_update, q_material, q_materials, q_bom_options, tblMaterials, btnVarianTambah')

# ---------------------------------------------------------------- 5. ganti komponen
app.add_query(SPEC, 'a_bom_change_component', 'a_bom_set_process',
              'SELECT fn_bom_change_component({{appsmith.store.token}}, {{this.params.line_id}}::uuid,\n'
              '                               {{this.params.component_id}}::uuid) AS n;')

# ---------------------------------------------------------------- 7. reset filter: Auth per page
FILTERS = {
    'Home': [],
    'Admin': ['tabAdmin', 'selAuditEntitas', 'inpAuditCari', 'tblUsers', 'tblAudit', 'tblFactories'],
    'Master Supplier': ['inpSupplierCari', 'selSupplierFilterStatus', 'tblSuppliers'],
    'Master Component': ['inpKomponenCari', 'selKomponenGrup', 'selKomponenFilterStatus', 'tblComponents'],
    'Master Material': ['inpMaterialCari', 'selMaterialStatus', 'selMaterialKategori', 'tblMaterials'],
    'Material Detail': ['tabMaterial', 'swHargaRiwayat', 'tblVariants', 'tblLinks', 'tblPrices'],
    'Master Options': ['inpPilihanCari', 'selPilihanJenis', 'tblPilihan'],
    'Price Approval': [],
    'Model List': ['inpModelCari', 'selModelSeason', 'selModelPabrik', 'tblModels'],
    'Model Detail': ['tabModel', 'tblArticles'],          # selSeason mengikuti URL (ModelDetailCtrl.init)
    'Specsheet': [],                                      # model / season dari URL
    'Cost Breakdown (CBD)': [],
}
assert set(FILTERS) == set(PAGES) - {'Login'}, sorted(set(PAGES) ^ set(FILTERS))
for pg, ws in FILTERS.items():
    for wn in ws:
        app.widget(pg, wn)                                # widget harus ada
    body = app.js_body(pg, 'Auth')
    lst = ', '.join(f"'{x}'" for x in ws)
    body = sub1(body, '\tme: null,', f"""\t// R19: filter page ini di-reset setiap page dibuka, kecuali saat kembali dari halaman detail (Util.resetFilters)
\tpageName: '{pg}',

\tfilterWidgets() {{
\t\treturn [{lst}];
\t}},

\tme: null,""", f'{pg}/Auth')
    body = sub1(body, '\t\tfor (const q of this.pageQueries()) {',
                '\t\tawait Util.resetFilters(this.pageName, this.filterWidgets());\n\t\tfor (const q of this.pageQueries()) {', f'{pg}/Auth')
    app.set_js(pg, 'Auth', body)
app.note('Auth per page: pageName + filterWidgets + Util.resetFilters sebelum pageQueries')

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
for n in app.log:
    print(n)
