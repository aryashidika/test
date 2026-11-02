"""Buat workbook pemetaan SS28: document/Migrasi SS28/Pemetaan_SS28.xlsx

  python build_mapping.py            -> workbook dari Excel SS28 (+ master bila ada)
Master dari database (opsional) dibaca dari document/Migrasi SS28/master/*.json, hasil query di Claude Doc
"Migrasi Specsheet SS28": material.json, supplier.json, component.json, model_option.json, model.json.
Kolom kuning = diisi / dikoreksi tim. Kolom lain = dari Excel atau saran otomatis.
"""
import collections
import difflib
import json
import os
import re

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.datavalidation import DataValidation

import extract

OUT_DIR = os.path.join(extract.ROOT, "document", "Migrasi SS28")
OUT = os.path.join(OUT_DIR, "Pemetaan_SS28.xlsx")
MASTER_DIR = os.path.join(OUT_DIR, "master")
PILOT = {"RAIDEN FG SS 28.xlsx", "RAIDEN IN SS 28.xlsx"}

FILL_IN = PatternFill("solid", fgColor="FFF2CC")      # diisi tim
FILL_HDR = PatternFill("solid", fgColor="1F3864")
FILL_WARN = PatternFill("solid", fgColor="F8CBAD")
FONT_HDR = Font(bold=True, color="FFFFFF")

PROCESS_WORDS = ("DECORATION", "SINGLE STICKER", "SINGLE STIKER", "STICKER", "COATING", "PRINT", "EMBOSS", "DEBOSS",
                 "PERFORAT", "PERPORAT", "LASER", "WELDING", "HF ", "HIGH FREQ", "EMBROID", "BORDIR", "PUNCH",
                 "STITCH", "LAMINAT")

# Master Komponen standar (R_impor_komponen.sql); dipakai bila component.json belum ada
STD_COMPONENTS = [
    "UPPER", "UPPER OVERLAY", "UPPER UNDERLAY", "UPPER LINING", "UPPER FOAM", "TONGUE", "TONGUE BACKER",
    "TONGUE COLLAR", "TONGUE LOGO", "COLLAR LINING", "COLLAR FOAM", "COLLAR FOAM BACKER", "COLLAR REINF IN",
    "COLLAR REINF OUT", "EYESTAY REINF", "VAMP LINING", "HEEL PATCH", "TOE BOX", "NO SEW", "PLASTIC PADDING",
    "PUNCH HOLE", "VAMP", "QUARTER", "EYELET", "HEEL TAB", "SOCKLINER COVER", "SOCKLINER DIE CUT", "SOCKLINER LOGO",
    "CUP INSOLE", "INSOLE", "HEEL COUNTER", "MIDSOLE", "MIDSOLE INSERT", "OUTSOLE", "INSOLE BOARD", "STROBEL BOARD",
    "SHANK", "CLEAT", "INNER BOX", "CARTON BOX", "STICKER INNER BOX", "ISOLATAPE", "WRAPPING PAPER", "TISSUE PAPER",
    "SILICA GEL", "STRING PIN", "HANGTAG PRICE", "SHOE BAG", "BARCODE STICKER", "CARTON STICKER", "CEMENT UPPER",
    "CEMENT ASSEMBLING", "CEMENT STOCKFIT", "SHOE LACE", "SEWING THREAD", "STROBEL THREAD", "THREAD VARIANCE",
    "SIZE LABEL", "PRIMER", "CARE LABEL",
]
COMPONENT_ALIAS = {
    "SHOE LACES": "SHOE LACE", "THREAD STROBLE": "STROBEL THREAD", "STROBLE THREAD": "STROBEL THREAD",
    "HANGTAG PRICE NEW": "HANGTAG PRICE", "HANG TAG PRICE": "HANGTAG PRICE", "HEEL PACTH": "HEEL PATCH",
    "COLLAR LINLING": "COLLAR LINING", "SOCKLINER DIECUT": "SOCKLINER DIE CUT", "STRING PIN": "STRING PIN",
}


def tight(s):
    return re.sub(r"[^A-Z0-9]", "", extract.clean(s).upper())


def load_master(name):
    p = os.path.join(MASTER_DIR, name)
    if not os.path.exists(p):
        return None
    with open(p, encoding="utf-8-sig") as f:
        return json.load(f)


# ---------------------------------------------------------------- saran
def suggest_component(text, master_names):
    t = extract.clean(text).upper()
    base = re.sub(r"\(.*?\)", " ", t)                       # INSOLE ( C/D ALPHA NERVE ) -> INSOLE
    base = re.sub(r"\b(PRM|PLM)\s*-?\s*\d+\w*", " ", base)   # OUTSOLE PRM-112 -> OUTSOLE
    base = re.sub(r"\s+", " ", base).strip(" -")
    base = COMPONENT_ALIAS.get(base, base)
    by_tight = {tight(n): n for n in master_names}
    if tight(base) in by_tight:
        return by_tight[tight(base)], "sama"
    # awalan: COLLAR REINF IN / OUT -> COLLAR REINF IN; INSOLE C/D CADANCE -> INSOLE
    for n in sorted(master_names, key=len, reverse=True):
        if tight(base).startswith(tight(n)) and len(tight(n)) >= 4:
            return n, "awalan"
    m = difflib.get_close_matches(tight(base), list(by_tight), n=1, cutoff=0.88)
    if m:
        return by_tight[m[0]], "mirip"
    return "", ""


def cluster_suppliers(counter, master_names):
    """Kelompokkan ejaan supplier. Kanonik = nama di master (bila ada), kalau tidak ejaan terbanyak."""
    groups = []
    for name, n in counter.most_common():
        k = tight(name)
        for g in groups:
            if k == g["key"] or k.startswith(g["key"]) and len(g["key"]) >= 4 \
                    or difflib.SequenceMatcher(None, k, g["key"]).ratio() >= 0.85:
                g["names"].append(name)
                break
        else:
            groups.append({"key": k, "names": [name]})
    out = {}
    for g in groups:
        canon = g["names"][0]
        hit = None
        for x in g["names"]:
            hit = match_supplier(x, master_names or [])
            if hit:
                break
        for x in g["names"]:
            out[x] = (hit or canon, bool(hit))
    return out


_LEGAL = re.compile(r"\b(PT|CV|PD|TBK|UD)\b\.?", re.I)


def supplier_core(name):
    s = _LEGAL.sub(" ", extract.clean(name).upper().replace(",", " ").replace(".", " "))
    return re.sub(r"\s+", " ", s).strip()


# keputusan user 28 Okt 2026
SUPPLIER_ALIAS = {"UMK": "UNIMITRA KHARISMA, PT", "PENTABIZ": "IMCO SILICA", "PENTABIZINTERNATIONAL": "IMCO SILICA"}


def match_supplier(text, master_names):
    """KINDO -> KINDO MAKMUR JAYA,PT; MKU -> MULTI KARYA USAHA, PT; WIN FAITH -> WINFAITH,PT."""
    k = tight(supplier_core(text))
    if k in SUPPLIER_ALIAS and SUPPLIER_ALIAS[k] in master_names:
        return SUPPLIER_ALIAS[k]
    if not k:
        return None
    best = None
    for m in master_names:
        core = supplier_core(m)
        ck = tight(core)
        words = [w for w in core.split() if w]
        acro = "".join(w[0] for w in words)
        if ck == k:
            return m
        if ck.startswith(k) and len(k) >= 4 and best is None:
            best = m
        elif acro == k and len(k) >= 3 and best is None:
            best = m
    if best:
        return best
    by = {tight(supplier_core(m)): m for m in master_names}
    c = difflib.get_close_matches(k, list(by), n=1, cutoff=0.86)
    return by[c[0]] if c else None


# ---------------------------------------------------------------- pencocokan material
_SPELL = {"SHYNTETIC": "SYNTHETIC", "SYNTETIC": "SYNTHETIC", "SUPERLIGHT": "SUPER LIGHT", "HYSOCK": "HY SOCK",
          "PERPORATED": "PERFORATED", "STIKER": "STICKER", "TRANSPAPER": "TRANSFER PAPER", "SILICAGEL": "SILICA GEL",
          "INER": "INNER", "KWALITAS": "KUALITAS"}
_STOP = {"MM", "CM", "X", "SPECS", "STANDARD", "NEW", "THE", "AND", "SEE", "DRAWING", "SESUAI", "ART", "WORK",
         "BACKING", "DECORATION", "DECO", "W"}


def mat_tokens(s):
    t = extract.clean(s).upper().replace("�", " ")
    t = re.sub(r"\d+(?:[.,]\d+)?\s*(MM|CM|\"|INCH)\b", " ", t)      # ketebalan / lebar
    t = re.sub(r"\bX\s*\d+(?:[.,]\d+)?\"?", " ", t)
    t = re.sub(r"[^A-Z0-9]+", " ", t)
    t = re.sub(r"(?<=\d)(?=[A-Z])|(?<=[A-Z])(?=\d)", " ", t)          # 50KG -> 50 KG, NSL0207 -> NSL 0207
    words = []
    for w in t.split():
        w = _SPELL.get(w, w)
        words.extend(w.split())
    return [w for w in words if w not in _STOP and not (len(w) == 1 and not w.isdigit())]


_THK_ANY = re.compile(r"(\d+(?:[.,]\d+)?)\s*MM\b")


def thickness_of(s):
    m = _THK_ANY.search(extract.clean(s).upper())
    return extract.num(m.group(1)) if m else None


def match_material(text, materials, n=2):
    """Kandidat material master terbaik: kemiripan kata (tanpa ketebalan / lebar) + kemiripan huruf.
    Hasil: [(skor, material, kata Excel yang tidak ada di master)]."""
    q = mat_tokens(text)
    if not q:
        return []
    qs = set(q)
    qn = {w for w in qs if w.isdigit()}
    qk = "".join(q)
    qt = thickness_of(text)
    scored = []
    for m in materials:
        mt = m.setdefault("_tok", mat_tokens(m["name"]))
        if not mt:
            continue
        ms = set(mt)
        inter = len(qs & ms)
        if not inter:
            continue
        cover = inter / len(qs)                   # berapa kata Excel ditemukan di master
        prec = inter / len(ms)
        ratio = difflib.SequenceMatcher(None, qk, "".join(mt)).ratio()
        score = 0.45 * cover + 0.25 * prec + 0.30 * ratio
        score -= 0.05 * len(qn - ms)              # angka beda (mis. hardness 45-50 vs 40-45)
        mtk = thickness_of(m["name"])
        if qt and mtk:                            # ketebalan di nama master: sama = lebih cocok
            score += 0.08 if qt == mtk else -0.08
        if m.get("status") != "ACTIVE":
            score -= 0.1
        scored.append((score, m, sorted(qs - ms)))
    scored.sort(key=lambda x: -x[0])
    return [(round(min(s, 1.0), 2), m, miss) for s, m, miss in scored[:n] if s >= 0.5]


def match_option(text, values, kind):
    """Saran Master Options: sama persis (tanpa spasi / tanda baca), awalan, atau kata kunci."""
    t = tight(text)
    if not t:
        return "", ""
    by = {tight(v): v for v in values}
    if t in by:
        return by[t], "sama"
    if kind in ("LAST", "OUTSOLE_MOLD"):
        # PRL 023 MID -> PRL-023; PRM- 112 -> PRM-112 (JR / TF ikut dibandingkan)
        for v in sorted(values, key=lambda v: -len(tight(v))):
            if t.startswith(tight(v)):
                rest = t[len(tight(v)):]
                if rest in ("JR", "TF", "TR") or (("JR" in t) == ("JR" in tight(v))):
                    return v, "awalan, sisa '" + rest + "'" if rest else "sama"
        return "", ""
    words = set(re.findall(r"[A-Z]+", extract.clean(text).upper()))
    best = ("", 0)
    for v in values:
        vw = set(re.findall(r"[A-Z]+", v.upper()))
        sc = len(words & vw) / max(len(words | vw), 1)
        if any(a.startswith(b) or b.startswith(a) for a in words for b in vw if min(len(a), len(b)) >= 4):
            sc += 0.2
        if sc > best[1]:
            best = (v, sc)
    return (best[0], "mirip") if best[1] >= 0.5 else ("", "")


def classify_sub(line, parent):
    """Usulan perlakuan sub-baris."""
    u = extract.clean(line["material"]).upper()
    if line.get("material_from_parent"):
        return "BAGIAN (material induk)"
    if any(u.startswith(w) for w in PROCESS_WORDS):
        return "PROCESS"
    pc = extract.clean(parent["component"]).upper() if parent else ""
    if re.search(r"\bSIZE\s*\d", u) and ("BOX" in pc):
        return "BAGIAN (material induk)"
    # bagian outsole / midsole (Base, Stud, Logo) dan sub tanpa supplier: material + supplier induk
    if not line["supplier"] and ("SOLE" in pc or not line["uom_raw"]):
        return "BAGIAN (material induk)"
    return "MATERIAL SENDIRI"


def sizes_from_range(s):
    nums = [int(x) for x in re.findall(r"\d+", s or "")]
    if len(nums) >= 2:
        return f"{min(nums)}-{max(nums)}"
    return ""


# ---------------------------------------------------------------- workbook helper
def sheet(wb, title, headers, widths, input_cols=()):
    ws = wb.create_sheet(title)
    ws.append(headers)
    for i, h in enumerate(headers, 1):
        c = ws.cell(row=1, column=i)
        c.fill = FILL_HDR
        c.font = FONT_HDR
        c.alignment = Alignment(wrap_text=True, vertical="center")
        ws.column_dimensions[get_column_letter(i)].width = widths[i - 1] if i - 1 < len(widths) else 14
    ws.freeze_panes = "B2"
    ws.row_dimensions[1].height = 32
    ws._input_cols = [headers.index(h) + 1 for h in input_cols]
    return ws


def finish(ws):
    for col in ws._input_cols:
        for r in range(2, ws.max_row + 1):
            ws.cell(row=r, column=col).fill = FILL_IN
    ws.auto_filter.ref = ws.dimensions


def add_list(ws, col_name, values, headers):
    col = get_column_letter(headers.index(col_name) + 1)
    dv = DataValidation(type="list", formula1='"' + ",".join(values) + '"', allow_blank=True)
    ws.add_data_validation(dv)
    dv.add(f"{col}2:{col}{max(ws.max_row, 2)}")


def main():
    files = extract.load_all()
    rekap = extract.load_rekap()
    m_comp = load_master("component.json")
    m_sup = load_master("supplier.json")
    m_mat = load_master("material.json")
    m_opt = load_master("model_option.json")
    m_model = load_master("model.json")
    comp_names = [c["name"] for c in m_comp] if m_comp else STD_COMPONENTS
    comp_no = {c["name"]: c.get("number") for c in m_comp} if m_comp else {}
    sup_names = [s["name"] for s in m_sup] if m_sup else []
    opt_vals = collections.defaultdict(list)
    for o in m_opt or []:
        if o.get("status", "ACTIVE") == "ACTIVE":
            opt_vals[o["kind"]].append(o["value"])
    existing_models = {tight(m["name"]) for m in (m_model or [])}

    def opt(text, kind):
        if not m_opt:
            return ""
        v, how = match_option(text, opt_vals[kind], kind)
        if not v:
            return "(baru)" if text else ""
        return v if how == "sama" else f"{v} [{how}]"

    wb = Workbook()
    ws0 = wb.active
    ws0.title = "Petunjuk"
    master_note = ("Master dari database: SUDAH dimuat." if m_mat else
                   "Master dari database BELUM dimuat: kolom 'di master' masih kosong. Jalankan query master di "
                   "Claude Doc 'Migrasi Specsheet SS28', lalu workbook ini dibuat ulang.")
    lines = [
        "Workbook pemetaan migrasi Specsheet SS28 (Excel lama ke sistem).",
        "",
        "Kolom kuning = diisi atau dikoreksi tim. Kolom lain berasal dari Excel atau saran otomatis, jangan diubah.",
        "Kolom 'Pakai' kosong = memakai saran di sebelahnya, KECUALI sheet Material: Material (Pakai) wajib diisi",
        "(nama material master persis, atau nama material baru). Kandidat master hanya saran: cek kolom",
        "'Kata Excel tidak ada di kandidat 1' (oranye = perlu dicek).",
        master_note,
        "",
        "Urutan pengisian:",
        "1. Model: cek nama model, stage, dan isi Category / Gender yang kosong. Kolom Impor = Tidak untuk file yang dilewati.",
        "2. Article: cek colorway, isi nomor article bila sudah ada (boleh kosong).",
        "3. Supplier: cek nama seragam. Supplier yang belum ada di master harus dibuat dulu di Master Supplier.",
        "4. Komponen: pilih komponen master untuk setiap ejaan di Excel.",
        "5. Material: tentukan nama material, Dimension, UoM, dan tanda Process. Satu baris = satu teks di Excel.",
        "6. Baris: daftar lengkap semua baris BOM per file (untuk dicek). Kolom 'Perlakuan sub' bisa dikoreksi.",
        "7. Masalah: hal yang perlu keputusan sebelum impor (supplier kosong, material kosong, dan lain-lain).",
        "",
        "Pilot: RAIDEN FG dan RAIDEN IN (kolom Pilot = Ya di sheet Model). Isi sheet lain cukup untuk baris yang",
        "dipakai kedua file itu dulu (filter kolom 'Pilot' = Ya).",
        "",
        "Aturan yang dipakai saran otomatis:",
        "- Ketebalan di depan teks material (mis. '1,2mm') pindah ke Dimension: '1.2 MM'.",
        "- Kolom UoM '54\" XM' = lebar 54\" (masuk Dimension) dan UoM XM. Contoh Dimension: 1.2 MM X 54\".",
        "- Panjang tali '( 115 Cm )' masuk Dimension: 6 MM X 115 CM.",
        "- Sub-baris Decoration / Single Sticker / Coating / Punch = material Process (tanpa Material Code).",
        "- Sub-baris bagian outsole / midsole (Base, Stud, Logo) dan ukuran inner box / carton box = material dan",
        "  supplier induk; teksnya menjadi nama sub-baris.",
        "- Warna 'None' / 'none' = baris dipakai tanpa warna (mis. Punch hole, Single Sticker).",
        "- Kolom Process di Excel (Laminating, Coating) masuk kolom Process baris BOM sebagai teks.",
    ]
    for l in lines:
        ws0.append([l])
    ws0.column_dimensions["A"].width = 120
    ws0["A1"].font = Font(bold=True, size=13)

    # ------------------------------------------------ Model
    H = ["File", "Pilot", "Impor", "Nama model (usulan)", "Nama model (Pakai)", "Nama di Excel", "Sudah ada di sistem",
         "FG / IN / TF", "Junior",
         "Category (Excel)", "Category (master)", "Category (Pakai)",
         "Gender (master)", "Gender (Pakai)",
         "Construction (Excel)", "Construction (master)", "Construction (Pakai)",
         "Last (Excel)", "Last (master)", "Last (Pakai)",
         "Outsole mold (Excel)", "Outsole mold (master)", "Outsole mold (Pakai)",
         "Size range (Excel)", "Ukuran (usulan)", "Sample size", "Season",
         "Stage (Rekap)", "Stage (Pakai)", "Tanggal revisi", "Article", "Baris utama", "Sub-baris", "Catatan"]
    ws = sheet(wb, "Model", H, [34, 7, 7, 30, 24, 30, 10, 8, 7, 20, 18, 14, 10, 10, 20, 22, 16, 14, 18, 12, 14, 18,
                                12, 14, 10, 8, 8, 12, 12, 12, 7, 8, 8, 30],
               ["Impor", "Nama model (Pakai)", "Category (Pakai)", "Gender (Pakai)", "Construction (Pakai)",
                "Last (Pakai)", "Outsole mold (Pakai)", "Stage (Pakai)", "Catatan"])
    for d in files:
        rk = rekap.get(d["file"], {})
        name = rk.get("model") or d["model_excel"]
        note = []
        if rk.get("status") and rk["status"] != "Sudah ada stage":
            note.append(rk["status"])
        if len(d["articles"]) > 5:
            note.append("article > 5")
        junior = rk.get("junior", "") == "Ya"
        gender = ("JR" if junior else "") if m_opt else ""
        ws.append([
            d["file"], "Ya" if d["file"] in PILOT else "", "Ya", name, "", d["model_excel"],
            ("Ya" if tight(name) in existing_models else "Tidak") if m_model is not None else "",
            rk.get("type", ""), rk.get("junior", ""),
            d["category"], opt(d["category"], "KATEGORI"), "",
            gender, "",
            d["construction"], opt(d["construction"], "CONSTRUCTION"), "",
            d["last"], opt(d["last"], "LAST"), "",
            d["outsole_mould"], opt(d["outsole_mould"], "OUTSOLE_MOLD"), "",
            d["size_range"], sizes_from_range(d["size_range"]), d["sample_size"], "SS28",
            rk.get("stage", ""), "", d["revision"], len(d["articles"]),
            sum(1 for l in d["lines"] if l["kind"] == "MAIN"), sum(1 for l in d["lines"] if l["kind"] == "SUB"),
            "; ".join(note),
        ])
        for col in ("Category (master)", "Construction (master)", "Last (master)", "Outsole mold (master)"):
            c = ws.cell(row=ws.max_row, column=H.index(col) + 1)
            if c.value and ("baru" in c.value or "[" in c.value):
                c.fill = FILL_WARN
    add_list(ws, "Impor", ["Ya", "Tidak"], H)
    add_list(ws, "Stage (Pakai)", ["Pullover", "Preview", "SMS", "GTM", "Production"], H)
    finish(ws)

    # ------------------------------------------------ Article
    H = ["File", "Pilot", "Model", "Kolom", "Colorway (Excel)", "Colorway (Pakai)", "Nomor article (Excel)",
         "Nomor article (Pakai)"]
    ws = sheet(wb, "Article", H, [34, 7, 30, 7, 40, 30, 18, 18], ["Colorway (Pakai)", "Nomor article (Pakai)"])
    for d in files:
        name = rekap.get(d["file"], {}).get("model") or d["model_excel"]
        for i, a in enumerate(d["articles"]):
            ws.append([d["file"], "Ya" if d["file"] in PILOT else "", name, i + 1, a or f"(kolom {i + 1} tanpa judul)",
                       "", d["article_codes"][i] if i < len(d["article_codes"]) else "", ""])
    finish(ws)

    # ------------------------------------------------ kumpulkan pemakaian
    comp_use = collections.OrderedDict()
    sup_count = collections.Counter()
    sup_files = collections.defaultdict(set)
    mat_use = collections.OrderedDict()
    proc_use = collections.Counter()
    for d in files:
        pilot = d["file"] in PILOT
        by_seq = {l["seq"]: l for l in d["lines"]}
        for l in d["lines"]:
            parent = by_seq.get(l["parent_seq"])
            l["treat"] = "" if l["kind"] == "MAIN" else classify_sub(l, parent)
            if l["kind"] == "SUB" and not l["supplier"] and parent and l["treat"].startswith("BAGIAN"):
                l["supplier"] = parent["supplier"]
                l["supplier_from_parent"] = True
            if l["kind"] == "MAIN":
                k = extract.key(l["component"])
                u = comp_use.setdefault(k, {"text": l["component"], "n": 0, "files": set(), "pilot": False})
                u["n"] += 1
                u["files"].add(d["file"])
                u["pilot"] |= pilot
            if l["supplier"]:
                sup_count[extract.clean(l["supplier"]).upper()] += 1
                sup_files[extract.clean(l["supplier"]).upper()].add((d["file"], pilot))
            if l["process"]:
                proc_use[extract.clean(l["process"]).upper()] += 1
            if l["material"] and not l["treat"].startswith("BAGIAN"):
                s = extract.suggest(l["material"], l["uom_raw"])
                mk = (extract.key(l["material"]), s["uom"])
                u = mat_use.setdefault(mk, {"text": l["material"], "uom_raw": l["uom_raw"], "sug": s, "n": 0,
                                            "files": set(), "comps": collections.Counter(),
                                            "sups": collections.Counter(), "kind": collections.Counter(),
                                            "pilot": False, "proc": False})
                u["n"] += 1
                u["files"].add(d["file"])
                u["pilot"] |= pilot
                u["kind"][l["kind"] if l["kind"] == "MAIN" else l["treat"]] += 1
                u["proc"] |= l["treat"] == "PROCESS"
                parent_comp = l["component"] if l["kind"] == "MAIN" else (parent["component"] if parent else "")
                u["comps"][extract.clean(parent_comp).upper()] += 1
                if l["supplier"]:
                    u["sups"][extract.clean(l["supplier"]).upper()] += 1

    # ------------------------------------------------ Supplier
    canon = cluster_suppliers(sup_count, sup_names)
    H = ["Teks di Excel", "Pilot", "Dipakai (baris)", "Jumlah file", "Usulan nama seragam", "Ada di master",
         "Supplier (Pakai)", "Catatan"]
    ws = sheet(wb, "Supplier", H, [30, 7, 10, 10, 30, 10, 30, 30], ["Supplier (Pakai)", "Catatan"])
    for name, n in sorted(sup_count.items(), key=lambda x: (canon[x[0]][0], -x[1])):
        c, in_master = canon[name]
        ws.append([name, "Ya" if any(p for _, p in sup_files[name]) else "", n, len({f for f, _ in sup_files[name]}),
                   c, ("Ya" if in_master else "Tidak") if m_sup is not None else "", "", ""])
    finish(ws)

    # ------------------------------------------------ Komponen
    H = ["Teks di Excel", "Pilot", "Dipakai (baris)", "Jumlah file", "Usulan komponen master", "Cocok",
         "Nomor master", "Komponen (Pakai)", "Catatan"]
    ws = sheet(wb, "Komponen", H, [40, 7, 10, 10, 28, 9, 10, 28, 30], ["Komponen (Pakai)", "Catatan"])
    for k, u in sorted(comp_use.items(), key=lambda x: x[0]):
        s, how = suggest_component(u["text"], comp_names)
        ws.append([extract.clean(u["text"]).upper(), "Ya" if u["pilot"] else "", u["n"], len(u["files"]), s, how,
                   comp_no.get(s, ""), "", ""])
    finish(ws)

    # ------------------------------------------------ Material
    H = ["Teks di Excel", "UoM di Excel", "Pilot", "Jenis", "Dipakai (baris)", "Jumlah file", "Komponen (contoh)",
         "Supplier (terbanyak)", "Usulan nama (dari Excel)", "Usulan Dimension", "Usulan Process",
         "Kandidat master 1", "Skor 1", "Kata Excel tidak ada di kandidat 1", "UoM master 1", "Process master 1",
         "Dimension di master 1", "Kandidat master 2", "Skor 2",
         "Material (Pakai)", "Dimension (Pakai)", "UoM (Pakai)", "Process (Pakai)", "Catatan"]
    ws = sheet(wb, "Material", H, [48, 10, 7, 14, 8, 7, 26, 18, 40, 16, 8, 44, 6, 20, 8, 8, 22, 40, 6,
                                   36, 16, 9, 9, 30],
               ["Material (Pakai)", "Dimension (Pakai)", "UoM (Pakai)", "Process (Pakai)", "Catatan"])
    mats = [m for m in (m_mat or [])]
    for (k, uom), u in sorted(mat_use.items(), key=lambda x: (x[1]["sug"]["name"], x[0][1])):
        s = u["sug"]
        cands = match_material(u["text"], mats) if mats else []
        c1 = cands[0] if cands else (None, None, [])
        c2 = cands[1] if len(cands) > 1 else (None, None, [])
        kind = ", ".join(f"{a}" for a, _ in u["kind"].most_common())
        ws.append([extract.clean(u["text"]), u["uom_raw"], "Ya" if u["pilot"] else "", kind, u["n"], len(u["files"]),
                   ", ".join(c for c, _ in u["comps"].most_common(3)),
                   u["sups"].most_common(1)[0][0] if u["sups"] else "",
                   s["name"], s["dimension"], "Ya" if u["proc"] else "",
                   c1[1]["name"] if c1[1] else ("(tidak ada, material baru)" if mats else ""), c1[0] or "",
                   ", ".join(c1[2]), c1[1]["uom"] if c1[1] else "", ("Ya" if c1[1]["is_process"] else "") if c1[1] else "",
                   (c1[1].get("dimensions") or "") if c1[1] else "",
                   c2[1]["name"] if c2[1] else "", c2[0] or "",
                   "", "", "", "", ""])
        if c1[0] is not None and (c1[0] < 0.7 or c1[2]):
            ws.cell(row=ws.max_row, column=H.index("Kandidat master 1") + 1).fill = FILL_WARN
    add_list(ws, "Process (Pakai)", ["Ya", "Tidak"], H)
    finish(ws)

    # ------------------------------------------------ Process (kolom)
    H = ["Isi kolom Process di Excel", "Dipakai (baris)", "Usulan", "Process (Pakai)", "Catatan"]
    ws = sheet(wb, "Process", H, [40, 10, 34, 30, 40], ["Process (Pakai)", "Catatan"])
    for p, n in proc_use.most_common():
        if re.search(r"\d+\s*CM", p):
            sug = "Catatan panjang tali (bukan Process)"
        elif any(w in p for w in ("COATING", "LAMINAT", "STAMPING", "PRINT", "EMBOSS", "WELD")):
            sug = "Process: " + p
        else:
            sug = "Bukan Process (salah kolom?)"
        ws.append([p, n, sug, "", ""])
    finish(ws)

    # ------------------------------------------------ Baris + Masalah
    max_art = max(len(d["articles"]) for d in files)
    H = (["File", "Pilot", "Urut", "Baris Excel", "Jenis", "No", "Komponen", "Teks material", "Supplier", "UoM",
          "Process", "Perlakuan sub", "Induk (urut)"] + [f"Warna {i + 1}" for i in range(max_art)] + ["Catatan"])
    ws = sheet(wb, "Baris", H, [30, 7, 6, 7, 6, 5, 26, 44, 18, 9, 14, 20, 8] + [22] * max_art + [30],
               ["Perlakuan sub", "Catatan"])
    issues = []
    for d in files:
        pilot = "Ya" if d["file"] in PILOT else ""
        for l in d["lines"]:
            note = []
            if l.get("material_from_parent"):
                note.append("material = induk")
            if l.get("supplier_from_parent"):
                note.append("supplier = induk")
            ws.append([d["file"], pilot, l["seq"], l["row"], l["kind"], l["no"], l["component"], l["material"],
                       l["supplier"], l["uom_raw"], l["process"], l["treat"], l["parent_seq"] or ""]
                      + l["colors"] + [""] * (max_art - len(l["colors"])) + ["; ".join(note)])
            r = ws.max_row
            if not l["material"]:
                issues.append([d["file"], pilot, l["row"], "Material kosong", l["component"]])
            if not l["supplier"] and not l["treat"].startswith("BAGIAN"):
                issues.append([d["file"], pilot, l["row"], "Supplier kosong", l["component"] or l["material"]])
                ws.cell(row=r, column=9).fill = FILL_WARN
            if "�" in l["material"]:
                issues.append([d["file"], pilot, l["row"], "Karakter rusak di teks material (mis. ±)", l["material"]])
            if l["kind"] == "MAIN" and not l["no"]:
                issues.append([d["file"], pilot, l["row"], "Komponen tanpa nomor (dibuat baris utama)", l["component"]])
            has_sub = any(x["parent_seq"] == l["seq"] for x in d["lines"])
            if l["kind"] == "MAIN" and not has_sub and not any(extract.clean(c) for c in l["colors"]):
                issues.append([d["file"], pilot, l["row"], "Warna kosong di semua article", l["component"]])
        for i in d["info_rows"]:
            if i["label"].upper().startswith("BAGIAN"):
                issues.append([d["file"], pilot, i["row"], "Komposisi Material (bukan BOM, tidak diimpor)",
                               i["label"] + ": " + " | ".join(v for v in i["values"] if v)])
        for i, a in enumerate(d["articles"]):
            if not a:
                issues.append([d["file"], pilot, "", f"Article kolom {i + 1} tanpa nama colorway", ""])
    finish(ws)

    H = ["File", "Pilot", "Baris Excel", "Masalah", "Isi", "Keputusan"]
    ws = sheet(wb, "Masalah", H, [34, 7, 8, 44, 60, 40], ["Keputusan"])
    for x in issues:
        ws.append(x)
    finish(ws)

    os.makedirs(OUT_DIR, exist_ok=True)
    wb.save(OUT)
    print("OK", OUT)
    print(f"model {len(files)}, komponen {len(comp_use)}, supplier {len(sup_count)}, material {len(mat_use)}, "
          f"process {len(proc_use)}, masalah {len(issues)}; master: {'ya' if m_mat else 'belum'}")


if __name__ == "__main__":
    main()
