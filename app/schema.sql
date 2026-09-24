-- Skema M1: fondasi + master data (komponen, material, supplier, audit log).
-- Tabel specsheet/CBD (M2-M4) dan master harga ada di bagian bawah file.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS component_group (
    id          TEXT PRIMARY KEY,
    code        TEXT NOT NULL UNIQUE,
    name        TEXT NOT NULL,
    range_start INTEGER NOT NULL,
    range_end   INTEGER NOT NULL,
    sort_order  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS component (
    id         TEXT PRIMARY KEY,
    number     INTEGER NOT NULL UNIQUE,
    name       TEXT NOT NULL,
    group_id   TEXT NOT NULL REFERENCES component_group(id),
    status     TEXT NOT NULL CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')) DEFAULT 'PROPOSED',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS material (
    id              TEXT PRIMARY KEY,
    material_code   TEXT NOT NULL UNIQUE,
    name            TEXT NOT NULL,
    name_normalized TEXT NOT NULL,
    category        TEXT NOT NULL,
    thickness       TEXT,
    thickness_normalized TEXT NOT NULL DEFAULT '',
    uom             TEXT NOT NULL,
    status          TEXT NOT NULL CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')) DEFAULT 'PROPOSED',
    merged_into_id  TEXT REFERENCES material(id),
    created_by      TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_by      TEXT,
    updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (name_normalized, thickness_normalized, uom)
);

CREATE TABLE IF NOT EXISTS material_attachment (
    id            TEXT PRIMARY KEY,
    material_id   TEXT NOT NULL REFERENCES material(id),
    file_path     TEXT NOT NULL,
    original_name TEXT NOT NULL,
    uploaded_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Supplier berdiri sendiri: tidak dipasangkan ke Material di master data.
-- Supplier dipilih langsung per baris BOM di specsheet ("Source of Material").
CREATE TABLE IF NOT EXISTS supplier (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL UNIQUE,
    status     TEXT NOT NULL CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')) DEFAULT 'APPROVED',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS audit_log (
    id          TEXT PRIMARY KEY,
    user_role   TEXT NOT NULL,
    entity      TEXT NOT NULL,
    entity_id   TEXT NOT NULL,
    action      TEXT NOT NULL,
    before_json TEXT,
    after_json  TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_material_status ON material(status);
CREATE INDEX IF NOT EXISTS idx_component_status ON component(status);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log(entity, entity_id);

-- ============================================================
-- M2: Specsheet (Model, Specsheet, Revisi, Article, BOM, Foto)
-- ============================================================

-- Model sepatu. "factory" adalah teks bebas (bukan master data) — hanya vendor/factory
-- untuk material yang dikelola sebagai master data (Supplier di atas).
-- Satu Model dapat hidup di lebih dari satu season; SKU/colorway (Article) ada per season.
CREATE TABLE IF NOT EXISTS product_model (
    id           TEXT PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE,
    name         TEXT NOT NULL,
    factory      TEXT,
    category     TEXT,
    outsole_mold TEXT,
    last_no      TEXT,
    construction TEXT,
    size_range   TEXT,
    sample_size  TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS specsheet (
    id       TEXT PRIMARY KEY,
    model_id TEXT NOT NULL REFERENCES product_model(id),
    season   TEXT NOT NULL,
    UNIQUE (model_id, season)
);

CREATE TABLE IF NOT EXISTS specsheet_revision (
    id                 TEXT PRIMARY KEY,
    specsheet_id       TEXT NOT NULL REFERENCES specsheet(id),
    stage              TEXT NOT NULL CHECK (stage IN ('PULL','SMS','GTM','PROD')),
    revision_no        INTEGER NOT NULL,
    status             TEXT NOT NULL CHECK (status IN ('DRAFT','PUBLISHED')) DEFAULT 'DRAFT',
    source_revision_id TEXT REFERENCES specsheet_revision(id),
    published_at       TEXT,
    published_by       TEXT,
    created_at         TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (specsheet_id, stage, revision_no)
);

CREATE TABLE IF NOT EXISTS article (
    id           TEXT PRIMARY KEY,
    specsheet_id TEXT NOT NULL REFERENCES specsheet(id),
    code         TEXT NOT NULL,
    colorway     TEXT NOT NULL,
    UNIQUE (specsheet_id, code)
);

CREATE TABLE IF NOT EXISTS revision_article (
    revision_id TEXT NOT NULL REFERENCES specsheet_revision(id),
    article_id  TEXT NOT NULL REFERENCES article(id),
    status      TEXT NOT NULL CHECK (status IN ('ACTIVE','DROPPED')) DEFAULT 'ACTIVE',
    PRIMARY KEY (revision_id, article_id)
);

-- Setiap baris BOM boleh punya Supplier ("Source of Material") sendiri — dipilih
-- langsung di specsheet, tidak lagi lewat relasi Material-Supplier di master data.
CREATE TABLE IF NOT EXISTS bom_line (
    id                    TEXT PRIMARY KEY,
    revision_id           TEXT NOT NULL REFERENCES specsheet_revision(id),
    line_key              TEXT NOT NULL,
    origin_line_key       TEXT,
    replaces_line_key     TEXT,
    component_id          TEXT REFERENCES component(id),
    local_component_no    INTEGER,
    local_component_name  TEXT,
    parent_line_key       TEXT,
    sub_seq               INTEGER,
    sub_name              TEXT,
    material_id            TEXT NOT NULL REFERENCES material(id),
    supplier_id             TEXT REFERENCES supplier(id),
    process                TEXT,
    is_active              INTEGER NOT NULL DEFAULT 1,
    sort_order             INTEGER NOT NULL,
    UNIQUE (revision_id, line_key)
);

-- Satu kolom per article/colorway: "color" adalah nilai teks yang ditampilkan (mis. nama
-- warna material). "is_used" diturunkan otomatis dari nilai itu (kosong / "none" = tidak
-- dipakai pada colorway tsb) — lihat app.domain.bom_service.update_cell_value.
CREATE TABLE IF NOT EXISTS bom_cell (
    bom_line_id TEXT NOT NULL REFERENCES bom_line(id),
    article_id  TEXT NOT NULL REFERENCES article(id),
    color       TEXT,
    is_used     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (bom_line_id, article_id)
);

CREATE TABLE IF NOT EXISTS change_log (
    id          TEXT PRIMARY KEY,
    doc_type    TEXT NOT NULL CHECK (doc_type IN ('SPECSHEET','CBD')),
    revision_id TEXT NOT NULL,
    category    TEXT NOT NULL CHECK (category IN
                 ('EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER')),
    reason      TEXT NOT NULL,
    diff_json   TEXT NOT NULL,
    created_by  TEXT NOT NULL,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS specsheet_photo (
    id            TEXT PRIMARY KEY,
    specsheet_id  TEXT NOT NULL REFERENCES specsheet(id),
    file_path     TEXT NOT NULL,
    original_name TEXT NOT NULL,
    uploaded_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_bom_line_revision ON bom_line(revision_id);
CREATE INDEX IF NOT EXISTS idx_bom_line_parent ON bom_line(parent_line_key);
CREATE INDEX IF NOT EXISTS idx_bom_cell_line ON bom_cell(bom_line_id);
CREATE INDEX IF NOT EXISTS idx_revision_specsheet ON specsheet_revision(specsheet_id);
CREATE INDEX IF NOT EXISTS idx_article_specsheet ON article(specsheet_id);

-- ============================================================
-- M3: CBD (Cost Breakdown)
-- ============================================================
-- Uang & kuantitas disimpan sebagai TEXT berisi representasi Decimal kanonik
-- (bukan REAL/float) — dikonversi ke/dari Python Decimal di app/domain/cbd_calc.py
-- dan app/domain/cbd_service.py. `supplier.default_currency` ditambahkan lewat
-- migrasi idempoten di app/db.py (ALTER TABLE tidak aman dijalankan berulang).

CREATE TABLE IF NOT EXISTS cbd_revision (
    id                     TEXT PRIMARY KEY,
    article_id             TEXT NOT NULL REFERENCES article(id),
    stage                  TEXT NOT NULL CHECK (stage IN ('PULL','SMS','GTM','PROD')),
    revision_no            INTEGER NOT NULL,
    specsheet_revision_id  TEXT NOT NULL REFERENCES specsheet_revision(id),
    exchange_rate          TEXT,
    status                 TEXT NOT NULL CHECK (status IN ('DRAFT','PUBLISHED')) DEFAULT 'DRAFT',
    sync_status            TEXT NOT NULL CHECK (sync_status IN ('IN_SYNC','NEEDS_REVISION')) DEFAULT 'IN_SYNC',
    amortization           TEXT NOT NULL DEFAULT '0',
    adjustment             TEXT NOT NULL DEFAULT '0',
    selling_price          TEXT,
    target_fob             TEXT,
    source_cbd_revision_id TEXT REFERENCES cbd_revision(id),
    published_at           TEXT,
    published_by           TEXT,
    created_at             TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (article_id, stage, revision_no)
);

-- lineKey di sini TIDAK unik lintas revisi/stage seperti BomLine.lineKey.
CREATE TABLE IF NOT EXISTS cbd_line (
    id                  TEXT PRIMARY KEY,
    cbd_revision_id     TEXT NOT NULL REFERENCES cbd_revision(id),
    line_key            TEXT NOT NULL,
    component_id        TEXT REFERENCES component(id),
    local_component_no  INTEGER,
    sub_seq             INTEGER,
    sub_name            TEXT,
    material_id         TEXT NOT NULL REFERENCES material(id),
    color               TEXT,
    supplier_id         TEXT REFERENCES supplier(id),
    uom                 TEXT NOT NULL,
    yield_value         TEXT,
    usage_value         TEXT,
    loss_pct            TEXT,
    price_original      TEXT,
    currency            TEXT CHECK (currency IN ('IDR','USD')),
    status              TEXT NOT NULL CHECK (status IN ('ACTIVE','MISSING_IN_SPEC')) DEFAULT 'ACTIVE',
    value_origin        TEXT NOT NULL CHECK (value_origin IN ('INPUT','COPIED','CARRIED_FROM_REPLACED')) DEFAULT 'INPUT',
    value_source_ref    TEXT,
    group_code          TEXT NOT NULL,
    sort_order          INTEGER NOT NULL,
    UNIQUE (cbd_revision_id, line_key)
);

CREATE INDEX IF NOT EXISTS idx_cbd_line_revision ON cbd_line(cbd_revision_id);
CREATE INDEX IF NOT EXISTS idx_cbd_revision_article ON cbd_revision(article_id);
CREATE INDEX IF NOT EXISTS idx_cbd_line_material ON cbd_line(material_id);

-- ============================================================
-- Master harga: Material–Supplier + Harga (tambahan di luar PRD)
-- ============================================================
-- Satu kode material bisa dipasok beberapa supplier. Link material–supplier
-- dimiliki tim specsheet (terbentuk otomatis saat supplier dipilih di BOM,
-- berstatus PROPOSED sampai di-approve Master Admin); harganya dimiliki tim
-- CBD. Kolom harga di cbd_line (price_source, material_price_id,
-- price_override_reason) ditambahkan lewat migrasi di app/db.py.

CREATE TABLE IF NOT EXISTS material_supplier (
    id                     TEXT PRIMARY KEY,
    material_id            TEXT NOT NULL REFERENCES material(id),
    supplier_id            TEXT NOT NULL REFERENCES supplier(id),
    supplier_material_code TEXT,
    is_preferred           INTEGER NOT NULL DEFAULT 0,
    status                 TEXT NOT NULL CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')) DEFAULT 'PROPOSED',
    created_by             TEXT,
    created_at             TEXT NOT NULL DEFAULT (datetime('now')),
    updated_by             TEXT,
    updated_at             TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (material_id, supplier_id)
);

-- Harga berbasis periode: harga baru menutup harga lama (valid_to diisi), tidak
-- menimpanya. color NULL = berlaku untuk semua warna; baris dengan color terisi
-- adalah harga khusus warna tsb. valid_from inklusif, valid_to eksklusif
-- (YYYY-MM-DD). Uang disimpan sebagai TEXT berisi Decimal, sama seperti CBD.
CREATE TABLE IF NOT EXISTS material_price (
    id                   TEXT PRIMARY KEY,
    material_supplier_id TEXT NOT NULL REFERENCES material_supplier(id),
    color                TEXT,
    color_normalized     TEXT NOT NULL DEFAULT '',
    price                TEXT NOT NULL,
    currency             TEXT NOT NULL CHECK (currency IN ('IDR','USD')),
    valid_from           TEXT NOT NULL,
    valid_to             TEXT,
    reference            TEXT,
    created_by           TEXT,
    created_at           TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_material_supplier_material ON material_supplier(material_id);
CREATE INDEX IF NOT EXISTS idx_material_price_link ON material_price(material_supplier_id, color_normalized);
