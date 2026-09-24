from flask import Blueprint, g, redirect, render_template, request, session, url_for

from ...domain import permissions
from ...domain.reset_service import reset_all_data
from ..auth import require_master

main_bp = Blueprint("main", __name__)

ROLE_LABELS = {
    "MASTER_ADMIN": "Master Admin",
    "VENDOR_SPEC": "Vendor - Specsheet",
    "VENDOR_CBD": "Vendor - CBD",
    "BRAND_VIEWER": "Brand Viewer (read-only)",
    "SYSTEM_ADMIN": "System Admin",
}


@main_bp.route("/")
def index():
    if g.session is None:
        return redirect(url_for("main.role_select"))
    return redirect(url_for("master.material_page"))


@main_bp.route("/masuk", methods=["GET", "POST"])
def role_select():
    if request.method == "POST":
        role = request.form.get("role")
        name = (request.form.get("name") or "").strip() or "Operator"
        if role not in permissions.ROLES:
            return "Role tidak valid.", 400
        session["role"] = role
        session["operator_name"] = name
        return redirect(url_for("master.material_page"))
    roles = [(r, ROLE_LABELS[r]) for r in permissions.ROLES]
    return render_template("role_select.html", roles=roles)


@main_bp.route("/keluar", methods=["POST"])
def logout():
    session.clear()
    return redirect(url_for("main.role_select"))


@main_bp.route("/reset-data", methods=["POST"])
@require_master
def reset_data():
    reset_all_data(g.db, g.session.actor_label)
    return redirect(url_for("master.material_page"))
