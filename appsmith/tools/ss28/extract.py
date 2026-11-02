"""Baca specsheet SS28 (Excel lama, .xls/.xlsx) menjadi data terstruktur.

Dipakai oleh build_mapping.py (workbook pemetaan) dan nanti generator SQL impor.
Tiap file: header model + daftar baris BOM (MAIN = komponen, SUB = sub-baris di bawahnya, INFO = bukan BOM).
"""
import glob
import os
import re

import pandas as pd

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SRC = os.path.join(ROOT, "Specsheet SS28")
REKAP = os.path.join(ROOT, "Rekap Stage Specsheet SS28.xlsx")
SKIP_FILES = {"104 NX .xls"}          # sudah dientri manual

NONE_COLORS = {"", "NONE", "-", "N/A"}


def clean(v):
    s = "" if v is None else str(v)
    s = s.replace("\r", " ").replace("\n", " ").replace(" ", " ")
    s = re.sub(r"\s+", " ", s).strip()
    return "" if s.lower() == "nan" else s


def key(s):
    """Kunci pembanding: huruf besar, tanpa spasi ganda, tanpa spasi di sekitar / ( ) -."""
    s = clean(s).upper()
    s = re.sub(r"\s*([/()\-+])\s*", r"\1", s)
    return s


def _after_label(rows, label, max_look=8):
    """Nilai di kanan sebuah label (lewati ':'), atau di baris bawahnya bila kanan kosong."""
    for ri, r in enumerate(rows):
        for ci, c in enumerate(r):
            if c.upper().startswith(label):
                rest = [x for x in r[ci + 1:ci + 1 + max_look] if x and x != ":"]
                inline = c[len(label):].strip(" :")
                if inline:
                    return inline
                if rest and not rest[0].upper().startswith(("LAST", "CONSTRUCTION", "SIZE", "SAMPLE", "ARTICLE", "PURPOSE")):
                    return rest[0].lstrip(": ").strip()
                if ri + 1 < len(rows) and rows[ri + 1][ci]:
                    return rows[ri + 1][ci].lstrip(": ").strip()
                return ""
    return ""


def _label_value_col(rows, label):
    """Untuk label di kolom tengah (LAST No., CONSTRUCTION, ...): nilai sesudah ':' di baris yang sama."""
    for r in rows:
        for ci, c in enumerate(r):
            if c.upper().startswith(label):
                rest = [x for x in r[ci + 1:ci + 5] if x and x != ":"]
                inline = re.sub(r"^" + re.escape(label) + r"[^:]*:?", "", c, flags=re.I).strip()
                if inline:
                    return inline.lstrip(": ").strip()
                return rest[0].lstrip(": ").strip() if rest else ""
    return ""


def parse_file(path):
    xl = pd.ExcelFile(path)
    df = xl.parse(xl.sheet_names[0], header=None, dtype=str)
    rows = [[clean(v) for v in r] for r in df.values.tolist()]
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]

    hdr = next(i for i, r in enumerate(rows) if any(c.upper() == "COMPONENT NAME" for c in r))
    H = [c.upper() for c in rows[hdr]]
    c_no = 0
    c_comp = H.index("COMPONENT NAME")
    c_sup = next(i for i, c in enumerate(H) if c.startswith("SOURCE"))
    c_desc_hdr = next((i for i, c in enumerate(H) if c.startswith("MATERIAL DESC")), None)
    # kolom UoM: judul MATERIAL / UNIT OF MSRMNT di header atau 1-2 baris di bawahnya
    sub_h = [[c.upper() for c in rows[hdr + k]] for k in (0, 1, 2)]
    c_uom = next((i for i in range(c_sup + 1, width)
                  if any(h[i] in ("MATERIAL", "UNIT OF MSRMNT") or h[i].startswith("UNIT OF") for h in sub_h)), None)
    c_proc = next((i for i in range(c_sup + 1, width) if any(h[i] == "PROCESS" for h in sub_h)), None)
    first = hdr + 1
    while first < len(rows) and not re.fullmatch(r"\d+", rows[first][c_no]):
        first += 1
    # kolom article: berjudul colorway, atau tanpa judul tapi berisi warna di baris BOM
    art_end = c_uom if c_uom else (c_proc if c_proc else width)
    art_cols = [i for i in range(c_sup + 1, art_end)
                if rows[hdr][i] or any(r[i] for r in rows[first:])]
    articles = [rows[hdr][i] for i in art_cols]

    # kolom deskripsi material: judul bila ada, kalau tidak kolom pertama terisi sesudah nama komponen
    if c_desc_hdr is None:
        cnt = {}
        for r in rows[first:]:
            for i in range(c_comp + 1, c_sup):
                if r[i]:
                    cnt[i] = cnt.get(i, 0) + 1
                    break
        c_desc = max(cnt, key=cnt.get)
    else:
        c_desc = c_desc_hdr

    head = rows[:hdr]
    info = {
        "file": os.path.basename(path),
        "model_excel": _after_label(head, "MODEL NAME"),
        "category": _after_label(head, "CATEGORY"),
        "outsole_mould": _after_label(head, "OUTSOLE MOULD"),
        "last": _label_value_col(head, "LAST NO"),
        "construction": _label_value_col(head, "CONSTRUCTION"),
        "size_range": _label_value_col(head, "SIZE RANGE"),
        "sample_size": _label_value_col(head, "SAMPLE SIZE"),
        "revision": (_after_label(head, "REVISION") or _after_label(head, "DATE"))[:10],
        "articles": articles,
        "lines": [],
        "info_rows": [],
    }
    # nomor article: teks di bawah label ARTICLE / ARTIKEL NO. pada kolom article (kolom 0 = outsole mould)
    info["article_codes"] = [""] * len(art_cols)
    for ri, r in enumerate(head):
        for ci, c in enumerate(r):
            if re.match(r"ARTI(CLE|KEL) NO", c.upper()) and ri + 1 < len(rows):
                info["article_codes"] = [rows[ri + 1][i] for i in art_cols]

    in_info = False
    seq = 0
    last_main = None
    for ri in range(first, len(rows)):
        r = rows[ri]
        no = r[c_no]
        comp = " ".join(x for x in r[c_comp:c_desc] if x).strip()
        desc = " ".join(x for x in r[c_desc:c_sup] if x).strip()
        sup = r[c_sup]
        colors = [r[i] for i in art_cols]
        uom = r[c_uom] if c_uom is not None else ""
        proc = r[c_proc] if c_proc is not None else ""
        if not any([no, comp, desc, sup, uom, proc] + colors):
            continue
        u = (comp + " " + desc).upper()
        if "KOMPOSISI MATERIAL" in u:
            in_info = True
            info["info_rows"].append({"row": ri + 1, "label": "Komposisi Material", "values": colors})
            continue
        if in_info and not re.fullmatch(r"\d+", no) and desc.upper().startswith("BAGIAN"):
            info["info_rows"].append({"row": ri + 1, "label": desc, "values": colors})
            continue
        in_info = False
        seq += 1
        if re.fullmatch(r"\d+", no) or comp:
            kind = "MAIN"
        else:
            kind = "SUB"
        line = {
            "seq": seq, "row": ri + 1, "kind": kind, "no": no, "component": comp,
            "material": desc, "supplier": sup, "uom_raw": uom, "process": proc, "colors": colors,
        }
        if kind == "MAIN":
            last_main = line
            line["parent_seq"] = None
        else:
            line["parent_seq"] = last_main["seq"] if last_main else None
            # sub-baris tanpa material (mis. Carton Box ukuran lain) = material induk
            if not desc and last_main:
                line["material"] = last_main["material"]
                line["material_from_parent"] = True
                if not sup:
                    line["supplier"] = last_main["supplier"]
        info["lines"].append(line)
    return info


# ---------------------------------------------------------------- saran nilai sistem
_THK = re.compile(r"^\s*(\d+(?:[.,]\d+)?)\s*mm\b\.?\s*", re.I)
_LEN = re.compile(r"\(\s*(\d+(?:[.,]\d+)?)\s*cm\s*\)\s*$", re.I)
_WIDTH_UOM = re.compile(r'^\s*(\d+(?:[.,]\d+)?)\s*(?:"|\'\'|”|inch)?\s*([A-Z]+)\s*$', re.I)


def num(s):
    s = s.replace(",", ".")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s


def suggest(material_text, uom_raw):
    """Saran nama material, Dimension, UoM dari teks Excel (format Dimension mengikuti fn_clean_thickness)."""
    t = clean(material_text)
    thk = None
    m = _THK.match(t)
    if m:
        thk = num(m.group(1)) + " MM"
        t = t[m.end():]
    length = None
    m = _LEN.search(t)
    if m and thk:
        length = num(m.group(1)) + " CM"
        t = t[:m.start()].strip()
    uom = clean(uom_raw).upper()
    width = None
    m = _WIDTH_UOM.match(uom)
    if m:
        width = num(m.group(1)) + '"'
        uom = m.group(2).upper()
    dims = [d for d in (thk, width or length) if d]
    name = re.sub(r"\s+", " ", t).strip(" -").upper()
    return {"name": name, "dimension": " X ".join(dims), "uom": uom}


def load_rekap():
    df = pd.read_excel(REKAP, sheet_name="Rekap Stage", header=1, dtype=str).fillna("")
    out = {}
    for _, r in df.iterrows():
        out[clean(r["Nama File"])] = {
            "model": clean(r["Model Name"]), "type": clean(r["FG / IN / TF"]), "junior": clean(r["Junior"]),
            "stage": clean(r["Stage di Sistem"]), "status": clean(r["Status"]), "ticked": clean(r["Yang Dicentang"]),
        }
    return out


def load_all(include_skipped=False):
    files = sorted(glob.glob(os.path.join(SRC, "*.xls*")))
    out = []
    for f in files:
        if not include_skipped and os.path.basename(f) in SKIP_FILES:
            continue
        out.append(parse_file(f))
    return out


if __name__ == "__main__":
    import sys
    for d in load_all():
        if len(sys.argv) > 1 and sys.argv[1].upper() not in d["file"].upper():
            continue
        m = sum(1 for l in d["lines"] if l["kind"] == "MAIN")
        s = sum(1 for l in d["lines"] if l["kind"] == "SUB")
        print(f'{d["file"][:40]:40} model={d["model_excel"]!r:32} art={len(d["articles"])} main={m} sub={s} '
              f'cat={d["category"]!r} last={d["last"]!r} cons={d["construction"]!r} mould={d["outsole_mould"]!r} '
              f'size={d["size_range"]!r} sample={d["sample_size"]!r} rev={d["revision"]} info={len(d["info_rows"])}')
