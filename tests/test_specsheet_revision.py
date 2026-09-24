import pytest

from app.domain.article_service import add_article
from app.domain.bom_service import add_component_line, replace_material, update_cell_value, update_process
from app.domain.revision_service import (
    create_carryover_revision,
    create_empty_revision,
    create_next_revision_same_stage,
    publish_revision,
)
from app.domain.specsheet_service import create_specsheet


def _setup_published_revision(conn, ctx):
    revision_id = create_empty_revision(conn, ctx["specsheet_id"], "TEST")
    article_id = add_article(conn, revision_id, ctx["specsheet_id"], "ART-1", "Black", "TEST")
    line_id = add_component_line(conn, revision_id, ctx["component_id"], ctx["material_id"], "Jahit", "TEST")
    update_cell_value(conn, line_id, article_id, "Black", "TEST")
    publish_revision(conn, revision_id, "COMPONENT", "", "TEST")
    return revision_id, article_id, line_id


def test_empty_revision_defaults_to_pull_but_stage_is_selectable(conn, specsheet_ctx):
    default_id = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    row = conn.execute("SELECT stage FROM specsheet_revision WHERE id=?", (default_id,)).fetchone()
    assert row["stage"] == "PULL"

    specsheet2_id = create_specsheet(conn, specsheet_ctx["model_id"], "FH27", "TEST")
    chosen_id = create_empty_revision(conn, specsheet2_id, "TEST", stage="GTM")
    row2 = conn.execute("SELECT stage FROM specsheet_revision WHERE id=?", (chosen_id,)).fetchone()
    assert row2["stage"] == "GTM"


def test_empty_revision_rejects_invalid_stage(conn, specsheet_ctx):
    with pytest.raises(ValueError):
        create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST", stage="NOT_A_STAGE")


def test_published_revision_is_immutable(conn, specsheet_ctx):
    revision_id, article_id, line_id = _setup_published_revision(conn, specsheet_ctx)

    row = conn.execute("SELECT status FROM specsheet_revision WHERE id=?", (revision_id,)).fetchone()
    assert row["status"] == "PUBLISHED"

    with pytest.raises(ValueError):
        update_process(conn, line_id, "Proses baru", "TEST")


def test_publish_rejects_specsheet_with_no_articles_at_all(conn, specsheet_ctx):
    revision_id = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    add_component_line(conn, revision_id, specsheet_ctx["component_id"], specsheet_ctx["material_id"], None, "TEST")
    with pytest.raises(ValueError):
        publish_revision(conn, revision_id, "COMPONENT", "", "TEST")


def test_publish_requires_article_to_use_at_least_one_line(conn, specsheet_ctx):
    revision_id = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    add_article(conn, revision_id, specsheet_ctx["specsheet_id"], "ART-1", "Black", "TEST")
    add_component_line(conn, revision_id, specsheet_ctx["component_id"], specsheet_ctx["material_id"], None, "TEST")
    # cell left isUsed=False by default -> publish must fail
    with pytest.raises(ValueError):
        publish_revision(conn, revision_id, "COMPONENT", "", "TEST")


def test_replace_material_creates_new_line_and_deactivates_old(conn, specsheet_ctx):
    revision_id, article_id, line_id = _setup_published_revision(conn, specsheet_ctx)
    original_line_key = conn.execute("SELECT line_key FROM bom_line WHERE id=?", (line_id,)).fetchone()[0]
    new_revision_id = create_next_revision_same_stage(conn, specsheet_ctx["specsheet_id"], "TEST")

    # lineKey is preserved across the new revision, but it's a distinct BomLine row (new id)
    line_id = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND line_key=?", (new_revision_id, original_line_key)
    ).fetchone()[0]

    new_line_id = replace_material(conn, new_revision_id, line_id, specsheet_ctx["material2_id"], "TEST")

    old_line = conn.execute("SELECT * FROM bom_line WHERE id=?", (line_id,)).fetchone()
    new_line = conn.execute("SELECT * FROM bom_line WHERE id=?", (new_line_id,)).fetchone()

    assert old_line["is_active"] == 0
    assert new_line["is_active"] == 1
    assert new_line["replaces_line_key"] == old_line["line_key"]
    assert new_line["material_id"] == specsheet_ctx["material2_id"]

    # BomCell (isUsed) carried over from the replaced line
    old_cell = conn.execute(
        "SELECT * FROM bom_cell WHERE bom_line_id=? AND article_id=?", (line_id, article_id)
    ).fetchone()
    new_cell = conn.execute(
        "SELECT * FROM bom_cell WHERE bom_line_id=? AND article_id=?", (new_line_id, article_id)
    ).fetchone()
    assert new_cell["is_used"] == old_cell["is_used"] == 1


def test_carryover_copies_lines_without_articles_or_cells(conn, specsheet_ctx):
    revision_id, article_id, line_id = _setup_published_revision(conn, specsheet_ctx)

    new_specsheet_id = create_specsheet(conn, specsheet_ctx["model_id"], "FH27", "TEST")
    carryover_revision_id = create_carryover_revision(conn, new_specsheet_id, revision_id, "TEST")

    old_line = conn.execute("SELECT * FROM bom_line WHERE id=?", (line_id,)).fetchone()
    new_lines = conn.execute(
        "SELECT * FROM bom_line WHERE revision_id=? AND is_active=1", (carryover_revision_id,)
    ).fetchall()

    assert len(new_lines) == 1
    assert new_lines[0]["origin_line_key"] == old_line["line_key"]
    assert new_lines[0]["line_key"] != old_line["line_key"]

    articles = conn.execute(
        "SELECT * FROM revision_article WHERE revision_id=?", (carryover_revision_id,)
    ).fetchall()
    assert articles == []

    cells = conn.execute(
        "SELECT * FROM bom_cell WHERE bom_line_id=?", (new_lines[0]["id"],)
    ).fetchall()
    assert cells == []
