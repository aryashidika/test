# Tampilkan teks per file beserta baris sumbernya (untuk konteks terjemahan). python show.py <file...>
import json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
d = json.load(open(f'{ROOT}/tools/r15/js_strings.json', encoding='utf-8'))
for f in sys.argv[1:]:
    src = open(f'{ROOT}/{f}', encoding='utf-8').read().split('\n')
    print('##', f)
    for s in d[f]:
        line = next((l.strip() for l in src if s in l), '')
        ctx = '' if line.strip(" '\",;`") == s else '   <- ' + line[:170]
        print('  ', repr(s), ctx)
