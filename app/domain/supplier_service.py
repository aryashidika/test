import sqlite3
from dataclasses import dataclass
from typing import Optional

from ..ids import new_id
from ..normalize import normalize_text
from .audit import write_audit_log


class DuplicateSupplierError(Exception):
    pass


@dataclass
class SupplierInput:
    name: str
    status: str = "APPROVED"
    default_currency: str = "IDR"


def create_supplier(conn: sqlite3.Connection, data: SupplierInput, actor: str) -> str:
    name = (data.name or "").strip()
    if not name:
        raise ValueError("Nama supplier wajib diisi.")
    if data.status not in ("PROPOSED", "APPROVED", "INACTIVE"):
        raise ValueError("Status tidak valid.")
    if data.default_currency not in ("IDR", "USD"):
        raise ValueError("Currency tidak valid.")

    supplier_id = new_id()
    try:
        conn.execute(
            "INSERT INTO supplier (id, name, status, default_currency) VALUES (?,?,?,?)",
            (supplier_id, name, data.status, data.default_currency),
        )
    except sqlite3.IntegrityError as exc:
        if "UNIQUE" in str(exc):
            raise DuplicateSupplierError(f"Supplier '{name}' sudah ada.") from exc
        raise

    write_audit_log(conn, actor, "Supplier", supplier_id, "CREATE", None,
                     {"name": name, "status": data.status, "defaultCurrency": data.default_currency})
    conn.commit()
    return supplier_id


def rename_supplier(conn: sqlite3.Connection, supplier_id: str, name: str, actor: str) -> None:
    """Ganti nama supplier (Master Admin). BOM, CBD, dan master harga mengacu ke
    id supplier, jadi semuanya ikut menampilkan nama baru."""
    name = (name or "").strip()
    if not name:
        raise ValueError("Nama supplier wajib diisi.")
    before = conn.execute("SELECT * FROM supplier WHERE id=?", (supplier_id,)).fetchone()
    if not before:
        raise ValueError("Supplier tidak ditemukan.")
    # Supplier di BOM dicari tanpa peduli huruf besar/kecil & spasi
    # (bom_service.resolve_supplier_text), jadi nama yang hanya beda kapitalisasi
    # dengan supplier lain juga ditolak.
    key = normalize_text(name)
    for other in conn.execute("SELECT id, name FROM supplier WHERE id<>?", (supplier_id,)).fetchall():
        if normalize_text(other["name"]) == key:
            raise DuplicateSupplierError(f"Supplier '{other['name']}' sudah ada.")
    conn.execute(
        "UPDATE supplier SET name=?, updated_at=datetime('now') WHERE id=?",
        (name, supplier_id),
    )
    write_audit_log(conn, actor, "Supplier", supplier_id, "RENAME", {"name": before["name"]}, {"name": name})
    conn.commit()


def set_default_currency(conn: sqlite3.Connection, supplier_id: str, currency: str, actor: str) -> None:
    if currency not in ("IDR", "USD"):
        raise ValueError("Currency tidak valid.")
    before = conn.execute("SELECT * FROM supplier WHERE id=?", (supplier_id,)).fetchone()
    if not before:
        raise ValueError("Supplier tidak ditemukan.")
    conn.execute(
        "UPDATE supplier SET default_currency=?, updated_at=datetime('now') WHERE id=?",
        (currency, supplier_id),
    )
    write_audit_log(
        conn, actor, "Supplier", supplier_id, "UPDATE_DEFAULT_CURRENCY",
        {"defaultCurrency": before["default_currency"]}, {"defaultCurrency": currency},
    )
    conn.commit()


def set_status(conn, supplier_id: str, new_status: str, actor: str) -> None:
    if new_status not in ("PROPOSED", "APPROVED", "INACTIVE"):
        raise ValueError("Status tidak valid.")
    before = conn.execute("SELECT * FROM supplier WHERE id=?", (supplier_id,)).fetchone()
    if not before:
        raise ValueError("Supplier tidak ditemukan.")
    conn.execute(
        "UPDATE supplier SET status=?, updated_at=datetime('now') WHERE id=?",
        (new_status, supplier_id),
    )
    write_audit_log(
        conn, actor, "Supplier", supplier_id, "STATUS_CHANGE",
        {"status": before["status"]}, {"status": new_status},
    )
    conn.commit()


def list_suppliers(conn, search: Optional[str] = None, status: Optional[str] = None):
    query = "SELECT * FROM supplier WHERE 1=1"
    params = []
    if search:
        query += " AND name LIKE ?"
        params.append(f"%{search}%")
    if status:
        query += " AND status=?"
        params.append(status)
    query += " ORDER BY name"
    return conn.execute(query, params).fetchall()
