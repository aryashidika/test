"""Hak akses per role ditegakkan di server (bukan hanya tombol yang
disembunyikan di template) — matriks hak akses di rencana implementasi UI."""

import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.web import create_app  # noqa: E402


@pytest.fixture
def client(tmp_path):
    db_path = tmp_path / "roles.db"
    app = create_app(db_path=db_path)
    app.testing = True
    with app.test_client() as c:
        c.db_path = db_path
        yield c


def login(client, role):
    return client.post("/masuk", data={"role": role, "name": role.title()})


def seeded(client):
    """Specsheet contoh PRM-097 yang di-seed otomatis: satu revisi DRAFT r0."""
    conn = sqlite3.connect(str(client.db_path))
    conn.row_factory = sqlite3.Row
    try:
        model = conn.execute("SELECT id FROM product_model WHERE code='PRM-097'").fetchone()
        rev = conn.execute(
            """SELECT r.id, r.specsheet_id FROM specsheet_revision r
               JOIN specsheet s ON s.id = r.specsheet_id WHERE s.model_id=?""", (model["id"],)
        ).fetchone()
        return model["id"], rev["specsheet_id"], rev["id"]
    finally:
        conn.close()


def test_login_lands_on_role_home(client):
    # Semua role mendarat di Beranda "Tugas Saya" yang isinya sesuai role.
    expected = {
        "VENDOR_SPEC": "Draft Specsheet", "VENDOR_CBD": "CBD Perlu Dibuat",
        "MASTER_ADMIN": "Material Menunggu Persetujuan", "BRAND_VIEWER": "Specsheet Terbit Terbaru",
        "SYSTEM_ADMIN": "Ringkasan Sistem",
    }
    for role, section in expected.items():
        assert login(client, role).headers["Location"].endswith("/")
        page = client.get("/").get_data(as_text=True)
        assert "Tugas Saya" in page and section in page
        others = [s for r, s in expected.items() if r != role]
        assert not any(s in page for s in others)


def test_vendor_spec_cannot_see_prices(client):
    login(client, "VENDOR_SPEC")
    assert client.get("/cbd").status_code == 403
    assert client.get("/laporan/histori-harga").status_code == 403
    page = client.get("/specsheet").get_data(as_text=True)
    assert ">CBD<" not in page and ">Specsheet<" in page
    assert client.get("/laporan/where-used").status_code == 200


def test_mutations_rejected_for_wrong_role(client):
    model_id, specsheet_id, revision_id = seeded(client)

    login(client, "BRAND_VIEWER")
    assert client.post("/model", data={"code": "X-1", "name": "X"}).status_code == 403
    assert client.post(f"/specsheet/{model_id}/revision/{revision_id}/publish",
                       data={"specsheet_id": specsheet_id, "category": "OTHER"}).status_code == 403
    assert client.post(f"/cbd/{model_id}/revision/any/publish", data={}).status_code == 403
    assert client.post("/master/material", data={"name": "X"}).status_code == 403

    # Model dikelola Vendor Spec + Master Admin; Vendor CBD hanya melihat.
    login(client, "VENDOR_CBD")
    assert client.post("/model", data={"code": "X-2", "name": "X"}).status_code == 403
    assert "+ Tambah Model" not in client.get("/model").get_data(as_text=True)
    assert client.post(f"/specsheet/{model_id}/revision/{revision_id}/bom/line",
                       data={"specsheet_id": specsheet_id}).status_code == 403

    # Master Admin boleh membuat model, tapi specsheet tetap hak Vendor Spec.
    login(client, "MASTER_ADMIN")
    assert "+ Tambah Model" in client.get("/model").get_data(as_text=True)
    assert client.post(f"/specsheet/{model_id}/revision/{revision_id}/delete",
                       data={"specsheet_id": specsheet_id}).status_code == 403
    assert client.post(f"/cbd/{model_id}/revision/any/field/selling_price", data={}).status_code == 403


def test_brand_sees_published_revisions_only(client):
    model_id, specsheet_id, revision_id = seeded(client)

    login(client, "VENDOR_SPEC")
    assert "DRAFT" in client.get(f"/specsheet/{model_id}").get_data(as_text=True)
    assert client.get(f"/specsheet/{model_id}/revision/{revision_id}/print").status_code == 200

    login(client, "BRAND_VIEWER")
    detail = client.get(f"/specsheet/{model_id}").get_data(as_text=True)
    assert "DRAFT" not in detail and "Belum ada revisi." in detail
    assert client.get(f"/specsheet/{model_id}/revision/{revision_id}/print").status_code == 403
    assert client.get(f"/specsheet/{model_id}/revision/{revision_id}/export.xlsx").status_code == 403
    assert "DRAFT" not in client.get("/specsheet").get_data(as_text=True)


def test_system_admin_is_technical_only(client):
    login(client, "MASTER_ADMIN")
    assert client.get("/admin").status_code == 403
    assert "Reset Data Prototipe" not in client.get("/master/material").get_data(as_text=True)

    login(client, "SYSTEM_ADMIN")
    assert client.get("/master/material").status_code == 403
    assert client.get("/model").status_code == 403
    assert client.get("/cbd").status_code == 403
    assert client.get("/admin").status_code == 200
    wrong = client.post("/admin/reset-data", data={"confirm": "ya"}).get_data(as_text=True)
    assert "untuk mengonfirmasi" in wrong
    done = client.post("/admin/reset-data", data={"confirm": "RESET"}).get_data(as_text=True)
    assert "sudah direset" in done
