import io
import json
from decimal import Decimal

from flask import Blueprint, g, render_template, request, send_file

from ...domain import permissions
from ...domain.article_service import list_articles_for_specsheet
from ...domain.cbd_calc import (
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
from ...domain.cbd_service import (
    CHANGE_CATEGORIES,
    article_cbd_status,
    cbd_draft_is_stale,
    compute_display_fields,
    create_cbd_from_article,
    create_cbd_next_stage,
    create_cbd_no_source,
    create_cbd_same_stage,
    delete_cbd_draft,
    find_cbd_copy_sources,
    get_cbd_change_log,
    clear_price_override,
    list_cbd_lines,
    list_cbd_revisions,
    override_price,
    publish_cbd_revision,
    refresh_cbd_draft,
    refresh_cbd_prices,
    set_quotation_price,
    stale_master_price_lines,
    update_adjustment,
    update_amortization,
    update_exchange_rate,
    update_loss_pct,
    update_margin_pct,
    update_selling_price,
    update_target_fob,
    update_yield,
)
from ...domain.export_service import build_cbd_workbook, cbd_export_context
from ...domain.material_price_service import price_gap
from ...domain.model_service import get_model, list_known_seasons, list_models_overview
from ...domain.report_service import validation_report
from ...domain.specsheet_service import list_specsheets, season_label
from ..auth import require_session

cbd_bp = Blueprint("cbd", __name__, url_prefix="/cbd")

GROUP_LABELS = {"a": "a. Upper", "c": "c. Bottom unit", "d": "d. Packaging", "e": "e. Miscellaneous"}


def _role_ctx():
    role = g.session.role
    return {"read_only": permissions.is_read_only(role), "can_manage_price": permissions.can_manage_price(role)}


def _fmt(value):
    if value is None:
        return "-"
    s = f"{value:.6f}".rstrip("0").rstrip(".")
    return s if s else "0"


# ---------------- List ----------------

@cbd_bp.route("")
@require_session
def list_page():
    return render_template("cbd/list.html", **_list_ctx())


@cbd_bp.route("/list")
@require_session
def list_partial():
    return render_template("cbd/_list_table.html", **_list_ctx())


def _list_ctx():
    search = request.args.get("q", "")
    season = request.args.get("season") or None
    seasons = list_known_seasons(g.db)
    models = list_models_overview(g.db, season=season, search=search or None)
    return {"models": models, "seasons": seasons, "search": search, "season": season or "", **_role_ctx()}


# ---------------- Detail ----------------

def _load_detail_ctx(model_id, specsheet_id=None, article_id=None, cbd_revision_id=None):
    model = get_model(g.db, model_id)
    specsheets = list_specsheets(g.db, model_id=model_id)

    specsheet = None
    if specsheet_id:
        specsheet = next((s for s in specsheets if s["id"] == specsheet_id), None)
    if specsheet is None and specsheets:
        specsheet = specsheets[-1]
    specsheet_id = specsheet["id"] if specsheet else None

    # Status tiap article menurut specsheet TERBIT terakhir: hanya yang ACTIVE
    # yang bisa dipilih untuk membuat/mengubah CBD; yang di-drop/belum terbit
    # hanya bisa dilihat (kalau sudah punya CBD).
    articles = []
    for a in (list_articles_for_specsheet(g.db, specsheet_id) if specsheet_id else []):
        d = dict(a)
        d["cbd_status"] = article_cbd_status(g.db, a["id"])
        d["has_cbd"] = g.db.execute("SELECT 1 FROM cbd_revision WHERE article_id=? LIMIT 1", (a["id"],)).fetchone() is not None
        articles.append(d)
    article = None
    if article_id:
        article = next((a for a in articles if a["id"] == article_id), None)
    if article is None:
        article = next((a for a in articles if a["cbd_status"] == "ACTIVE"), None)
    article_id = article["id"] if article else None
    article_active = bool(article) and article["cbd_status"] == "ACTIVE"

    revisions = list_cbd_revisions(g.db, article_id) if article_id else []
    has_draft = any(r["status"] == "DRAFT" for r in revisions)
    has_published = any(r["status"] == "PUBLISHED" for r in revisions)

    revision = None
    if cbd_revision_id:
        revision = next((r for r in revisions if r["id"] == cbd_revision_id), None)
    if revision is None and revisions:
        revision = next((r for r in revisions if r["status"] == "DRAFT"), None) or revisions[-1]
    cbd_revision_id = revision["id"] if revision else None

    can_edit = permissions.can_edit_cbd(g.session.role) and article_active
    editable = bool(revision) and can_edit and revision["status"] == "DRAFT"
    # Selling Price & Margin % tetap bisa diedit walau revisi sudah PUBLISHED
    # (beda dari field Rekap Biaya lain & baris CBD yang terkunci begitu terbit).
    margin_editable = bool(revision) and can_edit
    creatable = bool(article_id) and can_edit and not has_draft
    # Hapus draft boleh juga untuk article yang sudah di-drop (draft-nya memang
    # tidak bisa diteruskan lagi).
    can_delete_draft = (bool(revision) and revision["status"] == "DRAFT"
                        and permissions.can_edit_cbd(g.session.role))
    stale = bool(revision) and cbd_draft_is_stale(g.db, revision)

    exchange_rate = to_decimal(revision["exchange_rate"]) if revision else None
    raw_lines = list_cbd_lines(g.db, cbd_revision_id) if cbd_revision_id else []
    lines = []
    calc_lines = []
    for line in raw_lines:
        d = dict(line)
        compute_display_fields(d)
        yv, uv, lp, po = (to_decimal(d["yield_value"]), to_decimal(d["usage_value"]),
                          to_decimal(d["loss_pct"]), to_decimal(d["price_original"]))
        # Rupiah adalah mata uang utama (revisi 3): IDR*/Cost per pair tidak
        # butuh exchange rate untuk baris berharga IDR. Hanya kolom USD* (dan
        # baris berharga USD) yang butuh rate.
        usd = price_usd(po, d["currency"], exchange_rate)
        idr = price_idr(po, d["currency"], exchange_rate)
        cost = cost_per_pair_idr(uv, po, d["currency"], lp, exchange_rate)
        d["price_usd_fmt"] = _fmt(usd)
        d["price_idr_fmt"] = _fmt(idr)
        d["cost_per_pair_fmt"] = _fmt(cost)
        d["usage_fmt"] = _fmt(uv)
        # Kenapa baris ini belum punya harga (supplier kosong / belum ada harga
        # untuk supplier ini / hanya ada harga warna lain) — harganya diisi di
        # Master Material, bukan di sini.
        d["price_gap"] = (
            price_gap(g.db, d["material_id"], d["supplier_id"], d["color"])
            if d["status"] == "ACTIVE" and d["price_original"] is None else None
        )
        lines.append(d)
        calc_lines.append({"status": d["status"], "usage": uv, "price_original": po,
                            "currency": d["currency"], "loss_pct": lp})

    # PRD 7.3: baris MISSING_IN_SPEC tampil di bagian terpisah, bukan tercampur di
    # grup a/c/d/e biasa.
    missing_lines = [l for l in lines if l["status"] == "MISSING_IN_SPEC"]
    normal_lines = [l for l in lines if l["status"] != "MISSING_IN_SPEC"]
    lines_by_group = {}
    for line in normal_lines:
        lines_by_group.setdefault(line["group_code"], []).append(line)
    grouped_lines = [
        (code, GROUP_LABELS.get(code, code), lines_by_group[code])
        for code in ("a", "c", "d", "e") if code in lines_by_group
    ]

    recap_biaya = None
    recap_margin = None
    if revision:
        mat_cost = material_cost_idr(calc_lines, exchange_rate)
        amortization = to_decimal(revision["amortization"]) or Decimal(0)
        adjustment = to_decimal(revision["adjustment"]) or Decimal(0)
        target_fob = to_decimal(revision["target_fob"])
        actual_fob = total_cost(mat_cost, amortization, adjustment)
        var = variance(actual_fob, target_fob)
        recap_biaya = {
            "exchange_rate": _fmt(exchange_rate),
            "amortization": _fmt(amortization),
            "adjustment": _fmt(adjustment),
            "target_fob": _fmt(target_fob),
            "actual_fob": _fmt(actual_fob),
            "variance": _fmt(var if var is None else abs(var)),
            "variance_label": variance_label(var) or "-",
        }
        selling_price = to_decimal(revision["selling_price"])
        margin = margin_pct(selling_price, actual_fob)
        recap_margin = {
            "selling_price": _fmt(selling_price),
            "margin_pct": _fmt(margin),
        }

    change_logs = []
    for log in (get_cbd_change_log(g.db, cbd_revision_id) if cbd_revision_id else []):
        d = dict(log)
        d["diff"] = json.loads(log["diff_json"]) if log["diff_json"] else {"added": [], "removed": [], "changed": {}}
        change_logs.append(d)
    require_reason = bool(revision) and (revision["source_cbd_revision_id"] is not None or revision["revision_no"] != 0)

    copy_sources = find_cbd_copy_sources(g.db, model_id, exclude_article_id=article_id) if article_id else []
    validation = validation_report(g.db, cbd_revision_id) if cbd_revision_id else None
    stale_prices = stale_master_price_lines(g.db, cbd_revision_id) if editable else []
    # Baris material proses (QUOTATION) yang kosong tidak dihitung sebagai
    # "belum ada harga di master" — kosong memang wajar untuknya (diwakili
    # baris proses lain).
    gap_codes = [l["price_gap"]["code"] for l in normal_lines if l["price_gap"]]
    missing_price_count = sum(1 for c in gap_codes if c not in ("NO_SUPPLIER", "QUOTATION"))
    no_supplier_count = gap_codes.count("NO_SUPPLIER")
    unpriced_count = sum(1 for l in normal_lines if l["price_original"] is None)

    return dict(
        model=model, model_id=model_id, specsheets=specsheets, specsheet=specsheet, specsheet_id=specsheet_id,
        articles=articles, article=article, article_id=article_id,
        revisions=revisions, revision=revision, cbd_revision_id=cbd_revision_id,
        has_draft=has_draft, has_published=has_published, creatable=creatable,
        can_edit=can_edit, editable=editable, margin_editable=margin_editable, stale=stale,
        can_delete_draft=can_delete_draft,
        require_reason=require_reason,
        grouped_lines=grouped_lines, missing_lines=missing_lines,
        recap_biaya=recap_biaya, recap_margin=recap_margin, change_logs=change_logs,
        copy_sources=copy_sources, validation=validation,
        stale_prices=stale_prices, missing_price_count=missing_price_count, no_supplier_count=no_supplier_count,
        unpriced_count=unpriced_count,
        change_categories=CHANGE_CATEGORIES, season_label=season_label,
        **_role_ctx(),
    )


@cbd_bp.route("/<model_id>")
@require_session
def detail(model_id):
    return render_template(
        "cbd/detail.html",
        **_load_detail_ctx(model_id, request.args.get("specsheet_id"), request.args.get("article_id"),
                            request.args.get("cbd_revision_id")),
    )


@cbd_bp.route("/<model_id>/body")
@require_session
def detail_body(model_id):
    return render_template(
        "cbd/_detail_body.html",
        **_load_detail_ctx(model_id, request.args.get("specsheet_id"), request.args.get("article_id"),
                            request.args.get("cbd_revision_id")),
    )


# ---------------- Wizard (revision creation) ----------------

@cbd_bp.route("/<model_id>/revision/no-source", methods=["POST"])
@require_session
def revision_no_source(model_id):
    specsheet_id = request.form.get("specsheet_id")
    article_id = request.form.get("article_id")
    error = None
    cbd_revision_id = None
    try:
        cbd_revision_id = create_cbd_no_source(
            g.db, article_id, request.form.get("exchange_rate", ""), g.session.actor_label
        )
    except ValueError as exc:
        error = str(exc)
    return render_template("cbd/_detail_body.html", form_error=error,
                            **_load_detail_ctx(model_id, specsheet_id, article_id, cbd_revision_id))


@cbd_bp.route("/<model_id>/revision/from-article", methods=["POST"])
@require_session
def revision_from_article(model_id):
    specsheet_id = request.form.get("specsheet_id")
    article_id = request.form.get("article_id")
    error = None
    cbd_revision_id = None
    try:
        cbd_revision_id = create_cbd_from_article(
            g.db, article_id, request.form.get("source_article_id"),
            request.form.get("exchange_rate", ""), g.session.actor_label,
        )
    except ValueError as exc:
        error = str(exc)
    return render_template("cbd/_detail_body.html", form_error=error,
                            **_load_detail_ctx(model_id, specsheet_id, article_id, cbd_revision_id))


@cbd_bp.route("/<model_id>/revision/same-stage", methods=["POST"])
@require_session
def revision_same_stage(model_id):
    specsheet_id = request.form.get("specsheet_id")
    article_id = request.form.get("article_id")
    error = None
    cbd_revision_id = None
    try:
        cbd_revision_id = create_cbd_same_stage(g.db, article_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("cbd/_detail_body.html", form_error=error,
                            **_load_detail_ctx(model_id, specsheet_id, article_id, cbd_revision_id))


@cbd_bp.route("/<model_id>/revision/next-stage", methods=["POST"])
@require_session
def revision_next_stage(model_id):
    specsheet_id = request.form.get("specsheet_id")
    article_id = request.form.get("article_id")
    error = None
    cbd_revision_id = None
    try:
        cbd_revision_id = create_cbd_next_stage(g.db, article_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("cbd/_detail_body.html", form_error=error,
                            **_load_detail_ctx(model_id, specsheet_id, article_id, cbd_revision_id))


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/select")
@require_session
def revision_select(model_id, cbd_revision_id):
    return render_template(
        "cbd/_detail_body.html",
        **_load_detail_ctx(model_id, request.args.get("specsheet_id"), request.args.get("article_id"), cbd_revision_id),
    )


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/print")
@require_session
def revision_print(model_id, cbd_revision_id):
    return render_template("cbd/_print.html", model_id=model_id, **cbd_export_context(g.db, cbd_revision_id))


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/export.xlsx")
@require_session
def revision_export_excel(model_id, cbd_revision_id):
    ctx = cbd_export_context(g.db, cbd_revision_id)
    wb = build_cbd_workbook(g.db, cbd_revision_id)
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    filename = (
        f"CBD_{ctx['model']['code']}_{ctx['article']['code']}_"
        f"{ctx['revision']['stage']}r{ctx['revision']['revision_no']}.xlsx"
    )
    return send_file(
        buf, as_attachment=True, download_name=filename,
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/publish", methods=["POST"])
@require_session
def revision_publish(model_id, cbd_revision_id):
    specsheet_id = request.form.get("specsheet_id")
    article_id = request.form.get("article_id")
    error = None
    try:
        publish_cbd_revision(g.db, cbd_revision_id, request.form.get("category"),
                              request.form.get("reason", ""), g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("cbd/_detail_body.html", form_error=error,
                            **_load_detail_ctx(model_id, specsheet_id, article_id, cbd_revision_id))


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/delete", methods=["POST"])
@require_session
def revision_delete_draft(model_id, cbd_revision_id):
    """Hapus revisi CBD DRAFT seakan belum pernah dibuat (revisi terbit tidak bisa)."""
    specsheet_id = request.form.get("specsheet_id")
    article_id = request.form.get("article_id")
    error = None
    try:
        if not permissions.can_edit_cbd(g.session.role):
            raise ValueError("Role Anda tidak bisa menghapus revisi CBD.")
        delete_cbd_draft(g.db, cbd_revision_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("cbd/_detail_body.html", form_error=error,
                            **_load_detail_ctx(model_id, specsheet_id, article_id,
                                               cbd_revision_id if error else None))


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/refresh", methods=["POST"])
@require_session
def revision_refresh(model_id, cbd_revision_id):
    specsheet_id = request.form.get("specsheet_id")
    article_id = request.form.get("article_id")
    error = None
    try:
        refresh_cbd_draft(g.db, cbd_revision_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("cbd/_detail_body.html", form_error=error,
                            **_load_detail_ctx(model_id, specsheet_id, article_id, cbd_revision_id))


# ---------------- Editor grid ----------------

def _line_response(model_id, specsheet_id, article_id, cbd_revision_id, error=None):
    # Re-render the whole detail body (not just the grid) since editing any single
    # line also changes the Rekap Biaya / Rekap Margin totals.
    return render_template("cbd/_detail_body.html", form_error=error,
                            **_load_detail_ctx(model_id, specsheet_id, article_id, cbd_revision_id))


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/line/<line_id>/yield", methods=["POST"])
@require_session
def line_yield(model_id, cbd_revision_id, line_id):
    error = None
    try:
        update_yield(g.db, line_id, request.form.get("value", ""), g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return _line_response(model_id, request.form.get("specsheet_id"), request.form.get("article_id"),
                           cbd_revision_id, error)


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/line/<line_id>/loss", methods=["POST"])
@require_session
def line_loss(model_id, cbd_revision_id, line_id):
    error = None
    try:
        update_loss_pct(g.db, line_id, request.form.get("value", ""), g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return _line_response(model_id, request.form.get("specsheet_id"), request.form.get("article_id"),
                           cbd_revision_id, error)


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/line/<line_id>/price-override", methods=["POST"])
@require_session
def line_price_override(model_id, cbd_revision_id, line_id):
    """Satu-satunya input harga di grid CBD: harga sekali pakai untuk baris ini
    (alasan wajib). Harga yang berlaku untuk semua CBD diisi di Master Material."""
    error = None
    try:
        override_price(g.db, line_id, request.form.get("price_original", ""), request.form.get("currency"),
                       request.form.get("reason", ""), g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return _line_response(model_id, request.form.get("specsheet_id"), request.form.get("article_id"),
                           cbd_revision_id, error)


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/line/<line_id>/quotation", methods=["POST"])
@require_session
def line_quotation_price(model_id, cbd_revision_id, line_id):
    """Harga material proses (metode Quotation) diisi langsung per baris: harga
    + currency saja. Harga kosong = baris tidak dihargai terpisah."""
    error = None
    try:
        set_quotation_price(g.db, line_id, request.form.get("price_original", ""), request.form.get("currency"),
                            None, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return _line_response(model_id, request.form.get("specsheet_id"), request.form.get("article_id"),
                           cbd_revision_id, error)


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/line/<line_id>/price-override/clear", methods=["POST"])
@require_session
def line_price_override_clear(model_id, cbd_revision_id, line_id):
    error = None
    try:
        clear_price_override(g.db, line_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return _line_response(model_id, request.form.get("specsheet_id"), request.form.get("article_id"),
                           cbd_revision_id, error)


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/refresh-prices", methods=["POST"])
@require_session
def revision_refresh_prices(model_id, cbd_revision_id):
    error = None
    try:
        refresh_cbd_prices(g.db, cbd_revision_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return _line_response(model_id, request.form.get("specsheet_id"), request.form.get("article_id"),
                           cbd_revision_id, error)


_HEADER_FIELD_UPDATERS = {
    "exchange_rate": update_exchange_rate,
    "amortization": update_amortization,
    "adjustment": update_adjustment,
    "selling_price": update_selling_price,
    "target_fob": update_target_fob,
    "margin_pct": update_margin_pct,
}


@cbd_bp.route("/<model_id>/revision/<cbd_revision_id>/field/<field_name>", methods=["POST"])
@require_session
def revision_field(model_id, cbd_revision_id, field_name):
    specsheet_id = request.form.get("specsheet_id")
    article_id = request.form.get("article_id")
    error = None
    updater = _HEADER_FIELD_UPDATERS.get(field_name)
    if not updater:
        error = "Field tidak dikenal."
    else:
        try:
            updater(g.db, cbd_revision_id, request.form.get("value", ""), g.session.actor_label)
        except ValueError as exc:
            error = str(exc)
    return render_template("cbd/_detail_body.html", form_error=error,
                            **_load_detail_ctx(model_id, specsheet_id, article_id, cbd_revision_id))
