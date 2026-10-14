# R15: ambil definisi fungsi & view public dari DB lokal (psql) -> tools/r15/db_objs.json; daftar literal -> db_literals.txt
import json, os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
PSQL = os.environ.get('PSQL', 'psql')
DB = sys.argv[1] if len(sys.argv) > 1 else 'r14c'
def q(sql):
    r = subprocess.run([PSQL, '-X', '-p', '55433', '-U', 'postgres', '-d', DB, '-tA', '-F', '\x1f', '-R', '\x1e'],
                       input=sql, capture_output=True, text=True, encoding='utf-8')
    assert r.returncode == 0, r.stderr
    return [x.split('\x1f') for x in r.stdout.split('\x1e') if x.strip()]
rows = q("""
SELECT 'F', p.oid::regprocedure::text, pg_get_functiondef(p.oid)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.prokind = 'f'
   AND p.prolang IN (SELECT oid FROM pg_language WHERE lanname IN ('plpgsql', 'sql'))
   AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
UNION ALL
SELECT 'V', c.oid::regclass::text, 'CREATE OR REPLACE VIEW ' || c.oid::regclass::text || ' AS' || chr(10) || pg_get_viewdef(c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'v'
""")
objs = [{'kind': k, 'name': n, 'def': d} for k, n, d in rows]
json.dump(objs, open(f'{HERE}/db_objs.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
LIT = re.compile(r"(?<![A-Za-z0-9_])E?'((?:[^']|'')*)'")
seen = {}
for o in objs:
    body = re.sub(r'--[^\n]*', '', o['def'])
    for m in LIT.finditer(body):
        s = m.group(1).replace("''", "'")
        if re.search(r'[a-z]{2,}', s) and (' ' in s.strip() or re.match(r'^[A-Z][a-z]', s)):
            seen.setdefault(s, set()).add(o['name'].split('(')[0])
with open(f'{HERE}/db_literals.txt', 'w', encoding='utf-8') as f:
    for s, objs_ in sorted(seen.items(), key=lambda x: sorted(x[1])[0]):
        f.write(f'{s!r}\t{",".join(sorted(objs_))}\n')
print(len(objs), 'objek;', len(seen), 'literal')
