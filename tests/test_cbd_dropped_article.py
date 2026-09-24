"""Article yang di-drop di specsheet terbit tidak boleh lagi dibuatkan/diubah
CBD-nya — status CBD mengikuti revisi specsheet TERBIT terakhir."""

import pytest

from app.domain.article_service import add_article, set_article_status
from app.domain.bom_service import update_cell_value
from app.domain.cbd_service import (
    article_cbd_status,
    build_expected_lines,
    create_cbd_no_source,
    list_cbd_lines,
    override_price,
    publish_cbd_revision,
    update_yield,
)
from app.domain.report_service import where_used
from app.domain.revision_service import create_next_revision_same_stage, publish_revision


@pytest.fixture
def two_articles(conn, cbd_ctx):
    """cbd_ctx + article kedua (ART-2) yang juga memakai baris BOM, terbit."""
    rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    art2 = add_article(conn, rev, cbd_ctx["specsheet_id"], "ART-2", "Blue", "TEST")
    line = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND line_key=(SELECT line_key FROM bom_line WHERE id=?)",
        (rev, cbd_ctx["line_id"]),
    ).fetchone()
    update_cell_value(conn, line["id"], art2, "Blue", "TEST")
    publish_revision(conn, rev, "COMPONENT", "tambah article", "TEST")
    return {**cbd_ctx, "article2_id": art2}


def _drop_and_publish(conn, ctx, article_id):
    rev = create_next_revision_same_stage(conn, ctx["specsheet_id"], "TEST")
    set_article_status(conn, rev, article_id, "DROPPED", "TEST")
    return rev


def test_drop_only_counts_after_specsheet_publish(conn, two_articles):
    rev = _drop_and_publish(conn, two_articles, two_articles["article2_id"])
    assert article_cbd_status(conn, two_articles["article2_id"]) == "ACTIVE"  # masih DRAFT
    publish_revision(conn, rev, "COMPONENT", "drop ART-2", "TEST")
    assert article_cbd_status(conn, two_articles["article2_id"]) == "DROPPED"
    assert article_cbd_status(conn, two_articles["article_id"]) == "ACTIVE"


def test_cannot_create_cbd_for_dropped_article(conn, two_articles):
    rev = _drop_and_publish(conn, two_articles, two_articles["article2_id"])
    publish_revision(conn, rev, "COMPONENT", "drop ART-2", "TEST")

    # Sel BOM article yang di-drop tetap is_used, tapi tidak boleh jadi baris CBD.
    assert build_expected_lines(conn, two_articles["article2_id"], rev) == []
    with pytest.raises(ValueError, match="di-drop"):
        create_cbd_no_source(conn, two_articles["article2_id"], "16300", "TEST")
    # Article lain tidak terpengaruh.
    create_cbd_no_source(conn, two_articles["article_id"], "16300", "TEST")


def test_existing_draft_of_dropped_article_becomes_read_only(conn, two_articles):
    cbd_id = create_cbd_no_source(conn, two_articles["article2_id"], "16300", "TEST")
    line = list_cbd_lines(conn, cbd_id)[0]

    rev = _drop_and_publish(conn, two_articles, two_articles["article2_id"])
    publish_revision(conn, rev, "COMPONENT", "drop ART-2", "TEST")

    with pytest.raises(ValueError, match="di-drop"):
        update_yield(conn, line["id"], "10", "TEST")
    with pytest.raises(ValueError, match="di-drop"):
        override_price(conn, line["id"], "10", "IDR", "x", "TEST")
    with pytest.raises(ValueError, match="di-drop"):
        publish_cbd_revision(conn, cbd_id, "OTHER", "", "TEST")


def test_reactivated_article_can_get_cbd_again(conn, two_articles):
    rev = _drop_and_publish(conn, two_articles, two_articles["article2_id"])
    publish_revision(conn, rev, "COMPONENT", "drop ART-2", "TEST")
    rev2 = create_next_revision_same_stage(conn, two_articles["specsheet_id"], "TEST")
    set_article_status(conn, rev2, two_articles["article2_id"], "ACTIVE", "TEST")
    publish_revision(conn, rev2, "COMPONENT", "aktifkan lagi ART-2", "TEST")

    assert article_cbd_status(conn, two_articles["article2_id"]) == "ACTIVE"
    assert list_cbd_lines(conn, create_cbd_no_source(conn, two_articles["article2_id"], "16300", "TEST"))


def test_article_only_in_draft_revision_is_not_available_for_cbd(conn, cbd_ctx):
    rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    art_new = add_article(conn, rev, cbd_ctx["specsheet_id"], "ART-NEW", "Green", "TEST")
    assert article_cbd_status(conn, art_new) == "NOT_PUBLISHED"
    with pytest.raises(ValueError, match="belum ada di revisi specsheet yang terbit"):
        create_cbd_no_source(conn, art_new, "16300", "TEST")


def test_where_used_skips_dropped_article(conn, two_articles):
    rev = _drop_and_publish(conn, two_articles, two_articles["article2_id"])
    publish_revision(conn, rev, "COMPONENT", "drop ART-2", "TEST")
    codes = {r["article_code"] for r in where_used(conn, two_articles["material_id"])}
    assert codes == {"ART-1"}
