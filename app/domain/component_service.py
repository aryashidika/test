import sqlite3
from typing import Optional

from ..ids import new_id
from .audit import write_audit_log


class ComponentNumberError(ValueError):
    pass


def suggest_next_number(conn, group_id: str) -> Optional[int]:
    group = conn.execute("SELECT * FROM component_group WHERE id=?", (group_id,)).fetchone()
    if not group:
        raise ValueError("Kelompok komponen tidak ditemukan.")
    row = conn.execute("SELECT MAX(number) m FROM component WHERE group_id=?", (group_id,)).fetchone()
    current_max = row["m"]
    if current_max is None:
        return group["range_start"]
    nxt = current_max + 10
    if nxt > group["range_end"]:
        return None
    return nxt


def _validate(conn, number: int, name: str, group_id: str) -> str:
    """Aturan nomor & nama komponen (dipakai tambah dan edit); mengembalikan nama
    yang sudah dirapikan."""
    group = conn.execute("SELECT * FROM component_group WHERE id=?", (group_id,)).fetchone()
    if not group:
        raise ValueError("Kelompok komponen tidak ditemukan.")
    if number % 10 != 0:
        raise ComponentNumberError("Nomor komponen harus kelipatan 10.")
    if not (group["range_start"] <= number <= group["range_end"]):
        raise ComponentNumberError(
            f"Nomor harus berada di rentang {group['range_start']}-{group['range_end']} "
            f"untuk kelompok {group['name']}."
        )
    name = (name or "").strip()
    if not name:
        raise ValueError("Nama komponen wajib diisi.")
    return name


def create_component(conn: sqlite3.Connection, number: int, name: str, group_id: str,
                      status: str, actor: str) -> str:
    name = _validate(conn, number, name, group_id)
    if status not in ("PROPOSED", "APPROVED", "INACTIVE"):
        raise ValueError("Status tidak valid.")

    component_id = new_id()
    try:
        conn.execute(
            "INSERT INTO component (id, number, name, group_id, status) VALUES (?,?,?,?,?)",
            (component_id, number, name, group_id, status),
        )
    except sqlite3.IntegrityError as exc:
        if "UNIQUE" in str(exc):
            raise ComponentNumberError(f"Nomor {number} sudah dipakai dan tidak bisa dipakai ulang.") from exc
        raise

    write_audit_log(
        conn, actor, "Component", component_id, "CREATE", None,
        {"number": number, "name": name, "status": status},
    )
    conn.commit()
    return component_id


def update_component(conn: sqlite3.Connection, component_id: str, number: int, name: str,
                      group_id: str, actor: str) -> None:
    """Edit nomor, nama, dan kelompok komponen (Master Admin). Aturan nomor sama
    dengan saat menambah; nomor yang dipakai komponen lain tetap ditolak. BOM &
    CBD menampilkan nomor/nama lewat join, jadi ikut berubah."""
    before = conn.execute("SELECT * FROM component WHERE id=?", (component_id,)).fetchone()
    if not before:
        raise ValueError("Komponen tidak ditemukan.")
    name = _validate(conn, number, name, group_id)
    if conn.execute("SELECT 1 FROM component WHERE number=? AND id<>?", (number, component_id)).fetchone():
        raise ComponentNumberError(f"Nomor {number} sudah dipakai komponen lain.")
    conn.execute(
        "UPDATE component SET number=?, name=?, group_id=?, updated_at=datetime('now') WHERE id=?",
        (number, name, group_id, component_id),
    )
    write_audit_log(
        conn, actor, "Component", component_id, "UPDATE",
        {"number": before["number"], "name": before["name"], "groupId": before["group_id"]},
        {"number": number, "name": name, "groupId": group_id},
    )
    conn.commit()


def set_status(conn, component_id: str, new_status: str, actor: str) -> None:
    if new_status not in ("PROPOSED", "APPROVED", "INACTIVE"):
        raise ValueError("Status tidak valid.")
    before = conn.execute("SELECT * FROM component WHERE id=?", (component_id,)).fetchone()
    if not before:
        raise ValueError("Komponen tidak ditemukan.")
    conn.execute(
        "UPDATE component SET status=?, updated_at=datetime('now') WHERE id=?",
        (new_status, component_id),
    )
    write_audit_log(
        conn, actor, "Component", component_id, "STATUS_CHANGE",
        {"status": before["status"]}, {"status": new_status},
    )
    conn.commit()


def list_components(conn, group_id: Optional[str] = None, status: Optional[str] = None):
    query = "SELECT * FROM component WHERE 1=1"
    params = []
    if group_id:
        query += " AND group_id=?"
        params.append(group_id)
    if status:
        query += " AND status=?"
        params.append(status)
    query += " ORDER BY number"
    return conn.execute(query, params).fetchall()
