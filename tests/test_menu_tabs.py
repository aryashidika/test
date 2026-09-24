"""Tahap 4: menu & tab — checklist terbit (specsheet & CBD), antrian
persetujuan, tab detail Material (Laporan dilebur), tab di URL, audit log."""

import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.domain.article_service import create_article, include_article  # noqa: E402
from app.domain.bom_service import add_component_line  # noqa: E402
from app.domain.cbd_service import cbd_publish_checklist, create_cbd_no_source, override_price  # noqa: E402
from app.domain.cbd_service import list_cbd_lines  # noqa: E402
from app.domain.material_service import MaterialInput, create_material  # noqa: E402
from app.domain.revision_service import (  # noqa: E402
    create_empty_revision,
    create_next_revision_same_stage,
    publish_checklist,
    publish_revision,
)
from app.web import create_app  # noqa: E402


def _by_label(checks):
    return {c["label"]: c for c in checks}


def test_specsheet_publish_checklist_matches_publish_rules(conn, cbd_ctx):
    draft = create_next_revision_same_stage(conn, cbd_ctx["specsheet_id"], "TEST")
    checks = _by_label(publish_checklist(conn, draft))
    assert all(c["ok"] for c in checks.values())

    late = create_article(conn, cbd_ctx["specsheet_id"], "ART-2", "Blue", "TEST")
    include_article(conn, draft, late, "TEST")
    check = _by_label(publish_checklist(conn, draft))["Setiap article aktif dipakai di BOM"]
    assert not check["ok"] and check["blocking"] and "ART-2" in check["detail"]
    with pytest.raises(ValueError, match="ART-2"):
        publish_revision(conn, draft, "OTHER", "alasan", "TEST")


def test_specsheet_checklist_no_article_and_missing_supplier_warning(conn, specsheet_ctx):
    revision_id = create_empty_revision(conn, specsheet_ctx["specsheet_id"], "TEST")
    add_component_line(conn, revision_id, specsheet_ctx["component_id"], specsheet_ctx["material_id"], "", "TEST")
    checks = _by_label(publish_checklist(conn, revision_id))
    assert not checks["Minimal satu article aktif"]["ok"]
    supplier = checks["Semua baris punya supplier (dibutuhkan harga CBD)"]
    assert not supplier["ok"] and not supplier["blocking"]


def test_cbd_publish_checklist(conn, cbd_ctx):
    revision_id = create_cbd_no_source(conn, cbd_ctx["article_id"], "", "TEST")
    checks = _by_label(cbd_publish_checklist(conn, revision_id))
    assert not checks["Exchange rate terisi (> 0)"]["ok"]
    assert not checks["Semua baris berharga"]["ok"] and not checks["Semua baris berharga"]["blocking"]

    line = list_cbd_lines(conn, revision_id)[0]
    override_price(conn, line["id"], "1000", "IDR", "test", "TEST")
    checks = _by_label(cbd_publish_checklist(conn, revision_id))
    assert not checks["Baris berharga punya yield"]["ok"]
    assert checks["Semua baris berharga"]["ok"]


# ---------------- Web ----------------

@pytest.fixture
def client(tmp_path):
    app = create_app(db_path=tmp_path / "tabs.db")
    app.testing = True
    with app.test_client() as c:
        c.db_path = tmp_path / "tabs.db"
        yield c


def _login(client, role):
    client.post("/masuk", data={"role": role, "name": role.title()})


def _one(client, sql, params=()):
    conn = sqlite3.connect(str(client.db_path))
    try:
        return conn.execute(sql, params).fetchone()
    finally:
        conn.close()


def test_approval_queue_page(client):
    conn = sqlite3.connect(str(client.db_path))
    conn.row_factory = sqlite3.Row
    material_id = create_material(conn, MaterialInput("MTR-USUL", "Usulan", "Textile", None, "M", "PROPOSED"), "VENDOR")
    conn.close()

    _login(client, "VENDOR_SPEC")
    assert client.get("/master/persetujuan").status_code == 403
    assert "Persetujuan" not in client.get("/master/material").get_data(as_text=True)

    _login(client, "MASTER_ADMIN")
    page = client.get("/master/persetujuan").get_data(as_text=True)
    assert "MTR-USUL" in page and 'class="count-badge"' in page
    resp = client.post(f"/master/persetujuan/material/{material_id}", data={"status": "APPROVED"})
    assert resp.status_code == 200 and "Disetujui." in resp.get_data(as_text=True)
    assert _one(client, "SELECT status FROM material WHERE id=?", (material_id,))[0] == "APPROVED"
    assert client.post(f"/master/persetujuan/material/{material_id}", data={"status": "PROPOSED"}).status_code == 400


def test_material_detail_tabs_and_old_report_urls(client):
    material_id = _one(client, "SELECT id FROM material WHERE material_code='MTR-0021'")[0]
    _login(client, "VENDOR_CBD")
    for tab, marker in (("info", "Metode harga"), ("dipakai", "Dipakai di"), ("histori", "Histori Harga CBD")):
        page = client.get(f"/master/material/{material_id}?tab={tab}").get_data(as_text=True)
        assert marker in page
    assert "PRM-097" in client.get(f"/master/material/{material_id}?tab=dipakai").get_data(as_text=True)

    old = client.get(f"/laporan/where-used?material_id={material_id}")
    assert old.status_code == 302 and "tab=dipakai" in old.headers["Location"]
    assert client.get("/laporan/where-used").headers["Location"].endswith("/master/material")
    # Menu Laporan tidak ada lagi di topbar.
    assert ">Laporan<" not in client.get("/").get_data(as_text=True)


def test_specsheet_and_cbd_tabs_in_url(client):
    model_id = _one(client, "SELECT id FROM product_model WHERE code='PRM-097'")[0]
    _login(client, "VENDOR_SPEC")
    page = client.get(f"/specsheet/{model_id}?tab=riwayat").get_data(as_text=True)
    assert 'class="tab-btn active"' in page and "Belum ada riwayat" in page
    assert "Terbitkan PULL" not in page  # seed PRM-097 = PROD r0
    assert "dlg-publish" in page and "Minimal satu article aktif" in page

    _login(client, "MASTER_ADMIN")
    page = client.get(f"/cbd/{model_id}?tab=validasi").get_data(as_text=True)
    assert "Belum terbit" in page  # chip article: specsheet seed belum terbit


def test_admin_audit_log(client):
    _login(client, "SYSTEM_ADMIN")
    page = client.get("/admin").get_data(as_text=True)
    assert "Audit Log" in page and "ProductModel" in page
    filtered = client.get("/admin?entity=Supplier").get_data(as_text=True)
    assert "ProductModel</td>" not in filtered
    assert "Reset Data Prototipe" in client.get("/admin?tab=reset").get_data(as_text=True)
