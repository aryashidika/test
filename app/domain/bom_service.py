import re

from ..ids import new_id
from ..normalize import normalize_text
from .audit import write_audit_log
from .cbd_service import component_no_sort_key
from .material_price_service import ensure_material_supplier
from .revision_service import ensure_draft

NONE_VALUES = {"", "none", "-", "n/a", "na"}

# Pemisah label material di input ketik BOM: "<kode> · <nama>".
MATERIAL_LABEL_SEP = " · "


def _is_used_value(value):
    return bool(value) and value.strip().lower() not in NONE_VALUES


def _active_article_ids(conn, revision_id: str):
    rows = conn.execute(
        "SELECT article_id FROM revision_article WHERE revision_id=? AND status='ACTIVE'", (revision_id,)
    ).fetchall()
    return [r["article_id"] for r in rows]


def _next_sort_order(conn, revision_id: str) -> int:
    row = conn.execute("SELECT MAX(sort_order) m FROM bom_line WHERE revision_id=?", (revision_id,)).fetchone()
    return (row["m"] or 0) + 1


def _create_cells(conn, line_id: str, revision_id: str) -> None:
    for article_id in _active_article_ids(conn, revision_id):
        conn.execute(
            "INSERT OR IGNORE INTO bom_cell (bom_line_id, article_id, is_used) VALUES (?,?,0)",
            (line_id, article_id),
        )


def _check_duplicate_tuple(conn, revision_id, component_id, local_component_no, material_id) -> bool:
    row = conn.execute(
        """SELECT id FROM bom_line WHERE revision_id=? AND is_active=1 AND material_id=?
           AND IFNULL(component_id,'')=? AND IFNULL(local_component_no,-1)=? AND sub_seq IS NULL""",
        (revision_id, material_id, component_id or "", local_component_no if local_component_no is not None else -1),
    ).fetchone()
    return row is not None


def add_component_line(conn, revision_id: str, component_id: str, material_id: str,
                        process: str, actor: str, supplier_id: str = None) -> str:
    ensure_draft(conn, revision_id)
    component = conn.execute("SELECT * FROM component WHERE id=?", (component_id,)).fetchone()
    if not component:
        raise ValueError("Komponen tidak ditemukan.")
    material = conn.execute("SELECT * FROM material WHERE id=?", (material_id,)).fetchone()
    if not material:
        raise ValueError("Material tidak ditemukan.")
    if _check_duplicate_tuple(conn, revision_id, component_id, None, material_id):
        raise ValueError("Kombinasi komponen + material ini sudah ada pada revisi ini.")
    if supplier_id:
        ensure_material_supplier(conn, material_id, supplier_id, actor)

    line_id = new_id()
    line_key = new_id()
    conn.execute(
        """INSERT INTO bom_line (id, revision_id, line_key, component_id, material_id, supplier_id,
           process, is_active, sort_order) VALUES (?,?,?,?,?,?,?,1,?)""",
        (line_id, revision_id, line_key, component_id, material_id, supplier_id,
         (process or "").strip() or None, _next_sort_order(conn, revision_id)),
    )
    _create_cells(conn, line_id, revision_id)
    write_audit_log(conn, actor, "BomLine", line_id, "CREATE", None,
                     {"componentId": component_id, "materialId": material_id, "supplierId": supplier_id})
    conn.commit()
    return line_id


def add_local_component_line(conn, revision_id: str, local_no: int, local_name: str,
                              material_id: str, process: str, actor: str, supplier_id: str = None) -> str:
    ensure_draft(conn, revision_id)
    if local_no % 10 == 0:
        raise ValueError("Nomor komponen lokal tidak boleh kelipatan 10.")
    local_name = (local_name or "").strip()
    if not local_name:
        raise ValueError("Nama komponen lokal wajib diisi.")
    material = conn.execute("SELECT * FROM material WHERE id=?", (material_id,)).fetchone()
    if not material:
        raise ValueError("Material tidak ditemukan.")

    exists = conn.execute(
        "SELECT id FROM bom_line WHERE revision_id=? AND is_active=1 AND local_component_no=?",
        (revision_id, local_no),
    ).fetchone()
    if exists:
        raise ValueError(f"Nomor lokal {local_no} sudah dipakai pada revisi ini.")
    if _check_duplicate_tuple(conn, revision_id, None, local_no, material_id):
        raise ValueError("Kombinasi komponen lokal + material ini sudah ada pada revisi ini.")
    if supplier_id:
        ensure_material_supplier(conn, material_id, supplier_id, actor)

    line_id = new_id()
    line_key = new_id()
    conn.execute(
        """INSERT INTO bom_line (id, revision_id, line_key, local_component_no, local_component_name,
           material_id, supplier_id, process, is_active, sort_order) VALUES (?,?,?,?,?,?,?,?,1,?)""",
        (line_id, revision_id, line_key, local_no, local_name, material_id, supplier_id,
         (process or "").strip() or None, _next_sort_order(conn, revision_id)),
    )
    _create_cells(conn, line_id, revision_id)
    write_audit_log(conn, actor, "BomLine", line_id, "CREATE", None,
                     {"localComponentNo": local_no, "localComponentName": local_name, "materialId": material_id})
    conn.commit()
    return line_id


def add_subcomponent_line(conn, revision_id: str, parent_line_id: str, sub_name: str,
                           material_id: str, process: str, actor: str, supplier_id: str = None) -> str:
    ensure_draft(conn, revision_id)
    parent = conn.execute(
        "SELECT * FROM bom_line WHERE id=? AND revision_id=?", (parent_line_id, revision_id)
    ).fetchone()
    if not parent:
        raise ValueError("Baris induk tidak ditemukan.")
    if parent["parent_line_key"]:
        raise ValueError("Subkomponen tidak bisa dibuat di bawah subkomponen lain.")
    sub_name = (sub_name or "").strip()
    if not sub_name:
        raise ValueError("Nama subkomponen wajib diisi.")
    material = conn.execute("SELECT * FROM material WHERE id=?", (material_id,)).fetchone()
    if not material:
        raise ValueError("Material tidak ditemukan.")

    if supplier_id:
        ensure_material_supplier(conn, material_id, supplier_id, actor)

    max_seq_row = conn.execute(
        "SELECT MAX(sub_seq) m FROM bom_line WHERE parent_line_key=?", (parent["line_key"],)
    ).fetchone()
    next_seq = (max_seq_row["m"] or 0) + 1

    line_id = new_id()
    line_key = new_id()
    conn.execute(
        """INSERT INTO bom_line (id, revision_id, line_key, parent_line_key, sub_seq, sub_name,
           material_id, supplier_id, process, is_active, sort_order) VALUES (?,?,?,?,?,?,?,?,?,1,?)""",
        (line_id, revision_id, line_key, parent["line_key"], next_seq, sub_name, material_id, supplier_id,
         (process or "").strip() or None, parent["sort_order"]),
    )
    _create_cells(conn, line_id, revision_id)
    write_audit_log(conn, actor, "BomLine", line_id, "CREATE", None,
                     {"parentLineKey": parent["line_key"], "subSeq": next_seq, "subName": sub_name})
    conn.commit()
    return line_id


def replace_material(conn, revision_id: str, old_line_id: str, new_material_id: str, actor: str) -> str:
    """Ganti material (PRD 6.2): baris lama isActive=false, baris baru dibuat dengan
    replacesLineKey. Komponen, subSeq, supplier, dan BomCell disalin dari baris lama."""
    ensure_draft(conn, revision_id)
    old_line = conn.execute(
        "SELECT * FROM bom_line WHERE id=? AND revision_id=?", (old_line_id, revision_id)
    ).fetchone()
    if not old_line or not old_line["is_active"]:
        raise ValueError("Baris tidak ditemukan atau sudah tidak aktif.")
    material = conn.execute("SELECT * FROM material WHERE id=?", (new_material_id,)).fetchone()
    if not material:
        raise ValueError("Material tidak ditemukan.")
    if old_line["material_id"] == new_material_id:
        raise ValueError("Material baru sama dengan material saat ini.")
    if old_line["supplier_id"]:
        ensure_material_supplier(conn, new_material_id, old_line["supplier_id"], actor)

    new_line_id = new_id()
    new_line_key = new_id()
    conn.execute(
        """INSERT INTO bom_line (id, revision_id, line_key, origin_line_key, replaces_line_key,
           component_id, local_component_no, local_component_name, parent_line_key, sub_seq, sub_name,
           material_id, supplier_id, process, is_active, sort_order)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?)""",
        (new_line_id, revision_id, new_line_key, old_line["origin_line_key"], old_line["line_key"],
         old_line["component_id"], old_line["local_component_no"], old_line["local_component_name"],
         old_line["parent_line_key"], old_line["sub_seq"], old_line["sub_name"], new_material_id,
         old_line["supplier_id"], old_line["process"], old_line["sort_order"]),
    )
    cells = conn.execute("SELECT * FROM bom_cell WHERE bom_line_id=?", (old_line_id,)).fetchall()
    for cell in cells:
        conn.execute(
            "INSERT INTO bom_cell (bom_line_id, article_id, color, is_used) VALUES (?,?,?,?)",
            (new_line_id, cell["article_id"], cell["color"], cell["is_used"]),
        )
    conn.execute("UPDATE bom_line SET is_active=0 WHERE id=?", (old_line_id,))

    write_audit_log(conn, actor, "BomLine", old_line_id, "REPLACED",
                     {"materialId": old_line["material_id"]},
                     {"replacedBy": new_line_id, "newMaterialId": new_material_id})
    conn.commit()
    return new_line_id


def update_process(conn, line_id: str, value: str, actor: str) -> None:
    line = conn.execute("SELECT * FROM bom_line WHERE id=?", (line_id,)).fetchone()
    if not line:
        raise ValueError("Baris tidak ditemukan.")
    ensure_draft(conn, line["revision_id"])
    value = (value or "").strip() or None
    conn.execute("UPDATE bom_line SET process=? WHERE id=?", (value, line_id))
    write_audit_log(conn, actor, "BomLine", line_id, "UPDATE_PROCESS",
                     {"process": line["process"]}, {"process": value})
    conn.commit()


def update_line_supplier(conn, line_id: str, supplier_id: str, actor: str) -> None:
    line = conn.execute("SELECT * FROM bom_line WHERE id=?", (line_id,)).fetchone()
    if not line:
        raise ValueError("Baris tidak ditemukan.")
    ensure_draft(conn, line["revision_id"])
    if supplier_id:
        ensure_material_supplier(conn, line["material_id"], supplier_id, actor)
    conn.execute("UPDATE bom_line SET supplier_id=? WHERE id=?", (supplier_id, line_id))
    write_audit_log(conn, actor, "BomLine", line_id, "UPDATE_SUPPLIER",
                     {"supplierId": line["supplier_id"]}, {"supplierId": supplier_id})
    conn.commit()


def update_cell_value(conn, line_id: str, article_id: str, value: str, actor: str) -> None:
    """Set nilai teks sel (mis. warna material) untuk satu article/colorway. `is_used`
    diturunkan otomatis: kosong atau literal "none" (case-insensitive) berarti baris ini
    tidak dipakai pada colorway tsb — sesuai contoh PDF referensi."""
    line = conn.execute("SELECT * FROM bom_line WHERE id=?", (line_id,)).fetchone()
    if not line:
        raise ValueError("Baris tidak ditemukan.")
    ensure_draft(conn, line["revision_id"])
    value = (value or "").strip()
    is_used = 1 if _is_used_value(value) else 0
    updated = conn.execute(
        "UPDATE bom_cell SET color=?, is_used=? WHERE bom_line_id=? AND article_id=?",
        (value or None, is_used, line_id, article_id),
    )
    if updated.rowcount == 0:
        conn.execute(
            "INSERT INTO bom_cell (bom_line_id, article_id, color, is_used) VALUES (?,?,?,?)",
            (line_id, article_id, value or None, is_used),
        )
    write_audit_log(conn, actor, "BomCell", f"{line_id}:{article_id}", "UPDATE_VALUE",
                     None, {"color": value, "isUsed": bool(is_used)})
    conn.commit()


def list_lines_with_cells(conn, revision_id: str):
    rows = conn.execute(
        """SELECT bl.*,
                  c.name AS master_component_name, c.number AS component_number,
                  m.name AS material_name, m.uom AS uom, m.material_code AS material_code,
                  s.name AS supplier_name, ms.status AS supplier_link_status
           FROM bom_line bl
           LEFT JOIN component c ON c.id = bl.component_id
           JOIN material m ON m.id = bl.material_id
           LEFT JOIN supplier s ON s.id = bl.supplier_id
           LEFT JOIN material_supplier ms ON ms.material_id = bl.material_id AND ms.supplier_id = bl.supplier_id
           WHERE bl.revision_id = ? AND bl.is_active = 1""",
        (revision_id,),
    ).fetchall()

    cell_rows = conn.execute(
        """SELECT bc.* FROM bom_cell bc
           JOIN bom_line bl ON bl.id = bc.bom_line_id
           WHERE bl.revision_id=? AND bl.is_active=1""",
        (revision_id,),
    ).fetchall()
    cells_by_line = {}
    for c in cell_rows:
        cells_by_line.setdefault(c["bom_line_id"], {})[c["article_id"]] = dict(c)

    # Urut menurut nomor komponen (master/lokal) — baris baru langsung masuk di
    # posisi nomornya, bukan di paling bawah. Nomor sama (komponen sama, material
    # beda) tetap urut sesuai waktu input. Subkomponen selalu tepat di bawah induknya.
    top_level = sorted(
        [r for r in rows if not r["parent_line_key"]],
        key=lambda r: (component_no_sort_key(r["component_number"] if r["component_number"] is not None
                                             else r["local_component_no"]), r["sort_order"]),
    )
    children_by_parent = {}
    for r in rows:
        if r["parent_line_key"]:
            children_by_parent.setdefault(r["parent_line_key"], []).append(r)
    for key in children_by_parent:
        children_by_parent[key].sort(key=lambda r: (r["sub_seq"] or 0))

    ordered = []
    for parent in top_level:
        parent_no = parent["component_number"] if parent["component_number"] is not None else parent["local_component_no"]
        ordered.append(_enrich_line(parent, cells_by_line, None))
        for child in children_by_parent.get(parent["line_key"], []):
            ordered.append(_enrich_line(child, cells_by_line, parent_no))
    return ordered


def _enrich_line(row, cells_by_line, parent_no):
    d = dict(row)
    if row["parent_line_key"]:
        d["display_no"] = f"{parent_no}-{row['sub_seq']}" if parent_no is not None else str(row["sub_seq"])
        d["display_name"] = row["sub_name"] or ""
    else:
        no = row["component_number"] if row["component_number"] is not None else row["local_component_no"]
        d["display_no"] = str(no)
        d["display_name"] = row["master_component_name"] or row["local_component_name"] or ""
    d["cells"] = cells_by_line.get(row["id"], {})
    d["material_label"] = material_label(row["material_code"], row["material_name"])
    return d


# ---------------- Input ketik di grid BOM ----------------
# Komponen, material, dan supplier diisi lewat input teks + saran (datalist),
# bukan dropdown. Fungsi di bawah menerjemahkan teks yang diketik ke baris
# master yang dimaksud.

def component_label(component) -> str:
    return f"{component['number']} - {component['name']}"


def material_label(code, name) -> str:
    return f"{code}{MATERIAL_LABEL_SEP}{name}"


def resolve_component_text(conn, text):
    """Komponen master APPROVED yang dimaksud teks ini ("10 - Vamp", "10", atau
    "Vamp" kalau namanya unik), atau None kalau tidak ada — artinya teks itu
    nama komponen lokal baru (nomornya wajib diisi terpisah)."""
    key = normalize_text(text)
    if not key:
        return None
    components = conn.execute("SELECT * FROM component WHERE status='APPROVED'").fetchall()
    for c in components:
        if normalize_text(component_label(c)) == key:
            return c
    if key.isdigit():
        for c in components:
            if c["number"] == int(key):
                return c
        return None
    by_name = [c for c in components if normalize_text(c["name"]) == key]
    return by_name[0] if len(by_name) == 1 else None


def resolve_material_text(conn, text) -> str:
    """ID material dari teks yang diketik ("KODE · Nama", kode saja, atau nama
    kalau unik). Material WAJIB sudah ada di master (PROPOSED/APPROVED) —
    material baru didaftarkan dulu lewat Master Data › Material."""
    raw = (text or "").strip()
    if not raw:
        raise ValueError("Material wajib diisi.")
    materials = conn.execute("SELECT * FROM material WHERE status != 'INACTIVE'").fetchall()
    key = normalize_text(raw)
    code_part = normalize_text(raw.split(MATERIAL_LABEL_SEP.strip(), 1)[0])
    for m in materials:
        if normalize_text(material_label(m["material_code"], m["name"])) == key or normalize_text(m["material_code"]) in (key, code_part):
            return m["id"]
    by_name = [m for m in materials if normalize_text(m["name"]) == key]
    if len(by_name) == 1:
        return by_name[0]["id"]
    if len(by_name) > 1:
        raise ValueError(f"Ada beberapa material bernama '{raw}'. Pilih dari daftar supaya kodenya ikut terisi.")
    raise ValueError(f"Material '{raw}' tidak ada di master. Pilih dari daftar, atau daftarkan dulu di Master Data › Material.")


def resolve_supplier_text(conn, text):
    """ID supplier dari nama yang diketik (tidak peka huruf besar/kecil & spasi),
    atau None kalau kosong. Supplier WAJIB sudah ada di Master Supplier."""
    raw = (text or "").strip()
    if not raw:
        return None
    key = normalize_text(raw)
    for s in conn.execute("SELECT * FROM supplier").fetchall():
        if normalize_text(s["name"]) == key:
            if s["status"] == "INACTIVE":
                raise ValueError(f"Supplier {s['name']} sudah dinonaktifkan di Master Supplier.")
            return s["id"]
    raise ValueError(f"Supplier '{raw}' tidak ada di Master Supplier. Minta Master Admin menambahkannya dulu.")


def add_line_from_text(conn, revision_id, component_text, local_no_raw, material_text, supplier_text,
                        process, actor):
    """Tambah baris BOM dari input ketik: komponen yang cocok dengan master →
    baris komponen master; kalau tidak cocok → komponen lokal dan nomornya
    wajib diisi (aturan nomor lokal tetap: bukan kelipatan 10, unik per revisi)."""
    component_text = (component_text or "").strip()
    if not component_text:
        raise ValueError("Komponen wajib diisi.")
    material_id = resolve_material_text(conn, material_text)
    supplier_id = resolve_supplier_text(conn, supplier_text)
    component = resolve_component_text(conn, component_text)
    if component:
        return add_component_line(conn, revision_id, component["id"], material_id, process, actor,
                                  supplier_id=supplier_id)
    if component_text.isdigit():
        raise ValueError(
            f"Komponen nomor {component_text} tidak ada di master. Untuk komponen baru, "
            "ketik namanya lalu isi No."
        )
    local_no_raw = (local_no_raw or "").strip()
    if not local_no_raw:
        raise ValueError(f"'{component_text}' tidak ada di master komponen — isi No. untuk komponen lokal ini.")
    try:
        local_no = int(local_no_raw)
    except ValueError:
        raise ValueError("No. komponen lokal harus berupa angka.")
    return add_local_component_line(conn, revision_id, local_no, component_text, material_id, process, actor,
                                    supplier_id=supplier_id)


def season_colors(conn, season):
    """Saran warna untuk sel BOM: semua warna yang pernah diinput di specsheet
    mana pun pada season yang sama (apa pun materialnya), tanpa duplikat
    (dibandingkan setelah normalisasi) dan tanpa nilai "tidak dipakai"."""
    rows = conn.execute(
        """SELECT bc.color FROM bom_cell bc
           JOIN bom_line bl ON bl.id = bc.bom_line_id
           JOIN specsheet_revision sr ON sr.id = bl.revision_id
           JOIN specsheet sp ON sp.id = sr.specsheet_id
           WHERE sp.season=? AND bc.is_used=1 AND bc.color IS NOT NULL""",
        (season,),
    ).fetchall()
    seen = {}
    for r in rows:
        color = re.sub(r"\s+", " ", r["color"].strip())
        key = normalize_text(color)
        if key and key not in NONE_VALUES and key not in seen:
            seen[key] = color
    return sorted(seen.values(), key=str.lower)
