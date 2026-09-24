import secrets

from flask import Flask, g, redirect, session, url_for

from ..db import get_connection, init_db
from ..domain import permissions
from ..domain.seed_data import has_master_data, seed_dummy_master_data
from ..domain.seed_specsheet_illuzion import ensure_illuzion_specsheet_seeded
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
        can_manage = bool(g.get("session")) and permissions.can_manage_master(g.session.role)
        return {"can_manage_master_global": can_manage}

    from .blueprints.cbd import cbd_bp
    from .blueprints.laporan import laporan_bp
    from .blueprints.main import main_bp
    from .blueprints.master import master_bp
    from .blueprints.model import model_bp

    app.register_blueprint(main_bp)
    app.register_blueprint(master_bp)
    app.register_blueprint(model_bp)
    app.register_blueprint(cbd_bp)
    app.register_blueprint(laporan_bp)

    @app.errorhandler(ValueError)
    def _handle_value_error(exc):
        return str(exc), 400

    return app
