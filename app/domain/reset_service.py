"""Reset data prototipe: kosongkan semua data transaksional + master data, lalu
seed ulang data dummy. ComponentGroup (a/c/d/e) tidak dihapus — itu referensi tetap.
"""
from .seed_data import seed_dummy_master_data
from .seed_specsheet_illuzion import ensure_illuzion_specsheet_seeded

_TABLES_IN_FK_SAFE_ORDER = [
    "audit_log", "change_log", "specsheet_photo",
    "cbd_line", "cbd_revision", "material_price", "material_supplier",
    "bom_cell", "bom_line",
    "revision_article", "article", "specsheet_revision", "specsheet",
    "product_model", "material_attachment",
    "material", "supplier", "component",
]


def reset_all_data(conn, actor: str = "RESET") -> None:
    for table in _TABLES_IN_FK_SAFE_ORDER:
        conn.execute(f"DELETE FROM {table}")
    conn.commit()
    seed_dummy_master_data(conn, actor)
    ensure_illuzion_specsheet_seeded(conn, actor)
