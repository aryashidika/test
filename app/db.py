import sqlite3
from pathlib import Path
from typing import Optional

from .ids import new_id

APP_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = APP_DIR.parent
DB_DIR = PROJECT_ROOT / "data"
DB_PATH = DB_DIR / "app.db"
SCHEMA_PATH = APP_DIR / "schema.sql"

SEED_COMPONENT_GROUPS = [
    ("a", "Upper", 0, 3990, 1),
    ("c", "Bottom unit", 4000, 5990, 2),
    ("d", "Packaging", 6000, 7990, 3),
    ("e", "Miscellaneous", 8000, 9990, 4),
]


def get_connection(db_path: Optional[Path] = None) -> sqlite3.Connection:
    DB_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path or DB_PATH))
    conn.execute("PRAGMA foreign_keys = ON")
    conn.row_factory = sqlite3.Row
    return conn


def init_db(conn: Optional[sqlite3.Connection] = None) -> sqlite3.Connection:
    """Buat skema + seed ComponentGroup saja. Data dummy Material/Komponen/Supplier
    TIDAK diseed di sini (dipanggil terpisah dari main.py) supaya test suite tetap
    memakai database kosong yang deterministik."""
    owns_conn = conn is None
    conn = conn or get_connection()
    with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
        conn.executescript(f.read())
    conn.commit()
    _seed_component_groups(conn)
    _migrate_supplier_default_currency(conn)
    _migrate_material_fields(conn)
    _migrate_cbd_line_sub_name(conn)
    _migrate_cbd_line_price_source(conn)
    _migrate_material_price_method(conn)
    _backfill_material_supplier_links(conn)
    if owns_conn:
        return conn
    return conn


def _migrate_supplier_default_currency(conn: sqlite3.Connection) -> None:
    """ALTER TABLE tidak idempoten di SQLite (tidak ada ADD COLUMN IF NOT EXISTS),
    jadi migrasi kolom baru dicek manual di sini alih-alih lewat schema.sql."""
    columns = {row["name"] for row in conn.execute("PRAGMA table_info(supplier)").fetchall()}
    if "default_currency" not in columns:
        conn.execute(
            "ALTER TABLE supplier ADD COLUMN default_currency TEXT "
            "CHECK (default_currency IN ('IDR','USD')) DEFAULT 'IDR'"
        )
        conn.commit()


def _migrate_material_fields(conn: sqlite3.Connection) -> None:
    """Material lama (dimension_value/dimension_unit) dipindah ke skema baru
    (material_code, thickness, created_by, updated_by) untuk database yang sudah ada."""
    columns = {row["name"] for row in conn.execute("PRAGMA table_info(material)").fetchall()}
    if "thickness" not in columns:
        conn.execute("ALTER TABLE material ADD COLUMN thickness TEXT")
        if "dimension_value" in columns:
            conn.execute(
                "UPDATE material SET thickness = TRIM(COALESCE(dimension_value,'') || ' ' || "
                "COALESCE(dimension_unit,'')) WHERE dimension_value IS NOT NULL"
            )
        conn.commit()
    if "thickness_normalized" not in columns:
        conn.execute("ALTER TABLE material ADD COLUMN thickness_normalized TEXT NOT NULL DEFAULT ''")
        conn.execute(
            "UPDATE material SET thickness_normalized = "
            "REPLACE(TRIM(LOWER(COALESCE(thickness,''))), ',', '.')"
        )
        conn.commit()
    if "material_code" not in columns:
        conn.execute("ALTER TABLE material ADD COLUMN material_code TEXT")
        conn.execute(
            "UPDATE material SET material_code = 'MTR-' || substr('0000' || rowid, -4, 4) "
            "WHERE material_code IS NULL"
        )
        conn.commit()
    if "created_by" not in columns:
        conn.execute("ALTER TABLE material ADD COLUMN created_by TEXT")
        conn.commit()
    if "updated_by" not in columns:
        conn.execute("ALTER TABLE material ADD COLUMN updated_by TEXT")
        conn.commit()


def _migrate_cbd_line_sub_name(conn: sqlite3.Connection) -> None:
    """Kolom `sub_name` (nama subkomponen, disalin dari BomLine saat generate)
    ditambahkan belakangan supaya baris CBD hasil subkomponen bisa menampilkan
    nama spesifiknya sendiri, bukan ikut nama komponen induk — lihat
    `cbd_service.compute_display_fields`."""
    columns = {row["name"] for row in conn.execute("PRAGMA table_info(cbd_line)").fetchall()}
    if "sub_name" not in columns:
        conn.execute("ALTER TABLE cbd_line ADD COLUMN sub_name TEXT")
        conn.commit()


_PRICE_SOURCE_CHECK_OLD = "CHECK (price_source IN ('MASTER','OVERRIDE'))"
_PRICE_SOURCE_CHECK = "CHECK (price_source IN ('MASTER','OVERRIDE','QUOTATION'))"


def _migrate_cbd_line_price_source(conn: sqlite3.Connection) -> None:
    """Kolom asal harga baris CBD: `price_source` ('MASTER' = disalin dari
    material_price, 'OVERRIDE' = harga sekali pakai material katalog dengan
    alasan wajib, 'QUOTATION' = harga material proses yang diisi per CBD),
    `material_price_id` (jejak baris harga master yang dipakai),
    `price_override_reason`, dan `price_reference` (no. quotation). Harga yang
    sudah diketik manual sebelum ada master harga dianggap OVERRIDE supaya tidak
    hilang saat CBD di-refresh/direvisi."""
    columns = {row["name"] for row in conn.execute("PRAGMA table_info(cbd_line)").fetchall()}
    if "price_source" not in columns:
        conn.execute(f"ALTER TABLE cbd_line ADD COLUMN price_source TEXT {_PRICE_SOURCE_CHECK}")
        conn.execute("ALTER TABLE cbd_line ADD COLUMN material_price_id TEXT")
        conn.execute("ALTER TABLE cbd_line ADD COLUMN price_override_reason TEXT")
        conn.execute(
            "UPDATE cbd_line SET price_source='OVERRIDE', "
            "price_override_reason='Diinput manual sebelum ada master harga' "
            "WHERE price_original IS NOT NULL"
        )
        conn.commit()
    else:
        _widen_price_source_check(conn)
    if "price_reference" not in columns:
        conn.execute("ALTER TABLE cbd_line ADD COLUMN price_reference TEXT")
        conn.commit()
    _clear_currency_without_price(conn)


def _widen_price_source_check(conn: sqlite3.Connection) -> None:
    """Database yang kolom price_source-nya dibuat sebelum ada 'QUOTATION':
    SQLite tidak bisa mengubah CHECK lewat ALTER, jadi tabel cbd_line dibangun
    ulang dengan definisi yang sama persis kecuali CHECK-nya (tidak ada tabel
    lain yang mereferensikan cbd_line, jadi aman)."""
    sql = conn.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='cbd_line'").fetchone()["sql"]
    if _PRICE_SOURCE_CHECK_OLD not in sql:
        return
    new_sql = sql.replace(_PRICE_SOURCE_CHECK_OLD, _PRICE_SOURCE_CHECK)
    conn.execute("ALTER TABLE cbd_line RENAME TO cbd_line_old")
    conn.execute(new_sql)
    conn.execute("INSERT INTO cbd_line SELECT * FROM cbd_line_old")
    conn.execute("DROP TABLE cbd_line_old")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_cbd_line_revision ON cbd_line(cbd_revision_id)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_cbd_line_material ON cbd_line(material_id)")
    conn.commit()


def _migrate_material_price_method(conn: sqlite3.Connection) -> None:
    """Metode harga material: 'CATALOG' (harga dari master harga per supplier)
    atau 'QUOTATION' (material proses — printing, molding, dst — yang harganya
    tergantung desain/warna, jadi diisi langsung per CBD). Saat kolom ini
    pertama kali dibuat, material berkategori "Proses ..." langsung dijadikan
    QUOTATION."""
    columns = {row["name"] for row in conn.execute("PRAGMA table_info(material)").fetchall()}
    if "price_method" in columns:
        return
    conn.execute(
        "ALTER TABLE material ADD COLUMN price_method TEXT NOT NULL "
        "CHECK (price_method IN ('CATALOG','QUOTATION')) DEFAULT 'CATALOG'"
    )
    conn.execute("UPDATE material SET price_method='QUOTATION' WHERE LOWER(category) LIKE 'proses%'")
    conn.commit()


def _clear_currency_without_price(conn: sqlite3.Connection) -> None:
    """Dulu currency baris CBD baru diisi dari supplier.default_currency walau
    harganya kosong; sekarang currency selalu ikut harga (master/override), jadi
    currency tanpa harga dibersihkan. Idempoten."""
    conn.execute("UPDATE cbd_line SET currency=NULL WHERE price_original IS NULL AND currency IS NOT NULL")
    conn.commit()


def _backfill_material_supplier_links(conn: sqlite3.Connection) -> None:
    """Sekali saja, saat tabel material_supplier masih kosong: bentuk link
    material–supplier dari kombinasi yang sudah dipakai di BOM, langsung
    APPROVED (sudah dipakai sebelum ada proses approval). Database baru tidak
    terpengaruh karena bom_line-nya juga masih kosong."""
    if conn.execute("SELECT 1 FROM material_supplier LIMIT 1").fetchone():
        return
    pairs = conn.execute(
        "SELECT DISTINCT material_id, supplier_id FROM bom_line WHERE supplier_id IS NOT NULL"
    ).fetchall()
    for pair in pairs:
        conn.execute(
            "INSERT INTO material_supplier (id, material_id, supplier_id, status, created_by, updated_by) "
            "VALUES (?,?,?,'APPROVED','MIGRASI','MIGRASI')",
            (new_id(), pair["material_id"], pair["supplier_id"]),
        )
    conn.commit()


def _seed_component_groups(conn: sqlite3.Connection) -> None:
    count = conn.execute("SELECT COUNT(*) c FROM component_group").fetchone()["c"]
    if count > 0:
        return
    for code, name, start, end, sort_order in SEED_COMPONENT_GROUPS:
        conn.execute(
            "INSERT INTO component_group (id, code, name, range_start, range_end, sort_order) "
            "VALUES (?,?,?,?,?,?)",
            (new_id(), code, name, start, end, sort_order),
        )
    conn.commit()
