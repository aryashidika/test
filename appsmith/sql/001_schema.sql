-- ============================================================================
-- 001_schema.sql — Skema PostgreSQL Sistem Specsheet & CBD (untuk Appsmith)
-- Migrasi dari app/schema.sql (SQLite) + kolom tambahan dari migrasi di app/db.py.
--
-- Perbedaan utama dari versi SQLite:
--   * Uang, kurs, yield, usage, loss  -> NUMERIC (bukan TEXT berisi Decimal)
--   * Flag 0/1                        -> BOOLEAN
--   * Tanggal/waktu                   -> DATE / TIMESTAMPTZ
--   * before/after/diff JSON          -> JSONB
--   * Kolom *_normalized              -> GENERATED dari fn_normalize(), tidak diisi aplikasi
--   * ID tetap TEXT (uuid hex 32 char) supaya data SQLite bisa diimpor apa adanya
--
-- Jalankan sekali di database kosong (idempoten: aman diulang).
-- ============================================================================

-- Kunci deteksi duplikat: lowercase, koma desimal -> titik, spasi berulang dirapatkan, trim.
-- Sama dengan app/normalize.py::normalize_text.
CREATE OR REPLACE FUNCTION fn_normalize(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT btrim(regexp_replace(replace(lower(coalesce(p, '')), ',', '.'), '\s+', ' ', 'g'))
$$;

CREATE OR REPLACE FUNCTION fn_new_id() RETURNS text
LANGUAGE sql VOLATILE AS $$
    SELECT replace(gen_random_uuid()::text, '-', '')
$$;

-- ---------------------------------------------------------------- Master data

CREATE TABLE IF NOT EXISTS component_group (
    id          text PRIMARY KEY DEFAULT fn_new_id(),
    code        text NOT NULL UNIQUE,
    name        text NOT NULL,
    range_start integer NOT NULL,
    range_end   integer NOT NULL,
    sort_order  integer NOT NULL,
    CHECK (range_start <= range_end)
);

CREATE TABLE IF NOT EXISTS component (
    id         text PRIMARY KEY DEFAULT fn_new_id(),
    number     integer NOT NULL UNIQUE,
    name       text NOT NULL,
    group_id   text NOT NULL REFERENCES component_group(id),
    status     text NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS material (
    id                   text PRIMARY KEY DEFAULT fn_new_id(),
    material_code        text NOT NULL UNIQUE,
    name                 text NOT NULL,
    name_normalized      text GENERATED ALWAYS AS (fn_normalize(name)) STORED,
    category             text NOT NULL,
    thickness            text,
    thickness_normalized text GENERATED ALWAYS AS (fn_normalize(thickness)) STORED,
    uom                  text NOT NULL,
    -- CATALOG = harga dari master harga per supplier; QUOTATION = material proses, harga diisi per CBD
    price_method         text NOT NULL DEFAULT 'CATALOG' CHECK (price_method IN ('CATALOG','QUOTATION')),
    status               text NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')),
    merged_into_id       text REFERENCES material(id),
    created_by           text,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_by           text,
    updated_at           timestamptz NOT NULL DEFAULT now(),
    UNIQUE (name_normalized, thickness_normalized, uom)
);

CREATE TABLE IF NOT EXISTS material_attachment (
    id            text PRIMARY KEY DEFAULT fn_new_id(),
    material_id   text NOT NULL REFERENCES material(id),
    file_path     text NOT NULL,
    original_name text NOT NULL,
    uploaded_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS supplier (
    id               text PRIMARY KEY DEFAULT fn_new_id(),
    name             text NOT NULL UNIQUE,
    default_currency text NOT NULL DEFAULT 'IDR' CHECK (default_currency IN ('IDR','USD')),
    status           text NOT NULL DEFAULT 'APPROVED' CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')),
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_log (
    id          text PRIMARY KEY DEFAULT fn_new_id(),
    user_email  text,
    user_role   text NOT NULL,
    entity      text NOT NULL,
    entity_id   text NOT NULL,
    action      text NOT NULL,
    before_json jsonb,
    after_json  jsonb,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_material_status  ON material(status);
CREATE INDEX IF NOT EXISTS idx_component_status ON component(status);
CREATE INDEX IF NOT EXISTS idx_audit_entity     ON audit_log(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_created    ON audit_log(created_at DESC);

-- ---------------------------------------------------------------- Model & Specsheet

CREATE TABLE IF NOT EXISTS product_model (
    id           text PRIMARY KEY DEFAULT fn_new_id(),
    code         text NOT NULL UNIQUE,
    name         text NOT NULL,
    factory      text,
    category     text,
    outsole_mold text,
    last_no      text,
    construction text,
    size_range   text,
    sample_size  text,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS specsheet (
    id       text PRIMARY KEY DEFAULT fn_new_id(),
    model_id text NOT NULL REFERENCES product_model(id),
    season   text NOT NULL,
    UNIQUE (model_id, season)
);

CREATE TABLE IF NOT EXISTS specsheet_revision (
    id                 text PRIMARY KEY DEFAULT fn_new_id(),
    specsheet_id       text NOT NULL REFERENCES specsheet(id),
    stage              text NOT NULL CHECK (stage IN ('PULL','SMS','GTM','PROD')),
    revision_no        integer NOT NULL,
    status             text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','PUBLISHED')),
    source_revision_id text REFERENCES specsheet_revision(id),
    published_at       timestamptz,
    published_by       text,
    created_at         timestamptz NOT NULL DEFAULT now(),
    UNIQUE (specsheet_id, stage, revision_no)
);

CREATE TABLE IF NOT EXISTS article (
    id           text PRIMARY KEY DEFAULT fn_new_id(),
    specsheet_id text NOT NULL REFERENCES specsheet(id),
    code         text NOT NULL,
    colorway     text NOT NULL,
    UNIQUE (specsheet_id, code)
);

CREATE TABLE IF NOT EXISTS revision_article (
    revision_id text NOT NULL REFERENCES specsheet_revision(id),
    article_id  text NOT NULL REFERENCES article(id),
    status      text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','DROPPED')),
    PRIMARY KEY (revision_id, article_id)
);

CREATE TABLE IF NOT EXISTS bom_line (
    id                   text PRIMARY KEY DEFAULT fn_new_id(),
    revision_id          text NOT NULL REFERENCES specsheet_revision(id),
    line_key             text NOT NULL,
    origin_line_key      text,
    replaces_line_key    text,
    component_id         text REFERENCES component(id),
    local_component_no   integer,
    local_component_name text,
    parent_line_key      text,
    sub_seq              integer,
    sub_name             text,
    material_id          text NOT NULL REFERENCES material(id),
    supplier_id          text REFERENCES supplier(id),
    process              text,
    is_active            boolean NOT NULL DEFAULT true,
    sort_order           integer NOT NULL,
    UNIQUE (revision_id, line_key)
);

-- Satu sel per (baris BOM, article). is_used diturunkan dari color (kosong / "none" = tidak dipakai).
CREATE TABLE IF NOT EXISTS bom_cell (
    bom_line_id text NOT NULL REFERENCES bom_line(id),
    article_id  text NOT NULL REFERENCES article(id),
    color       text,
    is_used     boolean NOT NULL DEFAULT false,
    PRIMARY KEY (bom_line_id, article_id)
);

CREATE TABLE IF NOT EXISTS change_log (
    id          text PRIMARY KEY DEFAULT fn_new_id(),
    doc_type    text NOT NULL CHECK (doc_type IN ('SPECSHEET','CBD')),
    revision_id text NOT NULL,
    category    text NOT NULL CHECK (category IN
                ('EX_RATE','LOP','AMORTIZATION','MATERIAL','YIELD','COMPONENT','TREATMENT','OTHER')),
    reason      text NOT NULL,
    diff_json   jsonb NOT NULL,
    created_by  text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS specsheet_photo (
    id            text PRIMARY KEY DEFAULT fn_new_id(),
    specsheet_id  text NOT NULL REFERENCES specsheet(id),
    file_path     text NOT NULL,
    original_name text NOT NULL,
    uploaded_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bom_line_revision   ON bom_line(revision_id);
CREATE INDEX IF NOT EXISTS idx_bom_line_parent     ON bom_line(parent_line_key);
CREATE INDEX IF NOT EXISTS idx_bom_cell_line       ON bom_cell(bom_line_id);
CREATE INDEX IF NOT EXISTS idx_revision_specsheet  ON specsheet_revision(specsheet_id);
CREATE INDEX IF NOT EXISTS idx_article_specsheet   ON article(specsheet_id);
CREATE INDEX IF NOT EXISTS idx_change_log_revision ON change_log(doc_type, revision_id);

-- ---------------------------------------------------------------- Master harga

CREATE TABLE IF NOT EXISTS material_supplier (
    id                     text PRIMARY KEY DEFAULT fn_new_id(),
    material_id            text NOT NULL REFERENCES material(id),
    supplier_id            text NOT NULL REFERENCES supplier(id),
    supplier_material_code text,
    is_preferred           boolean NOT NULL DEFAULT false,
    status                 text NOT NULL DEFAULT 'PROPOSED' CHECK (status IN ('PROPOSED','APPROVED','INACTIVE')),
    created_by             text,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_by             text,
    updated_at             timestamptz NOT NULL DEFAULT now(),
    UNIQUE (material_id, supplier_id)
);

-- Harga berbasis periode: valid_from inklusif, valid_to eksklusif (NULL = masih berlaku).
-- color NULL = berlaku untuk semua warna.
CREATE TABLE IF NOT EXISTS material_price (
    id                   text PRIMARY KEY DEFAULT fn_new_id(),
    material_supplier_id text NOT NULL REFERENCES material_supplier(id),
    color                text,
    color_normalized     text GENERATED ALWAYS AS (fn_normalize(color)) STORED,
    price                numeric(18,4) NOT NULL CHECK (price >= 0),
    currency             text NOT NULL CHECK (currency IN ('IDR','USD')),
    valid_from           date NOT NULL,
    valid_to             date,
    reference            text,
    created_by           text,
    created_at           timestamptz NOT NULL DEFAULT now(),
    CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE INDEX IF NOT EXISTS idx_material_supplier_material ON material_supplier(material_id);
CREATE INDEX IF NOT EXISTS idx_material_price_link        ON material_price(material_supplier_id, color_normalized);

-- ---------------------------------------------------------------- CBD

CREATE TABLE IF NOT EXISTS cbd_revision (
    id                     text PRIMARY KEY DEFAULT fn_new_id(),
    article_id             text NOT NULL REFERENCES article(id),
    stage                  text NOT NULL CHECK (stage IN ('PULL','SMS','GTM','PROD')),
    revision_no            integer NOT NULL,
    specsheet_revision_id  text NOT NULL REFERENCES specsheet_revision(id),
    exchange_rate          numeric(18,4),
    status                 text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','PUBLISHED')),
    sync_status            text NOT NULL DEFAULT 'IN_SYNC' CHECK (sync_status IN ('IN_SYNC','NEEDS_REVISION')),
    amortization           numeric(18,4) NOT NULL DEFAULT 0,
    adjustment             numeric(18,4) NOT NULL DEFAULT 0,
    selling_price          numeric(18,4),
    target_fob             numeric(18,4),
    source_cbd_revision_id text REFERENCES cbd_revision(id),
    published_at           timestamptz,
    published_by           text,
    created_at             timestamptz NOT NULL DEFAULT now(),
    UNIQUE (article_id, stage, revision_no)
);

CREATE TABLE IF NOT EXISTS cbd_line (
    id                    text PRIMARY KEY DEFAULT fn_new_id(),
    cbd_revision_id       text NOT NULL REFERENCES cbd_revision(id),
    line_key              text NOT NULL,
    component_id          text REFERENCES component(id),
    local_component_no    integer,
    sub_seq               integer,
    sub_name              text,
    material_id           text NOT NULL REFERENCES material(id),
    color                 text,
    supplier_id           text REFERENCES supplier(id),
    uom                   text NOT NULL,
    yield_value           numeric(18,6),
    usage_value           numeric(18,6),
    loss_pct              numeric(9,4),
    price_original        numeric(18,4),
    currency              text CHECK (currency IN ('IDR','USD')),
    -- MASTER = disalin dari material_price; OVERRIDE = harga sekali pakai (alasan wajib);
    -- QUOTATION = material proses, harga diisi per CBD
    price_source          text CHECK (price_source IN ('MASTER','OVERRIDE','QUOTATION')),
    material_price_id     text REFERENCES material_price(id),
    price_override_reason text,
    price_reference       text,
    status                text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','MISSING_IN_SPEC')),
    value_origin          text NOT NULL DEFAULT 'INPUT' CHECK (value_origin IN ('INPUT','COPIED','CARRIED_FROM_REPLACED')),
    value_source_ref      text,
    group_code            text NOT NULL,
    sort_order            integer NOT NULL,
    UNIQUE (cbd_revision_id, line_key),
    CHECK (currency IS NULL OR price_original IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_cbd_line_revision    ON cbd_line(cbd_revision_id);
CREATE INDEX IF NOT EXISTS idx_cbd_revision_article ON cbd_revision(article_id);
CREATE INDEX IF NOT EXISTS idx_cbd_line_material    ON cbd_line(material_id);

-- ---------------------------------------------------------------- Pengguna & hak akses
-- Login ditangani Appsmith (akun Appsmith). Tabel ini memetakan email login -> role aplikasi.

CREATE TABLE IF NOT EXISTS app_user (
    email      text PRIMARY KEY CHECK (email = lower(email)),
    full_name  text NOT NULL,
    role       text NOT NULL CHECK (role IN
               ('MASTER_ADMIN','VENDOR_SPEC','VENDOR_CBD','BRAND_VIEWER','SYSTEM_ADMIN')),
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS role_permission (
    role       text NOT NULL,
    permission text NOT NULL,
    PRIMARY KEY (role, permission)
);
