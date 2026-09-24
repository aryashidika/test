import pytest

from app.domain.article_service import add_article
from app.domain.bom_service import add_component_line, update_cell_value
from app.domain.cbd_service import (
    create_cbd_no_source,
    list_cbd_lines,
    publish_cbd_revision,
    override_price,
    update_yield,
)
from app.domain.model_service import ModelInput, create_model
from app.domain.report_service import price_history, reference_price, validation_report, where_used
from app.domain.revision_service import create_empty_revision, create_next_revision_same_stage, publish_revision
from app.domain.specsheet_service import create_specsheet
from app.domain.supplier_service import SupplierInput, create_supplier


def _fill(conn, line, actor="TEST"):
    update_yield(conn, line["id"], "10", actor)
    override_price(conn, line["id"], "100000", "IDR", "harga test", actor)


def _publish_full_cbd(conn, article_id, actor="TEST"):
    revision_id = create_cbd_no_source(conn, article_id, "16300", actor)
    for line in list_cbd_lines(conn, revision_id):
        _fill(conn, line, actor)
    publish_cbd_revision(conn, revision_id, "OTHER", "", actor)
    return revision_id


def _publish_material_usage(conn, code, component_id, material_id, supplier_id, color,
                             price="100000", currency="IDR", actor="TEST"):
    """Model/specsheet/article baru, published, dengan satu baris BOM (material_id
    lewat component_id, warna `color`) dan CBD-nya published dengan harga
    `price`/`currency` — dipakai untuk skenario matching bertingkat `reference_price`."""
    model_id = create_model(conn, ModelInput(code=code, name=f"Model {code}", factory="F"), actor)
    specsheet_id = create_specsheet(conn, model_id, "FH26", actor)
    revision_id = create_empty_revision(conn, specsheet_id, actor)
    line_id = add_component_line(conn, revision_id, component_id, material_id, "", actor, supplier_id=supplier_id)
    article_id = add_article(conn, revision_id, specsheet_id, f"ART-{code}", color, actor)
    update_cell_value(conn, line_id, article_id, color, actor)
    publish_revision(conn, revision_id, "OTHER", "", actor)

    cbd_id = create_cbd_no_source(conn, article_id, "16300", actor)
    for line in list_cbd_lines(conn, cbd_id):
        update_yield(conn, line["id"], "10", actor)
        override_price(conn, line["id"], price, currency, "harga test", actor)
    publish_cbd_revision(conn, cbd_id, "OTHER", "", actor)
    return model_id, article_id, cbd_id


# ---------------- validation_report ----------------


def test_validation_report_all_matched_when_in_sync(conn, cbd_ctx):
    draft_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    report = validation_report(conn, draft_id)
    assert len(report["matched"]) == 1
    assert report["missing_in_cbd"] == []
    assert report["extra_in_cbd"] == []
    assert report["compared_against_latest_specsheet"] is False


def test_validation_report_flags_missing_and_extra_after_specsheet_drift(conn, cbd_ctx):
    cbd_id = _publish_full_cbd(conn, cbd_ctx["article_id"])

    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    line2 = add_component_line(
        conn, new_rev, cbd_ctx["component2_id"], cbd_ctx["material2_id"], "", "TEST",
        supplier_id=cbd_ctx["supplier_id"],
    )
    update_cell_value(conn, line2, cbd_ctx["article_id"], "Blue", "TEST")
    old_line = conn.execute("SELECT * FROM bom_line WHERE id=?", (cbd_ctx["line_id"],)).fetchone()
    new_line = conn.execute(
        "SELECT * FROM bom_line WHERE revision_id=? AND line_key=?", (new_rev, old_line["line_key"])
    ).fetchone()
    update_cell_value(conn, new_line["id"], cbd_ctx["article_id"], "none", "TEST")
    publish_revision(conn, new_rev, "COMPONENT", "swap komponen dipakai", "TEST")

    report = validation_report(conn, cbd_id)
    assert report["matched"] == []
    assert len(report["missing_in_cbd"]) == 1
    assert report["missing_in_cbd"][0]["material_name"] == "Kain B"
    assert len(report["extra_in_cbd"]) == 1
    assert report["extra_in_cbd"][0]["material_name"] == "Kain A"
    assert report["compared_against_latest_specsheet"] is True


# ---------------- where_used ----------------


def test_where_used_material_not_found(conn):
    with pytest.raises(ValueError):
        where_used(conn, "nonexistent")


def test_where_used_lists_current_usage(conn, cbd_ctx):
    results = where_used(conn, cbd_ctx["material_id"])
    assert len(results) == 1
    r = results[0]
    assert r["model_code"] == "MDL-1"
    assert r["article_code"] == "ART-1"
    assert r["stage"] == "PULL"
    assert r["revision_no"] == 0


def test_where_used_reflects_latest_revision_not_older_published_one(conn, cbd_ctx):
    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    line = conn.execute(
        "SELECT * FROM bom_line WHERE revision_id=? AND material_id=?", (new_rev, cbd_ctx["material_id"])
    ).fetchone()
    update_cell_value(conn, line["id"], cbd_ctx["article_id"], "none", "TEST")
    # new_rev is DRAFT (not published) but is the latest revision of this specsheet
    assert where_used(conn, cbd_ctx["material_id"]) == []


# ---------------- price_history ----------------


def test_price_history_default_stage_prod_ignores_other_stage_data(conn, cbd_ctx):
    _publish_full_cbd(conn, cbd_ctx["article_id"])  # specsheet/CBD stage is PULL here
    assert price_history(conn, cbd_ctx["material_id"]) == []


def test_price_history_groups_by_color_supplier_uom_currency(conn, cbd_ctx):
    _publish_full_cbd(conn, cbd_ctx["article_id"])
    groups = price_history(conn, cbd_ctx["material_id"], stage="PULL")
    assert len(groups) == 1
    g = groups[0]
    assert g["color"] == "Red"
    assert g["supplier"] == "Supplier Test"
    assert g["currency"] == "IDR"
    assert len(g["entries"]) == 1
    assert g["entries"][0]["price_original"] == "100000"


def test_price_history_excludes_draft_revisions(conn, cbd_ctx):
    draft_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    for line in list_cbd_lines(conn, draft_id):
        _fill(conn, line, "TEST")
    assert price_history(conn, cbd_ctx["material_id"], stage="PULL") == []


def test_price_history_invalid_stage_rejected(conn, cbd_ctx):
    with pytest.raises(ValueError):
        price_history(conn, cbd_ctx["material_id"], stage="NOPE")


# ---------------- reference_price ----------------


def test_reference_price_none_when_no_history(conn, cbd_ctx):
    assert reference_price(conn, cbd_ctx["material_id"]) is None


def test_reference_price_exact_tier_match(conn, cbd_ctx):
    _publish_material_usage(conn, "MDL-A", cbd_ctx["component_id"], cbd_ctx["material2_id"],
                             cbd_ctx["supplier_id"], "Red", price="50000")
    ref = reference_price(conn, cbd_ctx["material2_id"], color="Red", supplier_id=cbd_ctx["supplier_id"])
    assert ref["tier"] == "MATERIAL_COLOR_SUPPLIER"
    assert ref["price_original"] == "50000"
    assert ref["currency"] == "IDR"


def test_reference_price_color_match_case_insensitive_and_trimmed(conn, cbd_ctx):
    _publish_material_usage(conn, "MDL-A", cbd_ctx["component_id"], cbd_ctx["material2_id"],
                             cbd_ctx["supplier_id"], "Red", price="50000")
    ref = reference_price(conn, cbd_ctx["material2_id"], color="  red  ", supplier_id=cbd_ctx["supplier_id"])
    assert ref is not None
    assert ref["tier"] == "MATERIAL_COLOR_SUPPLIER"


def test_reference_price_supplier_tier_outranks_color_tier(conn, cbd_ctx):
    other_supplier_id = create_supplier(conn, SupplierInput(name="Other Supplier", status="APPROVED"), "TEST")
    # matches queried supplier but NOT queried color
    _publish_material_usage(conn, "MDL-A", cbd_ctx["component_id"], cbd_ctx["material2_id"],
                             cbd_ctx["supplier_id"], "Green", price="50000")
    # matches queried color but NOT queried supplier
    _publish_material_usage(conn, "MDL-B", cbd_ctx["component_id"], cbd_ctx["material2_id"],
                             other_supplier_id, "Red", price="77000")

    ref = reference_price(conn, cbd_ctx["material2_id"], color="Red", supplier_id=cbd_ctx["supplier_id"])
    assert ref["tier"] == "MATERIAL_SUPPLIER"
    assert ref["price_original"] == "50000"


def test_reference_price_falls_back_to_material_only(conn, cbd_ctx):
    other_supplier_id = create_supplier(conn, SupplierInput(name="Other Supplier", status="APPROVED"), "TEST")
    _publish_material_usage(conn, "MDL-A", cbd_ctx["component_id"], cbd_ctx["material2_id"],
                             other_supplier_id, "Green", price="33000")
    ref = reference_price(conn, cbd_ctx["material2_id"], color="Red", supplier_id=cbd_ctx["supplier_id"])
    assert ref["tier"] == "MATERIAL"
    assert ref["price_original"] == "33000"


def test_reference_price_without_color_or_supplier_uses_material_tier(conn, cbd_ctx):
    _publish_material_usage(conn, "MDL-A", cbd_ctx["component_id"], cbd_ctx["material2_id"],
                             cbd_ctx["supplier_id"], "Red", price="50000")
    ref = reference_price(conn, cbd_ctx["material2_id"])
    assert ref["tier"] == "MATERIAL"


def test_reference_price_picks_most_recently_published_within_tier(conn, cbd_ctx):
    other_supplier_id = create_supplier(conn, SupplierInput(name="Other Supplier", status="APPROVED"), "TEST")
    _publish_material_usage(conn, "MDL-A", cbd_ctx["component_id"], cbd_ctx["material2_id"],
                             other_supplier_id, "Green", price="10000")
    _publish_material_usage(conn, "MDL-B", cbd_ctx["component_id"], cbd_ctx["material2_id"],
                             other_supplier_id, "Green", price="20000")
    ref = reference_price(conn, cbd_ctx["material2_id"], color="Red", supplier_id=cbd_ctx["supplier_id"])
    assert ref["price_original"] == "20000"


def test_reference_price_ignores_unpublished_draft_cbd(conn, cbd_ctx):
    model_id = create_model(conn, ModelInput(code="MDL-A", name="Model A", factory="F"), "TEST")
    specsheet_id = create_specsheet(conn, model_id, "FH26", "TEST")
    revision_id = create_empty_revision(conn, specsheet_id, "TEST")
    line_id = add_component_line(conn, revision_id, cbd_ctx["component_id"], cbd_ctx["material2_id"], "", "TEST",
                                  supplier_id=cbd_ctx["supplier_id"])
    article_id = add_article(conn, revision_id, specsheet_id, "ART-A", "Red", "TEST")
    update_cell_value(conn, line_id, article_id, "Red", "TEST")
    publish_revision(conn, revision_id, "OTHER", "", "TEST")
    cbd_id = create_cbd_no_source(conn, article_id, "16300", "TEST")
    for line in list_cbd_lines(conn, cbd_id):
        update_yield(conn, line["id"], "10", "TEST")
        override_price(conn, line["id"], "99999", "IDR", "harga test", "TEST")
    # never published

    assert reference_price(conn, cbd_ctx["material2_id"], color="Red", supplier_id=cbd_ctx["supplier_id"]) is None
