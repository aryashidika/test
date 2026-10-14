# Build R15: salin exports/build_r14.json (app R14 user tidak diubah, hanya di-deploy; keputusan user 13 Okt 2026)
# -> edit di tempat -> exports/build_r15.json. SQL: sql/R15_english.sql (jalankan dulu).
# Isi: seluruh teks app ke bahasa Inggris (kamus tools/r15/), tanpa em dash, nama page baru, kode status harga baru,
# PURPOSE Excel specsheet 5 stage, T72 (kolom Last login tblUsers).
import copy, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'r15'))
from aslib import App
from rlib import ROOT, rd, lock_manual_queries
import en_app
from en_widgets import EXACT, QSUB
from apply_js import do_js, do_html, nodash


def js(path):
    s = rd(path)
    return s[s.index('export default'):]


BASE = f'{ROOT}/exports/build_r14.json'
OUT = f'{ROOT}/exports/build_r15.json'
app = App(BASE)
d = app.d
d['exportedApplication']['name'] = 'Product Management R15'
PAGES = [p['unpublishedPage']['name'] for p in d['pageList']]
RENAME = en_app.PAGES
QS = dict(QSUB)
QS.update(RENAME)
SPECIFIC = {('Material Detail', 'tblPrices', 'primaryColumns.price.label'): 'Price',
            ('Model Detail', 'Canvas2', 'tabName'): 'Model Info'}
EXACT = dict(EXACT, **{'Info Model': 'Model Info'})
stats = {'exact': 0, 'qsub': 0, 'codes': 0, 'dash': 0}


def qsub(s):
    def rep(m):
        q, t = m.group(1), m.group(2)
        if t in QS:
            stats['qsub'] += 1
            return q + QS[t] + q
        if t in en_app.CODES:
            stats['codes'] += 1
            return q + en_app.CODES[t] + q
        return m.group(0)
    return re.sub(r"(['\"])([^'\"\n]+)\1", rep, s)


def fix_value(page, wname, path, v):
    if (page, wname, path) in SPECIFIC:
        stats['exact'] += 1
        return SPECIFIC[(page, wname, path)]
    if v in EXACT:
        stats['exact'] += 1
        return EXACT[v]
    if '{{' in v:
        v = qsub(v)
    if '—' in v:
        stats['dash'] += 1
        v = nodash(v)
    return v


def fix_widget(page, w):
    def rec(obj, path):
        if isinstance(obj, dict):
            for k in list(obj):
                if k in ('children', 'srcDoc', 'uncompiledSrcDoc'):
                    continue
                obj[k] = rec(obj[k], f'{path}.{k}' if path else k)
            return obj
        if isinstance(obj, list):
            return [rec(x, f'{path}[{i}]') for i, x in enumerate(obj)]
        if isinstance(obj, str):
            return fix_value(page, w.get('widgetName'), path, obj)
        return obj
    rec(w, '')
    for t in (w.get('tabsObj') or {}).values():
        if t['label'] in EXACT:
            t['label'] = EXACT[t['label']]


# ---------------------------------------------------------------- widget native + Custom Widget
def norm_js(s):
    s = re.sub(r'//[^\n]*|/\*.*?\*/', '', s, flags=re.S)
    s = re.sub(r'\((\w+)\)\s*=>', r'\1 =>', s)
    return re.sub(r'[\s;,]', '', s)


cw_diff = []
for pg in PAGES:
    for w, _ in app.walk(app.dsl(pg)):
        fix_widget(pg, w)
        if w.get('type') == 'CUSTOM_WIDGET':
            name = w['widgetName']
            src = w['uncompiledSrcDoc']
            # cek: hasil kamus atas sumber di app = isi repo (beda format diabaikan; beda isi hanya polesan kalimat)
            tr_js, _ = do_js(f'widgets/{name}/script.js', src['js'])
            if norm_js(tr_js) != norm_js(rd(f'widgets/{name}/script.js')):
                cw_diff.append(f'{pg}/{name} js')
            # JS & HTML dari repo (sudah dipoles); CSS dari app (sebagian widget memakai CSS gabungan)
            new_css = re.sub(r'/\*.*?\*/', lambda m: nodash(m.group(0)), src['css'], flags=re.S)
            new_css = new_css.replace('.vl.sesuai', '.vl.match')
            app.set_cw_source(pg, name, html=rd(f'widgets/{name}/index.html'), css=new_css,
                              js=rd(f'widgets/{name}/script.js'))

# T72: kolom Last login membaca kunci label "Login terakhir" (tidak ada) -> jam sekarang
t = app.widget('Admin', 'tblUsers')
c = t['primaryColumns']['last_login_at']
assert c['computedValue'].count('currentRow["Login terakhir"]') == 2
c['computedValue'] = c['computedValue'].replace('currentRow["Login terakhir"]', 'currentRow["last_login_at"]')

# ---------------------------------------------------------------- query: kode status harga + em dash
nq = 0
for a in d['actionList']:
    u = a['unpublishedAction']
    if a.get('pluginType') != 'DB' or u.get('collectionId'):
        continue
    body = (u.get('actionConfiguration') or {}).get('body') or ''
    new = re.sub(r"'([^'\n]+)'", lambda m: "'" + en_app.CODES.get(m.group(1), m.group(1)) + "'", body)
    new = nodash(new)
    if new != body:
        app.set_query(u['pageId'], u['name'], body=new)
        nq += 1

# ---------------------------------------------------------------- JSObject dari repo (semua page)
# Auth beda per page (requiredPerm + pageQueries): diterjemahkan dari isi app, bukan dari template repo.
JS_PAGES = {}
AUTH_SRC = {}
for c in d['actionCollectionList']:
    u = c['unpublishedCollection']
    JS_PAGES.setdefault(u['name'], []).append(u['pageId'])
    if u['name'] == 'Auth':
        AUTH_SRC[u['pageId']] = u['body']
for name, pages in JS_PAGES.items():
    f = f'js/{name}.js'
    if not os.path.exists(f'{ROOT}/{f}'):
        raise SystemExit(f'JSObject {name} tidak ada di repo')
    for pg in pages:
        if name == 'Auth':
            body, _ = do_js(f, AUTH_SRC[pg])
            app.set_js(pg, name, body[body.index('export default'):])
        else:
            app.set_js(pg, name, js(f))
for c in d['actionCollectionList']:
    u = c['unpublishedCollection']
    if u['name'] == 'Auth' and u['pageId'] != 'Beranda':
        assert "requiredPerm: ''" not in u['body'] and 'return [];' not in u['body'], u['pageId']

# salinan isi fungsi di layoutOnLoadActions (jsonPathKeys) ikut diperbarui
FN = {a['id']: a['unpublishedAction']['actionConfiguration']['body'] for a in d['actionList']
      if a['unpublishedAction'].get('collectionId')}
for p in d['pageList']:
    for lay in p['unpublishedPage']['layouts']:
        for group in lay.get('layoutOnLoadActions') or []:
            for x in group:
                if x.get('pluginType') == 'JS' and x.get('id') in FN:
                    x['jsonPathKeys'] = [FN[x['id']]]

lock_manual_queries(app)


# ---------------------------------------------------------------- ganti nama page (terakhir: aslib mencari page lewat nama)
def slug(s):
    return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')


def rename_page(old, new):
    for p in d['pageList']:
        for k in ('unpublishedPage', 'publishedPage'):
            pp = p[k]
            if pp['name'] == old:
                pp['name'] = new
                pp['slug'] = slug(new)
                for lay in pp['layouts']:
                    if lay.get('id') == old:
                        lay['id'] = new
                    for group in lay.get('layoutOnLoadActions') or []:
                        for x in group:
                            for kk in ('id', 'collectionId'):
                                if isinstance(x.get(kk), str) and x[kk].startswith(old + '_'):
                                    x[kk] = new + x[kk][len(old):]
    for k in ('pages', 'publishedPages'):
        for p in d['exportedApplication'][k]:
            if p['id'] == old:
                p['id'] = new
    for lst, inner in ((d['actionList'], ('unpublishedAction', 'publishedAction')),
                       (d['actionCollectionList'], ('unpublishedCollection', 'publishedCollection'))):
        for a in lst:
            if a['id'].startswith(old + '_'):
                a['id'] = new + a['id'][len(old):]
            for k in inner:
                x = a.get(k) or {}
                if x.get('pageId') == old:
                    x['pageId'] = new
                if isinstance(x.get('collectionId'), str) and x['collectionId'].startswith(old + '_'):
                    x['collectionId'] = new + x['collectionId'][len(old):]
    app.note(f'page {old} -> {new}')


app.publish_all()
for old, new in RENAME.items():
    rename_page(old, new)
app.save(OUT)

raw = open(OUT, encoding='utf-8').read()
left = {o: raw.count(f'"{o}"') + raw.count(f"'{o}'") for o in RENAME}
print('statistik:', stats, '| query diubah:', nq)
print('nama page lama tersisa (harus 0):', left)
print('em dash tersisa (harus 0):', raw.count('—'))
print('Custom Widget beda dengan repo:', cw_diff)
for n in app.log:
    if not n.startswith(('JSObject', 'Custom Widget')):
        print(n)
