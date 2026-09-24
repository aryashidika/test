"""Ekspor Excel & data untuk halaman cetak (PRD 7.5) — specsheet dan CBD.

Context builder di sini murni baca-saja dan dipakai bersama oleh route Excel
(`build_*_workbook`) maupun route halaman cetak (`*_export_context` langsung
dipakai sebagai variabel template) supaya keduanya selalu menampilkan data yang
sama persis dengan yang ada di editor web.
"""

from decimal import Decimal

from openpyxl import Workbook
from openpyxl.styles import Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

from .article_service import list_articles_for_revision
from .bom_service import list_lines_with_cells
from .cbd_calc import (
    cost_per_pair_idr,
    margin_pct,
    material_cost_idr,
    price_idr,
    price_usd,
    to_decimal,
    total_cost,
    variance,
    variance_label,
)
from .cbd_service import compute_display_fields, get_cbd_change_log, list_cbd_lines
from .model_service import get_model
from .revision_service import get_change_log, get_revision
from .specsheet_service import get_specsheet, season_label

GROUP_LABELS = {"a": "a. Upper", "c": "c. Bottom unit", "d": "d. Packaging", "e": "e. Miscellaneous"}

_HEADER_FILL = PatternFill("solid", fgColor="122A52")
_HEADER_FONT = Font(color="FFFFFF", bold=True)
_GROUP_FILL = PatternFill("solid", fgColor="DCE4F3")
_MISSING_FILL = PatternFill("solid", fgColor="FCEFD8")
_THIN = Side(style="thin", color="C9CFDB")
_BORDER = Border(left=_THIN, right=_THIN, top=_THIN, bottom=_THIN)

CBD_HEADERS = [
    "No", "Komponen", "Material", "Thickness", "Color", "Supplier", "UoM", "Remarks", "Yield", "Usage",
    "Loss %", "Harga Asli", "Currency", "USD*", "IDR*", "Cost/pair (Rp)*", "Asal Nilai",
]


def _fmt(value):
    if value is None:
        return None
    s = f"{value:.6f}".rstrip("0").rstrip(".")
    return s if s else "0"


def _style_header_row(ws, row_idx, ncols):
    for col in range(1, ncols + 1):
        cell = ws.cell(row=row_idx, column=col)
        cell.fill = _HEADER_FILL
        cell.font = _HEADER_FONT
        cell.border = _BORDER


def _border_row(ws, row_idx, ncols):
    for col in range(1, ncols + 1):
        ws.cell(row=row_idx, column=col).border = _BORDER


def _autosize(ws, widths):
    for i, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w


# ---------------- Specsheet ----------------

def specsheet_export_context(conn, revision_id):
    revision = get_revision(conn, revision_id)
    specsheet = get_specsheet(conn, revision["specsheet_id"])
    model = get_model(conn, specsheet["model_id"])
    all_articles = list_articles_for_revision(conn, revision_id)
    active_articles = [a for a in all_articles if a["revision_status"] == "ACTIVE"]
    bom_lines = list_lines_with_cells(conn, revision_id)
    return {
        "model": model,
        "specsheet": specsheet,
        "revision": revision,
        "articles": active_articles,
        "bom_lines": bom_lines,
        "season_label": season_label(specsheet["season"]),
    }


def build_specsheet_workbook(conn, revision_id):
    ctx = specsheet_export_context(conn, revision_id)
    model, specsheet, revision = ctx["model"], ctx["specsheet"], ctx["revision"]
    articles, bom_lines = ctx["articles"], ctx["bom_lines"]

    wb = Workbook()
    ws = wb.active
    ws.title = "Specsheet"

    ws.append([f"{model['code']} — {model['name']}"])
    ws.cell(row=ws.max_row, column=1).font = Font(bold=True, size=14)
    ws.append([f"Season: {ctx['season_label']}"])
    ws.append([f"Stage {revision['stage']} · Revisi {revision['revision_no']} · {revision['status']}"])
    ws.append([])

    fixed_headers = ["No", "Komponen", "Deskripsi Material", "Source of Material", "UoM", "Remarks"]
    headers = fixed_headers + [f"{a['code']} ({a['colorway']})" for a in articles]
    ws.append(headers)
    _style_header_row(ws, ws.max_row, len(headers))
    header_row = ws.max_row

    for line in bom_lines:
        row = [
            line["display_no"], line["display_name"], line["material_name"],
            line["supplier_name"] or "-", line["uom"], line["process"] or "-",
        ]
        for art in articles:
            cell = line["cells"].get(art["id"])
            row.append(cell["color"] if cell and cell["is_used"] else "")
        ws.append(row)
        _border_row(ws, ws.max_row, len(headers))

    ws.append([])
    ws.append(["Dibuat oleh", "", "Diperiksa oleh", "", "Disetujui oleh"])
    ws.append([])
    ws.append([])
    ws.append(["(_______________)", "", "(_______________)", "", "(_______________)"])

    _autosize(ws, [8, 22, 26, 20, 8, 18] + [16] * len(articles))
    ws.freeze_panes = f"A{header_row + 1}"
    return wb


# ---------------- CBD ----------------

def cbd_export_context(conn, cbd_revision_id):
    revision = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (cbd_revision_id,)).fetchone()
    if not revision:
        raise ValueError("Revisi CBD tidak ditemukan.")
    article = conn.execute("SELECT * FROM article WHERE id=?", (revision["article_id"],)).fetchone()
    specsheet = get_specsheet(conn, article["specsheet_id"])
    model = get_model(conn, specsheet["model_id"])

    exchange_rate = to_decimal(revision["exchange_rate"])
    raw_lines = list_cbd_lines(conn, cbd_revision_id)
    lines = []
    calc_lines = []
    for line in raw_lines:
        d = dict(line)
        compute_display_fields(d)
        yv, uv, lp, po = (to_decimal(d["yield_value"]), to_decimal(d["usage_value"]),
                          to_decimal(d["loss_pct"]), to_decimal(d["price_original"]))
        d["yield_fmt"] = _fmt(yv)
        d["usage_fmt"] = _fmt(uv)
        d["loss_fmt"] = _fmt(lp)
        d["price_fmt"] = _fmt(po)
        d["price_usd_fmt"] = _fmt(price_usd(po, d["currency"], exchange_rate))
        d["price_idr_fmt"] = _fmt(price_idr(po, d["currency"], exchange_rate))
        d["cost_per_pair_fmt"] = _fmt(cost_per_pair_idr(uv, po, d["currency"], lp, exchange_rate))
        lines.append(d)
        calc_lines.append({"status": d["status"], "usage": uv, "price_original": po,
                            "currency": d["currency"], "loss_pct": lp})

    missing_lines = [l for l in lines if l["status"] == "MISSING_IN_SPEC"]
    normal_lines = [l for l in lines if l["status"] != "MISSING_IN_SPEC"]
    lines_by_group = {}
    for line in normal_lines:
        lines_by_group.setdefault(line["group_code"], []).append(line)
    grouped_lines = [
        (code, GROUP_LABELS.get(code, code), lines_by_group[code])
        for code in ("a", "c", "d", "e") if code in lines_by_group
    ]

    mat_cost = material_cost_idr(calc_lines, exchange_rate)
    amortization = to_decimal(revision["amortization"]) or Decimal(0)
    adjustment = to_decimal(revision["adjustment"]) or Decimal(0)
    target_fob = to_decimal(revision["target_fob"])
    actual_fob = total_cost(mat_cost, amortization, adjustment)
    var = variance(actual_fob, target_fob)
    selling_price = to_decimal(revision["selling_price"])
    margin = margin_pct(selling_price, actual_fob)

    recap_biaya = {
        "exchange_rate": _fmt(exchange_rate) or "-",
        "amortization": _fmt(amortization) or "0",
        "adjustment": _fmt(adjustment) or "0",
        "target_fob": _fmt(target_fob) or "-",
        "actual_fob": _fmt(actual_fob) or "0",
        "variance": _fmt(var if var is None else abs(var)) or "-",
        "variance_label": variance_label(var) or "-",
    }
    recap_margin = {
        "selling_price": _fmt(selling_price) or "-",
        "margin_pct": _fmt(margin) or "-",
    }

    change_logs = get_cbd_change_log(conn, cbd_revision_id)

    return {
        "model": model,
        "specsheet": specsheet,
        "article": article,
        "revision": revision,
        "grouped_lines": grouped_lines,
        "missing_lines": missing_lines,
        "recap_biaya": recap_biaya,
        "recap_margin": recap_margin,
        "change_logs": change_logs,
        "season_label": season_label(specsheet["season"]),
    }


def _write_cbd_line_row(ws, line, ncols):
    ws.append([
        line["display_no"], line["display_name"], line["material_name"], line["material_thickness"] or "-",
        line["color"] or "-", line["supplier_name"] or "-", line["uom"], line["remarks"] or "-",
        line["yield_fmt"], line["usage_fmt"], line["loss_fmt"], line["price_fmt"], line["currency"] or "-",
        line["price_usd_fmt"], line["price_idr_fmt"], line["cost_per_pair_fmt"],
        f"{line['value_origin']} · harga {line['price_source'] or '-'}",
    ])
    _border_row(ws, ws.max_row, ncols)


def _write_cbd_group(ws, label, lines, ncols, fill):
    ws.append([label] + [""] * (ncols - 1))
    row = ws.max_row
    ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=ncols)
    cell = ws.cell(row=row, column=1)
    cell.font = Font(bold=True)
    cell.fill = fill
    ws.append(CBD_HEADERS)
    _style_header_row(ws, ws.max_row, ncols)
    for line in lines:
        _write_cbd_line_row(ws, line, ncols)


def build_cbd_workbook(conn, cbd_revision_id):
    ctx = cbd_export_context(conn, cbd_revision_id)
    model, specsheet, article, revision = ctx["model"], ctx["specsheet"], ctx["article"], ctx["revision"]
    ncols = len(CBD_HEADERS)

    wb = Workbook()
    ws = wb.active
    ws.title = "CBD"

    ws.append([f"{model['code']} — {model['name']}"])
    ws.cell(row=ws.max_row, column=1).font = Font(bold=True, size=14)
    ws.append([f"Season {ctx['season_label']} · Article {article['code']} ({article['colorway']})"])
    ws.append([f"Stage {revision['stage']} · Revisi {revision['revision_no']} · {revision['status']}"])
    ws.append([])

    for code, label, lines in ctx["grouped_lines"]:
        _write_cbd_group(ws, label, lines, ncols, _GROUP_FILL)

    if ctx["missing_lines"]:
        _write_cbd_group(ws, "Baris Hilang dari Specsheet (MISSING_IN_SPEC)",
                          ctx["missing_lines"], ncols, _MISSING_FILL)

    ws.append([])
    ws.append(["Rekap Biaya"])
    ws.cell(row=ws.max_row, column=1).font = Font(bold=True)
    rb = ctx["recap_biaya"]
    variance_display = rb["variance"]
    if rb["variance_label"] != "-":
        variance_display = f"{rb['variance']} ({rb['variance_label']})"
    for label, value in [
        ("Exchange Rate", rb["exchange_rate"]), ("Amortisasi", rb["amortization"]),
        ("Adjustment", rb["adjustment"]), ("Target FOB", rb["target_fob"]),
        ("Actual FOB", rb["actual_fob"]), ("Selisih", variance_display),
    ]:
        ws.append([label, value])

    ws.append([])
    ws.append(["Rekap Margin"])
    ws.cell(row=ws.max_row, column=1).font = Font(bold=True)
    rm = ctx["recap_margin"]
    ws.append(["Selling Price", rm["selling_price"]])
    ws.append(["Margin %", rm["margin_pct"]])

    if ctx["change_logs"]:
        ws.append([])
        ws.append(["Change Log"])
        ws.cell(row=ws.max_row, column=1).font = Font(bold=True)
        ws.append(["Tanggal", "Kategori", "Oleh", "Alasan"])
        for log in ctx["change_logs"]:
            ws.append([log["created_at"], log["category"], log["created_by"], log["reason"]])

    _autosize(ws, [8, 20, 22, 10, 12, 16, 8, 16, 8, 8, 8, 12, 10, 10, 12, 16, 18])
    return wb
