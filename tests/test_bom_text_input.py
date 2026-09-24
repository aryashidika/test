"""Input ketik di grid BOM: komponen (master atau lokal), material (wajib dari
master), supplier (wajib dari Master Supplier), dan saran warna per season."""

import pytest

from app.domain.bom_service import (
    add_line_from_text,
    resolve_component_text,
    resolve_material_text,
    resolve_supplier_text,
    season_colors,
)
from app.domain.material_price_service import find_material_supplier
from app.domain.revision_service import create_empty_revision


@pytest.fixture
def draft(conn, specsheet_ctx):
    return create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")


def _line(conn, line_id):
    return conn.execute("SELECT * FROM bom_line WHERE id=?", (line_id,)).fetchone()


def test_resolve_component_by_label_number_or_unique_name(conn, specsheet_ctx):
    vamp = specsheet_ctx["component_id"]
    assert resolve_component_text(conn, "10 - Vamp")["id"] == vamp
    assert resolve_component_text(conn, " 10  -  vamp ")["id"] == vamp
    assert resolve_component_text(conn, "10")["id"] == vamp
    assert resolve_component_text(conn, "VAMP")["id"] == vamp
    assert resolve_component_text(conn, "Heel Tab Custom") is None


def test_typed_master_component_creates_master_line(conn, specsheet_ctx, draft):
    line_id = add_line_from_text(conn, draft, "10 - Vamp", "", "MTR-A · Kain A", "Supplier Test", "", "TEST")
    line = _line(conn, line_id)
    assert line["component_id"] == specsheet_ctx["component_id"]
    assert line["local_component_no"] is None
    assert line["supplier_id"] == specsheet_ctx["supplier_id"]


def test_unknown_component_becomes_local_and_requires_number(conn, specsheet_ctx, draft):
    with pytest.raises(ValueError, match="isi No."):
        add_line_from_text(conn, draft, "Heel Tab Custom", "", "MTR-A", "", "", "TEST")
    line_id = add_line_from_text(conn, draft, "Heel Tab Custom", "15", "MTR-A", "", "", "TEST")
    line = _line(conn, line_id)
    assert line["component_id"] is None
    assert (line["local_component_no"], line["local_component_name"]) == (15, "Heel Tab Custom")


def test_local_component_number_rules_still_apply(conn, specsheet_ctx, draft):
    with pytest.raises(ValueError, match="kelipatan 10"):
        add_line_from_text(conn, draft, "Heel Tab Custom", "30", "MTR-A", "", "", "TEST")
    with pytest.raises(ValueError, match="angka"):
        add_line_from_text(conn, draft, "Heel Tab Custom", "abc", "MTR-A", "", "", "TEST")


def test_unknown_component_number_alone_is_rejected(conn, specsheet_ctx, draft):
    with pytest.raises(ValueError, match="tidak ada di master"):
        add_line_from_text(conn, draft, "999", "15", "MTR-A", "", "", "TEST")


def test_material_must_exist_in_master(conn, specsheet_ctx):
    assert resolve_material_text(conn, "MTR-A · Kain A") == specsheet_ctx["material_id"]
    assert resolve_material_text(conn, "mtr-a") == specsheet_ctx["material_id"]
    assert resolve_material_text(conn, "kain a") == specsheet_ctx["material_id"]
    with pytest.raises(ValueError, match="tidak ada di master"):
        resolve_material_text(conn, "Kain Z")
    with pytest.raises(ValueError, match="wajib"):
        resolve_material_text(conn, "  ")


def test_supplier_must_exist_in_master_supplier(conn, specsheet_ctx):
    assert resolve_supplier_text(conn, " supplier   test ") == specsheet_ctx["supplier_id"]
    assert resolve_supplier_text(conn, "") is None
    with pytest.raises(ValueError, match="tidak ada di Master Supplier"):
        resolve_supplier_text(conn, "Supplier Baru")


def test_new_material_supplier_combination_becomes_proposed_link(conn, specsheet_ctx, draft):
    add_line_from_text(conn, draft, "Vamp", "", "MTR-B", "Supplier Test", "", "TEST")
    link = find_material_supplier(conn, specsheet_ctx["material2_id"], specsheet_ctx["supplier_id"])
    assert link["status"] == "PROPOSED"


def test_season_colors_cover_all_materials_in_that_season_only(conn, cbd_ctx):
    # cbd_ctx: FH26 memakai warna "Red". Tambah specsheet FH27 dengan warna lain.
    from app.domain.article_service import add_article
    from app.domain.bom_service import add_component_line, update_cell_value
    from app.domain.specsheet_service import create_specsheet

    fh27 = create_specsheet(conn, cbd_ctx["model_id"], "FH27", "TEST")
    rev = create_empty_revision(conn, fh27, "TEST")
    line_id = add_component_line(conn, rev, cbd_ctx["component_id"], cbd_ctx["material2_id"], "", "TEST")
    art = add_article(conn, rev, fh27, "ART-9", "Green", "TEST")
    update_cell_value(conn, line_id, art, "Forest Green", "TEST")

    assert season_colors(conn, "FH26") == ["Red"]
    assert season_colors(conn, "FH27") == ["Forest Green"]
