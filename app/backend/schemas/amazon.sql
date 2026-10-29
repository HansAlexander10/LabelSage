-- amazon.sqlite: Amazon SP-API lookups and matches. Its own file (extract.AMAZON_DB), kept across weekly builds,
-- because every row cost an API call. Filled by app/backend/etl/match; the build only reads product_amazon.
-- A product never depends on a match: product rows exist with or without one.
--
-- Fixes against the first draft schema:
--   * product rows are not gated on Amazon: no NOT NULL asin / image, no CHECK (confidence >= 0.85)
--   * one barcode can map to many ASINs and one ASIN to many barcodes (identifier table, candidate table)
--   * every scored candidate is kept with its tier and reasons, not only the accepted ones (evals, audit)
--   * "not tried" and "tried, no hit" are different: amazon_lookup records every request
--   * the matcher version is stored, so a rule change can re-score without re-fetching

-- ---------- what we asked Amazon ----------

-- one row per request; a barcode with no row here was never looked up
CREATE TABLE amazon_lookup (
    lookup_id       INTEGER PRIMARY KEY,
    gtin            INTEGER NOT NULL,        -- product.gtin we were looking for
    method          TEXT NOT NULL,           -- barcode or name_brand
    query           TEXT NOT NULL,           -- the identifier sent, or the keywords + brand
    marketplace_id  TEXT NOT NULL,           -- ATVPDKIKX0DER = amazon.com
    http_status     INTEGER,
    candidates      INTEGER NOT NULL DEFAULT 0,
    requested_at    TEXT NOT NULL            -- ISO time
);

-- the items each request returned, in Amazon's order (a name_brand search lists items that may not carry our barcode)
CREATE TABLE amazon_lookup_item (
    lookup_id       INTEGER NOT NULL,        -- amazon_lookup.lookup_id
    asin            TEXT NOT NULL,
    marketplace_id  TEXT NOT NULL,
    rank            INTEGER NOT NULL,        -- 0 = first result
    PRIMARY KEY (lookup_id, asin)
);

-- ---------- what Amazon has ----------

-- one row per ASIN and marketplace, from summaries/productTypes/relationships; attributes only if our account gets them
CREATE TABLE amazon_item (
    asin                 TEXT NOT NULL,
    marketplace_id       TEXT NOT NULL,
    item_name            TEXT,
    brand                TEXT,
    manufacturer         TEXT,
    product_type         TEXT,               -- e.g. GROCERY
    item_classification  TEXT,               -- BASE_PRODUCT, VARIATION_PARENT, PRODUCT_BUNDLE
    parent_asin          TEXT,
    package_quantity     INTEGER,            -- 3 for "Pack of 3"
    size_name            TEXT,
    ingredients_text     TEXT,               -- attributes.ingredients, NULL when not returned
    allergen_info        TEXT,               -- attributes.allergen_information, comma joined
    fetched_at           TEXT NOT NULL,
    raw_json             TEXT NOT NULL,      -- the whole item as returned; check Amazon's terms before keeping it long term
    PRIMARY KEY (asin, marketplace_id)
);

-- every barcode Amazon lists for an ASIN (many-to-many)
CREATE TABLE amazon_item_identifier (
    asin             TEXT NOT NULL,
    marketplace_id   TEXT NOT NULL,
    identifier_type  TEXT NOT NULL,          -- UPC, EAN, GTIN, ...
    identifier       TEXT NOT NULL,          -- as returned
    gtin             INTEGER,                -- GTIN-14 (shared/barcode.py), NULL when not a valid barcode
    PRIMARY KEY (asin, marketplace_id, identifier_type, identifier)
);

-- the largest image of each variant (MAIN, PT01..PT08, SWCH swatch); links only, no downloaded files.
-- The phone gets them in catalog.product_image (MAIN first, no swatch)
CREATE TABLE amazon_image (
    asin            TEXT NOT NULL,
    marketplace_id  TEXT NOT NULL,
    variant         TEXT NOT NULL,
    url             TEXT NOT NULL,
    width           INTEGER,
    height          INTEGER,
    PRIMARY KEY (asin, marketplace_id, variant)
);

-- ---------- how sure we are ----------

-- every scored (barcode, ASIN) pair, per matcher version
CREATE TABLE amazon_match (
    gtin             INTEGER NOT NULL,
    asin             TEXT NOT NULL,
    marketplace_id   TEXT NOT NULL,
    matcher_version  TEXT NOT NULL,
    method           TEXT NOT NULL,          -- barcode (Amazon lists our barcode) or name_brand
    brand_score      REAL,                   -- NULL when a brand is missing on either side
    title_score      REAL NOT NULL,
    penalty          REAL NOT NULL,
    confidence       REAL NOT NULL,          -- 0..1
    tier             TEXT NOT NULL,          -- accept, review or reject
    reasons          TEXT NOT NULL,          -- JSON list, e.g. ["claim_conflict:gluten"]
    scored_at        TEXT NOT NULL,
    PRIMARY KEY (gtin, asin, marketplace_id, matcher_version)
);

-- the one ASIN we use per product: an accepted match, or a review someone approved
CREATE TABLE product_amazon (
    gtin             INTEGER PRIMARY KEY,    -- product.gtin
    asin             TEXT NOT NULL,
    marketplace_id   TEXT NOT NULL,
    matcher_version  TEXT NOT NULL,
    method           TEXT NOT NULL,
    confidence       REAL NOT NULL,
    decided_by       TEXT NOT NULL,          -- matcher, or the reviewer's name
    image_url        TEXT,                   -- best MAIN image; all images: amazon_image by asin
    decided_at       TEXT NOT NULL
);

-- ---------- evals ----------

-- one row per eval run and threshold, so results can be compared across matcher versions
CREATE TABLE match_eval (
    run_at           TEXT NOT NULL,
    matcher_version  TEXT NOT NULL,
    dataset          TEXT NOT NULL,          -- e.g. synthetic-2026-10-28, or a hand-labelled real sample
    method           TEXT NOT NULL,          -- barcode, name_brand or all
    threshold        REAL NOT NULL,
    tp INTEGER, fp INTEGER, tn INTEGER, fn INTEGER,
    accuracy REAL, precision REAL, recall REAL, f1 REAL,
    PRIMARY KEY (run_at, method, threshold)
);

CREATE INDEX idx_amazon_lookup_gtin ON amazon_lookup(gtin);
CREATE INDEX idx_amazon_identifier_gtin ON amazon_item_identifier(gtin);
CREATE INDEX idx_amazon_match_tier ON amazon_match(tier);
