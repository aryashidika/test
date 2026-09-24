"""Metode harga QUOTATION (material proses: printing, molding, dst) — harga
diisi langsung per baris CBD, tidak ada harga master; baris kosong boleh
diterbitkan (diwakili satu baris proses lain)."""

import pytest

from app.db import init_db
from app.domain.article_service import add_article
from app.domain.bom_service import update_cell_value
from app.domain.cbd_service import (
    create_cbd_from_article,
    create_cbd_no_source,
    create_cbd_same_stage,
    list_cbd_lines,
    override_price,
    publish_cbd_revision,
    refresh_cbd_prices,
    set_quotation_price,
    stale_master_price_lines,
    update_yield,
)
from app.domain.material_price_service import (
    add_price,
    find_material_supplier,
    materials_without_price,
    price_gap,
    set_price_method,
)
from app.domain.material_service import MaterialInput, create_material
from app.domain.revision_service import create_next_revision_same_stage, publish_revision


@pytest.fixture
def quotation_ctx(conn, cbd_ctx):
    """cbd_ctx dengan material baris BOM-nya dijadikan material proses."""
    set_price_method(conn, cbd_ctx["material_id"], "QUOTATION", "CBD")
    return cbd_ctx


def _line(conn, cbd_id):
    return list_cbd_lines(conn, cbd_id)[0]


def test_new_material_defaults_to_catalog_and_process_can_be_quotation(conn):
    mid = create_material(conn, MaterialInput("MTR-X", "Kain X", "Textile", None, "M", "APPROVED"), "T")
    pid = create_material(conn, MaterialInput("MTR-P", "Printing", "Proses Dekorasi", None, "PRS", "APPROVED",
                                              "QUOTATION"), "T")
    methods = dict(conn.execute("SELECT id, price_method FROM material").fetchall())
    assert methods[mid] == "CATALOG" and methods[pid] == "QUOTATION"
    with pytest.raises(ValueError):
        set_price_method(conn, mid, "LAINNYA", "T")


def test_quotation_material_has_no_master_price(conn, quotation_ctx):
    link = find_material_supplier(conn, quotation_ctx["material_id"], quotation_ctx["supplier_id"])
    with pytest.raises(ValueError, match="Quotation"):
        add_price(conn, link["id"], None, "20500", "IDR", None, None, "CBD")
    assert quotation_ctx["material_id"] not in materials_without_price(conn)
    assert price_gap(conn, quotation_ctx["material_id"], quotation_ctx["supplier_id"], "Red")["code"] == "QUOTATION"


def test_quotation_price_is_entered_in_cbd_without_reason(conn, quotation_ctx):
    cbd_id = create_cbd_no_source(conn, quotation_ctx["article_id"], "16300", "CBD")
    line = _line(conn, cbd_id)
    assert line["price_original"] is None and line["material_price_method"] == "QUOTATION"
    assert stale_master_price_lines(conn, cbd_id) == []

    set_quotation_price(conn, line["id"], "20500", "IDR", "Q-MGE-117", "CBD")
    line = _line(conn, cbd_id)
    assert (line["price_original"], line["currency"], line["price_source"], line["price_reference"]) == \
        ("20500", "IDR", "QUOTATION", "Q-MGE-117")

    # dikosongkan lagi = tidak dihargai terpisah
    set_quotation_price(conn, line["id"], "", "IDR", "", "CBD")
    line = _line(conn, cbd_id)
    assert line["price_original"] is None and line["price_source"] is None


def test_quotation_and_override_are_not_interchangeable(conn, cbd_ctx):
    cbd_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")
    line = _line(conn, cbd_id)
    with pytest.raises(ValueError, match="metode harga Quotation"):
        set_quotation_price(conn, line["id"], "100", "IDR", None, "CBD")  # material katalog

    set_price_method(conn, cbd_ctx["material_id"], "QUOTATION", "CBD")
    with pytest.raises(ValueError, match="tanpa override"):
        override_price(conn, line["id"], "100", "IDR", "nego", "CBD")


def test_empty_process_lines_can_be_published(conn, quotation_ctx):
    cbd_id = create_cbd_no_source(conn, quotation_ctx["article_id"], "16300", "CBD")
    publish_cbd_revision(conn, cbd_id, "OTHER", "", "CBD")
    assert conn.execute("SELECT status FROM cbd_revision WHERE id=?", (cbd_id,)).fetchone()["status"] == "PUBLISHED"


def test_quotation_carries_to_same_and_other_article(conn, quotation_ctx):
    first_id = create_cbd_no_source(conn, quotation_ctx["article_id"], "16300", "CBD")
    line = _line(conn, first_id)
    update_yield(conn, line["id"], "1", "CBD")
    set_quotation_price(conn, line["id"], "20500", "IDR", "Q-1", "CBD")
    publish_cbd_revision(conn, first_id, "OTHER", "", "CBD")

    same = _line(conn, create_cbd_same_stage(conn, quotation_ctx["article_id"], "CBD"))
    assert (same["price_original"], same["price_source"], same["price_reference"]) == ("20500", "QUOTATION", "Q-1")

    new_rev = create_next_revision_same_stage(conn, quotation_ctx["specsheet_id"], "TEST")
    art2 = add_article(conn, new_rev, quotation_ctx["specsheet_id"], "ART-2", "Blue", "TEST")
    bom_line = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND line_key=(SELECT line_key FROM bom_line WHERE id=?)",
        (new_rev, quotation_ctx["line_id"]),
    ).fetchone()
    update_cell_value(conn, bom_line["id"], art2, "Blue", "TEST")
    publish_revision(conn, new_rev, "COMPONENT", "tambah article", "TEST")

    other = _line(conn, create_cbd_from_article(conn, art2, quotation_ctx["article_id"], "16300", "CBD"))
    # "Copy dari Article Lain" ikut membawa harga quotation (harga + currency)
    assert (other["price_original"], other["currency"], other["price_source"]) == ("20500", "IDR", "QUOTATION")
    assert other["yield_value"] == "1"
    assert other["color"] == "Blue"  # warna tetap dari specsheet article tujuan


def test_switching_catalog_material_to_quotation_clears_master_price_on_refresh(conn, cbd_ctx):
    link = find_material_supplier(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"])
    add_price(conn, link["id"], None, "85000", "IDR", None, None, "CBD")
    cbd_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")
    assert _line(conn, cbd_id)["price_source"] == "MASTER"

    set_price_method(conn, cbd_ctx["material_id"], "QUOTATION", "CBD")
    assert len(stale_master_price_lines(conn, cbd_id)) == 1
    refresh_cbd_prices(conn, cbd_id, "CBD")
    assert _line(conn, cbd_id)["price_original"] is None


def test_migration_marks_process_category_as_quotation(conn):
    create_material(conn, MaterialInput("MTR-P", "Printing", "Proses Dekorasi", None, "PRS", "APPROVED"), "T")
    create_material(conn, MaterialInput("MTR-K", "Kain", "Textile", None, "M", "APPROVED"), "T")
    # simulasi database lama: kolom price_method belum ada
    conn.execute("ALTER TABLE material DROP COLUMN price_method")
    init_db(conn)
    methods = dict(conn.execute("SELECT material_code, price_method FROM material").fetchall())
    assert methods == {"MTR-P": "QUOTATION", "MTR-K": "CATALOG"}
