# Build R3: salin export_r2.json -> edit di tempat -> exports/build_r3.json
# Harga Varian × Supplier: tab Harga di Material Detail (ajukan banyak varian, salin harga), page baru
# Persetujuan Harga (Manager Costing), Beranda Manager Costing per pengajuan.
import copy, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App

ROOT = r'D:/OJT_PM/Mock Up/appsmith'
BASE = f'{ROOT}/exports/export_r2.json'
OUT = f'{ROOT}/exports/build_r3.json'
app = App(BASE)
d = app.d
TOKEN = '{{appsmith.store.token}}'


def rd(path):
    return open(f'{ROOT}/{path}', encoding='utf-8').read()


def wr(path, text):
    with open(f'{ROOT}/{path}', 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


def add_event(w, event, handler):
    if event not in w['events']:
        w['events'].append(event)
    w[event] = handler
    for lk in ('dynamicTriggerPathList', 'dynamicPropertyPathList'):
        lst = w.setdefault(lk, [])
        if not any(x['key'] == event for x in lst):
            lst.append({'key': event})


def drop_event(w, event):
    w['events'] = [e for e in w['events'] if e != event]
    w.pop(event, None)
    for lk in ('dynamicTriggerPathList', 'dynamicPropertyPathList'):
        w[lk] = [x for x in w.get(lk, []) if x['key'] != event]


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
    fallback = expr if expr else cid
    return ('{{(() => { const tableData = ' + table + '.processedTableData || []; return tableData.length > 0 ? '
            f'tableData.map((currentRow, currentIndex) => ({e})) : {fallback} }})()}}}}')


def cell_flag(table, expr):
    return ('{{(() => { const tableData = ' + table + '.processedTableData || []; return tableData.length > 0 ? '
            f'tableData.map((currentRow, currentIndex) => ({expr})) : {expr} }})()}}}}')


def rebuild_columns(t, cols, order):
    """Ganti seluruh kolom tabel; dynamicBindingPathList disusun ulang dari isi kolom."""
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


def text_col(tpl, table, cid, label, width=150.0, expr=None, visible=True):
    c = copy.deepcopy(tpl)
    for k in ('textColor', 'cellBackground', 'fontStyle'):
        c.pop(k, None)
    c.update(label=label, width=width, columnType='text', isVisible=visible, isDerived=False,
             isCellVisible=True, computedValue=col_cv(table, cid, expr), horizontalAlignment='LEFT')
    return c


def button_col(tpl, label, on_click, table, visible_expr, color=None):
    c = copy.deepcopy(tpl)
    c.update(label='-', buttonLabel=label, onClick=on_click, isDerived=True,
             isCellVisible=cell_flag(table, visible_expr), computedValue='')
    if color:
        c['buttonColor'] = color
    return c


d['exportedApplication']['name'] = 'Product Management R3'

# ================================================================ Material Detail: query harga
PG = 'Material Detail'
MID = "{{appsmith.URL.queryParams.id || ''}}"
app.set_query(PG, 'q_prices', body=f'''SELECT p.row_key, p.id, p.variant_id, p.code, p.color, p.thickness_label, p.link_id, p.supplier_name,
       p.price, p.currency, p.valid_from, p.valid_to, p.reference, p.status, p.state, p.reject_reason,
       p.created_by, p.created_at, p.decided_by, p.decided_at
FROM (SELECT fn_auth({TOKEN}, 'view_price') AS me) a
JOIN v_material_price p ON p.material_id::text = {MID} AND fn_can_see_factory(a.me, p.factory_id)
ORDER BY p.code, p.supplier_name, p.state_order, p.valid_from DESC NULLS LAST, p.created_at DESC NULLS LAST;''',
              run_behaviour='MANUAL')
app.add_query(PG, 'a_price_propose', 'a_price_add', f'''SELECT fn_price_propose({TOKEN}, {{{{this.params.link_id}}}}::uuid, {{{{this.params.variant_ids}}}}::jsonb,
                        {{{{this.params.price}}}}::numeric, {{{{this.params.currency}}}},
                        {{{{this.params.valid_from}}}}::date, {{{{this.params.reference || ''}}}}) AS batch_id;''')
app.add_query(PG, 'a_price_copy', 'a_price_add', f'''SELECT batch_id, created, skipped
FROM fn_price_copy({TOKEN}, {{{{this.params.source_id}}}}::uuid, {{{{this.params.variant_ids}}}}::jsonb,
                   {{{{this.params.valid_from}}}}::date, {{{{this.params.reference || ''}}}});''')
app.add_query(PG, 'a_price_decide', 'a_price_approve', f'''SELECT fn_price_decide({TOKEN}, {{{{this.params.ids}}}}::jsonb, {{{{this.params.decision}}}},
                       {{{{this.params.reason || ''}}}}) AS n;''')
for q in ('a_price_add', 'a_price_approve', 'a_price_reject'):
    app.delete_query(PG, q)
app.set_js(PG, 'MaterialDetailCtrl', rd('js/MaterialDetailCtrl.js'))

# ================================================================ Material Detail: tab Harga (isi cntHarga dipindah)
tab = app.widget(PG, 'tabMaterial')
cv_src = app.widget(PG, 'CanvasTabSupplier')
cv = copy.deepcopy({k: v for k, v in cv_src.items() if k != 'children'})
cv.update(widgetName='CanvasTabHarga', widgetId=app.new_wid(), key=app.new_wid(), parentId=tab['widgetId'],
          tabId='tab3', tabName='Harga', children=[])
tab['children'].append(cv)
tab['tabsObj']['tab3'] = {'label': 'Harga', 'id': 'tab3', 'widgetId': cv['widgetId'],
                          'isVisible': '{{MaterialDetailCtrl.canViewPrice()}}', 'index': 2.0, 'positioning': 'vertical'}
tab['dynamicBindingPathList'].append({'key': 'tabsObj.tab3.isVisible'})
POS = {  # (top, bottom, left, right) dalam canvas tab (tinggi 52 baris)
    'txtHargaInfo': (0.0, 4.0, 0.0, 32.0),
    'btnHargaSalin': (0.0, 4.0, 33.0, 47.0),
    'btnHargaTambah': (0.0, 4.0, 48.0, 64.0),
    'swHargaRiwayat': (5.0, 9.0, 0.0, 14.0),
    'tblPrices': (10.0, 50.0, 0.0, 64.0),
}
for name in ('txtHargaInfo', 'swHargaRiwayat', 'btnHargaTambah', 'tblPrices'):
    w, parent = app.widget(PG, name, with_parent=True)
    parent['children'].remove(w)
    w['parentId'] = cv['widgetId']
    cv['children'].append(w)
h, h_parent = app.widget(PG, 'cntHarga', with_parent=True)
assert all(c['widgetName'] == 'Canvas2' and not c.get('children') for c in h['children']), 'cntHarga masih berisi widget'
h_parent['children'].remove(h)
bs = app.clone_widget(PG, 'btnHargaTambah', 'btnHargaSalin')
bs.update(text='Salin Harga', onClick='{{MaterialDetailCtrl.openCopyPrice()}}', isVisible='{{MaterialDetailCtrl.canCopyPrice()}}')
bt = app.widget(PG, 'btnHargaTambah')
bt.update(text='+ Ajukan Harga', onClick='{{MaterialDetailCtrl.openProposePrice()}}', buttonVariant='PRIMARY',
          isVisible='{{MaterialDetailCtrl.canAddPrice()}}')
for name, (top, bottom, left, right) in POS.items():
    w = app.widget(PG, name)
    w.update(topRow=top, bottomRow=bottom, leftColumn=left, rightColumn=right,
             mobileTopRow=top, mobileBottomRow=bottom, mobileLeftColumn=left, mobileRightColumn=right)
app.widget(PG, 'swHargaRiwayat')['label'] = 'Tampilkan riwayat'
app.note('Material Detail: tab Harga (tab3, terlihat bila view_price), isi cntHarga dipindah, cntHarga dihapus, btnHargaSalin baru')

# -- tblPrices: satu baris per harga / pasangan varian × supplier
T = 'tblPrices'
t = app.widget(PG, T)
src = t['primaryColumns']
tpl_text, tpl_btn = src['reference'], src['customColumn1']
cols = {
    'code': text_col(tpl_text, T, 'code', 'Material Code', 130.0),
    'color': text_col(tpl_text, T, 'color', 'Warna', 110.0),
    'thickness_label': text_col(tpl_text, T, 'thickness_label', 'Thickness', 100.0),
    'supplier_name': text_col(tpl_text, T, 'supplier_name', 'Supplier', 160.0),
    'price': copy.deepcopy(src['price']),
    'currency': copy.deepcopy(src['currency']),
    'valid_from': copy.deepcopy(src['valid_from']),
    'valid_to': copy.deepcopy(src['valid_to']),
    'state': copy.deepcopy(src['state']),
    'reference': copy.deepcopy(src['reference']),
    'created_by': copy.deepcopy(src['created_by']),
    'decided_by': copy.deepcopy(src['decided_by']),
    'customColumn1': button_col(tpl_btn, 'Ajukan', '{{MaterialDetailCtrl.openProposePrice(currentRow)}}', T,
                                'MaterialDetailCtrl.canProposeRow(currentRow)'),
    'customColumn3': button_col(src['customColumn3'], 'Setujui', '{{MaterialDetailCtrl.approvePrice(currentRow)}}', T,
                                'MaterialDetailCtrl.canDecideRow(currentRow)'),
    'customColumn4': button_col(src['customColumn4'], 'Tolak', '{{MaterialDetailCtrl.openReject(currentRow)}}', T,
                                'MaterialDetailCtrl.canDecideRow(currentRow)'),
    'customColumn5': button_col(src['customColumn5'], 'Batalkan', '{{MaterialDetailCtrl.cancelPrice(currentRow)}}', T,
                                'MaterialDetailCtrl.canCancelRow(currentRow)'),
    'customColumn2': button_col(src['customColumn2'], 'Akhiri', '{{MaterialDetailCtrl.endPrice(currentRow)}}', T,
                                'MaterialDetailCtrl.canEndRow(currentRow)'),
}
cols['created_by']['label'] = 'Diajukan oleh'
cols['decided_by']['label'] = 'Diproses oleh'
for hid in ('row_key', 'id', 'variant_id', 'link_id', 'status', 'reject_reason', 'created_at', 'decided_at'):
    cols[hid] = text_col(tpl_text, T, hid, hid, 100.0, visible=False)
rebuild_columns(t, cols, list(cols))
t['tableData'] = '{{MaterialDetailCtrl.pricesShown()}}'
t['label'] = 'Harga'
t['primaryColumnId'] = 'row_key'
t['searchKey'] = ''
t.pop('onRowSelected', None)
t['dynamicTriggerPathList'] = [x for x in t['dynamicTriggerPathList'] if x['key'] != 'onRowSelected']
app.note('tblPrices: kolom varian × supplier, tombol Ajukan/Setujui/Tolak/Batalkan/Akhiri per baris, primary key row_key')

# -- form harga & modal
w = app.widget(PG, 'cwPriceForm')
css = w['uncompiledSrcDoc']['css'] + rd('widgets/cwPriceForm/extra.css')
app.set_cw_source(PG, 'cwPriceForm', html=rd('widgets/cwPriceForm/index.html'), js=rd('widgets/cwPriceForm/script.js'), css=css)
resize_modal(PG, 'mdlHarga', 760, 74)
m = app.widget(PG, 'mdlHarga')
m.update(leftColumn=14.0, rightColumn=50.0, mobileLeftColumn=14.0, mobileRightColumn=50.0,
         canOutsideClickClose=False, dynamicHeight='FIXED')
app.note('cwPriceForm: mode Ajukan (centang banyak varian) / Salin harga; mdlHarga 760 px, lebih lebar, klik luar tidak menutup')

# ================================================================ Beranda: Manager Costing per pengajuan + menu
PG = 'Beranda'
app.set_query(PG, 'q_worklist_admin', body=f'''SELECT w.*
FROM (SELECT fn_auth({TOKEN}, 'approve_price') AS me) a
JOIN v_worklist_admin w ON fn_can_see_factory(a.me, w.factory_id)
ORDER BY w.proposed_at DESC;''')
app.replace_js(PG, 'BerandaCtrl', [
    ("""	// ---- Manager Costing (R1: antrian usulan harga) ----
	adminItem(r) {
		const nav = this.toMaterial(r);""",
     """	// ---- Manager Costing (R3: satu baris per pengajuan harga -> page Persetujuan Harga) ----
	adminItem(r) {
		const nav = { target: 'Persetujuan Harga', params: { batch: r.ref_id } };"""),
    ("""				{ key: 'appr-prices', value: of('PRICE').length, label: 'Harga usulan', tone: 'warn' },""",
     """				{ key: 'appr-prices', value: of('PRICE').length, label: 'Pengajuan harga', tone: 'warn' },"""),
    ("""				section('appr-prices', 'PRICE', 'Harga Menunggu Approval', 'Tidak ada usulan harga.',
					'Usulan Vendor CBD. Harga lama tetap berlaku sampai usulan disetujui.'),""",
     """				section('appr-prices', 'PRICE', 'Pengajuan Harga Menunggu Persetujuan', 'Tidak ada usulan harga.',
					'Usulan Vendor CBD (per pengajuan). Harga lama tetap berlaku sampai usulan disetujui.'),"""),
])
menu = app.widget(PG, 'cwMenu')
old_admin = """    {
      key: 'admin',"""
assert menu['defaultModel'].count(old_admin) == 1
menu['defaultModel'] = menu['defaultModel'].replace(old_admin, """    {
      key: 'approval',
      title: 'Persetujuan Harga',
      desc: 'Setujui atau tolak usulan harga material dari tim CBD.',
      target: 'Persetujuan Harga',
      icon: 'list',
      show: Auth.can('approve_price')
    },
""" + old_admin)
app.note('Beranda: q_worklist_admin per pengajuan + filter pabrik; BerandaCtrl -> Persetujuan Harga; menu Persetujuan Harga')

# ================================================================ page baru: Persetujuan Harga (salinan Beranda)
SRC_PG, NEW_PG = 'Beranda', 'Persetujuan Harga'
new_page = copy.deepcopy(app.page(SRC_PG))
new_page['gitSyncId'] = app.new_git()
up = new_page['unpublishedPage']
up['name'] = NEW_PG
up['slug'] = 'persetujuan-harga'
up['isHidden'] = False
lay = up['layouts'][0]
lay['id'] = NEW_PG
lay['layoutOnLoadActions'] = json.loads(json.dumps(lay['layoutOnLoadActions']).replace(f'"{SRC_PG}_', f'"{NEW_PG}_'))
WREN = {'cwWorklist': 'cwPriceApproval'}


def regen(node, parent_id):
    if node['widgetId'] != '0':
        node['widgetId'] = app.new_wid()
        node['parentId'] = parent_id
    node['key'] = app.new_wid()
    node['widgetName'] = WREN.get(node['widgetName'], node['widgetName'])
    for ch in node.get('children', []) or []:
        regen(ch, node['widgetId'])


regen(lay['dsl'], None)
lay['dsl']['children'] = [c for c in lay['dsl']['children'] if c['widgetName'] != 'cwMenu']
pos = next(i for i, p in enumerate(d['pageList']) if p['unpublishedPage']['name'] == 'Master Pilihan') + 1
d['pageList'].insert(pos, new_page)
pages = d['exportedApplication']['pages']
pos2 = next(i for i, p in enumerate(pages) if p['id'] == 'Master Pilihan') + 1
pages.insert(pos2, {'id': NEW_PG, 'isDefault': False})


def clone_action(a, new_name=None):
    a2 = json.loads(json.dumps(a).replace(f'"{SRC_PG}_', f'"{NEW_PG}_').replace(f'"pageId": "{SRC_PG}"', f'"pageId": "{NEW_PG}"'))
    a2['gitSyncId'] = app.new_git()
    for k in ('unpublishedAction', 'publishedAction'):
        if k in a2 and a2[k]:
            a2[k]['pageId'] = NEW_PG
    if new_name:
        a2['unpublishedAction']['name'] = new_name
        a2['id'] = f'{NEW_PG}_{new_name}'
    return a2


for a in [x for x in d['actionList'] if x['unpublishedAction']['pageId'] == SRC_PG]:
    u = a['unpublishedAction']
    cid = u.get('collectionId') or ''
    if cid.endswith('_BerandaCtrl'):
        continue                                       # diganti ApprovalCtrl
    if not cid and u['name'] not in ('q_me', 'q_worklist_admin'):
        continue
    d['actionList'].append(clone_action(a, {'q_worklist_admin': 'q_price_pending'}.get(u['name']) if not cid else None))
    if not cid and u['name'] == 'q_worklist_admin':
        d['actionList'].append(clone_action(a, 'a_price_decide'))
for c in [x for x in d['actionCollectionList'] if x['unpublishedCollection']['pageId'] == SRC_PG]:
    nm = c['unpublishedCollection']['name']
    c2 = json.loads(json.dumps(c).replace(f'"{SRC_PG}_', f'"{NEW_PG}_'))
    c2['gitSyncId'] = app.new_git()
    for k in ('unpublishedCollection', 'publishedCollection'):
        if k in c2 and c2[k]:
            c2[k]['pageId'] = NEW_PG
    if nm == 'BerandaCtrl':
        c2['unpublishedCollection']['name'] = 'ApprovalCtrl'
        c2['id'] = f'{NEW_PG}_ApprovalCtrl'
        tpl = next(x for x in d['actionList'] if x['unpublishedAction'].get('collectionId') == f'{SRC_PG}_BerandaCtrl')
        e = clone_action(tpl)
        e['unpublishedAction']['collectionId'] = c2['id']
        e['unpublishedAction']['name'] = 'load'
        e['unpublishedAction']['fullyQualifiedName'] = 'ApprovalCtrl.load'
        e['id'] = f'{NEW_PG}_ApprovalCtrl.load'
        d['actionList'].append(e)
    d['actionCollectionList'].append(c2)
app.note(f'page baru {NEW_PG} (salinan {SRC_PG}, tanpa cwMenu)')

PG = NEW_PG
app.set_query(PG, 'q_price_pending', body=f'''SELECT p.id, p.batch_id, p.material_id, p.material_name, p.uom, p.code, p.color, p.thickness_label,
       p.supplier_name, p.price, p.currency, p.valid_from, p.reference, p.created_by, p.created_at,
       p.cur_price, p.cur_currency, p.cur_valid_from, p.problem
FROM (SELECT fn_auth({TOKEN}, 'approve_price') AS me) a
JOIN v_price_pending p ON fn_can_see_factory(a.me, p.factory_id)
ORDER BY p.created_at, p.batch_id, p.code, p.supplier_name;''', run_behaviour='MANUAL')
app.set_query(PG, 'a_price_decide', body=f'''SELECT fn_price_decide({TOKEN}, {{{{this.params.ids}}}}::jsonb, {{{{this.params.decision}}}},
                       {{{{this.params.reason || ''}}}}) AS n;''', run_behaviour='MANUAL')
app.set_js(PG, 'ApprovalCtrl', rd('js/ApprovalCtrl.js'))
app.replace_js(PG, 'Auth', [
    ("""	requiredPerm: '',""", """	requiredPerm: 'approve_price',"""),
    ("""		return [{ run: () => BerandaCtrl.load() }];""", """		return [{ run: () => ApprovalCtrl.load() }];"""),
])
hdr = app.widget(PG, 'cwHeader')
assert hdr['defaultModel'].count("pageTitle: 'Beranda'") == 1 and hdr['defaultModel'].count('showHome: false') == 1
hdr['defaultModel'] = hdr['defaultModel'].replace("pageTitle: 'Beranda'", "pageTitle: 'Persetujuan Harga'").replace('showHome: false', 'showHome: true')
w = app.widget(PG, 'cwPriceApproval')
w['defaultModel'] = '{{ApprovalCtrl.model()}}'
drop_event(w, 'onOpen')
add_event(w, 'onDecide', '{{ApprovalCtrl.decide()}}')
add_event(w, 'onOpenMaterial', '{{ApprovalCtrl.openMaterial()}}')
add_event(w, 'onRefresh', '{{ApprovalCtrl.reload()}}')
w.update(topRow=9.0, bottomRow=95.0, mobileTopRow=9.0, mobileBottomRow=95.0)
app.set_cw_source(PG, 'cwPriceApproval', html=rd('widgets/cwPriceApproval/index.html'),
                  css=rd('widgets/cwPriceApproval/style.css'), js=rd('widgets/cwPriceApproval/script.js'))
app.note('Persetujuan Harga: cwPriceApproval (onDecide/onOpenMaterial/onRefresh), Auth approve_price, q_price_pending, a_price_decide')

# ================================================================ simpan sumber ke repo (kondisi final)
wr('widgets/cwPriceForm/style.css', app.widget('Material Detail', 'cwPriceForm')['uncompiledSrcDoc']['css'])
wr('js/BerandaCtrl.js', app.js_body('Beranda', 'BerandaCtrl'))

# ================================================================ semua query DB Manual dikunci (userSetOnLoad)
for a in d['actionList']:
    u = a['unpublishedAction']
    if a.get('pluginType') == 'DB' and u['runBehaviour'] == 'MANUAL':
        u['userSetOnLoad'] = True

app.publish_all()
app.save(OUT)
print('\n'.join(app.log))
print('OK ->', OUT)
