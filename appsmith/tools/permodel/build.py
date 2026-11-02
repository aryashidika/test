# Nama baku material per model (Size Label, Hang Tag, Sticker Inner Box) dari Permodel.xlsx (29 Okt 2026)
# -> appsmith/sql/R_impor_material_permodel.sql + document/Material Per Model/Nama_Baku_Permodel.xlsx
# Pakai: python -I build.py <Permodel.xlsx> [master/material.json]
import json
import re
import sys
from pathlib import Path

import openpyxl
from openpyxl.styles import Font, PatternFill

ROOT = Path(__file__).resolve().parents[3]
OUT_SQL = ROOT / 'appsmith' / 'sql' / 'R_impor_material_permodel.sql'
OUT_XLSX = ROOT / 'document' / 'Material Per Model' / 'Nama_Baku_Permodel.xlsx'

# Jenis -> awalan nama baku, kategori & UoM untuk material BARU (material lama tetap kategori / UoM-nya)
KINDS = {
    'SIZE LABEL': ('LABEL', 'PRS'),
    'HANGTAG': ('PACKAGING', 'PCS'),
    'STICKER INNER BOX': ('PACKAGING', 'PCS'),
}

# Prefix kode (4 karakter) -> jenis + nama model baku.
# Nama model mengikuti penulisan model SS28: LIGHT SPEED (bukan LS / LIGHTSPEED), FG / IN / TF lalu JR, NATIV, WOMEN (bukan WMN).
LS = 'LIGHT SPEED'
MODEL = {
    # Size Label
    '5721': ('SIZE LABEL', '104B'),
    '5722': ('SIZE LABEL', '104T'),
    '58O4': ('SIZE LABEL', 'AERODYNE FG'),
    '58PK': ('SIZE LABEL', 'GALACTICA MORPH NV IN'),
    '58PL': ('SIZE LABEL', 'GALACTICA MORPH NV FG'),
    '58PQ': ('SIZE LABEL', 'ESSORER FG'),
    '58QJ': ('SIZE LABEL', f'{LS} REBORN META SL FG'),
    '58QN': ('SIZE LABEL', f'{LS} REBORN META XR FG'),
    '58QO': ('SIZE LABEL', f'{LS} REBORN META XR IN'),
    '58RK': ('SIZE LABEL', 'NOVASPEED SUBSX'),
    '58RL': ('SIZE LABEL', 'NOVASPEED WOMEN SUBSX'),
    '58RM': ('SIZE LABEL', 'XLR 4 FG'),
    '58RT': ('SIZE LABEL', 'ESSORER TF'),
    '58S1': ('SIZE LABEL', 'GALACTICA MORPH NV FG JR'),
    '58S2': ('SIZE LABEL', 'GALACTICA MORPH NV IN JR'),
    '58S3': ('SIZE LABEL', 'METASALA NATIV RE'),
    '58S4': ('SIZE LABEL', 'SPEEDBLAZE 5 FG'),
    '58S5': ('SIZE LABEL', 'SPEEDBLAZE 5 IN'),
    '58S6': ('SIZE LABEL', f'{LS} REBORN META XR FG JR'),
    '58S7': ('SIZE LABEL', f'{LS} REBORN META XR IN JR'),
    '58S8': ('SIZE LABEL', f'{LS} REBORN META XR TF'),
    # Hang Tag
    'M00H': ('HANGTAG', f'{LS} REBORN META SL FG'),
    'M00L': ('HANGTAG', f'{LS} REBORN META XR FG'),
    'M00M': ('HANGTAG', f'{LS} REBORN META XR IN'),
    'M010': ('HANGTAG', f'{LS} REBORN FG JR'),
    'M011': ('HANGTAG', f'{LS} REBORN IN JR'),
    'M01G': ('HANGTAG', '104 NX'),
    'M01I': ('HANGTAG', 'NOVASPEED SUBSX'),
    'M01J': ('HANGTAG', 'NOVASPEED WOMEN SUBSX'),
    'M01K': ('HANGTAG', 'XLR 4 FG'),
    'M01R': ('HANGTAG', 'ESSORER TF'),
    'M01V': ('HANGTAG', f'ACC {LS} 5 RK ELITE FG'),
    'M01W': ('HANGTAG', f'ACC {LS} 5 RK PRO FG'),
    'M01X': ('HANGTAG', f'{LS} FLUX FG'),
    'M01Y': ('HANGTAG', f'{LS} FLUX IN'),
    'M01Z': ('HANGTAG', 'GALACTICA MORPH NV FG JR'),
    'M020': ('HANGTAG', 'GALACTICA MORPH NV IN JR'),
    'M021': ('HANGTAG', 'METASALA NATIV RE'),
    'M022': ('HANGTAG', 'SPEEDBLAZE 5 FG'),
    'M023': ('HANGTAG', 'SPEEDBLAZE 5 IN'),
    'M024': ('HANGTAG', f'{LS} REBORN META XR FG JR'),
    'M025': ('HANGTAG', f'{LS} REBORN META XR IN JR'),
    'M026': ('HANGTAG', f'{LS} REBORN META XR TF'),
    # Sticker Inner Box (isi dalam kurung / komposisi tidak dipakai)
    'P01B': ('STICKER INNER BOX', 'COANDA SV SUBS1'),
    'P02C': ('STICKER INNER BOX', 'XCELLS FG'),
    'P02D': ('STICKER INNER BOX', 'XCELLS IN'),
    'P055': ('STICKER INNER BOX', 'ELEVATION TWO FG'),
    'P056': ('STICKER INNER BOX', 'ELEVATION TWO IN'),
    'P057': ('STICKER INNER BOX', 'ELEVATION TWO FG JR'),
    'P058': ('STICKER INNER BOX', 'ELEVATION TWO IN JR'),
    'P059': ('STICKER INNER BOX', 'GALACTICA MORPH NV IN'),
    'P05A': ('STICKER INNER BOX', 'GALACTICA MORPH NV FG'),
    'P05F': ('STICKER INNER BOX', 'ESSORER FG'),
    'P069': ('STICKER INNER BOX', f'{LS} REBORN META SL FG'),
    'P073': ('STICKER INNER BOX', f'{LS} REBORN META XR FG'),
    'P074': ('STICKER INNER BOX', f'{LS} REBORN META XR IN'),
    'P088': ('STICKER INNER BOX', f'{LS} REBORN FG JR'),
    'P089': ('STICKER INNER BOX', f'{LS} REBORN IN JR'),
    'P08O': ('STICKER INNER BOX', '104 NX'),
    'P08Q': ('STICKER INNER BOX', 'NOVASPEED SUBSX'),
    'P08R': ('STICKER INNER BOX', 'NOVASPEED WOMEN SUBSX'),
    'P08S': ('STICKER INNER BOX', 'XLR 4 FG'),
    'P08Z': ('STICKER INNER BOX', 'ESSORER TF'),
    'P093': ('STICKER INNER BOX', f'ACC {LS} 5 RK ELITE FG'),
    'P094': ('STICKER INNER BOX', f'ACC {LS} 5 RK PRO FG'),
    'P095': ('STICKER INNER BOX', f'{LS} FLUX FG'),
    'P096': ('STICKER INNER BOX', f'{LS} FLUX IN'),
    'P097': ('STICKER INNER BOX', 'GALACTICA MORPH NV FG JR'),
    'P098': ('STICKER INNER BOX', 'GALACTICA MORPH NV IN JR'),
    'P099': ('STICKER INNER BOX', 'METASALA NATIV RE'),
    'P09A': ('STICKER INNER BOX', 'SPEEDBLAZE 5 FG'),
    'P09B': ('STICKER INNER BOX', 'SPEEDBLAZE 5 IN'),
    'P09C': ('STICKER INNER BOX', f'{LS} REBORN META XR FG JR'),
    'P09D': ('STICKER INNER BOX', f'{LS} REBORN META XR IN JR'),
    'P09E': ('STICKER INNER BOX', f'{LS} REBORN META XR TF'),
}

# Penulisan lain yang dianggap sama saat mencari material lama di master (bukan nama baku)
SYNONYM = [
    (r'\bHEAT ?SEAL\b', ''), (r'\bSZ\b', 'SIZE'), (r'\bLABL\b', 'LABEL'), (r'\bHANG TAG\b', 'HANGTAG'),
    (r'\bLIGHT SPEED\b', 'LS'), (r'\bLIGHTSPEED\b', 'LS'), (r'\bLSREBORN\b', 'LS REBORN'),
    (r'\bACCESSORIES\b', 'ACC'), (r'\bNATIVE\b', 'NATIV'), (r'\bGALACTCA\b', 'GALACTICA'), (r'\bMORP\b', 'MORPH'),
    (r'\bJUNIOR\b', 'JR'), (r'\bWMN\b', 'WOMEN'), (r'\bSTICKER INNER BOX\b|\bSTICKER INER BOX\b', 'STKIB'),
]


def tokens(name):
    s = ' ' + re.sub(r'\s+', ' ', name.upper()) + ' '
    for pat, rep in SYNONYM:
        s = re.sub(pat, rep, s)
    return frozenset(s.split())


def dim_clean(v):
    v = (v or '').strip()
    if v in ('', '.', '-'):
        return ''
    v = re.sub(r'(\d)\s*(MM|CM)\s*X\s*(\d)', r'\1 \2 X \3', v.upper())
    return re.sub(r'\s+', ' ', v)


def q(s):
    return "'" + s.replace("'", "''") + "'"


def main():
    src = Path(sys.argv[1])
    snap = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8')) if len(sys.argv) > 2 else []
    ws = openpyxl.load_workbook(src, data_only=True).active
    rows = []
    for r in ws.iter_rows(min_row=2, values_only=True):
        if not r[0]:
            continue
        code, desc, color, dim, uom, vendor = (str(c).strip() if c is not None else '' for c in r[:6])
        kind, model = MODEL[code[:4]]
        name = f'{kind} {model}'
        old = [m for m in snap if tokens(m['name']) == tokens(name)]
        rows.append(dict(code=code, erp=desc, name=name, kind=kind, model=model, color=color.upper(),
                         dim=dim_clean(dim), uom=uom.upper(), vendor=vendor,
                         old=old[0]['name'] if old else '', old_uom=old[0]['uom'] if old else ''))
    assert len({r['code'] for r in rows}) == len(rows), 'kode kembar di file'
    assert len({r['name'] for r in rows}) == len(rows), 'nama baku kembar'
    write_xlsx(rows, snap)
    write_sql(rows)
    print(len(rows), 'baris;', sum(1 for r in rows if r['old']), 'cocok material lama;', OUT_SQL)


def write_xlsx(rows, snap):
    OUT_XLSX.parent.mkdir(parents=True, exist_ok=True)
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'Nama Baku'
    head = ['Material Code', 'Nama di ERP', 'Nama baku (dipakai)', 'Jenis', 'Model', 'Dimension', 'Warna', 'UoM ERP',
            'Material lama di master (snapshot 28 Okt)', 'UoM lama', 'Catatan']
    ws.append(head)
    for c in ws[1]:
        c.font = Font(bold=True, color='FFFFFF')
        c.fill = PatternFill('solid', fgColor='122A52')
    yellow = PatternFill('solid', fgColor='FFF2CC')
    for r in rows:
        note = []
        if r['old'] and r['old'] != r['name']:
            note.append('nama lama diganti ke nama baku')
        if r['old'] and r['old_uom'] != r['uom']:
            note.append(f"UoM lama {r['old_uom']} tetap dipakai (ERP {r['uom']})")
        if not r['old']:
            note.append('material baru')
        ws.append([r['code'], r['erp'], r['name'], r['kind'], r['model'], r['dim'] or '(None)', r['color'], r['uom'],
                   r['old'], r['old_uom'], '; '.join(note)])
        if r['old'] and r['old_uom'] != r['uom']:
            ws.cell(ws.max_row, 11).fill = yellow
    for col, w in zip('ABCDEFGHIJK', [13, 32, 46, 18, 34, 14, 16, 9, 42, 9, 44]):
        ws.column_dimensions[col].width = w
    ws.freeze_panes = 'A2'
    # Material per model lain yang sudah ada di master tapi tidak ada di file (tidak disentuh)
    used = {r['old'] for r in rows}
    ws2 = wb.create_sheet('Tidak di file')
    ws2.append(['Material di master (snapshot 28 Okt) yang tidak ada di Permodel.xlsx - tidak diubah', 'UoM', 'Kategori'])
    ws2['A1'].font = Font(bold=True)
    for m in snap:
        t = m['name'].upper()
        if (t.startswith(('SIZE LABEL', 'SZ LABEL', 'HEATSEAL SIZE', 'HANGTAG', 'STICKER INNER', 'STANDARD STICKER'))
                and m['name'] not in used):
            ws2.append([m['name'], m['uom'], m['category']])
    ws2.column_dimensions['A'].width = 80
    wb.save(OUT_XLSX)


def values(rows):
    lines = []
    for r in rows:
        cat, _ = KINDS[r['kind']]
        lines.append(f"    ({q(r['code'])}, {q(r['name'])}, {q(r['erp'])}, {q(r['old'])}, {q(cat)}, {q(r['uom'])}, "
                     f"{q(r['dim'])}, {q(r['color'])})")
    return ',\n'.join(lines)


SQL_HEAD = """-- ============================================================================
-- Impor Material per model dari "Permodel.xlsx" (29 Okt 2026): {n} Material Code
--   Size Label {n_sl}, Hang Tag {n_ht}, Sticker Inner Box {n_st}. Supplier: EMRAN GHANIM.
-- Dibuat oleh appsmith/tools/permodel/build.py (jangan diedit tangan; ubah build.py lalu jalankan ulang).
-- Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF), satu bagian per kali:
--   1. CEK   : hanya membaca. Lihat kolom "aksi" sebelum menyimpan.
--   2. SIMPAN: satu transaksi. Jalankan dulu dengan v_simpan := false (uji, semua dibatalkan, pesan berisi
--              ringkasan), lalu ubah ke true dan jalankan lagi.
-- Nama baku = JENIS + nama model: "SIZE LABEL <model>", "HANGTAG <model>", "STICKER INNER BOX <model>".
--   Model ditulis seperti model SS28: LIGHT SPEED (bukan LS / LIGHTSPEED), FG / IN / TF lalu JR, NATIV, WOMEN (bukan WMN).
--   Sticker Inner Box: isi dalam kurung (komposisi) tidak dipakai.
-- Urutan pencocokan per baris:
--   a. Material Code sudah terdaftar  -> material varian itu dipakai, namanya diganti ke nama baku.
--   b. Material dengan nama baku / nama ERP / nama lama (snapshot 28 Okt) sudah ada -> dipakai, nama diganti.
--   c. Tidak ada -> material baru (ACTIVE, CATALOG, kategori LABEL / PACKAGING, UoM dari ERP).
--   Varian (Dimension + warna + kode) ditambah bila kode belum ada. Supplier EMRAN GHANIM ditautkan bila belum.
--   Kategori dan UoM material lama tidak diubah. Aman diulang (baris yang sudah selesai dilewati).
-- ============================================================================
"""

SQL_CEK = """
-- ---------------------------------------------------------------- 1. CEK (hanya membaca)
WITH f AS (SELECT id FROM factory WHERE name ILIKE '%UNIMITRA%'),
src (code, name, erp_name, old_name, category, uom, dim, color) AS (VALUES
{values}
),
x AS (
  SELECT s.*,
         (SELECT m.name || ' (' || m.uom || ')' FROM material_variant v JOIN material m ON m.id = v.material_id
           WHERE v.factory_id = (SELECT id FROM f) AND v.code = s.code) AS kode_di,
         (SELECT m.name || ' (' || m.uom || ')' FROM material m
           WHERE m.factory_id = (SELECT id FROM f)
             AND m.name_key IN (fn_normalize(s.name), fn_normalize(s.erp_name), fn_normalize(nullif(s.old_name, '')))
           ORDER BY m.status = 'ACTIVE' DESC, m.name_key = fn_normalize(s.name) DESC LIMIT 1) AS nama_di
    FROM src s
)
SELECT code, name AS nama_baku, coalesce(kode_di, nama_di, '-') AS material_sekarang,
       CASE WHEN kode_di IS NOT NULL THEN 'a. kode sudah ada' || CASE WHEN kode_di NOT LIKE name || ' (%' THEN ', ganti nama' ELSE '' END
            WHEN nama_di IS NOT NULL THEN 'b. tambah varian ke material lama' || CASE WHEN nama_di NOT LIKE name || ' (%' THEN ', ganti nama' ELSE '' END
            ELSE 'c. material baru' END AS aksi,
       nullif(dim, '') AS dimension, color AS warna
  FROM x
 ORDER BY aksi, name;

-- Ringkas: jumlah per aksi + pabrik / supplier ditemukan
-- SELECT (SELECT count(*) FROM factory WHERE name ILIKE '%UNIMITRA%') AS pabrik,
--        (SELECT string_agg(name, ' | ') FROM supplier WHERE name ILIKE 'EMRAN GHANIM%') AS supplier;
"""

SQL_SIMPAN = """
-- ---------------------------------------------------------------- 2. SIMPAN (uji dulu: v_simpan := false)
DO $$
DECLARE
  v_simpan  boolean := false;   -- ubah ke true setelah uji berhasil
  v_by      text := 'impor Permodel.xlsx';
  v_factory uuid;
  v_supp    uuid;
  r         record;
  v_mat     uuid;
  v_name    text;
  n_new int := 0; n_ren int := 0; n_var int := 0; n_link int := 0; n_skip int := 0;
BEGIN
  SELECT id INTO v_factory FROM factory WHERE name ILIKE '%UNIMITRA%';
  IF (SELECT count(*) FROM factory WHERE name ILIKE '%UNIMITRA%') <> 1 THEN
    RAISE EXCEPTION 'Pabrik UNIMITRA harus tepat satu.';
  END IF;
  SELECT id INTO v_supp FROM supplier WHERE name ILIKE 'EMRAN GHANIM%' ORDER BY status = 'ACTIVE' DESC, name LIMIT 1;
  IF v_supp IS NULL THEN
    RAISE EXCEPTION 'Supplier EMRAN GHANIM tidak ditemukan.';
  END IF;

  FOR r IN SELECT * FROM (VALUES
{values}
  ) AS s (code, name, erp_name, old_name, category, uom, dim, color)
  LOOP
    v_mat := NULL;
    -- a. kode sudah terdaftar
    SELECT v.material_id INTO v_mat FROM material_variant v WHERE v.factory_id = v_factory AND v.code = r.code;
    -- b. material dengan nama baku / ERP / lama
    IF v_mat IS NULL THEN
      SELECT m.id INTO v_mat FROM material m
       WHERE m.factory_id = v_factory
         AND m.name_key IN (fn_normalize(r.name), fn_normalize(r.erp_name), fn_normalize(nullif(r.old_name, '')))
       ORDER BY m.status = 'ACTIVE' DESC, m.name_key = fn_normalize(r.name) DESC LIMIT 1;
    END IF;
    -- c. material baru
    IF v_mat IS NULL THEN
      INSERT INTO material (factory_id, name, category, uom, price_method, status, updated_by)
      VALUES (v_factory, r.name, r.category, r.uom, 'CATALOG', 'ACTIVE', v_by)
      RETURNING id INTO v_mat;
      n_new := n_new + 1;
    ELSE
      SELECT name INTO v_name FROM material WHERE id = v_mat;
      IF v_name <> r.name THEN
        UPDATE material SET name = r.name, updated_by = v_by WHERE id = v_mat;
        n_ren := n_ren + 1;
      END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM material_variant WHERE factory_id = v_factory AND code = r.code) THEN
      n_skip := n_skip + 1;
    ELSE
      INSERT INTO material_variant (material_id, thickness, color, code, status, updated_by)
      VALUES (v_mat, nullif(r.dim, ''), r.color, r.code, 'ACTIVE', v_by);
      n_var := n_var + 1;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM material_supplier WHERE material_id = v_mat AND supplier_id = v_supp) THEN
      INSERT INTO material_supplier (material_id, supplier_id, is_preferred, status, updated_by)
      VALUES (v_mat, v_supp,
              NOT EXISTS (SELECT 1 FROM material_supplier WHERE material_id = v_mat AND is_preferred), 'ACTIVE', v_by);
      n_link := n_link + 1;
    END IF;
  END LOOP;

  IF NOT v_simpan THEN
    RAISE EXCEPTION 'UJI BERHASIL (tidak ada yang disimpan): material baru %, ganti nama %, varian baru %, kode sudah ada %, tautan supplier baru %. Ubah v_simpan ke true lalu jalankan lagi.',
      n_new, n_ren, n_var, n_skip, n_link;
  END IF;
  RAISE NOTICE 'TERSIMPAN: material baru %, ganti nama %, varian baru %, kode sudah ada %, tautan supplier baru %.',
    n_new, n_ren, n_var, n_skip, n_link;
END;
$$;
"""


def write_sql(rows):
    v = values(rows)
    cnt = {k: sum(1 for r in rows if r['kind'] == k) for k in KINDS}
    text = (SQL_HEAD.format(n=len(rows), n_sl=cnt['SIZE LABEL'], n_ht=cnt['HANGTAG'], n_st=cnt['STICKER INNER BOX'])
            + SQL_CEK.format(values=v) + SQL_SIMPAN.format(values=v))
    OUT_SQL.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    main()
