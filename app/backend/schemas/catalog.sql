-- catalog.sqlite: the read-only starter catalog the phone downloads every week: every recalled product plus the
-- most-scanned products, under 60 MB. The server holds the whole catalog for everything else.
-- Built by app/backend/etl (load phase). Design and merge rules: app/backend/etl/README.md.
-- Allergens are not stored: the app's LabelSageCore parses the ingredients text itself.

CREATE TABLE catalog_meta (key TEXT PRIMARY KEY, value TEXT);

CREATE TABLE brand    (brand_id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE category (category_id INTEGER PRIMARY KEY, name TEXT NOT NULL, parent_id INTEGER);

-- one row per barcode; every column except gtin can be NULL ("unknown")
CREATE TABLE product (
    gtin          INTEGER PRIMARY KEY,   -- GTIN-14 as a number
    name          TEXT,
    brand_id      INTEGER,
    category_id   INTEGER,
    size          TEXT,                  -- package size as printed, e.g. "18 oz (510 g)"
    serving_size  REAL,                  -- grams, or ml when basis_ml = 1
    basis_ml      INTEGER DEFAULT 0,     -- 1 = nutrients per 100 ml
    flags         INTEGER DEFAULT 0,     -- bits: 1 recall-only stub, 2 discontinued, 4 toddler serving,
                                         --       8 recipe may have changed (FDC and OFF food words differ)
    sources       INTEGER DEFAULT 0,     -- bits: 1 FDC, 2 OFF, 4 openFDA recall
    nova          INTEGER,
    image         TEXT,                  -- full Amazon image URL (matched), or OFF image file name;
                                         -- OFF folder = last 13 barcode digits split 3/3/3/4
    confidence    INTEGER,               -- 0 low, 1 medium, 2 high
    region        TEXT,                  -- us, id (Indonesia) or us,id
    fdc_date      INTEGER,               -- FDC publication date, days since 1970-01-01
    off_date      INTEGER                -- Open Food Facts last edit, days since 1970-01-01
);

-- more photos of a product, from its matched Amazon item, in display order (rank 0 = MAIN = product.image).
-- image = the file name after catalog_meta.amazon_image_prefix (https://m.media-amazon.com/images/I/), or a full
-- https URL when Amazon used another host; products without an Amazon match have no rows (one photo: product.image)
CREATE TABLE product_image (gtin INTEGER, rank INTEGER, image TEXT NOT NULL, PRIMARY KEY (gtin, rank)) WITHOUT ROWID;

-- nutrients per 100 g (or 100 ml) as whole numbers: *_cg = hundredths of a gram, *_mg = mg, kcal = kcal
CREATE TABLE nutrient (
    gtin INTEGER PRIMARY KEY,
    kcal INTEGER, protein_cg INTEGER, carbs_cg INTEGER, sugar_cg INTEGER, added_sugar_cg INTEGER,
    fiber_cg INTEGER, fat_cg INTEGER, sat_fat_cg INTEGER, trans_fat_cg INTEGER,
    sodium_mg INTEGER, cholesterol_mg INTEGER, potassium_mg INTEGER,
    from_off_mask INTEGER DEFAULT 0      -- bit per nutrient (order above) when the value came from OFF
);

-- the ingredient list as printed, zlib-compressed with the shared dictionary below;
-- the app unpacks one product at a time (zlib inflate with inflateSetDictionary)
CREATE TABLE ingredients (gtin INTEGER PRIMARY KEY, text_z BLOB NOT NULL, from_off INTEGER);
CREATE TABLE zlib_dictionary (id INTEGER PRIMARY KEY, dict BLOB NOT NULL);

CREATE TABLE recall (
    recall_number TEXT PRIMARY KEY, report_date INTEGER, class INTEGER, ongoing INTEGER, reason TEXT
);
CREATE TABLE recall_link (gtin INTEGER, recall_number TEXT, PRIMARY KEY (gtin, recall_number)) WITHOUT ROWID;

