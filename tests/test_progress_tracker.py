"""Tracker progres Appsmith (progress/update_progress.py): membaca export JSON
Appsmith + dump skema Postgres, lalu menulis PROGRESS.md."""

import importlib.util
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("update_progress", ROOT / "progress" / "update_progress.py")
tracker = importlib.util.module_from_spec(_spec)
sys.modules["update_progress"] = tracker  # dataclass butuh modulnya terdaftar
_spec.loader.exec_module(tracker)

PLAN = """
[proyek]
nama = "Uji"
mulai = 2026-09-28

[aturan]
js_wajib_per_page = ["Auth"]

[[fase]]
kode = "MVP"
nama = "MVP"
target = 9

[[group]]
modul = "M1 Master Data"
judul = "Supplier"
fase = "MVP"
minggu = 3
page = "Master_Supplier"
pages = ["Master_Supplier"]
queries = ["q_suppliers", "a_supplier_create"]
js = ["SupplierCtrl"]
widgets = ["SupplierTable"]
views = ["v_supplier_list"]
functions = ["fn_supplier_create"]

[[group]]
modul = "M3 Specsheet"
judul = "BOM"
fase = "MVP"
minggu = 7
page = "Specsheet_Detail"
pages = ["Specsheet_Detail"]
queries = ["a_bom_update_cell"]
libs = ["xlsx"]
"""


def _export():
    """Bentuk mengikuti export JSON Appsmith: pageId berisi nama page, fungsi JS Object ikut di actionList."""
    def page(name, widgets):
        return {"unpublishedPage": {"name": name, "layouts": [{"dsl": {
            "widgetName": "MainContainer", "type": "CANVAS_WIDGET",
            "children": [{"widgetName": w, "type": "TABLE_WIDGET_V2", "children": []} for w in widgets],
        }}]}}

    def query(page_name, name, body):
        return {"pluginType": "DB", "unpublishedAction": {
            "name": name, "pageId": page_name, "actionConfiguration": {"body": body}}}

    return {
        "exportedApplication": {"name": "Specsheet CBD"},
        "pageList": [page("Master_Supplier", ["SupplierTable"]), page("Beranda", [])],
        "actionList": [
            query("Master_Supplier", "q_suppliers", "SELECT * FROM v_supplier_list"),
            query("Master_Supplier", "a_supplier_create", "SELECT fn_supplier_create({{this.params.name}})"),
            query("Master_Supplier", "a_bom_update_cell", "UPDATE bom_cell SET value = 1"),
            query("Beranda", "Query1", "SELECT fn_tidak_ada()"),
            {"pluginType": "JS", "unpublishedAction": {"name": "save", "pageId": "Master_Supplier",
                                                       "collectionId": "SupplierCtrl"}},
        ],
        "actionCollectionList": [
            {"unpublishedCollection": {"name": "SupplierCtrl", "pageId": "Master_Supplier"}},
            {"unpublishedCollection": {"name": "Auth", "pageId": "Master_Supplier"}},
        ],
        "customJSLibList": [{"name": "xlsx", "accessor": ["XLSX"]}],
    }


SCHEMA = """
CREATE TABLE public.supplier (id text);
CREATE VIEW public.v_supplier_list AS SELECT * FROM supplier;
CREATE OR REPLACE FUNCTION public.fn_supplier_create(p_name text) RETURNS text AS $$ $$;
CREATE FUNCTION public.fn_helper() RETURNS void AS $$ $$;
"""


@pytest.fixture
def run(tmp_path):
    (tmp_path / "plan.toml").write_text(PLAN, encoding="utf-8")
    (tmp_path / "status.toml").write_text('diuji = ["q_suppliers", "fn_tidak_dikenal"]\n', encoding="utf-8")
    (tmp_path / "export.json").write_text(json.dumps(_export()), encoding="utf-8")
    # pg_dump yang diarahkan dengan `>` di Windows PowerShell 5.1 menghasilkan UTF-16.
    (tmp_path / "schema.sql").write_bytes(SCHEMA.encode("utf-16"))

    def _run():
        tracker.main([
            "--plan", str(tmp_path / "plan.toml"), "--status", str(tmp_path / "status.toml"),
            "--appsmith", str(tmp_path / "export.json"), "--db", str(tmp_path / "schema.sql"),
            "--history", str(tmp_path / "history.json"), "--out", str(tmp_path / "PROGRESS.md"),
            "--today", "2026-11-20",
        ])
        return (tmp_path / "PROGRESS.md").read_text(encoding="utf-8")

    return _run


def _row(md, name):
    return next(line for line in md.splitlines() if f"| `{name}` |" in line)


def test_items_found_in_export_and_schema_are_marked(run):
    md = run()
    assert "✅ Diuji" in _row(md, "q_suppliers")
    for name in ("a_supplier_create", "SupplierCtrl", "SupplierTable", "Master_Supplier",
                 "v_supplier_list", "fn_supplier_create", "xlsx"):
        assert "🟡 Dibuat" in _row(md, name), name
    assert "⬜ Belum" in _row(md, "Specsheet_Detail")


def test_js_object_functions_are_not_counted_as_queries(run):
    md = run()
    assert "`Master_Supplier/save`" not in md


def test_query_on_wrong_page_is_not_counted(run):
    md = run()
    row = _row(md, "a_bom_update_cell")
    assert "⬜ Belum" in row and "ada di page Master_Supplier" in row


def test_warnings(run):
    md = run()
    warnings = md.split("## Peringatan")[1].split("## Detail checklist")[0]
    assert "`Master_Supplier/a_bom_update_cell` menulis langsung ke tabel (`UPDATE BOM_CELL`)" in warnings
    assert "`Beranda/Query1` memakai `fn_tidak_ada` yang belum ada di dump skema" in warnings
    assert "Page `Beranda` belum punya JS Object wajib: Auth" in warnings
    assert "Page `Master_Supplier` belum punya" not in warnings
    assert "`fn_tidak_dikenal` di status.toml tidak ada di plan.toml" in warnings


def test_unplanned_items_listed(run):
    extra = run().split("## Di luar rencana")[1].split("## Riwayat")[0]
    for name in ("Beranda", "Beranda/Query1", "fn_helper"):
        assert f"`{name}`" in extra
    assert "Master_Supplier/Auth" not in extra


def test_overdue_module_and_history_not_duplicated(run):
    run()
    md = run()
    # 20 Nov 2026 = W8. Specsheet (target W7) belum dibuat → terlambat; Master Data (W3) sudah
    # dibuat semua, tinggal uji → tidak terlambat.
    modul = {l.split(" | ")[0][2:]: l for l in md.splitlines() if l.startswith("| M")}
    assert "⏰ Terlambat" in modul["M3 Specsheet"]
    assert "🧪 Tinggal uji" in modul["M1 Master Data"] and "Terlambat" not in modul["M1 Master Data"]
    history = md.split("## Riwayat")[1].split("## Cara update")[0]
    assert history.count("| 2026-11-20 |") == 1
