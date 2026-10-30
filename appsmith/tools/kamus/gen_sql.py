"""R21: tulis isi kamus kode ERP ke sql/R21_kamus_isi_<n>.sql (dijalankan sesudah sql/R21_kamus.sql).

Sumber (hasil review 29 Okt 2026, lihat PLAN §6 R21): filt.pkl (material), dimensi.pkl (Dimension), warna.pkl (warna).
Hanya baris MASUK. Keputusan user yang diterapkan di sini:
  - A1: awalan 938L, 938N, 960I, 20CZ, 504A MASUK (filt.pkl menandainya gabungan / process); 4038 TIDAK
  - TANYA: Dimension B28 tidak masuk kamus (arti ERP beda dengan varian app 6717B28BFC)
  - teks untuk kode yang sudah dipakai varian app = teks varian app (kamus mengikuti app, A2 / KAMUS / TANYA);
    itu dikerjakan SQL saat impor (LEFT JOIN ke material_variant), bukan di sini
Perbaikan bentuk baku Dimension dari dimensi.py (tanda '#' dipakai sebagai pengganti titik sementara):
  - '#200' jadi '.200' -> dikembalikan '#200'
  - sel Excel dua baris ('..._x000D_\\n39') -> baris kedua dibuang
Pakai: python -X utf8 -I gen_sql.py   (dari folder tools/kamus)
"""
import os, pickle, re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'sql')
MAX_BYTES = 150_000          # file SQL terbesar yang pernah dijalankan user lewat DB Tools ~160 KB

A1_IN = {'938L', '938N', '960I', '20CZ', '504A'}
DIM_OUT = {'B28'}


def ld(name):
    with open(os.path.join(HERE, name), 'rb') as f:
        return pickle.load(f)


def ws(s):
    s = re.sub(r'(?i)_x000d_', '', s or '')
    return re.sub(r'\s+', ' ', s).strip().upper()


def tight(s):
    return re.sub(r'[^a-z0-9]', '', (s or '').lower())


def first_line(raw):
    return re.split(r'(?i)_x000d_|\n', raw or '')[0]


# ---------------------------------------------------------------- material
filt = ld('filt.pkl')
mat = [(c.strip().upper(), ws(n)) for _, c, n, _ in filt['mat_keep']]
mat += [(c.strip().upper(), ws(n)) for _, c, n, _ in filt['mat_drop'] if c.strip().upper() in A1_IN]
assert len({c for c, _ in mat}) == len(mat), 'awalan kembar'
assert {c for c, _ in mat} >= A1_IN and '4038' not in {c for c, _ in mat}
name_n = {}
for _, n in mat:
    name_n[tight(n)] = name_n.get(tight(n), 0) + 1
# kolom 3: nama rapat unik di seluruh ADF -> boleh disambung ke material app tanpa varian yang namanya sama
mat_rows = [(c, n, '1' if name_n[tight(n)] == 1 else '0') for c, n in sorted(mat)]

# ---------------------------------------------------------------- Dimension
dim_rows, fixed = [], []
for _, c, raw, baku, st, _ in ld('dimensi.pkl'):
    c = c.strip().upper()
    if st != 'MASUK' or c in DIM_OUT:
        continue
    t = '' if baku == '(None)' else baku
    if '#' in raw and t.startswith('.'):
        t = '#' + t[1:]
        fixed.append((c, raw, t))
    rest = ws(raw[len(first_line(raw)):])
    if rest and t.endswith(' ' + rest):
        t = t[:-len(rest) - 1].rstrip()
        fixed.append((c, raw, t))
    dim_rows.append((c, ws(t)))
assert len({c for c, _ in dim_rows}) == len(dim_rows), 'kode Dimension kembar'

# ---------------------------------------------------------------- warna
col_rows = []
for r in ld('warna.pkl'):
    _, c, raw, baku, st = r[:5]
    if st == 'MASUK':
        col_rows.append((c.strip().upper(), ws(baku or raw)))
assert len({c for c, _ in col_rows}) == len(col_rows), 'kode warna kembar'
assert all(t for _, t in col_rows), 'warna kosong'

for rows in (mat_rows, dim_rows, col_rows):
    for row in rows:
        for v in row:
            assert '\t' not in v and '\n' not in v and '$kamus$' not in v and '{{' not in v and '}}' not in v, row

# File SQL hanya ASCII: karakter lain bisa berubah saat ditempel ke DB Tools (kutip miring jadi kutip biasa, uji user 20 &
# 30 Okt 2026). Satu-satunya non-ASCII di kamus = '±' (25 material + 1 Dimension) -> ditulis '~PM~', dikembalikan chr(177) di SQL.
PM = '~PM~'
assert not any(PM in v for rows in (mat_rows, dim_rows, col_rows) for row in rows for v in row)


def ascii_only(rows):
    out = []
    for row in rows:
        row = tuple(v.replace('±', PM) for v in row)
        assert all(v.isascii() for v in row), ('non-ASCII baru, tambahkan penggantinya', row)
        out.append(row)
    return out


mat_rows, dim_rows, col_rows = ascii_only(mat_rows), ascii_only(dim_rows), ascii_only(col_rows)

# ---------------------------------------------------------------- SQL per tabel
INSERT = {
    'material': """  INSERT INTO code_dict_material (factory_id, code, name, material_id, source, created_by)
  SELECT v_factory, s.code, s.txt, a.material_id, 'ERP', 'R21 import'
    FROM src s
    LEFT JOIN LATERAL (SELECT v.material_id FROM material_variant v
                        WHERE v.factory_id = v_factory AND length(v.code) = 10 AND left(v.code, 4) = s.code
                        GROUP BY v.material_id ORDER BY count(*) DESC, min(v.created_at), v.material_id LIMIT 1) a ON true
  ON CONFLICT (factory_id, code) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  -- material app tanpa varian berkode yang namanya sama (rapat) dengan nama ADF yang unik -> disambung
  WITH k AS (SELECT fn_tight_key(m.name) AS name_key, min(m.id::text)::uuid AS id
               FROM material m WHERE m.factory_id = v_factory GROUP BY 1 HAVING count(*) = 1),
       c AS (SELECT k.* FROM k JOIN material m ON m.id = k.id
              WHERE NOT m.is_process
                AND NOT EXISTS (SELECT 1 FROM material_variant v WHERE v.material_id = m.id AND length(v.code) = 10)
                AND NOT EXISTS (SELECT 1 FROM code_dict_material x WHERE x.material_id = m.id))
  UPDATE code_dict_material d SET material_id = c.id
    FROM src s JOIN c ON c.name_key = s.name_key
   WHERE s.uniq = '1' AND d.factory_id = v_factory AND d.code = s.code AND d.material_id IS NULL;""",
    'dimension': """  INSERT INTO code_dict_dimension (factory_id, code, thickness, source, created_by)
  SELECT v_factory, s.code, coalesce(a.thickness, fn_clean_thickness(s.txt), ''), 'ERP', 'R21 import'
    FROM src s
    LEFT JOIN LATERAL (SELECT coalesce((array_agg(v.thickness ORDER BY v.created_at, v.code))[1], '') AS thickness
                         FROM material_variant v
                        WHERE v.factory_id = v_factory AND length(v.code) = 10 AND substr(v.code, 5, 3) = s.code
                        GROUP BY v.thickness_key ORDER BY count(*) DESC, min(v.created_at) LIMIT 1) a ON true
  ON CONFLICT (factory_id, code) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;""",
    'color': """  INSERT INTO code_dict_color (factory_id, code, color, source, created_by)
  SELECT v_factory, s.code, coalesce(a.color, fn_clean_color(s.txt)), 'ERP', 'R21 import'
    FROM src s
    LEFT JOIN LATERAL (SELECT (array_agg(v.color ORDER BY v.created_at, v.code))[1] AS color
                         FROM material_variant v
                        WHERE v.factory_id = v_factory AND length(v.code) = 10 AND substr(v.code, 8, 3) = s.code
                        GROUP BY v.color_key ORDER BY count(*) DESC, min(v.created_at) LIMIT 1) a ON true
  ON CONFLICT (factory_id, code) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;""",
}
COLS = {'material': "split_part(l, E'\\t', 1) AS code, split_part(l, E'\\t', 2) AS txt, split_part(l, E'\\t', 3) AS uniq,\n"
                    "         fn_tight_key(split_part(l, E'\\t', 2)) AS name_key",
        'dimension': "split_part(l, E'\\t', 1) AS code, split_part(l, E'\\t', 2) AS txt",
        'color': "split_part(l, E'\\t', 1) AS code, split_part(l, E'\\t', 2) AS txt"}
LABEL = {'material': 'awalan material', 'dimension': 'kode Dimension', 'color': 'kode warna'}


def chunks(rows):
    out, cur, size = [], [], 0
    for r in rows:
        line = '\t'.join(r) + '\n'
        if cur and size + len(line.encode()) > MAX_BYTES - 4000:
            out.append(cur)
            cur, size = [], 0
        cur.append(line)
        size += len(line.encode())
    if cur:
        out.append(cur)
    return out


parts = []
for kind, rows in (('material', mat_rows), ('dimension', dim_rows), ('color', col_rows)):
    cs = chunks(rows)
    for i, c in enumerate(cs, 1):
        parts.append((kind, i, len(cs), c))

for old in os.listdir(OUT):
    if re.fullmatch(r'R21_kamus_isi_\d+\.sql', old):
        os.remove(os.path.join(OUT, old))
TOTAL = {'material': len(mat_rows), 'dimension': len(dim_rows), 'color': len(col_rows)}
for n, (kind, i, k, lines) in enumerate(parts, 1):
    first, last = lines[0].split('\t')[0], lines[-1].split('\t')[0]
    head = f"""-- ============================================================================
-- R21 Appsmith: isi kamus kode ERP - file {n} dari {len(parts)}: {LABEL[kind]} bagian {i}/{k} ({len(lines)} baris, {first} - {last})
-- Dibuat oleh appsmith/tools/kamus/gen_sql.py (jangan diedit tangan). Jalankan SESUDAH sql/R21_kamus.sql lewat
-- z_run_sql di app "DB Tools" (Use prepared statements = OFF). Satu transaksi. Aman diulang (kode yang sudah ada dilewati).
-- Kode yang sudah dipakai varian app memakai teks varian app (kamus mengikuti app). Varian tidak diubah.
-- Total {LABEL[kind]} di kamus: {TOTAL[kind]}. Cek jumlah sesudah semua file: steps/R21_uji.md bagian 1.
-- ============================================================================
DO $r21$
DECLARE
  v_factory uuid := fn_r21_import_factory();
  v_n       int;
BEGIN
  CREATE TEMP TABLE src ON COMMIT DROP AS
  SELECT {COLS[kind]}
    FROM regexp_split_to_table(replace(replace($kamus$
"""
    tail = f"""$kamus$, E'\\r', ''), '{PM}', chr(177)), E'\\n') l
   WHERE l <> '';
{INSERT[kind]}
  RAISE NOTICE 'R21 file {n}: % {LABEL[kind]} baru', v_n;
END
$r21$;
"""
    path = os.path.join(OUT, f'R21_kamus_isi_{n}.sql')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(head + ''.join(lines) + tail)
    print(f'{os.path.basename(path)}: {kind} {i}/{k}, {len(lines)} baris, {os.path.getsize(path):,} byte')
print('total', TOTAL)
print('Dimension diperbaiki:', len(fixed))
for r in fixed:
    print('  ', r)
