import io
import json

from flask import Blueprint, abort, g, render_template, request, send_file, url_for

from ...domain import permissions
from ...domain.article_service import (
    include_article,
    list_articles_for_revision,
    list_articles_not_in_revision,
    set_article_status,
)
from ...domain.bom_service import (
    add_line_from_text,
    add_subcomponent_line,
    list_lines_with_cells,
    replace_material,
    resolve_material_text,
    resolve_supplier_text,
    season_colors,
    update_cell_value,
    update_line_supplier,
    update_process,
)
from ...domain.component_service import list_components
from ...domain.export_service import build_specsheet_workbook, specsheet_export_context
from ...domain.material_price_service import default_supplier_for, supplier_suggestions
from ...domain.material_service import list_materials
from ...domain.model_service import (
    get_model,
    list_known_seasons,
    list_models_overview,
)
from ...domain.report_service import reference_price
from ...domain.revision_service import (
    STAGES,
    create_carryover_revision,
    create_empty_revision,
    create_next_revision_same_stage,
    create_next_stage_revision,
    delete_draft_revision,
    get_change_log,
    list_revisions,
    publish_revision,
)
from ...domain.specsheet_service import (
    find_carryover_sources,
    find_cross_model_carryover_sources,
    list_specsheets,
    season_label,
)
from ..auth import guard_blueprint, require_permission, require_session

specsheet_bp = Blueprint("specsheet", __name__, url_prefix="/specsheet")
guard_blueprint(specsheet_bp, permissions.can_view_specsheet)

CHANGE_CATEGORIES = [
    "MATERIAL", "COMPONENT", "TREATMENT", "EX_RATE", "LOP", "AMORTIZATION", "YIELD", "OTHER",
]


def _role_ctx():
    role = g.session.role
    return {
        "can_manage": permissions.can_manage_master(role),
        "read_only": permissions.is_read_only(role),
        "can_edit_model": permissions.can_edit_model(role),
    }


def _visible_revisions(specsheet_id):
    """Brand hanya melihat revisi PUBLISHED; role lain melihat draft juga."""
    revisions = list_revisions(g.db, specsheet_id)
    if permissions.can_view_drafts(g.session.role):
        return revisions
    return [r for r in revisions if r["status"] == "PUBLISHED"]


def _require_visible_revision(revision_id):
    """Cetak/ekspor revisi DRAFT ditolak untuk role yang tidak boleh melihat draft."""
    row = g.db.execute("SELECT status FROM specsheet_revision WHERE id=?", (revision_id,)).fetchone()
    if row is None:
        abort(404)
    if row["status"] != "PUBLISHED" and not permissions.can_view_drafts(g.session.role):
        abort(403, description="Revisi ini belum diterbitkan.")


def _material_options(exclude_id=None):
    materials = list_materials(g.db, status="APPROVED") + list_materials(g.db, status="PROPOSED")
    return [m for m in materials if m["id"] != exclude_id]


def _reference_prices(revision, bom_lines, active_articles):
    """Harga referensi per sel (tambahan di luar PRD): hanya dihitung untuk role
    BRAND_VIEWER melihat revisi yang sudah PUBLISHED — supaya brand punya
    perkiraan harga material walau CBD article itu belum pernah dibuat. Tidak
    dihitung untuk role lain maupun revisi DRAFT."""
    if not revision or revision["status"] != "PUBLISHED" or g.session.role != "BRAND_VIEWER":
        return {}
    result = {}
    for line in bom_lines:
        for art in active_articles:
            cell = line["cells"].get(art["id"])
            if not cell or not cell["is_used"]:
                continue
            ref = reference_price(g.db, line["material_id"], cell["color"], line["supplier_id"])
            if ref:
                result[f"{line['id']}:{art['id']}"] = ref
    return result


# ---------------- Daftar specsheet (per model) ----------------

@specsheet_bp.route("")
@require_session
def list_page():
    return render_template("specsheet/list.html", **_list_ctx())


@specsheet_bp.route("/list")
@require_session
def list_partial():
    return render_template("model/_list_table.html", **_list_ctx())


def _list_ctx():
    search = request.args.get("q", "")
    season = request.args.get("season") or None
    seasons = list_known_seasons(g.db)
    models = list_models_overview(g.db, season=season, search=search or None,
                                  published_only=not permissions.can_view_drafts(g.session.role))
    return {"models": models, "seasons": seasons, "search": search, "season": season or "",
            "detail_endpoint": "specsheet.detail", **_role_ctx()}


# ---------------- Detail specsheet ----------------

def _load_detail_ctx(model_id, specsheet_id=None, revision_id=None):
    model = get_model(g.db, model_id)
    specsheets = list_specsheets(g.db, model_id=model_id)
    published_only = "" if permissions.can_view_drafts(g.session.role) else " WHERE status='PUBLISHED'"
    rev_counts = {
        row["specsheet_id"]: row["c"]
        for row in g.db.execute(
            f"SELECT specsheet_id, COUNT(*) c FROM specsheet_revision{published_only} GROUP BY specsheet_id"
        ).fetchall()
    }

    specsheet = None
    if specsheet_id:
        specsheet = next((s for s in specsheets if s["id"] == specsheet_id), None)
    if specsheet is None and specsheets:
        specsheet = specsheets[-1]
    specsheet_id = specsheet["id"] if specsheet else None

    revisions = _visible_revisions(specsheet_id) if specsheet_id else []
    has_draft = any(r["status"] == "DRAFT" for r in revisions)
    has_published = any(r["status"] == "PUBLISHED" for r in revisions)

    revision = None
    if revision_id:
        revision = next((r for r in revisions if r["id"] == revision_id), None)
    if revision is None and revisions:
        revision = next((r for r in revisions if r["status"] == "DRAFT"), None) or revisions[-1]
    revision_id = revision["id"] if revision else None

    can_edit = permissions.can_edit_specsheet(g.session.role)
    editable = bool(revision) and can_edit and revision["status"] == "DRAFT"
    creatable = bool(specsheet_id) and can_edit and not has_draft

    bom_lines = list_lines_with_cells(g.db, revision_id) if revision_id else []
    all_articles = list_articles_for_revision(g.db, revision_id) if revision_id else []
    active_articles = [a for a in all_articles if a["revision_status"] == "ACTIVE"]
    reference_prices = _reference_prices(revision, bom_lines, active_articles)

    carryover_sources = find_carryover_sources(g.db, model_id, specsheet["season"]) if specsheet else []
    change_logs = []
    for log in (get_change_log(g.db, revision_id) if revision_id else []):
        d = dict(log)
        d["diff"] = json.loads(log["diff_json"]) if log["diff_json"] else {"added": [], "removed": [], "changed": {}}
        change_logs.append(d)
    require_reason = bool(revision) and (revision["source_revision_id"] is not None or revision["revision_no"] != 0)

    return dict(
        model=model, model_id=model_id, specsheets=specsheets, rev_counts=rev_counts,
        specsheet=specsheet, specsheet_id=specsheet_id,
        revisions=revisions, revision=revision, revision_id=revision_id,
        has_draft=has_draft, has_published=has_published, creatable=creatable,
        can_edit=can_edit, editable=editable, require_reason=require_reason,
        bom_lines=bom_lines, articles=all_articles, active_articles=active_articles,
        reference_prices=reference_prices,
        carryover_sources=carryover_sources, change_logs=change_logs,
        material_options=_material_options(),
        component_options=list_components(g.db, status="APPROVED"), stages=STAGES,
        change_categories=CHANGE_CATEGORIES, season_label=season_label,
        **_role_ctx(),
    )


def _detail_ctx(model_id, specsheet_id=None, revision_id=None):
    """Konteks detail + daftar saran untuk input ketik di grid BOM (hanya
    dihitung kalau revisinya bisa diedit): warna se-season, dan supplier per
    material (supplier terdaftar untuk material itu di atas, supplier lain di
    bawah) — satu datalist per material yang ada di grid."""
    ctx = _load_detail_ctx(model_id, specsheet_id, revision_id)
    ctx["season_colors"] = []
    ctx["supplier_lists"] = {}
    ctx["all_suppliers"] = []
    ctx["available_articles"] = []
    if ctx["editable"]:
        ctx["available_articles"] = list_articles_not_in_revision(g.db, ctx["revision_id"], ctx["specsheet_id"])
        ctx["season_colors"] = season_colors(g.db, ctx["specsheet"]["season"])
        ctx["supplier_lists"] = {
            material_id: supplier_suggestions(g.db, material_id)
            for material_id in {l["material_id"] for l in ctx["bom_lines"]}
        }
        ctx["all_suppliers"] = supplier_suggestions(g.db)
    return ctx


@specsheet_bp.route("/<model_id>")
@require_session
def detail(model_id):
    specsheet_id = request.args.get("specsheet_id")
    revision_id = request.args.get("revision_id")
    return render_template("specsheet/detail.html", **_detail_ctx(model_id, specsheet_id, revision_id))


@specsheet_bp.route("/<model_id>/body")
@require_session
def detail_body(model_id):
    specsheet_id = request.args.get("specsheet_id")
    revision_id = request.args.get("revision_id")
    return render_template("specsheet/_detail_body.html", **_detail_ctx(model_id, specsheet_id, revision_id))


# ---------------- Revision ----------------

@specsheet_bp.route("/<model_id>/revision/empty", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def revision_empty(model_id):
    specsheet_id = request.form.get("specsheet_id")
    stage = request.form.get("stage") or "PULL"
    try:
        revision_id = create_empty_revision(g.db, specsheet_id, g.session.actor_label, stage=stage)
    except ValueError as exc:
        return render_template("specsheet/_detail_body.html", form_error=str(exc),
                                **_detail_ctx(model_id, specsheet_id))
    return render_template("specsheet/_detail_body.html", **_detail_ctx(model_id, specsheet_id, revision_id))


@specsheet_bp.route("/<model_id>/revision/carryover", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def revision_carryover(model_id):
    specsheet_id = request.form.get("specsheet_id")
    source_specsheet_id = request.form.get("source_specsheet_id")
    stage = request.form.get("stage") or "PULL"
    latest_published = g.db.execute(
        "SELECT * FROM specsheet_revision WHERE specsheet_id=? AND status='PUBLISHED' "
        "ORDER BY revision_no DESC LIMIT 1",
        (source_specsheet_id,),
    ).fetchone()
    error = None
    revision_id = None
    if not latest_published:
        error = "Season sumber belum punya revisi terbit."
    else:
        try:
            revision_id = create_carryover_revision(
                g.db, specsheet_id, latest_published["id"], g.session.actor_label, stage=stage
            )
        except ValueError as exc:
            error = str(exc)
    return render_template("specsheet/_detail_body.html", form_error=error,
                            **_detail_ctx(model_id, specsheet_id, revision_id))


@specsheet_bp.route("/<model_id>/revision/copy-cross-model")
@require_session
@require_permission(permissions.can_edit_specsheet)
def copy_cross_model_open(model_id):
    specsheet_id = request.args.get("specsheet_id")
    q = request.args.get("q", "")
    sources = find_cross_model_carryover_sources(g.db, exclude_model_id=model_id, search=q or None)
    return render_template(
        "specsheet/_copy_cross_model_modal.html", model_id=model_id, specsheet_id=specsheet_id,
        q=q, sources=sources, error=None, stages=STAGES,
    )


@specsheet_bp.route("/<model_id>/revision/copy-cross-model/results")
@require_session
@require_permission(permissions.can_edit_specsheet)
def copy_cross_model_results(model_id):
    specsheet_id = request.args.get("specsheet_id")
    q = request.args.get("q", "")
    sources = find_cross_model_carryover_sources(g.db, exclude_model_id=model_id, search=q or None)
    return render_template(
        "specsheet/_copy_cross_model_results.html", model_id=model_id, specsheet_id=specsheet_id, sources=sources,
    )


@specsheet_bp.route("/<model_id>/revision/copy-cross-model", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def copy_cross_model_create(model_id):
    specsheet_id = request.form.get("specsheet_id")
    source_specsheet_id = request.form.get("source_specsheet_id")
    stage = request.form.get("stage") or "PULL"
    q = request.form.get("q", "")
    latest_published = g.db.execute(
        "SELECT * FROM specsheet_revision WHERE specsheet_id=? AND status='PUBLISHED' "
        "ORDER BY revision_no DESC LIMIT 1",
        (source_specsheet_id,),
    ).fetchone()
    error = None
    revision_id = None
    if not latest_published:
        error = "Specsheet sumber belum punya revisi terbit."
    else:
        try:
            revision_id = create_carryover_revision(
                g.db, specsheet_id, latest_published["id"], g.session.actor_label, stage=stage
            )
        except ValueError as exc:
            error = str(exc)
    if error:
        sources = find_cross_model_carryover_sources(g.db, exclude_model_id=model_id, search=q or None)
        return render_template(
            "specsheet/_copy_cross_model_modal.html", model_id=model_id, specsheet_id=specsheet_id,
            q=q, sources=sources, error=error, stages=STAGES,
        )
    return "", 200, {"HX-Redirect": url_for("specsheet.detail", model_id=model_id, specsheet_id=specsheet_id,
                                            revision_id=revision_id)}


@specsheet_bp.route("/<model_id>/revision/same-stage", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def revision_same_stage(model_id):
    specsheet_id = request.form.get("specsheet_id")
    error = None
    revision_id = None
    try:
        revision_id = create_next_revision_same_stage(g.db, specsheet_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("specsheet/_detail_body.html", form_error=error,
                            **_detail_ctx(model_id, specsheet_id, revision_id))


@specsheet_bp.route("/<model_id>/revision/next-stage", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def revision_next_stage(model_id):
    specsheet_id = request.form.get("specsheet_id")
    error = None
    revision_id = None
    try:
        revision_id = create_next_stage_revision(g.db, specsheet_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("specsheet/_detail_body.html", form_error=error,
                            **_detail_ctx(model_id, specsheet_id, revision_id))


@specsheet_bp.route("/<model_id>/revision/<revision_id>/select")
@require_session
def revision_select(model_id, revision_id):
    specsheet_id = request.args.get("specsheet_id")
    return render_template("specsheet/_detail_body.html", **_detail_ctx(model_id, specsheet_id, revision_id))


@specsheet_bp.route("/<model_id>/revision/<revision_id>/print")
@require_session
def revision_print(model_id, revision_id):
    _require_visible_revision(revision_id)
    return render_template("specsheet/_print.html", model_id=model_id, **specsheet_export_context(g.db, revision_id))


@specsheet_bp.route("/<model_id>/revision/<revision_id>/export.xlsx")
@require_session
def revision_export_excel(model_id, revision_id):
    _require_visible_revision(revision_id)
    ctx = specsheet_export_context(g.db, revision_id)
    wb = build_specsheet_workbook(g.db, revision_id)
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    filename = (
        f"Specsheet_{ctx['model']['code']}_{ctx['specsheet']['season']}_"
        f"{ctx['revision']['stage']}r{ctx['revision']['revision_no']}.xlsx"
    )
    return send_file(
        buf, as_attachment=True, download_name=filename,
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )


@specsheet_bp.route("/<model_id>/revision/<revision_id>/publish", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def revision_publish(model_id, revision_id):
    specsheet_id = request.form.get("specsheet_id")
    category = request.form.get("category")
    reason = request.form.get("reason", "")
    error = None
    try:
        publish_revision(g.db, revision_id, category, reason, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("specsheet/_detail_body.html", form_error=error,
                            **_detail_ctx(model_id, specsheet_id, revision_id))


@specsheet_bp.route("/<model_id>/revision/<revision_id>/delete", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def revision_delete_draft(model_id, revision_id):
    """Hapus revisi DRAFT seakan belum pernah dibuat (revisi terbit tidak bisa)."""
    specsheet_id = request.form.get("specsheet_id")
    error = None
    try:
        delete_draft_revision(g.db, revision_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("specsheet/_detail_body.html", form_error=error,
                            **_detail_ctx(model_id, specsheet_id, None if not error else revision_id))


# ---------------- BOM lines ----------------

@specsheet_bp.route("/<model_id>/revision/<revision_id>/bom/line", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def bom_add_line(model_id, revision_id):
    """Satu baris inline untuk tambah komponen. Semua kolom diketik dengan saran:
    komponen yang cocok dengan master jadi baris komponen master, yang tidak
    cocok jadi komponen lokal (No. wajib diisi); material & supplier wajib ada
    di master."""
    specsheet_id = request.form.get("specsheet_id")
    error = None
    try:
        add_line_from_text(
            g.db, revision_id, request.form.get("component_text", ""), request.form.get("local_no", ""),
            request.form.get("material_text", ""), request.form.get("supplier_text", ""),
            request.form.get("process", ""), g.session.actor_label,
        )
    except ValueError as exc:
        error = str(exc)
    return render_template("specsheet/_bom_grid.html", bom_error=error,
                            **_detail_ctx(model_id, specsheet_id, revision_id))


@specsheet_bp.route("/<model_id>/revision/<revision_id>/bom/supplier-field")
@require_session
@require_permission(permissions.can_edit_specsheet)
def bom_supplier_field(model_id, revision_id):
    """Input supplier untuk baris baru/subkomponen, di-render ulang setiap kali
    material diketik: saran supplier menyesuaikan material itu, dan kalau
    supplier belum diisi, supplier utama (atau satu-satunya supplier) material
    itu langsung terisi."""
    supplier_text = request.args.get("supplier_text", "").strip()
    try:
        material_id = resolve_material_text(g.db, request.args.get("material_text", ""))
    except ValueError:
        material_id = None
    if material_id and not supplier_text:
        default = default_supplier_for(g.db, material_id)
        supplier_text = default["supplier_name"] if default else ""
    return render_template(
        "specsheet/_bom_supplier_field.html", supplier_text=supplier_text,
        suggestions=supplier_suggestions(g.db, material_id), list_id=f"dl-sup-new-{material_id or 'all'}",
    )


@specsheet_bp.route("/<model_id>/revision/<revision_id>/bom/<line_id>/subcomponent/row")
@require_session
@require_permission(permissions.can_edit_specsheet)
def bom_subcomponent_row(model_id, revision_id, line_id):
    specsheet_id = request.args.get("specsheet_id")
    ctx = _detail_ctx(model_id, specsheet_id, revision_id)
    line = next(l for l in ctx["bom_lines"] if l["id"] == line_id)
    return render_template(
        "specsheet/_bom_subcomponent_row.html", line=line, model_id=model_id, revision_id=revision_id,
        specsheet_id=specsheet_id, active_articles=ctx["active_articles"],
        all_suppliers=ctx["all_suppliers"],
    )


@specsheet_bp.route("/<model_id>/revision/<revision_id>/bom/<line_id>/subcomponent", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def bom_add_subcomponent(model_id, revision_id, line_id):
    specsheet_id = request.form.get("specsheet_id")
    error = None
    try:
        add_subcomponent_line(
            g.db, revision_id, line_id, request.form.get("sub_name", ""),
            resolve_material_text(g.db, request.form.get("material_text", "")),
            request.form.get("process", ""), g.session.actor_label,
            supplier_id=resolve_supplier_text(g.db, request.form.get("supplier_text", "")),
        )
    except ValueError as exc:
        error = str(exc)
    return render_template("specsheet/_bom_grid.html", bom_error=error,
                            **_detail_ctx(model_id, specsheet_id, revision_id))


@specsheet_bp.route("/<model_id>/revision/<revision_id>/bom/<line_id>/replace-material", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def bom_replace_material(model_id, revision_id, line_id):
    """Material diketik ulang di sel Deskripsi Material = Ganti Material (PRD 6.2).
    Teks yang tetap menunjuk ke material yang sama tidak mengubah apa pun."""
    specsheet_id = request.form.get("specsheet_id")
    error = None
    try:
        material_id = resolve_material_text(g.db, request.form.get("material_text", ""))
        current = g.db.execute("SELECT material_id FROM bom_line WHERE id=?", (line_id,)).fetchone()
        if not current or current["material_id"] != material_id:
            replace_material(g.db, revision_id, line_id, material_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("specsheet/_bom_grid.html", bom_error=error,
                            **_detail_ctx(model_id, specsheet_id, revision_id))


@specsheet_bp.route("/<model_id>/revision/<revision_id>/bom/<line_id>/supplier", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def bom_set_supplier(model_id, revision_id, line_id):
    cell_error = None
    typed = request.form.get("supplier_text", "")
    try:
        update_line_supplier(g.db, line_id, resolve_supplier_text(g.db, typed), g.session.actor_label)
    except ValueError as exc:
        cell_error = str(exc)
    line = next(l for l in list_lines_with_cells(g.db, revision_id) if l["id"] == line_id)
    return render_template("specsheet/_bom_supplier_cell.html", line=line, editable=True, cell_error=cell_error,
                            typed_value=typed if cell_error else None,
                            model_id=model_id, specsheet_id=request.form.get("specsheet_id"))


@specsheet_bp.route("/<model_id>/revision/<revision_id>/bom/<line_id>/process", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def bom_set_process(model_id, revision_id, line_id):
    update_process(g.db, line_id, request.form.get("value", ""), g.session.actor_label)
    line = next(l for l in list_lines_with_cells(g.db, revision_id) if l["id"] == line_id)
    return render_template("specsheet/_bom_process_cell.html", line=line, editable=True,
                            model_id=model_id, specsheet_id=request.form.get("specsheet_id"))


@specsheet_bp.route("/<model_id>/revision/<revision_id>/bom/<line_id>/cell/<article_id>", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def bom_set_cell(model_id, revision_id, line_id, article_id):
    update_cell_value(g.db, line_id, article_id, request.form.get("value", ""), g.session.actor_label)
    line = next(l for l in list_lines_with_cells(g.db, revision_id) if l["id"] == line_id)
    return render_template("specsheet/_bom_value_cell.html", line=line, article_id=article_id, editable=True,
                            model_id=model_id, specsheet_id=request.form.get("specsheet_id"))


# ---------------- Articles ----------------

@specsheet_bp.route("/<model_id>/revision/<revision_id>/article", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def article_include(model_id, revision_id):
    """"Pilih Article": masukkan article season ini (dibuat di halaman Model)
    ke revisi DRAFT. Article baru dibuat di halaman Model, bukan di sini."""
    specsheet_id = request.form.get("specsheet_id")
    article_ids = request.form.getlist("article_id")
    error = None if article_ids else "Pilih minimal satu article."
    try:
        for article_id in article_ids:
            include_article(g.db, revision_id, article_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("specsheet/_bom_grid.html", bom_error=error,
                            **_detail_ctx(model_id, specsheet_id, revision_id))


@specsheet_bp.route("/<model_id>/revision/<revision_id>/article/<article_id>/status", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_specsheet)
def article_set_status(model_id, revision_id, article_id):
    specsheet_id = request.form.get("specsheet_id")
    status = request.form.get("status")
    error = None
    try:
        set_article_status(g.db, revision_id, article_id, status, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return render_template("specsheet/_bom_grid.html", bom_error=error,
                            **_detail_ctx(model_id, specsheet_id, revision_id))
