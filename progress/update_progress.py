"""Perbarui PROGRESS.md dari export JSON Appsmith + dump skema Postgres.

Cara pakai:
    1. Appsmith: menu aplikasi > Export > simpan file .json ke progress/exports/
    2. pg_dump --schema-only -f progress/db/schema_YYYYMMDD.sql <nama_db>
    3. python progress/update_progress.py

File terbaru di tiap folder yang dipakai. Rencana item ada di progress/plan.toml,
tanda "sudah diuji" dan catatan di progress/status.toml. PROGRESS.md selalu
ditulis ulang — jangan diedit manual.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent

BELUM, DIBUAT, DIUJI = "belum", "dibuat", "diuji"
STATUS_LABEL = {BELUM: "⬜ Belum", DIBUAT: "🟡 Dibuat", DIUJI: "✅ Diuji"}
KIND_LABEL = {
    "page": "Page", "query": "Query", "js": "JS Object", "widget": "Widget", "lib": "Library",
    "function": "Function DB", "view": "View DB", "table": "Tabel DB",
}
PAGE_SCOPED = ("query", "js", "widget")
DB_KINDS = ("function", "view", "table")

_DDL = re.compile(
    r"\bCREATE\s+(?:OR\s+REPLACE\s+)?(FUNCTION|PROCEDURE|MATERIALIZED\s+VIEW|VIEW|TABLE)\s+"
    r"(?:IF\s+NOT\s+EXISTS\s+)?(?:\"?\w+\"?\.)?\"?(\w+)\"?",
    re.IGNORECASE,
)
_DIRECT_WRITE = re.compile(r"\b(INSERT\s+INTO|UPDATE\s+[\w.\"]+\s+SET|DELETE\s+FROM)\b", re.IGNORECASE)
_SQL_COMMENT = re.compile(r"--[^\n]*|/\*.*?\*/", re.DOTALL)
_DB_REF = re.compile(r"\b((?:fn|v)_\w+)")


@dataclass
class Item:
    kind: str
    name: str
    page: str | None
    group: dict
    status: str = BELUM
    note: str = ""

    @property
    def key(self) -> str:
        return f"{self.page}/{self.name}" if self.kind in PAGE_SCOPED else self.name


@dataclass
class AppsmithApp:
    source: Path
    name: str = ""
    pages: dict[str, dict[str, str]] = field(default_factory=dict)  # page -> {widgetName: type}
    queries: dict[tuple[str, str], str] = field(default_factory=dict)  # (page, name) -> body
    js: set[tuple[str, str]] = field(default_factory=set)
    libs: set[str] = field(default_factory=set)


def read_text(path: Path) -> str:
    """Baca teks apa pun encoding-nya — `>` di Windows PowerShell 5.1 menulis UTF-16."""
    raw = path.read_bytes()
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        return raw.decode("utf-16")
    return raw.decode("utf-8-sig", errors="replace")


def latest(folder: Path, pattern: str) -> Path | None:
    files = [p for p in folder.glob(pattern) if p.is_file()]
    return max(files, key=lambda p: p.stat().st_mtime) if files else None


# ─────────────────────────── sumber data ───────────────────────────

def _walk_widgets(node, out: dict[str, str]) -> None:
    if not isinstance(node, dict):
        return
    if node.get("widgetName") and node.get("type") != "CANVAS_WIDGET":
        out[node["widgetName"]] = node.get("type", "")
    for child in node.get("children") or []:
        _walk_widgets(child, out)


def load_appsmith(path: Path) -> AppsmithApp:
    data = json.loads(read_text(path))
    app = AppsmithApp(source=path, name=(data.get("exportedApplication") or {}).get("name", ""))

    page_names: dict[str, str] = {}
    for p in data.get("pageList") or []:
        page = p.get("unpublishedPage") or p.get("publishedPage") or p
        name = page.get("name")
        if not name:
            continue
        for ident in (p.get("id"), p.get("gitSyncId"), page.get("id"), name):
            if ident:
                page_names[ident] = name
        widgets: dict[str, str] = {}
        for layout in page.get("layouts") or []:
            _walk_widgets(layout.get("dsl"), widgets)
        app.pages[name] = widgets

    def page_of(page_id):
        return page_names.get(page_id, page_id or "?")

    for a in data.get("actionList") or []:
        action = a.get("unpublishedAction") or a.get("publishedAction") or {}
        # Fungsi di dalam JS Object juga muncul di actionList — itu bagian dari JS Object, bukan query.
        if action.get("collectionId") or "JS" in (a.get("pluginType"), action.get("pluginType")):
            continue
        if action.get("name"):
            body = (action.get("actionConfiguration") or {}).get("body") or ""
            app.queries[(page_of(action.get("pageId")), action["name"])] = body

    for c in data.get("actionCollectionList") or []:
        collection = c.get("unpublishedCollection") or c.get("publishedCollection") or {}
        if collection.get("name"):
            app.js.add((page_of(collection.get("pageId")), collection["name"]))

    for lib in data.get("customJSLibList") or []:
        app.libs.add(str(lib.get("name", "")).lower())
        app.libs.update(str(acc).lower() for acc in lib.get("accessor") or [])
    return app


def load_schema(path: Path) -> dict[str, set[str]]:
    found: dict[str, set[str]] = {k: set() for k in DB_KINDS}
    for kind, name in _DDL.findall(read_text(path)):
        kind = kind.upper()
        bucket = "function" if kind in ("FUNCTION", "PROCEDURE") else "view" if "VIEW" in kind else "table"
        found[bucket].add(name.lower())
    return found


def load_plan(path: Path) -> tuple[dict, list[Item]]:
    plan = tomllib.loads(read_text(path))
    items: list[Item] = []
    for g in plan.get("group", []):
        page = g.get("page")
        if not page and any(g.get(k) for k in ("queries", "js", "widgets")):
            raise ValueError(f"Group '{g.get('judul')}' berisi queries/js/widgets tapi tidak punya `page`.")
        items += [Item("page", n, None, g) for n in g.get("pages", [])]
        for kind, key in (("query", "queries"), ("js", "js"), ("widget", "widgets")):
            items += [Item(kind, n, page, g) for n in g.get(key, [])]
        for kind, key in (("lib", "libs"), ("function", "functions"), ("view", "views"), ("table", "tables")):
            items += [Item(kind, n, None, g) for n in g.get(key, [])]
    return plan, items


# ─────────────────────────── evaluasi ───────────────────────────

def _find(item: Item, app: AppsmithApp | None, schema: dict[str, set[str]] | None) -> tuple[bool, str]:
    if item.kind in DB_KINDS:
        return bool(schema) and item.name.lower() in schema[item.kind], ""
    if app is None:
        return False, ""
    if item.kind == "page":
        return item.name in app.pages, ""
    if item.kind == "widget":
        return item.name in app.pages.get(item.page, {}), ""
    if item.kind == "lib":
        return any(item.name.lower() in lib for lib in app.libs), ""
    pool = app.queries.keys() if item.kind == "query" else app.js
    if (item.page, item.name) in pool:
        return True, ""
    elsewhere = sorted(p for p, n in pool if n == item.name)
    return False, (f"ada di page {', '.join(elsewhere)}, bukan {item.page}" if elsewhere else "")


def evaluate(items: list[Item], app, schema, tested: set[str], notes: dict[str, str]) -> None:
    for item in items:
        found, note = _find(item, app, schema)
        item.status = BELUM
        if found:
            item.status = DIUJI if (item.key in tested or item.name in tested) else DIBUAT
        manual = notes.get(item.key) or notes.get(item.name) or ""
        item.note = "; ".join(x for x in (note, manual) if x)


def collect_warnings(plan: dict, items: list[Item], app, schema, tested: set[str]) -> list[str]:
    warnings: list[str] = []
    rules = plan.get("aturan", {})
    if app:
        exempt = set(rules.get("page_tanpa_aturan", []))
        for page in sorted(app.pages):
            missing = [j for j in rules.get("js_wajib_per_page", []) if (page, j) not in app.js]
            if missing and page not in exempt:
                warnings.append(f"Page `{page}` belum punya JS Object wajib: {', '.join(missing)}")
        for (page, name), body in sorted(app.queries.items()):
            sql = _SQL_COMMENT.sub("", body)
            write = _DIRECT_WRITE.search(sql)
            if write:
                verb = " ".join(write.group(1).split()[:2]).upper()
                warnings.append(f"Query `{page}/{name}` menulis langsung ke tabel (`{verb}`) — seharusnya lewat function `fn_*`")
            if schema:
                for ref in sorted(set(_DB_REF.findall(sql))):
                    kind = "function" if ref.startswith("fn_") else "view"
                    if ref.lower() not in schema[kind]:
                        warnings.append(f"Query `{page}/{name}` memakai `{ref}` yang belum ada di dump skema")
    for item in items:
        if "ada di page" in item.note:
            warnings.append(f"{KIND_LABEL[item.kind]} `{item.name}` {item.note}")
    known = {i.key for i in items} | {i.name for i in items}
    for name in sorted(tested):
        if name not in known:
            warnings.append(f"`{name}` di status.toml tidak ada di plan.toml (salah ketik?)")
    for item in items:
        if item.status == BELUM and (item.key in tested or item.name in tested):
            warnings.append(f"`{item.key}` ditandai diuji di status.toml tapi belum ditemukan di export/skema")
    return warnings


def unplanned(items: list[Item], plan: dict, app, schema) -> list[tuple[str, str]]:
    extra: list[tuple[str, str]] = []
    if app:
        planned_pages = {i.name for i in items if i.kind == "page"}
        extra += [("Page", p) for p in sorted(app.pages) if p not in planned_pages]
        planned_q = {(i.page, i.name) for i in items if i.kind == "query"}
        extra += [("Query", f"{p}/{n}") for p, n in sorted(app.queries) if (p, n) not in planned_q]
        planned_js = {(i.page, i.name) for i in items if i.kind == "js"}
        required = set(plan.get("aturan", {}).get("js_wajib_per_page", []))
        extra += [("JS Object", f"{p}/{n}") for p, n in sorted(app.js)
                  if (p, n) not in planned_js and n not in required]
    if schema:
        for kind in ("function", "view"):
            planned = {i.name.lower() for i in items if i.kind == kind}
            extra += [(KIND_LABEL[kind], n) for n in sorted(schema[kind]) if n not in planned]
    return extra


# ─────────────────────────── ringkasan & render ───────────────────────────

def counts(items: list[Item]) -> tuple[int, int, int]:
    made = sum(i.status in (DIBUAT, DIUJI) for i in items)
    tested = sum(i.status == DIUJI for i in items)
    return len(items), made, tested


def bar(done: int, total: int, width: int = 10) -> str:
    frac = done / total if total else 0
    filled = round(frac * width)
    return f"{'█' * filled}{'░' * (width - filled)} {frac:.0%}"


def module_status(items: list[Item], target: int, week: int) -> str:
    total, made, tested = counts(items)
    if tested == total:
        label = "✅ Selesai"
    elif made == total:
        label = "🧪 Tinggal uji"
    elif made:
        label = "🟡 Berjalan"
    else:
        label = "⬜ Belum mulai"
    if week > target and made < total:
        label += " · ⏰ Terlambat"
    return label


def current_week(start: dt.date, today: dt.date) -> int:
    return max(0, (today - start).days // 7 + 1)


def _ordered(values):
    return list(dict.fromkeys(values))


def render(plan, items, app, db_path, warnings, extra, history, today, week) -> str:
    fases = plan.get("fase", [])
    fase_name = {f["kode"]: f["nama"] for f in fases}
    out: list[str] = []
    w = out.append

    w(f"# Progres Pembangunan — {plan['proyek']['nama']}\n")
    w("> File ini dibuat otomatis oleh `progress/update_progress.py`. Jangan diedit manual —")
    w("> ubah `progress/plan.toml` (rencana) atau `progress/status.toml` (status uji & catatan).\n")
    w("| | |")
    w("|---|---|")
    app_src = f"`{app.source.name}`" + (f" ({app.name})" if app.name else "") if app else "_belum ada — taruh export JSON di `progress/exports/`_"
    db_src = f"`{db_path.name}`" if db_path else "_belum ada — taruh dump skema di `progress/db/`_"
    w(f"| Export Appsmith | {app_src} |")
    w(f"| Dump skema DB | {db_src} |")
    w(f"| Diperbarui | {today:%d %b %Y} · minggu berjalan **W{week}** (mulai {plan['proyek']['mulai']:%d %b %Y}) |\n")

    w("## Ringkasan\n")
    w("| Fase | Target | Item | Dibuat | Diuji |")
    w("|---|---|---|---|---|")
    for f in fases:
        fi = [i for i in items if i.group["fase"] == f["kode"]]
        total, made, tested = counts(fi)
        w(f"| {f['nama']} | W{f['target']} | {total} | {bar(made, total)} | {bar(tested, total)} |")
    total, made, tested = counts(items)
    w(f"| **Total** | | **{total}** | {bar(made, total)} | {bar(tested, total)} |\n")

    w("## Per modul\n")
    w("| Modul | Fase | Target | Dibuat | Diuji | Status |")
    w("|---|---|---|---|---|---|")
    for f in fases:
        fi = [i for i in items if i.group["fase"] == f["kode"]]
        for modul in _ordered(i.group["modul"] for i in fi):
            mi = [i for i in fi if i.group["modul"] == modul]
            target = max(i.group["minggu"] for i in mi)
            total, made, tested = counts(mi)
            w(f"| {modul} | {f['kode']} | W{target} | {made}/{total} | {tested}/{total} | {module_status(mi, target, week)} |")
    w("")

    w("## Peringatan\n")
    w("\n".join(f"- {x}" for x in warnings) if warnings else "_Tidak ada._")
    w("")

    w("## Detail checklist\n")
    for f in fases:
        w(f"### {fase_name[f['kode']]}\n")
        fi = [i for i in items if i.group["fase"] == f["kode"]]
        for modul in _ordered(i.group["modul"] for i in fi):
            mi = [i for i in fi if i.group["modul"] == modul]
            total, made, tested = counts(mi)
            started = made > 0 or week >= min(i.group["minggu"] for i in mi)
            is_open = " open" if made < total and started else ""
            w(f"<details{is_open}><summary><b>{modul}</b> — {made}/{total} dibuat · {tested}/{total} diuji</summary>\n")
            for group in _ordered(id(i.group) for i in mi):
                gi = [i for i in mi if id(i.group) == group]
                g = gi[0].group
                gt, gm, _ = counts(gi)
                w(f"**{g['judul']}** · target W{g['minggu']} · {gm}/{gt}\n")
                w("| Jenis | Nama | Page | Status | Catatan |")
                w("|---|---|---|---|---|")
                for i in gi:
                    w(f"| {KIND_LABEL[i.kind]} | `{i.name}` | {i.page if i.kind in PAGE_SCOPED else ''} | {STATUS_LABEL[i.status]} | {i.note} |")
                w("")
            w("</details>\n")

    w("## Di luar rencana\n")
    w("Ada di Appsmith/DB tapi tidak ada di `plan.toml`. Bisa jadi salah nama, atau item baru yang perlu ditambahkan ke rencana.\n")
    if extra:
        w("| Jenis | Nama |")
        w("|---|---|")
        w("\n".join(f"| {k} | `{n}` |" for k, n in extra))
    else:
        w("_Tidak ada._")
    w("")

    w("## Riwayat\n")
    if history:
        w("| Tanggal | Export Appsmith | Dump skema | MVP dibuat | MVP diuji | Total dibuat |")
        w("|---|---|---|---|---|---|")
        for h in history:
            w(f"| {h['tanggal']} | {h['appsmith'] or '-'} | {h['db'] or '-'} | {h['mvp_dibuat']} | {h['mvp_diuji']} | {h['total_dibuat']} |")
    else:
        w("_Belum ada._")
    w("")

    w("## Cara update\n")
    w("1. Appsmith: menu aplikasi → **Export** → simpan `.json` ke `progress/exports/`")
    w("2. `pg_dump --schema-only -f progress/db/schema_YYYYMMDD.sql <nama_db>` (pakai `-f`, bukan `>`)")
    w("3. Tandai item yang sudah dites di `progress/status.toml`")
    w("4. `python progress/update_progress.py`")
    return "\n".join(out) + "\n"


def pct(done: int, total: int) -> str:
    return f"{done / total:.0%}" if total else "0%"


def update_history(path: Path, app, schema_src, items, today) -> list[dict]:
    history = json.loads(read_text(path)) if path.exists() else []
    if app or schema_src:
        mvp = [i for i in items if i.group["fase"] == "MVP"]
        total, made, tested = counts(mvp)
        all_total, all_made, _ = counts(items)
        entry = {
            "tanggal": today.isoformat(),
            "appsmith": app.source.name if app else None,
            "db": schema_src.name if schema_src else None,
            "mvp_dibuat": pct(made, total), "mvp_diuji": pct(tested, total),
            "total_dibuat": pct(all_made, all_total),
        }
        history = [h for h in history if (h["appsmith"], h["db"]) != (entry["appsmith"], entry["db"])]
        history.append(entry)
        path.write_text(json.dumps(history, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return history


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--appsmith", type=Path, help="file export JSON (default: terbaru di progress/exports/)")
    ap.add_argument("--db", type=Path, help="dump skema .sql (default: terbaru di progress/db/)")
    ap.add_argument("--plan", type=Path, default=HERE / "plan.toml")
    ap.add_argument("--status", type=Path, default=HERE / "status.toml")
    ap.add_argument("--history", type=Path, default=HERE / "history.json")
    ap.add_argument("--out", type=Path, default=REPO / "PROGRESS.md")
    ap.add_argument("--today", type=dt.date.fromisoformat, default=dt.date.today())
    args = ap.parse_args(argv)

    plan, items = load_plan(args.plan)
    status = tomllib.loads(read_text(args.status)) if args.status.exists() else {}
    tested = set(status.get("diuji", []))
    notes = status.get("catatan", {})

    app_path = args.appsmith or latest(HERE / "exports", "*.json")
    db_path = args.db or latest(HERE / "db", "*.sql")
    app = load_appsmith(app_path) if app_path else None
    schema = load_schema(db_path) if db_path else None

    evaluate(items, app, schema, tested, notes)
    week = current_week(plan["proyek"]["mulai"], args.today)
    warnings = collect_warnings(plan, items, app, schema, tested)
    extra = unplanned(items, plan, app, schema)
    history = update_history(args.history, app, db_path, items, args.today)
    args.out.write_text(render(plan, items, app, db_path, warnings, extra, history, args.today, week), encoding="utf-8")

    total, made, tested_n = counts(items)
    print(f"{args.out.name}: {made}/{total} dibuat, {tested_n}/{total} diuji, "
          f"{len(warnings)} peringatan, {len(extra)} di luar rencana (W{week})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
