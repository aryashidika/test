from ..ids import new_id
from .audit import write_audit_log
from .revision_service import ensure_draft


def list_articles_for_specsheet(conn, specsheet_id: str):
    """Semua Article milik specsheet ini, lintas revisi (Article bukan snapshot per
    revisi — dipakai untuk navigasi CBD yang berbasis Article, bukan Revisi)."""
    return conn.execute(
        "SELECT * FROM article WHERE specsheet_id=? ORDER BY code", (specsheet_id,)
    ).fetchall()


def list_articles_for_revision(conn, revision_id: str):
    return conn.execute(
        """SELECT a.*, ra.status AS revision_status FROM revision_article ra
           JOIN article a ON a.id = ra.article_id
           WHERE ra.revision_id=? ORDER BY a.code""",
        (revision_id,),
    ).fetchall()


def add_article(conn, revision_id: str, specsheet_id: str, code: str, colorway: str, actor: str) -> str:
    ensure_draft(conn, revision_id)
    code = (code or "").strip()
    colorway = (colorway or "").strip()
    if not code:
        raise ValueError("Kode article wajib diisi.")
    if not colorway:
        raise ValueError("Colorway wajib diisi.")

    article = conn.execute(
        "SELECT * FROM article WHERE specsheet_id=? AND code=?", (specsheet_id, code)
    ).fetchone()
    if not article:
        article_id = new_id()
        conn.execute(
            "INSERT INTO article (id, specsheet_id, code, colorway) VALUES (?,?,?,?)",
            (article_id, specsheet_id, code, colorway),
        )
    else:
        article_id = article["id"]

    existing_link = conn.execute(
        "SELECT * FROM revision_article WHERE revision_id=? AND article_id=?", (revision_id, article_id)
    ).fetchone()
    if existing_link:
        raise ValueError("Article ini sudah ada pada revisi ini.")

    conn.execute(
        "INSERT INTO revision_article (revision_id, article_id, status) VALUES (?,?, 'ACTIVE')",
        (revision_id, article_id),
    )

    lines = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND is_active=1", (revision_id,)
    ).fetchall()
    for line in lines:
        conn.execute(
            "INSERT OR IGNORE INTO bom_cell (bom_line_id, article_id, is_used) VALUES (?,?,0)",
            (line["id"], article_id),
        )

    write_audit_log(conn, actor, "Article", article_id, "ADD_TO_REVISION", None,
                     {"revisionId": revision_id, "code": code, "colorway": colorway})
    conn.commit()
    return article_id


def set_article_status(conn, revision_id: str, article_id: str, status: str, actor: str) -> None:
    ensure_draft(conn, revision_id)
    if status not in ("ACTIVE", "DROPPED"):
        raise ValueError("Status article tidak valid.")
    before = conn.execute(
        "SELECT * FROM revision_article WHERE revision_id=? AND article_id=?", (revision_id, article_id)
    ).fetchone()
    if not before:
        raise ValueError("Article tidak ditemukan pada revisi ini.")

    conn.execute(
        "UPDATE revision_article SET status=? WHERE revision_id=? AND article_id=?",
        (status, revision_id, article_id),
    )
    if status == "ACTIVE":
        lines = conn.execute(
            "SELECT id FROM bom_line WHERE revision_id=? AND is_active=1", (revision_id,)
        ).fetchall()
        for line in lines:
            conn.execute(
                "INSERT OR IGNORE INTO bom_cell (bom_line_id, article_id, is_used) VALUES (?,?,0)",
                (line["id"], article_id),
            )

    write_audit_log(conn, actor, "RevisionArticle", f"{revision_id}:{article_id}", "STATUS_CHANGE",
                     {"status": before["status"]}, {"status": status})
    conn.commit()
