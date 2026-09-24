import pytest

from app.domain.material_service import (
    DuplicateMaterialCodeError,
    DuplicateMaterialError,
    MaterialInput,
    create_material,
)


def test_duplicate_material_rejected_after_normalization(conn):
    create_material(
        conn,
        MaterialInput(material_code="MTR-1", name="PU Foam", category="Foam",
                      thickness="2.5mm", uom="M", status="APPROVED"),
        "TEST",
    )
    with pytest.raises(DuplicateMaterialError):
        create_material(
            conn,
            MaterialInput(material_code="MTR-2", name="  pu   foam ", category="Foam",
                          thickness="2,5mm", uom="M", status="APPROVED"),
            "TEST",
        )


def test_different_uom_is_not_a_duplicate(conn):
    create_material(
        conn,
        MaterialInput("MTR-1", "PU Foam", "Foam", "2.5mm", "M", "APPROVED"),
        "TEST",
    )
    material_id = create_material(
        conn,
        MaterialInput("MTR-2", "PU Foam", "Foam", "2.5mm", "PCS", "APPROVED"),
        "TEST",
    )
    assert material_id


def test_duplicate_material_code_rejected(conn):
    create_material(
        conn,
        MaterialInput("MTR-1", "PU Foam", "Foam", "2.5mm", "M", "APPROVED"),
        "TEST",
    )
    with pytest.raises(DuplicateMaterialCodeError):
        create_material(
            conn,
            MaterialInput("MTR-1", "Kain Mesh", "Textile", None, "M", "APPROVED"),
            "TEST",
        )


def test_create_material_requires_material_code(conn):
    with pytest.raises(ValueError):
        create_material(
            conn,
            MaterialInput("", "PU Foam", "Foam", None, "M", "APPROVED"),
            "TEST",
        )


def test_create_material_requires_name(conn):
    with pytest.raises(ValueError):
        create_material(
            conn,
            MaterialInput("MTR-1", "", "Foam", None, "M", "APPROVED"),
            "TEST",
        )


def test_create_material_records_created_and_updated_by(conn):
    from app.domain.material_service import set_status

    material_id = create_material(
        conn,
        MaterialInput("MTR-1", "PU Foam", "Foam", None, "M", "APPROVED"),
        "ALICE",
    )
    row = conn.execute("SELECT * FROM material WHERE id=?", (material_id,)).fetchone()
    assert row["created_by"] == "ALICE"
    assert row["updated_by"] == "ALICE"

    set_status(conn, material_id, "INACTIVE", "BOB")
    row = conn.execute("SELECT * FROM material WHERE id=?", (material_id,)).fetchone()
    assert row["updated_by"] == "BOB"
