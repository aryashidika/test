# R15: terapkan kamus (en_app.py) ke js/*.js dan widgets/*/ (script.js, index.html, style.css).
# Hanya isi literal string JS / teks & atribut HTML yang diganti; em dash di komentar diganti ' - '.
# python apply_js.py [--check]   (--check: hanya laporkan, tidak menulis)
import glob, os, re, sys
import esprima

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import en_app as en
from extract_js import prep, inner

CHECK = '--check' in sys.argv
# kode status harga sebagai key objek tanpa tanda kutip (MaterialDetailCtrl)
BARE_KEYS = {'BERLAKU': 'ACTIVE', 'DITOLAK': 'REJECTED'}


def lookup(f, s):
    if s in en.CODES:
        return en.CODES[s]
    d = en.T.get(f, {})
    if s in d:
        return d[s]
    return en.T['*'].get(s)


def esc_for(q, s):
    if q == "'":
        return s.replace("'", "\\'")
    if q == '"':
        return s.replace('"', '\\"')
    return s.replace('`', '\\`').replace('${', '\\${')


def nodash(c):
    return c.replace(' — ', ' - ').replace('—', '-')


def do_js(f, src):
    p = prep(src)
    toks = esprima.tokenize(p, {'range': True, 'comment': True})
    edits = []
    n = 0
    for t in toks:
        a, b = t.range
        tok = src[a:b]
        if t.type in ('String', 'Template'):
            s = inner(tok)
            new = lookup(f, s)
            if new is None and '—' in s:
                new = s.replace(' — ', ' · ').replace('—', '-')   # potongan template tanpa kata, mis. '} — ${'
            if new is None or new == s:
                continue
            q = tok[0] if tok[0] in '\'"' else '`'
            lead = 1 if tok[0] in '\'"`}' else 0
            new_tok = tok[:lead] + esc_for(q, new) + tok[lead + len(s):]
            edits.append((a, b, new_tok))
            n += 1
        elif t.type in ('LineComment', 'BlockComment') and '—' in tok:
            edits.append((a, b, nodash(tok)))
    for a, b, new in sorted(edits, reverse=True):
        src = src[:a] + new + src[b:]
    if f.endswith('MaterialDetailCtrl.js'):
        for k, v in BARE_KEYS.items():
            src, c = re.subn(r'(?<![\w\'"])' + k + r'(?=: \')', v, src)
            n += c
    return src, n


def do_html(f, src):
    n = 0

    def text(m):
        nonlocal n
        raw = m.group(1)
        s = raw.strip()
        new = lookup(f, s)
        if not s or new is None or new == s:
            return m.group(0)
        n += 1
        return '>' + raw.replace(s, new, 1) + '<'

    def attr(m):
        nonlocal n
        new = lookup(f, m.group(2))
        if new is None or new == m.group(2):
            return m.group(0)
        n += 1
        return f'{m.group(1)}="{new}"'

    src = re.sub(r'>([^<>]*[A-Za-z][^<>]*)<', text, src)
    src = re.sub(r'\b(placeholder|title|aria-label|alt)="([^"]*)"', attr, src)
    src = re.sub(r'<!--.*?-->', lambda m: nodash(m.group(0)), src, flags=re.S)
    return src, n


total = 0
files = sorted(glob.glob(f'{ROOT}/js/*.js')) + sorted(glob.glob(f'{ROOT}/widgets/*/*'))
for path in files:
    f = os.path.relpath(path, ROOT).replace(os.sep, '/')
    if not f.endswith(('.js', '.html', '.css')):
        continue
    src = open(path, encoding='utf-8').read()
    if f.endswith('.js'):
        out, n = do_js(f, src)
    elif f.endswith('.html'):
        out, n = do_html(f, src)
    else:
        out, n = re.sub(r'/\*.*?\*/', lambda m: nodash(m.group(0)), src, flags=re.S), 0
    if out != src:
        total += n
        if not CHECK:
            open(path, 'w', encoding='utf-8', newline='\n').write(out)
        print(f'{f}: {n} teks')
print('total', total)
