"""Halaman Model: data model + article/colorway per season dikelola sebelum dan
terlepas dari revisi specsheet (Tahap 2 rencana implementasi UI)."""

import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.domain.article_service import (  # noqa: E402
    copy_articles_from_specsheet,
    create_article,
    delete_article,
    include_article,
    list_articles_for_revision,
    list_articles_overview,
    update_article,
)
from app.domain.bom_service import add_component_line, update_cell_value  # noqa: E402
from app.domain.cbd_service import create_cbd_no_source  # noqa: E402
from app.domain.model_service import DuplicateModelError, ModelInput, create_model, get_model, update_model  # noqa: E402
from app.domain.revision_service import (  # noqa: E402
    create_carryover_revision,
    create_empty_revision,
    create_next_revision_same_stage,
    publish_revision,
)
from app.domain.specsheet_service import create_specsheet  # noqa: E402
from app.web import create_app  # noqa: E402


def test_article_exists_without_revision_and_code_unique_per_season(conn, specsheet_ctx):
    sid = specsheet_ctx["specsheet_id"]
    create_article(conn, sid, "ART-1", "Red", "TEST")
    with pytest.raises(ValueError, match="sudah ada"):
        create_article(conn, sid, "ART-1", "Blue", "TEST")
    with pytest.raises(ValueError, match="Colorway"):
        create_article(conn, sid, "ART-2", "  ", "TEST")
    # Kode sama boleh di season lain model yang sama.
    other = create_specsheet(conn, specsheet_ctx["model_id"], "SS27", "TEST")
    create_article(conn, other, "ART-1", "Red", "TEST")


def test_first_revision_includes_all_season_articles(conn, specsheet_ctx):
    sid = specsheet_ctx["specsheet_id"]
    a1 = create_article(conn, sid, "ART-1", "Red", "TEST")
    a2 = create_article(conn, sid, "ART-2", "Blue", "TEST")
    revision_id = create_empty_revision(conn, sid, "TEST")
    linked = {a["id"]: a["revision_status"] for a in list_articles_for_revision(conn, revision_id)}
    assert linked == {a1: "ACTIVE", a2: "ACTIVE"}

    # Baris BOM baru langsung punya sel untuk setiap article.
    line_id = add_component_line(conn, revision_id, specsheet_ctx["component_id"],
                                 specsheet_ctx["material_id"], "", "TEST")
    cells = conn.execute("SELECT article_id FROM bom_cell WHERE bom_line_id=?", (line_id,)).fetchall()
    assert {c["article_id"] for c in cells} == {a1, a2}


def test_carryover_includes_target_season_articles_not_source(conn, cbd_ctx):
    target = create_specsheet(conn, cbd_ctx["model_id"], "SS27", "TEST")
    new_art = create_article(conn, target, "ART-SS27", "Green", "TEST")
    revision_id = create_carryover_revision(conn, target, cbd_ctx["revision_id"], "TEST")
    assert [a["id"] for a in list_articles_for_revision(conn, revision_id)] == [new_art]
    cells = conn.execute(
        """SELECT bc.* FROM bom_cell bc JOIN bom_line bl ON bl.id = bc.bom_line_id
           WHERE bl.revision_id=?""", (revision_id,)
    ).fetchall()
    assert cells and all(c["article_id"] == new_art and not c["is_used"] for c in cells)


def test_include_article_into_later_draft(conn, cbd_ctx):
    sid = cbd_ctx["specsheet_id"]
    late = create_article(conn, sid, "ART-LATE", "Black", "TEST")
    draft = create_next_revision_same_stage(conn, sid, "TEST")
    # Revisi lanjutan menyalin article revisi sebelumnya saja; article baru dipilih manual.
    assert late not in {a["id"] for a in list_articles_for_revision(conn, draft)}
    include_article(conn, draft, late, "TEST")
    assert late in {a["id"] for a in list_articles_for_revision(conn, draft)}
    with pytest.raises(ValueError, match="sudah ada"):
        include_article(conn, draft, late, "TEST")
    other = create_specsheet(conn, cbd_ctx["model_id"], "SS27", "TEST")
    foreign = create_article(conn, other, "ART-X", "Grey", "TEST")
    with pytest.raises(ValueError, match="bukan milik"):
        include_article(conn, draft, foreign, "TEST")
    with pytest.raises(ValueError, match="sudah diterbitkan"):
        include_article(conn, cbd_ctx["revision_id"], late, "TEST")


def test_edit_and_delete_rules(conn, cbd_ctx):
    sid = cbd_ctx["specsheet_id"]
    fresh = create_article(conn, sid, "ART-9", "Navy", "TEST")
    update_article(conn, fresh, "ART-10", "Navy Blue", "TEST")
    assert conn.execute("SELECT code, colorway FROM article WHERE id=?", (fresh,)).fetchone()[:] == ("ART-10", "Navy Blue")

    used = cbd_ctx["article_id"]
    update_article(conn, used, "ART-1", "Crimson", "TEST")  # colorway selalu bisa
    with pytest.raises(ValueError, match="tidak bisa diubah"):
        update_article(conn, used, "ART-1B", "Crimson", "TEST")
    with pytest.raises(ValueError, match="tidak bisa dihapus"):
        delete_article(conn, used, "TEST")

    delete_article(conn, fresh, "TEST")
    assert conn.execute("SELECT 1 FROM article WHERE id=?", (fresh,)).fetchone() is None


def test_copy_articles_from_other_season_skips_existing_codes(conn, cbd_ctx):
    target = create_specsheet(conn, cbd_ctx["model_id"], "SS27", "TEST")
    create_article(conn, cbd_ctx["specsheet_id"], "ART-2", "Blue", "TEST")
    create_article(conn, target, "ART-2", "Blue v2", "TEST")
    assert copy_articles_from_specsheet(conn, target, cbd_ctx["specsheet_id"], "TEST") == 1
    rows = conn.execute("SELECT code, colorway FROM article WHERE specsheet_id=? ORDER BY code", (target,)).fetchall()
    assert [tuple(r) for r in rows] == [("ART-1", "Red"), ("ART-2", "Blue v2")]
    with pytest.raises(ValueError):
        copy_articles_from_specsheet(conn, target, target, "TEST")


def test_articles_overview_statuses(conn, specsheet_ctx):
    sid = specsheet_ctx["specsheet_id"]
    art = create_article(conn, sid, "ART-1", "Red", "TEST")
    assert list_articles_overview(conn, sid)[0]["spec_status"] == "NONE"

    revision_id = create_empty_revision(conn, sid, "TEST")
    overview = list_articles_overview(conn, sid)[0]
    assert overview["spec_status"] == "DRAFT" and not overview["deletable"]
    assert list_articles_overview(conn, sid, include_drafts=False)[0]["spec_status"] == "NONE"

    line_id = add_component_line(conn, revision_id, specsheet_ctx["component_id"],
                                 specsheet_ctx["material_id"], "", "TEST",
                                 supplier_id=specsheet_ctx["supplier_id"])
    update_cell_value(conn, line_id, art, "Red", "TEST")
    publish_revision(conn, revision_id, "OTHER", "", "TEST")
    overview = list_articles_overview(conn, sid)[0]
    assert overview["spec_status"] == "ACTIVE" and overview["spec_detail"] == "PULL r0 terbit"
    assert overview["cbd_revision"] is None

    create_cbd_no_source(conn, art, "", "TEST")
    assert list_articles_overview(conn, sid)[0]["cbd_revision"]["status"] == "DRAFT"
    assert list_articles_overview(conn, sid, include_drafts=False)[0]["cbd_revision"] is None


def test_update_model_info(conn, specsheet_ctx):
    model_id = specsheet_ctx["model_id"]
    update_model(conn, model_id, ModelInput(code="MDL-1", name="Model Baru", size_range="37-44"), "TEST")
    model = get_model(conn, model_id)
    assert (model["name"], model["size_range"], model["factory"]) == ("Model Baru", "37-44", None)
    create_model(conn, ModelInput(code="MDL-2", name="Lain"), "TEST")
    with pytest.raises(DuplicateModelError):
        update_model(conn, model_id, ModelInput(code="MDL-2", name="X"), "TEST")


# ---------------- Web ----------------

@pytest.fixture
def client(tmp_path):
    app = create_app(db_path=tmp_path / "model.db")
    app.testing = True
    with app.test_client() as c:
        c.db_path = tmp_path / "model.db"
        yield c


def _login(client, role):
    client.post("/masuk", data={"role": role, "name": role.title()})


def _db(client):
    conn = sqlite3.connect(str(client.db_path))
    conn.row_factory = sqlite3.Row
    return conn


def test_model_page_article_flow_and_permissions(client):
    _login(client, "VENDOR_SPEC")
    client.post("/model", data={"code": "MDL-W", "name": "Model Web"})
    conn = _db(client)
    model_id = conn.execute("SELECT id FROM product_model WHERE code='MDL-W'").fetchone()["id"]
    client.post(f"/model/{model_id}/season", data={"season": "FH26"})
    sid = conn.execute("SELECT id FROM specsheet WHERE model_id=?", (model_id,)).fetchone()["id"]

    page = client.post(f"/model/{model_id}/season/{sid}/article", data={"code": "W-1", "colorway": "White"})
    assert page.status_code == 200 and "W-1" in page.get_data(as_text=True)
    assert "BELUM MASUK SPECSHEET" in page.get_data(as_text=True)
    art = conn.execute("SELECT id FROM article WHERE code='W-1'").fetchone()["id"]

    # Master Admin juga boleh; Vendor CBD & Brand hanya melihat.
    _login(client, "MASTER_ADMIN")
    assert client.post(f"/model/{model_id}/article/{art}",
                       data={"specsheet_id": sid, "code": "W-1", "colorway": "Off White"}).status_code == 200
    assert client.post(f"/model/{model_id}/edit", data={"code": "MDL-W", "name": "Model Web 2"}).status_code == 200
    for role in ("VENDOR_CBD", "BRAND_VIEWER"):
        _login(client, role)
        assert client.get(f"/model/{model_id}").status_code == 200
        assert client.post(f"/model/{model_id}/season/{sid}/article",
                           data={"code": "W-2", "colorway": "Grey"}).status_code == 403
        assert client.post(f"/model/{model_id}/article/{art}/delete", data={"specsheet_id": sid}).status_code == 403
    assert conn.execute("SELECT colorway FROM article WHERE id=?", (art,)).fetchone()["colorway"] == "Off White"
    assert conn.execute("SELECT name FROM product_model WHERE id=?", (model_id,)).fetchone()["name"] == "Model Web 2"

    # Vendor Spec: revisi pertama memuat article; article yang ditambah belakangan dipilih lewat "Pilih Article".
    _login(client, "VENDOR_SPEC")
    client.post(f"/specsheet/{model_id}/revision/empty", data={"specsheet_id": sid, "stage": "PULL"})
    rev = conn.execute("SELECT id FROM specsheet_revision WHERE specsheet_id=?", (sid,)).fetchone()["id"]
    client.post(f"/model/{model_id}/season/{sid}/article", data={"code": "W-2", "colorway": "Grey"})
    art2 = conn.execute("SELECT id FROM article WHERE code='W-2'").fetchone()["id"]
    grid = client.get(f"/specsheet/{model_id}?specsheet_id={sid}&revision_id={rev}").get_data(as_text=True)
    assert "Pilih Article (1)" in grid
    client.post(f"/specsheet/{model_id}/revision/{rev}/article", data={"specsheet_id": sid, "article_id": [art2]})
    linked = conn.execute("SELECT article_id FROM revision_article WHERE revision_id=?", (rev,)).fetchall()
    assert {r["article_id"] for r in linked} == {art, art2}

    # Hapus draft tidak menghapus article.
    client.post(f"/specsheet/{model_id}/revision/{rev}/delete", data={"specsheet_id": sid})
    assert conn.execute("SELECT COUNT(*) c FROM article WHERE specsheet_id=?", (sid,)).fetchone()["c"] == 2
    conn.close()


def test_old_model_revision_url_redirects_to_specsheet(client):
    _login(client, "VENDOR_SPEC")
    resp = client.get("/model/abc?specsheet_id=s1&revision_id=r1")
    assert resp.status_code == 302 and "/specsheet/abc?" in resp.headers["Location"]
