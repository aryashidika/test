import sqlite3
from dataclasses import dataclass
from typing import Optional

from ..ids import new_id
from .audit import write_audit_log
from .specsheet_service import season_sort_key


class DuplicateModelError(Exception):
    pass


@dataclass
class ModelInput:
    code: str
    name: str
    factory: Optional[str] = None
    category: Optional[str] = None
    outsole_mold: Optional[str] = None
    last_no: Optional[str] = None
    construction: Optional[str] = None
    size_range: Optional[str] = None
    sample_size: Optional[str] = None


def _clean(value: Optional[str]) -> Optional[str]:
    value = (value or "").strip()
    return value or None


def create_model(conn: sqlite3.Connection, data: ModelInput, actor: str) -> str:
    code = (data.code or "").strip()
    name = (data.name or "").strip()
    if not code:
        raise ValueError("Kode model wajib diisi.")
    if not name:
        raise ValueError("Nama model wajib diisi.")

    model_id = new_id()
    try:
        conn.execute(
            """INSERT INTO product_model
               (id, code, name, factory, category, outsole_mold, last_no, construction,
                size_range, sample_size)
               VALUES (?,?,?,?,?,?,?,?,?,?)""",
            (
                model_id, code, name, _clean(data.factory), _clean(data.category),
                _clean(data.outsole_mold), _clean(data.last_no), _clean(data.construction),
                _clean(data.size_range), _clean(data.sample_size),
            ),
        )
    except sqlite3.IntegrityError as exc:
        if "UNIQUE" in str(exc):
            raise DuplicateModelError(f"Kode model '{code}' sudah dipakai.") from exc
        raise
    write_audit_log(conn, actor, "ProductModel", model_id, "CREATE", None,
                     {"code": code, "name": name, "factory": data.factory})
    conn.commit()
    return model_id


def get_model(conn, model_id: str):
    row = conn.execute("SELECT * FROM product_model WHERE id=?", (model_id,)).fetchone()
    if not row:
        raise ValueError("Model tidak ditemukan.")
    return row


def list_models(conn, search: Optional[str] = None):
    query = "SELECT * FROM product_model WHERE 1=1"
    params = []
    if search:
        query += " AND (code LIKE ? OR name LIKE ?)"
        params.extend([f"%{search}%", f"%{search}%"])
    query += " ORDER BY code"
    return conn.execute(query, params).fetchall()


def list_models_overview(conn, season: Optional[str] = None, search: Optional[str] = None):
    """Model + info turunan (jumlah season, dan status specsheet untuk `season` bila diisi).

    Bila `season` diisi, hanya model yang punya specsheet pada season itu yang dikembalikan.
    """
    models = list_models(conn, search=search)
    result = []
    for model in models:
        sheets = conn.execute(
            "SELECT * FROM specsheet WHERE model_id=?", (model["id"],)
        ).fetchall()
        season_count = len(sheets)
        if season is not None:
            sheets = [s for s in sheets if s["season"] == season]
            if not sheets:
                continue

        target_sheet = None
        if season is not None and sheets:
            target_sheet = sheets[0]
        elif sheets:
            target_sheet = sorted(sheets, key=lambda s: season_sort_key(s["season"]))[-1]

        specsheet_summary = "Belum ada specsheet"
        article_count = 0
        if target_sheet:
            latest_revision = conn.execute(
                """SELECT * FROM specsheet_revision WHERE specsheet_id=?
                   ORDER BY created_at DESC LIMIT 1""",
                (target_sheet["id"],),
            ).fetchone()
            if latest_revision:
                specsheet_summary = f"{latest_revision['stage']} r{latest_revision['revision_no']} · {latest_revision['status']}"
                article_count = conn.execute(
                    """SELECT COUNT(*) c FROM revision_article
                       WHERE revision_id=? AND status='ACTIVE'""",
                    (latest_revision["id"],),
                ).fetchone()["c"]

        d = dict(model)
        d["season_count"] = season_count
        d["current_season"] = target_sheet["season"] if target_sheet else None
        d["current_specsheet_id"] = target_sheet["id"] if target_sheet else None
        d["specsheet_summary"] = specsheet_summary
        d["article_count"] = article_count
        result.append(d)
    return result


def list_known_seasons(conn):
    rows = conn.execute("SELECT DISTINCT season FROM specsheet").fetchall()
    seasons = [r["season"] for r in rows]
    seasons.sort(key=season_sort_key)
    return seasons
