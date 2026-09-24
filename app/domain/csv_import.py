import csv
from dataclasses import dataclass, field
from typing import List, Tuple

from .component_service import ComponentNumberError, create_component
from .material_service import DuplicateMaterialError, MaterialInput, create_material
from .supplier_service import DuplicateSupplierError, SupplierInput, create_supplier


@dataclass
class ImportReport:
    success: int = 0
    errors: List[Tuple[int, str]] = field(default_factory=list)


def import_materials_csv(conn, path: str, actor: str) -> ImportReport:
    """Expected header: material_code,name,category,thickness,uom,status"""
    report = ImportReport()
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader, start=2):
            try:
                data = MaterialInput(
                    material_code=row.get("material_code", ""),
                    name=row.get("name", ""),
                    category=row.get("category", ""),
                    thickness=(row.get("thickness") or "").strip() or None,
                    uom=row.get("uom", ""),
                    status=(row.get("status") or "PROPOSED").strip().upper(),
                )
                create_material(conn, data, actor)
                report.success += 1
            except (ValueError, DuplicateMaterialError) as exc:
                report.errors.append((i, str(exc)))
    return report


def import_suppliers_csv(conn, path: str, actor: str) -> ImportReport:
    """Expected header: name,status"""
    report = ImportReport()
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader, start=2):
            try:
                data = SupplierInput(
                    name=row.get("name", ""),
                    status=(row.get("status") or "APPROVED").strip().upper(),
                )
                create_supplier(conn, data, actor)
                report.success += 1
            except (ValueError, DuplicateSupplierError) as exc:
                report.errors.append((i, str(exc)))
    return report


def import_components_csv(conn, path: str, actor: str) -> ImportReport:
    """Expected header: number,name,group_code,status"""
    report = ImportReport()
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader, start=2):
            try:
                group_code = (row.get("group_code") or "").strip()
                group = conn.execute(
                    "SELECT id FROM component_group WHERE code=?", (group_code,)
                ).fetchone()
                if not group:
                    raise ValueError(f"Kode kelompok '{group_code}' tidak dikenal.")
                number_raw = (row.get("number") or "").strip()
                if not number_raw.isdigit():
                    raise ValueError(f"Nomor '{number_raw}' bukan angka.")
                number = int(number_raw)
                name = row.get("name", "")
                status = (row.get("status") or "PROPOSED").strip().upper()
                create_component(conn, number, name, group["id"], status, actor)
                report.success += 1
            except (ValueError, ComponentNumberError) as exc:
                report.errors.append((i, str(exc)))
    return report
