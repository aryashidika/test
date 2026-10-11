# Helper bersama build R4+ (salinan helper build_r2/build_r3 + salin widget antar-page).
import copy, json

ROOT = r'D:/OJT_PM/Mock Up/appsmith'
TOKEN = '{{appsmith.store.token}}'


def rd(path):
    return open(f'{ROOT}/{path}', encoding='utf-8').read()


def wr(path, text):
    with open(f'{ROOT}/{path}', 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)


def sub1(text, old, new, where=''):
    assert text.count(old) == 1, f'{where}: harus tepat 1x: {old[:70]!r} ({text.count(old)}x)'
    return text.replace(old, new)


def add_event(w, event, handler):
    if event not in w['events']:
        w['events'].append(event)
    w[event] = handler
    for lk in ('dynamicTriggerPathList', 'dynamicPropertyPathList'):
        lst = w.setdefault(lk, [])
        if not any(x['key'] == event for x in lst):
            lst.append({'key': event})


def set_binding(w, key, value):
    w[key] = value
    lst = w.setdefault('dynamicBindingPathList', [])
    if '{{' in str(value) and not any(x['key'] == key for x in lst):
        lst.append({'key': key})


def resize_modal(app, page, modal, height, cw_rows, left=None, right=None):
    m = app.widget(page, modal)
    m['height'] = height
    m['bottomRow'] = m['topRow'] + height
    m['canOutsideClickClose'] = False
    m['dynamicHeight'] = 'FIXED'
    if left is not None:
        m.update(leftColumn=float(left), rightColumn=float(right), mobileLeftColumn=float(left), mobileRightColumn=float(right))
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


def text_col_from(tpl, table, cid, label, width=150.0, visible=True):
    c = copy.deepcopy(tpl)
    for k in ('textColor', 'cellBackground', 'fontStyle'):
        c.pop(k, None)
    c.update(id=cid, originalId=cid, alias=cid, label=label, width=width, columnType='text', isVisible=visible,
             isDerived=False, isCellVisible=True, computedValue=col_cv(table, cid), horizontalAlignment='LEFT')
    return c


def table_set_columns(t, order):
    """Tulis ulang columnOrder/index + dynamicBindingPathList kolom (kolom sudah ada di primaryColumns)."""
    pc = t['primaryColumns']
    assert set(order) == set(pc), sorted(set(order) ^ set(pc))
    t['columnOrder'] = order
    for i, k in enumerate(order):
        pc[k]['index'] = float(i)
    keep = [x for x in t['dynamicBindingPathList'] if not x['key'].startswith('primaryColumns.')]
    trig = [x for x in t.get('dynamicTriggerPathList', []) if not x['key'].startswith('primaryColumns.')]
    for k in order:
        for p, v in pc[k].items():
            if isinstance(v, str) and '{{' in v:
                (trig if p == 'onClick' else keep).append({'key': f'primaryColumns.{k}.{p}'})
    t['dynamicBindingPathList'] = keep
    t['dynamicTriggerPathList'] = trig
    t['columnWidthMap'] = {k: v for k, v in (t.get('columnWidthMap') or {}).items() if k in pc}


def copy_widget_to_page(app, src_page, src_name, dst_page, renames):
    """Salin widget (mis. modal) beserta anaknya dari page lain ke kanvas utama dst_page.
    renames: {namaLama: namaBaru} — semua nama hasil salinan harus unik di dst_page."""
    src = app.widget(src_page, src_name)
    w = copy.deepcopy(src)
    main = app.dsl(dst_page)
    existing = {x.get('widgetName') for x, _ in app.walk(main)}

    def fix(node, parent_id):
        node['widgetId'] = app.new_wid()
        node['key'] = app.new_wid()
        node['parentId'] = parent_id
        node['widgetName'] = renames.get(node['widgetName'], node['widgetName'])
        assert node['widgetName'] not in existing, f'{dst_page}: nama {node["widgetName"]} sudah ada'
        existing.add(node['widgetName'])
        for ch in node.get('children', []) or []:
            fix(ch, node['widgetId'])
    fix(w, main['widgetId'])
    main['children'].append(w)
    app.note(f'widget {dst_page}/{w["widgetName"]} disalin dari {src_page}/{src_name}')
    return w


def lock_manual_queries(app):
    for a in app.d['actionList']:
        u = a['unpublishedAction']
        if a.get('pluginType') == 'DB' and u['runBehaviour'] == 'MANUAL':
            u['userSetOnLoad'] = True
