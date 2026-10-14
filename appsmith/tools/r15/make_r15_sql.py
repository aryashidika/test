# R15: buat sql/R15_english.sql dari definisi fungsi & view di DB lokal (tools/r15/db_objs.json, dari db_dump.py
# setelah R14) + kamus en_db.py + kode status harga (en_app_b.CODES). Hanya objek yang berubah yang ditulis.
# - literal teks diganti utuh (bukan potongan kata); jumlah placeholder % harus sama
# - argumen RAISE berisi kode stage dibungkus fn_stage_label() (pesan memakai Pullover/Preview/Production)
# - em dash di komentar & teks diganti
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from en_db import D
from en_app_b import CODES

MAP = dict(D)
MAP.update(CODES)
LIT = re.compile(r"(?<![A-Za-z0-9_])'((?:[^']|'')*)'")
pct = lambda s: len(re.findall(r'(?<!%)%(?!%)', s.replace('%%', '')))
used = set()


def tr_literals(src):
    def rep(m):
        s = m.group(1).replace("''", "'")
        new = MAP.get(s)
        if new is None:
            return m.group(0)
        assert pct(new) == pct(s), f'jumlah % beda: {s!r} -> {new!r}'
        used.add(s)
        return "'" + new.replace("'", "''") + "'"
    # literal di komentar baris tidak disentuh (komentar diproses terpisah)
    out = []
    for line in src.split('\n'):
        code, sep, comment = line.partition('--') if not re.search(r"'[^']*--", line) else (line, '', '')
        out.append(LIT.sub(rep, code) + sep + comment)
    return '\n'.join(out)




def tr_raise(src):
    # RAISE EXCEPTION '...', a, b;  -> argumen *.stage / v_stage dibungkus fn_stage_label()
    def rep(m):
        args = re.sub(r'(?<![\w.(])((?:\w+\.)?(?:stage|v_stage))\b', r'fn_stage_label(\1)', m.group(2))
        args = args.replace('fn_stage_label(fn_stage_label(', 'fn_stage_label((')
        return m.group(1) + args + ';'
    return re.sub(r"(RAISE EXCEPTION '(?:[^']|'')*'\s*,)([^;]*);", rep, src)


objs = json.load(open(f'{HERE}/db_objs.json', encoding='utf-8'))
parts, names = [], []
for o in objs:
    d = o['def']
    new = tr_literals(d)
    new = tr_raise(new)
    new = new.replace(' — ', ' - ').replace('—', '-')
    if new != d:
        parts.append(new.rstrip().rstrip(';') + ';\n')
        names.append(o['name'].split('(')[0])
missing = [k for k in MAP if k not in used]

HEAD = """-- ============================================================================
-- R15: teks sistem ke bahasa Inggris + tanpa em dash (13 Okt 2026, keputusan user).
-- Jalankan SETELAH R14_audit_stage.sql, lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aman diulang. Satu transaksi.
--
-- Dibuat otomatis oleh tools/r15/make_r15_sql.py dari definisi fungsi & view setelah R14 (kamus tools/r15/en_db.py).
-- Isi: %d fungsi/view dibuat ulang dengan pesan & label bahasa Inggris. Logika tidak berubah, kecuali:
--   - kode status harga (fn_price_state) jadi bahasa Inggris: BERLAKU -> ACTIVE, AKAN BERLAKU -> UPCOMING,
--     MENUNGGU APPROVAL -> PENDING APPROVAL, DITOLAK -> REJECTED, DIBATALKAN -> CANCELLED, RIWAYAT -> EXPIRED,
--     BELUM ADA HARGA -> NO PRICE (dihitung, tidak tersimpan; app R15 memakai kode baru)
--   - selisih Target FOB: SESUAI -> MATCH
--   - pesan error menyebut stage dengan label (Pullover, Preview, Production)
-- Data yang sudah tersimpan (mis. alasan "Revisi awal." di change log lama) tidak diubah.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_stage_label(text)') IS NULL THEN
    RAISE EXCEPTION 'R14 is not installed. Run sql/R14_audit_stage.sql first.';
  END IF;
END;
$$;

""" % len(parts)
TAIL = """
-- ---------------------------------------------------------------- ringkasan
SELECT 'R15 terpasang' AS cek,
       concat_ws(' · ',
         'price states: ' || (SELECT string_agg(DISTINCT state, ',' ORDER BY state) FROM v_material_price),
         'stage label: ' || fn_stage_label('PROD'),
         'role: ' || fn_role_label('VENDOR_SPEC')) AS hasil;

COMMIT;
"""
text = HEAD + '\n'.join(parts) + TAIL
open(f'{ROOT}/sql/R15_english.sql', 'w', encoding='utf-8', newline='\n').write(text)
print(len(parts), 'objek:', ', '.join(names))
print('kamus tidak terpakai:', missing)
print('em dash tersisa:', text.count('—'))
