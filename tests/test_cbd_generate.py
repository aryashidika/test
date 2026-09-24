import pytest

from app.domain.article_service import add_article
from app.domain.bom_service import add_component_line, replace_material, update_cell_value
from app.domain.cbd_service import (
    create_cbd_from_article,
    create_cbd_from_season,
    create_cbd_next_stage,
    create_cbd_no_source,
    create_cbd_same_stage,
    generate_or_merge_cbd,
    list_cbd_lines,
    publish_cbd_revision,
)
from app.domain.revision_service import create_empty_revision, create_next_revision_same_stage, publish_revision


def test_generate_no_source_includes_only_used_active_lines(conn, cbd_ctx):
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    lines = list_cbd_lines(conn, revision_id)
    assert len(lines) == 1
    line = lines[0]
    assert line["status"] == "ACTIVE"
    assert line["material_id"] == cbd_ctx["material_id"]
    assert line["value_origin"] == "INPUT"
    assert line["yield_value"] is None
    assert line["loss_pct"] == "0.00"  # default 0.00, bisa diedit
    assert line["supplier_id"] == cbd_ctx["supplier_id"]  # supplier CBD selalu ikut specsheet
    # master harga belum punya harga material + supplier ini -> harga & currency kosong
    assert line["price_original"] is None
    assert line["currency"] is None
    assert line["price_source"] is None


def test_generate_uses_specsheet_revisions_own_stage_not_hardcoded_pull(conn, cbd_ctx):
    # cbd_ctx's specsheet revision is created at stage PULL by default; create a
    # second article whose specsheet starts at a later stage and confirm the CBD
    # revision follows it (regression: create_cbd_no_source used to hardcode "PULL").
    from app.domain.specsheet_service import create_specsheet

    specsheet2_id = create_specsheet(conn, cbd_ctx["model_id"], "FH27", "TEST")
    rev2_id = create_empty_revision(conn, specsheet2_id, "TEST", stage="GTM")
    line2_id = add_component_line(
        conn, rev2_id, cbd_ctx["component_id"], cbd_ctx["material_id"], "", "TEST",
        supplier_id=cbd_ctx["supplier_id"],
    )
    article2_id = add_article(conn, rev2_id, specsheet2_id, "ART-1", "Red", "TEST")
    update_cell_value(conn, line2_id, article2_id, "Red", "TEST")
    publish_revision(conn, rev2_id, "OTHER", "", "TEST")

    revision_id = create_cbd_no_source(conn, article2_id, "16300", "TEST")
    row = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (revision_id,)).fetchone()
    assert row["stage"] == "GTM"


def test_generate_excludes_bom_cell_not_used_by_article(conn, cbd_ctx):
    # add a second component in a new draft revision, but never mark it used by the article
    # (cbd_ctx's own revision is already published by the fixture)
    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    add_component_line(
        conn, new_rev, cbd_ctx["component2_id"], cbd_ctx["material2_id"],
        "", "TEST", supplier_id=cbd_ctx["supplier_id"],
    )
    publish_revision(conn, new_rev, "COMPONENT", "tambah komponen", "TEST")

    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    materials = {l["material_id"] for l in list_cbd_lines(conn, revision_id)}
    assert cbd_ctx["material_id"] in materials
    assert cbd_ctx["material2_id"] not in materials


def test_only_one_draft_cbd_revision_per_article(conn, cbd_ctx):
    create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    with pytest.raises(ValueError, match="DRAFT"):
        create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")


def test_same_stage_revision_copies_values_by_line_key(conn, cbd_ctx):
    first_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    line = list_cbd_lines(conn, first_id)[0]
    from app.domain.cbd_service import override_price, update_yield

    update_yield(conn, line["id"], "10", "TEST")
    override_price(conn, line["id"], "14.7", "USD", "harga test", "TEST")
    publish_cbd_revision(conn, first_id, "OTHER", "", "TEST")

    second_id = create_cbd_same_stage(conn, cbd_ctx["article_id"], "TEST")
    second_line = list_cbd_lines(conn, second_id)[0]
    assert second_line["value_origin"] == "COPIED"
    assert second_line["yield_value"] == "10"
    assert second_line["usage_value"] == "0.1"
    assert second_line["price_original"] == "14.7"
    assert second_line["currency"] == "USD"
    assert second_line["value_source_ref"] is not None


def _fill_line_for_publish(conn, line):
    from app.domain.cbd_service import override_price, update_yield

    update_yield(conn, line["id"], "10", "TEST")
    override_price(conn, line["id"], "14.7", "USD", "harga test", "TEST")


def test_next_stage_advances_and_rejects_past_prod(conn, cbd_ctx):
    first_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    _fill_line_for_publish(conn, list_cbd_lines(conn, first_id)[0])
    publish_cbd_revision(conn, first_id, "OTHER", "", "TEST")

    second_id = create_cbd_next_stage(conn, cbd_ctx["article_id"], "TEST")
    row = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (second_id,)).fetchone()
    assert row["stage"] == "SMS"
    publish_cbd_revision(conn, second_id, "OTHER", "lanjut stage", "TEST")

    for _ in range(2):
        rid = create_cbd_next_stage(conn, cbd_ctx["article_id"], "TEST")
        publish_cbd_revision(conn, rid, "OTHER", "lanjut stage", "TEST")

    with pytest.raises(ValueError, match="PROD"):
        create_cbd_next_stage(conn, cbd_ctx["article_id"], "TEST")


def test_replaced_line_carries_yield_usage_loss_without_price(conn, cbd_ctx):
    first_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    line = list_cbd_lines(conn, first_id)[0]
    from app.domain.cbd_service import update_loss_pct, override_price, update_yield

    update_yield(conn, line["id"], "10", "TEST")
    update_loss_pct(conn, line["id"], "1.01", "TEST")
    override_price(conn, line["id"], "14.7", "USD", "harga test", "TEST")
    publish_cbd_revision(conn, first_id, "OTHER", "", "TEST")

    # ganti material (PRD 6.2) harus terjadi di revisi DRAFT baru, bukan di revisi
    # yang sudah terbit -> buat revisi baru stage sama dulu (lineKey dipertahankan).
    from app.domain.revision_service import create_next_revision_same_stage

    original_line_key = conn.execute(
        "SELECT line_key FROM bom_line WHERE id=?", (cbd_ctx["line_id"],)
    ).fetchone()["line_key"]
    new_spec_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    copied_line = conn.execute(
        "SELECT * FROM bom_line WHERE revision_id=? AND line_key=?", (new_spec_rev, original_line_key)
    ).fetchone()
    replace_material(conn, new_spec_rev, copied_line["id"], cbd_ctx["material2_id"], "TEST")
    publish_revision(conn, new_spec_rev, "MATERIAL", "ganti material", "TEST")

    second_id = create_cbd_same_stage(conn, cbd_ctx["article_id"], "TEST")
    second_line = list_cbd_lines(conn, second_id)[0]
    assert second_line["material_id"] == cbd_ctx["material2_id"]
    assert second_line["value_origin"] == "CARRIED_FROM_REPLACED"
    assert second_line["yield_value"] == "10"
    assert second_line["usage_value"] == "0.1"
    assert second_line["loss_pct"] == "1.01"
    assert second_line["price_original"] is None
    assert second_line["currency"] is None


def test_missing_in_spec_when_line_no_longer_expected(conn, cbd_ctx):
    # add a second component so the article still uses >=1 line after we drop the
    # first one below (specsheet publish requires every active article to use a line)
    setup_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    line2_id = add_component_line(
        conn, setup_rev, cbd_ctx["component2_id"], cbd_ctx["material2_id"],
        "", "TEST", supplier_id=cbd_ctx["supplier_id"],
    )
    update_cell_value(conn, line2_id, cbd_ctx["article_id"], "Red", "TEST")
    publish_revision(conn, setup_rev, "COMPONENT", "tambah komponen", "TEST")

    first_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    for line in list_cbd_lines(conn, first_id):
        _fill_line_for_publish(conn, line)
    publish_cbd_revision(conn, first_id, "OTHER", "", "TEST")

    # drop the article's usage of the FIRST BOM line only, in a new specsheet revision
    new_spec_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    original_line_key = conn.execute(
        "SELECT line_key FROM bom_line WHERE id=?", (cbd_ctx["line_id"],)
    ).fetchone()["line_key"]
    new_line = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND line_key=?", (new_spec_rev, original_line_key)
    ).fetchone()
    update_cell_value(conn, new_line["id"], cbd_ctx["article_id"], "", "TEST")
    publish_revision(conn, new_spec_rev, "COMPONENT", "drop usage", "TEST")

    second_id = create_cbd_same_stage(conn, cbd_ctx["article_id"], "TEST")
    lines = list_cbd_lines(conn, second_id)
    assert len(lines) == 2
    dropped = next(l for l in lines if l["material_id"] == cbd_ctx["material_id"])
    kept = next(l for l in lines if l["material_id"] == cbd_ctx["material2_id"])
    assert dropped["status"] == "MISSING_IN_SPEC"
    assert kept["status"] == "ACTIVE"


def test_copy_from_article_in_same_specsheet(conn, cbd_ctx):
    source_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    line = list_cbd_lines(conn, source_id)[0]
    from app.domain.cbd_service import override_price, update_yield

    update_yield(conn, line["id"], "10", "TEST")
    override_price(conn, line["id"], "14.7", "USD", "harga test", "TEST")
    publish_cbd_revision(conn, source_id, "OTHER", "", "TEST")

    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    other_article_id = add_article(conn, new_rev, cbd_ctx["specsheet_id"], "ART-2", "Blue", "TEST")
    line_in_new_rev = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND line_key=(SELECT line_key FROM bom_line WHERE id=?)",
        (new_rev, cbd_ctx["line_id"]),
    ).fetchone()
    update_cell_value(conn, line_in_new_rev["id"], other_article_id, "Blue", "TEST")
    publish_revision(conn, new_rev, "COMPONENT", "tambah article", "TEST")

    new_id = create_cbd_from_article(conn, other_article_id, cbd_ctx["article_id"], "16300", "TEST")
    new_line = list_cbd_lines(conn, new_id)[0]
    assert new_line["value_origin"] == "COPIED"
    assert new_line["usage_value"] == "0.1"


def test_copy_from_other_season_cross_specsheet(conn, cbd_ctx):
    from app.domain.cbd_service import override_price, update_yield
    from app.domain.specsheet_service import create_specsheet

    source_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    line = list_cbd_lines(conn, source_id)[0]
    update_yield(conn, line["id"], "10", "TEST")
    override_price(conn, line["id"], "14.7", "USD", "harga test", "TEST")
    publish_cbd_revision(conn, source_id, "OTHER", "", "TEST")

    # new season, same model, same component/material identity -> matches by identity tuple
    specsheet2_id = create_specsheet(conn, cbd_ctx["model_id"], "FH27", "TEST")
    rev2_id = create_empty_revision(conn, specsheet2_id, "TEST")
    line2_id = add_component_line(
        conn, rev2_id, cbd_ctx["component_id"], cbd_ctx["material_id"], "", "TEST",
        supplier_id=cbd_ctx["supplier_id"],
    )
    article2_id = add_article(conn, rev2_id, specsheet2_id, "ART-1", "Red", "TEST")
    update_cell_value(conn, line2_id, article2_id, "Red", "TEST")
    publish_revision(conn, rev2_id, "OTHER", "", "TEST")

    new_id = create_cbd_from_season(conn, article2_id, source_id, "16300", "TEST")
    new_line = list_cbd_lines(conn, new_id)[0]
    assert new_line["value_origin"] == "COPIED"
    assert new_line["usage_value"] == "0.1"


def test_generate_requires_positive_exchange_rate(conn, cbd_ctx):
    with pytest.raises(ValueError):
        create_cbd_no_source(conn, cbd_ctx["article_id"], "0", "TEST")


def test_generate_allows_blank_exchange_rate(conn, cbd_ctx):
    # Revision: exchange rate is no longer required up front when creating a
    # CBD revision — it can be filled in later, before publish.
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "", "TEST")
    row = conn.execute("SELECT exchange_rate FROM cbd_revision WHERE id=?", (revision_id,)).fetchone()
    assert row["exchange_rate"] is None
