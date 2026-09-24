from flask import Blueprint, g, redirect, render_template, request, session, url_for

from ...domain import permissions

main_bp = Blueprint("main", __name__)


def home_url(role):
    """Halaman pertama setelah masuk, sesuai pekerjaan utama tiap role."""
    if permissions.is_system_admin(role):
        return url_for("admin.index")
    if role == "VENDOR_CBD":
        return url_for("cbd.list_page")
    if role in ("VENDOR_SPEC", "BRAND_VIEWER"):
        return url_for("specsheet.list_page")
    return url_for("master.material_page")


@main_bp.route("/")
def index():
    if g.session is None:
        return redirect(url_for("main.role_select"))
    return redirect(home_url(g.session.role))


@main_bp.route("/masuk", methods=["GET", "POST"])
def role_select():
    if request.method == "POST":
        role = request.form.get("role")
        name = (request.form.get("name") or "").strip() or "Operator"
        if role not in permissions.ROLES:
            return "Role tidak valid.", 400
        session["role"] = role
        session["operator_name"] = name
        return redirect(home_url(role))
    roles = [(r, permissions.role_label(r)) for r in permissions.ROLES]
    return render_template("role_select.html", roles=roles)


@main_bp.route("/keluar", methods=["POST"])
def logout():
    session.clear()
    return redirect(url_for("main.role_select"))
