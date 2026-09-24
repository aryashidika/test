def _lines_by_key(conn, revision_id: str):
    rows = conn.execute(
        """SELECT bl.*, c.name AS master_component_name, m.name AS material_name,
                  s.name AS supplier_name
           FROM bom_line bl
           LEFT JOIN component c ON c.id = bl.component_id
           JOIN material m ON m.id = bl.material_id
           LEFT JOIN supplier s ON s.id = bl.supplier_id
           WHERE bl.revision_id=? AND bl.is_active=1""",
        (revision_id,),
    ).fetchall()
    result = {}
    for r in rows:
        cells = conn.execute(
            "SELECT article_id, color, is_used FROM bom_cell WHERE bom_line_id=?", (r["id"],)
        ).fetchall()
        cell_map = {c["article_id"]: {"color": c["color"], "isUsed": bool(c["is_used"])} for c in cells}
        d = dict(r)
        d["display"] = d["master_component_name"] or d["local_component_name"] or d["sub_name"] or "-"
        result[r["line_key"]] = (d, cell_map)
    return result


def compute_bom_diff(conn, old_revision_id: str, new_revision_id: str) -> dict:
    """Diff BOM antar dua revisi specsheet, mengacu pada lineKey (PRD 6.7)."""
    old_lines = _lines_by_key(conn, old_revision_id)
    new_lines = _lines_by_key(conn, new_revision_id)

    added = []
    for key, (line, _cells) in new_lines.items():
        if key not in old_lines:
            added.append({"lineKey": key, "component": line["display"], "material": line["material_name"]})

    removed = []
    for key, (line, _cells) in old_lines.items():
        if key not in new_lines:
            removed.append({"lineKey": key, "component": line["display"], "material": line["material_name"]})

    changed = {}
    for key in set(old_lines) & set(new_lines):
        old_line, old_cells = old_lines[key]
        new_line, new_cells = new_lines[key]
        field_changes = {}
        for field, label in (
            ("material_name", "Material"),
            ("display", "Komponen/Subkomponen"),
            ("supplier_name", "Source of Material"),
            ("process", "Process"),
        ):
            if old_line.get(field) != new_line.get(field):
                field_changes[label] = {"before": old_line.get(field), "after": new_line.get(field)}

        cell_changes = {}
        for article_id in set(old_cells) | set(new_cells):
            oc = old_cells.get(article_id, {"color": None, "isUsed": False})
            nc = new_cells.get(article_id, {"color": None, "isUsed": False})
            if oc != nc:
                cell_changes[article_id] = {"before": oc, "after": nc}

        if field_changes or cell_changes:
            changed[key] = {
                "component": new_line["display"],
                "fields": field_changes,
                "cells": cell_changes,
            }

    return {"added": added, "removed": removed, "changed": changed}
