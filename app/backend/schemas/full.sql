-- labelsage-full.sqlite: the whole cleaned product database, readable, on the build machine only.
-- Built by app/backend/etl in the same run as catalog.sqlite. catalog.sqlite (catalog.sql) is a slim export of it
-- for the phone: whole-number nutrients, compressed ingredients, no source records or audit tables.

CREATE TABLE build_info (key TEXT PRIMARY KEY, value TEXT);

-- ---------- the merged products ----------

-- one row per barcode; every column except gtin can be NULL ("unknown")
CREATE TABLE product (
    gtin               INTEGER PRIMARY KEY,   -- GTIN-14 as a number
    barcode            TEXT NOT NULL,         -- 13 digits, as scanners report it
    name               TEXT,
    brand              TEXT,
    category           TEXT,
    size               TEXT,                  -- package size as printed
    serving_size       REAL,
    serving_unit       TEXT,                  -- g or ml
    toddler_serving    INTEGER,               -- 1 = FDC lists a serving for ages 1-3
    discontinued       INTEGER,
    nova_group         INTEGER,
    image_url          TEXT,                  -- Amazon MAIN image of an accepted match, else the OFF photo when
                                              -- off_match_tier = accept (or the product is OFF-only)
    in_fdc             INTEGER,               -- 1 = FDC Branded Foods has this barcode
    in_off             INTEGER,               -- 1 = Open Food Facts has this barcode
    is_recall_stub     INTEGER,               -- 1 = known only from a recall
    has_recall         INTEGER,
    off_match_tier     TEXT,                  -- OFF record vs FDC on the same barcode: accept, review or reject
    off_match_confidence REAL,                -- 0..1 from match/matcher.py (method same_barcode)
    fdc_updated        TEXT,                  -- FDC publication date
    off_updated        TEXT,                  -- OFF last edit date
    confidence         INTEGER,               -- 0 low, 1 medium, 2 high
    recipe_changed     INTEGER,               -- 1 = FDC and OFF food words differ: nutrients may be from an old recipe
    unique_scans       INTEGER,               -- Open Food Facts scans: picks the phone's starter catalog
    on_phone           INTEGER,               -- 1 = in this week's phone catalog
    region             TEXT,                  -- us, id (Indonesia) or us,id
    category_source    TEXT,                  -- fdc, off, or name (Indonesian name keywords)
    brand_owner        TEXT,                  -- FDC brand_owner, the company ("Kellanova" for Pringles)
    image_source       TEXT,                  -- amazon (accepted match in amazon.sqlite) or off
    amazon_asin        TEXT                   -- the matched Amazon item, when there is one
);

-- every photo of a product in display order: the images of its matched Amazon item (MAIN first), else the
-- one OFF photo; product.image_url is rank 0
CREATE TABLE product_image (
    gtin    INTEGER NOT NULL REFERENCES product(gtin),
    rank    INTEGER NOT NULL,                 -- 0 = main photo
    url     TEXT NOT NULL,
    source  TEXT NOT NULL,                    -- amazon or off
    variant TEXT,                             -- Amazon image variant: MAIN, PT01..PT08
    width   INTEGER,
    height  INTEGER,
    PRIMARY KEY (gtin, rank)
);

-- nutrients per 100 g (or 100 ml), as decimals
CREATE TABLE nutrient (
    gtin             INTEGER PRIMARY KEY REFERENCES product(gtin),
    energy_kcal      REAL, protein_g REAL, carbs_g REAL, sugar_g REAL, added_sugar_g REAL, fiber_g REAL,
    fat_g            REAL, sat_fat_g REAL, trans_fat_g REAL, sodium_mg REAL, cholesterol_mg REAL, potassium_mg REAL,
    from_off         TEXT                    -- nutrients that came from OFF because FDC had none, e.g. "fiber_g,sodium_mg"
);

-- the ingredient list as printed, and which record it came from (the newest one)
CREATE TABLE ingredients (
    gtin         INTEGER PRIMARY KEY REFERENCES product(gtin),
    text         TEXT NOT NULL,
    source       TEXT NOT NULL,              -- fdc or off
    source_date  TEXT,
    language     TEXT,                       -- id, en or other, from the words of the list
    looks_ok     INTEGER                     -- 0 = failed the quality gate (codes, broken scans); hidden on the phone
);

-- ---------- audit: which source won, and what lost ----------

-- the winning source of each merged field
CREATE TABLE product_field_source (
    gtin    INTEGER REFERENCES product(gtin),
    field   TEXT,                            -- name, brand, category, ingredients, serving_size
    source  TEXT,                            -- fdc or off
    PRIMARY KEY (gtin, field)
);

-- the losing value when FDC and OFF disagree (nutrients differ by more than 5%)
CREATE TABLE merge_conflict (
    gtin           INTEGER REFERENCES product(gtin),
    field          TEXT,
    winner_source  TEXT,
    winner_value   TEXT,
    loser_source   TEXT,
    loser_value    TEXT,
    PRIMARY KEY (gtin, field)
);

-- ---------- each source, cleaned, before the merge ----------

CREATE TABLE source_fdc (
    gtin INTEGER PRIMARY KEY, fdc_id INTEGER, name TEXT, brand TEXT, category TEXT, ingredients TEXT,
    serving_size REAL, serving_unit TEXT, size TEXT, discontinued INTEGER, updated TEXT,
    energy_kcal REAL, protein_g REAL, carbs_g REAL, sugar_g REAL, added_sugar_g REAL, fiber_g REAL,
    fat_g REAL, sat_fat_g REAL, trans_fat_g REAL, sodium_mg REAL, cholesterol_mg REAL, potassium_mg REAL
);

CREATE TABLE source_off (
    gtin INTEGER PRIMARY KEY, name TEXT, brand TEXT, category TEXT, ingredients TEXT,
    serving_size REAL, size TEXT, nova_group INTEGER, image_url TEXT, updated TEXT,
    energy_kcal REAL, protein_g REAL, carbs_g REAL, sugar_g REAL, added_sugar_g REAL, fiber_g REAL,
    fat_g REAL, sat_fat_g REAL, trans_fat_g REAL, sodium_mg REAL, cholesterol_mg REAL, potassium_mg REAL
);

-- ---------- recalls and natural foods ----------

CREATE TABLE recall (
    recall_number TEXT PRIMARY KEY, report_date TEXT, class INTEGER, ongoing INTEGER,
    reason TEXT, product_description TEXT
);

CREATE TABLE recall_link (
    recall_number TEXT REFERENCES recall(recall_number),
    gtin          INTEGER,
    PRIMARY KEY (recall_number, gtin)
);

-- natural foods without a barcode (FDC Foundation and SR Legacy), per 100 g
CREATE TABLE generic_food (
    fdc_id INTEGER PRIMARY KEY, name TEXT NOT NULL, category TEXT,
    energy_kcal REAL, protein_g REAL, carbs_g REAL, sugar_g REAL, added_sugar_g REAL, fiber_g REAL,
    fat_g REAL, sat_fat_g REAL, trans_fat_g REAL, sodium_mg REAL, cholesterol_mg REAL, potassium_mg REAL
);

-- ---------- input for the Amazon match step (app/backend/etl/match) ----------

-- US products with a name, most-scanned first; ingredients only when they passed the quality gate
CREATE VIEW match_input AS
    SELECT printf('%014d', p.gtin) AS gtin, p.name, p.brand, p.brand_owner,
           CASE WHEN i.looks_ok = 1 THEN i.text END AS ingredients, p.unique_scans
    FROM product p LEFT JOIN ingredients i USING (gtin)
    WHERE p.is_recall_stub = 0 AND p.name IS NOT NULL AND p.region LIKE '%us%'
    ORDER BY coalesce(p.unique_scans, 0) DESC;

CREATE INDEX idx_product_name ON product(name);
CREATE INDEX idx_recall_link_gtin ON recall_link(gtin);
