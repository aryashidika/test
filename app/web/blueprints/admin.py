"""Menu Admin untuk role SYSTEM_ADMIN (admin teknis): reset data prototipe.
Tidak menyentuh data bisnis selain lewat reset."""

from flask import Blueprint, g, render_template, request

from ...domain import permissions
from ...domain.reset_service import reset_all_data
from ..auth import guard_blueprint

admin_bp = Blueprint("admin", __name__, url_prefix="/admin")
guard_blueprint(admin_bp, permissions.is_system_admin, "Menu Admin hanya untuk role System Admin.")

RESET_CONFIRM_WORD = "RESET"


@admin_bp.route("")
def index():
    return render_template("admin/index.html", confirm_word=RESET_CONFIRM_WORD, error=None, done=False)


@admin_bp.route("/reset-data", methods=["POST"])
def reset_data():
    if request.form.get("confirm", "").strip() != RESET_CONFIRM_WORD:
        return render_template("admin/index.html", confirm_word=RESET_CONFIRM_WORD, done=False,
                               error=f'Ketik "{RESET_CONFIRM_WORD}" untuk mengonfirmasi reset.')
    reset_all_data(g.db, g.session.actor_label)
    return render_template("admin/index.html", confirm_word=RESET_CONFIRM_WORD, error=None, done=True)
