"""Daftar pekerjaan per role untuk Beranda "Tugas Saya" — menjawab "apa yang
harus saya kerjakan sekarang" tanpa harus membuka model/article satu per satu."""

from .cbd_service import (
    article_cbd_status,
    cbd_draft_is_stale,
    latest_published_specsheet_revision,
    list_cbd_revisions,
    stale_master_price_lines,
)
from .material_price_service import is_quotation_material, lookup_price
from .revision_service import STAGES

_SPECSHEET_INFO_SQL = """
    SELECT sp.id AS specsheet_id, sp.season, pm.id AS model_id, pm.code AS model_code, pm.name AS model_name
    FROM specsheet sp JOIN product_model pm ON pm.id = sp.model_id
"""


def _specsheets(conn):
    return conn.execute(_SPECSHEET_INFO_SQL + " ORDER BY pm.code, sp.season").fetchall()


def _unused_active_articles(conn, revision_id):
    """Article aktif di revisi yang belum dipakai di baris BOM mana pun (penghambat terbit)."""
    return conn.execute(
        """SELECT a.code FROM revision_article ra JOIN article a ON a.id = ra.article_id
           WHERE ra.revision_id=? AND ra.status='ACTIVE' AND NOT EXISTS (
               SELECT 1 FROM bom_cell bc JOIN bom_line bl ON bl.id = bc.bom_line_id
               WHERE bl.revision_id=? AND bl.is_active=1 AND bc.article_id=a.id AND bc.is_used=1)
           ORDER BY a.code""",
        (revision_id, revision_id),
    ).fetchall()


# ---------------- Vendor Spec ----------------

def spec_worklist(conn):
    drafts = []
    unassigned = []
    for sp in _specsheets(conn):
        draft = conn.execute(
            "SELECT * FROM specsheet_revision WHERE specsheet_id=? AND status='DRAFT'", (sp["specsheet_id"],)
        ).fetchone()
        if draft:
            line_count = conn.execute(
                "SELECT COUNT(*) c FROM bom_line WHERE revision_id=? AND is_active=1", (draft["id"],)
            ).fetchone()["c"]
            no_supplier = conn.execute(
                "SELECT COUNT(*) c FROM bom_line WHERE revision_id=? AND is_active=1 AND supplier_id IS NULL",
                (draft["id"],),
            ).fetchone()["c"]
            active_articles = conn.execute(
                "SELECT COUNT(*) c FROM revision_article WHERE revision_id=? AND status='ACTIVE'", (draft["id"],)
            ).fetchone()["c"]
            drafts.append({
                **dict(sp), "revision_id": draft["id"], "stage": draft["stage"],
                "revision_no": draft["revision_no"], "created_at": draft["created_at"],
                "line_count": line_count, "no_supplier": no_supplier, "active_articles": active_articles,
                "unused_articles": [r["code"] for r in _unused_active_articles(conn, draft["id"])],
            })
        rows = conn.execute(
            """SELECT code FROM article WHERE specsheet_id=? AND id NOT IN
               (SELECT article_id FROM revision_article) ORDER BY code""",
            (sp["specsheet_id"],),
        ).fetchall()
        if rows:
            has_revision = conn.execute(
                "SELECT 1 FROM specsheet_revision WHERE specsheet_id=? LIMIT 1", (sp["specsheet_id"],)
            ).fetchone() is not None
            unassigned.append({**dict(sp), "codes": [r["code"] for r in rows], "has_revision": has_revision})
    return {"drafts": drafts, "unassigned_articles": unassigned, **proposal_counts(conn)}


def proposal_counts(conn):
    count = lambda sql: conn.execute(sql).fetchone()["c"]  # noqa: E731
    return {
        "proposed_materials": count("SELECT COUNT(*) c FROM material WHERE status='PROPOSED'"),
        "proposed_components": count("SELECT COUNT(*) c FROM component WHERE status='PROPOSED'"),
        "proposed_links": count("SELECT COUNT(*) c FROM material_supplier WHERE status='PROPOSED'"),
    }


# ---------------- Vendor CBD ----------------

def cbd_worklist(conn):
    """Per article yang aktif di specsheet terbit terakhir: belum ada CBD, draft
    yang harus di-refresh (specsheet/harga), CBD terbit yang NEEDS_REVISION,
    atau draft yang sedang berjalan. Plus kombinasi material+supplier(+warna)
    di BOM terbit yang belum punya harga master."""
    result = {"to_create": [], "to_refresh": [], "to_revise": [], "in_progress": []}
    for sp in _specsheets(conn):
        articles = conn.execute(
            "SELECT * FROM article WHERE specsheet_id=? ORDER BY code", (sp["specsheet_id"],)
        ).fetchall()
        for article in articles:
            if article_cbd_status(conn, article["id"]) != "ACTIVE":
                continue
            item = {**dict(sp), "article_id": article["id"], "article_code": article["code"],
                    "colorway": article["colorway"]}
            revisions = list_cbd_revisions(conn, article["id"])
            draft = next((r for r in revisions if r["status"] == "DRAFT"), None)
            if not revisions:
                result["to_create"].append(item)
            elif draft:
                item.update(cbd_revision_id=draft["id"], stage=draft["stage"], revision_no=draft["revision_no"])
                if cbd_draft_is_stale(conn, draft):
                    result["to_refresh"].append({**item, "reason": "Specsheet acuan sudah direvisi"})
                elif stale_master_price_lines(conn, draft["id"]):
                    result["to_refresh"].append({**item, "reason": "Harga master berubah"})
                else:
                    result["in_progress"].append(item)
            else:
                latest = max(revisions, key=lambda r: (STAGES.index(r["stage"]), r["revision_no"]))
                if latest["sync_status"] == "NEEDS_REVISION":
                    item.update(cbd_revision_id=latest["id"], stage=latest["stage"], revision_no=latest["revision_no"])
                    result["to_revise"].append(item)
    result["price_gaps"] = price_gaps(conn)
    return result


def price_gaps(conn):
    """Material katalog + supplier di BOM terbit terakhir (article aktif) yang
    belum punya harga master berlaku — dikelompokkan per material+supplier,
    dengan warna yang belum berharga."""
    groups = {}
    for sp in _specsheets(conn):
        revision = latest_published_specsheet_revision(conn, sp["specsheet_id"])
        if not revision:
            continue
        rows = conn.execute(
            """SELECT DISTINCT bl.material_id, bl.supplier_id, bc.color,
                      m.material_code, m.name AS material_name, s.name AS supplier_name
               FROM bom_line bl
               JOIN bom_cell bc ON bc.bom_line_id = bl.id AND bc.is_used = 1
               JOIN revision_article ra ON ra.revision_id = bl.revision_id AND ra.article_id = bc.article_id
                    AND ra.status = 'ACTIVE'
               JOIN material m ON m.id = bl.material_id
               JOIN supplier s ON s.id = bl.supplier_id
               WHERE bl.revision_id=? AND bl.is_active=1""",
            (revision["id"],),
        ).fetchall()
        for row in rows:
            if is_quotation_material(conn, row["material_id"]):
                continue
            if lookup_price(conn, row["material_id"], row["supplier_id"], row["color"]):
                continue
            key = (row["material_id"], row["supplier_id"])
            group = groups.setdefault(key, {
                "material_id": row["material_id"], "material_code": row["material_code"],
                "material_name": row["material_name"], "supplier_name": row["supplier_name"],
                "colors": set(), "models": set(),
            })
            if row["color"]:
                group["colors"].add(row["color"])
            group["models"].add(sp["model_code"])
    return [
        {**g, "colors": sorted(g["colors"]), "models": sorted(g["models"])}
        for g in sorted(groups.values(), key=lambda g: (g["material_code"], g["supplier_name"]))
    ]


# ---------------- Master Admin ----------------

def approval_queue(conn):
    return {
        "materials": conn.execute(
            """SELECT id, material_code, name, category, created_by, created_at FROM material
               WHERE status='PROPOSED' ORDER BY created_at DESC"""
        ).fetchall(),
        "components": conn.execute(
            """SELECT c.id, c.number, c.name, g.code AS group_code, c.created_at FROM component c
               JOIN component_group g ON g.id = c.group_id WHERE c.status='PROPOSED' ORDER BY c.number"""
        ).fetchall(),
        "links": conn.execute(
            """SELECT ms.id, ms.material_id, m.material_code, m.name AS material_name,
                      s.name AS supplier_name, ms.created_by, ms.created_at
               FROM material_supplier ms JOIN material m ON m.id = ms.material_id
               JOIN supplier s ON s.id = ms.supplier_id
               WHERE ms.status='PROPOSED' ORDER BY ms.created_at DESC"""
        ).fetchall(),
    }


# ---------------- Brand Viewer ----------------

def _first_per(rows, key, limit):
    seen, result = set(), []
    for row in rows:
        if row[key] in seen:
            continue
        seen.add(row[key])
        result.append(row)
        if len(result) == limit:
            break
    return result


def recently_published(conn, limit=10):
    """Revisi terbit terakhir tiap specsheet (season) dan tiap article, terbaru dulu."""
    specsheets = conn.execute(
        """SELECT r.id AS revision_id, r.stage, r.revision_no, r.published_at, r.published_by,
                  sp.id AS specsheet_id, sp.season, pm.id AS model_id, pm.code AS model_code, pm.name AS model_name
           FROM specsheet_revision r JOIN specsheet sp ON sp.id = r.specsheet_id
           JOIN product_model pm ON pm.id = sp.model_id
           WHERE r.status='PUBLISHED' ORDER BY r.published_at DESC, r.rowid DESC"""
    ).fetchall()
    cbds = conn.execute(
        """SELECT c.id AS cbd_revision_id, c.stage, c.revision_no, c.published_at, c.sync_status,
                  a.id AS article_id, a.code AS article_code, a.colorway,
                  sp.id AS specsheet_id, sp.season, pm.id AS model_id, pm.code AS model_code
           FROM cbd_revision c JOIN article a ON a.id = c.article_id
           JOIN specsheet sp ON sp.id = a.specsheet_id JOIN product_model pm ON pm.id = sp.model_id
           WHERE c.status='PUBLISHED' ORDER BY c.published_at DESC, c.rowid DESC"""
    ).fetchall()
    return {"specsheets": _first_per(specsheets, "specsheet_id", limit),
            "cbds": _first_per(cbds, "article_id", limit)}


# ---------------- System Admin ----------------

def system_summary(conn):
    count = lambda sql: conn.execute(sql).fetchone()["c"]  # noqa: E731
    return {
        "models": count("SELECT COUNT(*) c FROM product_model"),
        "specsheets": count("SELECT COUNT(*) c FROM specsheet"),
        "articles": count("SELECT COUNT(*) c FROM article"),
        "cbd_revisions": count("SELECT COUNT(*) c FROM cbd_revision"),
        "materials": count("SELECT COUNT(*) c FROM material"),
        "audit_entries": count("SELECT COUNT(*) c FROM audit_log"),
        "last_audit": conn.execute("SELECT MAX(created_at) m FROM audit_log").fetchone()["m"],
    }
