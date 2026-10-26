-- catalog.sqlite: the read-only US product catalog the phone downloads every week.
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
    flags         INTEGER DEFAULT 0,     -- bits: 1 recall-only stub, 2 discontinued, 4 toddler serving
    sources       INTEGER DEFAULT 0,     -- bits: 1 FDC, 2 OFF, 4 openFDA recall
    nova          INTEGER,
    image         TEXT,                  -- OFF image file name; folder = last 13 barcode digits split 3/3/3/4
    updated       INTEGER                -- newest source date, days since 1970-01-01
);

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

-- natural foods without a barcode (FDC Foundation and SR Legacy), found by name; same units as nutrient
CREATE TABLE generic_food (
    fdc_id INTEGER PRIMARY KEY, name TEXT NOT NULL, category_id INTEGER,
    kcal INTEGER, protein_cg INTEGER, carbs_cg INTEGER, sugar_cg INTEGER, added_sugar_cg INTEGER,
    fiber_cg INTEGER, fat_cg INTEGER, sat_fat_cg INTEGER, trans_fat_cg INTEGER,
    sodium_mg INTEGER, cholesterol_mg INTEGER, potassium_mg INTEGER
);
