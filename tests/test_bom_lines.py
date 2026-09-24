import pytest

from app.domain.bom_service import (
    add_component_line,
    add_local_component_line,
    add_subcomponent_line,
    list_lines_with_cells,
)
from app.domain.revision_service import create_empty_revision, create_next_revision_same_stage


def test_local_component_number_must_not_be_multiple_of_ten(conn, specsheet_ctx):
    revision_id = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    with pytest.raises(ValueError):
        add_local_component_line(conn, revision_id, 20, "Aksesoris", specsheet_ctx["material_id"], None, "TEST")


def test_local_component_number_unique_within_revision(conn, specsheet_ctx):
    revision_id = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    add_local_component_line(conn, revision_id, 15, "Aksesoris A", specsheet_ctx["material_id"], None, "TEST")
    with pytest.raises(ValueError):
        add_local_component_line(conn, revision_id, 15, "Aksesoris B", specsheet_ctx["material2_id"], None, "TEST")


def test_subcomponent_seq_increments_and_display(conn, specsheet_ctx):
    revision_id = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    line_id = add_component_line(conn, revision_id, specsheet_ctx["component_id"],
                                  specsheet_ctx["material_id"], None, "TEST")
    sub1 = add_subcomponent_line(conn, revision_id, line_id, "Cuci", specsheet_ctx["material2_id"], None, "TEST")
    sub2 = add_subcomponent_line(conn, revision_id, line_id, "Jemur", specsheet_ctx["material_id"], None, "TEST")

    row1 = conn.execute("SELECT * FROM bom_line WHERE id=?", (sub1,)).fetchone()
    row2 = conn.execute("SELECT * FROM bom_line WHERE id=?", (sub2,)).fetchone()
    assert row1["sub_seq"] == 1
    assert row2["sub_seq"] == 2
    assert row1["parent_line_key"] == row2["parent_line_key"]

    # display_no format [nomor komponen]-[urutan subkomponen], mis. 10-1, 10-2
    lines = list_lines_with_cells(conn, revision_id)
    subs = {l["id"]: l["display_no"] for l in lines if l["parent_line_key"]}
    assert subs[sub1] == "10-1"
    assert subs[sub2] == "10-2"


def test_cannot_nest_subcomponent_under_subcomponent(conn, specsheet_ctx):
    revision_id = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    line_id = add_component_line(conn, revision_id, specsheet_ctx["component_id"],
                                  specsheet_ctx["material_id"], None, "TEST")
    sub_id = add_subcomponent_line(conn, revision_id, line_id, "Cuci", specsheet_ctx["material2_id"], None, "TEST")
    with pytest.raises(ValueError):
        add_subcomponent_line(conn, revision_id, sub_id, "Jemur", specsheet_ctx["material_id"], None, "TEST")


def test_duplicate_component_material_combo_rejected(conn, specsheet_ctx):
    revision_id = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    add_component_line(conn, revision_id, specsheet_ctx["component_id"], specsheet_ctx["material_id"], None, "TEST")
    with pytest.raises(ValueError):
        add_component_line(conn, revision_id, specsheet_ctx["component_id"], specsheet_ctx["material_id"], None, "TEST")


def test_only_one_draft_revision_at_a_time(conn, specsheet_ctx):
    create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    with pytest.raises(ValueError):
        create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")


def test_new_revision_requires_a_published_source(conn, specsheet_ctx):
    with pytest.raises(ValueError):
        create_next_revision_same_stage(conn, specsheet_ctx["specsheet_id"], "TEST")
