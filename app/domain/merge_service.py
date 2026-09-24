from .audit import write_audit_log

# (table, column) pairs that reference Material.id with a simple, non-composite key.
# Tables from later milestones (bom_line, cbd_line) are picked up automatically once
# they exist, without any change needed here.
SIMPLE_FK_TABLES = [
    ("bom_line", "material_id"),
    ("cbd_line", "material_id"),
]


def _existing_tables(conn):
    rows = conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
    return {r["name"] for r in rows}


def _merge_material_suppliers(conn, source_id, target_id) -> int:
    """material_supplier unik per (material, supplier), jadi tidak bisa dipindah
    lewat SIMPLE_FK_TABLES: kalau target sudah punya supplier yang sama, harga
    link sumber dipindah ke link target dan link sumber dinonaktifkan; kalau
    belum, link-nya sendiri dipindah ke target."""
    count = 0
    for link in conn.execute("SELECT * FROM material_supplier WHERE material_id=?", (source_id,)).fetchall():
        target_link = conn.execute(
            "SELECT id FROM material_supplier WHERE material_id=? AND supplier_id=?",
            (target_id, link["supplier_id"]),
        ).fetchone()
        if target_link:
            conn.execute("UPDATE material_price SET material_supplier_id=? WHERE material_supplier_id=?",
                         (target_link["id"], link["id"]))
            conn.execute("UPDATE material_supplier SET status='INACTIVE', is_preferred=0 WHERE id=?", (link["id"],))
        else:
            conn.execute("UPDATE material_supplier SET material_id=?, is_preferred=0 WHERE id=?",
                         (target_id, link["id"]))
        count += 1
    return count


def merge_materials(conn, source_id: str, target_id: str, actor: str) -> dict:
    if source_id == target_id:
        raise ValueError("Material sumber dan target tidak boleh sama.")
    source = conn.execute("SELECT * FROM material WHERE id=?", (source_id,)).fetchone()
    target = conn.execute("SELECT * FROM material WHERE id=?", (target_id,)).fetchone()
    if not source:
        raise ValueError("Material sumber tidak ditemukan.")
    if not target:
        raise ValueError("Material target tidak ditemukan.")

    moved: dict = {}
    existing = _existing_tables(conn)

    for table, column in SIMPLE_FK_TABLES:
        if table not in existing:
            continue
        count_row = conn.execute(
            f"SELECT COUNT(*) c FROM {table} WHERE {column}=?", (source_id,)
        ).fetchone()
        if count_row["c"]:
            conn.execute(f"UPDATE {table} SET {column}=? WHERE {column}=?", (target_id, source_id))
            moved[table] = count_row["c"]

    moved_links = _merge_material_suppliers(conn, source_id, target_id)
    if moved_links:
        moved["material_supplier"] = moved_links

    conn.execute(
        "UPDATE material SET merged_into_id=?, status='INACTIVE', updated_at=datetime('now') WHERE id=?",
        (target_id, source_id),
    )
    write_audit_log(
        conn, actor, "Material", source_id, "MERGE",
        {"status": source["status"], "mergedIntoId": source["merged_into_id"]},
        {"status": "INACTIVE", "mergedIntoId": target_id, "movedReferences": moved},
    )
    conn.commit()
    return moved
