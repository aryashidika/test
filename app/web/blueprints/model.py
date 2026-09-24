"""Halaman Model: data Model, Season, dan Article/colorway — sumber sebelum
specsheet dibuat. Revisi & BOM ada di blueprint `specsheet`."""

from flask import Blueprint, g, redirect, render_template, request, url_for

from ...domain import permissions
from ...domain.article_service import (
    copy_articles_from_specsheet,
    create_article,
    delete_article,
    list_articles_overview,
    update_article,
)
from ...domain.model_service import (
    DuplicateModelError,
    ModelInput,
    create_model,
    get_model,
    list_known_seasons,
    list_models_overview,
    update_model,
)
from ...domain.specsheet_service import DuplicateSpecsheetError, create_specsheet, list_specsheets
from ..auth import guard_blueprint, require_permission, require_session

model_bp = Blueprint("model", __name__, url_prefix="/model")
guard_blueprint(model_bp, permissions.can_view_model)

MODEL_FIELDS = ("code", "name", "category", "factory", "outsole_mold", "last_no",
                "construction", "size_range", "sample_size")
TABS = ("info", "article")


def _role_ctx():
    role = g.session.role
    return {
        "can_edit_model": permissions.can_edit_model(role),
        "can_view_cbd": permissions.can_view_cbd(role),
        "can_view_drafts": permissions.can_view_drafts(role),
    }


def _model_input(values):
    return ModelInput(**{k: values.get(k, "") for k in MODEL_FIELDS})


# ---------------- Daftar model ----------------

def _list_ctx():
    search = request.args.get("q", "")
    season = request.args.get("season") or None
    models = list_models_overview(g.db, season=season, search=search or None,
                                  published_only=not permissions.can_view_drafts(g.session.role))
    return {"models": models, "seasons": list_known_seasons(g.db), "search": search,
            "season": season or "", "detail_endpoint": "model.detail", **_role_ctx()}


@model_bp.route("")
@require_session
def list_page():
    return render_template("model/list.html", **_list_ctx())


@model_bp.route("/list")
@require_session
def list_partial():
    return render_template("model/_list_table.html", **_list_ctx())


@model_bp.route("/new")
@require_session
@require_permission(permissions.can_edit_model)
def new_form():
    return render_template("model/_new_form.html", error=None, values={}, model=None)


@model_bp.route("", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_model)
def create():
    values = request.form.to_dict()
    try:
        model_id = create_model(g.db, _model_input(values), g.session.actor_label)
    except (DuplicateModelError, ValueError) as exc:
        return render_template("model/_new_form.html", error=str(exc), values=values, model=None)
    return "", 200, {"HX-Redirect": url_for("model.detail", model_id=model_id, tab="article")}


# ---------------- Detail model ----------------

def _detail_ctx(model_id, tab=None, specsheet_id=None, edit_article_id=None, error=None, notice=None):
    model = get_model(g.db, model_id)
    specsheets = list_specsheets(g.db, model_id=model_id)
    specsheet = next((s for s in specsheets if s["id"] == specsheet_id), None)
    if specsheet is None and specsheets:
        specsheet = specsheets[-1]
    articles = list_articles_overview(
        g.db, specsheet["id"], include_drafts=permissions.can_view_drafts(g.session.role)
    ) if specsheet else []
    counts = {
        row["specsheet_id"]: row["c"] for row in g.db.execute(
            "SELECT specsheet_id, COUNT(*) c FROM article GROUP BY specsheet_id"
        ).fetchall()
    }
    copy_sources = [s for s in specsheets if specsheet and s["id"] != specsheet["id"] and counts.get(s["id"])]
    return dict(
        model=model, model_id=model_id, tab=tab if tab in TABS else "article",
        specsheets=specsheets, specsheet=specsheet, specsheet_id=specsheet["id"] if specsheet else None,
        articles=articles, article_counts=counts, copy_sources=copy_sources,
        edit_article_id=edit_article_id, error=error, notice=notice, **_role_ctx(),
    )


def _render_body(model_id, **kwargs):
    return render_template("model/_detail_body.html", **_detail_ctx(model_id, **kwargs))


@model_bp.route("/<model_id>")
@require_session
def detail(model_id):
    # URL lama /model/<id>?revision_id=... (sebelum Specsheet punya menu sendiri)
    # diarahkan ke halaman specsheet.
    if request.args.get("revision_id"):
        return redirect(url_for("specsheet.detail", model_id=model_id, **request.args))
    return render_template(
        "model/detail.html",
        **_detail_ctx(model_id, request.args.get("tab"), request.args.get("specsheet_id")),
    )


@model_bp.route("/<model_id>/body")
@require_session
def detail_body(model_id):
    return _render_body(model_id, tab=request.args.get("tab"), specsheet_id=request.args.get("specsheet_id"),
                        edit_article_id=request.args.get("edit_article"))


@model_bp.route("/<model_id>/edit")
@require_session
@require_permission(permissions.can_edit_model)
def edit_form(model_id):
    model = get_model(g.db, model_id)
    return render_template("model/_new_form.html", error=None, values=dict(model), model=model)


@model_bp.route("/<model_id>/edit", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_model)
def update(model_id):
    values = request.form.to_dict()
    try:
        update_model(g.db, model_id, _model_input(values), g.session.actor_label)
    except (DuplicateModelError, ValueError) as exc:
        return render_template("model/_new_form.html", error=str(exc), values=values, model=get_model(g.db, model_id))
    return "", 200, {"HX-Redirect": url_for("model.detail", model_id=model_id, tab="info")}


# ---------------- Season ----------------

@model_bp.route("/<model_id>/season/new")
@require_session
@require_permission(permissions.can_edit_model)
def season_new_form(model_id):
    return render_template("model/_season_form.html", model_id=model_id, error=None)


@model_bp.route("/<model_id>/season", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_model)
def season_create(model_id):
    try:
        specsheet_id = create_specsheet(g.db, model_id, request.form.get("season", ""), g.session.actor_label)
    except (DuplicateSpecsheetError, ValueError) as exc:
        return render_template("model/_season_form.html", model_id=model_id, error=str(exc))
    return "", 200, {"HX-Redirect": url_for("model.detail", model_id=model_id, tab="article",
                                            specsheet_id=specsheet_id)}


# ---------------- Article ----------------

@model_bp.route("/<model_id>/season/<specsheet_id>/article", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_model)
def article_create(model_id, specsheet_id):
    error = None
    try:
        create_article(g.db, specsheet_id, request.form.get("code", ""), request.form.get("colorway", ""),
                       g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return _render_body(model_id, tab="article", specsheet_id=specsheet_id, error=error)


@model_bp.route("/<model_id>/season/<specsheet_id>/copy-articles", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_model)
def article_copy(model_id, specsheet_id):
    error = notice = None
    try:
        copied = copy_articles_from_specsheet(g.db, specsheet_id, request.form.get("source_specsheet_id"),
                                              g.session.actor_label)
        notice = f"{copied} article disalin." if copied else "Semua kode article sumber sudah ada di season ini."
    except ValueError as exc:
        error = str(exc)
    return _render_body(model_id, tab="article", specsheet_id=specsheet_id, error=error, notice=notice)


@model_bp.route("/<model_id>/article/<article_id>", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_model)
def article_update(model_id, article_id):
    specsheet_id = request.form.get("specsheet_id")
    try:
        update_article(g.db, article_id, request.form.get("code", ""), request.form.get("colorway", ""),
                       g.session.actor_label)
    except ValueError as exc:
        return _render_body(model_id, tab="article", specsheet_id=specsheet_id, edit_article_id=article_id,
                            error=str(exc))
    return _render_body(model_id, tab="article", specsheet_id=specsheet_id)


@model_bp.route("/<model_id>/article/<article_id>/delete", methods=["POST"])
@require_session
@require_permission(permissions.can_edit_model)
def article_delete(model_id, article_id):
    specsheet_id = request.form.get("specsheet_id")
    error = None
    try:
        delete_article(g.db, article_id, g.session.actor_label)
    except ValueError as exc:
        error = str(exc)
    return _render_body(model_id, tab="article", specsheet_id=specsheet_id, error=error)
