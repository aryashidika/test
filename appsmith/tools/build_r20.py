# Build R20: salin exports/build_r19.json (R19 lolos uji user, app belum diubah) -> edit di tempat -> exports/build_r20.json.
# SQL R20 ada di steps/R20_uji.md (bagian 1, salin ke z_run_sql). PLAN §6 R20: penulisan material seragam + kode ERP ketat.
#  1. nama beda spasi / tanda baca = material yang sama (cwBomGrid, BomCtrl.nearMaterialNames, DB fn_material_check)
#  2. Material Code ketat dua arah tanpa centang konfirmasi (cwVariantForm, q_code_hint, BomCtrl / MaterialDetailCtrl)
#  3. Use: varian yang sudah ada dipakai di sel kuning / sel yang diisi kode material lain (cwBomGrid, BomCtrl,
#     a_bom_use_variant baru, tombol "Use this variant" di modal Register)
# JSObject / Custom Widget yang ditimpa dicek dulu: isi di app = repo di git HEAD (R19), lalu diganti isi repo sekarang.
# Pakai: python -X utf8 -I tools/build_r20.py [base.json]   (default base = exports/build_r19.json)
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, rd, lock_manual_queries, sub1


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


def git_head(path):
    return subprocess.run(['git', '-C', ROOT, 'show', f'HEAD:appsmith/{path}'], capture_output=True, text=True,
                          encoding='utf-8', check=True).stdout


def squash(s):
    return ''.join(s.split())


BASE = sys.argv[1] if len(sys.argv) > 1 else f'{ROOT}/exports/build_r19.json'
OUT = f'{ROOT}/exports/build_r20.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R20'
SPEC, MD = 'Specsheet', 'Material Detail'

# ---------------------------------------------------------------- JSObject & Custom Widget dari repo (cek dulu = git HEAD)
JS = {'BomCtrl': [SPEC], 'MaterialDetailCtrl': [MD]}
CW = {'cwBomGrid': [SPEC], 'cwVariantForm': [MD, SPEC]}
PART = (('html', 'index.html'), ('css', 'style.css'), ('js', 'script.js'))
for n, pages in JS.items():
    head = git_head(f'js/{n}.js')
    for pg in pages:
        assert squash(app.js_body(pg, n)) == squash(head[head.index('export default'):]), f'{pg}/{n}: isi di app beda dengan repo R19'
for n, pages in CW.items():
    for pg in pages:
        w = app.widget(pg, n)
        for part, fn in PART:
            assert squash(w['uncompiledSrcDoc'][part]) == squash(git_head(f'widgets/{n}/{fn}')), f'{pg}/{n} {part} beda dengan repo R19'
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


# ---------------------------------------------------------------- 2. hint kode: warna + dimension, Use, masalah aturan ketat
for pg in (SPEC, MD):
    query(pg, 'q_code_hint', [
        ('SELECT code, thickness_known, thickness, thickness_ref, color_known, color, color_ref, other_prefixes\n',
         'SELECT code, thickness_known, thickness, thickness_ref, color_known, color, color_ref, other_prefixes,\n'
         "       used_id, used_label, used_active, array_to_string(problems, E'\\n') AS problems\n"),
        ("nullif({{this.params.exclude_id || ''}}, '')::uuid);",
         "nullif({{this.params.exclude_id || ''}}, '')::uuid,\n"
         "                          {{this.params.color || ''}}, {{this.params.thickness || ''}});"),
    ])
    # konfirmasi R9 tidak dipakai lagi (parameter DB tetap ada, selalu false)
    query(pg, 'a_variant_save', [("({{this.params.confirm === true ? 'true' : 'false'}})::boolean) AS id;", 'false) AS id;')])
app.note('q_code_hint (+ warna, dimension, used_*, problems) & a_variant_save tanpa confirm: Specsheet + Material Detail')

# ---------------------------------------------------------------- 3. Use
app.add_query(SPEC, 'a_bom_use_variant', 'a_bom_change_component',
              'SELECT fn_bom_use_variant({{appsmith.store.token}}, {{this.params.line_id}}::uuid,\n'
              '                          {{this.params.article_id}}::uuid, {{this.params.variant_id}}::uuid) AS result;')

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
for n in app.log:
    print(n)
