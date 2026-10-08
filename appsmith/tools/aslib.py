# Helper untuk mengedit export JSON Appsmith (salin base -> edit di tempat -> validasi).
import copy, json, re, random, string, uuid, datetime
import esprima

def sanitize(src):
    """esprima-python belum mengenal ?. dan ?? — ganti dengan sintaks lama yang PANJANGNYA SAMA
    supaya posisi (range) tetap cocok dengan teks asli."""
    src = src.replace('?.[', '  [').replace('?.(', '  (')
    src = re.sub(r'\?\.(?=[A-Za-z_$])', ' .', src)
    return src.replace('??', '||')

def check_js(src, module=False):
    s = sanitize(src)
    return esprima.parseModule(s) if module else esprima.parseScript(s)

class App:
    def __init__(self, path):
        self.d = json.load(open(path, encoding='utf-8'))
        sample = next(a['gitSyncId'] for a in self.d['actionList'] if a.get('gitSyncId'))
        self.git_prefix = sample.split('_')[0]
        self.changed_js = []          # (page, name) untuk validasi
        self.changed_cw = []          # (page, widgetName)
        self.log = []

    # ------------------------------------------------------------- umum
    def note(self, msg):
        self.log.append(msg)

    def page(self, name):
        for p in self.d['pageList']:
            if p['unpublishedPage']['name'] == name:
                return p
        raise KeyError(f'page {name}')

    def dsl(self, page):
        return self.page(page)['unpublishedPage']['layouts'][0]['dsl']

    @staticmethod
    def walk(w, parent=None):
        yield w, parent
        for c in w.get('children', []) or []:
            yield from App.walk(c, w)

    def widget(self, page, name, with_parent=False):
        for w, p in self.walk(self.dsl(page)):
            if w.get('widgetName') == name:
                return (w, p) if with_parent else w
        raise KeyError(f'widget {page}/{name}')

    @staticmethod
    def new_wid():
        return ''.join(random.choice(string.ascii_lowercase + string.digits) for _ in range(10))

    def new_git(self):
        return f'{self.git_prefix}_{uuid.uuid4()}'

    # ------------------------------------------------------------- query
    def action(self, page, name):
        for a in self.d['actionList']:
            u = a['unpublishedAction']
            if u['pageId'] == page and u['name'] == name and not u.get('collectionId'):
                return a
        raise KeyError(f'query {page}/{name}')

    @staticmethod
    def path_keys(body):
        return sorted(set(m.strip() for m in re.findall(r'\{\{(.*?)\}\}', body, re.S)))

    def set_query(self, page, name, body=None, run_behaviour=None, confirm=None):
        a = self.action(page, name)
        u = a['unpublishedAction']
        if body is not None:
            u['actionConfiguration']['body'] = body
            u['jsonPathKeys'] = self.path_keys(body)
        if run_behaviour is not None:
            u['runBehaviour'] = run_behaviour
            # userSetOnLoad=True: Appsmith tidak mengubah Manual -> Automatic saat import (temuan R1:
            # q_factories & q_change_log_images kembali Automatic karena flag ini false)
            u['userSetOnLoad'] = True
        if confirm is not None:
            u['confirmBeforeExecute'] = confirm
        self.note(f'query {page}/{name} diubah')
        return a

    def add_query(self, page, name, template, body, confirm=False):
        src = self.action(page, template)
        a = copy.deepcopy(src)
        u = a['unpublishedAction']
        u['name'] = name
        u['actionConfiguration']['body'] = body
        u['jsonPathKeys'] = self.path_keys(body)
        u['runBehaviour'] = 'MANUAL'
        u['userSetOnLoad'] = True          # lihat set_query
        u['confirmBeforeExecute'] = confirm
        u['createdAt'] = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
        a['id'] = f'{page}_{name}'
        a['gitSyncId'] = self.new_git()
        self.d['actionList'].append(a)
        self.note(f'query baru {page}/{name}')
        return a

    def delete_query(self, page, name):
        a = self.action(page, name)
        self.d['actionList'].remove(a)
        self.note(f'query {page}/{name} dihapus')

    # ------------------------------------------------------------- JSObject
    def collection(self, page, name):
        for c in self.d['actionCollectionList']:
            u = c['unpublishedCollection']
            if u['pageId'] == page and u['name'] == name:
                return c
        raise KeyError(f'JSObject {page}/{name}')

    def js_body(self, page, name):
        return self.collection(page, name)['unpublishedCollection']['body']

    def set_js(self, page, name, body):
        assert body.startswith('export default'), f'{page}/{name}: body JSObject wajib diawali "export default"'
        c = self.collection(page, name)
        coll_id = c['id']
        u = c['unpublishedCollection']
        tree = esprima.parseModule(sanitize(body), {'range': True})
        decl = tree.body[0]
        assert decl.type == 'ExportDefaultDeclaration' and decl.declaration.type == 'ObjectExpression', name
        variables, funcs = [], {}
        for prop in decl.declaration.properties:
            key = prop.key.name if prop.key.type == 'Identifier' else prop.key.value
            v = prop.value
            if v.type in ('FunctionExpression', 'ArrowFunctionExpression'):
                params = [body[p.range[0]:p.range[1]] for p in v.params]
                names = [(p.left.name if p.type == 'AssignmentPattern' else p.name) for p in v.params]
                blk = body[v.body.range[0]:v.body.range[1]]
                if v.body.type != 'BlockStatement':
                    blk = '{\n  return ' + blk + ';\n}'
                fn = ('async ' if v.isAsync else '') + 'function (' + ', '.join(params) + ') ' + blk
                fn = re.sub(r'\bthis\.', name + '.', fn)
                funcs[key] = (fn, names)
            else:
                variables.append({'name': key, 'value': body[v.range[0]:v.range[1]]})
        u['body'] = body
        u['variables'] = variables
        # aksi fungsi: ubah / tambah / hapus
        existing = [a for a in self.d['actionList'] if a['unpublishedAction'].get('collectionId') == coll_id]
        if not existing:
            # JSObject ini di export memang tanpa entri fungsi (Appsmith membaca dari body) — ikuti apa adanya
            self.changed_js.append((page, name))
            self.note(f'JSObject {page}/{name} diubah (body saja, tanpa entri fungsi seperti di base)')
            return
        template = existing[0]
        by_name = {a['unpublishedAction']['name']: a for a in existing}
        for fname, (fn, names) in funcs.items():
            a = by_name.get(fname)
            if a is None:
                a = copy.deepcopy(template)
                a['id'] = f'{coll_id}.{fname}'.replace(f'{page}_{name}.', f'{page}_{name}.')
                a['gitSyncId'] = self.new_git()
                a['unpublishedAction']['name'] = fname
                a['unpublishedAction']['fullyQualifiedName'] = f'{name}.{fname}'
                a['unpublishedAction']['runBehaviour'] = 'MANUAL'
                a['unpublishedAction']['confirmBeforeExecute'] = False
                a['unpublishedAction']['createdAt'] = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
                self.d['actionList'].append(a)
            ua = a['unpublishedAction']
            ua['actionConfiguration']['body'] = fn
            ua['actionConfiguration']['jsArguments'] = [{'name': n} for n in names]
            ua['jsonPathKeys'] = [fn]
        removed = [n for n in by_name if n not in funcs]
        if removed:
            self.d['actionList'] = [a for a in self.d['actionList']
                                    if not (a['unpublishedAction'].get('collectionId') == coll_id
                                            and a['unpublishedAction']['name'] in removed)]
        self.changed_js.append((page, name))
        self.note(f'JSObject {page}/{name} diubah (fungsi {len(funcs)}, dihapus {removed})')

    def replace_js(self, page, name, pairs):
        body = self.js_body(page, name)
        for old, new in pairs:
            n = body.count(old)
            assert n >= 1, f'{page}/{name}: teks tidak ditemukan: {old[:60]}'
            body = body.replace(old, new)
        self.set_js(page, name, body)

    # ------------------------------------------------------------- widget
    def set_prop(self, page, wname, key, value, binding=None, trigger=None):
        w = self.widget(page, wname)
        w[key] = value
        if binding is not None:
            self._path_list(w, 'dynamicBindingPathList', key, binding)
        if trigger is not None:
            self._path_list(w, 'dynamicTriggerPathList', key, trigger)
            self._path_list(w, 'dynamicPropertyPathList', key, trigger)
        return w

    @staticmethod
    def _path_list(w, list_key, key, present):
        lst = w.setdefault(list_key, [])
        has = any(x['key'] == key for x in lst)
        if present and not has:
            lst.append({'key': key})
        if not present and has:
            w[list_key] = [x for x in lst if x['key'] != key]

    def set_cw_source(self, page, wname, html=None, css=None, js=None):
        w = self.widget(page, wname)
        for part, val in (('html', html), ('css', css), ('js', js)):
            if val is not None:
                w['uncompiledSrcDoc'][part] = val
        # srcDoc = sumber asli (versi "compiled" Appsmith hanya format ulang)
        w['srcDoc'] = dict(w['uncompiledSrcDoc'])
        self.changed_cw.append((page, wname))
        self.note(f'Custom Widget {page}/{wname} diubah')

    def clone_widget(self, page, src_name, new_name, parent_name=None, renames=None):
        """Salin widget beserta anaknya. renames: {namaLama: namaBaru} untuk anak-anaknya."""
        src, src_parent = self.widget(page, src_name, with_parent=True)
        parent = self.widget(page, parent_name) if parent_name else src_parent
        w = copy.deepcopy(src)
        renames = dict(renames or {})
        renames[src_name] = new_name
        def fix(node, parent_id):
            node['widgetId'] = self.new_wid()
            node['key'] = self.new_wid()
            node['parentId'] = parent_id
            if node.get('widgetName') in renames:
                node['widgetName'] = renames[node['widgetName']]
            for ch in node.get('children', []) or []:
                fix(ch, node['widgetId'])
        fix(w, parent['widgetId'])
        parent.setdefault('children', []).append(w)
        self.note(f'widget baru {page}/{new_name} (salinan {src_name})')
        return w

    # ------------------------------------------------------------- akhir
    def publish_all(self):
        """Sama dengan Deploy: versi published = versi edit."""
        for p in self.d['pageList']:
            p['publishedPage'] = copy.deepcopy(p['unpublishedPage'])
        for a in self.d['actionList']:
            a['publishedAction'] = copy.deepcopy(a['unpublishedAction'])
        for c in self.d['actionCollectionList']:
            c['publishedCollection'] = copy.deepcopy(c['unpublishedCollection'])

    def save(self, path):
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(self.d, f, ensure_ascii=False)
