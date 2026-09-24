"""Urutan baris BOM/CBD menurut nomor komponen, kolom Thickness & Remarks CBD
(live dari master/specsheet), saran Material Code, dan aturan "Copy dari
Article Lain" (baris selalu dari specsheet tujuan, subkomponen dicocokkan
lewat nama, baris sumber yang tak terpakai tidak ikut)."""

from app.domain.article_service import add_article
from app.domain.bom_service import (
    add_component_line,
    add_subcomponent_line,
    list_lines_with_cells,
    update_cell_value,
)
from app.domain.cbd_service import (
    create_cbd_from_article,
    create_cbd_no_source,
    list_cbd_lines,
    publish_cbd_revision,
    update_yield,
)
from app.domain.material_service import MaterialInput, create_material, suggest_next_material_code
from app.domain.revision_service import create_empty_revision, publish_revision
from app.domain.specsheet_service import create_specsheet


def test_bom_lines_sorted_by_component_number_with_subcomponents_under_parent(conn, specsheet_ctx):
    rev = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    line_20 = add_component_line(conn, rev, specsheet_ctx["component2_id"], specsheet_ctx["material_id"], "", "TEST")
    add_component_line(conn, rev, specsheet_ctx["component_id"], specsheet_ctx["material_id"], "", "TEST")
    add_subcomponent_line(conn, rev, line_20, "Print", specsheet_ctx["material2_id"], "", "TEST")

    assert [l["display_no"] for l in list_lines_with_cells(conn, rev)] == ["10", "20", "20-1"]


def test_cbd_lines_follow_component_order_and_show_thickness_and_remarks(conn, specsheet_ctx):
    rev = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    line_20 = add_component_line(conn, rev, specsheet_ctx["component2_id"], specsheet_ctx["material_id"],
                                 "Skiving", "TEST")
    line_10 = add_component_line(conn, rev, specsheet_ctx["component_id"], specsheet_ctx["material2_id"],
                                 "Cutting", "TEST")
    art = add_article(conn, rev, specsheet_ctx["specsheet_id"], "ART-1", "Red", "TEST")
    update_cell_value(conn, line_20, art, "Red", "TEST")
    update_cell_value(conn, line_10, art, "Red", "TEST")
    publish_revision(conn, rev, "OTHER", "", "TEST")

    cbd_id = create_cbd_no_source(conn, art, "16300", "CBD")
    lines = list_cbd_lines(conn, cbd_id)
    assert [l["component_number"] for l in lines] == [10, 20]
    assert [l["remarks"] for l in lines] == ["Cutting", "Skiving"]

    # Thickness dibaca live dari Master Material
    conn.execute("UPDATE material SET thickness='1.2mm' WHERE id=?", (specsheet_ctx["material2_id"],))
    assert list_cbd_lines(conn, cbd_id)[0]["material_thickness"] == "1.2mm"


def test_suggest_next_material_code(conn):
    assert suggest_next_material_code(conn) == "MTR-0001"
    create_material(conn, MaterialInput("MTR-0041", "Kain", "Textile", None, "M", "APPROVED"), "T")
    create_material(conn, MaterialInput("KODE-LAIN", "Kain 2", "Textile", None, "M", "APPROVED"), "T")
    assert suggest_next_material_code(conn) == "MTR-0042"


def _published_cbd_with_sub(conn, ctx, specsheet_id, subs, colorway, yields):
    """Specsheet (season sendiri) berisi komponen 10 + subkomponen `subs` (nama),
    satu article yang memakai semuanya; CBD-nya dibuat dengan `yields` per nama
    lalu diterbitkan kalau `yields` diisi."""
    rev = create_empty_revision(conn, specsheet_id, "TEST")
    parent = add_component_line(conn, rev, ctx["component_id"], ctx["material_id"], "", "TEST")
    art = add_article(conn, rev, specsheet_id, f"ART-{colorway}", colorway, "TEST")
    update_cell_value(conn, parent, art, colorway, "TEST")
    for name in subs:
        sub = add_subcomponent_line(conn, rev, parent, name, ctx["material2_id"], "", "TEST")
        update_cell_value(conn, sub, art, colorway, "TEST")
    publish_revision(conn, rev, "OTHER", "", "TEST")
    if yields is None:
        return art, None
    cbd_id = create_cbd_no_source(conn, art, "16300", "CBD")
    for line in list_cbd_lines(conn, cbd_id):
        value = yields.get(line["sub_name"] or "")
        if value:
            update_yield(conn, line["id"], value, "CBD")
    publish_cbd_revision(conn, cbd_id, "OTHER", "", "CBD")
    return art, cbd_id


def test_copy_from_other_season_matches_subcomponent_by_name_and_skips_unused_source_lines(conn, specsheet_ctx):
    # Sumber (FH26): 10, 10-1 "Print", 10-2 "Logo Lama"
    source_art, _ = _published_cbd_with_sub(
        conn, specsheet_ctx, specsheet_ctx["specsheet_id"], ["Print", "Logo Lama"], "Red",
        {"": "2", "Print": "5", "Logo Lama": "9"},
    )
    # Tujuan (SS27, model sama): 10, 10-1 "Emboss", 10-2 "Print" — urutan beda
    ss27 = create_specsheet(conn, specsheet_ctx["model_id"], "SS27", "TEST")
    target_art, _ = _published_cbd_with_sub(conn, specsheet_ctx, ss27, ["Emboss", "Print"], "Blue", None)

    copied_id = create_cbd_from_article(conn, target_art, source_art, "16300", "CBD")
    lines = {(l["sub_name"] or ""): l for l in list_cbd_lines(conn, copied_id)}

    assert set(lines) == {"", "Emboss", "Print"}  # "Logo Lama" tidak ikut sebagai MISSING_IN_SPEC
    assert all(l["status"] == "ACTIVE" for l in lines.values())
    assert lines[""]["yield_value"] == "2"
    assert lines["Print"]["yield_value"] == "5"  # dicocokkan lewat nama, bukan nomor 10-1
    assert lines["Print"]["color"] == "Blue"  # warna dari specsheet tujuan
    assert lines["Emboss"]["yield_value"] is None  # baris baru, diisi manual


def test_copy_carries_recap_biaya_and_margin(conn, cbd_ctx):
    from app.domain.cbd_service import (
        create_cbd_same_stage, update_adjustment, update_amortization, update_selling_price, update_target_fob,
    )
    from app.domain.revision_service import create_next_revision_same_stage

    first = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")
    update_amortization(conn, first, "1500", "CBD")
    update_adjustment(conn, first, "250", "CBD")
    update_target_fob(conn, first, "90000", "CBD")
    update_selling_price(conn, first, "150000", "CBD")
    publish_cbd_revision(conn, first, "OTHER", "", "CBD")

    def header(rev_id):
        r = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (rev_id,)).fetchone()
        return (r["exchange_rate"], r["amortization"], r["adjustment"], r["target_fob"], r["selling_price"])

    expected = ("16300", "1500", "250", "90000", "150000")
    assert header(create_cbd_same_stage(conn, cbd_ctx["article_id"], "CBD")) == expected

    new_rev = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    other = add_article(conn, new_rev, cbd_ctx["specsheet_id"], "ART-2", "Blue", "TEST")
    line = conn.execute("SELECT id FROM bom_line WHERE revision_id=?", (new_rev,)).fetchone()
    update_cell_value(conn, line["id"], other, "Blue", "TEST")
    publish_revision(conn, new_rev, "COMPONENT", "tambah article", "TEST")
    # exchange rate kosong di form copy -> ikut rate sumber
    assert header(create_cbd_from_article(conn, other, cbd_ctx["article_id"], "", "CBD")) == expected


def test_delete_cbd_draft_as_if_never_created(conn, cbd_ctx):
    import pytest
    from app.domain.cbd_service import delete_cbd_draft, list_cbd_revisions

    draft = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")
    delete_cbd_draft(conn, draft, "CBD")
    assert list_cbd_revisions(conn, cbd_ctx["article_id"]) == []
    assert conn.execute("SELECT COUNT(*) FROM cbd_line WHERE cbd_revision_id=?", (draft,)).fetchone()[0] == 0

    again = create_cbd_no_source(conn, cbd_ctx["article_id"], "16300", "CBD")  # bisa dibuat ulang
    update_yield(conn, list_cbd_lines(conn, again)[0]["id"], "2", "CBD")
    publish_cbd_revision(conn, again, "OTHER", "", "CBD")
    with pytest.raises(ValueError):
        delete_cbd_draft(conn, again, "CBD")


def test_delete_specsheet_draft_removes_lines_and_draft_only_articles(conn, cbd_ctx):
    import pytest
    from app.domain.revision_service import (
        create_next_revision_same_stage, delete_draft_revision, get_draft_revision,
    )

    draft = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    new_art = add_article(conn, draft, cbd_ctx["specsheet_id"], "ART-NEW", "Green", "TEST")
    delete_draft_revision(conn, draft, "TEST")

    assert get_draft_revision(conn, cbd_ctx["specsheet_id"]) is None
    assert conn.execute("SELECT COUNT(*) FROM bom_line WHERE revision_id=?", (draft,)).fetchone()[0] == 0
    assert conn.execute("SELECT 1 FROM article WHERE id=?", (new_art,)).fetchone() is None  # hanya ada di draft
    assert conn.execute("SELECT 1 FROM article WHERE id=?", (cbd_ctx["article_id"],)).fetchone()  # tetap ada
    assert list_lines_with_cells(conn, cbd_ctx["revision_id"])  # revisi terbit utuh

    with pytest.raises(ValueError):
        delete_draft_revision(conn, cbd_ctx["revision_id"], "TEST")
