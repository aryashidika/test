"""Edit master data (material, komponen, supplier) & harga oleh Master Admin."""

import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.domain.component_service import ComponentNumberError, create_component, update_component  # noqa: E402
from app.domain.material_service import (  # noqa: E402
    DuplicateMaterialCodeError,
    DuplicateMaterialError,
    MaterialInput,
    create_material,
    update_material,
)
from app.domain.supplier_service import (  # noqa: E402
    DuplicateSupplierError,
    SupplierInput,
    create_supplier,
    rename_supplier,
)
from app.web import create_app  # noqa: E402


def _group(conn, code):
    return conn.execute("SELECT id FROM component_group WHERE code=?", (code,)).fetchone()["id"]


# ---------------- domain ----------------

def test_update_material_changes_identity_and_logs_audit(conn, specsheet_ctx):
    mid = specsheet_ctx["material_id"]
    update_material(conn, mid, MaterialInput("MTR-A2", " Kain A Baru ", "Mesh", "1,2mm", "YD"), "ADMIN")
    m = conn.execute("SELECT * FROM material WHERE id=?", (mid,)).fetchone()
    assert (m["material_code"], m["name"], m["category"], m["thickness"], m["uom"]) == \
        ("MTR-A2", "Kain A Baru", "Mesh", "1,2mm", "YD")
    assert m["name_normalized"] == "kain a baru" and m["thickness_normalized"] == "1.2mm"
    assert m["updated_by"] == "ADMIN"
    log = conn.execute(
        "SELECT * FROM audit_log WHERE entity='Material' AND entity_id=? AND action='UPDATE'", (mid,)
    ).fetchone()
    assert log is not None and '"MTR-A"' in log["before_json"]


def test_update_material_rejects_duplicates_but_allows_keeping_own_values(conn, specsheet_ctx):
    mid, other = specsheet_ctx["material_id"], specsheet_ctx["material2_id"]
    # Simpan tanpa perubahan tidak dianggap duplikat dirinya sendiri.
    update_material(conn, mid, MaterialInput("MTR-A", "Kain A", "Textile", None, "M"), "ADMIN")
    with pytest.raises(DuplicateMaterialCodeError):
        update_material(conn, mid, MaterialInput("MTR-B", "Kain A", "Textile", None, "M"), "ADMIN")
    with pytest.raises(DuplicateMaterialError):
        update_material(conn, mid, MaterialInput("MTR-A", "KAIN  B", "Textile", None, "M"), "ADMIN")
    with pytest.raises(ValueError):
        update_material(conn, mid, MaterialInput("MTR-A", "", "Textile", None, "M"), "ADMIN")
    assert conn.execute("SELECT name FROM material WHERE id=?", (other,)).fetchone()["name"] == "Kain B"


def test_update_component_follows_number_rules(conn, specsheet_ctx):
    cid = specsheet_ctx["component_id"]  # 10 "Vamp" di kelompok a
    group_a, group_c = _group(conn, "a"), _group(conn, "c")
    update_component(conn, cid, 30, "Vamp Baru", group_a, "ADMIN")
    c = conn.execute("SELECT * FROM component WHERE id=?", (cid,)).fetchone()
    assert (c["number"], c["name"]) == (30, "Vamp Baru")

    with pytest.raises(ComponentNumberError):
        update_component(conn, cid, 20, "Vamp", group_a, "ADMIN")  # dipakai "Lining"
    with pytest.raises(ComponentNumberError):
        update_component(conn, cid, 35, "Vamp", group_a, "ADMIN")  # bukan kelipatan 10
    with pytest.raises(ComponentNumberError):
        update_component(conn, cid, 30, "Vamp", group_c, "ADMIN")  # di luar rentang kelompok c
    with pytest.raises(ValueError):
        update_component(conn, cid, 30, "  ", group_a, "ADMIN")


def test_rename_supplier_rejects_names_that_only_differ_in_case(conn, specsheet_ctx):
    sid = specsheet_ctx["supplier_id"]
    create_supplier(conn, SupplierInput("Hwasung"), "ADMIN")
    rename_supplier(conn, sid, "Supplier Baru", "ADMIN")
    assert conn.execute("SELECT name FROM supplier WHERE id=?", (sid,)).fetchone()["name"] == "Supplier Baru"
    with pytest.raises(DuplicateSupplierError):
        rename_supplier(conn, sid, "  HWASUNG ", "ADMIN")
    # Ganti kapitalisasi nama sendiri boleh.
    rename_supplier(conn, sid, "SUPPLIER BARU", "ADMIN")


# ---------------- web: hak akses ----------------

@pytest.fixture
def client(tmp_path):
    app = create_app(db_path=tmp_path / "web.db")
    app.testing = True
    with app.test_client() as c:
        c.db_path = tmp_path / "web.db"
        yield c


def _login(client, role):
    client.post("/masuk", data={"role": role, "name": role.title()})


def _q(client, query, params=()):
    conn = sqlite3.connect(str(client.db_path))
    conn.row_factory = sqlite3.Row
    try:
        return conn.execute(query, params).fetchone()
    finally:
        conn.close()


def _setup_material_with_supplier(client):
    _login(client, "MASTER_ADMIN")
    client.post("/master/material", data={"material_code": "MTR-W1", "name": "Kain W", "category": "Textile",
                                          "uom": "M"})
    client.post("/master/supplier", data={"name": "Supplier W", "default_currency": "USD"})
    material_id = _q(client, "SELECT id FROM material WHERE material_code='MTR-W1'")["id"]
    client.post(f"/master/material/{material_id}/supplier", data={"supplier_text": "Supplier W"})
    link_id = _q(client, "SELECT id FROM material_supplier WHERE material_id=?", (material_id,))["id"]
    return material_id, link_id


def test_master_admin_can_edit_master_data_and_prices(client):
    material_id, link_id = _setup_material_with_supplier(client)

    assert client.post(f"/master/material/{material_id}/edit", data={
        "material_code": "MTR-W1", "name": "Kain W Edit", "category": "Textile", "thickness": "", "uom": "YD",
    }).status_code == 200
    assert _q(client, "SELECT name, uom FROM material WHERE id=?", (material_id,))["name"] == "Kain W Edit"

    assert client.post(f"/master/material/{material_id}/price", data={
        "link_id": link_id, "color": "", "price": "2.5", "currency": "USD", "valid_from": "2026-01-01",
    }).status_code == 200
    price = _q(client, "SELECT * FROM material_price WHERE material_supplier_id=?", (link_id,))
    assert (price["price"], price["currency"]) == ("2.5", "USD")

    # Tombol Ubah mengisi form dengan supplier, harga, dan currency harga itu.
    page = client.get(f"/master/material/{material_id}?ubah={price['id']}").get_data(as_text=True)
    assert "Ubah Harga" in page and 'value="2.5"' in page

    supplier_id = _q(client, "SELECT id FROM supplier WHERE name='Supplier W'")["id"]
    assert client.post(f"/master/supplier/{supplier_id}/edit", data={"name": "Supplier W2"}).status_code == 200
    assert _q(client, "SELECT name FROM supplier WHERE id=?", (supplier_id,))["name"] == "Supplier W2"

    component = _q(client, "SELECT * FROM component ORDER BY number LIMIT 1")
    assert client.post(f"/master/komponen/{component['id']}/edit", data={
        "number": component["number"], "name": "Nama Baru", "group_id": component["group_id"],
    }).status_code == 200
    assert _q(client, "SELECT name FROM component WHERE id=?", (component["id"],))["name"] == "Nama Baru"


@pytest.mark.parametrize("role", ["VENDOR_SPEC", "VENDOR_CBD", "BRAND_VIEWER"])
def test_other_roles_cannot_edit_master_data(client, role):
    material_id, _ = _setup_material_with_supplier(client)
    supplier_id = _q(client, "SELECT id FROM supplier WHERE name='Supplier W'")["id"]
    component = _q(client, "SELECT * FROM component ORDER BY number LIMIT 1")
    _login(client, role)
    assert client.post(f"/master/material/{material_id}/edit", data={
        "material_code": "X", "name": "X", "category": "X", "uom": "X",
    }).status_code == 403
    assert client.post(f"/master/material/{material_id}/status", data={"status": "INACTIVE"}).status_code == 403
    assert client.post(f"/master/supplier/{supplier_id}/edit", data={"name": "X"}).status_code == 403
    assert client.post(f"/master/supplier/{supplier_id}/status", data={"status": "INACTIVE"}).status_code == 403
    assert client.post(f"/master/komponen/{component['id']}/edit", data={
        "number": component["number"], "name": "X", "group_id": component["group_id"],
    }).status_code == 403
    assert _q(client, "SELECT name FROM material WHERE id=?", (material_id,))["name"] == "Kain W"
