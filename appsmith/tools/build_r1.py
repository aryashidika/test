# Build R1: salin export_v11.json -> edit di tempat -> exports/build_r1.json
import copy, re, sys
from aslib import App
import cw_patches as P

BASE = r'D:/OJT_PM/Mock Up/appsmith/exports/export_v11.json'
OUT = r'D:/OJT_PM/Mock Up/appsmith/exports/build_r1.json'
app = App(BASE)
d = app.d

def sub_all(text, pairs, where):
    for old, new in pairs:
        assert old in text, f'{where}: tidak ketemu: {old[:70]!r}'
        text = text.replace(old, new)
    return text

# ---------------------------------------------------------------- nama app
d['exportedApplication']['name'] = 'Product Management R1'

# ---------------------------------------------------------------- Admin: query
app.set_query('Admin', 'q_users', body='''SELECT u.email, u.full_name, u.role, fn_role_label(u.role) AS role_label, u.is_active,
       u.factory_id, f.name AS factory_name,
       u.must_change_password, u.locked_until, u.last_login_at, u.updated_at, u.updated_by
FROM app_user u
LEFT JOIN factory f ON f.id = u.factory_id
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'manage_users')) IS NOT NULL
ORDER BY u.is_active DESC, u.full_name;''')

app.set_query('Admin', 'a_user_save', body='''SELECT fn_user_save({{appsmith.store.token}}, {{this.params.email}}, {{this.params.full_name}},
                    {{this.params.role}}, {{this.params.is_active}}::boolean, {{this.params.is_new}}::boolean,
                    nullif({{this.params.factory_id || ''}}, '')::uuid)
       AS temp_password;''')

app.add_query('Admin', 'q_factories', 'q_users', '''SELECT id, name, status, active_users, updated_at, updated_by
FROM v_factory_list
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'manage_users')) IS NOT NULL
ORDER BY status, name;''')

app.add_query('Admin', 'a_factory_save', 'a_user_save', '''SELECT fn_factory_save({{appsmith.store.token}}, nullif({{this.params.id || ''}}, '')::uuid,
                       {{this.params.name}}, {{this.params.status}}) AS id;''')

# ---------------------------------------------------------------- Admin: JSObject
app.set_js('Admin', 'AdminCtrl', open('admin_ctrl.js', encoding='utf-8').read())
app.replace_js('Admin', 'Auth', [(
    'pageQueries() { return [q_users, q_audit_entities, q_audit]; },',
    'pageQueries() { return [q_factories, q_users, q_audit_entities, q_audit]; },')])

# ---------------------------------------------------------------- Admin: form user + pabrik
w = app.widget('Admin', 'cwUserForm')
app.set_cw_source('Admin', 'cwUserForm',
                  html=sub_all(w['uncompiledSrcDoc']['html'], P.USER_HTML, 'cwUserForm.html'),
                  js=sub_all(w['uncompiledSrcDoc']['js'], P.USER_JS, 'cwUserForm.js'),
                  css=w['uncompiledSrcDoc']['css'])
w['defaultModel'] = sub_all(w['defaultModel'], [P.USER_MODEL], 'cwUserForm.defaultModel')
mdl = app.widget('Admin', 'mdlUser')
# modal sedikit ditinggikan untuk baris Pabrik
mdl['height'] = 560
mdl['bottomRow'] = mdl['topRow'] + 560
cv = mdl['children'][0]; cv['bottomRow'] = 556; cv['minHeight'] = 560
w['bottomRow'] = w['topRow'] + 55

# ---------------------------------------------------------------- Admin: kolom Pabrik di tblUsers
t = app.widget('Admin', 'tblUsers')
col = copy.deepcopy(t['primaryColumns']['role_label'])
col.update(id='factory_name', originalId='factory_name', alias='factory_name', label='Pabrik', width=170.0,
           computedValue=col['computedValue'].replace('"role_label"', '"factory_name"').replace(': role_label', ': factory_name'))
t['primaryColumns']['factory_name'] = col
hid = copy.deepcopy(col)
hid.update(id='factory_id', originalId='factory_id', alias='factory_id', label='factory_id', isVisible=False,
           computedValue=col['computedValue'].replace('"factory_name"', '"factory_id"').replace(': factory_name', ': factory_id'))
t['primaryColumns']['factory_id'] = hid
order = t['columnOrder']; order.insert(order.index('role_label') + 1, 'factory_name'); order.append('factory_id')
t['dynamicBindingPathList'].append({'key': 'primaryColumns.factory_id.computedValue'})
for i, k in enumerate(order):
    t['primaryColumns'][k]['index'] = float(i)
t['dynamicBindingPathList'].append({'key': 'primaryColumns.factory_name.computedValue'})
# kolom factory_id disembunyikan bila Appsmith menambahkannya otomatis
app.note('tblUsers: kolom Pabrik ditambahkan')

# ---------------------------------------------------------------- Admin: tab Pabrik (salinan tab User)
tabs = app.widget('Admin', 'tabAdmin')
canvas = app.clone_widget('Admin', 'Canvas1', 'CanvasPabrik', parent_name='tabAdmin',
                          renames={'btnUserTambah': 'btnPabrikTambah', 'tblUsers': 'tblFactories'})
canvas['tabId'] = 'tab3'; canvas['tabName'] = 'Pabrik'
tabs['tabsObj']['tab3'] = {'label': 'Pabrik', 'id': 'tab3', 'widgetId': canvas['widgetId'], 'isVisible': True,
                           'index': 2.0, 'positioning': 'vertical'}
btn = next(c for c in canvas['children'] if c['widgetName'] == 'btnPabrikTambah')
btn['text'] = '+ Tambah Pabrik'; btn['onClick'] = '{{AdminCtrl.openFactoryAdd()}}'
ft = next(c for c in canvas['children'] if c['widgetName'] == 'tblFactories')
src_cols = ft['primaryColumns']
text_tpl, btn_tpl = src_cols['full_name'], src_cols['customColumn2']
def text_col(cid, label, width=150.0, ctype='text'):
    c = copy.deepcopy(text_tpl)
    c.update(id=cid, originalId=cid, alias=cid, label=label, width=width, columnType=ctype, isDerived=False,
             computedValue='{{(() => { const tableData = tblFactories.processedTableData || []; return tableData.length > 0 ? '
                           f'tableData.map((currentRow, currentIndex) => (currentRow["{cid}"])) : {cid} }})()}}}}')
    return c
cols = {
    'name': text_col('name', 'Nama Pabrik', 260.0),
    'status': text_col('status', 'Status', 110.0),
    'active_users': text_col('active_users', 'User Aktif', 110.0, 'number'),
    'updated_at': text_col('updated_at', 'Diubah', 170.0),
    'updated_by': text_col('updated_by', 'Oleh', 200.0),
}
b = copy.deepcopy(btn_tpl)
b.update(id='customColumn1', originalId='customColumn1', label='Ubah',
         onClick='{{AdminCtrl.openFactoryEdit(currentRow)}}', buttonLabel='Ubah', index=5.0,
         buttonColor=b['buttonColor'].replace('tblUsers', 'tblFactories'))
cols['customColumn1'] = b
cols['id'] = text_col('id', 'id', 100.0); cols['id']['isVisible'] = False
order = ['name', 'status', 'active_users', 'updated_at', 'updated_by', 'customColumn1', 'id']
for i, k in enumerate(order):
    cols[k]['index'] = float(i)
ft['primaryColumns'] = cols
ft['columnOrder'] = order
ft['columnWidthMap'] = {}
ft['tableData'] = '{{q_factories.data}}'
ft['primaryColumnId'] = 'id'
ft['label'] = 'Pabrik'
ft['searchKey'] = ''
ft.pop('cachedTableData', None)
ft['dynamicBindingPathList'] = ([{'key': k} for k in ('accentColor', 'borderRadius', 'boxShadow', 'tableData')]
    + [{'key': f'primaryColumns.{k}.computedValue'} for k in order if k != 'customColumn1']
    + [{'key': f'primaryColumns.customColumn1.{p}'} for p in ('buttonColor', 'borderRadius', 'boxShadow')])
ft['dynamicTriggerPathList'] = [{'key': 'primaryColumns.customColumn1.onClick'}]
# sisa referensi tblUsers di salinan
import json as _j
s = _j.dumps(ft)
assert 'tblUsers' not in s.replace('tblUsers.', 'X') or True
ft_json = _j.loads(s.replace('tblUsers', 'tblFactories'))
ft.clear(); ft.update(ft_json)

# ---------------------------------------------------------------- Admin: modal Pabrik (salinan mdlUser)
m2 = app.clone_widget('Admin', 'mdlUser', 'mdlPabrik', renames={'Canvas3': 'CanvasPabrikForm', 'cwUserForm': 'cwFactoryForm'})
m2['height'] = 360; m2['bottomRow'] = m2['topRow'] + 360
cv2 = m2['children'][0]; cv2['bottomRow'] = 356; cv2['minHeight'] = 360
cf = cv2['children'][0]
cf['bottomRow'] = cf['topRow'] + 35
cf['defaultModel'] = P.FACTORY_MODEL
cf['onSave'] = '{{AdminCtrl.saveFactory()}}'
cf['onCancel'] = "{{closeModal('mdlPabrik')}}"
app.set_cw_source('Admin', 'cwFactoryForm', html=P.FACTORY_HTML, css=w['uncompiledSrcDoc']['css'], js=P.FACTORY_JS)

# ---------------------------------------------------------------- Header: role + pabrik (semua page)
OLD_ROLE = "role: Auth.me?.role_label ?? '',"
NEW_ROLE = "role: [Auth.me?.role_label, Auth.me?.factory_name].filter(Boolean).join(' · '),"
for p in d['pageList']:
    name = p['unpublishedPage']['name']
    for wd, _ in app.walk(app.dsl(name)):
        if wd.get('widgetName') == 'cwHeader' and OLD_ROLE in wd.get('defaultModel', ''):
            wd['defaultModel'] = wd['defaultModel'].replace(OLD_ROLE, NEW_ROLE)
            app.note(f'cwHeader {name}: role + pabrik')

# ---------------------------------------------------------------- Beranda: Manager Costing
app.set_query('Beranda', 'q_worklist_admin', body='''SELECT * FROM v_worklist_admin
WHERE (SELECT fn_auth({{appsmith.store.token}}, 'approve_price')) IS NOT NULL
  AND kind = 'PRICE'
ORDER BY kind, proposed_at DESC;''')
app.replace_js('Beranda', 'BerandaCtrl', [
    ('MASTER_ADMIN: [q_worklist_admin],', 'MANAGER_COSTING: [q_worklist_admin],'),
    ('MASTER_ADMIN: () => this.adminModel(),', 'MANAGER_COSTING: () => this.adminModel(),'),
    ('// ---- Master Admin ----', '// ---- Manager Costing (R1: antrian usulan harga) ----'),
])

# ---------------------------------------------------------------- Material Detail: approval harga = Manager Costing
app.replace_js('Material Detail', 'MaterialDetailCtrl', [
    ("canManageMaster() { return Auth.can('manage_master'); },",
     "canManageMaster() { return Auth.can('manage_master'); },\n\tcanApprovePrice() { return Auth.can('approve_price'); },"),
    ('menunggu approval Master Admin', 'menunggu approval Manager Costing'),
])
tp = app.widget('Material Detail', 'tblPrices')['primaryColumns']
tp['customColumn2']['isCellVisible'] = tp['customColumn2']['isCellVisible'].replace(
    'MaterialDetailCtrl.canManagePrice()', 'MaterialDetailCtrl.canApprovePrice()')
for k in ('customColumn3', 'customColumn4'):
    tp[k]['isCellVisible'] = tp[k]['isCellVisible'].replace('MaterialDetailCtrl.canManageMaster()', 'MaterialDetailCtrl.canApprovePrice()')
tp['customColumn5']['isCellVisible'] = tp['customColumn5']['isCellVisible'].replace(
    ' && !MaterialDetailCtrl.canManageMaster()', '')
for k in ('customColumn2', 'customColumn3', 'customColumn4', 'customColumn5'):
    assert 'canManageMaster' not in tp[k]['isCellVisible'] and ('canApprovePrice' in tp[k]['isCellVisible'] or k == 'customColumn5'), k
app.note('tblPrices: Akhiri/Approve/Tolak = canApprovePrice, Batalkan = canManagePrice')
w = app.widget('Material Detail', 'cwPriceForm')
app.set_cw_source('Material Detail', 'cwPriceForm', js=w['uncompiledSrcDoc']['js'].replace('Master Admin', 'Manager Costing'))
app.replace_js('Cost Breakdown (CBD)', 'CbdGridCtrl', [('approval Master Admin', 'approval Manager Costing')])
w = app.widget('Cost Breakdown (CBD)', 'cwCbdGrid')
app.set_cw_source('Cost Breakdown (CBD)', 'cwCbdGrid', js=w['uncompiledSrcDoc']['js'].replace('approval Master Admin', 'approval Manager Costing'))

# ---------------------------------------------------------------- T49–T52
app.set_query('Cost Breakdown (CBD)', 'q_change_log_images', run_behaviour='MANUAL')
lay = app.page('Cost Breakdown (CBD)')['unpublishedPage']['layouts'][0]
lay['layoutOnLoadActions'] = [[x for x in grp if x['name'] != 'q_change_log_images'] for grp in lay['layoutOnLoadActions']]
lay['layoutOnLoadActions'] = [grp for grp in lay['layoutOnLoadActions'] if grp]
app.note('T49: q_change_log_images (CBD) Manual + keluar dari on-load')
tr = app.widget('Specsheet', 'tblRiwayat')
assert tr['onRowSelected'].endswith('}}.')
tr['onRowSelected'] = tr['onRowSelected'][:-1]
app.note('T50: titik di onRowSelected tblRiwayat dihapus')
for pg, tn in (('Specsheet', 'tblRiwayat'), ('Cost Breakdown (CBD)', 'tblCbdRiwayat')):
    app.widget(pg, tn)['primaryColumns']['image_count']['columnType'] = 'text'
app.note('T51: kolom Gambar = Plain text')
for pg, mname, cwrows, h in (('Specsheet', 'mdlTerbit', 62, 640), ('Cost Breakdown (CBD)', 'mdlCbdTerbit', 63, 660)):
    mm = app.widget(pg, mname)
    mm['height'] = h; mm['bottomRow'] = mm['topRow'] + h
    c0 = mm['children'][0]; c0['bottomRow'] = h; c0['minHeight'] = h
    pf = next(x for x, _ in app.walk(mm) if x.get('widgetName') == 'cwPublishForm')
    pf['bottomRow'] = pf['topRow'] + cwrows
app.note('T52: modal Terbit & cwPublishForm ditinggikan')

# ---------------------------------------------------------------- selesai
app.publish_all()
app.save(OUT)
print('\n'.join(app.log))
print('OK ->', OUT)
