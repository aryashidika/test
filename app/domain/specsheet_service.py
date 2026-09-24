import re
import sqlite3
from typing import Optional

from ..ids import new_id
from .audit import write_audit_log

SEASON_PATTERN = re.compile(r"^(SS|FH)(\d{2})$")
_SEASON_ORDER = {"SS": 0, "FH": 1}  # SS (Jan-Jun) selalu sebelum FH (Jul-Des) di tahun yang sama


class DuplicateSpecsheetError(Exception):
    pass


def validate_season(season: str) -> str:
    season = (season or "").strip().upper()
    match = SEASON_PATTERN.match(season)
    if not match:
        raise ValueError("Season harus berformat SS[tahun] atau FH[tahun], mis. SS26 atau FH26.")
    return season


def season_sort_key(season: str):
    match = SEASON_PATTERN.match((season or "").strip().upper())
    if not match:
        return (9999, 9)
    prefix, year = match.groups()
    return (int(year), _SEASON_ORDER[prefix])


def season_label(season: str) -> str:
    match = SEASON_PATTERN.match((season or "").strip().upper())
    if not match:
        return season
    prefix, year = match.groups()
    name = "Spring/Summer" if prefix == "SS" else "Fall/Holiday"
    return f"{season} · {name} 20{year}"


def create_specsheet(conn, model_id: str, season: str, actor: str) -> str:
    season = validate_season(season)
    model = conn.execute("SELECT * FROM product_model WHERE id=?", (model_id,)).fetchone()
    if not model:
        raise ValueError("Model tidak ditemukan.")

    specsheet_id = new_id()
    try:
        conn.execute(
            "INSERT INTO specsheet (id, model_id, season) VALUES (?,?,?)",
            (specsheet_id, model_id, season),
        )
    except sqlite3.IntegrityError as exc:
        if "UNIQUE" in str(exc):
            raise DuplicateSpecsheetError(
                f"Specsheet untuk model ini di season '{season}' sudah ada."
            ) from exc
        raise
    write_audit_log(conn, actor, "Specsheet", specsheet_id, "CREATE", None,
                     {"modelId": model_id, "season": season})
    conn.commit()
    return specsheet_id


def get_specsheet(conn, specsheet_id: str):
    row = conn.execute(
        """SELECT sp.*, pm.code AS model_code, pm.name AS model_name
           FROM specsheet sp JOIN product_model pm ON pm.id = sp.model_id
           WHERE sp.id=?""",
        (specsheet_id,),
    ).fetchone()
    if not row:
        raise ValueError("Specsheet tidak ditemukan.")
    return row


def list_specsheets(conn, model_id: Optional[str] = None):
    query = """SELECT sp.*, pm.code AS model_code, pm.name AS model_name
               FROM specsheet sp JOIN product_model pm ON pm.id = sp.model_id WHERE 1=1"""
    params = []
    if model_id:
        query += " AND sp.model_id=?"
        params.append(model_id)
    query += " ORDER BY pm.code"
    rows = conn.execute(query, params).fetchall()
    return sorted(rows, key=lambda r: (r["model_code"], season_sort_key(r["season"])), reverse=False)


def find_carryover_sources(conn, model_id: str, exclude_season: str):
    """Specsheet model yang sama, season lain, yang punya minimal satu revisi terbit."""
    rows = conn.execute(
        """SELECT sp.* FROM specsheet sp
           WHERE sp.model_id=? AND sp.season != ?
             AND EXISTS (
                 SELECT 1 FROM specsheet_revision sr
                 WHERE sr.specsheet_id = sp.id AND sr.status = 'PUBLISHED'
             )""",
        (model_id, exclude_season),
    ).fetchall()
    return sorted(rows, key=lambda r: season_sort_key(r["season"]), reverse=True)


def find_cross_model_carryover_sources(conn, exclude_model_id: Optional[str] = None, search: Optional[str] = None):
    """Specsheet model manapun yang punya minimal satu revisi terbit, untuk di-copy
    BOM-nya ke Model baru (colorway/Article tetap tidak ikut disalin)."""
    query = """SELECT sp.*, pm.code AS model_code, pm.name AS model_name
               FROM specsheet sp JOIN product_model pm ON pm.id = sp.model_id
               WHERE EXISTS (
                   SELECT 1 FROM specsheet_revision sr
                   WHERE sr.specsheet_id = sp.id AND sr.status = 'PUBLISHED'
               )"""
    params = []
    if exclude_model_id:
        query += " AND sp.model_id != ?"
        params.append(exclude_model_id)
    if search:
        query += " AND (pm.code LIKE ? OR pm.name LIKE ? OR sp.season LIKE ?)"
        like = f"%{search}%"
        params.extend([like, like, like])
    rows = conn.execute(query, params).fetchall()
    return sorted(rows, key=lambda r: (r["model_code"], season_sort_key(r["season"])))
