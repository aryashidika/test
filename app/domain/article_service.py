"""Article (colorway/SKU) milik Model per season — dikelola di halaman Model,
sebelum dan terlepas dari revisi specsheet. Keikutsertaan article di sebuah
revisi (aktif/di-drop) tetap diatur per revisi di specsheet (`revision_article`)."""

from ..ids import new_id
from .audit import write_audit_log
from .revision_service import ensure_draft, link_article


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


def list_articles_not_in_revision(conn, revision_id: str, specsheet_id: str):
    """Article season ini yang belum masuk revisi — pilihan "Pilih Article" di specsheet."""
    return conn.execute(
        """SELECT * FROM article WHERE specsheet_id=? AND id NOT IN
           (SELECT article_id FROM revision_article WHERE revision_id=?) ORDER BY code""",
        (specsheet_id, revision_id),
    ).fetchall()


def _clean_input(code, colorway):
    code = (code or "").strip()
    colorway = (colorway or "").strip()
    if not code:
        raise ValueError("Kode article wajib diisi.")
    if not colorway:
        raise ValueError("Colorway wajib diisi.")
    return code, colorway


def _get_article(conn, article_id):
    row = conn.execute("SELECT * FROM article WHERE id=?", (article_id,)).fetchone()
    if not row:
        raise ValueError("Article tidak ditemukan.")
    return row


def _ensure_unique_code(conn, specsheet_id, code, exclude_id=None):
    row = conn.execute(
        "SELECT id FROM article WHERE specsheet_id=? AND code=?", (specsheet_id, code)
    ).fetchone()
    if row and row["id"] != exclude_id:
        raise ValueError(f"Kode article '{code}' sudah ada di season ini.")


def article_is_used(conn, article_id: str) -> bool:
    """Sudah pernah masuk revisi specsheet, sel BOM, atau CBD."""
    return conn.execute(
        """SELECT 1 FROM revision_article WHERE article_id=?
           UNION SELECT 1 FROM bom_cell WHERE article_id=?
           UNION SELECT 1 FROM cbd_revision WHERE article_id=? LIMIT 1""",
        (article_id, article_id, article_id),
    ).fetchone() is not None


def create_article(conn, specsheet_id: str, code: str, colorway: str, actor: str) -> str:
    code, colorway = _clean_input(code, colorway)
    _ensure_unique_code(conn, specsheet_id, code)
    article_id = new_id()
    conn.execute(
        "INSERT INTO article (id, specsheet_id, code, colorway) VALUES (?,?,?,?)",
        (article_id, specsheet_id, code, colorway),
    )
    write_audit_log(conn, actor, "Article", article_id, "CREATE", None,
                     {"specsheetId": specsheet_id, "code": code, "colorway": colorway})
    conn.commit()
    return article_id


def update_article(conn, article_id: str, code: str, colorway: str, actor: str) -> None:
    """Colorway selalu bisa diubah; kode hanya selama article belum dipakai
    (kode dipakai sebagai identitas di specsheet, CBD, dan ekspor)."""
    before = _get_article(conn, article_id)
    code, colorway = _clean_input(code, colorway)
    if code != before["code"]:
        if article_is_used(conn, article_id):
            raise ValueError("Kode article tidak bisa diubah karena sudah dipakai di specsheet/CBD.")
        _ensure_unique_code(conn, before["specsheet_id"], code, exclude_id=article_id)
    conn.execute("UPDATE article SET code=?, colorway=? WHERE id=?", (code, colorway, article_id))
    write_audit_log(conn, actor, "Article", article_id, "UPDATE",
                     {"code": before["code"], "colorway": before["colorway"]},
                     {"code": code, "colorway": colorway})
    conn.commit()


def delete_article(conn, article_id: str, actor: str) -> None:
    before = _get_article(conn, article_id)
    if article_is_used(conn, article_id):
        raise ValueError(
            "Article sudah dipakai di specsheet/CBD dan tidak bisa dihapus. "
            "Hentikan pemakaiannya dengan drop di specsheet."
        )
    conn.execute("DELETE FROM article WHERE id=?", (article_id,))
    write_audit_log(conn, actor, "Article", article_id, "DELETE",
                     {"code": before["code"], "colorway": before["colorway"]}, None)
    conn.commit()


def copy_articles_from_specsheet(conn, target_specsheet_id: str, source_specsheet_id: str, actor: str) -> int:
    """Salin kode + colorway article dari season lain model yang sama. Kode yang
    sudah ada di season tujuan dilewati. Mengembalikan jumlah yang disalin."""
    if target_specsheet_id == source_specsheet_id:
        raise ValueError("Pilih season sumber yang berbeda.")
    existing = {r["code"] for r in list_articles_for_specsheet(conn, target_specsheet_id)}
    copied = 0
    for src in list_articles_for_specsheet(conn, source_specsheet_id):
        if src["code"] in existing:
            continue
        article_id = new_id()
        conn.execute(
            "INSERT INTO article (id, specsheet_id, code, colorway) VALUES (?,?,?,?)",
            (article_id, target_specsheet_id, src["code"], src["colorway"]),
        )
        write_audit_log(conn, actor, "Article", article_id, "CREATE", None,
                         {"specsheetId": target_specsheet_id, "code": src["code"],
                          "colorway": src["colorway"], "copiedFrom": src["id"]})
        copied += 1
    conn.commit()
    return copied


def include_article(conn, revision_id: str, article_id: str, actor: str) -> None:
    """Masukkan article season ini ke revisi DRAFT ("Pilih Article" di specsheet)."""
    revision = ensure_draft(conn, revision_id)
    article = _get_article(conn, article_id)
    if article["specsheet_id"] != revision["specsheet_id"]:
        raise ValueError("Article bukan milik season specsheet ini.")
    if conn.execute(
        "SELECT 1 FROM revision_article WHERE revision_id=? AND article_id=?", (revision_id, article_id)
    ).fetchone():
        raise ValueError("Article ini sudah ada pada revisi ini.")
    link_article(conn, revision_id, article_id)
    write_audit_log(conn, actor, "Article", article_id, "ADD_TO_REVISION", None,
                     {"revisionId": revision_id, "code": article["code"]})
    conn.commit()


def add_article(conn, revision_id: str, specsheet_id: str, code: str, colorway: str, actor: str) -> str:
    """Buat article (bila kodenya belum ada di season) lalu langsung masukkan ke
    revisi DRAFT — jalan pintas untuk seed & test."""
    ensure_draft(conn, revision_id)
    code, colorway = _clean_input(code, colorway)
    row = conn.execute(
        "SELECT id FROM article WHERE specsheet_id=? AND code=?", (specsheet_id, code)
    ).fetchone()
    article_id = row["id"] if row else create_article(conn, specsheet_id, code, colorway, actor)
    include_article(conn, revision_id, article_id, actor)
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


def list_articles_overview(conn, specsheet_id: str, include_drafts: bool = True):
    """Article season ini + ringkasan statusnya di specsheet dan CBD, untuk tab
    Season & Article di halaman Model. `include_drafts=False` meringkas dari
    revisi PUBLISHED saja (role yang tidak boleh melihat draft)."""
    latest_published = conn.execute(
        """SELECT * FROM specsheet_revision WHERE specsheet_id=? AND status='PUBLISHED'
           ORDER BY created_at DESC, rowid DESC LIMIT 1""",
        (specsheet_id,),
    ).fetchone()
    draft = conn.execute(
        "SELECT * FROM specsheet_revision WHERE specsheet_id=? AND status='DRAFT'", (specsheet_id,)
    ).fetchone() if include_drafts else None
    cbd_filter = "" if include_drafts else " AND status='PUBLISHED'"

    result = []
    for article in list_articles_for_specsheet(conn, specsheet_id):
        d = dict(article)
        in_published = conn.execute(
            "SELECT status FROM revision_article WHERE revision_id=? AND article_id=?",
            (latest_published["id"], article["id"]),
        ).fetchone() if latest_published else None
        in_draft = conn.execute(
            "SELECT status FROM revision_article WHERE revision_id=? AND article_id=?",
            (draft["id"], article["id"]),
        ).fetchone() if draft else None

        pub_label = f"{latest_published['stage']} r{latest_published['revision_no']}" if latest_published else ""
        if in_published:
            d["spec_status"] = in_published["status"]
            d["spec_detail"] = f"{pub_label} terbit"
        elif in_draft:
            d["spec_status"] = "DRAFT"
            d["spec_detail"] = f"{draft['stage']} r{draft['revision_no']}, belum terbit"
        else:
            d["spec_status"], d["spec_detail"] = "NONE", ""

        cbd = conn.execute(
            f"""SELECT * FROM cbd_revision WHERE article_id=?{cbd_filter}
                ORDER BY created_at DESC, rowid DESC LIMIT 1""",
            (article["id"],),
        ).fetchone()
        d["cbd_revision"] = dict(cbd) if cbd else None
        d["deletable"] = not article_is_used(conn, article["id"])
        result.append(d)
    return result
