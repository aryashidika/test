import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.db import init_db  # noqa: E402
from app.domain.article_service import add_article  # noqa: E402
from app.domain.bom_service import add_component_line, update_cell_value  # noqa: E402
from app.domain.component_service import create_component  # noqa: E402
from app.domain.material_service import MaterialInput, create_material  # noqa: E402
from app.domain.model_service import ModelInput, create_model  # noqa: E402
from app.domain.revision_service import create_empty_revision, publish_revision  # noqa: E402
from app.domain.specsheet_service import create_specsheet  # noqa: E402
from app.domain.supplier_service import SupplierInput, create_supplier  # noqa: E402


@pytest.fixture
def conn():
    connection = sqlite3.connect(":memory:")
    connection.execute("PRAGMA foreign_keys = ON")
    connection.row_factory = sqlite3.Row
    init_db(connection)
    yield connection
    connection.close()


@pytest.fixture
def specsheet_ctx(conn):
    """Menyiapkan Model, Specsheet, komponen, supplier, dan dua material siap pakai untuk test M2."""
    model_id = create_model(
        conn, ModelInput(code="MDL-1", name="Model Test", factory="Factory Test"), "TEST"
    )
    specsheet_id = create_specsheet(conn, model_id, "FH26", "TEST")

    group_a = conn.execute("SELECT id FROM component_group WHERE code='a'").fetchone()["id"]
    component_id = create_component(conn, 10, "Vamp", group_a, "APPROVED", "TEST")
    component2_id = create_component(conn, 20, "Lining", group_a, "APPROVED", "TEST")

    material_id = create_material(
        conn, MaterialInput("MTR-A", "Kain A", "Textile", None, "M", "APPROVED"), "TEST"
    )
    material2_id = create_material(
        conn, MaterialInput("MTR-B", "Kain B", "Textile", None, "M", "APPROVED"), "TEST"
    )
    supplier_id = create_supplier(conn, SupplierInput("Supplier Test", "APPROVED"), "TEST")

    return {
        "model_id": model_id,
        "specsheet_id": specsheet_id,
        "component_id": component_id,
        "component2_id": component2_id,
        "material_id": material_id,
        "material2_id": material2_id,
        "supplier_id": supplier_id,
    }


@pytest.fixture
def cbd_ctx(conn, specsheet_ctx):
    """specsheet_ctx + satu revisi PULL r0 terpublish berisi satu baris BOM
    (component_id/material_id/supplier_id) dan satu article aktif yang
    memakainya — siap dipakai untuk generate CBD (M3)."""
    revision_id = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    line_id = add_component_line(
        conn, revision_id, specsheet_ctx["component_id"], specsheet_ctx["material_id"],
        "Cutting", "TEST", supplier_id=specsheet_ctx["supplier_id"],
    )
    article_id = add_article(conn, revision_id, specsheet_ctx["specsheet_id"], "ART-1", "Red", "TEST")
    update_cell_value(conn, line_id, article_id, "Red", "TEST")
    publish_revision(conn, revision_id, "OTHER", "", "TEST")

    return {
        **specsheet_ctx,
        "revision_id": revision_id,
        "line_id": line_id,
        "article_id": article_id,
    }
