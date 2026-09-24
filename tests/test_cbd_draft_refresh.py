import pytest

from app.domain.bom_service import add_component_line, update_cell_value
from app.domain.cbd_service import (
    create_cbd_no_source,
    list_cbd_lines,
    publish_cbd_revision,
    refresh_cbd_draft,
    override_price,
    update_yield,
)
from app.domain.revision_service import create_next_revision_same_stage, publish_revision


def _fill(conn, line, actor="TEST"):
    update_yield(conn, line["id"], "10", actor)
    override_price(conn, line["id"], "14.7", "USD", "harga test", actor)


def _revise_specsheet_with_new_used_line(conn, cbd_ctx):
    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    line2_id = add_component_line(
        conn, new_rev, cbd_ctx["component2_id"], cbd_ctx["material2_id"], "", "TEST",
        supplier_id=cbd_ctx["supplier_id"],
    )
    update_cell_value(conn, line2_id, cbd_ctx["article_id"], "Red", "TEST")
    publish_revision(conn, new_rev, "COMPONENT", "tambah komponen dipakai article", "TEST")
    return new_rev


def test_refresh_raises_when_already_in_sync(conn, cbd_ctx):
    cbd_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    with pytest.raises(ValueError, match="sudah sinkron"):
        refresh_cbd_draft(conn, cbd_id, "TEST")


def test_publish_blocked_when_specsheet_revised_while_cbd_draft(conn, cbd_ctx):
    cbd_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    for line in list_cbd_lines(conn, cbd_id):
        _fill(conn, line)

    _revise_specsheet_with_new_used_line(conn, cbd_ctx)

    with pytest.raises(ValueError, match="Refresh"):
        publish_cbd_revision(conn, cbd_id, "OTHER", "", "TEST")


def test_refresh_cbd_draft_preserves_filled_values_and_adds_new_line(conn, cbd_ctx):
    cbd_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    original_line = list_cbd_lines(conn, cbd_id)[0]
    _fill(conn, original_line)

    new_rev = _revise_specsheet_with_new_used_line(conn, cbd_ctx)

    refresh_cbd_draft(conn, cbd_id, "TEST")

    revision = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (cbd_id,)).fetchone()
    assert revision["specsheet_revision_id"] == new_rev

    lines = list_cbd_lines(conn, cbd_id)
    assert len(lines) == 2
    kept = next(l for l in lines if l["line_key"] == original_line["line_key"])
    assert kept["yield_value"] == "10"
    assert kept["price_original"] == "14.7"
    added = next(l for l in lines if l["line_key"] != original_line["line_key"])
    assert added["status"] == "ACTIVE"
    assert added["yield_value"] is None

    # baris baru belum berharga -> tetap boleh terbit (cost 0); diisi dulu di
    # sini supaya CBD-nya lengkap seperti alur normal
    _fill(conn, added)
    publish_cbd_revision(conn, cbd_id, "OTHER", "", "TEST")
    published = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (cbd_id,)).fetchone()
    assert published["status"] == "PUBLISHED"
