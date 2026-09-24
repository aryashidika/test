from functools import wraps

from flask import abort, g, redirect, url_for


def require_session(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if g.session is None:
            return redirect(url_for("main.role_select"))
        return view(*args, **kwargs)

    return wrapped


def require_permission(check, message="Role Anda tidak punya akses untuk aksi ini."):
    """Menolak (403) request dari role yang tidak lolos `check(role)` — penegakan
    di server, bukan hanya menyembunyikan tombol di template."""
    def decorator(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if g.session is None:
                return redirect(url_for("main.role_select"))
            if not check(g.session.role):
                abort(403, description=message)
            return view(*args, **kwargs)

        return wrapped

    return decorator


def guard_blueprint(bp, check, message="Role Anda tidak punya akses ke menu ini."):
    """Syarat akses satu menu (blueprint) sekaligus untuk semua route-nya."""
    @bp.before_request
    def _guard():
        if g.session is None:
            return redirect(url_for("main.role_select"))
        if not check(g.session.role):
            abort(403, description=message)
