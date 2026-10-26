"""Transform: turn the raw downloads into one merged US product table, in DuckDB.

The phases follow the team's ETL board: Part 1 barcodes, Part 2 combine & select,
Part 3 cleanup, Part 4 enrich. Merge rules: app/backend/etl/README.md
"""
from extract import extract
from shared import barcode

# our column -> FDC nutrient ids; the first id a food has wins. FDC amounts are per 100 g (or 100 ml).
FDC_NUTRIENTS = {
    "kcal": (1008, 2047, 2048), "protein_g": (1003,), "carbs_g": (1005,), "sugar_g": (2000, 1063),
    "added_sugar_g": (1235,), "fiber_g": (1079,), "fat_g": (1004,), "sat_fat_g": (1258,),
    "trans_fat_g": (1257,), "sodium_mg": (1093,), "cholesterol_mg": (1253,), "potassium_mg": (1092,),
}
# our column -> (OFF CSV column, factor to our unit). OFF stores sodium, cholesterol and potassium in g.
OFF_NUTRIENTS = {
    "kcal": ("energy-kcal_100g", 1), "protein_g": ("proteins_100g", 1), "carbs_g": ("carbohydrates_100g", 1),
    "sugar_g": ("sugars_100g", 1), "added_sugar_g": ("added-sugars_100g", 1), "fiber_g": ("fiber_100g", 1),
    "fat_g": ("fat_100g", 1), "sat_fat_g": ("saturated-fat_100g", 1), "trans_fat_g": ("trans-fat_100g", 1),
    "sodium_mg": ("sodium_100g", 1000), "cholesterol_mg": ("cholesterol_100g", 1000),
    "potassium_mg": ("potassium_100g", 1000),
}
NUTRIENTS = list(FDC_NUTRIENTS)
# the highest believable value per 100 g; anything above is a typo and becomes unknown
NUTRIENT_MAX = {"kcal": 900, "sodium_mg": 40_000, "cholesterol_mg": 5_000, "potassium_mg": 20_000}

BARCODE_MACROS = """
CREATE OR REPLACE MACRO digits(x) AS regexp_replace(coalesce(x, ''), '[^0-9]', '', 'g');
CREATE OR REPLACE MACRO gtin14(x) AS CASE WHEN length(digits(x)) BETWEEN 8 AND 14 THEN lpad(digits(x), 14, '0') END;
CREATE OR REPLACE MACRO name_words(x) AS
    list_filter(string_split_regex(lower(coalesce(x, '')), '[^a-z0-9]+'), lambda w: length(w) >= 3);
CREATE OR REPLACE MACRO gtin_ok(g) AS g IS NOT NULL AND (10 - list_sum(list_transform(range(13),
    lambda i: CAST(substr(g, i + 1, 1) AS INTEGER) * CASE WHEN i % 2 = 0 THEN 3 ELSE 1 END)) % 10) % 10
    = CAST(substr(g, 14, 1) AS INTEGER);
"""


def _csv(path, **options):
    """DuckDB read_csv call for one file, every column read as text."""
    extra = "".join(f", {k}={v}" for k, v in options.items())
    return f"read_csv('{path}', header=true, all_varchar=true{extra})"


def _pivot_nutrients(food_nutrient_view):
    """SQL that turns FDC's one-row-per-nutrient table into one row per food."""
    columns = []
    for name, ids in FDC_NUTRIENTS.items():
        picks = ", ".join(f"max(TRY_CAST(amount AS DOUBLE)) FILTER (WHERE nutrient_id = '{i}')" for i in ids)
        columns.append(f"coalesce({picks}) AS {name}")
    return f"SELECT fdc_id, {', '.join(columns)} FROM {food_nutrient_view} GROUP BY fdc_id"


def _clean(value_sql, nutrient):
    """Keep a nutrient value only when it is believable; otherwise NULL (shown as unknown)."""
    limit = NUTRIENT_MAX.get(nutrient, 100)
    return f"CASE WHEN {value_sql} BETWEEN 0 AND {limit} THEN {value_sql} END"


# ------ PHASE 1: LOAD THE SOURCES INTO DUCKDB --------

def load_sources(con):
    """Make every source readable in DuckDB as a view or a table."""

    # job 1: FDC Branded Foods, unpacked from the zip
    folder = extract.unpack("fdc_branded", ("food", "branded_food", "food_nutrient"))
    for table in ("food", "branded_food", "food_nutrient"):
        con.execute(f"CREATE OR REPLACE VIEW fdc_{table} AS SELECT * FROM {_csv(folder / (table + '.csv'))}")

    # job 2: Open Food Facts, US products only, straight from the gzip file
    off = extract.latest_file("off")
    con.execute(f"""CREATE OR REPLACE VIEW off_raw AS
        SELECT * FROM {_csv(off, delim="'\\t'", quote="''", escape="''", ignore_errors="true",
                            strict_mode="false", max_line_size=20_000_000)}
        WHERE countries_tags LIKE '%en:united-states%'""")

    # job 3: generic foods without barcodes (FDC Foundation and SR Legacy)
    names, nutrients = [], []
    for source, data_type in (("fdc_foundation", "foundation_food"), ("fdc_sr_legacy", "sr_legacy_food")):
        folder = extract.unpack(source, ("food", "food_nutrient", "food_category"))
        names.append(f"""SELECT f.fdc_id, f.description AS name, c.description AS category
            FROM {_csv(folder / 'food.csv')} f LEFT JOIN {_csv(folder / 'food_category.csv')} c ON c.id = f.food_category_id
            WHERE f.data_type = '{data_type}'""")
        nutrients.append(f"SELECT fdc_id, nutrient_id, amount FROM {_csv(folder / 'food_nutrient.csv')}")
    con.execute(f"CREATE OR REPLACE VIEW generic_names AS {' UNION ALL '.join(names)}")
    con.execute(f"CREATE OR REPLACE VIEW generic_nutrient_rows AS {' UNION ALL '.join(nutrients)}")

    # job 4: openFDA recalls, with the barcodes written in their text
    recalls, links = [], []
    for r in extract.read_openfda(extract.latest_file("openfda")):
        day = r.get("report_date") or ""
        recalls.append((r["recall_number"], f"{day[:4]}-{day[4:6]}-{day[6:8]}" if len(day) == 8 else None,
                        {"Class I": 1, "Class II": 2, "Class III": 3}.get(r.get("classification")),
                        r.get("status") == "Ongoing", r.get("reason_for_recall"), r.get("product_description")))
        text = " ".join(filter(None, [r.get("product_description"), r.get("code_info")]))
        links += [(r["recall_number"], int(g)) for g in barcode.recall_gtins(text)]
    con.execute("""CREATE OR REPLACE TABLE recall (recall_number VARCHAR PRIMARY KEY, report_date DATE,
                   class TINYINT, ongoing BOOLEAN, reason VARCHAR, product_description VARCHAR)""")
    con.executemany("INSERT OR IGNORE INTO recall VALUES (?, ?, ?, ?, ?, ?)", recalls)
    con.execute("CREATE OR REPLACE TABLE recall_link (recall_number VARCHAR, gtin BIGINT)")
    con.executemany("INSERT INTO recall_link VALUES (?, ?)", links)
    con.execute("CREATE OR REPLACE TABLE recall_link AS SELECT DISTINCT * FROM recall_link")


# ------ PHASE 2: TRANSFORM PART 1, BARCODES --------

def key_and_dedup(con):
    """One record per source and GTIN-14: broken barcodes dropped, newest version kept."""

    # job 1: the barcode rules as SQL macros
    con.execute(BARCODE_MACROS)

    # job 2: FDC, latest publication per GTIN-14, US market only, with nutrients per 100 g
    con.execute(f"CREATE OR REPLACE TABLE fdc_nutrients AS {_pivot_nutrients('fdc_food_nutrient')}")
    con.execute("""CREATE OR REPLACE TABLE fdc AS
        SELECT gtin14(b.gtin_upc) AS g, b.fdc_id, f.description AS name,
               coalesce(nullif(b.brand_name, ''), b.brand_owner) AS brand,
               b.branded_food_category AS category, b.ingredients,
               TRY_CAST(b.serving_size AS DOUBLE) AS serving_size,
               CASE lower(b.serving_size_unit) WHEN 'grm' THEN 'g' WHEN 'g' THEN 'g'
                    WHEN 'mlt' THEN 'ml' WHEN 'ml' THEN 'ml' END AS serving_unit,
               coalesce(b.household_serving_fulltext, '') ILIKE '%age 1-3%' AS toddler,
               b.package_weight AS size, nullif(b.discontinued_date, '') IS NOT NULL AS discontinued,
               TRY_CAST(f.publication_date AS DATE) AS updated
        FROM fdc_branded_food b JOIN fdc_food f USING (fdc_id)
        WHERE gtin_ok(gtin14(b.gtin_upc)) AND coalesce(b.market_country, 'United States') IN ('United States', 'US')
        QUALIFY row_number() OVER (PARTITION BY g ORDER BY updated DESC NULLS LAST, TRY_CAST(b.fdc_id AS BIGINT) DESC) = 1""")

    # job 3: Open Food Facts, latest edit per GTIN-14
    off_values = ", ".join(f"TRY_CAST(\"{col}\" AS DOUBLE) * {factor} AS off_{name}"
                           for name, (col, factor) in OFF_NUTRIENTS.items())
    con.execute(f"""CREATE OR REPLACE TABLE off AS
        SELECT gtin14(code) AS g, nullif(product_name, '') AS name, nullif(trim(split_part(brands, ',', 1)), '') AS brand,
               nullif(regexp_replace(main_category, '^[a-z]+:', ''), '') AS category,
               nullif(ingredients_text, '') AS ingredients, TRY_CAST(serving_quantity AS DOUBLE) AS serving_size,
               nullif(quantity, '') AS size, TRY_CAST(nova_group AS TINYINT) AS nova, nullif(image_url, '') AS image_url,
               to_timestamp(TRY_CAST(last_modified_t AS BIGINT))::DATE AS updated, {off_values}
        FROM off_raw
        WHERE gtin_ok(gtin14(code))
        QUALIFY row_number() OVER (PARTITION BY g ORDER BY updated DESC NULLS LAST) = 1""")

    # job 4: how many products each source gave
    return {"fdc_products": con.execute("SELECT count(*) FROM fdc").fetchone()[0],
            "off_us_products": con.execute("SELECT count(*) FROM off").fetchone()[0]}


# ------ PHASE 3: TRANSFORM PARTS 2 AND 3, COMBINE & SELECT, THEN CLEANUP --------

def combine_and_clean(con):
    """One product per GTIN-14. Each field comes from its preferred source; the other source fills gaps."""

    # job 1: nutrients from FDC first, OFF as fallback, cleaned; from_off marks the OFF values
    values, bits = [], []
    for i, name in enumerate(NUTRIENTS):
        fdc_v, off_v = _clean(f"n.{name}", name), _clean(f"o.off_{name}", name)
        values.append(f"coalesce({fdc_v}, {off_v}) AS {name}")
        bits.append(f"CASE WHEN {fdc_v} IS NULL AND {off_v} IS NOT NULL THEN {1 << i} ELSE 0 END")

    # job 2: identity from OFF, category from FDC, ingredients from the newest record, serving from OFF.
    #        The OFF name is a volunteer edit: when FDC has the product too, the OFF name must share a word
    #        with FDC's name or brand, else FDC's name wins (Cheerios was "My Bff" in the 2026-10-23 dump).
    con.execute(f"""CREATE OR REPLACE TABLE merged AS
        SELECT CAST(coalesce(o.g, f.g) AS BIGINT) AS gtin,
               CASE WHEN o.name IS NULL THEN f.name
                    WHEN f.name IS NULL THEN o.name
                    WHEN list_has_any(name_words(o.name), list_concat(name_words(f.name), name_words(f.brand))) THEN o.name
                    ELSE f.name END AS name,
               o.name IS NOT NULL AND f.name IS NOT NULL
                    AND NOT list_has_any(name_words(o.name), list_concat(name_words(f.name), name_words(f.brand)))
                    AS off_name_rejected,
               coalesce(o.brand, f.brand) AS brand,
               coalesce(nullif(f.category, ''), o.category) AS category,
               CASE WHEN o.ingredients IS NOT NULL AND (f.ingredients IS NULL OR o.updated >= f.updated)
                    THEN o.ingredients ELSE f.ingredients END AS ingredients_raw,
               (o.ingredients IS NOT NULL AND (f.ingredients IS NULL OR o.updated >= f.updated)) AS ingredients_from_off,
               coalesce(o.serving_size, CASE WHEN f.serving_unit IS NOT NULL THEN f.serving_size END) AS serving_size,
               o.serving_size IS NULL AND coalesce(f.toddler, false) AS toddler_serving,
               coalesce(f.serving_unit, 'g') = 'ml' AS basis_ml,
               coalesce(o.size, f.size) AS size, o.nova, o.image_url,
               coalesce(f.discontinued, false) AS discontinued, greatest(o.updated, f.updated) AS updated,
               (f.g IS NOT NULL)::INTEGER + 2 * (o.g IS NOT NULL)::INTEGER AS sources,
               false AS is_stub, {', '.join(values)}, {' + '.join(bits)} AS from_off_mask
        FROM fdc f FULL OUTER JOIN off o ON o.g = f.g
        LEFT JOIN fdc_nutrients n ON n.fdc_id = f.fdc_id""")

    # job 3: clean up FDC formatting: a space after joined sentences ("FRESHNESS.VITAMINS")
    con.execute("""ALTER TABLE merged ADD COLUMN ingredients VARCHAR;
        UPDATE merged SET ingredients = trim(regexp_replace(ingredients_raw, '\\.([A-Za-z])', '. \\1', 'g'));
        ALTER TABLE merged DROP COLUMN ingredients_raw""")

    # job 4: generic foods without barcodes, one row per FDC food
    con.execute(f"""CREATE OR REPLACE TABLE generic_food AS
        SELECT CAST(g.fdc_id AS INTEGER) AS fdc_id, g.name, g.category,
               {', '.join(_clean('n.' + name, name) + ' AS ' + name for name in NUTRIENTS)}
        FROM generic_names g LEFT JOIN ({_pivot_nutrients('generic_nutrient_rows')}) n USING (fdc_id)""")


# ------ PHASE 4: TRANSFORM PART 4, ENRICH --------

def enrich(con):
    """Recalls become stubs when we have no product for their barcode; counts for the run log."""

    # job 1: a recalled barcode with no product becomes a stub, so a scan still shows the recall
    con.execute("""INSERT INTO merged (gtin, name, sources, is_stub, discontinued, basis_ml, toddler_serving,
                                       ingredients_from_off, from_off_mask, updated)
        SELECT l.gtin, arg_max(trim(regexp_extract(r.product_description, '^[^.,]*')), r.report_date), 4, true,
               false, false, false, false, 0, max(r.report_date)
        FROM recall_link l JOIN recall r USING (recall_number)
        WHERE l.gtin NOT IN (SELECT gtin FROM merged)
        GROUP BY l.gtin""")  # one stub per barcode, named after its newest recall

    # job 2: mark products that have a recall
    con.execute("UPDATE merged SET sources = sources | 4 WHERE gtin IN (SELECT gtin FROM recall_link) AND NOT is_stub")

    # job 3: counts for the run log
    one = lambda sql: con.execute(sql).fetchone()[0]
    return {"products": one("SELECT count(*) FROM merged"),
            "with_ingredients": one("SELECT count(*) FROM merged WHERE ingredients IS NOT NULL"),
            "with_nutrients": one("SELECT count(*) FROM merged WHERE kcal IS NOT NULL OR protein_g IS NOT NULL"),
            "in_both_sources": one("SELECT count(*) FROM merged WHERE sources & 3 = 3"),
            "off_names_rejected": one("SELECT count(*) FROM merged WHERE off_name_rejected"),
            "recall_stubs": one("SELECT count(*) FROM merged WHERE is_stub"),
            "recalls_with_barcode": one("SELECT count(DISTINCT recall_number) FROM recall_link"),
            "generic_foods": one("SELECT count(*) FROM generic_food")}


def run(con):
    """All transform phases in order. Returns the counts for the run log."""
    load_sources(con)
    stats = key_and_dedup(con)
    combine_and_clean(con)
    stats.update(enrich(con))
    return stats
