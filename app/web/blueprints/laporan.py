from flask import Blueprint, g, redirect, render_template, request, url_for

from ...domain.material_service import list_materials
from ...domain.report_service import price_history, where_used
from ..auth import require_session

laporan_bp = Blueprint("laporan", __name__, url_prefix="/laporan")

STAGES = ["PULL", "SMS", "GTM", "PROD"]


@laporan_bp.route("")
@require_session
def index():
    return redirect(url_for("laporan.where_used_page"))


# ---------------- Where-used ----------------

def _material_picker_ctx(search):
    materials = list_materials(g.db, search=search or None, limit=50) if search else []
    return {"search": search, "materials": materials}


def _get_material(material_id):
    return g.db.execute("SELECT * FROM material WHERE id=?", (material_id,)).fetchone()


@laporan_bp.route("/where-used")
@require_session
def where_used_page():
    search = request.args.get("q", "")
    material_id = request.args.get("material_id") or None
    selected_material = None
    results = []
    if material_id:
        selected_material = _get_material(material_id)
        if selected_material:
            results = where_used(g.db, material_id)
    return render_template(
        "laporan/where_used.html",
        results=results, selected_material=selected_material, material_id=material_id or "",
        **_material_picker_ctx(search),
    )


# ---------------- Histori harga ----------------

@laporan_bp.route("/histori-harga")
@require_session
def histori_harga_page():
    search = request.args.get("q", "")
    material_id = request.args.get("material_id") or None
    stage = request.args.get("stage") or "PROD"
    if stage not in STAGES:
        stage = "PROD"
    selected_material = None
    groups = []
    if material_id:
        selected_material = _get_material(material_id)
        if selected_material:
            groups = price_history(g.db, material_id, stage=stage)
    return render_template(
        "laporan/histori_harga.html",
        groups=groups, selected_material=selected_material, material_id=material_id or "",
        stage=stage, stages=STAGES,
        **_material_picker_ctx(search),
    )
