from app.domain.article_service import add_article
from app.domain.bom_service import add_component_line, replace_material, update_cell_value, update_process
from app.domain.diff_service import compute_bom_diff
from app.domain.revision_service import create_empty_revision, create_next_revision_same_stage, publish_revision


def test_diff_detects_added_removed_and_changed(conn, specsheet_ctx):
    r0 = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    article_id = add_article(conn, r0, specsheet_ctx["specsheet_id"], "ART-1", "Black", "TEST")
    line_kept_id = add_component_line(conn, r0, specsheet_ctx["component_id"], specsheet_ctx["material_id"], None, "TEST")
    line_to_replace_id = add_component_line(conn, r0, specsheet_ctx["component2_id"], specsheet_ctx["material_id"], None, "TEST")
    update_cell_value(conn, line_kept_id, article_id, "Black", "TEST")
    update_cell_value(conn, line_to_replace_id, article_id, "Black", "TEST")
    publish_revision(conn, r0, "COMPONENT", "", "TEST")

    kept_line_key = conn.execute("SELECT line_key FROM bom_line WHERE id=?", (line_kept_id,)).fetchone()[0]

    r1 = create_next_revision_same_stage(conn, specsheet_ctx["specsheet_id"], "TEST")
    r1_kept_line_id = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND line_key=?", (r1, kept_line_key)
    ).fetchone()[0]
    update_process(conn, r1_kept_line_id, "Proses baru", "TEST")

    r1_replace_target_id = conn.execute(
        "SELECT bl.id FROM bom_line bl WHERE bl.revision_id=? AND bl.component_id=?",
        (r1, specsheet_ctx["component2_id"]),
    ).fetchone()[0]
    new_line_id = replace_material(conn, r1, r1_replace_target_id, specsheet_ctx["material2_id"], "TEST")

    # add a brand new line only present in r1
    added_line_id = add_component_line(conn, r1, specsheet_ctx["component_id"], specsheet_ctx["material2_id"],
                                        None, "TEST")

    diff = compute_bom_diff(conn, r0, r1)

    added_keys = {a["lineKey"] for a in diff["added"]}
    new_line_key = conn.execute("SELECT line_key FROM bom_line WHERE id=?", (new_line_id,)).fetchone()[0]
    added_added_key = conn.execute("SELECT line_key FROM bom_line WHERE id=?", (added_line_id,)).fetchone()[0]
    assert new_line_key in added_keys
    assert added_added_key in added_keys

    removed_keys = {r["lineKey"] for r in diff["removed"]}
    old_replaced_key = conn.execute("SELECT line_key FROM bom_line WHERE id=?", (r1_replace_target_id,)).fetchone()[0]
    assert old_replaced_key in removed_keys

    assert kept_line_key in diff["changed"]
    assert "Process" in diff["changed"][kept_line_key]["fields"]
    assert diff["changed"][kept_line_key]["fields"]["Process"]["after"] == "Proses baru"
