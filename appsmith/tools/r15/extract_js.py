# R15: kumpulkan literal string (JS) & teks (HTML) di js/*.js dan widgets/*/ yang mungkin tampil ke user.
# Keluaran: tools/r15/js_strings.json = {file: [teks unik sesuai urutan]}. Kamus terjemahan: tools/r15/en_app.json.
import glob, json, os, re, sys
import esprima

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORD = re.compile(r'[A-Za-z]{2,}')
CODE = re.compile(r'^[A-Z0-9_]+$|^[a-z][A-Za-z0-9_-]*$|^[#.][\w-]+$|^\W*$')


def prep(src):
    # esprima lama: ganti operator baru dengan panjang sama supaya posisi token tetap
    return src.replace('??=', '||=').replace('??', '||').replace('?.', ' .')


def js_tokens(src):
    toks = esprima.tokenize(prep(src), {'range': True})
    for t in toks:
        if t.type in ('String', 'Template'):
            yield t.range[0], t.range[1], src[t.range[0]:t.range[1]]


def inner(tok):
    if tok[0] in '\'"':
        return tok[1:-1]
    # template: ` ... ${  /  } ... ${  /  } ... `
    a = 1 if tok[0] in '`}' else 0
    b = -2 if tok.endswith('${') else -1
    return tok[a:len(tok) + b]


def visible(s):
    s2 = s.strip()
    if not WORD.search(s2):
        return False
    if CODE.match(s2) and not (s != s2 and re.match(r'^[a-z]{2,}$', s2)):
        return False   # kode; kecuali potongan template berspasi seperti ' dari '
    if re.match(r'^(SELECT|WITH|INSERT|UPDATE)\b', s2) or s2.startswith(('http', '<', 'data:')):
        return '<' in s2 and re.search(r'>[^<]*[A-Za-z]{3}', s2) is not None
    return True


def html_texts(src):
    out = []
    for m in re.finditer(r'>([^<>]*[A-Za-z][^<>]*)<', src):
        if m.group(1).strip():
            out.append(m.group(1).strip())
    for m in re.finditer(r'\b(placeholder|title|aria-label|alt)="([^"]*[A-Za-z][^"]*)"', src):
        out.append(m.group(2))
    return out


def main():
    global res
    res = {}
    files = sorted(glob.glob(f'{ROOT}/js/*.js')) + sorted(glob.glob(f'{ROOT}/widgets/*/script.js'))
    for f in files:
        src = open(f, encoding='utf-8').read()
        seen = []
        for a, b, tok in js_tokens(src):
            s = inner(tok)
            if visible(s) and s not in seen:
                seen.append(s)
        res[os.path.relpath(f, ROOT).replace(os.sep, '/')] = seen
    for f in sorted(glob.glob(f'{ROOT}/widgets/*/index.html')):
        seen = []
        for s in html_texts(open(f, encoding='utf-8').read()):
            if s not in seen:
                seen.append(s)
        res[os.path.relpath(f, ROOT).replace(os.sep, '/')] = seen
    json.dump(res, open(f'{ROOT}/tools/r15/js_strings.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(sum(len(v) for v in res.values()), 'teks;', len({s for v in res.values() for s in v}), 'unik')


if __name__ == '__main__':
    main()
