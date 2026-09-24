"""Beranda "Tugas Saya": daftar pekerjaan per role (Tahap 3 rencana implementasi UI)."""

from app.domain.article_service import create_article, include_article
from app.domain.bom_service import add_component_line
from app.domain.cbd_service import create_cbd_no_source, publish_cbd_revision
from app.domain.material_price_service import add_price, find_material_supplier, today_iso
from app.domain.revision_service import create_next_revision_same_stage, publish_revision
from app.domain.worklist_service import (
    approval_queue,
    cbd_worklist,
    recently_published,
    spec_worklist,
)


def _codes(items):
    return [i["article_code"] for i in items]


def test_cbd_worklist_follows_article_lifecycle(conn, cbd_ctx):
    work = cbd_worklist(conn)
    assert _codes(work["to_create"]) == ["ART-1"]
    gap = work["price_gaps"]
    assert [(g["material_code"], g["supplier_name"], g["colors"]) for g in gap] == [("MTR-A", "Supplier Test", ["Red"])]

    create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    work = cbd_worklist(conn)
    assert work["to_create"] == [] and _codes(work["in_progress"]) == ["ART-1"]

    # Harga master baru tersedia -> draft harus di-refresh; gap harga hilang.
    link = find_material_supplier(conn, cbd_ctx["material_id"], cbd_ctx["supplier_id"])
    add_price(conn, link["id"], None, "15000", "IDR", today_iso(), None, "TEST")
    work = cbd_worklist(conn)
    assert [(i["article_code"], i["reason"]) for i in work["to_refresh"]] == [("ART-1", "Harga master berubah")]
    assert work["price_gaps"] == []

    # Specsheet direvisi selagi CBD masih draft -> draft usang.
    rev2 = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    publish_revision(conn, rev2, "OTHER", "revisi test", "TEST")
    reasons = [i["reason"] for i in cbd_worklist(conn)["to_refresh"]]
    assert reasons == ["Specsheet acuan sudah direvisi"]


def test_cbd_worklist_needs_revision(conn, cbd_ctx):
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "TEST")
    publish_cbd_revision(conn, revision_id, "OTHER", "", "TEST")
    assert cbd_worklist(conn)["to_revise"] == []
    conn.execute("UPDATE cbd_revision SET sync_status='NEEDS_REVISION' WHERE id=?", (revision_id,))
    assert _codes(cbd_worklist(conn)["to_revise"]) == ["ART-1"]


def test_spec_worklist_flags_draft_blockers_and_unassigned_articles(conn, cbd_ctx):
    sid = cbd_ctx["specsheet_id"]
    create_article(conn, sid, "ART-2", "Blue", "TEST")
    work = spec_worklist(conn)
    assert work["drafts"] == []
    assert [(u["codes"], u["has_revision"]) for u in work["unassigned_articles"]] == [(["ART-2"], True)]

    draft = create_next_revision_same_stage(conn, sid, "TEST")
    add_component_line(conn, draft, cbd_ctx["component2_id"], cbd_ctx["material2_id"], "", "TEST")
    art3 = create_article(conn, sid, "ART-3", "Green", "TEST")
    include_article(conn, draft, art3, "TEST")
    d = spec_worklist(conn)["drafts"][0]
    assert (d["stage"], d["revision_no"], d["line_count"]) == ("PULL", 1, 2)
    assert d["no_supplier"] == 1 and d["unused_articles"] == ["ART-3"]


def test_approval_queue_and_recently_published(conn, cbd_ctx):
    queue = approval_queue(conn)
    assert queue["materials"] == [] and queue["components"] == []
    assert [l["material_code"] for l in queue["links"]] == ["MTR-A"]  # dibuat otomatis dari BOM

    feed = recently_published(conn)
    assert [(r["stage"], r["revision_no"]) for r in feed["specsheets"]] == [("PULL", 0)]
    assert feed["cbds"] == []
