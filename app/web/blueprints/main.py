from flask import Blueprint, g, redirect, render_template, request, session, url_for

from ...domain import permissions
from ...domain import worklist_service as worklist

main_bp = Blueprint("main", __name__)


def _home_ctx(role):
    """Isi Beranda "Tugas Saya" sesuai pekerjaan utama role."""
    if role == "VENDOR_SPEC":
        return {"spec": worklist.spec_worklist(g.db)}
    if role == "VENDOR_CBD":
        return {"cbd": worklist.cbd_worklist(g.db)}
    if role == "MASTER_ADMIN":
        return {"approvals": worklist.approval_queue(g.db)}
    if role == "BRAND_VIEWER":
        return {"published": worklist.recently_published(g.db)}
    return {"summary": worklist.system_summary(g.db)}


@main_bp.route("/")
def index():
    if g.session is None:
        return redirect(url_for("main.role_select"))
    return render_template("home.html", **_home_ctx(g.session.role))


@main_bp.route("/masuk", methods=["GET", "POST"])
def role_select():
    if request.method == "POST":
        role = request.form.get("role")
        name = (request.form.get("name") or "").strip() or "Operator"
        if role not in permissions.ROLES:
            return "Role tidak valid.", 400
        session["role"] = role
        session["operator_name"] = name
        return redirect(url_for("main.index"))
    roles = [(r, permissions.role_label(r)) for r in permissions.ROLES]
    return render_template("role_select.html", roles=roles)


@main_bp.route("/keluar", methods=["POST"])
def logout():
    session.clear()
    return redirect(url_for("main.role_select"))
