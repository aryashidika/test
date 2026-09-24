import json

from ..ids import new_id


def write_audit_log(conn, actor: str, entity: str, entity_id: str, action: str, before, after) -> None:
    """Insert an AuditLog row. Does not commit — caller commits once, alongside its own mutation."""
    conn.execute(
        "INSERT INTO audit_log (id, user_role, entity, entity_id, action, before_json, after_json) "
        "VALUES (?,?,?,?,?,?,?)",
        (
            new_id(),
            actor,
            entity,
            entity_id,
            action,
            json.dumps(before, default=str) if before is not None else None,
            json.dumps(after, default=str) if after is not None else None,
        ),
    )
