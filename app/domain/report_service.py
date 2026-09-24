"""Laporan (PRD 7.4 / M4): validasi CBD vs specsheet, where-used, histori
harga, dan harga referensi. Semua fungsi di sini hanya MEMBACA data (tidak
ada mutasi) — dibangun di atas service M2/M3 yang sudah ada (`cbd_service`,
`bom_service`, dst) supaya logika pencocokan baris (lineKey -> originLineKey
-> identitas) dan definisi "revisi terbit terakhir" tetap satu sumber
kebenaran.
"""

from .bom_service import list_lines_with_cells
from .cbd_service import (
    STAGES,
    build_expected_lines,
    compute_display_fields,
    get_article,
    latest_published_specsheet_revision,
    list_cbd_lines,
)
from .material_price_service import lookup_price
from .specsheet_service import season_sort_key

# ---------------- Validasi CBD vs specsheet ----------------


def _line_display(conn, component_id, local_component_no, sub_seq, sub_name, material_id):
    component_name = None
    component_number = None
    if component_id:
        comp = conn.execute("SELECT name, number FROM component WHERE id=?", (component_id,)).fetchone()
        if comp:
            component_name, component_number = comp["name"], comp["number"]
    material = conn.execute("SELECT name FROM material WHERE id=?", (material_id,)).fetchone()
    material_name = material["name"] if material else None
    row = {
        "component_number": component_number, "master_component_name": component_name,
        "local_component_no": local_component_no, "sub_seq": sub_seq, "sub_name": sub_name,
        "material_name": material_name,
    }
    compute_display_fields(row)
    return row["display_no"], row["display_name"], material_name


def validation_report(conn, cbd_revision_id):
    """Bandingkan baris CBD revisi ini dengan baris yang SEHARUSNYA ada menurut
    revisi specsheet terbit TERKINI (bukan hanya specsheet_revision_id yang
    dipakai revisi ini saat digenerate) — supaya laporan juga menangkap drift
    yang belum ter-refresh, sejalan dengan tujuan laporan validasi (PRD 7.4).
    Tiga kelompok: `matched` (sesuai), `missing_in_cbd` (ada di specsheet, tidak
    ada baris CBD aktif untuk itu), `extra_in_cbd` (ada baris CBD aktif yang
    sudah tidak diharapkan specsheet lagi — termasuk baris `MISSING_IN_SPEC`)."""
    revision = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (cbd_revision_id,)).fetchone()
    if not revision:
        raise ValueError("Revisi CBD tidak ditemukan.")
    article = get_article(conn, revision["article_id"])
    latest_specsheet = latest_published_specsheet_revision(conn, article["specsheet_id"])

    expected_by_key = {}
    if latest_specsheet:
        for line in build_expected_lines(conn, revision["article_id"], latest_specsheet["id"]):
            expected_by_key[line["line_key"]] = line

    actual_lines = list_cbd_lines(conn, cbd_revision_id)
    active_by_key = {l["line_key"]: l for l in actual_lines if l["status"] == "ACTIVE"}

    matched = []
    missing_in_cbd = []
    for key, exp in expected_by_key.items():
        display_no, display_name, material_name = _line_display(
            conn, exp["component_id"], exp["local_component_no"], exp["sub_seq"], exp["sub_name"],
            exp["material_id"],
        )
        entry = {"line_key": key, "display_no": display_no, "display_name": display_name,
                  "material_name": material_name, "color": exp["color"]}
        if key in active_by_key:
            matched.append(entry)
        else:
            missing_in_cbd.append(entry)

    extra_in_cbd = []
    for key, line in active_by_key.items():
        if key in expected_by_key:
            continue
        d = dict(line)
        compute_display_fields(d)
        extra_in_cbd.append({"line_key": key, "display_no": d["display_no"], "display_name": d["display_name"],
                              "material_name": line["material_name"], "color": line["color"]})

    for group in (matched, missing_in_cbd, extra_in_cbd):
        group.sort(key=lambda e: (e["display_no"] is None, e["display_no"] or 0))

    return {
        "matched": matched,
        "missing_in_cbd": missing_in_cbd,
        "extra_in_cbd": extra_in_cbd,
        "compared_against_latest_specsheet": bool(
            latest_specsheet and latest_specsheet["id"] != revision["specsheet_revision_id"]
        ),
    }


# ---------------- Where-used ----------------


def _latest_revision_per_specsheet(conn, published_only=False):
    """Revisi TERBARU (dibuat paling akhir, DRAFT atau PUBLISHED) tiap
    specsheet — merepresentasikan pemakaian material "saat ini", bukan hanya
    yang sudah terbit, karena where-used dipakai juga untuk mengecek dampak
    sebelum sebuah revisi diterbitkan. `published_only` untuk role yang tidak
    boleh melihat draft."""
    status_filter = " AND status='PUBLISHED'" if published_only else ""
    specsheets = conn.execute("SELECT id FROM specsheet").fetchall()
    result = {}
    for sp in specsheets:
        # `rowid` tiebreaks `created_at` (second-resolution TEXT) so the revision
        # created LAST wins even when two revisions land in the same second.
        rev = conn.execute(
            f"SELECT * FROM specsheet_revision WHERE specsheet_id=?{status_filter} "
            "ORDER BY created_at DESC, rowid DESC LIMIT 1",
            (sp["id"],),
        ).fetchone()
        if rev:
            result[sp["id"]] = rev
    return result


def where_used(conn, material_id, published_only=False):
    material = conn.execute("SELECT * FROM material WHERE id=?", (material_id,)).fetchone()
    if not material:
        raise ValueError("Material tidak ditemukan.")

    results = []
    for specsheet_id, revision in _latest_revision_per_specsheet(conn, published_only).items():
        lines = list_lines_with_cells(conn, revision["id"])
        matches = [l for l in lines if l["material_id"] == material_id]
        if not matches:
            continue
        # Sel article yang di-drop tetap is_used (drop tidak menghapus isi sel),
        # jadi article non-aktif di revisi ini dilewati eksplisit.
        active_article_ids = {
            r["article_id"] for r in conn.execute(
                "SELECT article_id FROM revision_article WHERE revision_id=? AND status='ACTIVE'",
                (revision["id"],),
            ).fetchall()
        }
        specsheet = conn.execute(
            """SELECT sp.season, pm.id AS model_id, pm.code AS model_code, pm.name AS model_name
               FROM specsheet sp JOIN product_model pm ON pm.id = sp.model_id WHERE sp.id=?""",
            (specsheet_id,),
        ).fetchone()
        for line in matches:
            for article_id, cell in line["cells"].items():
                if not cell["is_used"] or article_id not in active_article_ids:
                    continue
                article = conn.execute("SELECT * FROM article WHERE id=?", (article_id,)).fetchone()
                results.append({
                    "model_id": specsheet["model_id"], "model_code": specsheet["model_code"],
                    "model_name": specsheet["model_name"], "season": specsheet["season"],
                    "article_code": article["code"], "colorway": article["colorway"],
                    "display_no": line["display_no"], "display_name": line["display_name"],
                    "stage": revision["stage"], "revision_no": revision["revision_no"],
                    "revision_status": revision["status"],
                })
    results.sort(key=lambda r: (r["model_code"], season_sort_key(r["season"]), r["article_code"], r["display_no"] or ""))
    return results


# ---------------- Histori harga ----------------


def price_history(conn, material_id, stage="PROD"):
    """Per PRD 7.4: dikelompokkan `color + supplier + uom + stage + currency`,
    dalam mata uang asli (tidak ada konversi kurs sama sekali di laporan ini),
    hanya baris ACTIVE dari revisi CBD PUBLISHED."""
    material = conn.execute("SELECT * FROM material WHERE id=?", (material_id,)).fetchone()
    if not material:
        raise ValueError("Material tidak ditemukan.")
    if stage not in STAGES:
        raise ValueError("Stage tidak valid.")

    rows = conn.execute(
        """SELECT cl.color, cl.uom, cl.currency, cl.price_original, cr.revision_no, cr.published_at,
                  s.name AS supplier_name, a.code AS article_code, sp.season,
                  pm.code AS model_code, pm.name AS model_name
           FROM cbd_line cl
           JOIN cbd_revision cr ON cr.id = cl.cbd_revision_id
           JOIN article a ON a.id = cr.article_id
           JOIN specsheet sp ON sp.id = a.specsheet_id
           JOIN product_model pm ON pm.id = sp.model_id
           LEFT JOIN supplier s ON s.id = cl.supplier_id
           WHERE cl.material_id=? AND cl.status='ACTIVE' AND cr.status='PUBLISHED' AND cr.stage=?
             AND cl.price_original IS NOT NULL""",
        (material_id, stage),
    ).fetchall()

    groups = {}
    for r in rows:
        key = (r["color"] or "-", r["supplier_name"] or "-", r["uom"], r["currency"] or "-")
        groups.setdefault(key, []).append(r)

    result = []
    for (color, supplier, uom, currency), entries in groups.items():
        entries = sorted(entries, key=lambda r: r["published_at"] or "")
        result.append({
            "color": color, "supplier": supplier, "uom": uom, "currency": currency,
            "entries": entries,
        })
    result.sort(key=lambda g: (g["color"], g["supplier"], g["uom"], g["currency"]))
    return result


# ---------------- Harga referensi (tambahan di luar PRD) ----------------

# Dari paling spesifik ke paling longgar: (label tier, butuh warna?, butuh supplier?).
_REFERENCE_PRICE_TIERS = [
    ("MATERIAL_COLOR_SUPPLIER", True, True),
    ("MATERIAL_SUPPLIER", False, True),
    ("MATERIAL_COLOR", True, False),
    ("MATERIAL", False, False),
]


def reference_price(conn, material_id, color=None, supplier_id=None):
    """Harga referensi terakhir untuk satu kombinasi material (+warna +supplier
    kalau ada) dari CBD PUBLISHED mana pun (article/model/stage apa pun) —
    dipakai brand melihat perkiraan harga di specsheet yang sudah terbit,
    walau CBD article itu sendiri belum pernah dibuat. Dicari bertingkat dari
    kombinasi paling spesifik ke paling longgar (material+warna+supplier ->
    material+supplier -> material+warna -> material saja); berhenti di tingkat
    pertama yang ada hasilnya, dan dari situ ambil SATU histori yang paling
    baru terbit (`published_at` terbesar), stage apa pun. Mengembalikan None
    kalau tidak ada histori PUBLISHED sama sekali untuk material ini.

    Sejak ada master harga: harga master yang berlaku untuk material + supplier
    (+ warna) baris ini selalu didahulukan (tier "MASTER"); histori CBD di atas
    hanya dipakai kalau master belum punya harganya."""
    master = lookup_price(conn, material_id, supplier_id, color)
    if master:
        return {
            "tier": "MASTER", "price_original": master["price"], "currency": master["currency"],
            "valid_from": master["valid_from"], "stage": None, "revision_no": None, "published_at": None,
        }

    color_key = (color or "").strip().lower() or None

    for tier, needs_color, needs_supplier in _REFERENCE_PRICE_TIERS:
        if needs_color and not color_key:
            continue
        if needs_supplier and not supplier_id:
            continue
        conditions = ["cl.material_id=?", "cl.status='ACTIVE'", "cl.price_original IS NOT NULL", "cr.status='PUBLISHED'"]
        params = [material_id]
        if needs_color:
            conditions.append("LOWER(TRIM(cl.color))=?")
            params.append(color_key)
        if needs_supplier:
            conditions.append("cl.supplier_id=?")
            params.append(supplier_id)
        # `cr.rowid` tiebreaks `published_at` (second-resolution TEXT) so the
        # revision published LAST wins even when two land in the same second.
        row = conn.execute(
            f"""SELECT cl.price_original, cl.currency, cr.stage, cr.revision_no, cr.published_at
                FROM cbd_line cl JOIN cbd_revision cr ON cr.id = cl.cbd_revision_id
                WHERE {' AND '.join(conditions)}
                ORDER BY cr.published_at DESC, cr.rowid DESC LIMIT 1""",
            params,
        ).fetchone()
        if row:
            return {
                "tier": tier, "price_original": row["price_original"], "currency": row["currency"],
                "stage": row["stage"], "revision_no": row["revision_no"], "published_at": row["published_at"],
            }
    return None
