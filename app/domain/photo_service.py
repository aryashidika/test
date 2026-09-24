import shutil
from pathlib import Path

from ..db import PROJECT_ROOT
from ..ids import new_id
from .audit import write_audit_log

UPLOAD_DIR = PROJECT_ROOT / "uploads" / "specsheet_photos"
MAX_SIZE_BYTES = 10 * 1024 * 1024
ALLOWED_EXT = {".jpg", ".jpeg", ".png"}


def upload_photo(conn, specsheet_id: str, source_path: str, actor: str) -> str:
    src = Path(source_path)
    if not src.is_file():
        raise ValueError("File tidak ditemukan.")
    if src.suffix.lower() not in ALLOWED_EXT:
        raise ValueError("Hanya file JPG/PNG yang diperbolehkan.")
    if src.stat().st_size > MAX_SIZE_BYTES:
        raise ValueError("Ukuran file melebihi 10 MB.")

    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    photo_id = new_id()
    dest_path = UPLOAD_DIR / f"{photo_id}{src.suffix.lower()}"
    shutil.copyfile(src, dest_path)

    conn.execute(
        "INSERT INTO specsheet_photo (id, specsheet_id, file_path, original_name) VALUES (?,?,?,?)",
        (photo_id, specsheet_id, str(dest_path), src.name),
    )
    write_audit_log(conn, actor, "SpecsheetPhoto", photo_id, "CREATE", None, {"originalName": src.name})
    conn.commit()
    return photo_id


def list_photos(conn, specsheet_id: str):
    return conn.execute(
        "SELECT * FROM specsheet_photo WHERE specsheet_id=? ORDER BY uploaded_at DESC", (specsheet_id,)
    ).fetchall()
