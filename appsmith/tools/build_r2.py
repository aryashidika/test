# Build R2: salin export_r1.json -> edit di tempat -> exports/build_r2.json
# Master tanpa approval, Material Induk + Varian per pabrik, page Master Pilihan.
import copy, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App

ROOT = r'D:/OJT_PM/Mock Up/appsmith'
BASE = f'{ROOT}/exports/export_r1.json'
OUT = f'{ROOT}/exports/build_r2.json'
app = App(BASE)
d = app.d

def rd(path):
    return open(f'{ROOT}/{path}', encoding='utf-8').read()

def sub_all(text, pairs, where):
    for old, new in pairs:
        assert text.count(old) == 1, f'{where}: harus tepat 1x: {old[:70]!r} ({text.count(old)}x)'
        text = text.replace(old, new)
    return text

TOKEN = '{{appsmith.store.token}}'
SIMILAR_CSS = rd('widgets/_similar.css')

def add_event(w, event, handler):
    """Tambah event Custom Widget (mis. onSearch) + handler-nya."""
    if event not in w['events']:
        w['events'].append(event)
    w[event] = handler
    for lk in ('dynamicTriggerPathList', 'dynamicPropertyPathList'):
        lst = w.setdefault(lk, [])
        if not any(x['key'] == event for x in lst):
            lst.append({'key': event})

def resize_modal(page, modal, height, cw_rows):
    m = app.widget(page, modal)
    m['height'] = height
    m['bottomRow'] = m['topRow'] + height
    c = m['children'][0]
    c['bottomRow'] = height
    c['minHeight'] = height
    k = c['children'][0]
    k['bottomRow'] = k['topRow'] + cw_rows

def col_cv(table, cid, expr=None):
    e = expr or f'currentRow["{cid}"]'
    fallback = expr.replace('currentRow.', 'currentRow.') if expr else cid
    return ('{{(() => { const tableData = ' + table + '.processedTableData || []; return tableData.length > 0 ? '
            f'tableData.map((currentRow, currentIndex) => ({e})) : {fallback} }})()}}}}')

def cell_flag(table, expr):
    return ('{{(() => { const tableData = ' + table + '.processedTableData || []; return tableData.length > 0 ? '
            f'tableData.map((currentRow, currentIndex) => ({expr})) : {expr} }})()}}}}')

def rebuild_columns(t, cols, order):
    """Ganti seluruh kolom tabel; dynamicBindingPathList disusun ulang dari isi kolom."""
    name = t['widgetName']
    for i, k in enumerate(order):
        c = cols[k]
        c.update(id=k, originalId=k, index=float(i))
        if c.get('columnType') != 'button':
            c['alias'] = k
    t['primaryColumns'] = {k: cols[k] for k in order}
    t['columnOrder'] = order
    t['columnWidthMap'] = {}
    t.pop('cachedTableData', None)
    keep = [x for x in t['dynamicBindingPathList'] if not x['key'].startswith('primaryColumns.')]
    trig = [x for x in t.get('dynamicTriggerPathList', []) if not x['key'].startswith('primaryColumns.')]
    for k in order:
        for p, v in cols[k].items():
            if isinstance(v, str) and '{{' in v:
                (trig if p == 'onClick' else keep).append({'key': f'primaryColumns.{k}.{p}'})
    t['dynamicBindingPathList'] = keep
    t['dynamicTriggerPathList'] = trig
    s = json.dumps(t)
    assert all(f'"{x}' not in s for x in ()), name

def text_col(tpl, table, cid, label, width=150.0, expr=None, ctype='text', visible=True):
    c = copy.deepcopy(tpl)
    for k in ('textColor', 'cellBackground', 'fontStyle'):
        c.pop(k, None)
    c.update(label=label, width=width, columnType=ctype, isVisible=visible, isDerived=False,
             isCellVisible=True, computedValue=col_cv(table, cid, expr))
    return c

def button_col(tpl, table, label, on_click, visible_expr=None, variant=None):
    c = copy.deepcopy(tpl)
    c.update(label='-', buttonLabel=label, onClick=on_click, isDerived=True,
             isCellVisible=cell_flag(table, visible_expr) if visible_expr else True,
             computedValue='')
    for k in ('buttonColor',):
        if isinstance(c.get(k), str):
            c[k] = re.sub(r'\btbl\w+\.processedTableData', f'{table}.processedTableData', c[k])
    if variant:
        c['buttonVariant'] = variant
    return c

def retarget(w, old, new):
    """Ganti nama widget lama di semua string properti (salinan tabel)."""
    w2 = json.loads(json.dumps(w).replace(old + '.', new + '.'))
    w.clear(); w.update(w2)

def hide_extra(table, fields):
    """Kolom hasil query yang tidak ditampilkan: tetap didaftarkan sebagai kolom tersembunyi.
    Tanpa ini Appsmith menambahkannya otomatis sebagai kolom yang terlihat."""
    t = app.widget(*table)
    pc, order = t['primaryColumns'], t['columnOrder']
    tpl = next(c for c in pc.values() if c.get('columnType') == 'text')
    for f in fields:
        if f in pc:
            continue
        c = text_col(tpl, t['widgetName'], f, f, 100.0, visible=False)
        c.update(id=f, originalId=f, alias=f, index=float(len(order)))
        pc[f] = c
        order.append(f)
        t['dynamicBindingPathList'].append({'key': f'primaryColumns.{f}.computedValue'})

STATUS_OPTIONS_NOTE = 'ACTIVE / INACTIVE'

# ================================================================ nama app
d['exportedApplication']['name'] = 'Product Management R2'

# ================================================================ temuan R1: query Manual kembali Automatic saat import
app.set_query('Admin', 'q_factories', run_behaviour='MANUAL')
app.set_query('Cost Breakdown (CBD)', 'q_change_log_images', run_behaviour='MANUAL')
for pg in ('Admin', 'Cost Breakdown (CBD)'):
    lay = app.page(pg)['unpublishedPage']['layouts'][0]
    lay['layoutOnLoadActions'] = [g for g in ([x for x in grp if x['name'] not in ('q_factories', 'q_change_log_images')]
                                              for grp in lay['layoutOnLoadActions']) if g]
app.note('T53: q_factories & q_change_log_images Manual + userSetOnLoad (tidak berubah Automatic lagi saat import)')

SIMILAR_Q = f'''SELECT ref_id, label, info
FROM fn_similar_names({TOKEN}, {{{{this.params.kind}}}}, {{{{this.params.text}}}},
                      nullif({{{{this.params.exclude_id || ''}}}}, '')::uuid);'''

# ================================================================ Master Supplier
PG = 'Master Supplier'
app.set_query(PG, 'a_supplier_insert', body=f'''SELECT fn_supplier_save({TOKEN}, NULL, {{{{this.params.name}}}}, 'ACTIVE') AS id;''')
app.set_query(PG, 'a_supplier_update', body=f'''SELECT fn_supplier_save({TOKEN}, {{{{this.params.id}}}}::uuid, {{{{this.params.name}}}},
                        {{{{this.params.status}}}}) AS id;''')
app.add_query(PG, 'q_similar', 'q_suppliers', SIMILAR_Q)
app.set_js(PG, 'SupplierCtrl', rd('js/SupplierCtrl.js'))
w = app.widget(PG, 'cwSupplierForm')
app.set_cw_source(PG, 'cwSupplierForm', html=rd('widgets/cwSupplierForm/index.html'),
                  js=rd('widgets/cwSupplierForm/script.js'), css=w['uncompiledSrcDoc']['css'] + SIMILAR_CSS)
w['defaultModel'] = '''{{ {
  key: SupplierCtrl.formKey,
  mode: SupplierCtrl.isNew ? 'add' : 'edit',
  form: SupplierCtrl.form,
  statusOptions: SupplierCtrl.statusOptions,
  similar: SupplierCtrl.similar,
  similarFor: SupplierCtrl.similarFor,
  busy: SupplierCtrl.busy,
  message: SupplierCtrl.message
} }}'''
add_event(w, 'onSearch', '{{SupplierCtrl.searchSimilar()}}')
resize_modal(PG, 'mdlSupplier', 470, 46)
app.widget(PG, 'selSupplierFilterStatus')['placeholderText'] = 'Semua status'

# ================================================================ Master Komponen
PG = 'Master Komponen'
app.set_query(PG, 'a_component_update', body=f'''SELECT fn_component_save({TOKEN}, {{{{this.params.id}}}}::uuid, {{{{this.params.group_code}}}},
                         {{{{this.params.number}}}}::integer, {{{{this.params.name}}}}, {{{{this.params.status}}}}) AS id;''')
app.delete_query(PG, 'a_component_set_status')
app.add_query(PG, 'q_similar', 'q_components', SIMILAR_Q)
app.set_js(PG, 'KomponenCtrl', rd('js/KomponenCtrl.js'))
t = app.widget(PG, 'tblComponents')
del t['primaryColumns']['customColumn1']                      # tombol Approve
t['columnOrder'].remove('customColumn1')
t['dynamicBindingPathList'] = [x for x in t['dynamicBindingPathList'] if not x['key'].startswith('primaryColumns.customColumn1.')]
t['dynamicTriggerPathList'] = [x for x in t['dynamicTriggerPathList'] if not x['key'].startswith('primaryColumns.customColumn1.')]
for i, k in enumerate(t['columnOrder']):
    t['primaryColumns'][k]['index'] = float(i)
t['primaryColumns']['customColumn2']['buttonLabel'] = 'Ubah'
app.note('tblComponents: kolom Approve dihapus')
b = app.set_prop(PG, 'btnKomponenTambah', 'text', '+ Tambah Komponen', binding=False)
w = app.widget(PG, 'cwKomponenForm')
src = w['uncompiledSrcDoc']
html = sub_all(src['html'], [
    ('''  <input id="name" type="text" maxlength="150" autocomplete="off" placeholder="mis. Vamp">
''', '''  <input id="name" type="text" maxlength="150" autocomplete="off" placeholder="mis. Vamp">
  <div class="similar" id="similar" hidden>
    <div class="similar-title">Komponen dengan nama mirip sudah ada — pakai yang ini bila sama:</div>
    <ul id="similarList"></ul>
  </div>
'''),
    ('''  <div class="info" id="proposeInfo" hidden>Usulan tersimpan sebagai PROPOSED dan menunggu persetujuan Master Admin.</div>''',
     '''  <div class="info" id="addInfo" hidden>Komponen dipakai bersama semua pabrik dan langsung bisa dipilih.</div>
  <div class="field-note" id="editNote" hidden>Nama, nomor, dan kelompok tidak bisa diubah bila komponen sudah dipakai di dokumen terbit. INACTIVE ditolak selama masih dipakai di draft.</div>'''),
], 'cwKomponenForm.html')
SIMILAR_FN = '''
// ---- nama mirip (R2: "cari dulu, baru buat") ----
let similarTimer = null;
let lastQuery = null;
const norm = s => String(s || '').trim().replace(/\\s+/g, ' ').toLowerCase();

function renderSimilar(m) {
  const list = m.similar || [];
  const show = list.length > 0 && norm(m.similarFor) === norm($('name').value);
  $('similar').hidden = !show;
  const ul = $('similarList');
  ul.innerHTML = '';
  if (!show) return;
  list.forEach(x => {
    const li = document.createElement('li');
    li.textContent = x.label;
    if (x.info) {
      const meta = document.createElement('span');
      meta.className = 'meta';
      meta.textContent = ` · ${x.info}`;
      li.appendChild(meta);
    }
    ul.appendChild(li);
  });
}

function querySimilar() {
  clearTimeout(similarTimer);
  similarTimer = setTimeout(() => {
    const q = $('name').value.trim().replace(/\\s+/g, ' ');
    if (q === lastQuery) return;
    lastQuery = q;
    appsmith.updateModel({ similarQuery: q });
    appsmith.triggerEvent('onSearch');
  }, 350);
}

// Isi ulang field hanya saat modal dibuka'''
js = sub_all(src['js'], [
    ('// cwKomponenForm — form Tambah/Usulkan/Ubah Komponen', '// cwKomponenForm — form Tambah/Ubah Komponen'),
    ('\n// Isi ulang field hanya saat modal dibuka', SIMILAR_FN),
    ("$('title').textContent = isEdit ? 'Ubah Komponen' : (m.canManage ? 'Tambah Komponen' : 'Usulkan Komponen');",
     "$('title').textContent = isEdit ? 'Ubah Komponen' : 'Tambah Komponen';"),
    ("fillSelect($('status'), m.statusOptions, f.status || 'APPROVED');",
     "fillSelect($('status'), m.statusOptions, f.status || 'ACTIVE');"),
    ("  $('proposeInfo').hidden = isEdit || !!m.canManage;\n  $('btnSave').dataset.label = !isEdit && !m.canManage ? 'Usulkan' : 'Simpan';",
     "  $('addInfo').hidden = isEdit;\n  $('editNote').hidden = !isEdit;\n  $('btnSave').dataset.label = 'Simpan';\n  lastQuery = isEdit ? $('name').value.trim() : null;"),
    ("  showMessage(m.message);\n  setBusy(!!m.busy);\n}", "  showMessage(m.message);\n  setBusy(!!m.busy);\n  renderSimilar(m);\n}"),
    ("  $('number').addEventListener('input', updateHint);", "  $('number').addEventListener('input', updateHint);\n  $('name').addEventListener('input', querySimilar);"),
], 'cwKomponenForm.js')
app.set_cw_source(PG, 'cwKomponenForm', html=html, js=js, css=src['css'] + SIMILAR_CSS)
w['defaultModel'] = '''{{ {
  key: KomponenCtrl.formKey,
  mode: KomponenCtrl.isNew ? 'add' : 'edit',
  form: KomponenCtrl.form,
  groups: KomponenCtrl.groups(),
  statusOptions: KomponenCtrl.statusOptions,
  similar: KomponenCtrl.similar,
  similarFor: KomponenCtrl.similarFor,
  busy: KomponenCtrl.busy,
  message: KomponenCtrl.message
} }}'''
add_event(w, 'onSearch', '{{KomponenCtrl.searchSimilar()}}')
resize_modal(PG, 'mdlKomponen', 600, 59)
os.makedirs(f'{ROOT}/widgets/cwKomponenForm', exist_ok=True)

# ================================================================ Master Material
PG = 'Master Material'
META_Q = f'''SELECT string_agg(DISTINCT m.category, '|' ORDER BY m.category) AS categories,
       string_agg(DISTINCT m.uom, '|' ORDER BY m.uom) AS uoms
FROM (SELECT fn_auth({TOKEN}, 'view_master') AS me) a
LEFT JOIN material m ON fn_can_see_factory(a.me, m.factory_id);'''
app.set_query(PG, 'q_material_meta', body=META_Q)
app.set_query(PG, 'q_materials', body=f'''SELECT m.id, m.factory_name, m.name, m.category, m.uom, m.price_method, m.status,
       m.variant_count, m.active_variant_count, m.thicknesses, m.supplier_count, m.preferred_supplier,
       m.updated_at, m.updated_by
FROM (SELECT fn_auth({TOKEN}, 'view_master') AS me) a
JOIN v_material_list m ON fn_can_see_factory(a.me, m.factory_id)
WHERE ({{{{inpMaterialCari.text || ''}}}} = ''
       OR m.name ILIKE '%' || {{{{inpMaterialCari.text || ''}}}} || '%'
       OR m.category ILIKE '%' || {{{{inpMaterialCari.text || ''}}}} || '%'
       OR m.codes ILIKE '%' || {{{{inpMaterialCari.text || ''}}}} || '%')
  AND ({{{{selMaterialStatus.selectedOptionValue || ''}}}} = '' OR m.status = {{{{selMaterialStatus.selectedOptionValue || ''}}}})
  AND ({{{{selMaterialKategori.selectedOptionValue || ''}}}} = '' OR m.category = {{{{selMaterialKategori.selectedOptionValue || ''}}}})
ORDER BY m.factory_name, m.name_key, m.uom
LIMIT 500;''')
app.set_query(PG, 'a_material_add', body=f'''SELECT fn_material_add({TOKEN}, {{{{this.params.name}}}}, {{{{this.params.category}}}},
                       {{{{this.params.uom}}}}) AS id;''')
app.delete_query(PG, 'a_material_set_status')
app.add_query(PG, 'q_similar', 'q_materials', SIMILAR_Q)
app.set_js(PG, 'MaterialCtrl', rd('js/MaterialCtrl.js'))
app.widget(PG, 'inpMaterialCari')['placeholderText'] = 'Cari nama / kategori / Material Code…'
for sw in ('swMaterialBelumHarga', 'swMaterialHargaPending'):      # harga kembali di R3
    app.set_prop(PG, sw, 'isVisible', False, binding=False)
app.set_prop(PG, 'btnMaterialTambah', 'text', '+ Tambah Material', binding=False)

t = app.widget(PG, 'tblMaterials')
pc = t['primaryColumns']
T = 'tblMaterials'
cols = {
    'id': pc['id'],
    'factory_name': text_col(pc['name'], T, 'factory_name', 'Pabrik', 140.0),
    'name': pc['name'],
    'category': pc['category'],
    'uom': pc['uom'],
    'variant_count': text_col(pc['name'], T, 'variant_count', 'Varian', 220.0, 'MaterialCtrl.variantSummary(currentRow)'),
    'price_method': pc['price_method'],
    'status': pc['status'],
    'supplier_count': pc['supplier_count'],
    'updated_at': pc['updated_at'],
    'customColumn2': pc['customColumn2'],
}
cols['supplier_count'].pop('textColor', None)
cols['name']['width'] = 260.0
order = list(cols)
rebuild_columns(t, cols, order)
app.note('tblMaterials: kolom Pabrik + Varian; Kode/Thickness/harga/Approve dihapus')

MAT_HTML, MAT_JS = rd('widgets/cwMaterialForm/index.html'), rd('widgets/cwMaterialForm/script.js')
w = app.widget(PG, 'cwMaterialForm')
mat_css = w['uncompiledSrcDoc']['css'] + SIMILAR_CSS
app.set_cw_source(PG, 'cwMaterialForm', html=MAT_HTML, js=MAT_JS, css=mat_css)
w['defaultModel'] = '''{{ {
  key: MaterialCtrl.formKey,
  mode: 'add',
  form: MaterialCtrl.form,
  categories: MaterialCtrl.meta().categories,
  uoms: MaterialCtrl.meta().uoms,
  statusOptions: MaterialCtrl.statusOptions,
  canIdentity: true,
  canPriceMethod: false,
  canStatus: false,
  similar: MaterialCtrl.similar,
  similarFor: MaterialCtrl.similarFor,
  busy: MaterialCtrl.busy,
  message: MaterialCtrl.message
} }}'''
add_event(w, 'onSearch', '{{MaterialCtrl.searchSimilar()}}')
resize_modal(PG, 'mdlMaterial', 640, 63)

# ================================================================ Material Detail
PG = 'Material Detail'
MID = "{{appsmith.URL.queryParams.id || ''}}"
app.set_query(PG, 'q_material', body=f'''SELECT m.id, m.factory_id, m.factory_name, m.name, m.category, m.uom, m.price_method, m.status,
       m.variant_count, m.active_variant_count, m.supplier_count, m.preferred_supplier, m.updated_at, m.updated_by
FROM (SELECT fn_auth({TOKEN}, 'view_master') AS me) a
JOIN v_material_list m ON fn_can_see_factory(a.me, m.factory_id)
WHERE m.id::text = {MID};''')
app.set_query(PG, 'q_material_meta', body=META_Q)
app.set_query(PG, 'q_links', body=f'''SELECT ms.id, ms.supplier_id, s.name AS supplier_name, s.status AS supplier_status,
       ms.is_preferred, ms.status, ms.updated_at, ms.updated_by
FROM (SELECT fn_auth({TOKEN}, 'view_master') AS me) a
JOIN material_supplier ms ON ms.material_id::text = {MID}
JOIN material m ON m.id = ms.material_id AND fn_can_see_factory(a.me, m.factory_id)
JOIN supplier s ON s.id = ms.supplier_id
ORDER BY ms.is_preferred DESC, ms.status = 'INACTIVE', s.name_key;''')
app.set_query(PG, 'q_link_supplier_options', body=f'''SELECT s.id, s.name
FROM supplier s
WHERE (SELECT fn_auth({TOKEN}, 'view_master')) IS NOT NULL
  AND s.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM material_supplier ms
                   WHERE ms.supplier_id = s.id AND ms.material_id::text = {MID})
ORDER BY s.name_key;''')
app.add_query(PG, 'q_variants', 'q_links', f'''SELECT v.id, v.thickness_mm, fn_thickness_label(v.thickness_mm) AS thickness_label,
       v.color, v.code, v.status, v.updated_at, v.updated_by
FROM (SELECT fn_auth({TOKEN}, 'view_master') AS me) a
JOIN material_variant v ON v.material_id::text = {MID} AND fn_can_see_factory(a.me, v.factory_id)
ORDER BY v.status = 'INACTIVE', v.thickness_mm NULLS FIRST, v.color_key;''')
app.set_query(PG, 'a_material_update', body=f'''SELECT fn_material_update({TOKEN}, {{{{this.params.id}}}}::uuid, {{{{this.params.name}}}},
                          {{{{this.params.category}}}}, {{{{this.params.uom}}}}, {{{{this.params.status}}}},
                          {{{{this.params.price_method}}}}) AS id;''')
app.set_query(PG, 'a_link_save', body=f'''SELECT fn_link_save({TOKEN}, nullif({{{{this.params.link_id || ''}}}}, '')::uuid,
                    {{{{this.params.material_id}}}}::uuid, {{{{this.params.supplier_id}}}}::uuid,
                    {{{{this.params.is_preferred}}}}::boolean, {{{{this.params.status}}}}) AS id;''')
app.add_query(PG, 'a_variant_add', 'a_link_save', f'''SELECT fn_variant_add({TOKEN}, {{{{this.params.material_id}}}}::uuid,
                      {{{{JSON.stringify(this.params.items || [])}}}}::jsonb) AS n;''')
app.add_query(PG, 'a_variant_update', 'a_link_save', f'''SELECT fn_variant_update({TOKEN}, {{{{this.params.id}}}}::uuid,
                         {{{{String(this.params.thickness_mm ?? '')}}}}, {{{{this.params.color}}}},
                         {{{{this.params.code}}}}, {{{{this.params.status}}}}) AS id;''')
app.delete_query(PG, 'a_link_set_status')
app.set_js(PG, 'MaterialDetailCtrl', rd('js/MaterialDetailCtrl.js'))
app.replace_js(PG, 'Auth', [('const q = [q_material, q_material_meta, q_links, q_link_supplier_options];',
                             'const q = [q_material, q_material_meta, q_variants, q_links, q_link_supplier_options];')])

# -- tblLinks: tanpa kode supplier & tombol Approve
t = app.widget(PG, 'tblLinks')
pc = t['primaryColumns']
T = 'tblLinks'
cols = {k: pc[k] for k in ('id', 'supplier_id', 'supplier_name', 'is_preferred', 'status', 'supplier_status',
                           'updated_at', 'updated_by', 'customColumn2')}
cols['customColumn2']['isCellVisible'] = cell_flag(T, 'MaterialDetailCtrl.canManageMaster()')
cols['customColumn2']['buttonLabel'] = 'Ubah'
cols['supplier_name']['label'] = 'Supplier'
rebuild_columns(t, cols, list(cols))
app.note('tblLinks: kolom Kode di Supplier & tombol Approve dihapus')

# -- tblVariants (salinan tblLinks) + tombol tambah varian (salinan btnLinkTambah)
tv = app.clone_widget(PG, 'tblLinks', 'tblVariants')
retarget(tv, 'tblLinks', 'tblVariants')
src_cols = tv['primaryColumns']
T = 'tblVariants'
tpl_text, tpl_btn = src_cols['supplier_name'], src_cols['customColumn2']
cols = {
    'thickness_label': text_col(tpl_text, T, 'thickness_label', 'Thickness', 150.0),
    'color': text_col(tpl_text, T, 'color', 'Warna', 200.0),
    'code': text_col(tpl_text, T, 'code', 'Material Code', 200.0),
    'status': copy.deepcopy(src_cols['status']),
    'updated_at': copy.deepcopy(src_cols['updated_at']),
    'updated_by': copy.deepcopy(src_cols['updated_by']),
    'customColumn1': button_col(tpl_btn, T, 'Ubah', '{{MaterialDetailCtrl.openEditVariant(currentRow)}}',
                                'MaterialDetailCtrl.canManageMaster()'),
    'id': text_col(tpl_text, T, 'id', 'id', 100.0, visible=False),
}
cols['updated_by']['isVisible'] = True
cols['updated_by']['label'] = 'Oleh'
rebuild_columns(tv, cols, list(cols))
tv['tableData'] = '{{q_variants.data}}'
tv['label'] = 'Varian'
tv['primaryColumnId'] = 'id'
tv['searchKey'] = ''
tv.pop('onRowSelected', None)
bv = app.clone_widget(PG, 'btnLinkTambah', 'btnVarianTambah')
bv['text'] = '+ Tambah Varian'
bv['onClick'] = '{{MaterialDetailCtrl.openAddVariant()}}'
bv['isVisible'] = '{{MaterialDetailCtrl.canManageMaster() && !!MaterialDetailCtrl.material()}}'
app.set_prop(PG, 'btnLinkTambah', 'text', '+ Tambah Supplier')
app.set_prop(PG, 'btnLinkTambah', 'isVisible', '{{MaterialDetailCtrl.canLink() && !!MaterialDetailCtrl.material()}}')

# -- Tab Varian | Supplier (salinan bentuk tabAdmin dari page Admin)
main = app.dsl(PG)
tab_src = app.widget('Admin', 'tabAdmin')
tab = copy.deepcopy({k: v for k, v in tab_src.items() if k != 'children'})
tab.update(widgetName='tabMaterial', widgetId=app.new_wid(), key=app.new_wid(), parentId=main['widgetId'],
           topRow=19.0, bottomRow=75.0, defaultTab='Varian', dynamicHeight='FIXED')
canvas_tpl = tab_src['children'][0]
tab['children'] = []
tab['tabsObj'] = {}
moved = {}
for i, (tab_id, label, members) in enumerate((('tab1', 'Varian', ('btnVarianTambah', 'tblVariants')),
                                              ('tab2', 'Supplier', ('btnLinkTambah', 'tblLinks')))):
    cv = copy.deepcopy({k: v for k, v in canvas_tpl.items() if k != 'children'})
    cv.update(widgetName=f'CanvasTab{label}', widgetId=app.new_wid(), key=app.new_wid(), parentId=tab['widgetId'],
              tabId=tab_id, tabName=label, bottomRow=520.0, minHeight=520.0, children=[])
    for name in members:
        wdg, parent = app.widget(PG, name, with_parent=True)
        parent['children'].remove(wdg)
        wdg['parentId'] = cv['widgetId']
        if name.startswith('btn'):
            wdg.update(topRow=0.0, bottomRow=4.0, leftColumn=48.0, rightColumn=64.0)
        else:
            wdg.update(topRow=5.0, bottomRow=50.0, leftColumn=0.0, rightColumn=64.0)
        cv['children'].append(wdg)
    tab['children'].append(cv)
    tab['tabsObj'][tab_id] = {'label': label, 'id': tab_id, 'widgetId': cv['widgetId'], 'isVisible': True,
                              'index': float(i), 'positioning': 'vertical'}
main['children'].insert(main['children'].index(app.widget(PG, 'cntInfo')) + 1, tab)
lbl, lbl_parent = app.widget(PG, 'txtSupplierJudul', with_parent=True)
lbl_parent['children'].remove(lbl)
h = app.widget(PG, 'cntHarga')
h['isVisible'] = False                               # harga per varian × supplier di R3
h['dynamicBindingPathList'] = [x for x in h['dynamicBindingPathList'] if x['key'] != 'isVisible']
shift = 76.0 - h['topRow']
h['topRow'] += shift; h['bottomRow'] += shift
main['bottomRow'] = max(main['bottomRow'], (h['bottomRow'] + 2) * 10)
app.note('Material Detail: tab Varian | Supplier (tabMaterial), txtSupplierJudul dihapus, cntHarga disembunyikan (R3)')

# -- modal varian (salinan mdlLink)
mv = app.clone_widget(PG, 'mdlLink', 'mdlVarian', renames={'Canvas4': 'CanvasVarian', 'cwLinkForm': 'cwVariantForm'})
cvf = mv['children'][0]['children'][0]
cvf['defaultModel'] = '{{MaterialDetailCtrl.variantFormModel()}}'
cvf['onSave'] = '{{MaterialDetailCtrl.saveVariant()}}'
cvf['onCancel'] = "{{closeModal('mdlVarian')}}"
link_css = app.widget(PG, 'cwLinkForm')['uncompiledSrcDoc']['css']
app.set_cw_source(PG, 'cwVariantForm', html=rd('widgets/cwVariantForm/index.html'),
                  js=rd('widgets/cwVariantForm/script.js'), css=link_css + rd('widgets/cwVariantForm/extra.css'))
resize_modal(PG, 'mdlVarian', 700, 69)
mv['leftColumn'], mv['rightColumn'] = 16.0, 48.0

# -- form supplier material: tanpa kode supplier & usulan
w = app.widget(PG, 'cwLinkForm')
src = w['uncompiledSrcDoc']
html = sub_all(src['html'], [
    ('''  <label for="code">Kode material di supplier</label>
  <input id="code" type="text" maxlength="60" autocomplete="off" placeholder="opsional">

''', ''),
    ('''  <div class="info" id="proposeInfo" hidden>Supplier baru tersimpan sebagai PROPOSED sampai di-approve Master Admin (tetap bisa dipakai di BOM).</div>''',
     '''  <div class="info" id="proposeInfo" hidden>Supplier langsung terhubung ke material ini (semua varian). Harga per varian diajukan tim CBD.</div>'''),
], 'cwLinkForm.html')
js = sub_all(src['js'], [
    ('// (canLink: kode & supplier utama, canStatus: status); aturan final di DB.',
     '// (canLink: supplier utama, canStatus: status); aturan final di DB. R2: tanpa kode supplier & approval.'),
    ("  $('code').value = f.supplier_material_code || '';\n  $('code').disabled = !canLink;\n", ''),
    ("fillSelect($('status'), m.statusOptions, f.status || 'PROPOSED');", "fillSelect($('status'), m.statusOptions, f.status || 'ACTIVE');"),
    ("'Kode supplier dan supplier utama diatur tim specsheet.'", "'Supplier utama diatur tim specsheet.'"),
    ("  $('proposeInfo').hidden = isEdit || canStatus;\n  (isEdit ? (canLink ? $('code') : $('status')) : $('supplier')).focus();",
     "  $('proposeInfo').hidden = isEdit;\n  (isEdit ? $('status') : $('supplier')).focus();"),
    ("    supplier_material_code: $('code').value.trim(),\n", ''),
    ("  $('code').addEventListener('keydown', e => {\n    if (e.key === 'Enter') submit();\n  });\n", ''),
], 'cwLinkForm.js')
assert "'code'" not in js and 'supplier_material_code' not in js
app.set_cw_source(PG, 'cwLinkForm', html=html, js=js, css=src['css'])

# -- form material (edit) di Material Detail: sumber sama dengan Master Material
w = app.widget(PG, 'cwMaterialForm')
app.set_cw_source(PG, 'cwMaterialForm', html=MAT_HTML, js=MAT_JS, css=w['uncompiledSrcDoc']['css'] + SIMILAR_CSS)
resize_modal(PG, 'mdlMaterial', 560, 55)

# ================================================================ Beranda
PG = 'Beranda'
app.delete_query(PG, 'q_worklist_proposals')
app.replace_js(PG, 'BerandaCtrl', [
    ('VENDOR_SPEC: [q_worklist_spec, q_worklist_proposals],', 'VENDOR_SPEC: [q_worklist_spec],'),
    ('''	proposalCounts() {
		const c = { SUPPLIER: 0, MATERIAL: 0, COMPONENT: 0, LINK: 0 };
		(q_worklist_proposals.data || []).forEach(r => { c[r.kind] = Number(r.n) || 0; });
		return c;
	},
''', ''),
    ('''		const c = this.proposalCounts();
		const proposalTotal = c.SUPPLIER + c.MATERIAL + c.COMPONENT + c.LINK;
''', ''),
    ('''				{ key: 'proposals', value: proposalTotal, label: 'Usulan menunggu persetujuan', tone: '' },
''', ''),
    ('''				{
					key: 'proposals', title: 'Usulan Master Data', empty: 'Tidak ada usulan yang menunggu.',
					items: proposalTotal ? [{
						title: `${c.SUPPLIER} supplier · ${c.MATERIAL} material · ${c.COMPONENT} komponen · ${c.LINK} supplier material`,
						meta: 'Menunggu persetujuan Master Admin. Usulan sudah bisa dipakai di BOM, tetapi specsheet baru bisa terbit setelah semuanya disetujui.',
						target: 'Master Material', params: {},
					}] : [],
				},
''', ''),
    ('''		const nav = r.kind === 'COMPONENT' ? { target: 'Master Komponen', params: {} }
			: r.kind === 'SUPPLIER' ? { target: 'Master Supplier', params: {} } : this.toMaterial(r);
''', '''		const nav = this.toMaterial(r);
'''),
    ('''				{ key: 'appr-suppliers', value: of('SUPPLIER').length, label: 'Supplier usulan', tone: 'warn' },
				{ key: 'appr-materials', value: of('MATERIAL').length, label: 'Material usulan', tone: 'warn' },
				{ key: 'appr-components', value: of('COMPONENT').length, label: 'Komponen usulan', tone: 'warn' },
				{ key: 'appr-links', value: of('LINK').length, label: 'Supplier material usulan', tone: 'warn' },
''', ''),
    ('''				section('appr-suppliers', 'SUPPLIER', 'Supplier Menunggu Persetujuan', 'Tidak ada supplier usulan.',
					'Disetujui di halaman Master Supplier (Ubah → status APPROVED).'),
				section('appr-materials', 'MATERIAL', 'Material Menunggu Persetujuan', 'Tidak ada material usulan.'),
				section('appr-components', 'COMPONENT', 'Komponen Menunggu Persetujuan', 'Tidak ada komponen usulan.',
					'Disetujui di halaman Master Komponen.'),
				section('appr-links', 'LINK', 'Supplier Material Menunggu Persetujuan', 'Tidak ada supplier material usulan.',
					'Terbentuk otomatis saat tim specsheet memilih supplier di BOM.'),
''', ''),
    ("subtitle: 'Usulan yang menunggu persetujuan Anda.',", "subtitle: 'Usulan harga yang menunggu persetujuan Anda.',"),
])

# ================================================================ page baru: Master Pilihan (salinan Master Supplier)
SRC_PG, NEW_PG = 'Master Supplier', 'Master Pilihan'
src_page = app.page(SRC_PG)
new_page = copy.deepcopy(src_page)
new_page['gitSyncId'] = app.new_git()
up = new_page['unpublishedPage']
up['name'] = NEW_PG
up['slug'] = 'master-pilihan'
lay = up['layouts'][0]
lay['id'] = NEW_PG
lay['layoutOnLoadActions'] = json.loads(json.dumps(lay['layoutOnLoadActions']).replace(f'"{SRC_PG}_', f'"{NEW_PG}_'))
WREN = {'selSupplierFilterStatus': 'selPilihanJenis', 'inpSupplierCari': 'inpPilihanCari',
        'btnSupplierCari': 'btnPilihanCari', 'btnSupplierTambah': 'btnPilihanTambah', 'tblSuppliers': 'tblPilihan',
        'mdlSupplier': 'mdlPilihan', 'cwSupplierForm': 'cwOptionForm', 'Canvas1': 'CanvasPilihan'}
def regen(node, parent_id):
    if node['widgetId'] != '0':
        node['widgetId'] = app.new_wid()
        node['parentId'] = parent_id
    node['key'] = app.new_wid()
    node['widgetName'] = WREN.get(node['widgetName'], node['widgetName'])
    for ch in node.get('children', []) or []:
        regen(ch, node['widgetId'])
regen(lay['dsl'], None)
lay['dsl'] = json.loads(json.dumps(lay['dsl']).replace('tblSuppliers.', 'tblPilihan.')
                        .replace("'mdlSupplier'", "'mdlPilihan'").replace("pageTitle: 'Master Supplier'", "pageTitle: 'Master Pilihan'"))
pos = next(i for i, p in enumerate(d['pageList']) if p['unpublishedPage']['name'] == 'Material Detail') + 1
d['pageList'].insert(pos, new_page)
pages = d['exportedApplication']['pages']
pos2 = next(i for i, p in enumerate(pages) if p['id'] == 'Material Detail') + 1
pages.insert(pos2, {'id': NEW_PG, 'isDefault': False})

def clone_action(a, new_name=None):
    a2 = json.loads(json.dumps(a).replace(f'"{SRC_PG}_', f'"{NEW_PG}_').replace(f'"pageId": "{SRC_PG}"', f'"pageId": "{NEW_PG}"'))
    a2['gitSyncId'] = app.new_git()
    for k in ('unpublishedAction', 'publishedAction'):
        if k in a2 and a2[k]:
            a2[k]['pageId'] = NEW_PG
    if new_name:
        u = a2['unpublishedAction']
        u['name'] = new_name
        a2['id'] = f'{NEW_PG}_{new_name}'
    return a2

for a in [x for x in d['actionList'] if x['unpublishedAction']['pageId'] == SRC_PG]:
    u = a['unpublishedAction']
    cid = u.get('collectionId') or ''
    if cid.endswith('_SupplierCtrl'):
        continue                                     # diganti OptionCtrl
    if not cid and u['name'] not in ('q_me', 'q_similar', 'q_suppliers', 'a_supplier_insert'):
        continue
    rename = {'q_suppliers': 'q_options', 'a_supplier_insert': 'a_option_save'}.get(u['name']) if not cid else None
    d['actionList'].append(clone_action(a, rename))
for c in [x for x in d['actionCollectionList'] if x['unpublishedCollection']['pageId'] == SRC_PG]:
    nm = c['unpublishedCollection']['name']
    c2 = json.loads(json.dumps(c).replace(f'"{SRC_PG}_', f'"{NEW_PG}_'))
    c2['gitSyncId'] = app.new_git()
    for k in ('unpublishedCollection', 'publishedCollection'):
        if k in c2 and c2[k]:
            c2[k]['pageId'] = NEW_PG
    if nm == 'SupplierCtrl':
        c2['unpublishedCollection']['name'] = 'OptionCtrl'
        c2['id'] = f'{NEW_PG}_OptionCtrl'
        # entri fungsi dibuat ulang oleh set_js dari satu entri contoh
        tpl = next(x for x in d['actionList'] if x['unpublishedAction'].get('collectionId') == f'{SRC_PG}_SupplierCtrl')
        e = clone_action(tpl)
        e['unpublishedAction']['collectionId'] = c2['id']
        e['unpublishedAction']['name'] = 'canManage'
        e['unpublishedAction']['fullyQualifiedName'] = 'OptionCtrl.canManage'
        e['id'] = f'{NEW_PG}_OptionCtrl.canManage'
        d['actionList'].append(e)
    d['actionCollectionList'].append(c2)
app.note(f'page baru {NEW_PG} (salinan {SRC_PG})')

PG = NEW_PG
app.set_query(PG, 'q_options', body=f'''SELECT o.id, o.kind, o.value, o.sort_order, o.status, o.factory_id,
       coalesce(f.name, 'Bersama') AS factory_name, o.updated_at, o.updated_by
FROM (SELECT fn_auth({TOKEN}, 'view_master') AS me) a
JOIN model_option o ON o.factory_id IS NULL OR fn_can_see_factory(a.me, o.factory_id)
LEFT JOIN factory f ON f.id = o.factory_id
WHERE o.kind = {{{{selPilihanJenis.selectedOptionValue || 'KATEGORI'}}}}
  AND ({{{{inpPilihanCari.text || ''}}}} = '' OR o.value ILIKE '%' || {{{{inpPilihanCari.text || ''}}}} || '%')
ORDER BY f.name NULLS FIRST, o.status = 'INACTIVE', o.sort_order NULLS LAST, o.value_key;''', run_behaviour='MANUAL')
app.set_query(PG, 'a_option_save', body=f'''SELECT fn_option_save({TOKEN}, nullif({{{{this.params.id || ''}}}}, '')::uuid, {{{{this.params.kind}}}},
                      {{{{this.params.value}}}}, nullif({{{{String(this.params.sort_order ?? '')}}}}, '')::integer,
                      {{{{this.params.status}}}}) AS id;''')
app.set_js(PG, 'OptionCtrl', rd('js/OptionCtrl.js'))
app.replace_js(PG, 'Auth', [('return [q_suppliers];', 'return [q_options];')])

sel = app.widget(PG, 'selPilihanJenis')
sel.update(sourceData='{{OptionCtrl.kindOptions}}', defaultOptionValue='KATEGORI', placeholderText='Pilih jenis',
           labelText='', onOptionChange='{{q_options.run()}}', isFilterable=False)
sel.setdefault('dynamicTriggerPathList', []).append({'key': 'onOptionChange'})
inp = app.widget(PG, 'inpPilihanCari')
inp['placeholderText'] = 'Cari nilai…'
inp.pop('onSubmit', None)
bc = app.widget(PG, 'btnPilihanCari'); bc['onClick'] = '{{q_options.run()}}'
bt = app.widget(PG, 'btnPilihanTambah')
bt.update(text='+ Tambah Pilihan', onClick='{{OptionCtrl.openAdd()}}', isVisible='{{OptionCtrl.canAdd()}}')
# catatan cakupan (bersama / per pabrik) di samping tombol tambah: salinan cwHeader tidak cocok -> pakai teks tombol
t = app.widget(PG, 'tblPilihan')
src_cols = t['primaryColumns']
T = 'tblPilihan'
tpl_text, tpl_btn = src_cols['name'], src_cols['customColumn1']
cols = {
    'value': text_col(tpl_text, T, 'value', 'Nilai', 260.0),
    'sort_order': text_col(tpl_text, T, 'sort_order', 'Urutan', 90.0),
    'factory_name': text_col(tpl_text, T, 'factory_name', 'Pabrik', 160.0),
    'status': copy.deepcopy(src_cols['status']),
    'updated_at': copy.deepcopy(src_cols['updated_at']),
    'updated_by': copy.deepcopy(src_cols['updated_by']),
    'customColumn1': button_col(tpl_btn, T, 'Ubah', '{{OptionCtrl.openEdit(currentRow)}}', 'OptionCtrl.canManage()'),
    'id': text_col(tpl_text, T, 'id', 'id', 100.0, visible=False),
    'kind': text_col(tpl_text, T, 'kind', 'kind', 100.0, visible=False),
}
rebuild_columns(t, cols, list(cols))
t['tableData'] = '{{q_options.data}}'
t['label'] = 'Pilihan'
t['primaryColumnId'] = 'id'
t['searchKey'] = ''
w = app.widget(PG, 'cwOptionForm')
w['defaultModel'] = '{{OptionCtrl.formModel()}}'
w['onSave'] = '{{OptionCtrl.save()}}'
w['onCancel'] = "{{closeModal('mdlPilihan')}}"
add_event(w, 'onSearch', '{{OptionCtrl.searchSimilar()}}')
sup_css = app.widget('Master Supplier', 'cwSupplierForm')['uncompiledSrcDoc']['css']
app.set_cw_source(PG, 'cwOptionForm', html=rd('widgets/cwOptionForm/index.html'),
                  js=rd('widgets/cwOptionForm/script.js'), css=sup_css)
resize_modal(PG, 'mdlPilihan', 520, 51)
# jenis di kiri, cari di kanan; keterangan jenis (bersama / per pabrik) di samping tombol tambah
sel.update(leftColumn=0.0, rightColumn=20.0, mobileLeftColumn=0.0, mobileRightColumn=20.0)
inp.update(leftColumn=21.0, rightColumn=41.0, mobileLeftColumn=21.0, mobileRightColumn=41.0)
txt = copy.deepcopy(app.widget('Material Detail', 'txtHargaInfo'))
txt.update(widgetName='txtPilihanInfo', widgetId=app.new_wid(), key=app.new_wid(), parentId='0',
           text='{{OptionCtrl.note()}}', topRow=15.0, bottomRow=19.0, leftColumn=17.0, rightColumn=64.0)
app.dsl(PG)['children'].append(txt)
app.note('Master Pilihan: txtPilihanInfo (salinan txtHargaInfo) menampilkan cakupan jenis')

# ================================================================ kolom query yang tidak ditampilkan -> tersembunyi
hide_extra(('Master Material', 'tblMaterials'), ['active_variant_count', 'thicknesses', 'preferred_supplier', 'updated_by'])
hide_extra(('Material Detail', 'tblVariants'), ['thickness_mm'])
hide_extra(('Master Pilihan', 'tblPilihan'), ['factory_id'])
app.note('kolom tersembunyi ditambahkan untuk field query yang tidak ditampilkan')

# ================================================================ simpan sumber widget ke repo (kondisi final)
for pg, n, folder in (('Master Supplier', 'cwSupplierForm', 'cwSupplierForm'),
                      ('Master Komponen', 'cwKomponenForm', 'cwKomponenForm'),
                      ('Master Material', 'cwMaterialForm', 'cwMaterialForm'),
                      ('Material Detail', 'cwLinkForm', 'cwLinkForm'),
                      ('Material Detail', 'cwVariantForm', 'cwVariantForm'),
                      ('Master Pilihan', 'cwOptionForm', 'cwOptionForm')):
    s = app.widget(pg, n)['uncompiledSrcDoc']
    for part, fn in (('html', 'index.html'), ('css', 'style.css'), ('js', 'script.js')):
        with open(f'{ROOT}/widgets/{folder}/{fn}', 'w', encoding='utf-8', newline='\n') as f:
            f.write(s[part])

# ================================================================ semua query DB Manual dikunci (userSetOnLoad)
n = 0
for a in d['actionList']:
    u = a['unpublishedAction']
    if a.get('pluginType') == 'DB' and u['runBehaviour'] == 'MANUAL' and not u.get('userSetOnLoad'):
        u['userSetOnLoad'] = True
        n += 1
app.note(f'T53: userSetOnLoad=true untuk {n} query Manual lain (cegah berubah Automatic saat import)')

# ================================================================ selesai
app.publish_all()
app.save(OUT)
print('\n'.join(app.log))
print('OK ->', OUT)
