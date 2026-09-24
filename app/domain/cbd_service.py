"""CBD (cost breakdown) generation, editing, dan publish — PRD bagian 6.4-6.6.

Catatan implementasi (deviasi dari PRD, lihat juga README):
- Supplier baris CBD SELALU mengikuti `bom_line.supplier_id` dari specsheet (tidak
  bisa di-override di CBD) — supplier bukan urusan CBD, itu urusan specsheet.
- Harga & currency diambil dari master harga (`material_price_service.lookup_price`:
  material + supplier + warna, lalu material + supplier untuk semua warna) dan
  disimpan sebagai snapshot di baris (`price_source='MASTER'`). Tidak ada input
  harga ke master dari grid CBD. Input harga di CBD hanya ada dua:
  * material QUOTATION (proses: printing, molding, dst): harga + currency
    diisi langsung per baris (`price_source='QUOTATION'`), tanpa alasan;
  * material CATALOG: override harga sekali pakai (`price_source='OVERRIDE'`,
    alasan wajib).
  Keduanya ikut ter-copy ke CBD baru yang dibuat dari CBD sumber — revisi
  berikutnya article yang sama maupun "Copy dari Article Lain".
- Baris tanpa harga boleh diterbitkan (cost 0) — mis. baris proses yang
  harganya sudah diwakili satu baris proses lain.
- Tidak ada lagi Aturan Transformasi (EXCLUDE/MERGE, dulu PRD 6.4/5.4) — dihapus
  atas permintaan lanjutan supaya semua baris BOM `isUsed` di specsheet selalu
  terrefleksi apa adanya (1:1) ke CBD, tanpa pengecualian/penggabungan komponen.
- Usage tidak diinput langsung: Usage = 1 / Yield (Yield = jumlah pasang yang
  dihasilkan satu unit material). Pengguna hanya mengisi Yield.
- Loss % default 0.00 (bisa diedit), bukan kosong.
- Tidak ada aksi "Batalkan baris" di CBD — status baris murni mengikuti specsheet
  (ACTIVE bila masih diharapkan, MISSING_IN_SPEC bila sudah tidak ada di
  specsheet). Status CANCELLED (PRD 6.4 langkah 4) dengan demikian tidak pernah
  terjadi di app ini dan tidak diimplementasikan.
- Margin % di rekap adalah tambahan di luar PRD; dihitung terhadap Selling Price
  (lihat `cbd_calc.margin_pct`), bukan bagian dari spesifikasi resmi.

STAGES didefinisikan ulang di sini (bukan import dari revision_service) supaya
tidak terjadi circular import: revision_service memanggil mark_cbd_sync_status
di sini setelah revisi specsheet terbit.
"""

import json
from decimal import Decimal

from ..ids import new_id
from ..normalize import normalize_text, parse_decimal
from .audit import write_audit_log
from .cbd_calc import (
    material_cost_idr,
    selling_price_from_margin,
    to_decimal,
    to_text,
    total_cost,
    usage_from_yield,
)
from .cbd_diff_service import compute_cbd_diff
from .material_price_service import is_quotation_material, lookup_price

STAGES = ["PULL", "SMS", "GTM", "PROD"]

CHANGE_CATEGORIES = (
    "EX_RATE", "LOP", "AMORTIZATION", "MATERIAL", "YIELD", "COMPONENT", "TREATMENT", "OTHER",
)


# ---------------- helpers ----------------

def get_article(conn, article_id):
    row = conn.execute("SELECT * FROM article WHERE id=?", (article_id,)).fetchone()
    if not row:
        raise ValueError("Article tidak ditemukan.")
    return row


def latest_published_specsheet_revision(conn, specsheet_id):
    rows = conn.execute(
        "SELECT * FROM specsheet_revision WHERE specsheet_id=? AND status='PUBLISHED'", (specsheet_id,)
    ).fetchall()
    if not rows:
        return None
    return max(rows, key=lambda r: (STAGES.index(r["stage"]), r["revision_no"]))


def latest_published_cbd(conn, article_id):
    rows = conn.execute(
        "SELECT * FROM cbd_revision WHERE article_id=? AND status='PUBLISHED'", (article_id,)
    ).fetchall()
    if not rows:
        return None
    return max(rows, key=lambda r: (STAGES.index(r["stage"]), r["revision_no"]))


def _get_cbd_revision(conn, cbd_revision_id):
    row = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (cbd_revision_id,)).fetchone()
    if not row:
        raise ValueError("Revisi CBD tidak ditemukan.")
    return row


def article_cbd_status(conn, article_id):
    """Status article menurut revisi specsheet TERBIT terakhir (acuan CBD):
    'ACTIVE', 'DROPPED' (di-drop di revisi itu), atau 'NOT_PUBLISHED' (belum
    ada di revisi terbit mana pun, mis. baru ditambahkan di revisi DRAFT).
    Drop/aktifkan article di revisi specsheet DRAFT baru berlaku untuk CBD
    setelah revisi itu terbit."""
    article = get_article(conn, article_id)
    latest = latest_published_specsheet_revision(conn, article["specsheet_id"])
    if not latest:
        return "NOT_PUBLISHED"
    row = conn.execute(
        "SELECT status FROM revision_article WHERE revision_id=? AND article_id=?", (latest["id"], article_id)
    ).fetchone()
    return row["status"] if row else "NOT_PUBLISHED"


def ensure_article_active_for_cbd(conn, article_id):
    status = article_cbd_status(conn, article_id)
    if status == "DROPPED":
        raise ValueError("Article ini sudah di-drop di specsheet terbit terakhir — CBD-nya tidak bisa "
                         "dibuat atau diubah lagi (hanya bisa dilihat).")
    if status == "NOT_PUBLISHED":
        raise ValueError("Article ini belum ada di revisi specsheet yang terbit. Terbitkan specsheet-nya dulu.")


def ensure_cbd_draft(conn, cbd_revision_id):
    """Dipakai semua aksi ubah CBD (edit baris, rekap, refresh, publish): revisi
    harus DRAFT dan article-nya masih aktif di specsheet terbit terakhir."""
    row = _get_cbd_revision(conn, cbd_revision_id)
    if row["status"] != "DRAFT":
        raise ValueError("Revisi CBD ini sudah diterbitkan dan tidak bisa diubah.")
    ensure_article_active_for_cbd(conn, row["article_id"])
    return row


def _component_groups(conn):
    return conn.execute("SELECT * FROM component_group").fetchall()


def _group_code_for(conn, component_id, local_component_no, groups):
    if component_id:
        comp = conn.execute("SELECT * FROM component WHERE id=?", (component_id,)).fetchone()
        group = conn.execute("SELECT * FROM component_group WHERE id=?", (comp["group_id"],)).fetchone()
        return group["code"]
    if local_component_no is not None:
        for g in groups:
            if g["range_start"] <= local_component_no <= g["range_end"]:
                return g["code"]
    raise ValueError("Tidak bisa menentukan kelompok komponen untuk baris ini.")


def component_no_sort_key(number):
    """Kunci urut baris menurut nomor komponen (master atau lokal); baris tanpa
    nomor di paling bawah. Dipakai grid BOM dan CBD supaya baris yang baru
    ditambahkan (mis. komponen 15) langsung masuk di antara 10 dan 20."""
    return (number is None, number if number is not None else 0)


def _identity_key(line):
    """Kunci pencocokan terakhir (setelah lineKey & originLineKey). Subkomponen
    dicocokkan lewat NAMA subkomponennya (bukan nomor urut `sub_seq`, yang bisa
    menunjuk hal berbeda antar specsheet/season) + material."""
    sub_name = normalize_text(line["sub_name"]) if line["sub_seq"] is not None else None
    return (line["component_id"], line["local_component_no"], sub_name, line["material_id"])


def _source_ref_label(conn, cbd_revision_id):
    row = conn.execute(
        """SELECT cr.stage, cr.revision_no, a.code AS article_code, sp.season
           FROM cbd_revision cr
           JOIN article a ON a.id = cr.article_id
           JOIN specsheet sp ON sp.id = a.specsheet_id
           WHERE cr.id=?""",
        (cbd_revision_id,),
    ).fetchone()
    if not row:
        return None
    return f"{row['season']} / {row['article_code']} / {row['stage']} r{row['revision_no']}"


def build_expected_lines(conn, article_id, specsheet_revision_id):
    """Langkah 1 (PRD 6.4): baris BOM aktif & dipakai article ini, dengan identitas
    (component/material/color/uom/supplier/groupCode) terisi. Tidak termasuk
    nilai biaya (yield/usage/harga/dst). Semua baris `isUsed` selalu ikut apa
    adanya (1:1) — tidak ada lagi tahap EXCLUDE/MERGE (Aturan Transformasi sudah
    dihapus, lihat catatan di atas).

    Article yang di-drop di revisi ini tidak mengharapkan baris apa pun — sel
    BOM-nya tetap `is_used` (drop tidak menghapus isi sel), jadi statusnya
    dicek eksplisit lewat revision_article."""
    rows = conn.execute(
        """SELECT bl.*, bc.color AS cell_color, bc.is_used AS cell_used, m.uom AS material_uom,
                  c.number AS component_number
           FROM bom_line bl
           LEFT JOIN bom_cell bc ON bc.bom_line_id = bl.id AND bc.article_id = ?
           LEFT JOIN component c ON c.id = bl.component_id
           JOIN material m ON m.id = bl.material_id
           WHERE bl.revision_id = ? AND bl.is_active = 1
           ORDER BY bl.sort_order""",
        (article_id, specsheet_revision_id),
    ).fetchall()
    article_active = conn.execute(
        "SELECT 1 FROM revision_article WHERE revision_id=? AND article_id=? AND status='ACTIVE'",
        (specsheet_revision_id, article_id),
    ).fetchone()
    if not article_active:
        return []

    # Induk dicari di SEMUA baris aktif (bukan hanya yang dipakai article ini) —
    # subkomponen boleh dipakai walau baris induknya kosong untuk colorway tsb.
    by_key = {r["line_key"]: r for r in rows}
    ordered = []
    children = {}
    for r in rows:
        if r["parent_line_key"]:
            children.setdefault(r["parent_line_key"], []).append(r)
    top_level = sorted(
        (r for r in rows if not r["parent_line_key"]),
        key=lambda r: (component_no_sort_key(r["component_number"] if r["component_number"] is not None
                                             else r["local_component_no"]), r["sort_order"]),
    )
    for parent in top_level:
        ordered.append(parent)
        ordered.extend(sorted(children.pop(parent["line_key"], []), key=lambda r: r["sub_seq"] or 0))
    for orphans in children.values():
        ordered.extend(orphans)
    rows = [r for r in ordered if r["cell_used"]]

    groups = _component_groups(conn)
    expected = []

    for row in rows:
        parent = by_key.get(row["parent_line_key"]) if row["parent_line_key"] else None
        display_component_id = (parent or row)["component_id"]
        display_local_no = (parent or row)["local_component_no"]

        expected.append({
            "line_key": row["line_key"],
            "component_id": display_component_id,
            "local_component_no": display_local_no,
            "sub_seq": row["sub_seq"],
            "sub_name": row["sub_name"],
            "material_id": row["material_id"],
            "color": row["cell_color"],
            "supplier_id": row["supplier_id"],
            "uom": row["material_uom"],
            "group_code": _group_code_for(conn, display_component_id, display_local_no, groups),
            "origin_line_key": row["origin_line_key"],
            "replaces_line_key": row["replaces_line_key"],
        })

    return expected


def _insert_cbd_line(conn, revision_id, sort_order, line_key, component_id, local_component_no,
                      sub_seq, sub_name, material_id, color, supplier_id, uom, yield_value, usage_value,
                      loss_pct, price, status, value_origin, value_source_ref, group_code):
    """`price` = dict hasil `_master_price` / `_carried_price` (price_original,
    currency, price_source, material_price_id, price_override_reason)."""
    cbd_line_id = new_id()
    conn.execute(
        """INSERT INTO cbd_line
           (id, cbd_revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
            material_id, color, supplier_id, uom, yield_value, usage_value, loss_pct,
            price_original, currency, price_source, material_price_id, price_override_reason,
            price_reference, status, value_origin, value_source_ref, group_code, sort_order)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (cbd_line_id, revision_id, line_key, component_id, local_component_no, sub_seq, sub_name,
         material_id, color, supplier_id, uom, yield_value, usage_value, loss_pct,
         price["price_original"], price["currency"], price["price_source"], price["material_price_id"],
         price["price_override_reason"], price["price_reference"], status, value_origin, value_source_ref,
         group_code, sort_order),
    )
    return cbd_line_id


_NO_PRICE = {"price_original": None, "currency": None, "price_source": None,
             "material_price_id": None, "price_override_reason": None, "price_reference": None}


def _master_price(conn, material_id, supplier_id, color):
    """Harga baris CBD dari master harga, atau kosong kalau master belum punya
    (material QUOTATION selalu kosong — harganya diisi per CBD)."""
    found = lookup_price(conn, material_id, supplier_id, color)
    if not found:
        return dict(_NO_PRICE)
    return {**_NO_PRICE, "price_original": found["price"], "currency": found["currency"],
            "price_source": "MASTER", "material_price_id": found["id"]}


def _carried_price(row):
    return {"price_original": row["price_original"], "currency": row["currency"],
            "price_source": row["price_source"], "material_price_id": row["material_price_id"],
            "price_override_reason": row["price_override_reason"], "price_reference": row["price_reference"]}


def _carries_price(conn, source_row):
    """Harga yang diinput di CBD (override material katalog / quotation material
    proses) ikut ter-copy dari baris sumber yang cocok — selama metode harga
    materialnya masih cocok dengan jenis harganya."""
    if source_row["price_source"] not in ("OVERRIDE", "QUOTATION"):
        return False
    quotation = is_quotation_material(conn, source_row["material_id"])
    return (source_row["price_source"] == "QUOTATION") == quotation


# ---------------- generate / merge (PRD 6.4) ----------------

def _populate_cbd_lines(conn, revision_id, expected_lines, source_by_key, source_by_identity,
                         source_ref_label, mark_missing):
    """Langkah 2-3 (PRD 6.4): cocokkan `expected_lines` (hasil `build_expected_lines`)
    ke baris sumber (by lineKey -> originLineKey -> identitas) untuk menyalin
    Yield/Loss%, lalu masukkan baris sumber yang tak lagi diharapkan sebagai
    MISSING_IN_SPEC bila `mark_missing`. Dipakai baik saat generate/merge CBD
    baru maupun saat refresh CBD DRAFT dari revisi specsheet terbaru.

    Harga master TIDAK disalin dari sumber: selalu diambil ulang dari master
    harga untuk material + supplier + warna specsheet tujuan. Harga yang diinput
    di CBD (override / quotation) di baris sumber yang cocok ikut ter-copy, lihat
    `_carries_price`."""
    matched_source_keys = set()
    sort_order = 0
    for line in expected_lines:
        match = source_by_key.get(line["line_key"])
        if match is None and line.get("origin_line_key"):
            match = source_by_key.get(line["origin_line_key"])
        if match is None:
            match = source_by_identity.get(_identity_key(line))

        # Langkah 1 defaults (identitas): supplier dari BOM, loss default 0.00.
        # Langkah 2 di bawah menimpa yield/loss dengan nilai sumber HANYA bila
        # ada baris yang cocok.
        yield_value = None
        loss_pct = to_text(Decimal("0.00"))
        value_origin = "INPUT"
        value_source_ref = None

        if match is not None:
            matched_source_keys.add(match["line_key"])
            yield_value = match["yield_value"]
            loss_pct = match["loss_pct"]
            value_origin = "COPIED"
            value_source_ref = source_ref_label
        elif line.get("replaces_line_key") and line["replaces_line_key"] in source_by_key:
            # PRD 6.4: baris pengganti hanya membawa Yield/Loss% — harganya
            # diambil dari master untuk material barunya, bukan dari baris lama.
            replaced = source_by_key[line["replaces_line_key"]]
            matched_source_keys.add(replaced["line_key"])
            yield_value = replaced["yield_value"]
            loss_pct = replaced["loss_pct"]
            value_origin = "CARRIED_FROM_REPLACED"

        if match is not None and _carries_price(conn, match):
            price = _carried_price(match)
        else:
            price = _master_price(conn, line["material_id"], line["supplier_id"], line["color"])

        usage_value = to_text(usage_from_yield(to_decimal(yield_value)))

        _insert_cbd_line(
            conn, revision_id, sort_order, line["line_key"], line["component_id"],
            line["local_component_no"], line["sub_seq"], line["sub_name"], line["material_id"], line["color"],
            line["supplier_id"], line["uom"], yield_value, usage_value, loss_pct, price,
            "ACTIVE", value_origin, value_source_ref, line["group_code"],
        )
        sort_order += 1

    # Langkah 3: baris sumber yang tidak lagi diharapkan -> MISSING_IN_SPEC
    # (tidak dihapus, status mengikuti specsheet — tidak ada aksi batalkan manual).
    if mark_missing:
        for key, src in source_by_key.items():
            if key in matched_source_keys:
                continue
            _insert_cbd_line(
                conn, revision_id, sort_order, src["line_key"], src["component_id"],
                src["local_component_no"], src["sub_seq"], src["sub_name"], src["material_id"], src["color"],
                src["supplier_id"], src["uom"], src["yield_value"], src["usage_value"],
                src["loss_pct"], _carried_price(src), "MISSING_IN_SPEC",
                src["value_origin"], src["value_source_ref"], src["group_code"],
            )
            sort_order += 1


def generate_or_merge_cbd(conn, article_id, stage, revision_no, specsheet_revision_id,
                           source_cbd_revision_id, exchange_rate, actor):
    """Satu algoritma untuk semua kasus pemakaian (lihat lima fungsi create_cbd_*
    di bawah). exchange_rate BOLEH kosong saat membuat revisi (revisi 2) — baru
    wajib diisi (>0) saat publish, lihat `publish_cbd_revision`."""
    ensure_article_active_for_cbd(conn, article_id)
    existing_draft = conn.execute(
        "SELECT id FROM cbd_revision WHERE article_id=? AND status='DRAFT'", (article_id,)
    ).fetchone()
    if existing_draft:
        raise ValueError("Sudah ada revisi CBD DRAFT untuk article ini. Selesaikan/terbitkan dulu.")

    source_revision = _get_cbd_revision(conn, source_cbd_revision_id) if source_cbd_revision_id else None

    # Rekap Biaya & Rekap Margin ikut ter-copy dari CBD sumber (tetap bisa
    # diedit di draft baru). Exchange rate yang diisi eksplisit menang atas rate
    # sumber. Actual FOB & Margin % tidak disimpan — selalu dihitung ulang.
    rate = to_decimal(exchange_rate)
    if rate is None and source_revision is not None:
        rate = to_decimal(source_revision["exchange_rate"])
    if rate is not None and rate <= 0:
        raise ValueError("Exchange rate harus lebih besar dari 0.")
    header = {"amortization": "0", "adjustment": "0", "target_fob": None, "selling_price": None}
    if source_revision is not None:
        header = {k: source_revision[k] for k in header}

    expected_lines = build_expected_lines(conn, article_id, specsheet_revision_id)

    source_by_key = {}
    source_by_identity = {}
    same_article = False
    if source_revision is not None:
        same_article = source_revision["article_id"] == article_id
        source_rows = conn.execute(
            "SELECT * FROM cbd_line WHERE cbd_revision_id=?", (source_cbd_revision_id,)
        ).fetchall()
        for r in source_rows:
            source_by_key[r["line_key"]] = r
            source_by_identity[_identity_key(r)] = r

    source_ref_label = _source_ref_label(conn, source_cbd_revision_id) if source_cbd_revision_id else None

    revision_id = new_id()
    conn.execute(
        """INSERT INTO cbd_revision
           (id, article_id, stage, revision_no, specsheet_revision_id, exchange_rate,
            amortization, adjustment, target_fob, selling_price,
            status, sync_status, source_cbd_revision_id)
           VALUES (?,?,?,?,?,?,?,?,?,?,'DRAFT','IN_SYNC',?)""",
        (revision_id, article_id, stage, revision_no, specsheet_revision_id,
         to_text(rate), header["amortization"], header["adjustment"], header["target_fob"],
         header["selling_price"], source_cbd_revision_id),
    )

    # Baris sumber yang tak terpakai hanya jadi MISSING_IN_SPEC untuk revisi
    # lanjutan article yang SAMA. Copy dari article lain mengabaikannya: baris
    # itu memang tidak pernah ada di specsheet article tujuan.
    _populate_cbd_lines(conn, revision_id, expected_lines, source_by_key, source_by_identity,
                         source_ref_label, mark_missing=same_article)

    write_audit_log(conn, actor, "CbdRevision", revision_id, "CREATE", None,
                     {"articleId": article_id, "stage": stage, "revisionNo": revision_no,
                      "sourceCbdRevisionId": source_cbd_revision_id})
    conn.commit()
    return revision_id


def refresh_cbd_draft(conn, cbd_revision_id, actor):
    """Regenerasi baris CBD DRAFT ini dari revisi specsheet terbit TERKINI, memakai
    baris CBD yang sudah ada sekarang sebagai sumber (yield/harga yang sudah diisi
    tidak hilang, dicocokkan seperti biasa: lineKey -> originLineKey -> identitas).

    Dipakai saat specsheet acuan CBD ini diterbitkan revisi baru SEMENTARA CBD
    masih DRAFT — publish_cbd_revision menolak terbit sampai di-refresh (lihat di
    sana), karena baris CBD DRAFT tidak pernah otomatis mengikuti perubahan
    specsheet (lihat catatan `mark_cbd_sync_status`, yang hanya menandai CBD
    berstatus PUBLISHED)."""
    revision = ensure_cbd_draft(conn, cbd_revision_id)
    article = get_article(conn, revision["article_id"])
    latest = latest_published_specsheet_revision(conn, article["specsheet_id"])
    if not latest:
        raise ValueError("Specsheet belum punya revisi terbit.")
    if latest["id"] == revision["specsheet_revision_id"]:
        raise ValueError("CBD ini sudah sinkron dengan specsheet terbaru.")

    expected_lines = build_expected_lines(conn, revision["article_id"], latest["id"])

    old_rows = conn.execute(
        "SELECT * FROM cbd_line WHERE cbd_revision_id=?", (cbd_revision_id,)
    ).fetchall()
    source_by_key = {r["line_key"]: r for r in old_rows}
    source_by_identity = {_identity_key(r): r for r in old_rows}

    conn.execute("DELETE FROM cbd_line WHERE cbd_revision_id=?", (cbd_revision_id,))

    _populate_cbd_lines(conn, cbd_revision_id, expected_lines, source_by_key, source_by_identity,
                         "revisi CBD ini sebelum di-refresh", mark_missing=True)

    conn.execute(
        "UPDATE cbd_revision SET specsheet_revision_id=?, stage=? WHERE id=?",
        (latest["id"], latest["stage"], cbd_revision_id),
    )
    write_audit_log(conn, actor, "CbdRevision", cbd_revision_id, "REFRESH_FROM_SPECSHEET",
                     {"specsheetRevisionId": revision["specsheet_revision_id"]},
                     {"specsheetRevisionId": latest["id"]})
    conn.commit()
    return cbd_revision_id


def delete_cbd_draft(conn, cbd_revision_id, actor):
    """Hapus revisi CBD DRAFT beserta barisnya seakan belum pernah dibuat —
    mis. terlanjur "Buat CBD" padahal mau copy dari article lain. Revisi terbit
    tidak bisa dihapus. Boleh juga untuk article yang sudah di-drop (draft-nya
    memang tidak bisa diteruskan lagi)."""
    revision = _get_cbd_revision(conn, cbd_revision_id)
    if revision["status"] != "DRAFT":
        raise ValueError("Revisi CBD ini sudah diterbitkan dan tidak bisa dihapus.")
    conn.execute("UPDATE cbd_revision SET source_cbd_revision_id=NULL WHERE source_cbd_revision_id=?",
                 (cbd_revision_id,))
    conn.execute("DELETE FROM cbd_line WHERE cbd_revision_id=?", (cbd_revision_id,))
    conn.execute("DELETE FROM change_log WHERE revision_id=? AND doc_type='CBD'", (cbd_revision_id,))
    conn.execute("DELETE FROM cbd_revision WHERE id=?", (cbd_revision_id,))
    write_audit_log(conn, actor, "CbdRevision", cbd_revision_id, "DELETE_DRAFT",
                     {"articleId": revision["article_id"], "stage": revision["stage"],
                      "revisionNo": revision["revision_no"]}, None)
    conn.commit()


def cbd_draft_is_stale(conn, revision):
    """True kalau `revision` (row cbd_revision berstatus DRAFT) mengacu ke revisi
    specsheet yang bukan revisi terbit terkini lagi — dipakai untuk menampilkan
    peringatan/tombol refresh di UI sebelum publish_cbd_revision menolaknya."""
    if revision["status"] != "DRAFT":
        return False
    article = get_article(conn, revision["article_id"])
    latest = latest_published_specsheet_revision(conn, article["specsheet_id"])
    return bool(latest) and latest["id"] != revision["specsheet_revision_id"]


def create_cbd_no_source(conn, article_id, exchange_rate, actor):
    """CBD pertama article, tanpa sumber."""
    article = get_article(conn, article_id)
    revision = latest_published_specsheet_revision(conn, article["specsheet_id"])
    if not revision:
        raise ValueError("Specsheet belum punya revisi terbit.")
    return generate_or_merge_cbd(conn, article_id, revision["stage"], 0, revision["id"], None, exchange_rate, actor)


def create_cbd_from_article(conn, article_id, source_article_id, exchange_rate, actor):
    """Copy dari article lain (model & season sama)."""
    article = get_article(conn, article_id)
    revision = latest_published_specsheet_revision(conn, article["specsheet_id"])
    if not revision:
        raise ValueError("Specsheet belum punya revisi terbit.")
    source = latest_published_cbd(conn, source_article_id)
    if not source:
        raise ValueError("Article sumber belum punya revisi CBD terbit.")
    return generate_or_merge_cbd(conn, article_id, revision["stage"], 0, revision["id"], source["id"], exchange_rate, actor)


def create_cbd_from_season(conn, article_id, source_cbd_revision_id, exchange_rate, actor):
    """Copy dari season lalu — sumber dipilih user dari CBD article manapun."""
    article = get_article(conn, article_id)
    revision = latest_published_specsheet_revision(conn, article["specsheet_id"])
    if not revision:
        raise ValueError("Specsheet belum punya revisi terbit.")
    source = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (source_cbd_revision_id,)).fetchone()
    if not source or source["status"] != "PUBLISHED":
        raise ValueError("Revisi CBD sumber harus revisi yang sudah terbit.")
    return generate_or_merge_cbd(conn, article_id, revision["stage"], 0, revision["id"], source["id"], exchange_rate, actor)


def create_cbd_same_stage(conn, article_id, actor, exchange_rate=None):
    """Revisi baru di stage yang sama."""
    latest = latest_published_cbd(conn, article_id)
    if not latest:
        raise ValueError("Belum ada revisi CBD terbit untuk article ini.")
    article = get_article(conn, article_id)
    revision = latest_published_specsheet_revision(conn, article["specsheet_id"])
    if not revision:
        raise ValueError("Specsheet belum punya revisi terbit.")
    rate = exchange_rate if exchange_rate is not None else latest["exchange_rate"]
    return generate_or_merge_cbd(conn, article_id, latest["stage"], latest["revision_no"] + 1,
                                  revision["id"], latest["id"], rate, actor)


def create_cbd_next_stage(conn, article_id, actor, exchange_rate=None):
    """Stage berikutnya."""
    latest = latest_published_cbd(conn, article_id)
    if not latest:
        raise ValueError("Belum ada revisi CBD terbit untuk article ini.")
    current_idx = STAGES.index(latest["stage"])
    if current_idx >= len(STAGES) - 1:
        raise ValueError("Sudah berada di stage terakhir (PROD).")
    next_stage = STAGES[current_idx + 1]
    article = get_article(conn, article_id)
    revision = latest_published_specsheet_revision(conn, article["specsheet_id"])
    if not revision:
        raise ValueError("Specsheet belum punya revisi terbit.")
    rate = exchange_rate if exchange_rate is not None else latest["exchange_rate"]
    return generate_or_merge_cbd(conn, article_id, next_stage, 0, revision["id"], latest["id"], rate, actor)


# ---------------- editing ----------------

def _update_line_decimal_field(conn, line_id, column, value, actor):
    line = conn.execute("SELECT * FROM cbd_line WHERE id=?", (line_id,)).fetchone()
    if not line:
        raise ValueError("Baris CBD tidak ditemukan.")
    ensure_cbd_draft(conn, line["cbd_revision_id"])
    parsed = to_decimal((value or "").strip())
    conn.execute(f"UPDATE cbd_line SET {column}=?, value_origin='INPUT' WHERE id=?",
                 (to_text(parsed), line_id))
    write_audit_log(conn, actor, "CbdLine", line_id, "UPDATE_VALUE",
                     {column: line[column]}, {column: to_text(parsed)})
    conn.commit()


def update_yield(conn, line_id, value, actor):
    """Usage tidak diinput terpisah — selalu diturunkan ulang dari Yield (1/Yield)."""
    line = conn.execute("SELECT * FROM cbd_line WHERE id=?", (line_id,)).fetchone()
    if not line:
        raise ValueError("Baris CBD tidak ditemukan.")
    ensure_cbd_draft(conn, line["cbd_revision_id"])
    parsed = to_decimal((value or "").strip())
    usage = usage_from_yield(parsed)
    conn.execute(
        "UPDATE cbd_line SET yield_value=?, usage_value=?, value_origin='INPUT' WHERE id=?",
        (to_text(parsed), to_text(usage), line_id),
    )
    write_audit_log(conn, actor, "CbdLine", line_id, "UPDATE_VALUE",
                     {"yield_value": line["yield_value"]}, {"yield_value": to_text(parsed)})
    conn.commit()


def update_loss_pct(conn, line_id, value, actor):
    _update_line_decimal_field(conn, line_id, "loss_pct", value, actor)


def _get_active_draft_line(conn, line_id):
    line = conn.execute("SELECT * FROM cbd_line WHERE id=?", (line_id,)).fetchone()
    if not line:
        raise ValueError("Baris CBD tidak ditemukan.")
    ensure_cbd_draft(conn, line["cbd_revision_id"])
    if line["status"] != "ACTIVE":
        raise ValueError("Baris yang sudah hilang dari specsheet tidak bisa diubah harganya.")
    return line


def _set_line_price(conn, line_id, price):
    conn.execute(
        """UPDATE cbd_line SET price_original=?, currency=?, price_source=?, material_price_id=?,
           price_override_reason=?, price_reference=? WHERE id=?""",
        (price["price_original"], price["currency"], price["price_source"], price["material_price_id"],
         price["price_override_reason"], price["price_reference"], line_id),
    )


def set_quotation_price(conn, line_id, price_original, currency, reference, actor):
    """Harga material proses (metode QUOTATION) diisi langsung di baris CBD,
    tanpa alasan — memang tidak ada harga master untuknya. Harga kosong =
    baris ini tidak dihargai terpisah (mis. sudah diwakili baris proses lain)."""
    line = _get_active_draft_line(conn, line_id)
    if not is_quotation_material(conn, line["material_id"]):
        raise ValueError("Harga quotation hanya untuk material dengan metode harga Quotation. "
                         "Untuk material katalog, harganya dari Master Material (atau override).")
    parsed = parse_decimal(price_original, "Harga")
    reference = (reference or "").strip() or None
    if parsed is None:
        price = dict(_NO_PRICE)
    else:
        if parsed <= 0:
            raise ValueError("Harga quotation harus lebih besar dari 0 (kosongkan kalau tidak dihargai).")
        if currency not in ("IDR", "USD"):
            raise ValueError("Currency harus IDR atau USD.")
        price = {**_NO_PRICE, "price_original": to_text(parsed), "currency": currency,
                 "price_source": "QUOTATION", "price_reference": reference}
    _set_line_price(conn, line_id, price)
    write_audit_log(conn, actor, "CbdLine", line_id, "SET_QUOTATION_PRICE",
                     {"priceOriginal": line["price_original"], "currency": line["currency"],
                      "reference": line["price_reference"]},
                     {"priceOriginal": price["price_original"], "currency": price["currency"],
                      "reference": price["price_reference"]})
    conn.commit()


def override_price(conn, line_id, price_original, currency, reason, actor):
    """Harga khusus untuk baris CBD ini saja (mis. harga nego sekali pakai),
    menggantikan harga master. Alasan wajib. Harga yang berlaku untuk semua CBD
    — termasuk harga khusus warna — BUKAN override: harus diisi di Master
    Material. Hanya untuk material katalog; material proses memakai
    `set_quotation_price`."""
    line = _get_active_draft_line(conn, line_id)
    if is_quotation_material(conn, line["material_id"]):
        raise ValueError("Material ini memakai metode harga Quotation — isi harganya langsung, tanpa override.")
    reason = (reason or "").strip()
    if not reason:
        raise ValueError("Alasan override harga wajib diisi.")
    parsed = parse_decimal(price_original, "Harga")
    if parsed is None or parsed <= 0:
        raise ValueError("Harga override harus diisi dan lebih besar dari 0.")
    if currency not in ("IDR", "USD"):
        raise ValueError("Currency harus IDR atau USD.")
    price = {**_NO_PRICE, "price_original": to_text(parsed), "currency": currency, "price_source": "OVERRIDE",
             "price_override_reason": reason}
    _set_line_price(conn, line_id, price)
    write_audit_log(conn, actor, "CbdLine", line_id, "OVERRIDE_PRICE",
                     {"priceOriginal": line["price_original"], "currency": line["currency"],
                      "priceSource": line["price_source"]},
                     {"priceOriginal": price["price_original"], "currency": currency, "reason": reason})
    conn.commit()


def clear_price_override(conn, line_id, actor):
    """Hapus override: baris kembali memakai harga master yang berlaku."""
    line = _get_active_draft_line(conn, line_id)
    if line["price_source"] != "OVERRIDE":
        raise ValueError("Baris ini tidak memakai override harga.")
    price = _master_price(conn, line["material_id"], line["supplier_id"], line["color"])
    _set_line_price(conn, line_id, price)
    write_audit_log(conn, actor, "CbdLine", line_id, "CLEAR_PRICE_OVERRIDE",
                     {"priceOriginal": line["price_original"], "currency": line["currency"],
                      "reason": line["price_override_reason"]},
                     {"priceOriginal": price["price_original"], "currency": price["currency"]})
    conn.commit()


def stale_master_price_lines(conn, cbd_revision_id):
    """Baris ACTIVE (bukan override) yang harga master-nya sekarang berbeda dari
    yang tersimpan: harga baru tersedia untuk baris yang tadinya kosong, harga
    master diganti/diakhiri, atau harga khusus warna ditambahkan. Dipakai untuk
    banner "Refresh Harga dari Master" dan untuk menahan publish."""
    rows = conn.execute(
        """SELECT * FROM cbd_line WHERE cbd_revision_id=? AND status='ACTIVE'
           AND (price_source IS NULL OR price_source='MASTER')""",
        (cbd_revision_id,),
    ).fetchall()
    stale = []
    for row in rows:
        current = lookup_price(conn, row["material_id"], row["supplier_id"], row["color"])
        if (current["id"] if current else None) != row["material_price_id"]:
            stale.append({"line": row, "current": current})
    return stale


def refresh_cbd_prices(conn, cbd_revision_id, actor):
    """Samakan harga baris non-override CBD DRAFT ini dengan master harga yang
    berlaku sekarang. Override tidak disentuh. Mengembalikan jumlah baris yang
    berubah."""
    ensure_cbd_draft(conn, cbd_revision_id)
    stale = stale_master_price_lines(conn, cbd_revision_id)
    for entry in stale:
        line = entry["line"]
        price = _master_price(conn, line["material_id"], line["supplier_id"], line["color"])
        _set_line_price(conn, line["id"], price)
        write_audit_log(conn, actor, "CbdLine", line["id"], "REFRESH_PRICE_FROM_MASTER",
                         {"priceOriginal": line["price_original"], "currency": line["currency"]},
                         {"priceOriginal": price["price_original"], "currency": price["currency"]})
    conn.commit()
    return len(stale)


def _update_revision_decimal_field(conn, cbd_revision_id, column, value, actor, allow_none=True,
                                    require_draft=True):
    revision = ensure_cbd_draft(conn, cbd_revision_id) if require_draft else _get_cbd_revision(conn, cbd_revision_id)
    parsed = to_decimal((value or "").strip())
    if parsed is None and not allow_none:
        raise ValueError("Nilai wajib diisi.")
    if column == "exchange_rate" and parsed is not None and parsed <= 0:
        raise ValueError("Exchange rate harus lebih besar dari 0.")
    conn.execute(f"UPDATE cbd_revision SET {column}=? WHERE id=?", (to_text(parsed), cbd_revision_id))
    write_audit_log(conn, actor, "CbdRevision", cbd_revision_id, "UPDATE_FIELD",
                     {column: revision[column]}, {column: to_text(parsed)})
    conn.commit()


def update_exchange_rate(conn, cbd_revision_id, value, actor):
    _update_revision_decimal_field(conn, cbd_revision_id, "exchange_rate", value, actor, allow_none=False)


def update_amortization(conn, cbd_revision_id, value, actor):
    _update_revision_decimal_field(conn, cbd_revision_id, "amortization", value, actor)


def update_adjustment(conn, cbd_revision_id, value, actor):
    _update_revision_decimal_field(conn, cbd_revision_id, "adjustment", value, actor)


def update_selling_price(conn, cbd_revision_id, value, actor):
    """Selling Price (dan Margin % di `update_margin_pct`) tetap bisa diedit
    setelah CBD terbit — harga jual bisa terus disesuaikan pasca-publish, beda
    dari field Rekap Biaya lain & baris CBD yang terkunci begitu PUBLISHED."""
    _update_revision_decimal_field(conn, cbd_revision_id, "selling_price", value, actor,
                                    require_draft=False)


def update_target_fob(conn, cbd_revision_id, value, actor):
    _update_revision_decimal_field(conn, cbd_revision_id, "target_fob", value, actor)


def _compute_actual_fob(conn, cbd_revision_id):
    """Actual FOB = Material Cost (Rupiah) + Amortisasi + Adjustment — dipakai
    ulang oleh `update_margin_pct` untuk menyelesaikan Selling Price dari Margin %."""
    revision = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (cbd_revision_id,)).fetchone()
    exchange_rate = to_decimal(revision["exchange_rate"])
    rows = conn.execute(
        "SELECT status, usage_value, price_original, currency, loss_pct FROM cbd_line WHERE cbd_revision_id=?",
        (cbd_revision_id,),
    ).fetchall()
    calc_lines = [
        {"status": r["status"], "usage": to_decimal(r["usage_value"]),
         "price_original": to_decimal(r["price_original"]), "currency": r["currency"],
         "loss_pct": to_decimal(r["loss_pct"])}
        for r in rows
    ]
    mat_cost = material_cost_idr(calc_lines, exchange_rate)
    amortization = to_decimal(revision["amortization"])
    adjustment = to_decimal(revision["adjustment"])
    return total_cost(mat_cost, amortization, adjustment)


def update_margin_pct(conn, cbd_revision_id, value, actor):
    """Margin % dan Selling Price saling terhubung dua arah (revisi 4): mengedit
    Margin % di sini menyelesaikan ulang Selling Price agar margin-nya sesuai
    (terhadap Actual FOB saat ini), lalu menyimpannya ke kolom `selling_price`
    yang sama dipakai `update_selling_price`. Sengaja tidak mensyaratkan DRAFT
    (lihat `update_selling_price`) — tetap bisa diedit setelah CBD terbit."""
    revision = _get_cbd_revision(conn, cbd_revision_id)
    margin = to_decimal((value or "").strip())
    if margin is None:
        conn.execute("UPDATE cbd_revision SET selling_price=NULL WHERE id=?", (cbd_revision_id,))
        write_audit_log(conn, actor, "CbdRevision", cbd_revision_id, "UPDATE_FIELD",
                         {"sellingPrice": revision["selling_price"]}, {"sellingPrice": None})
        conn.commit()
        return
    cost = _compute_actual_fob(conn, cbd_revision_id)
    selling_price = selling_price_from_margin(cost, margin)
    conn.execute("UPDATE cbd_revision SET selling_price=? WHERE id=?",
                 (to_text(selling_price), cbd_revision_id))
    write_audit_log(conn, actor, "CbdRevision", cbd_revision_id, "UPDATE_FIELD",
                     {"sellingPrice": revision["selling_price"]}, {"sellingPrice": to_text(selling_price)})
    conn.commit()


# ---------------- publish (PRD 6.5) ----------------

def publish_cbd_revision(conn, cbd_revision_id, category, reason, actor):
    revision = ensure_cbd_draft(conn, cbd_revision_id)

    article = get_article(conn, revision["article_id"])
    latest_specsheet = latest_published_specsheet_revision(conn, article["specsheet_id"])
    if latest_specsheet and latest_specsheet["id"] != revision["specsheet_revision_id"]:
        raise ValueError(
            "Specsheet acuan CBD ini sudah diterbitkan revisi baru. "
            "Refresh CBD ini dari specsheet terbaru dulu sebelum diterbitkan."
        )

    rate = to_decimal(revision["exchange_rate"])
    if rate is None or rate <= 0:
        raise ValueError("Exchange rate harus lebih besar dari 0.")

    # Harga master adalah snapshot saat CBD dibuat/di-refresh — kalau master
    # sudah berubah sejak itu, CBD tidak boleh terbit dengan harga usang tanpa
    # disadari (sama seperti aturan specsheet usang di atas).
    stale_prices = stale_master_price_lines(conn, cbd_revision_id)
    if stale_prices:
        raise ValueError(
            f"Harga master untuk {len(stale_prices)} baris sudah berubah sejak CBD ini dibuat. "
            "Klik 'Refresh Harga dari Master' dulu sebelum diterbitkan."
        )

    # Baris tanpa harga BOLEH diterbitkan (mis. proses yang harganya sudah
    # termasuk di baris lain, atau barang FOC) — cost-nya dihitung 0. Yang wajib
    # hanya: baris yang berharga harus punya yield, supaya cost/pair-nya terhitung.
    active_lines = conn.execute(
        "SELECT * FROM cbd_line WHERE cbd_revision_id=? AND status='ACTIVE'", (cbd_revision_id,)
    ).fetchall()
    incomplete = [l for l in active_lines if l["price_original"] and not l["yield_value"]]
    if incomplete:
        raise ValueError(
            f"Ada {len(incomplete)} baris berharga yang belum lengkap (yield belum diisi)."
        )

    requires_reason = revision["source_cbd_revision_id"] is not None or revision["revision_no"] != 0
    reason = (reason or "").strip()
    if requires_reason and not reason:
        raise ValueError("Alasan perubahan (change log) wajib diisi untuk revisi ini.")
    if category not in CHANGE_CATEGORIES:
        raise ValueError("Kategori change log tidak valid.")

    diff = {}
    if revision["source_cbd_revision_id"]:
        diff = compute_cbd_diff(conn, revision["source_cbd_revision_id"], cbd_revision_id)

    conn.execute(
        "UPDATE cbd_revision SET status='PUBLISHED', published_at=datetime('now'), published_by=? WHERE id=?",
        (actor, cbd_revision_id),
    )
    change_log_id = new_id()
    conn.execute(
        """INSERT INTO change_log (id, doc_type, revision_id, category, reason, diff_json, created_by)
           VALUES (?,?,?,?,?,?,?)""",
        (change_log_id, "CBD", cbd_revision_id, category, reason or "Revisi awal.", json.dumps(diff), actor),
    )
    write_audit_log(conn, actor, "CbdRevision", cbd_revision_id, "PUBLISH",
                     {"status": "DRAFT"}, {"status": "PUBLISHED", "changeLogId": change_log_id})
    conn.commit()
    return diff


def get_cbd_change_log(conn, cbd_revision_id):
    return conn.execute(
        "SELECT * FROM change_log WHERE revision_id=? AND doc_type='CBD' ORDER BY created_at DESC",
        (cbd_revision_id,),
    ).fetchall()


def list_cbd_revisions(conn, article_id):
    return conn.execute(
        "SELECT * FROM cbd_revision WHERE article_id=? ORDER BY stage, revision_no", (article_id,)
    ).fetchall()


def find_cbd_copy_sources(conn, model_id, exclude_article_id=None):
    """Article manapun (season apa pun) di Model yang sama dengan minimal satu revisi
    CBD terbit — dipakai wizard 'Copy dari Article Lain' (PRD 6.4 usage table baris
    2 & 3 digabung jadi satu aksi UI: keduanya sama-sama 'ambil CBD terbit terakhir
    article yang dipilih user', beda hanya article itu di season sama atau season
    lalu — dibedakan lewat kolom season yang ditampilkan, bukan lewat aksi terpisah).

    Article yang sudah di-drop tetap boleh jadi SUMBER copy (CBD terbitnya masih
    data valid, mis. colorway yang mirip) — ditandai `dropped` supaya jelas di UI.

    Yang di-copy selalu revisi CBD TERBIT terakhir article sumber (stage & revisi
    tertinggi, lihat `latest_published_cbd`) — disertakan sebagai `source_stage`
    / `source_revision_no` supaya label pilihannya menyebut revisi mana."""
    rows = conn.execute(
        """SELECT a.*, sp.season AS specsheet_season
           FROM article a
           JOIN specsheet sp ON sp.id = a.specsheet_id
           WHERE sp.model_id=?
             AND EXISTS (SELECT 1 FROM cbd_revision cr WHERE cr.article_id = a.id AND cr.status='PUBLISHED')""",
        (model_id,),
    ).fetchall()
    sources = []
    for r in rows:
        if r["id"] == exclude_article_id:
            continue
        latest = latest_published_cbd(conn, r["id"])
        sources.append({**dict(r), "dropped": article_cbd_status(conn, r["id"]) == "DROPPED",
                        "source_stage": latest["stage"], "source_revision_no": latest["revision_no"]})
    return sorted(sources, key=lambda r: (r["specsheet_season"], r["code"]))


def compute_display_fields(row: dict) -> None:
    """Isi `row['display_no']` & `row['display_name']` in-place dari kolom hasil
    join `list_cbd_lines` (component_number, master_component_name,
    local_component_no, sub_seq, sub_name, material_name). Baris subkomponen
    (`sub_seq` terisi) menampilkan "{no induk}-{urutan}" dan nama subkomponennya
    sendiri (`sub_name`) — meniru konvensi tampilan yang sama dengan grid BOM
    specsheet (`bom_service._enrich_line`), bukan mengulang nama komponen induk
    untuk semua baris turunannya."""
    base_no = row["component_number"] if row["component_number"] is not None else row["local_component_no"]
    if row.get("sub_seq") is not None:
        row["display_no"] = f"{base_no}-{row['sub_seq']}" if base_no is not None else str(row["sub_seq"])
        row["display_name"] = row.get("sub_name") or row["material_name"]
    else:
        # String (bukan int) supaya konsisten & tetap bisa dibandingkan/di-sort
        # bersama baris subkomponen di atas (mis. laporan validasi CBD).
        row["display_no"] = str(base_no) if base_no is not None else None
        row["display_name"] = row["master_component_name"] or (
            f"Lokal {row['local_component_no']}" if row["local_component_no"] is not None else None
        ) or row["material_name"]


def list_cbd_lines(conn, cbd_revision_id):
    """Thickness (`material_thickness`) dan Remarks (`remarks`) tidak disimpan di
    cbd_line — selalu dibaca live: thickness dari Master Material, remarks dari
    baris BOM (lineKey sama) di revisi specsheet acuan CBD ini. Keduanya murni
    informasi, tidak memengaruhi harga/cost.

    Urutan baris mengikuti nomor komponen (lihat `component_no_sort_key`), bukan urutan
    penyimpanan, supaya CBD lama pun ikut rapi."""
    rows = conn.execute(
        """SELECT cl.*, c.name AS master_component_name, c.number AS component_number,
                  m.name AS material_name, m.thickness AS material_thickness,
                  m.price_method AS material_price_method, s.name AS supplier_name,
                  mp.color AS master_price_color, mp.valid_from AS master_price_valid_from,
                  bl.process AS remarks
           FROM cbd_line cl
           JOIN cbd_revision cr ON cr.id = cl.cbd_revision_id
           LEFT JOIN component c ON c.id = cl.component_id
           JOIN material m ON m.id = cl.material_id
           LEFT JOIN supplier s ON s.id = cl.supplier_id
           LEFT JOIN material_price mp ON mp.id = cl.material_price_id
           LEFT JOIN bom_line bl ON bl.revision_id = cr.specsheet_revision_id AND bl.line_key = cl.line_key
           WHERE cl.cbd_revision_id=?
           ORDER BY cl.sort_order""",
        (cbd_revision_id,),
    ).fetchall()
    return sorted(rows, key=lambda r: (
        component_no_sort_key(r["component_number"] if r["component_number"] is not None
                              else r["local_component_no"]),
        r["sort_order"],
    ))


# ---------------- sync marking (PRD 6.6) ----------------

def _sync_signature(conn, article_id, specsheet_revision_id):
    """lineKey baris yang diharapkan, plus supplier & warnanya: keduanya ikut
    menentukan harga master sebuah baris CBD, jadi perubahan supplier/warna di
    specsheet juga membuat CBD perlu direvisi walau lineKey-nya tetap sama
    (ganti supplier bukan "Ganti Material")."""
    return {
        (l["line_key"], l["supplier_id"], normalize_text(l["color"]))
        for l in build_expected_lines(conn, article_id, specsheet_revision_id)
    }


def mark_cbd_sync_status(conn, specsheet_id, old_specsheet_revision_id, new_specsheet_revision_id, actor):
    """Dipanggil setelah sebuah revisi specsheet diterbitkan (lihat pemanggilan di
    revision_service.publish_revision). Tidak melakukan apa-apa untuk revisi
    pertama sebuah specsheet (tidak ada 'yang lama' untuk dibandingkan)."""
    if not old_specsheet_revision_id:
        return
    active_article_ids = [
        r["article_id"] for r in conn.execute(
            "SELECT article_id FROM revision_article WHERE revision_id=? AND status='ACTIVE'",
            (new_specsheet_revision_id,),
        ).fetchall()
    ]
    for article_id in active_article_ids:
        latest_cbd = latest_published_cbd(conn, article_id)
        if not latest_cbd:
            continue
        old_signature = _sync_signature(conn, article_id, old_specsheet_revision_id)
        new_signature = _sync_signature(conn, article_id, new_specsheet_revision_id)
        before_status = latest_cbd["sync_status"]
        if old_signature != new_signature:
            conn.execute("UPDATE cbd_revision SET sync_status='NEEDS_REVISION' WHERE id=?", (latest_cbd["id"],))
            after_status = "NEEDS_REVISION"
        else:
            conn.execute(
                "UPDATE cbd_revision SET specsheet_revision_id=?, sync_status='IN_SYNC' WHERE id=?",
                (new_specsheet_revision_id, latest_cbd["id"]),
            )
            after_status = "IN_SYNC"
        if before_status != after_status:
            write_audit_log(conn, actor, "CbdRevision", latest_cbd["id"], "SYNC_STATUS_CHANGE",
                             {"syncStatus": before_status}, {"syncStatus": after_status})
    conn.commit()
