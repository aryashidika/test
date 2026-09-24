import re
import sqlite3
from dataclasses import dataclass
from typing import Optional

from ..ids import new_id
from ..normalize import normalize_text
from .audit import write_audit_log


class DuplicateMaterialError(Exception):
    def __init__(self, existing=None):
        self.existing = existing
        super().__init__("Material dengan nama, thickness, dan UoM yang sama (setelah normalisasi) sudah ada.")


class DuplicateMaterialCodeError(Exception):
    def __init__(self, existing=None):
        self.existing = existing
        super().__init__("Material Code ini sudah dipakai material lain.")


@dataclass
class MaterialInput:
    material_code: str
    name: str
    category: str
    thickness: Optional[str]
    uom: str
    status: str = "PROPOSED"
    # 'CATALOG' = harga dari master harga; 'QUOTATION' = material proses yang
    # harganya diisi per CBD (lihat material_price_service.set_price_method).
    price_method: str = "CATALOG"


MATERIAL_CODE_PREFIX = "MTR-"
_MATERIAL_CODE_RE = re.compile(r"^MTR-(\d+)$", re.IGNORECASE)


def suggest_next_material_code(conn) -> str:
    """Isi awal Material Code di form tambah material: nomor `MTR-NNNN` terbesar
    yang sudah ada + 1 (minimal 4 digit). Kode dengan format lain diabaikan.
    Hanya saran — tetap bisa diedit dan tetap dicek unik saat disimpan."""
    highest = 0
    for row in conn.execute("SELECT material_code FROM material").fetchall():
        match = _MATERIAL_CODE_RE.match((row["material_code"] or "").strip())
        if match:
            highest = max(highest, int(match.group(1)))
    return f"{MATERIAL_CODE_PREFIX}{highest + 1:04d}"


def _clean_identity(data: MaterialInput):
    """Validasi & rapikan field identitas material (dipakai tambah dan edit)."""
    material_code = (data.material_code or "").strip()
    if not material_code:
        raise ValueError("Material Code wajib diisi.")
    name = (data.name or "").strip()
    if not name:
        raise ValueError("Material Name wajib diisi.")
    category = (data.category or "").strip()
    if not category:
        raise ValueError("Material Category wajib diisi.")
    uom = (data.uom or "").strip()
    if not uom:
        raise ValueError("Unit of Measurement wajib diisi.")
    thickness = (data.thickness or "").strip() or None
    return material_code, name, category, thickness, uom


def create_material(conn: sqlite3.Connection, data: MaterialInput, actor: str) -> str:
    material_code, name, category, thickness, uom = _clean_identity(data)
    if data.status not in ("PROPOSED", "APPROVED", "INACTIVE"):
        raise ValueError("Material Status tidak valid.")
    if data.price_method not in ("CATALOG", "QUOTATION"):
        raise ValueError("Metode harga tidak valid.")

    if conn.execute("SELECT 1 FROM material WHERE material_code=?", (material_code,)).fetchone():
        raise DuplicateMaterialCodeError()

    thickness_normalized = normalize_text(thickness)
    name_normalized = normalize_text(name)

    material_id = new_id()
    try:
        conn.execute(
            """INSERT INTO material
               (id, material_code, name, name_normalized, category, thickness,
                thickness_normalized, uom, status, price_method, created_by, updated_by)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                material_id,
                material_code,
                name,
                name_normalized,
                category,
                thickness,
                thickness_normalized,
                uom,
                data.status,
                data.price_method,
                actor,
                actor,
            ),
        )
    except sqlite3.IntegrityError as exc:
        if "UNIQUE" in str(exc):
            existing = find_exact(conn, name_normalized, thickness_normalized, uom)
            raise DuplicateMaterialError(existing) from exc
        raise

    write_audit_log(
        conn, actor, "Material", material_id, "CREATE", None,
        {"materialCode": material_code, "name": name, "category": category, "uom": uom, "status": data.status},
    )
    conn.commit()
    return material_id


def update_material(conn: sqlite3.Connection, material_id: str, data: MaterialInput, actor: str) -> None:
    """Edit identitas material (kode, nama, kategori, thickness, UoM) oleh Master
    Admin. Status & metode harga diubah lewat aksinya sendiri. BOM dan CBD DRAFT
    ikut menampilkan data baru (join ke material); baris CBD yang sudah terbit
    menyimpan UoM sebagai snapshot sehingga tidak berubah."""
    before = conn.execute("SELECT * FROM material WHERE id=?", (material_id,)).fetchone()
    if not before:
        raise ValueError("Material tidak ditemukan.")
    material_code, name, category, thickness, uom = _clean_identity(data)
    if conn.execute(
        "SELECT 1 FROM material WHERE material_code=? AND id<>?", (material_code, material_id)
    ).fetchone():
        raise DuplicateMaterialCodeError()
    name_normalized = normalize_text(name)
    thickness_normalized = normalize_text(thickness)
    existing = conn.execute(
        "SELECT * FROM material WHERE name_normalized=? AND thickness_normalized=? AND uom=? AND id<>?",
        (name_normalized, thickness_normalized, uom, material_id),
    ).fetchone()
    if existing:
        raise DuplicateMaterialError(existing)

    conn.execute(
        """UPDATE material SET material_code=?, name=?, name_normalized=?, category=?, thickness=?,
                  thickness_normalized=?, uom=?, updated_by=?, updated_at=datetime('now')
           WHERE id=?""",
        (material_code, name, name_normalized, category, thickness, thickness_normalized, uom, actor,
         material_id),
    )
    fields = {"materialCode": "material_code", "name": "name", "category": "category",
              "thickness": "thickness", "uom": "uom"}
    after = {"materialCode": material_code, "name": name, "category": category, "thickness": thickness, "uom": uom}
    write_audit_log(conn, actor, "Material", material_id, "UPDATE",
                     {k: before[col] for k, col in fields.items()}, after)
    conn.commit()


def find_exact(conn, name_normalized: str, thickness_normalized: str, uom: str):
    return conn.execute(
        "SELECT * FROM material WHERE name_normalized=? AND thickness_normalized=? AND uom=?",
        (name_normalized, thickness_normalized, uom),
    ).fetchone()


def find_similar(conn, name: str, limit: int = 10):
    key = normalize_text(name)
    if not key:
        return []
    rows = conn.execute(
        "SELECT * FROM material WHERE name_normalized LIKE ? ORDER BY name LIMIT ?",
        (f"%{key}%", limit),
    ).fetchall()
    return rows


def set_status(conn, material_id: str, new_status: str, actor: str) -> None:
    if new_status not in ("PROPOSED", "APPROVED", "INACTIVE"):
        raise ValueError("Status tidak valid.")
    before = conn.execute("SELECT * FROM material WHERE id=?", (material_id,)).fetchone()
    if not before:
        raise ValueError("Material tidak ditemukan.")
    conn.execute(
        "UPDATE material SET status=?, updated_by=?, updated_at=datetime('now') WHERE id=?",
        (new_status, actor, material_id),
    )
    write_audit_log(
        conn, actor, "Material", material_id, "STATUS_CHANGE",
        {"status": before["status"]}, {"status": new_status},
    )
    conn.commit()


def list_materials(conn, search: Optional[str] = None, status: Optional[str] = None,
                    category: Optional[str] = None, limit: int = 500):
    query = "SELECT * FROM material WHERE 1=1"
    params = []
    if search:
        query += " AND (name LIKE ? OR category LIKE ? OR material_code LIKE ?)"
        params.extend([f"%{search}%", f"%{search}%", f"%{search}%"])
    if status:
        query += " AND status=?"
        params.append(status)
    if category:
        query += " AND category=?"
        params.append(category)
    query += " ORDER BY name LIMIT ?"
    params.append(limit)
    return conn.execute(query, params).fetchall()
