import json

from ..ids import new_id
from .audit import write_audit_log
from .cbd_service import mark_cbd_sync_status
from .diff_service import compute_bom_diff

STAGES = ["PULL", "SMS", "GTM", "PROD"]


def get_revision(conn, revision_id: str):
    row = conn.execute("SELECT * FROM specsheet_revision WHERE id=?", (revision_id,)).fetchone()
    if not row:
        raise ValueError("Revisi tidak ditemukan.")
    return row


def ensure_draft(conn, revision_id: str):
    row = get_revision(conn, revision_id)
    if row["status"] != "DRAFT":
        raise ValueError("Revisi ini sudah diterbitkan dan tidak bisa diubah.")
    return row


def list_revisions(conn, specsheet_id: str):
    return conn.execute(
        "SELECT * FROM specsheet_revision WHERE specsheet_id=? ORDER BY stage, revision_no",
        (specsheet_id,),
    ).fetchall()


def get_draft_revision(conn, specsheet_id: str):
    return conn.execute(
        "SELECT * FROM specsheet_revision WHERE specsheet_id=? AND status='DRAFT'",
        (specsheet_id,),
    ).fetchone()


def _guard_single_draft(conn, specsheet_id: str):
    if get_draft_revision(conn, specsheet_id):
        raise ValueError("Sudah ada revisi DRAFT untuk specsheet ini. Selesaikan/terbitkan dulu.")


def _copy_lines_and_cells_preserving_line_key(conn, revision_id: str, source_revision_id: str):
    source_lines = conn.execute(
        "SELECT * FROM bom_line WHERE revision_id=? AND is_active=1", (source_revision_id,)
    ).fetchall()
    old_to_new_line_id = {}
    for line in source_lines:
        new_line_id = new_id()
        old_to_new_line_id[line["id"]] = new_line_id
        conn.execute(
            """INSERT INTO bom_line (id, revision_id, line_key, origin_line_key, replaces_line_key,
               component_id, local_component_no, local_component_name, parent_line_key, sub_seq,
               sub_name, material_id, supplier_id, process, is_active, sort_order)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?)""",
            (new_line_id, revision_id, line["line_key"], line["origin_line_key"], line["replaces_line_key"],
             line["component_id"], line["local_component_no"], line["local_component_name"],
             line["parent_line_key"], line["sub_seq"], line["sub_name"], line["material_id"],
             line["supplier_id"], line["process"], line["sort_order"]),
        )
    for line in source_lines:
        cells = conn.execute("SELECT * FROM bom_cell WHERE bom_line_id=?", (line["id"],)).fetchall()
        new_line_id = old_to_new_line_id[line["id"]]
        for cell in cells:
            conn.execute(
                "INSERT INTO bom_cell (bom_line_id, article_id, color, is_used) VALUES (?,?,?,?)",
                (new_line_id, cell["article_id"], cell["color"], cell["is_used"]),
            )


def _copy_revision_articles(conn, revision_id: str, source_revision_id: str):
    rows = conn.execute(
        "SELECT * FROM revision_article WHERE revision_id=?", (source_revision_id,)
    ).fetchall()
    for row in rows:
        conn.execute(
            "INSERT INTO revision_article (revision_id, article_id, status) VALUES (?,?,?)",
            (revision_id, row["article_id"], row["status"]),
        )


def link_article(conn, revision_id: str, article_id: str, status: str = "ACTIVE") -> None:
    """Masukkan article ke revisi: baris revision_article + sel kosong di setiap
    baris BOM aktif (sel yang sudah ada dibiarkan)."""
    conn.execute(
        "INSERT INTO revision_article (revision_id, article_id, status) VALUES (?,?,?)",
        (revision_id, article_id, status),
    )
    lines = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND is_active=1", (revision_id,)
    ).fetchall()
    for line in lines:
        conn.execute(
            "INSERT OR IGNORE INTO bom_cell (bom_line_id, article_id, is_used) VALUES (?,?,0)",
            (line["id"], article_id),
        )


def _include_season_articles(conn, revision_id: str, specsheet_id: str) -> None:
    """Revisi pertama sebuah season langsung memuat semua article season itu
    (article dikelola di halaman Model, sebelum specsheet dibuat)."""
    articles = conn.execute(
        """SELECT id FROM article WHERE specsheet_id=? AND id NOT IN
           (SELECT article_id FROM revision_article WHERE revision_id=?) ORDER BY code""",
        (specsheet_id, revision_id),
    ).fetchall()
    for article in articles:
        link_article(conn, revision_id, article["id"])


def create_empty_revision(conn, specsheet_id: str, actor: str, stage: str = "PULL") -> str:
    """Specsheet baru, tanpa sumber -> r0 kosong. Stage bisa dipilih (specsheet
    tidak selalu mulai dari PULL — mis. article yang masuk belakangan)."""
    if stage not in STAGES:
        raise ValueError("Stage tidak valid.")
    _guard_single_draft(conn, specsheet_id)
    revision_id = new_id()
    conn.execute(
        "INSERT INTO specsheet_revision (id, specsheet_id, stage, revision_no, status) VALUES (?,?,?,?,?)",
        (revision_id, specsheet_id, stage, 0, "DRAFT"),
    )
    _include_season_articles(conn, revision_id, specsheet_id)
    write_audit_log(conn, actor, "SpecsheetRevision", revision_id, "CREATE",
                     None, {"stage": stage, "revisionNo": 0, "source": "EMPTY"})
    conn.commit()
    return revision_id


def create_carryover_revision(conn, specsheet_id: str, source_revision_id: str, actor: str,
                               stage: str = "PULL") -> str:
    """Carryover dari season lalu. lineKey baru, originLineKey = lineKey lama.
    Article dan BomCell season sumber TIDAK disalin; article season tujuan (dari
    halaman Model) langsung dimuat dengan sel kosong. Stage bisa dipilih (lihat
    create_empty_revision)."""
    if stage not in STAGES:
        raise ValueError("Stage tidak valid.")
    _guard_single_draft(conn, specsheet_id)
    source = get_revision(conn, source_revision_id)
    if source["status"] != "PUBLISHED":
        raise ValueError("Revisi sumber carryover harus revisi yang sudah terbit.")

    revision_id = new_id()
    conn.execute(
        "INSERT INTO specsheet_revision (id, specsheet_id, stage, revision_no, status, source_revision_id) "
        "VALUES (?,?,?,?,?,?)",
        (revision_id, specsheet_id, stage, 0, "DRAFT", source_revision_id),
    )

    source_lines = conn.execute(
        "SELECT * FROM bom_line WHERE revision_id=? AND is_active=1", (source_revision_id,)
    ).fetchall()
    key_map = {}
    top_level = [l for l in source_lines if not l["parent_line_key"]]
    children = [l for l in source_lines if l["parent_line_key"]]
    for line in top_level:
        new_key = new_id()
        key_map[line["line_key"]] = new_key
        conn.execute(
            """INSERT INTO bom_line (id, revision_id, line_key, origin_line_key, component_id,
               local_component_no, local_component_name, material_id, supplier_id, process,
               is_active, sort_order)
               VALUES (?,?,?,?,?,?,?,?,?,?,1,?)""",
            (new_id(), revision_id, new_key, line["line_key"], line["component_id"],
             line["local_component_no"], line["local_component_name"], line["material_id"],
             line["supplier_id"], line["process"], line["sort_order"]),
        )
    for line in children:
        parent_new_key = key_map.get(line["parent_line_key"])
        if not parent_new_key:
            continue
        new_key = new_id()
        conn.execute(
            """INSERT INTO bom_line (id, revision_id, line_key, origin_line_key, parent_line_key,
               sub_seq, sub_name, material_id, supplier_id, process, is_active, sort_order)
               VALUES (?,?,?,?,?,?,?,?,?,?,1,?)""",
            (new_id(), revision_id, new_key, line["line_key"], parent_new_key,
             line["sub_seq"], line["sub_name"], line["material_id"], line["supplier_id"],
             line["process"], line["sort_order"]),
        )

    _include_season_articles(conn, revision_id, specsheet_id)
    write_audit_log(conn, actor, "SpecsheetRevision", revision_id, "CREATE",
                     None, {"stage": stage, "revisionNo": 0, "source": "CARRYOVER", "from": source_revision_id})
    conn.commit()
    return revision_id


def create_next_revision_same_stage(conn, specsheet_id: str, actor: str) -> str:
    """Revisi baru di stage yang sama. lineKey dipertahankan, revisionNo+1."""
    _guard_single_draft(conn, specsheet_id)
    latest_in_stage = _latest_published_overall(conn, specsheet_id)
    if not latest_in_stage:
        raise ValueError("Belum ada revisi terbit untuk specsheet ini.")
    stage = latest_in_stage["stage"]
    latest_same_stage = conn.execute(
        "SELECT * FROM specsheet_revision WHERE specsheet_id=? AND stage=? AND status='PUBLISHED' "
        "ORDER BY revision_no DESC LIMIT 1",
        (specsheet_id, stage),
    ).fetchone()

    revision_id = new_id()
    conn.execute(
        "INSERT INTO specsheet_revision (id, specsheet_id, stage, revision_no, status, source_revision_id) "
        "VALUES (?,?,?,?,?,?)",
        (revision_id, specsheet_id, stage, latest_same_stage["revision_no"] + 1, "DRAFT", latest_same_stage["id"]),
    )
    _copy_lines_and_cells_preserving_line_key(conn, revision_id, latest_same_stage["id"])
    _copy_revision_articles(conn, revision_id, latest_same_stage["id"])

    write_audit_log(conn, actor, "SpecsheetRevision", revision_id, "CREATE", None,
                     {"stage": stage, "revisionNo": latest_same_stage["revision_no"] + 1, "source": "SAME_STAGE"})
    conn.commit()
    return revision_id


def _latest_published_overall(conn, specsheet_id: str):
    """Revisi terbit terakhir specsheet ini, berdasarkan urutan stage lalu revisionNo."""
    rows = conn.execute(
        "SELECT * FROM specsheet_revision WHERE specsheet_id=? AND status='PUBLISHED'",
        (specsheet_id,),
    ).fetchall()
    if not rows:
        return None
    return max(rows, key=lambda r: (STAGES.index(r["stage"]), r["revision_no"]))


def create_next_stage_revision(conn, specsheet_id: str, actor: str) -> str:
    """Stage berikutnya. Salin revisi terbit terakhir stage sebelumnya. revisionNo=0."""
    _guard_single_draft(conn, specsheet_id)
    latest = _latest_published_overall(conn, specsheet_id)
    if not latest:
        raise ValueError("Belum ada revisi terbit untuk specsheet ini.")
    current_idx = STAGES.index(latest["stage"])
    if current_idx >= len(STAGES) - 1:
        raise ValueError("Sudah berada di stage terakhir (PROD).")
    next_stage = STAGES[current_idx + 1]

    revision_id = new_id()
    conn.execute(
        "INSERT INTO specsheet_revision (id, specsheet_id, stage, revision_no, status, source_revision_id) "
        "VALUES (?,?,?,?,?,?)",
        (revision_id, specsheet_id, next_stage, 0, "DRAFT", latest["id"]),
    )
    _copy_lines_and_cells_preserving_line_key(conn, revision_id, latest["id"])
    _copy_revision_articles(conn, revision_id, latest["id"])

    write_audit_log(conn, actor, "SpecsheetRevision", revision_id, "CREATE", None,
                     {"stage": next_stage, "revisionNo": 0, "source": "NEXT_STAGE"})
    conn.commit()
    return revision_id


def publish_checklist(conn, revision_id: str) -> list:
    """Pemeriksaan sebelum terbit, dipakai modal "Terbitkan" (ditampilkan sebelum
    diklik) dan `publish_revision` (item `blocking` yang gagal menolak terbit).
    Tiap item: label, ok, detail, blocking, error (pesan penolakan)."""
    active_articles = conn.execute(
        """SELECT a.id, a.code FROM revision_article ra JOIN article a ON a.id = ra.article_id
           WHERE ra.revision_id=? AND ra.status='ACTIVE' ORDER BY a.code""",
        (revision_id,),
    ).fetchall()
    unused = [a["code"] for a in active_articles if conn.execute(
        """SELECT COUNT(*) c FROM bom_cell bc JOIN bom_line bl ON bl.id = bc.bom_line_id
           WHERE bl.revision_id=? AND bl.is_active=1 AND bc.article_id=? AND bc.is_used=1""",
        (revision_id, a["id"]),
    ).fetchone()["c"] == 0]
    inactive = [r["name"] for r in conn.execute(
        """SELECT DISTINCT m.name FROM bom_line bl JOIN material m ON m.id = bl.material_id
           WHERE bl.revision_id=? AND bl.is_active=1 AND m.status='INACTIVE' ORDER BY m.name""",
        (revision_id,),
    ).fetchall()]
    no_supplier = conn.execute(
        "SELECT COUNT(*) c FROM bom_line WHERE revision_id=? AND is_active=1 AND supplier_id IS NULL",
        (revision_id,),
    ).fetchone()["c"]
    return [
        {"label": "Minimal satu article aktif", "ok": bool(active_articles), "blocking": True,
         "detail": f"{len(active_articles)} article aktif",
         "error": "Specsheet harus punya minimal satu article aktif sebelum diterbitkan."},
        {"label": "Setiap article aktif dipakai di BOM", "ok": not unused, "blocking": True,
         "detail": ("Belum dipakai: " + ", ".join(unused)) if unused else "",
         "error": f"Article '{unused[0]}' belum memakai baris BOM manapun." if unused else ""},
        {"label": "Tidak ada material INACTIVE", "ok": not inactive, "blocking": True,
         "detail": ", ".join(inactive),
         "error": f"Ada baris memakai material berstatus INACTIVE: {', '.join(inactive)}." if inactive else ""},
        {"label": "Semua baris punya supplier (dibutuhkan harga CBD)", "ok": not no_supplier, "blocking": False,
         "detail": f"{no_supplier} baris tanpa supplier — boleh terbit, tapi harga CBD-nya tidak bisa diambil"
                   if no_supplier else "", "error": ""},
    ]


def publish_revision(conn, revision_id: str, category: str, reason: str, actor: str) -> dict:
    revision = ensure_draft(conn, revision_id)

    for check in publish_checklist(conn, revision_id):
        if check["blocking"] and not check["ok"]:
            raise ValueError(check["error"])

    requires_reason = revision["source_revision_id"] is not None or revision["revision_no"] != 0
    reason = (reason or "").strip()
    if requires_reason and not reason:
        raise ValueError("Alasan perubahan (change log) wajib diisi untuk revisi ini.")
    if category not in (
        "EX_RATE", "LOP", "AMORTIZATION", "MATERIAL", "YIELD", "COMPONENT", "TREATMENT", "OTHER",
    ):
        raise ValueError("Kategori change log tidak valid.")

    diff = {}
    if revision["source_revision_id"]:
        diff = compute_bom_diff(conn, revision["source_revision_id"], revision_id)

    conn.execute(
        "UPDATE specsheet_revision SET status='PUBLISHED', published_at=datetime('now'), published_by=? WHERE id=?",
        (actor, revision_id),
    )

    change_log_id = new_id()
    conn.execute(
        """INSERT INTO change_log (id, doc_type, revision_id, category, reason, diff_json, created_by)
           VALUES (?,?,?,?,?,?,?)""",
        (change_log_id, "SPECSHEET", revision_id, category, reason or "Revisi awal.", json.dumps(diff), actor),
    )

    write_audit_log(conn, actor, "SpecsheetRevision", revision_id, "PUBLISH",
                     {"status": "DRAFT"}, {"status": "PUBLISHED", "changeLogId": change_log_id})
    conn.commit()

    mark_cbd_sync_status(conn, revision["specsheet_id"], revision["source_revision_id"], revision_id, actor)

    return diff


def delete_draft_revision(conn, revision_id: str, actor: str) -> None:
    """Hapus revisi specsheet DRAFT beserta isinya (baris BOM, sel, daftar
    article revisi) seakan belum pernah dibuat. Article-nya sendiri TIDAK ikut
    terhapus — article milik Model/season, dikelola di halaman Model.
    Revisi terbit tidak bisa dihapus. CBD tidak terdampak: CBD selalu mengacu ke
    revisi specsheet terbit, bukan draft."""
    revision = ensure_draft(conn, revision_id)

    conn.execute(
        "DELETE FROM bom_cell WHERE bom_line_id IN (SELECT id FROM bom_line WHERE revision_id=?)", (revision_id,)
    )
    conn.execute("DELETE FROM bom_line WHERE revision_id=?", (revision_id,))
    conn.execute("DELETE FROM revision_article WHERE revision_id=?", (revision_id,))
    conn.execute("DELETE FROM specsheet_revision WHERE id=?", (revision_id,))

    write_audit_log(conn, actor, "SpecsheetRevision", revision_id, "DELETE_DRAFT",
                     {"stage": revision["stage"], "revisionNo": revision["revision_no"]}, None)
    conn.commit()


def get_change_log(conn, revision_id: str):
    return conn.execute(
        "SELECT * FROM change_log WHERE revision_id=? ORDER BY created_at DESC", (revision_id,)
    ).fetchall()
