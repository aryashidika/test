# Build R2b: salin export_r2a.json (R2 yang sudah dirapikan user) -> edit di tempat -> exports/build_r2b.json
# Varian satu baris seperti ERP (Material Code, warna, thickness teks), isi otomatis dari bagian kode, label Mea.
import copy, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App

ROOT = r'D:/OJT_PM/Mock Up/appsmith'
BASE = f'{ROOT}/exports/export_r2a.json'
OUT = f'{ROOT}/exports/build_r2b.json'
app = App(BASE)
d = app.d
TOKEN = '{{appsmith.store.token}}'

def rd(path):
    return open(f'{ROOT}/{path}', encoding='utf-8').read()

def sub_all(text, pairs, where):
    for old, new in pairs:
        assert text.count(old) == 1, f'{where}: harus tepat 1x: {old[:70]!r} ({text.count(old)}x)'
        text = text.replace(old, new)
    return text

def add_event(w, event, handler):
    if event not in w['events']:
        w['events'].append(event)
    w[event] = handler
    for lk in ('dynamicTriggerPathList', 'dynamicPropertyPathList'):
        lst = w.setdefault(lk, [])
        if not any(x['key'] == event for x in lst):
            lst.append({'key': event})

def col_cv(table, cid):
    return ('{{(() => { const tableData = ' + table + '.processedTableData || []; return tableData.length > 0 ? '
            f'tableData.map((currentRow, currentIndex) => (currentRow["{cid}"])) : {cid} }})()}}}}')

d['exportedApplication']['name'] = 'Product Management R2b'

# ================================================================ Material Detail: varian satu baris
PG = 'Material Detail'
MID = "{{appsmith.URL.queryParams.id || ''}}"
app.set_query(PG, 'q_variants', body=f'''SELECT v.id, v.code, v.color, v.thickness, fn_thickness_label(v.thickness) AS thickness_label,
       v.status, v.updated_at, v.updated_by
FROM (SELECT fn_auth({TOKEN}, 'view_master') AS me) a
JOIN material_variant v ON v.material_id::text = {MID} AND fn_can_see_factory(a.me, v.factory_id)
ORDER BY v.status = 'INACTIVE', v.code;''')
app.add_query(PG, 'a_variant_save', 'a_variant_add', f'''SELECT fn_variant_save({TOKEN}, nullif({{{{this.params.id || ''}}}}, '')::uuid,
                       {{{{this.params.material_id}}}}::uuid, {{{{this.params.code}}}}, {{{{this.params.color}}}},
                       {{{{this.params.thickness || ''}}}}, {{{{this.params.status}}}}) AS id;''')
app.add_query(PG, 'q_code_hint', 'q_variants', f'''SELECT code, thickness_known, thickness, thickness_ref, color_known, color, color_ref, other_prefixes
FROM fn_variant_code_hint({TOKEN}, {{{{this.params.material_id}}}}::uuid, {{{{this.params.code}}}},
                          nullif({{{{this.params.exclude_id || ''}}}}, '')::uuid);''')
app.delete_query(PG, 'a_variant_add')
app.delete_query(PG, 'a_variant_update')
app.set_js(PG, 'MaterialDetailCtrl', rd('js/MaterialDetailCtrl.js'))

# tblVariants: Material Code, Warna, Thickness (urutan seperti ERP); kolom thickness_mm lama dihapus
t = app.widget(PG, 'tblVariants')
pc = t['primaryColumns']
T = 'tblVariants'
del pc['thickness_mm']
pc['thickness'] = copy.deepcopy(pc['id'])                       # kolom tersembunyi (dipakai form ubah)
pc['thickness'].update(id='thickness', originalId='thickness', alias='thickness', label='thickness',
                       computedValue=col_cv(T, 'thickness'), isVisible=False)
order = ['code', 'color', 'thickness_label', 'status', 'updated_at', 'updated_by', 'customColumn1', 'id', 'thickness']
assert set(order) == set(pc), sorted(set(pc) ^ set(order))
t['columnOrder'] = order
for i, k in enumerate(order):
    pc[k]['index'] = float(i)
t['dynamicBindingPathList'] = [x for x in t['dynamicBindingPathList'] if not x['key'].startswith('primaryColumns.thickness_mm.')]
t['dynamicBindingPathList'].append({'key': 'primaryColumns.thickness.computedValue'})
t['columnWidthMap'] = {k: v for k, v in (t.get('columnWidthMap') or {}).items() if k != 'thickness_mm'}
app.note('tblVariants: urutan Material Code · Warna · Thickness; thickness_mm -> thickness (tersembunyi)')

# form varian
w = app.widget(PG, 'cwVariantForm')
link_css = app.widget(PG, 'cwLinkForm')['uncompiledSrcDoc']['css']
app.set_cw_source(PG, 'cwVariantForm', html=rd('widgets/cwVariantForm/index.html'),
                  js=rd('widgets/cwVariantForm/script.js'), css=link_css + rd('widgets/cwVariantForm/extra.css'))
add_event(w, 'onLookup', '{{MaterialDetailCtrl.lookupVariantCode()}}')
m = app.widget(PG, 'mdlVarian')
m['height'] = 560; m['bottomRow'] = m['topRow'] + 560
c = m['children'][0]; c['bottomRow'] = 560; c['minHeight'] = 560
w['bottomRow'] = w['topRow'] + 55
m['leftColumn'], m['rightColumn'] = 20.0, 44.0                   # selebar modal lain (tanpa tabel kombinasi)

# ================================================================ label Mea (UoM)
MAT_PAIRS = [
    ('<label for="uom">UoM <span class="req">*</span></label>', '<label for="uom">Mea (UoM) <span class="req">*</span></label>'),
    ('Nama + UoM yang sama di pabrik Anda dianggap material yang sama.', 'Nama + Mea yang sama di pabrik Anda dianggap material yang sama.'),
]
for pg in ('Master Material', 'Material Detail'):
    w = app.widget(pg, 'cwMaterialForm')
    app.set_cw_source(pg, 'cwMaterialForm', html=sub_all(w['uncompiledSrcDoc']['html'], MAT_PAIRS, f'{pg}/cwMaterialForm'))
js_mat = app.widget('Master Material', 'cwMaterialForm')['uncompiledSrcDoc']['js']
js_mat2 = js_mat.replace("[['category', 'Kategori'], ['name', 'Nama material'], ['uom', 'UoM']]",
                         "[['category', 'Kategori'], ['name', 'Nama material'], ['uom', 'Mea (UoM)']]")
assert js_mat2 != js_mat
for pg in ('Master Material', 'Material Detail'):
    app.set_cw_source(pg, 'cwMaterialForm', js=js_mat2)
app.widget('Master Material', 'tblMaterials')['primaryColumns']['uom']['label'] = 'Mea'
app.replace_js('Master Material', 'MaterialCtrl', [("'Lengkapi kategori, nama, dan UoM.'", "'Lengkapi kategori, nama, dan Mea.'")])
app.note('label UoM -> Mea (UoM) di form material & kolom tblMaterials')

# ================================================================ simpan sumber widget ke repo (kondisi final)
for pg, n in (('Material Detail', 'cwVariantForm'), ('Master Material', 'cwMaterialForm')):
    s = app.widget(pg, n)['uncompiledSrcDoc']
    for part, fn in (('html', 'index.html'), ('css', 'style.css'), ('js', 'script.js')):
        with open(f'{ROOT}/widgets/{n}/{fn}', 'w', encoding='utf-8', newline='\n') as f:
            f.write(s[part])
with open(f'{ROOT}/js/MaterialCtrl.js', 'w', encoding='utf-8', newline='\n') as f:
    f.write(app.js_body('Master Material', 'MaterialCtrl'))

# ================================================================ semua query DB Manual dikunci (userSetOnLoad)
for a in d['actionList']:
    u = a['unpublishedAction']
    if a.get('pluginType') == 'DB' and u['runBehaviour'] == 'MANUAL':
        u['userSetOnLoad'] = True

app.publish_all()
app.save(OUT)
print('\n'.join(app.log))
print('OK ->', OUT)
