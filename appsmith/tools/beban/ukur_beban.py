# Ukur semua query BACA app (q_*) di DB beban: EXPLAIN (ANALYZE, BUFFERS) + jumlah baris + ukuran payload JSON.
# pakai: python -I ukur_beban.py <export.json> <db> <label> <out_dir>
#   env PSQL (path psql.exe), PGPORT (default 55433), SKIP (regex nama query yang dilewati, mis. yang sudah pasti timeout)
# Token per role dibuat oleh beban_setup(): 'tok-spec', 'tok-cbd', 'tok-mc', 'tok-brand', 'tok-admin'.
import sys, os, re, json, subprocess

PSQL = os.environ['PSQL']
PORT = os.environ.get('PGPORT', '55433')
export, DB, LABEL, OUT = sys.argv[1:5]
ENV = dict(os.environ, PGOPTIONS='-c statement_timeout=120000')
SKIP = re.compile(os.environ['SKIP']) if os.environ.get('SKIP') else None


def run(q):
    r = subprocess.run([PSQL, '-X', '-h', '127.0.0.1', '-p', PORT, '-U', 'postgres', '-d', DB, '-tA', '-v', 'ON_ERROR_STOP=1', '-c', q],
                       capture_output=True, text=True, encoding='utf-8', env=ENV)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def one(q):
    rc, out, err = run(q)
    if rc:
        raise SystemExit(f'{q}\n{err}')
    return out.splitlines()[0] if out else ''


# ---- parameter "kasus berat yang wajar": season terakhir, model yang sedang dikerjakan
P = {}
P['season'] = one("SELECT season FROM specsheet ORDER BY season_sort DESC LIMIT 1")
P['specsheet_id'] = one(f"""SELECT sh.id FROM specsheet sh JOIN specsheet_revision r ON r.specsheet_id = sh.id AND r.status = 'DRAFT'
                           WHERE sh.season = '{P['season']}'
                             AND EXISTS (SELECT 1 FROM article a JOIN cbd_revision c ON c.article_id = a.id AND c.status = 'DRAFT'
                                          WHERE a.specsheet_id = sh.id)
                           ORDER BY sh.id LIMIT 1""")
P['model_id'] = one(f"SELECT model_id FROM specsheet WHERE id = '{P['specsheet_id']}'")
P['spec_rev'] = one(f"SELECT id FROM specsheet_revision WHERE specsheet_id = '{P['specsheet_id']}' AND status = 'DRAFT'")
P['article_id'] = one(f"""SELECT a.id FROM article a JOIN cbd_revision c ON c.article_id = a.id AND c.status = 'DRAFT'
                         WHERE a.specsheet_id = '{P['specsheet_id']}' ORDER BY a.code LIMIT 1""")
P['cbd_rev'] = one(f"SELECT id FROM cbd_revision WHERE article_id = '{P['article_id']}' AND status = 'DRAFT'")
P['material_id'] = one("""SELECT v.material_id FROM material_variant v JOIN material_supplier ms ON ms.material_id = v.material_id
                          GROUP BY v.material_id ORDER BY count(*) DESC, v.material_id LIMIT 1""")
P['code'], P['color'], P['thickness'] = one(f"SELECT code || '|' || color || '|' || coalesce(thickness, '') FROM material_variant WHERE material_id = '{P['material_id']}' ORDER BY code LIMIT 1").split('|')
P['log_id'] = one(f"SELECT id FROM change_log WHERE revision_id IN (SELECT id FROM specsheet_revision WHERE specsheet_id = '{P['specsheet_id']}') LIMIT 1")

ROLE = {'edit_specsheet': 'spec', 'edit_cbd': 'cbd', 'approve_price': 'mc', 'view_audit': 'admin', 'manage_users': 'admin',
        'view_cbd': 'cbd', 'view_price': 'cbd'}
OVERRIDE = {'q_worklist_pub_spec': 'brand', 'q_worklist_pub_cbd': 'brand'}
# variasi tambahan: (nama, {ekspresi widget: nilai})
VARIANTS = {'q_audit': [{'inpAuditCari.text': 'zzz'}], 'q_materials': [{'inpMaterialCari.text': 'leather'}],
            'q_models': [{'inpModelCari.text': 'model 01'}]}


def build(name, page, body, role, widget):
    def sub(m):
        e = m.group(1).strip()
        if e == 'appsmith.store.token':
            return f"'tok-{role}'"
        if 'URL.queryParams.id' in e:
            return "'" + (P['model_id'] if page == 'Model Detail' else P['material_id']) + "'"
        mm = re.match(r'this\.params\.(\w+)', e)
        if mm:
            k = mm.group(1)
            v = {'revision_id': P['cbd_rev'] if page.startswith('Cost') else P['spec_rev'],
                 'kind': 'MATERIAL', 'text': 'MATERIAL 01', 'exclude_id': '', 'id': ''}.get(k, P.get(k, ''))
            return "'" + str(v) + "'"
        for w, v in widget.items():
            if e.startswith(w):
                return "'" + v + "'"
        if 'selPilihanJenis' in e:
            return "'KATEGORI'"
        return "''"
    return re.sub(r'\{\{(.*?)\}\}', sub, body, flags=re.S).strip().rstrip(';').strip()


d = json.load(open(export, encoding='utf-8'))
seen, results = set(), []
os.makedirs(OUT, exist_ok=True)
plans = open(os.path.join(OUT, f'plans_{LABEL}.txt'), 'w', encoding='utf-8')
for a in d['actionList']:
    u = a['unpublishedAction']
    if a.get('pluginType') != 'DB' or not u['name'].startswith('q_') or u['name'] == 'q_me':
        continue
    body = u['actionConfiguration'].get('body') or ''
    if (u['name'], body) in seen:
        continue
    seen.add((u['name'], body))
    perms = re.findall(r"fn_auth\([^,]+,\s*'(\w+)'", body)
    role = OVERRIDE.get(u['name']) or next((ROLE[p] for p in perms if p in ROLE), 'spec')
    for widget in [{}] + VARIANTS.get(u['name'], []):
        label = u['name'] + ('' if not widget else ' [' + ','.join(f'{k.split(".")[0]}={v}' for k, v in widget.items()) + ']')
        if SKIP and SKIP.search(label):
            continue
        sql = build(u['name'], u['pageId'], body, role, widget)
        res = {'page': u['pageId'], 'query': label, 'role': role}
        for attempt in range(2):          # ke-2 = cache hangat
            rc, out, err = run('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + sql)
            if rc:
                break
        if rc:
            res['error'] = err.splitlines()[0][:200]
        else:
            pj = json.loads(out)[0]
            res['exec_ms'] = round(pj['Execution Time'], 1)
            res['plan_ms'] = round(pj['Planning Time'], 1)
            rc2, out2, err2 = run(f'SELECT count(*), coalesce(sum(length(row_to_json(t)::text)), 0) FROM ({sql}) t')
            if rc2 == 0:
                n, b = out2.split('|')
                res['rows'], res['payload_kb'] = int(n), round(int(b) / 1024, 1)
            rc3, txt, _ = run('EXPLAIN (ANALYZE, BUFFERS) ' + sql)
            plans.write(f'===== {u["pageId"]} / {label}  ({res["exec_ms"]} ms)\n{txt}\n\n')
        results.append(res)
        print(f"{res.get('exec_ms', 'ERR'):>10}  {res.get('rows', ''):>6}  {res.get('payload_kb', ''):>8}  {u['pageId']} / {label}"
              + (f"  !! {res['error']}" if 'error' in res else ''), flush=True)

sizes = run("""SELECT json_object_agg(t, n) FROM (
  SELECT 'material_variant' t, count(*) n FROM material_variant UNION ALL SELECT 'material_price', count(*) FROM material_price
  UNION ALL SELECT 'product_model', count(*) FROM product_model UNION ALL SELECT 'specsheet', count(*) FROM specsheet
  UNION ALL SELECT 'article', count(*) FROM article UNION ALL SELECT 'specsheet_revision', count(*) FROM specsheet_revision
  UNION ALL SELECT 'bom_line', count(*) FROM bom_line UNION ALL SELECT 'bom_cell', count(*) FROM bom_cell
  UNION ALL SELECT 'cbd_revision', count(*) FROM cbd_revision UNION ALL SELECT 'cbd_line', count(*) FROM cbd_line
  UNION ALL SELECT 'audit_log', count(*) FROM audit_log) x""")[1]
dbsize = one(f"SELECT pg_size_pretty(pg_database_size('{DB}'))")
json.dump({'label': LABEL, 'params': P, 'tables': json.loads(sizes), 'db_size': dbsize, 'results': results},
          open(os.path.join(OUT, f'hasil_{LABEL}.json'), 'w', encoding='utf-8'), indent=1)
print('tabel:', sizes, '| ukuran DB:', dbsize)
