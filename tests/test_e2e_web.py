"""E2E (M5, PRD Bagian 10): alur utama lewat HTTP request nyata ke seluruh
blueprint Flask + database SQLite asli (bukan cuma app/domain/ langsung seperti
test lain) — buat master -> specsheet 2 article -> terbit -> generate CBD kedua
article -> revisi specsheet -> CBD terdampak ditandai -> revisi CBD -> ekspor.

Dipakai sebagai pengganti Playwright (lihat README "Penyesuaian dari PRD asli"):
app ini server-rendered (Flask + htmx) tanpa SPA, jadi alur bisa diverifikasi
penuh lewat request HTTP ke route asli tanpa browser sungguhan.
"""

import sqlite3
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.web import create_app  # noqa: E402


@pytest.fixture
def client(tmp_path):
    db_path = tmp_path / "e2e.db"
    app = create_app(db_path=db_path)
    app.testing = True
    with app.test_client() as c:
        c.db_path = db_path
        yield c


def login(client, role, name):
    resp = client.post("/masuk", data={"role": role, "name": name})
    assert resp.status_code in (200, 302)


def row(client, query, params=()):
    conn = sqlite3.connect(str(client.db_path))
    conn.row_factory = sqlite3.Row
    try:
        return conn.execute(query, params).fetchone()
    finally:
        conn.close()


def rows(client, query, params=()):
    conn = sqlite3.connect(str(client.db_path))
    conn.row_factory = sqlite3.Row
    try:
        return conn.execute(query, params).fetchall()
    finally:
        conn.close()


def test_full_flow_master_to_export(client):
    # ---- 1. Buat master (material x2, supplier, komponen x2) ----
    login(client, "MASTER_ADMIN", "Admin")

    assert client.post("/master/material", data={
        "material_code": "MTR-E2E-1", "name": "Kain E2E", "category": "Textile",
        "thickness": "1mm", "uom": "M",
    }).status_code == 200
    assert client.post("/master/material", data={
        "material_code": "MTR-E2E-2", "name": "Kulit E2E", "category": "Leather",
        "thickness": "2mm", "uom": "SF",
    }).status_code == 200
    assert client.post("/master/supplier", data={
        "name": "Supplier E2E", "default_currency": "IDR",
    }).status_code == 200

    material1 = row(client, "SELECT id FROM material WHERE material_code='MTR-E2E-1'")["id"]
    material2 = row(client, "SELECT id FROM material WHERE material_code='MTR-E2E-2'")["id"]
    supplier_id = row(client, "SELECT id FROM supplier WHERE name='Supplier E2E'")["id"]
    group_a = row(client, "SELECT id FROM component_group WHERE code='a'")["id"]

    assert client.post("/master/komponen", data={
        "number": "10", "name": "Vamp E2E", "group_id": group_a,
    }).status_code == 200
    assert client.post("/master/komponen", data={
        "number": "20", "name": "Lining E2E", "group_id": group_a,
    }).status_code == 200
    # Nomor 10/20 sudah dipakai komponen seed Illuzion, jadi dua POST di atas
    # ditolak (nomor tidak boleh dipakai ulang) — pakai komponen yang ada.
    comp1_row = row(client, "SELECT id, number, name FROM component WHERE number=10")
    comp2_row = row(client, "SELECT id, number, name FROM component WHERE number=20")
    component1, component2 = comp1_row["id"], comp2_row["id"]

    # ---- 2. Buat specsheet dengan 2 article (hak Vendor Spec) ----
    login(client, "VENDOR_SPEC", "Spec Ops")
    assert client.post("/model", data={
        "code": "MDL-E2E", "name": "Model E2E", "factory": "Factory E2E",
    }).status_code == 200
    model_id = row(client, "SELECT id FROM product_model WHERE code='MDL-E2E'")["id"]

    assert client.post(f"/model/{model_id}/season", data={"season": "FH26"}).status_code == 200
    specsheet_id = row(
        client, "SELECT id FROM specsheet WHERE model_id=? AND season='FH26'", (model_id,)
    )["id"]

    assert client.post(
        f"/model/{model_id}/revision/empty", data={"specsheet_id": specsheet_id, "stage": "PULL"}
    ).status_code == 200
    revision_id = row(
        client, "SELECT id FROM specsheet_revision WHERE specsheet_id=?", (specsheet_id,)
    )["id"]

    assert client.post(
        f"/model/{model_id}/revision/{revision_id}/article",
        data={"specsheet_id": specsheet_id, "code": "ART-A", "colorway": "Red"},
    ).status_code == 200
    assert client.post(
        f"/model/{model_id}/revision/{revision_id}/article",
        data={"specsheet_id": specsheet_id, "code": "ART-B", "colorway": "Blue"},
    ).status_code == 200
    articles = rows(client, "SELECT * FROM article WHERE specsheet_id=? ORDER BY code", (specsheet_id,))
    article_a, article_b = articles[0]["id"], articles[1]["id"]

    # Komponen/material/supplier diketik (dengan saran), bukan dipilih dari dropdown.
    assert client.post(f"/model/{model_id}/revision/{revision_id}/bom/line", data={
        "specsheet_id": specsheet_id, "component_text": f"{comp1_row['number']} - {comp1_row['name']}",
        "material_text": "MTR-E2E-1 · Kain E2E", "process": "Cutting", "supplier_text": "Supplier E2E",
    }).status_code == 200
    assert client.post(f"/model/{model_id}/revision/{revision_id}/bom/line", data={
        "specsheet_id": specsheet_id, "component_text": comp2_row["name"], "material_text": "MTR-E2E-2",
        "process": "Stitching", "supplier_text": "supplier e2e",
    }).status_code == 200
    # Komponen yang tidak ada di master jadi komponen lokal (No. wajib).
    resp = client.post(f"/model/{model_id}/revision/{revision_id}/bom/line", data={
        "specsheet_id": specsheet_id, "component_text": "Heel Tab E2E", "material_text": "MTR-E2E-1",
        "process": "", "supplier_text": "",
    })
    assert "isi No." in resp.get_data(as_text=True)
    # Supplier yang belum ada di Master Supplier ditolak.
    resp = client.post(f"/model/{model_id}/revision/{revision_id}/bom/line", data={
        "specsheet_id": specsheet_id, "component_text": "Heel Tab E2E", "local_no": "15",
        "material_text": "MTR-E2E-1", "supplier_text": "Supplier Belum Terdaftar",
    })
    assert "tidak ada di Master Supplier" in resp.get_data(as_text=True)

    lines = rows(client, "SELECT * FROM bom_line WHERE revision_id=? ORDER BY sort_order", (revision_id,))
    assert len(lines) == 2
    line1, line2 = lines[0]["id"], lines[1]["id"]
    assert (lines[0]["component_id"], lines[1]["component_id"]) == (component1, component2)
    assert (lines[0]["material_id"], lines[1]["material_id"]) == (material1, material2)
    assert lines[0]["supplier_id"] == lines[1]["supplier_id"] == supplier_id
    links = rows(client, "SELECT * FROM material_supplier WHERE supplier_id=?", (supplier_id,))
    assert {l["status"] for l in links} == {"PROPOSED"}  # kombinasi baru dari BOM -> usulan

    for line_id in (line1, line2):
        for art_id, color in ((article_a, "Red"), (article_b, "Blue")):
            assert client.post(
                f"/model/{model_id}/revision/{revision_id}/bom/{line_id}/cell/{art_id}",
                data={"specsheet_id": specsheet_id, "value": color},
            ).status_code == 200

    # ---- 3. Terbitkan specsheet ----
    assert client.post(
        f"/model/{model_id}/revision/{revision_id}/publish",
        data={"specsheet_id": specsheet_id, "category": "OTHER", "reason": ""},
    ).status_code == 200
    published = row(client, "SELECT status FROM specsheet_revision WHERE id=?", (revision_id,))
    assert published["status"] == "PUBLISHED"

    # Tim spec melihat supplier di Master Material, tapi tidak melihat/mengisi harga.
    login(client, "VENDOR_SPEC", "Spec Ops")
    detail = client.get(f"/master/material/{material1}").get_data(as_text=True)
    assert "Supplier E2E" in detail and "Simpan Harga" not in detail
    link1 = row(client, "SELECT id FROM material_supplier WHERE material_id=?", (material1,))["id"]
    link2 = row(client, "SELECT id FROM material_supplier WHERE material_id=?", (material2,))["id"]
    assert client.post(f"/master/material/{material1}/price", data={
        "link_id": link1, "price": "10000", "currency": "IDR",
    }).status_code == 403

    # ---- 3b. Master Admin approve link; tim CBD isi harga di Master Material ----
    login(client, "MASTER_ADMIN", "Admin")
    assert client.post(f"/master/material/{material1}/supplier/{link1}/status",
                       data={"status": "APPROVED"}).status_code == 200
    assert row(client, "SELECT status FROM material_supplier WHERE id=?", (link1,))["status"] == "APPROVED"

    login(client, "VENDOR_CBD", "CBD Ops")
    for material_id, link_id in ((material1, link1), (material2, link2)):
        assert client.post(f"/master/material/{material_id}/price", data={
            "link_id": link_id, "color": "", "price": "10000", "currency": "IDR", "valid_from": "",
            "reference": "Q-E2E",
        }).status_code == 200
    # Harga khusus warna Blue untuk material 1 (dipakai article B).
    assert client.post(f"/master/material/{material1}/price", data={
        "link_id": link1, "color": "Blue", "price": "12000", "currency": "IDR", "valid_from": "",
    }).status_code == 200

    # ---- 4. Generate CBD untuk kedua article (harga terisi dari master) ----
    assert client.post(f"/cbd/{model_id}/revision/no-source", data={
        "specsheet_id": specsheet_id, "article_id": article_a, "exchange_rate": "15000",
    }).status_code == 200
    assert client.post(f"/cbd/{model_id}/revision/no-source", data={
        "specsheet_id": specsheet_id, "article_id": article_b, "exchange_rate": "15000",
    }).status_code == 200
    cbd_a = row(client, "SELECT id FROM cbd_revision WHERE article_id=?", (article_a,))["id"]
    cbd_b = row(client, "SELECT id FROM cbd_revision WHERE article_id=?", (article_b,))["id"]

    prices_b = rows(client, "SELECT material_id, price_original, price_source FROM cbd_line WHERE cbd_revision_id=?",
                    (cbd_b,))
    assert {(p["material_id"], p["price_original"], p["price_source"]) for p in prices_b} == {
        (material1, "12000", "MASTER"), (material2, "10000", "MASTER"),
    }

    for cbd_rev, art_id in ((cbd_a, article_a), (cbd_b, article_b)):
        for cbd_line in rows(client, "SELECT id FROM cbd_line WHERE cbd_revision_id=?", (cbd_rev,)):
            lid = cbd_line["id"]
            assert client.post(
                f"/cbd/{model_id}/revision/{cbd_rev}/line/{lid}/yield",
                data={"specsheet_id": specsheet_id, "article_id": art_id, "value": "2"},
            ).status_code == 200

    # Override harga sekali pakai di grid CBD: alasan wajib.
    lid_a = rows(client, "SELECT id FROM cbd_line WHERE cbd_revision_id=? AND material_id=?", (cbd_a, material2))[0]["id"]
    resp = client.post(f"/cbd/{model_id}/revision/{cbd_a}/line/{lid_a}/price-override", data={
        "specsheet_id": specsheet_id, "article_id": article_a, "price_original": "9000", "currency": "IDR",
        "reason": "",
    })
    assert "Alasan override" in resp.get_data(as_text=True)
    assert client.post(f"/cbd/{model_id}/revision/{cbd_a}/line/{lid_a}/price-override", data={
        "specsheet_id": specsheet_id, "article_id": article_a, "price_original": "9000", "currency": "IDR",
        "reason": "Nego order pertama",
    }).status_code == 200
    assert row(client, "SELECT price_source FROM cbd_line WHERE id=?", (lid_a,))["price_source"] == "OVERRIDE"

    assert client.post(f"/cbd/{model_id}/revision/{cbd_a}/publish", data={
        "specsheet_id": specsheet_id, "article_id": article_a, "category": "OTHER", "reason": "",
    }).status_code == 200
    assert client.post(f"/cbd/{model_id}/revision/{cbd_b}/publish", data={
        "specsheet_id": specsheet_id, "article_id": article_b, "category": "OTHER", "reason": "",
    }).status_code == 200

    # ---- 5. Revisi specsheet: hanya lepas pemakaian baris untuk article A ----
    login(client, "VENDOR_SPEC", "Spec Ops")
    assert client.post(
        f"/model/{model_id}/revision/same-stage", data={"specsheet_id": specsheet_id}
    ).status_code == 200
    rev2 = row(
        client, "SELECT id FROM specsheet_revision WHERE specsheet_id=? AND revision_no=1",
        (specsheet_id,),
    )["id"]
    line1_r2 = row(
        client,
        "SELECT id FROM bom_line WHERE revision_id=? AND line_key=(SELECT line_key FROM bom_line WHERE id=?)",
        (rev2, line1),
    )["id"]
    assert client.post(
        f"/model/{model_id}/revision/{rev2}/bom/{line1_r2}/cell/{article_a}",
        data={"specsheet_id": specsheet_id, "value": "none"},
    ).status_code == 200
    assert client.post(
        f"/model/{model_id}/revision/{rev2}/publish",
        data={"specsheet_id": specsheet_id, "category": "COMPONENT", "reason": "Drop baris untuk article A"},
    ).status_code == 200

    # ---- 6. CBD terdampak (article A) ditandai, article B tidak ----
    sync_a = row(client, "SELECT sync_status FROM cbd_revision WHERE id=?", (cbd_a,))["sync_status"]
    sync_b = row(client, "SELECT sync_status FROM cbd_revision WHERE id=?", (cbd_b,))["sync_status"]
    assert sync_a == "NEEDS_REVISION"
    assert sync_b == "IN_SYNC"

    # ---- 7. Revisi CBD (article B, yang masih in-sync) ----
    login(client, "VENDOR_CBD", "CBD Ops")
    assert client.post(
        f"/cbd/{model_id}/revision/same-stage",
        data={"specsheet_id": specsheet_id, "article_id": article_b},
    ).status_code == 200
    cbd_b2 = row(
        client, "SELECT id FROM cbd_revision WHERE article_id=? AND revision_no=1", (article_b,)
    )["id"]
    assert client.post(f"/cbd/{model_id}/revision/{cbd_b2}/publish", data={
        "specsheet_id": specsheet_id, "article_id": article_b,
        "category": "OTHER", "reason": "Revisi lanjutan",
    }).status_code == 200

    # ---- 8. Ekspor (Excel + halaman cetak) untuk specsheet dan CBD ----
    print_specsheet = client.get(f"/model/{model_id}/revision/{revision_id}/print")
    assert print_specsheet.status_code == 200
    assert b"MDL-E2E" in print_specsheet.data

    export_specsheet = client.get(f"/model/{model_id}/revision/{revision_id}/export.xlsx")
    assert export_specsheet.status_code == 200
    assert export_specsheet.headers["Content-Type"] == (
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    assert len(export_specsheet.data) > 0

    print_cbd = client.get(f"/cbd/{model_id}/revision/{cbd_b2}/print")
    assert print_cbd.status_code == 200
    assert b"MDL-E2E" in print_cbd.data

    export_cbd = client.get(f"/cbd/{model_id}/revision/{cbd_b2}/export.xlsx")
    assert export_cbd.status_code == 200
    assert export_cbd.headers["Content-Type"] == (
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    assert len(export_cbd.data) > 0
