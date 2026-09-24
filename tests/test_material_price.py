"""Master harga (tambahan di luar PRD): link material–supplier, harga per
supplier/warna berbasis periode, dan pemakaiannya di CBD."""

import datetime

import pytest

from app.domain.article_service import add_article
from app.domain.bom_service import add_component_line, update_cell_value, update_line_supplier
from app.domain.cbd_service import (
    clear_price_override,
    create_cbd_from_article,
    create_cbd_no_source,
    create_cbd_same_stage,
    list_cbd_lines,
    override_price,
    publish_cbd_revision,
    refresh_cbd_prices,
    stale_master_price_lines,
    update_yield,
)
from app.domain.material_price_service import (
    add_material_supplier,
    add_price,
    default_supplier_for,
    end_price,
    find_material_supplier,
    lookup_price,
    price_gap,
    set_material_supplier_status,
    set_preferred_supplier,
    supplier_suggestions,
)
from app.domain.report_service import reference_price
from app.domain.revision_service import create_next_revision_same_stage, publish_revision
from app.domain.supplier_service import SupplierInput, create_supplier, set_status as set_supplier_status


def _link(conn, ctx):
    return find_material_supplier(conn, ctx["material_id"], ctx["supplier_id"])


def _days(n):
    return (datetime.date.today() + datetime.timedelta(days=n)).isoformat()


# ---------------- link material–supplier ----------------


def test_selecting_supplier_in_bom_creates_proposed_link(conn, cbd_ctx):
    link = _link(conn, cbd_ctx)
    assert link is not None
    assert link["status"] == "PROPOSED"
    assert link["created_by"] == "TEST"


def test_inactive_link_blocks_selecting_that_supplier_again(conn, cbd_ctx):
    set_material_supplier_status(conn, _link(conn, cbd_ctx)["id"], "INACTIVE", "ADMIN")
    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    with pytest.raises(ValueError, match="dinonaktifkan"):
        add_component_line(conn, new_rev, cbd_ctx["component2_id"], cbd_ctx["material_id"], "", "TEST",
                           supplier_id=cbd_ctx["supplier_id"])


def test_inactive_master_supplier_cannot_be_linked(conn, specsheet_ctx):
    set_supplier_status(conn, specsheet_ctx["supplier_id"], "INACTIVE", "ADMIN")
    with pytest.raises(ValueError, match="dinonaktifkan"):
        add_material_supplier(conn, specsheet_ctx["material_id"], specsheet_ctx["supplier_id"], None, False,
                              "APPROVED", "ADMIN")


def test_preferred_supplier_is_unique_and_used_as_default(conn, specsheet_ctx):
    other = create_supplier(conn, SupplierInput("Supplier Lain", "APPROVED"), "ADMIN")
    link1 = add_material_supplier(conn, specsheet_ctx["material_id"], specsheet_ctx["supplier_id"], "A-1",
                                  True, "APPROVED", "ADMIN")
    link2 = add_material_supplier(conn, specsheet_ctx["material_id"], other, "B-1", False, "APPROVED", "ADMIN")
    assert default_supplier_for(conn, specsheet_ctx["material_id"])["id"] == link1

    set_preferred_supplier(conn, link2, "ADMIN")
    assert default_supplier_for(conn, specsheet_ctx["material_id"])["id"] == link2
    preferred = conn.execute(
        "SELECT COUNT(*) c FROM material_supplier WHERE material_id=? AND is_preferred=1",
        (specsheet_ctx["material_id"],),
    ).fetchone()["c"]
    assert preferred == 1


def test_supplier_suggestions_list_linked_first_and_hide_inactive_links(conn, specsheet_ctx):
    other = create_supplier(conn, SupplierInput("AAA Supplier", "APPROVED"), "ADMIN")
    dropped = create_supplier(conn, SupplierInput("Dropped Supplier", "APPROVED"), "ADMIN")
    add_material_supplier(conn, specsheet_ctx["material_id"], specsheet_ctx["supplier_id"], None, True,
                          "APPROVED", "ADMIN")
    dropped_link = add_material_supplier(conn, specsheet_ctx["material_id"], dropped, None, False,
                                         "APPROVED", "ADMIN")
    set_material_supplier_status(conn, dropped_link, "INACTIVE", "ADMIN")

    names = [s["name"] for s in supplier_suggestions(conn, specsheet_ctx["material_id"])]
    assert names[0] == "Supplier Test"  # terdaftar + utama, walau alfabetis kalah dari "AAA"
    assert "AAA Supplier" in names
    assert "Dropped Supplier" not in names
    assert other  # supplier aktif lain tetap ditawarkan di kelompok bawah


# ---------------- harga ----------------


def test_new_price_closes_previous_one_instead_of_overwriting(conn, cbd_ctx):
    link_id = _link(conn, cbd_ctx)["id"]
    first = add_price(conn, link_id, None, "85000", "IDR", _days(-10), "Q-1", "CBD")
    second = add_price(conn, link_id, None, "90000", "IDR", _days(-1), "Q-2", "CBD")

    rows = {r["id"]: r for r in conn.execute("SELECT * FROM material_price").fetchall()}
    assert rows[first]["valid_to"] == _days(-1)
    assert rows[second]["valid_to"] is None
    assert lookup_price(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"])["price"] == "90000"


def test_new_price_cannot_start_before_the_price_it_replaces(conn, cbd_ctx):
    link_id = _link(conn, cbd_ctx)["id"]
    add_price(conn, link_id, None, "85000", "IDR", _days(-1), None, "CBD")
    with pytest.raises(ValueError, match="tidak boleh lebih awal"):
        add_price(conn, link_id, None, "80000", "IDR", _days(-5), None, "CBD")


def test_same_day_price_is_a_correction(conn, cbd_ctx):
    link_id = _link(conn, cbd_ctx)["id"]
    add_price(conn, link_id, None, "85000", "IDR", None, None, "CBD")
    add_price(conn, link_id, None, "58000", "IDR", None, "salah ketik", "CBD")
    assert lookup_price(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"])["price"] == "58000"


def test_future_price_is_not_used_yet(conn, cbd_ctx):
    link_id = _link(conn, cbd_ctx)["id"]
    add_price(conn, link_id, None, "85000", "IDR", _days(-1), None, "CBD")
    add_price(conn, link_id, None, "95000", "IDR", _days(30), None, "CBD")
    assert lookup_price(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"])["price"] == "85000"
    assert lookup_price(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"], on_date=_days(30))["price"] == "95000"


def test_price_validation(conn, cbd_ctx):
    link_id = _link(conn, cbd_ctx)["id"]
    with pytest.raises(ValueError):
        add_price(conn, link_id, None, "", "IDR", None, None, "CBD")
    with pytest.raises(ValueError):
        add_price(conn, link_id, None, "-5", "IDR", None, None, "CBD")
    with pytest.raises(ValueError):
        add_price(conn, link_id, None, "5", "EUR", None, None, "CBD")
    with pytest.raises(ValueError):
        add_price(conn, link_id, None, "5", "IDR", "23/09/2026", None, "CBD")
    assert add_price(conn, link_id, None, "1,5", "USD", None, None, "CBD")  # koma desimal diterima


def test_color_price_wins_over_all_colors_and_falls_back(conn, cbd_ctx):
    link_id = _link(conn, cbd_ctx)["id"]
    add_price(conn, link_id, None, "85000", "IDR", None, None, "CBD")
    add_price(conn, link_id, "Neon Yellow", "92000", "IDR", None, None, "CBD")

    neon = lookup_price(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"], "  neon   yellow ")
    assert neon["price"] == "92000" and neon["tier"] == "COLOR"
    white = lookup_price(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"], "White")
    assert white["price"] == "85000" and white["tier"] == "ALL_COLORS"


def test_no_cross_supplier_fallback(conn, cbd_ctx):
    other = create_supplier(conn, SupplierInput("Supplier Lain", "APPROVED"), "ADMIN")
    link_id = add_material_supplier(conn, cbd_ctx["material_id"], other, None, False, "APPROVED", "ADMIN")
    add_price(conn, link_id, None, "70000", "IDR", None, None, "CBD")
    assert lookup_price(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"]) is None


def test_price_gap_reasons(conn, cbd_ctx):
    assert price_gap(conn, cbd_ctx["material_id"], None)["code"] == "NO_SUPPLIER"
    assert price_gap(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"], "Red")["code"] == "NO_PRICE"

    link_id = _link(conn, cbd_ctx)["id"]
    add_price(conn, link_id, "White", "80000", "IDR", None, None, "CBD")
    gap = price_gap(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"], "Red")
    assert gap == {"code": "NO_COLOR_PRICE", "colors": ["White"]}
    assert price_gap(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"], "white") is None


def test_ending_color_price_returns_to_all_colors_price(conn, cbd_ctx):
    link_id = _link(conn, cbd_ctx)["id"]
    add_price(conn, link_id, None, "85000", "IDR", _days(-5), None, "CBD")
    neon_id = add_price(conn, link_id, "Red", "92000", "IDR", _days(-5), None, "CBD")
    end_price(conn, neon_id, "CBD")
    assert lookup_price(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"], "Red")["price"] == "85000"


# ---------------- pemakaian di CBD ----------------


def test_generate_cbd_takes_price_from_master(conn, cbd_ctx):
    link_id = _link(conn, cbd_ctx)["id"]
    add_price(conn, link_id, None, "85000", "IDR", None, None, "CBD")
    red_id = add_price(conn, link_id, "Red", "92000", "IDR", None, None, "CBD")

    cbd_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")
    line = list_cbd_lines(conn, cbd_id)[0]
    assert line["price_original"] == "92000"  # article memakai warna Red
    assert line["currency"] == "IDR"
    assert line["price_source"] == "MASTER"
    assert line["material_price_id"] == red_id
    assert line["master_price_color"] == "Red"


def test_master_price_change_must_be_refreshed_before_publish(conn, cbd_ctx):
    link_id = _link(conn, cbd_ctx)["id"]
    add_price(conn, link_id, None, "85000", "IDR", _days(-1), None, "CBD")
    cbd_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")
    update_yield(conn, list_cbd_lines(conn, cbd_id)[0]["id"], "2", "CBD")

    add_price(conn, link_id, None, "90000", "IDR", None, "harga naik", "CBD")
    assert len(stale_master_price_lines(conn, cbd_id)) == 1
    with pytest.raises(ValueError, match="Refresh Harga dari Master"):
        publish_cbd_revision(conn, cbd_id, "OTHER", "", "CBD")

    assert refresh_cbd_prices(conn, cbd_id, "CBD") == 1
    assert list_cbd_lines(conn, cbd_id)[0]["price_original"] == "90000"
    publish_cbd_revision(conn, cbd_id, "OTHER", "", "CBD")


def test_price_added_to_master_later_fills_empty_line_on_refresh(conn, cbd_ctx):
    cbd_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")
    assert stale_master_price_lines(conn, cbd_id) == []

    add_price(conn, _link(conn, cbd_ctx)["id"], None, "85000", "IDR", None, None, "CBD")
    assert len(stale_master_price_lines(conn, cbd_id)) == 1
    refresh_cbd_prices(conn, cbd_id, "CBD")
    assert list_cbd_lines(conn, cbd_id)[0]["price_original"] == "85000"


def test_published_cbd_keeps_its_snapshot_when_master_changes(conn, cbd_ctx):
    link_id = _link(conn, cbd_ctx)["id"]
    add_price(conn, link_id, None, "85000", "IDR", _days(-1), None, "CBD")
    cbd_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")
    update_yield(conn, list_cbd_lines(conn, cbd_id)[0]["id"], "2", "CBD")
    publish_cbd_revision(conn, cbd_id, "OTHER", "", "CBD")

    add_price(conn, link_id, None, "99000", "IDR", None, None, "CBD")
    assert list_cbd_lines(conn, cbd_id)[0]["price_original"] == "85000"

    next_id = create_cbd_same_stage(conn, cbd_ctx["article_id"], "CBD")
    assert list_cbd_lines(conn, next_id)[0]["price_original"] == "99000"


def test_override_requires_reason_and_can_be_cleared(conn, cbd_ctx):
    add_price(conn, _link(conn, cbd_ctx)["id"], None, "85000", "IDR", None, None, "CBD")
    cbd_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")
    line = list_cbd_lines(conn, cbd_id)[0]

    with pytest.raises(ValueError, match="Alasan"):
        override_price(conn, line["id"], "80000", "IDR", "  ", "CBD")
    override_price(conn, line["id"], "80000", "IDR", "nego order ini", "CBD")
    line = list_cbd_lines(conn, cbd_id)[0]
    assert (line["price_original"], line["price_source"], line["material_price_id"]) == ("80000", "OVERRIDE", None)
    assert stale_master_price_lines(conn, cbd_id) == []  # override tidak ikut di-refresh

    clear_price_override(conn, line["id"], "CBD")
    line = list_cbd_lines(conn, cbd_id)[0]
    assert (line["price_original"], line["price_source"]) == ("85000", "MASTER")


def test_override_carries_to_same_and_other_article(conn, cbd_ctx):
    add_price(conn, _link(conn, cbd_ctx)["id"], None, "85000", "IDR", None, None, "CBD")
    first_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")
    line = list_cbd_lines(conn, first_id)[0]
    update_yield(conn, line["id"], "2", "CBD")
    override_price(conn, line["id"], "80000", "IDR", "nego", "CBD")
    publish_cbd_revision(conn, first_id, "OTHER", "", "CBD")

    same_article = list_cbd_lines(conn, create_cbd_same_stage(conn, cbd_ctx["article_id"], "CBD"))[0]
    assert (same_article["price_original"], same_article["price_source"]) == ("80000", "OVERRIDE")
    assert same_article["price_override_reason"] == "nego"

    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    other_article = add_article(conn, new_rev, cbd_ctx["specsheet_id"], "ART-2", "Blue", "TEST")
    line_in_new_rev = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND line_key=(SELECT line_key FROM bom_line WHERE id=?)",
        (new_rev, cbd_ctx["line_id"]),
    ).fetchone()
    update_cell_value(conn, line_in_new_rev["id"], other_article, "Red", "TEST")
    publish_revision(conn, new_rev, "COMPONENT", "tambah article", "TEST")

    copied = list_cbd_lines(conn, create_cbd_from_article(conn, other_article, cbd_ctx["article_id"], "16300", "CBD"))[0]
    # "Copy dari Article Lain" ikut membawa override (beserta alasannya)
    assert (copied["price_original"], copied["price_source"]) == ("80000", "OVERRIDE")
    assert copied["price_override_reason"] == "nego"
    assert copied["yield_value"] == "2"
    assert copied["color"] == "Red"  # warna tetap dari specsheet article tujuan


def test_supplier_change_in_specsheet_flags_published_cbd(conn, cbd_ctx):
    add_price(conn, _link(conn, cbd_ctx)["id"], None, "85000", "IDR", None, None, "CBD")
    cbd_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")
    update_yield(conn, list_cbd_lines(conn, cbd_id)[0]["id"], "2", "CBD")
    publish_cbd_revision(conn, cbd_id, "OTHER", "", "CBD")

    other = create_supplier(conn, SupplierInput("Supplier Lain", "APPROVED"), "ADMIN")
    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    line = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND line_key=(SELECT line_key FROM bom_line WHERE id=?)",
        (new_rev, cbd_ctx["line_id"]),
    ).fetchone()
    update_line_supplier(conn, line["id"], other, "TEST")
    publish_revision(conn, new_rev, "MATERIAL", "ganti supplier", "TEST")

    row = conn.execute("SELECT sync_status FROM cbd_revision WHERE id=?", (cbd_id,)).fetchone()
    assert row["sync_status"] == "NEEDS_REVISION"
    assert find_material_supplier(conn, cbd_ctx["material_id"], other)["status"] == "PROPOSED"


def test_reference_price_prefers_master(conn, cbd_ctx):
    add_price(conn, _link(conn, cbd_ctx)["id"], None, "85000", "IDR", None, None, "CBD")
    ref = reference_price(conn, cbd_ctx["material_id"], "Red", cbd_ctx["supplier_id"])
    assert ref["tier"] == "MASTER"
    assert ref["price_original"] == "85000"
