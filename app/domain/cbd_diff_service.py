"""Diff antar dua revisi CBD, mengacu pada lineKey (PRD 6.7) — sama persis
polanya dengan diff_service.compute_bom_diff, plus satu pseudo-entry "__header__"
untuk field header CbdRevision (exchangeRate/amortisasi/dst) yang tidak ada
padanannya di BOM."""


def _cbd_lines_by_key(conn, cbd_revision_id):
    rows = conn.execute(
        """SELECT cl.*, c.name AS master_component_name, m.name AS material_name,
                  s.name AS supplier_name
           FROM cbd_line cl
           LEFT JOIN component c ON c.id = cl.component_id
           JOIN material m ON m.id = cl.material_id
           LEFT JOIN supplier s ON s.id = cl.supplier_id
           WHERE cl.cbd_revision_id=?""",
        (cbd_revision_id,),
    ).fetchall()
    result = {}
    for r in rows:
        d = dict(r)
        d["display"] = (
            d["master_component_name"]
            or (f"Lokal {d['local_component_no']}" if d["local_component_no"] is not None else None)
            or d["material_name"]
        )
        result[r["line_key"]] = d
    return result


def compute_cbd_diff(conn, old_cbd_revision_id: str, new_cbd_revision_id: str) -> dict:
    old_lines = _cbd_lines_by_key(conn, old_cbd_revision_id)
    new_lines = _cbd_lines_by_key(conn, new_cbd_revision_id)

    added = []
    for key, line in new_lines.items():
        if key not in old_lines:
            added.append({"lineKey": key, "component": line["display"], "material": line["material_name"]})

    removed = []
    for key, line in old_lines.items():
        if key not in new_lines:
            removed.append({"lineKey": key, "component": line["display"], "material": line["material_name"]})

    changed = {}
    for key in set(old_lines) & set(new_lines):
        old_line = old_lines[key]
        new_line = new_lines[key]
        field_changes = {}
        for field, label in (
            ("material_name", "Material"),
            ("supplier_name", "Supplier"),
            ("color", "Color"),
            ("uom", "UoM"),
            ("yield_value", "Yield"),
            ("usage_value", "Usage"),
            ("loss_pct", "Loss %"),
            ("price_original", "Harga asli"),
            ("currency", "Currency"),
            ("price_source", "Sumber Harga"),
            ("status", "Status"),
        ):
            if old_line.get(field) != new_line.get(field):
                field_changes[label] = {"before": old_line.get(field), "after": new_line.get(field)}
        if field_changes:
            changed[key] = {"component": new_line["display"], "fields": field_changes}

    old_rev = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (old_cbd_revision_id,)).fetchone()
    new_rev = conn.execute("SELECT * FROM cbd_revision WHERE id=?", (new_cbd_revision_id,)).fetchone()
    header_changes = {}
    for field, label in (
        ("exchange_rate", "Exchange Rate"),
        ("amortization", "Amortisasi"),
        ("adjustment", "Adjustment"),
        ("selling_price", "Selling Price"),
        ("target_fob", "Target FOB"),
    ):
        if old_rev[field] != new_rev[field]:
            header_changes[label] = {"before": old_rev[field], "after": new_rev[field]}
    if header_changes:
        changed["__header__"] = {"component": "Header CBD", "fields": header_changes}

    return {"added": added, "removed": removed, "changed": changed}
