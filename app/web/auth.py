from functools import wraps

from flask import g, redirect, url_for

from ..domain import permissions


def require_session(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if g.session is None:
            return redirect(url_for("main.role_select"))
        return view(*args, **kwargs)

    return wrapped


def require_master(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if g.session is None:
            return redirect(url_for("main.role_select"))
        if not permissions.can_manage_master(g.session.role):
            return "Aksi ini hanya untuk role Master Admin.", 403
        return view(*args, **kwargs)

    return wrapped
