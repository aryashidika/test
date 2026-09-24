"""Menu Admin untuk role SYSTEM_ADMIN (admin teknis): audit log dan reset data
prototipe. Tidak menyentuh data bisnis selain lewat reset."""

import json

from flask import Blueprint, g, render_template, request

from ...domain import permissions
from ...domain.reset_service import reset_all_data
from ..auth import guard_blueprint

admin_bp = Blueprint("admin", __name__, url_prefix="/admin")
guard_blueprint(admin_bp, permissions.is_system_admin, "Menu Admin hanya untuk role System Admin.")

RESET_CONFIRM_WORD = "RESET"
AUDIT_LIMIT = 200


def _pretty(raw):
    if not raw:
        return ""
    try:
        return json.dumps(json.loads(raw), ensure_ascii=False, indent=1)
    except ValueError:
        return raw


def _audit_ctx():
    entity = request.args.get("entity", "")
    search = request.args.get("q", "").strip()
    query = "SELECT * FROM audit_log WHERE 1=1"
    params = []
    if entity:
        query += " AND entity=?"
        params.append(entity)
    if search:
        query += " AND (user_role LIKE ? OR action LIKE ? OR entity_id LIKE ? OR after_json LIKE ?)"
        params.extend([f"%{search}%"] * 4)
    query += f" ORDER BY created_at DESC, rowid DESC LIMIT {AUDIT_LIMIT}"
    entries = [dict(r, before=_pretty(r["before_json"]), after=_pretty(r["after_json"]))
               for r in g.db.execute(query, params).fetchall()]
    entities = [r["entity"] for r in g.db.execute("SELECT DISTINCT entity FROM audit_log ORDER BY entity")]
    return {"entries": entries, "entities": entities, "entity": entity, "search": search, "limit": AUDIT_LIMIT}


def _render(tab, **kwargs):
    ctx = {"tab": tab, "confirm_word": RESET_CONFIRM_WORD, "error": None, "done": False, **kwargs}
    if tab == "audit":
        ctx.update(_audit_ctx())
    return render_template("admin/index.html", **ctx)


@admin_bp.route("")
def index():
    return _render("reset" if request.args.get("tab") == "reset" else "audit")


@admin_bp.route("/reset-data", methods=["POST"])
def reset_data():
    if request.form.get("confirm", "").strip() != RESET_CONFIRM_WORD:
        return _render("reset", error=f'Ketik "{RESET_CONFIRM_WORD}" untuk mengonfirmasi reset.')
    reset_all_data(g.db, g.session.actor_label)
    return _render("reset", done=True)
