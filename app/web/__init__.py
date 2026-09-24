import secrets

from flask import Flask, g, render_template, request, session

from ..db import get_connection, init_db
from ..domain import permissions
from ..domain.seed_data import has_master_data, seed_dummy_master_data
from ..domain.seed_specsheet_illuzion import ensure_illuzion_specsheet_seeded
from .formatting import fmt_num, fmt_rupiah
from .user_session import Session


def create_app(db_path=None):
    app = Flask(__name__)
    app.config["SECRET_KEY"] = secrets.token_hex(16)
    app.config["DB_PATH"] = db_path

    conn = get_connection(db_path=db_path)
    init_db(conn)
    if not has_master_data(conn):
        seed_dummy_master_data(conn)
    ensure_illuzion_specsheet_seeded(conn)
    conn.close()

    @app.before_request
    def _load_session():
        g.db = get_connection(db_path=app.config["DB_PATH"])
        g.db.execute("PRAGMA foreign_keys = ON")
        if session.get("role") and session.get("operator_name"):
            g.session = Session(role=session["role"], operator_name=session["operator_name"])
        else:
            g.session = None

    @app.teardown_appcontext
    def _close_db(exc):
        db = g.pop("db", None)
        if db is not None:
            db.close()

    @app.context_processor
    def _inject_globals():
        session_ = g.get("session")
        role = session_.role if session_ else None
        nav = {
            "master": bool(role) and permissions.can_view_master(role),
            "model": bool(role) and permissions.can_view_model(role),
            "specsheet": bool(role) and permissions.can_view_specsheet(role),
            "cbd": bool(role) and permissions.can_view_cbd(role),
            "admin": bool(role) and permissions.is_system_admin(role),
        }
        return {"nav": nav, "role_label": permissions.role_label(role) if role else ""}

    app.add_template_filter(fmt_num, "angka")
    app.add_template_filter(fmt_rupiah, "rupiah")

    from .blueprints.admin import admin_bp
    from .blueprints.cbd import cbd_bp
    from .blueprints.laporan import laporan_bp
    from .blueprints.main import main_bp
    from .blueprints.master import master_bp
    from .blueprints.model import model_bp
    from .blueprints.specsheet import specsheet_bp

    app.register_blueprint(main_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(master_bp)
    app.register_blueprint(model_bp)
    app.register_blueprint(specsheet_bp)
    app.register_blueprint(cbd_bp)
    app.register_blueprint(laporan_bp)

    @app.errorhandler(403)
    def _handle_forbidden(exc):
        message = exc.description or "Role Anda tidak punya akses."
        if request.headers.get("HX-Request"):
            return message, 403
        return render_template("forbidden.html", message=message), 403

    @app.errorhandler(ValueError)
    def _handle_value_error(exc):
        return str(exc), 400

    return app
