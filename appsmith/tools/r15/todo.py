# Teks yang belum ada di kamus (T) dan belum ditandai aman (KEEP). python todo.py [file...]
import json, os, sys, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
spec = importlib.util.spec_from_file_location('en_app', f'{HERE}/en_app.py'); en = importlib.util.module_from_spec(spec); spec.loader.exec_module(en)
d = json.load(open(f'{HERE}/js_strings.json', encoding='utf-8'))
keep = getattr(en, 'KEEP', set())
files = sys.argv[1:] or list(d)
n = 0
for f in files:
    src = open(f'{ROOT}/{f}', encoding='utf-8').read().split('\n')
    rest = [s for s in d[f] if s not in en.T.get(f, {}) and s not in en.T['*'] and s not in keep and s not in getattr(en, 'CODES', {})]
    if not rest: continue
    print('##', f, len(rest))
    for s in rest:
        line = next((l.strip() for l in src if s in l), '')
        ctx = '' if line.strip(" '\",;`") == s else '   <- ' + line[:160]
        print('  ', repr(s), ctx); n += 1
print('sisa', n)
