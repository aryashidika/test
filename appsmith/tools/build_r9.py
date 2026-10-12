# Build R9: salin build_r8.json (= app user setelah uji R8 lolos, tanpa perubahan) -> edit di tempat -> exports/build_r9.json
# Material Code: isi otomatis (usulan) + kamus kode tiga tingkat (tolak / konfirmasi / info). SQL: sql/R9_kode_varian.sql.
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App
from rlib import ROOT, TOKEN, rd, resize_modal, lock_manual_queries


def js(path):
    """Isi JSObject = file repo mulai 'export default' (komentar header repo tidak ikut ke app)."""
    s = rd(path)
    return s[s.index('export default'):]


BASE = f'{ROOT}/exports/build_r8.json'
OUT = f'{ROOT}/exports/build_r9.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R9'

SAVE = f'''SELECT fn_variant_save({TOKEN}, nullif({{{{this.params.id || ''}}}}, '')::uuid,
                       {{{{this.params.material_id}}}}::uuid, {{{{this.params.code}}}}, {{{{this.params.color}}}},
                       {{{{this.params.thickness || ''}}}}, {{{{this.params.status}}}},
                       ({{{{this.params.confirm === true ? 'true' : 'false'}}}})::boolean) AS id;'''
SUGGEST = f'''SELECT prefixes, thickness_codes, color_codes
FROM fn_variant_code_suggest({TOKEN}, {{{{this.params.material_id}}}}::uuid, {{{{this.params.color || ''}}}},
                             {{{{this.params.thickness || ''}}}});'''

for pg, ctrl, modal in (('Material Detail', 'MaterialDetailCtrl', 'mdlVarian'), ('Specsheet', 'BomCtrl', 'mdlVarianBaru')):
    app.set_query(pg, 'a_variant_save', body=SAVE)
    app.add_query(pg, 'q_code_suggest', 'q_code_hint', SUGGEST)
    app.set_js(pg, ctrl, js(f'js/{ctrl}.js'))
    app.set_cw_source(pg, 'cwVariantForm', html=rd('widgets/cwVariantForm/index.html'), css=rd('widgets/cwVariantForm/style.css'),
                      js=rd('widgets/cwVariantForm/script.js'))
    resize_modal(app, pg, modal, 760, 75)

lock_manual_queries(app)
app.publish_all()
app.save(OUT)
print('\n'.join(app.log))
print('OK ->', OUT)
