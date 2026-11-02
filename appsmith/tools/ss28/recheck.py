"""Bandingkan specsheet hasil impor (hasil query recheck, JSON dari DB Tools) dengan Excel SS28.

  python recheck.py <hasil.json> [<out.xlsx>]

Setiap baris Excel dicari padanannya di sistem lewat aturan impor (gen_import.build_model), lalu komponen,
material, Dimension, supplier, Process, dan warna per article dibandingkan. Baris sistem tanpa padanan Excel
juga dilaporkan. Teks dibandingkan setelah dirapikan seperti di sistem (huruf besar, spasi di sekitar / - + , & dihapus).
"""
import collections
import json
import re
import sys

import build_mapping as bm
import extract
import gen_import as gi


def norm(s):
    s = re.sub(r"\s+", " ", (s or "").upper()).strip()
    return re.sub(r"\s*([/&+,-])\s*", r"\1", s)


def main(path, out=None):
    rows = json.load(open(path, encoding="utf-8-sig"))
    sysm = collections.defaultdict(list)
    for r in rows:
        sysm[r["model"]].append(r)
    comps = [c["name"] for c in bm.load_master("component.json")]
    sups = [s["name"] for s in bm.load_master("supplier.json")]
    every = extract.load_all()
    cnt = collections.Counter(extract.clean(l["supplier"]).upper() for d in every for l in d["lines"] if l["supplier"])
    gi.SUP_CANON.update({k: v for k, v in bm.cluster_suppliers(cnt, sups).items() if v[1]})
    report = []          # (model, baris Excel, bagian, status, Excel, sistem)
    for d in every:
        batch = next((b for b in gi.BATCHES.values() if d["file"] in b["models"]), None)
        if not batch or not any(d["file"] in b["models"] and b["models"][d["file"]]["name"] in sysm
                                for b in gi.BATCHES.values()):
            continue        # hanya model yang ada di hasil query
        exp = gi.build_model(d, comps + [n for n, _ in batch.get("components", [])], sups, batch)
        name = exp["name"]
        got = sysm.get(name, [])
        if not got:
            report.append((name, "", "model", "TIDAK ADA", name, "model tidak ditemukan di sistem"))
            continue
        h = got[0]
        # header model
        for field, e, s in [("category", exp["category"], h["category"]), ("construction", exp["construction"], h["construction"]),
                            ("gender", exp["gender"], h["gender"]), ("last", exp["last"], h["last"]),
                            ("outsole mold", exp["outsole_mold"], h["outsole_mold"]),
                            ("ukuran", ",".join(map(str, exp["sizes"])), h["sizes"]),
                            ("sample size", str(exp["sample"]), str(h["sample_size"])),
                            ("stage / status", "PREV / DRAFT", f'{h["stage"]} / {h["status"]}')]:
            report.append((name, "header", field, "OK" if norm(e) == norm(s) else "BEDA", e, s))
        arts = " | ".join(a["colorway"] for a in exp["articles"])
        sys_arts = [x.split(" #")[0] for x in h["article"].split(" | ")]     # urutan sistem: nomor article, colorway
        ok = sorted(norm(a["colorway"]) for a in exp["articles"]) == sorted(norm(x) for x in sys_arts)
        report.append((name, "header", "article", "OK" if ok else "BEDA", arts, h["article"]))
        pos = {norm(x): i for i, x in enumerate(sys_arts)}
        # baris BOM: urutan sistem = urutan tampil; cocokkan per kunci (komponen/sub, material, dimension), berurutan
        pool = list(got)
        for i, l in enumerate(exp["lines"]):
            label = l["component"] if l["kind"] == "MAIN" else l["sub_name"]
            cand = [r for r in pool if norm(r["komponen"]) == norm(label) and norm(r["material"]) == norm(l["material"])
                    and norm(r["dimension"]) == norm(l["dimension"])]
            if not cand:
                report.append((name, l["excel_row"], label, "TIDAK ADA", f'{l["material"]} {l["dimension"] or ""}', "-"))
                continue
            r = cand[0]
            pool.remove(r)
            diffs = []
            if norm(r["supplier"]) != norm(l["supplier"]):
                diffs.append(f'supplier {l["supplier"]} vs {r["supplier"]}')
            if norm(r["process"]) != norm(l["process"]):
                diffs.append(f'process {l["process"]} vs {r["process"]}')
            # warna dibandingkan per colorway (sistem mengurutkan article menurut nomor lalu colorway)
            sw = (r["warna"] or "").split(" | ")
            ec = " | ".join(norm(c) if c else "-" for c in l["colors"])
            sc = " | ".join(norm(sw[pos[norm(a["colorway"])]]) if norm(a["colorway"]) in pos else "?"
                            for a in exp["articles"])
            if ec != sc:
                diffs.append(f"warna {ec} vs {sc}")
            report.append((name, l["excel_row"], f'{r["no"]} {label}', "BEDA" if diffs else "OK",
                           f'{l["material"]} {l["dimension"] or ""}'.strip(), "; ".join(diffs) or r["material"]))
        for r in pool:
            report.append((name, "", f'{r["no"]} {r["komponen"]}', "LEBIH (tidak ada di Excel)", "-", r["material"]))
    c = collections.Counter(x[3] for x in report)
    for x in report:
        if x[3] != "OK":
            print(" | ".join(str(v) for v in x))
    print(dict(c))
    if out:
        from openpyxl import Workbook
        wb = Workbook()
        ws = wb.active
        ws.title = "Recheck"
        ws.append(["Model", "Baris Excel", "Bagian", "Status", "Excel (sesudah aturan impor)", "Sistem / beda"])
        for x in report:
            ws.append(list(x))
        for col, w in zip("ABCDEF", (14, 11, 60, 14, 50, 70)):
            ws.column_dimensions[col].width = w
        ws.freeze_panes = "A2"
        ws.auto_filter.ref = ws.dimensions
        wb.save(out)
        print("OK", out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
