"""Master harga: link Material–Supplier dan harga per link (tambahan di luar PRD).

Aturan kepemilikan (lihat juga README):
- Link material–supplier dimiliki tim specsheet. Terbentuk otomatis saat
  supplier dipilih di BOM (`ensure_material_supplier`, status PROPOSED) atau
  didaftarkan langsung di Master Material; Master Admin yang approve /
  menonaktifkan. Supplier-nya sendiri wajib sudah ada di Master Supplier.
- Harga dimiliki tim CBD dan HANYA diisi di Master Material — tidak ada jalan
  pintas dari grid CBD. CBD mengambil harga dari sini (`lookup_price`) lalu
  menyimpannya sebagai snapshot di cbd_line, jadi CBD yang sudah terbit tidak
  ikut berubah saat harga master berubah.
- Harga tidak pernah ditimpa: harga baru untuk link + warna yang sama menutup
  harga yang masih berlaku (valid_to = valid_from harga baru). valid_from
  inklusif, valid_to eksklusif, keduanya teks 'YYYY-MM-DD'.
- color NULL = harga untuk semua warna. Baris dengan color terisi adalah harga
  khusus warna tsb dan selalu menang atas harga semua warna.
- Metode harga per material (`material.price_method`): 'CATALOG' memakai
  harga master di sini; 'QUOTATION' (material proses — printing, molding, dst,
  yang harganya beda tiap desain/warna) TIDAK punya harga master sama sekali —
  harganya diisi langsung per baris CBD beserta no. quotation-nya.
"""

import datetime

from ..ids import new_id
from ..normalize import normalize_text, parse_decimal
from .audit import write_audit_log
from .cbd_calc import to_text

LINK_STATUSES = ("PROPOSED", "APPROVED", "INACTIVE")
CURRENCIES = ("IDR", "USD")
PRICE_METHODS = ("CATALOG", "QUOTATION")


def today_iso() -> str:
    return datetime.date.today().isoformat()


def _parse_date(value, field_name="Tanggal"):
    text = (value or "").strip()
    if not text:
        return None
    try:
        return datetime.date.fromisoformat(text).isoformat()
    except ValueError as exc:
        raise ValueError(f"{field_name} harus berformat YYYY-MM-DD.") from exc


# ---------------- Metode harga ----------------

def get_price_method(conn, material_id):
    row = conn.execute("SELECT price_method FROM material WHERE id=?", (material_id,)).fetchone()
    return row["price_method"] if row else "CATALOG"


def is_quotation_material(conn, material_id):
    return get_price_method(conn, material_id) == "QUOTATION"


def set_price_method(conn, material_id, method, actor):
    """Keputusan tim CBD. Pindah ke QUOTATION tidak menghapus harga master yang
    sudah ada (tetap di riwayat), tapi harga itu tidak dipakai CBD lagi; CBD
    DRAFT yang sudah terisi harga master akan menawarkan 'Refresh Harga'."""
    if method not in PRICE_METHODS:
        raise ValueError("Metode harga tidak valid.")
    before = conn.execute("SELECT price_method FROM material WHERE id=?", (material_id,)).fetchone()
    if not before:
        raise ValueError("Material tidak ditemukan.")
    conn.execute(
        "UPDATE material SET price_method=?, updated_by=?, updated_at=datetime('now') WHERE id=?",
        (method, actor, material_id),
    )
    write_audit_log(conn, actor, "Material", material_id, "SET_PRICE_METHOD",
                     {"priceMethod": before["price_method"]}, {"priceMethod": method})
    conn.commit()


# ---------------- Material–Supplier ----------------

def get_material_supplier(conn, link_id):
    row = conn.execute("SELECT * FROM material_supplier WHERE id=?", (link_id,)).fetchone()
    if not row:
        raise ValueError("Supplier untuk material ini tidak ditemukan.")
    return row


def find_material_supplier(conn, material_id, supplier_id):
    return conn.execute(
        "SELECT * FROM material_supplier WHERE material_id=? AND supplier_id=?", (material_id, supplier_id)
    ).fetchone()


def _check_supplier_usable(conn, supplier_id):
    supplier = conn.execute("SELECT * FROM supplier WHERE id=?", (supplier_id,)).fetchone()
    if not supplier:
        raise ValueError("Supplier tidak ditemukan di Master Supplier.")
    if supplier["status"] == "INACTIVE":
        raise ValueError(f"Supplier {supplier['name']} sudah dinonaktifkan di Master Supplier.")
    return supplier


def ensure_material_supplier(conn, material_id, supplier_id, actor):
    """Dipanggil setiap kali supplier dipilih untuk sebuah material di BOM.
    Kombinasi baru dibuat sebagai link PROPOSED (langsung bisa dipakai, tidak
    menunggu approval). Kombinasi yang sudah dinonaktifkan Master Admin ditolak.
    TIDAK commit — pemanggil (bom_service) commit bersama mutasinya sendiri."""
    supplier = _check_supplier_usable(conn, supplier_id)
    existing = find_material_supplier(conn, material_id, supplier_id)
    if existing:
        if existing["status"] == "INACTIVE":
            material = conn.execute("SELECT name FROM material WHERE id=?", (material_id,)).fetchone()
            raise ValueError(
                f"Supplier {supplier['name']} sudah dinonaktifkan untuk material "
                f"{material['name'] if material else ''}. Pilih supplier lain."
            )
        return existing["id"]
    link_id = new_id()
    conn.execute(
        """INSERT INTO material_supplier (id, material_id, supplier_id, status, created_by, updated_by)
           VALUES (?,?,?,'PROPOSED',?,?)""",
        (link_id, material_id, supplier_id, actor, actor),
    )
    write_audit_log(conn, actor, "MaterialSupplier", link_id, "CREATE", None,
                     {"materialId": material_id, "supplierId": supplier_id, "status": "PROPOSED"})
    return link_id


def add_material_supplier(conn, material_id, supplier_id, supplier_material_code, is_preferred,
                           status, actor):
    """Mendaftarkan supplier sebuah material langsung dari Master Material."""
    if not conn.execute("SELECT 1 FROM material WHERE id=?", (material_id,)).fetchone():
        raise ValueError("Material tidak ditemukan.")
    if status not in LINK_STATUSES:
        raise ValueError("Status tidak valid.")
    supplier = _check_supplier_usable(conn, supplier_id)
    if find_material_supplier(conn, material_id, supplier_id):
        raise ValueError(f"Supplier {supplier['name']} sudah terdaftar untuk material ini.")
    link_id = new_id()
    conn.execute(
        """INSERT INTO material_supplier
           (id, material_id, supplier_id, supplier_material_code, status, created_by, updated_by)
           VALUES (?,?,?,?,?,?,?)""",
        (link_id, material_id, supplier_id, (supplier_material_code or "").strip() or None,
         status, actor, actor),
    )
    write_audit_log(conn, actor, "MaterialSupplier", link_id, "CREATE", None,
                     {"materialId": material_id, "supplierId": supplier_id, "status": status})
    if is_preferred:
        _set_preferred(conn, link_id, actor)
    conn.commit()
    return link_id


def update_supplier_material_code(conn, link_id, code, actor):
    link = get_material_supplier(conn, link_id)
    code = (code or "").strip() or None
    conn.execute(
        "UPDATE material_supplier SET supplier_material_code=?, updated_by=?, updated_at=datetime('now') "
        "WHERE id=?",
        (code, actor, link_id),
    )
    write_audit_log(conn, actor, "MaterialSupplier", link_id, "UPDATE_SUPPLIER_CODE",
                     {"supplierMaterialCode": link["supplier_material_code"]}, {"supplierMaterialCode": code})
    conn.commit()


def _set_preferred(conn, link_id, actor):
    link = get_material_supplier(conn, link_id)
    if link["status"] == "INACTIVE":
        raise ValueError("Supplier yang nonaktif tidak bisa dijadikan supplier utama.")
    conn.execute("UPDATE material_supplier SET is_preferred=0 WHERE material_id=?", (link["material_id"],))
    conn.execute(
        "UPDATE material_supplier SET is_preferred=1, updated_by=?, updated_at=datetime('now') WHERE id=?",
        (actor, link_id),
    )
    write_audit_log(conn, actor, "MaterialSupplier", link_id, "SET_PREFERRED", None, {"isPreferred": True})


def set_preferred_supplier(conn, link_id, actor):
    """Supplier utama = yang otomatis terisi di BOM saat material dipilih.
    Maksimal satu per material."""
    _set_preferred(conn, link_id, actor)
    conn.commit()


def set_material_supplier_status(conn, link_id, status, actor):
    if status not in LINK_STATUSES:
        raise ValueError("Status tidak valid.")
    link = get_material_supplier(conn, link_id)
    conn.execute(
        "UPDATE material_supplier SET status=?, updated_by=?, updated_at=datetime('now') WHERE id=?",
        (status, actor, link_id),
    )
    if status == "INACTIVE":
        conn.execute("UPDATE material_supplier SET is_preferred=0 WHERE id=?", (link_id,))
    write_audit_log(conn, actor, "MaterialSupplier", link_id, "STATUS_CHANGE",
                     {"status": link["status"]}, {"status": status})
    conn.commit()


def list_material_suppliers(conn, material_id):
    """Supplier utama dulu, lalu yang aktif, lalu alfabetis."""
    return conn.execute(
        """SELECT ms.*, s.name AS supplier_name, s.default_currency, s.status AS supplier_status
           FROM material_supplier ms JOIN supplier s ON s.id = ms.supplier_id
           WHERE ms.material_id=?
           ORDER BY ms.is_preferred DESC, ms.status='INACTIVE', s.name""",
        (material_id,),
    ).fetchall()


def supplier_suggestions(conn, material_id=None):
    """Pilihan supplier untuk kolom "Source of Material" di BOM: supplier yang
    sudah terdaftar untuk material ini dulu (utama paling atas, link INACTIVE
    tidak ditawarkan), lalu semua supplier aktif lain dari Master Supplier."""
    suppliers = conn.execute(
        "SELECT * FROM supplier WHERE status != 'INACTIVE' ORDER BY name"
    ).fetchall()
    links = {}
    if material_id:
        for link in list_material_suppliers(conn, material_id):
            links[link["supplier_id"]] = link
    linked, others = [], []
    for s in suppliers:
        link = links.get(s["id"])
        if link and link["status"] == "INACTIVE":
            continue
        entry = {"id": s["id"], "name": s["name"], "linked": bool(link),
                 "preferred": bool(link and link["is_preferred"]),
                 "supplier_material_code": link["supplier_material_code"] if link else None,
                 "link_status": link["status"] if link else None}
        (linked if link else others).append(entry)
    linked.sort(key=lambda e: (not e["preferred"], e["name"].lower()))
    return linked + others


def default_supplier_for(conn, material_id):
    """Supplier yang otomatis terisi di BOM saat material dipilih: supplier
    utama, atau satu-satunya supplier aktif kalau hanya ada satu."""
    active = [l for l in list_material_suppliers(conn, material_id) if l["status"] != "INACTIVE"]
    preferred = [l for l in active if l["is_preferred"]]
    if preferred:
        return preferred[0]
    if len(active) == 1:
        return active[0]
    return None


# ---------------- Harga ----------------

def add_price(conn, material_supplier_id, color, price, currency, valid_from, reference, actor):
    """Tambah harga untuk satu link material–supplier. `color` kosong = semua
    warna. Harga yang masih berlaku untuk link + warna yang sama ditutup
    (valid_to = valid_from harga baru); harga baru tidak boleh mulai berlaku
    lebih awal dari harga yang ditutupnya. Tanggal yang sama boleh (koreksi):
    harga lama jadi berdurasi nol dan tidak pernah terpakai lagi."""
    link = get_material_supplier(conn, material_supplier_id)
    if link["status"] == "INACTIVE":
        raise ValueError("Supplier ini sudah nonaktif untuk material ini — tidak bisa diberi harga baru.")
    if is_quotation_material(conn, link["material_id"]):
        raise ValueError("Material ini memakai metode harga Quotation — harganya diisi per CBD, bukan di master.")
    parsed = parse_decimal(price, "Harga")
    if parsed is None:
        raise ValueError("Harga wajib diisi.")
    if parsed <= 0:
        raise ValueError("Harga harus lebih besar dari 0.")
    if currency not in CURRENCIES:
        raise ValueError("Currency harus IDR atau USD.")
    valid_from = _parse_date(valid_from, "Berlaku mulai") or today_iso()
    color = (color or "").strip() or None
    color_normalized = normalize_text(color)

    open_row = conn.execute(
        """SELECT * FROM material_price WHERE material_supplier_id=? AND color_normalized=?
           AND valid_to IS NULL ORDER BY valid_from DESC LIMIT 1""",
        (material_supplier_id, color_normalized),
    ).fetchone()
    if open_row:
        if valid_from < open_row["valid_from"]:
            raise ValueError(
                f"Sudah ada harga yang berlaku mulai {open_row['valid_from']} untuk "
                f"{'warna ' + color if color else 'semua warna'}. Tanggal berlaku harga baru "
                f"tidak boleh lebih awal dari itu."
            )
        conn.execute("UPDATE material_price SET valid_to=? WHERE id=?", (valid_from, open_row["id"]))

    price_id = new_id()
    conn.execute(
        """INSERT INTO material_price
           (id, material_supplier_id, color, color_normalized, price, currency, valid_from, reference, created_by)
           VALUES (?,?,?,?,?,?,?,?,?)""",
        (price_id, material_supplier_id, color, color_normalized, to_text(parsed), currency, valid_from,
         (reference or "").strip() or None, actor),
    )
    write_audit_log(
        conn, actor, "MaterialPrice", price_id, "CREATE",
        {"closedPriceId": open_row["id"], "price": open_row["price"], "currency": open_row["currency"]}
        if open_row else None,
        {"materialSupplierId": material_supplier_id, "color": color, "price": to_text(parsed),
         "currency": currency, "validFrom": valid_from},
    )
    conn.commit()
    return price_id


def end_price(conn, price_id, actor, valid_to=None):
    """Akhiri harga yang masih berlaku (mis. harga khusus warna yang tidak
    berlaku lagi, sehingga warna itu kembali memakai harga semua warna)."""
    row = conn.execute("SELECT * FROM material_price WHERE id=?", (price_id,)).fetchone()
    if not row:
        raise ValueError("Harga tidak ditemukan.")
    if row["valid_to"] is not None:
        raise ValueError("Harga ini sudah tidak berlaku.")
    valid_to = _parse_date(valid_to, "Berlaku sampai") or today_iso()
    if valid_to < row["valid_from"]:
        valid_to = row["valid_from"]
    conn.execute("UPDATE material_price SET valid_to=? WHERE id=?", (valid_to, price_id))
    write_audit_log(conn, actor, "MaterialPrice", price_id, "END", {"validTo": None}, {"validTo": valid_to})
    conn.commit()


def get_price(conn, price_id):
    return conn.execute(
        """SELECT mp.*, ms.material_id, ms.supplier_id FROM material_price mp
           JOIN material_supplier ms ON ms.id = mp.material_supplier_id WHERE mp.id=?""",
        (price_id,),
    ).fetchone()


def list_prices(conn, material_id):
    """Semua harga sebuah material (berlaku + riwayat), per link."""
    return conn.execute(
        """SELECT mp.*, ms.supplier_id, s.name AS supplier_name
           FROM material_price mp
           JOIN material_supplier ms ON ms.id = mp.material_supplier_id
           JOIN supplier s ON s.id = ms.supplier_id
           WHERE ms.material_id=?
           ORDER BY s.name, mp.color_normalized, mp.valid_from DESC, mp.created_at DESC""",
        (material_id,),
    ).fetchall()


def _valid_on(on_date):
    return "mp.valid_from <= ? AND (mp.valid_to IS NULL OR mp.valid_to > ?)", [on_date, on_date]


def lookup_price(conn, material_id, supplier_id, color=None, on_date=None):
    """Harga master yang berlaku untuk satu baris CBD: material + supplier +
    warna dulu, lalu material + supplier untuk semua warna. Mengembalikan row
    material_price (plus `tier`: 'COLOR' / 'ALL_COLORS') atau None. Tidak ada
    fallback lintas supplier — harga supplier lain bukan harga baris ini."""
    if not material_id or not supplier_id or is_quotation_material(conn, material_id):
        return None
    on_date = on_date or today_iso()
    color_normalized = normalize_text(color)
    cond, params = _valid_on(on_date)
    candidates = [("COLOR", color_normalized)] if color_normalized else []
    candidates.append(("ALL_COLORS", ""))
    for tier, key in candidates:
        row = conn.execute(
            f"""SELECT mp.* FROM material_price mp
                JOIN material_supplier ms ON ms.id = mp.material_supplier_id
                WHERE ms.material_id=? AND ms.supplier_id=? AND mp.color_normalized=? AND {cond}
                ORDER BY mp.valid_from DESC, mp.created_at DESC, mp.rowid DESC LIMIT 1""",
            [material_id, supplier_id, key] + params,
        ).fetchone()
        if row:
            result = dict(row)
            result["tier"] = tier
            return result
    return None


def price_gap(conn, material_id, supplier_id, color=None, on_date=None):
    """Kenapa sebuah baris CBD belum punya harga master — dipakai untuk pesan di
    grid CBD. 'NO_SUPPLIER' (supplier belum dipilih di specsheet),
    'NO_COLOR_PRICE' (hanya ada harga untuk warna lain, `colors` berisi daftar
    warnanya), atau 'NO_PRICE' (belum ada harga sama sekali untuk material +
    supplier ini), atau 'QUOTATION' (material proses: harga diisi per CBD, boleh
    dikosongkan kalau sudah termasuk di baris proses lain). None kalau
    sebenarnya ada harga."""
    if is_quotation_material(conn, material_id):
        return {"code": "QUOTATION", "colors": []}
    if not supplier_id:
        return {"code": "NO_SUPPLIER", "colors": []}
    if lookup_price(conn, material_id, supplier_id, color, on_date):
        return None
    on_date = on_date or today_iso()
    cond, params = _valid_on(on_date)
    rows = conn.execute(
        f"""SELECT DISTINCT mp.color FROM material_price mp
            JOIN material_supplier ms ON ms.id = mp.material_supplier_id
            WHERE ms.material_id=? AND ms.supplier_id=? AND mp.color IS NOT NULL AND {cond}
            ORDER BY mp.color""",
        [material_id, supplier_id] + params,
    ).fetchall()
    colors = [r["color"] for r in rows]
    if colors:
        return {"code": "NO_COLOR_PRICE", "colors": colors}
    return {"code": "NO_PRICE", "colors": []}


def color_suggestions_for_price(conn, material_id, supplier_id=None):
    """Saran warna di form harga: warna yang pernah dipakai material ini di BOM
    (untuk supplier tsb kalau diberikan) + warna yang sudah pernah diberi harga."""
    params = [material_id]
    supplier_cond = ""
    if supplier_id:
        supplier_cond = " AND bl.supplier_id=?"
        params.append(supplier_id)
    rows = conn.execute(
        f"""SELECT bc.color FROM bom_cell bc JOIN bom_line bl ON bl.id = bc.bom_line_id
            WHERE bl.material_id=? AND bc.is_used=1 AND bc.color IS NOT NULL{supplier_cond}""",
        params,
    ).fetchall()
    price_rows = conn.execute(
        """SELECT mp.color FROM material_price mp JOIN material_supplier ms ON ms.id = mp.material_supplier_id
           WHERE ms.material_id=? AND mp.color IS NOT NULL""",
        (material_id,),
    ).fetchall()
    return _distinct_colors([r["color"] for r in rows] + [r["color"] for r in price_rows])


def _distinct_colors(colors):
    seen = {}
    for c in colors:
        c = (c or "").strip()
        key = normalize_text(c)
        if key and key not in seen:
            seen[key] = c
    return sorted(seen.values(), key=str.lower)


def materials_without_price(conn, on_date=None):
    """ID material yang punya minimal satu supplier aktif (non-INACTIVE) tanpa
    harga berlaku sama sekali — dipakai filter "Belum ada harga" di Master
    Material untuk tim CBD."""
    on_date = on_date or today_iso()
    cond, params = _valid_on(on_date)
    rows = conn.execute(
        f"""SELECT DISTINCT ms.material_id FROM material_supplier ms
            JOIN material m ON m.id = ms.material_id AND m.price_method = 'CATALOG'
            WHERE ms.status != 'INACTIVE' AND NOT EXISTS (
                SELECT 1 FROM material_price mp WHERE mp.material_supplier_id = ms.id AND {cond})""",
        params,
    ).fetchall()
    return {r["material_id"] for r in rows}


def supplier_summary_by_material(conn, on_date=None):
    """{material_id: {"suppliers": n aktif, "priced": n aktif yang punya harga berlaku,
    "proposed": n PROPOSED, "quotation": metode harga QUOTATION?}} untuk kolom
    ringkasan di daftar Master Material."""
    on_date = on_date or today_iso()
    cond, params = _valid_on(on_date)
    rows = conn.execute(
        f"""SELECT ms.material_id, ms.status, m.price_method,
                   EXISTS (SELECT 1 FROM material_price mp WHERE mp.material_supplier_id = ms.id AND {cond})
                   AS has_price
            FROM material_supplier ms JOIN material m ON m.id = ms.material_id""",
        params,
    ).fetchall()
    summary = {}
    for r in rows:
        s = summary.setdefault(r["material_id"], {"suppliers": 0, "priced": 0, "proposed": 0,
                                                  "quotation": r["price_method"] == "QUOTATION"})
        if r["status"] == "INACTIVE":
            continue
        s["suppliers"] += 1
        s["priced"] += 1 if r["has_price"] else 0
        s["proposed"] += 1 if r["status"] == "PROPOSED" else 0
    return summary
