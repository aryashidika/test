# Build R20: salin exports/build_r19.json (R19 lolos uji user, app belum diubah) -> edit di tempat -> exports/build_r20.json.
# SQL R20 ada di steps/R20_uji.md (bagian 1, salin ke z_run_sql). PLAN §6 R20: penulisan material seragam + kode ERP ketat.
#  1. nama beda spasi / tanda baca = material yang sama (cwBomGrid, BomCtrl.nearMaterialNames, DB fn_material_check)
#  2. Material Code ketat dua arah tanpa centang konfirmasi (cwVariantForm, q_code_hint, BomCtrl / MaterialDetailCtrl)
#  3. Use: varian yang sudah ada dipakai di sel kuning / sel yang diisi kode material lain (cwBomGrid, BomCtrl,
#     a_bom_use_variant baru, tombol "Use this variant" di modal Register)
#  4. (bagian 2, 27 Okt 2026) warna seragam (BLACK / WHITE = BLACK/WHITE, cwBomGrid + cwVariantForm, SQL 0b) dan Dimension seperti
#     dropdown: grid = daftar penuh saat diklik + dimension material lain saat mengetik; form varian = daftar q_dimensions baru
#  5. (bagian 3, 28 Okt 2026) Dimension wajib: (None) paling atas, default = dimension material dengan varian terbanyak
#     (q_bom_options + first_at, q_dimensions + n_own / baris kosong material ini); kode Dimension kosong per material
#     (q_code_suggest + thickness_free)
#  6. (bagian 4, 28 Okt 2026) Material Code tersusun otomatis di DB (SQL 0d, tanpa query baru): BomCtrl memuat ulang q_bom_options
#     bila grid punya kode baru; cwVariantForm: Save menunggu cek kode (tombol Use) selesai. Kode purchasing yang belum terdaftar
#     tapi terbaca (q_code_decode baru) -> tombol Use di modal Register (a_bom_use_code baru)
#  7. (bagian 5, 28 Okt 2026) link "Edit material" di kolom Material grid -> Edit Material di modal mdlMaterialBaru (mode edit,
#     q_material_edit + a_material_update baru di Specsheet; fn_material_update R19 tanpa perubahan SQL)
#  8. (bagian 6, 28 Okt 2026) cwBomGrid saja: Dimension dipilih dari daftar = langsung simpan, render ulang tidak menyimpan kotak
#     yang dibuang, kotak yang fokus dipakai lagi, fokus ikut baris pengganti (replaces_line_key), daftar dibuka lagi setelah render
#  9. (bagian 7, 28 Okt 2026) dropdown Dimension grid langsung lengkap: terdaftar, sudah dipakai di specsheet tanpa kode
#     (q_bom_options + used_dims, BomCtrl usedDims), lalu dimension material lain di bawah "Other materials"
# JSObject / Custom Widget yang ditimpa dicek dulu: isi di app = repo di commit R19 (a1af1d1), lalu diganti isi repo sekarang.
# Pakai: python -X utf8 -I tools/build_r20.py [base.json]   (default base = exports/build_r19.json)
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, rd, lock_manual_queries, sub1


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


R19_COMMIT = 'a1af1d1'     # R19 lolos uji user; build_r19.json = isi repo di commit ini


def git_head(path):
    return subprocess.run(['git', '-C', ROOT, 'show', f'{R19_COMMIT}:appsmith/{path}'], capture_output=True, text=True,
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
    # R20 bagian 3: dimension kosong yang belum ada di material ini = hanya saran
    query(pg, 'q_code_suggest', [('SELECT prefixes, thickness_codes, color_codes\n',
                                  'SELECT prefixes, thickness_codes, color_codes, thickness_free\n')])
    # konfirmasi R9 tidak dipakai lagi (parameter DB tetap ada, selalu false)
    query(pg, 'a_variant_save', [("({{this.params.confirm === true ? 'true' : 'false'}})::boolean) AS id;", 'false) AS id;')])
app.note('q_code_hint (+ warna, dimension, used_*, problems), q_code_suggest (+ thickness_free) & a_variant_save tanpa confirm: '
         'Specsheet + Material Detail')

# ---------------------------------------------------------------- 5. bagian 3: default Dimension grid = varian terbanyak, paling dulu
query(SPEC, 'q_bom_options', [
    ("                                                'thickness', x.thickness, 'variant_count', x.n, 'is_process', x.is_process)\n",
     "                                                'thickness', x.thickness, 'variant_count', x.n, 'is_process', x.is_process,\n"
     "                                                'first_at', x.first_at)\n"),
    ("     FROM (SELECT m.id AS material_id, m.name, m.uom, m.is_process, v.thickness, count(v.id) AS n\n",
     "     FROM (SELECT m.id AS material_id, m.name, m.uom, m.is_process, v.thickness, count(v.id) AS n,\n"
     "                  extract(epoch FROM min(v.created_at))::bigint AS first_at\n"),
])

# ---------------------------------------------------------------- 9. bagian 7: dimension yang sudah dipakai di specsheet (belum ada kode)
query(SPEC, 'q_bom_options', [
    ("  (SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'code', v.code, 'material_id', v.material_id,\n",
     "  (SELECT coalesce(jsonb_agg(jsonb_build_object('material_id', u.material_id, 'thickness', u.thickness, 'lines', u.n)\n"
     "                             ORDER BY u.thickness), '[]'::jsonb)\n"
     "     FROM (SELECT l.material_id, l.thickness, count(*) AS n\n"
     "             FROM bom_line l JOIN material m ON m.id = l.material_id\n"
     "            WHERE l.is_active AND coalesce(l.thickness, '') <> '' AND m.status = 'ACTIVE'\n"
     "              AND m.factory_id = fn_user_factory(a.me)\n"
     "              AND NOT EXISTS (SELECT 1 FROM material_variant v WHERE v.material_id = l.material_id\n"
     "                                AND v.status = 'ACTIVE' AND v.thickness IS NOT DISTINCT FROM l.thickness)\n"
     "            GROUP BY l.material_id, l.thickness) u) AS used_dims,\n"
     "  (SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'code', v.code, 'material_id', v.material_id,\n"),
])

# ---------------------------------------------------------------- 3. Use
app.add_query(SPEC, 'a_bom_use_variant', 'a_bom_change_component',
              'SELECT fn_bom_use_variant({{appsmith.store.token}}, {{this.params.line_id}}::uuid,\n'
              '                          {{this.params.article_id}}::uuid, {{this.params.variant_id}}::uuid) AS result;')

# ---------------------------------------------------------------- 6. bagian 4: Use kode purchasing yang belum terdaftar (Specsheet)
app.add_query(SPEC, 'q_code_decode', 'q_code_suggest',
              "SELECT material_id, label, thickness, color, array_to_string(problems, E'\\n') AS problems\n"
              "FROM fn_variant_code_decode({{appsmith.store.token}}, {{this.params.material_id}}::uuid, {{this.params.code}},\n"
              "                            {{this.params.color || ''}}, {{this.params.thickness || ''}});")
app.add_query(SPEC, 'a_bom_use_code', 'a_bom_use_variant',
              'SELECT fn_bom_use_code({{appsmith.store.token}}, {{this.params.line_id}}::uuid,\n'
              '                       {{this.params.article_id}}::uuid, {{this.params.code}}) AS result;')

# ---------------------------------------------------------------- 7. bagian 5: Edit material dari specsheet
app.add_query(SPEC, 'q_material_edit', 'q_similar',
              "SELECT m.id, m.name, m.category, m.uom, m.price_method, m.status, m.is_process, m.variant_count,\n"
              "       fn_material_used_published(m.id) AS used_published,\n"
              "       (SELECT count(DISTINCT r.specsheet_id) FROM bom_line l JOIN specsheet_revision r ON r.id = l.revision_id\n"
              "         WHERE l.material_id = m.id AND l.is_active AND r.status = 'DRAFT')::int AS draft_specs,\n"
              "       (SELECT count(DISTINCT c.id) FROM cbd_line cl JOIN cbd_revision c ON c.id = cl.cbd_revision_id\n"
              "         WHERE cl.material_id = m.id AND c.status = 'DRAFT')::int AS draft_cbds\n"
              "FROM (SELECT fn_auth({{appsmith.store.token}}, 'view_master') AS me) a\n"
              "JOIN v_material_list m ON fn_can_see_factory(a.me, m.factory_id)\n"
              "WHERE m.id::text = {{this.params.id || ''}};")
app.add_query(SPEC, 'a_material_update', 'a_material_add',
              app.action(MD, 'a_material_update')['unpublishedAction']['actionConfiguration']['body'])

# ---------------------------------------------------------------- 4. daftar Dimension form varian (Material Detail)
# R20 bagian 3: + n_own (varian material ini), baris tanpa dimension material ini; material ini dulu, varian terbanyak, paling dulu
app.add_query(MD, 'q_dimensions', 'q_variants',
              "SELECT coalesce(v.thickness, '') AS thickness, count(*)::int AS n,\n"
              "       count(*) FILTER (WHERE v.material_id = m0.id)::int AS n_own, bool_or(v.material_id = m0.id) AS own\n"
              "FROM (SELECT fn_auth({{appsmith.store.token}}, 'view_master') AS me) a\n"
              "JOIN material m0 ON m0.id::text = {{appsmith.URL.queryParams.id || ''}}\n"
              "JOIN material_variant v ON v.factory_id = m0.factory_id AND fn_can_see_factory(a.me, v.factory_id)\n"
              "WHERE (coalesce(v.thickness, '') <> '' OR v.material_id = m0.id) AND v.status = 'ACTIVE'\n"
              "GROUP BY coalesce(v.thickness, '')\n"
              "ORDER BY bool_or(v.material_id = m0.id) DESC, count(*) FILTER (WHERE v.material_id = m0.id) DESC,\n"
              "         min(v.created_at) FILTER (WHERE v.material_id = m0.id), count(*) DESC, coalesce(v.thickness, '');")

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
for n in app.log:
    print(n)
