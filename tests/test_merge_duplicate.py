from app.domain.bom_service import add_component_line
from app.domain.material_service import MaterialInput, create_material
from app.domain.merge_service import merge_materials
from app.domain.revision_service import create_empty_revision


def test_merge_moves_references_and_writes_audit_log(conn, specsheet_ctx):
    source_id = create_material(conn, MaterialInput("MTR-C", "Kain C", "Textile", None, "M", "APPROVED"), "TEST")
    target_id = create_material(
        conn, MaterialInput("MTR-D", "Kain C Duplikat", "Textile", None, "M", "APPROVED"), "TEST"
    )
    revision_id = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    add_component_line(
        conn, revision_id, specsheet_ctx["component_id"], source_id, "", "TEST",
        supplier_id=specsheet_ctx["supplier_id"],
    )

    moved = merge_materials(conn, source_id, target_id, "TEST")

    assert moved.get("bom_line") == 1

    bom_row = conn.execute("SELECT * FROM bom_line WHERE material_id=?", (target_id,)).fetchone()
    assert bom_row is not None

    old_bom_row = conn.execute("SELECT * FROM bom_line WHERE material_id=?", (source_id,)).fetchone()
    assert old_bom_row is None

    source_row = conn.execute("SELECT * FROM material WHERE id=?", (source_id,)).fetchone()
    assert source_row["status"] == "INACTIVE"
    assert source_row["merged_into_id"] == target_id

    audit_rows = conn.execute(
        "SELECT * FROM audit_log WHERE entity='Material' AND entity_id=? AND action='MERGE'", (source_id,)
    ).fetchall()
    assert len(audit_rows) == 1


def test_merge_source_and_target_must_differ(conn):
    material_id = create_material(conn, MaterialInput("MTR-E", "Kain E", "Textile", None, "M", "APPROVED"), "TEST")
    import pytest

    with pytest.raises(ValueError):
        merge_materials(conn, material_id, material_id, "TEST")
