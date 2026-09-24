from app.domain.bom_service import add_component_line, update_cell_value
from app.domain.cbd_service import (
    create_cbd_no_source,
    list_cbd_lines,
    publish_cbd_revision,
    override_price,
    update_yield,
)
from app.domain.revision_service import create_next_revision_same_stage, publish_revision


def _fill(conn, line, actor="TEST"):
    update_yield(conn, line["id"], "10", actor)
    override_price(conn, line["id"], "14.7", "USD", "harga test", actor)


def _publish_full_cbd(conn, article_id, actor="TEST"):
    revision_id = create_cbd_no_source(conn, article_id, "16300", actor)
    for line in list_cbd_lines(conn, revision_id):
        _fill(conn, line, actor)
    publish_cbd_revision(conn, revision_id, "OTHER", "", actor)
    return revision_id


def test_first_specsheet_publish_does_not_touch_any_cbd(conn, cbd_ctx):
    # cbd_ctx already published the specsheet's first (only) revision — nothing
    # to do here beyond confirming no crash happens when no CBD exists yet.
    row = conn.execute(
        "SELECT COUNT(*) c FROM cbd_revision WHERE article_id=?", (cbd_ctx["article_id"],)
    ).fetchone()
    assert row["c"] == 0


def test_unrelated_bom_change_keeps_cbd_in_sync(conn, cbd_ctx):
    cbd_id = _publish_full_cbd(conn, cbd_ctx["article_id"])

    # publish a new specsheet revision that changes nothing about this article's
    # expected lines (e.g. adds a component but never marks it used by the article)
    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    add_component_line(
        conn, new_rev, cbd_ctx["component2_id"], cbd_ctx["material2_id"], "", "TEST",
        supplier_id=cbd_ctx["supplier_id"],
    )
    publish_revision(conn, new_rev, "COMPONENT", "tambah komponen tak dipakai", "TEST")

    row = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (cbd_id,)).fetchone()
    assert row["sync_status"] == "IN_SYNC"
    assert row["specsheet_revision_id"] == new_rev


def test_bom_change_used_by_article_flags_needs_revision(conn, cbd_ctx):
    cbd_id = _publish_full_cbd(conn, cbd_ctx["article_id"])
    before = conn.execute("SELECT specsheet_revision_id FROM cbd_revision WHERE id=?", (cbd_id,)).fetchone()

    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    line2_id = add_component_line(
        conn, new_rev, cbd_ctx["component2_id"], cbd_ctx["material2_id"], "", "TEST",
        supplier_id=cbd_ctx["supplier_id"],
    )
    update_cell_value(conn, line2_id, cbd_ctx["article_id"], "Red", "TEST")
    publish_revision(conn, new_rev, "COMPONENT", "tambah komponen dipakai article", "TEST")

    row = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (cbd_id,)).fetchone()
    assert row["sync_status"] == "NEEDS_REVISION"
    # specsheet_revision_id stays at the last validated one, per PRD 6.6
    assert row["specsheet_revision_id"] == before["specsheet_revision_id"]


def test_sync_marking_only_affects_the_changed_articles_cbd(conn, cbd_ctx):
    from app.domain.article_service import add_article

    # second article on the same specsheet, unaffected by the change below
    setup_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    article2_id = add_article(conn, setup_rev, cbd_ctx["specsheet_id"], "ART-2", "Blue", "TEST")
    line_in_setup = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND line_key=(SELECT line_key FROM bom_line WHERE id=?)",
        (setup_rev, cbd_ctx["line_id"]),
    ).fetchone()
    update_cell_value(conn, line_in_setup["id"], article2_id, "Blue", "TEST")
    publish_revision(conn, setup_rev, "COMPONENT", "tambah article kedua", "TEST")

    cbd1_id = _publish_full_cbd(conn, cbd_ctx["article_id"])
    cbd2_id = _publish_full_cbd(conn, article2_id)

    # change only article 1's usage
    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    line2_id = add_component_line(
        conn, new_rev, cbd_ctx["component2_id"], cbd_ctx["material2_id"], "", "TEST",
        supplier_id=cbd_ctx["supplier_id"],
    )
    update_cell_value(conn, line2_id, cbd_ctx["article_id"], "Red", "TEST")
    publish_revision(conn, new_rev, "COMPONENT", "hanya article 1", "TEST")

    row1 = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (cbd1_id,)).fetchone()
    row2 = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (cbd2_id,)).fetchone()
    assert row1["sync_status"] == "NEEDS_REVISION"
    assert row2["sync_status"] == "IN_SYNC"
