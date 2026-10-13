# Validasi build JSON Appsmith: python validate.py <base.json> <build.json>
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aslib import App, check_js, sanitize
import esprima

base, build = App(sys.argv[1]), App(sys.argv[2])
errors, warns = [], []
def err(m): errors.append(m)

d = build.d
pages = [p['unpublishedPage']['name'] for p in d['pageList']]

# ---- 1. widget: nama & id unik, path binding ada
all_ids = {}
for pg in pages:
    names = {}
    for w, parent in build.walk(build.dsl(pg)):
        n = w.get('widgetName')
        if n in names: err(f'{pg}: nama widget ganda {n}')
        names[n] = w
        wid = w.get('widgetId')
        if wid in all_ids and wid != '0': err(f'{pg}: widgetId ganda {wid} ({n} & {all_ids[wid]})')
        all_ids[wid] = n
        if parent is not None and w.get('parentId') != parent.get('widgetId'):
            err(f'{pg}: parentId {n} tidak cocok dengan induk {parent.get("widgetName")}')
        for lk in ('dynamicBindingPathList', 'dynamicTriggerPathList'):
            for x in w.get(lk, []) or []:
                cur = w
                for part in x['key'].split('.'):
                    if isinstance(cur, dict) and part in cur: cur = cur[part]
                    else: err(f'{pg}/{n}: {lk} {x["key"]} tidak ada'); break
        if w.get('type') == 'TABLE_WIDGET_V2':
            pc = w.get('primaryColumns', {})
            for ck, cv in pc.items():
                if cv.get('id') != ck or cv.get('originalId') != ck:
                    err(f'{pg}/{n}: kolom {ck} punya id {cv.get("id")}/{cv.get("originalId")} (tidak akan tampil)')
                if cv.get('columnType') == 'button' and not cv.get('onClick'):
                    err(f'{pg}/{n}: tombol {ck} tanpa onClick')
            for ck in w.get('columnOrder', []):
                if ck not in pc: err(f'{pg}/{n}: columnOrder {ck} tidak ada di primaryColumns')
            for ck in pc:
                if ck not in w.get('columnOrder', []): err(f'{pg}/{n}: kolom {ck} tidak ada di columnOrder')
        if w.get('type') == 'TABS_WIDGET':
            kids = {c['widgetId'] for c in w.get('children', [])}
            for t in w['tabsObj'].values():
                if t['widgetId'] not in kids: err(f'{pg}/{n}: tab {t["label"]} tanpa canvas')
    build.__dict__.setdefault('names', {})[pg] = names

# ---- 2. JSObject: diawali export default, sintaks, fungsi
coll_members = {}
for c in d['actionCollectionList']:
    u = c['unpublishedCollection']; pg, nm, body = u['pageId'], u['name'], u['body']
    if not body.startswith('export default'): err(f'{pg}/{nm}: body tidak diawali export default')
    try:
        tree = esprima.parseModule(sanitize(body))
        props = tree.body[0].declaration.properties
        coll_members[(pg, nm)] = {(p.key.name if p.key.type == 'Identifier' else p.key.value) for p in props}
    except Exception as e:
        err(f'{pg}/{nm}: sintaks JS {e}')
    entries = [a['unpublishedAction']['name'] for a in d['actionList'] if a['unpublishedAction'].get('collectionId') == c['id']]
    base_had = any(a['unpublishedAction'].get('collectionId') == c['id'] for a in base.d['actionList'])
    if base_had:
        fnames = {p.key.name for p in props if p.value.type in ('FunctionExpression', 'ArrowFunctionExpression')}
        if set(entries) != fnames: err(f'{pg}/{nm}: entri fungsi {sorted(set(entries) ^ fnames)} tidak cocok')

# ---- 3. query
queries = {}
for a in d['actionList']:
    u = a['unpublishedAction']
    if u.get('collectionId'): continue
    queries.setdefault(u['pageId'], {})[u['name']] = u
    if u['name'].lower().startswith('query'): err(f'{u["pageId"]}: ada query uji {u["name"]}')
    if (a.get('pluginType') or u.get('pluginType')) == 'DB':
        tpl = u['actionConfiguration'].get('pluginSpecifiedTemplates') or [{}]
        if tpl[0].get('value') is not True: err(f'{u["pageId"]}/{u["name"]}: prepared statement OFF')
        if u['runBehaviour'] != 'MANUAL': err(f'{u["pageId"]}/{u["name"]}: bukan Manual ({u["runBehaviour"]})')
        elif not u.get('userSetOnLoad'): warns.append(f'{u["pageId"]}/{u["name"]}: Manual tetapi userSetOnLoad=false (bisa jadi Automatic saat import)')
        body = u['actionConfiguration']['body']
        if 'fn_auth' not in body and not re.search(r'fn_\w+\(', body): warns.append(f'{u["pageId"]}/{u["name"]}: tanpa fn_auth')

# ---- 4. referensi nama di JS & widget per page (query, JSObject.member, widget)
GLOBAL_OK = {'appsmith', 'Math', 'JSON', 'moment', 'Object', 'Array', 'String', 'Number', 'Promise', 'console', 'Date', 'window', 'document', 'Boolean', '_', 'e', 'this', 'currentRow', 'currentIndex', 'row', 'tableData'}
def refs_in(text, pg, where):
    qs = queries.get(pg, {})
    for m in re.finditer(r'\b((?:q|a|z)_\w+)\b', text):
        if m.group(1) not in qs:
            err(f'{pg} {where}: query {m.group(1)} tidak ada')
    for m in re.finditer(r'\b([A-Z]\w*(?:Ctrl|Auth|Util|XlsxWriter))\.(\w+)', text):
        key = (pg, m.group(1))
        if key not in coll_members: err(f'{pg} {where}: JSObject {m.group(1)} tidak ada')
        elif m.group(2) not in coll_members[key] and m.group(2) not in ('data',):
            err(f'{pg} {where}: {m.group(1)}.{m.group(2)} tidak ada')
    for m in re.finditer(r"(?:showModal|closeModal)\('(\w+)'\)", text):
        if m.group(1) not in build.names[pg]: err(f'{pg} {where}: modal {m.group(1)} tidak ada')
    for m in re.finditer(r'\b((?:cw|tbl|sel|inp|btn|sw|txt|mdl|tab|fp|dp|chk|ms|lst)[A-Z]\w*)\.(model|selectedRow|text|selectedOptionValue|isSwitchedOn|processedTableData|triggeredRow|selectedRows|isChecked|files)', text):
        if m.group(1) not in build.names[pg]: err(f'{pg} {where}: widget {m.group(1)} tidak ada')
for c in d['actionCollectionList']:
    u = c['unpublishedCollection']
    refs_in(re.sub(r'(?m)^\s*//.*$', '', u['body']), u['pageId'], u['name'])   # komentar baris penuh tidak dicek
def walk_str(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k in ('children', 'srcDoc', 'uncompiledSrcDoc'): continue
            yield from walk_str(v)
    elif isinstance(o, list):
        for v in o: yield from walk_str(v)
    elif isinstance(o, str) and '{{' in o:
        yield o
for pg in pages:
    for n, w in build.names[pg].items():
        for s in walk_str(w):
            refs_in(s, pg, n)

# ---- 5. params query vs pemanggil (query yang berubah/baru)
changed_q = set()
for a in d['actionList']:
    u = a['unpublishedAction']
    if u.get('collectionId'): continue
    try: b = base.action(u['pageId'], u['name'])['unpublishedAction']['actionConfiguration']['body']
    except KeyError: b = None
    if b != u['actionConfiguration']['body']: changed_q.add((u['pageId'], u['name']))
for pg, qn in sorted(changed_q):
    needed = set(re.findall(r'this\.params\.(\w+)', queries[pg][qn]['actionConfiguration']['body']))
    for c in d['actionCollectionList']:
        u = c['unpublishedCollection']
        if u['pageId'] != pg: continue
        for m in re.finditer(qn + r'\.run\(\s*(\w+|\{[^}]*\})', u['body']):
            arg = m.group(1)
            if arg.startswith('{'):
                keys = set(re.findall(r'(\w+)\s*:', arg)) | set(re.findall(r'[{,]\s*(\w+)\s*(?=[,}])', arg))
            else:
                before = u['body'][:m.start()]
                k0 = before.rfind('const ' + arg + ' = {')
                mm = re.match(r'const ' + arg + r' = \{(.*?)\n\t\t\};', before[k0:], re.S) if k0 >= 0 else None
                keys = set(re.findall(r'^\s*(\w+):', mm.group(1), re.M)) if mm else None
            if keys is None: warns.append(f'{pg}/{qn}: params dari {arg} tidak dicek')
            elif needed - keys: err(f'{pg}/{qn}: param {needed - keys} tidak dikirim oleh {u["name"]}')
            else: print(f'params OK {pg}/{qn} <- {u["name"]}: {sorted(needed)}')

# ---- 6. Custom Widget yang berubah: sintaks & id elemen
for pg in pages:
    for n, w in build.names[pg].items():
        if w.get('type') != 'CUSTOM_WIDGET': continue
        bw = None
        try: bw = base.widget(pg, n)
        except KeyError: pass
        if bw is not None and bw['uncompiledSrcDoc'] == w['uncompiledSrcDoc']: continue
        js, html = w['uncompiledSrcDoc']['js'], w['uncompiledSrcDoc']['html']
        try: check_js(js)
        except Exception as e: err(f'{pg}/{n}: sintaks JS widget {e}')
        ids = set(re.findall(r'id="(\w+)"', html))
        for m in set(re.findall(r"\$\('(\w+)'\)", js)):
            if m not in ids: err(f'{pg}/{n}: elemen #{m} tidak ada di HTML')
        if w['srcDoc'] != w['uncompiledSrcDoc']: err(f'{pg}/{n}: srcDoc != uncompiledSrcDoc')
        print(f'widget OK {pg}/{n}')

# ---- 6b. tabel yang tableData = {{q_x.data}}: setiap kolom hasil query harus ada di primaryColumns
#      (kalau tidak, Appsmith menambahkannya sendiri sebagai kolom TERLIHAT)
import pglast
checked_tables = []
def select_names(body):
    sql = re.sub(r'\{\{.*?\}\}', "'x'", body, flags=re.S)
    stmt = pglast.parse_sql(sql)[0].stmt
    while getattr(stmt, 'op', None) is not None and str(stmt.op) != 'SetOperation.SETOP_NONE' and stmt.larg is not None:
        stmt = stmt.larg
    names = []
    for t in stmt.targetList or []:
        if t.name:
            names.append(t.name)
        elif t.val.__class__.__name__ == 'ColumnRef':
            last = t.val.fields[-1]
            if last.__class__.__name__ == 'A_Star':
                return None
            names.append(last.sval)
        else:
            names.append('?column?')
    return names
for pg in pages:
    for n, w in build.names[pg].items():
        if w.get('type') != 'TABLE_WIDGET_V2': continue
        m = re.fullmatch(r'\{\{\s*(q_\w+)\.data\s*\}\}', str(w.get('tableData', '')).strip())
        if not m or m.group(1) not in queries.get(pg, {}): continue
        try:
            names = select_names(queries[pg][m.group(1)]['actionConfiguration']['body'])
        except Exception as e:
            warns.append(f'{pg}/{n}: query {m.group(1)} tidak bisa diurai ({e})'); continue
        if names is None:
            warns.append(f'{pg}/{n}: {m.group(1)} memakai SELECT * — kolom tidak dicek'); continue
        pc = w.get('primaryColumns', {})
        miss = [x for x in names if x not in pc]
        checked_tables.append(n)
        if miss: err(f'{pg}/{n}: kolom hasil {m.group(1)} tidak terdaftar di tabel (akan muncul sendiri): {miss}')
        extra = [k for k, c in pc.items() if k not in names and not c.get('isDerived') and c.get('columnType') != 'button']
        if extra: warns.append(f'{pg}/{n}: kolom tabel tanpa data dari {m.group(1)}: {extra}')

# ---- 7. published = unpublished
for p in d['pageList']:
    if p.get('publishedPage') != p['unpublishedPage']: err(f'page {p["unpublishedPage"]["name"]} belum published')

print('tabel dicek kolomnya:', len(checked_tables), sorted(checked_tables))
print('\nRingkasan: pages', len(pages), '| query', sum(len(v) for v in queries.values()),
      f'(base {sum(1 for a in base.d["actionList"] if not a["unpublishedAction"].get("collectionId"))})',
      '| JSObject', len(d['actionCollectionList']))
for w_ in warns: print('WARN', w_)
for e_ in errors: print('ERROR', e_)
print('HASIL:', 'LOLOS' if not errors else f'{len(errors)} ERROR')
