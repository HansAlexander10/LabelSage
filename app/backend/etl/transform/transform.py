"""Transform: turn the raw downloads into one merged US product table, in DuckDB.

The phases follow the team's ETL board: Part 1 barcodes, Part 2 combine & select,
Part 3 cleanup, Part 4 enrich. Merge rules: app/backend/etl/README.md
"""
import pandas
from duckdb.typing import BOOLEAN, VARCHAR

from extract import extract
from match import matcher
from shared import barcode, categories, ingredients_text, recipe

# FDC is the main source (decision 2026-10-28). False: only FDC products; Open Food Facts only enriches them.
# True: also products only Open Food Facts has, with OFF's name and ingredients.
KEEP_OFF_ONLY = False

# Open Food Facts countries we read. US only: Indonesian products are skipped for now (decision 2026-10-29);
# add "indonesia" to bring them back (region, quality gate, word list and name categories still handle them).
OFF_COUNTRIES = ("united-states",)

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

    # job 2: Open Food Facts products of OFF_COUNTRIES, straight from the gzip file
    off = extract.latest_file("off")
    con.execute(f"""CREATE OR REPLACE VIEW off_raw AS
        SELECT * FROM {_csv(off, delim="'\\t'", quote="''", escape="''", ignore_errors="true",
                            strict_mode="false", max_line_size=20_000_000)}
        WHERE {" OR ".join(f"countries_tags LIKE '%en:{c}%'" for c in OFF_COUNTRIES)}""")

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
               coalesce(nullif(b.brand_name, ''), b.brand_owner) AS brand, nullif(b.brand_owner, '') AS brand_owner,
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
               nullif(regexp_replace(main_category_en, '^[a-z]{2}:', ''), '') AS category,
               nullif(ingredients_text, '') AS ingredients, TRY_CAST(serving_quantity AS DOUBLE) AS serving_size,
               nullif(quantity, '') AS size, TRY_CAST(nova_group AS TINYINT) AS nova, nullif(image_url, '') AS image_url,
               to_timestamp(TRY_CAST(last_modified_t AS BIGINT))::DATE AS updated,
               TRY_CAST(unique_scans_n AS INTEGER) AS unique_scans, TRY_CAST(completeness AS DOUBLE) AS completeness,
               concat_ws(',', CASE WHEN countries_tags LIKE '%en:united-states%' THEN 'us' END,
                              CASE WHEN countries_tags LIKE '%en:indonesia%' THEN 'id' END) AS region,
               {off_values}
        FROM off_raw
        WHERE gtin_ok(gtin14(code))
        QUALIFY row_number() OVER (PARTITION BY g ORDER BY updated DESC NULLS LAST) = 1""")

    # job 4: how many products each source gave
    return {"fdc_products": con.execute("SELECT count(*) FROM fdc").fetchone()[0],
            "off_products_us_and_id": con.execute("SELECT count(*) FROM off").fetchone()[0]}


# ------ PHASE 3: TRANSFORM PARTS 2 AND 3, COMBINE & SELECT, THEN CLEANUP --------

def combine_and_clean(con):
    """One product per GTIN-14. FDC gives identity, ingredients and nutrients; Open Food Facts fills gaps and gives
    the photo, but only when its record passes the identity check against FDC (job 3)."""

    # job 0: the recipe-change check (shared/recipe.py) as a SQL function; NULL lists skip the call
    con.create_function("recipe_changed", recipe.recipe_changed, [VARCHAR, VARCHAR], BOOLEAN)

    # job 1: nutrients from FDC first, OFF as fallback, cleaned; from_off marks the OFF values
    values, bits = [], []
    for i, name in enumerate(NUTRIENTS):
        fdc_v, off_v = _clean(f"n.{name}", name), _clean(f"o.off_{name}", name)
        values.append(f"coalesce({fdc_v}, {off_v}) AS {name}")
        bits.append(f"CASE WHEN {fdc_v} IS NULL AND {off_v} IS NOT NULL THEN {1 << i} ELSE 0 END")

    # job 2: identity, category and ingredients from FDC; OFF fills what FDC lacks. Serving stays OFF first
    #        (FDC can list a toddler serving). Without KEEP_OFF_ONLY, products FDC lacks are left out.
    join = "FULL OUTER JOIN" if KEEP_OFF_ONLY else "LEFT JOIN"
    con.execute(f"""CREATE OR REPLACE TABLE merged AS
        SELECT CAST(coalesce(f.g, o.g) AS BIGINT) AS gtin,
               coalesce(f.name, o.name) AS name, coalesce(f.brand, o.brand) AS brand, f.brand_owner,
               coalesce(nullif(f.category, ''), o.category) AS category,
               coalesce(f.ingredients, o.ingredients) AS ingredients_raw,
               f.ingredients IS NULL AND o.ingredients IS NOT NULL AS ingredients_from_off,
               coalesce(o.serving_size, CASE WHEN f.serving_unit IS NOT NULL THEN f.serving_size END) AS serving_size,
               o.serving_size IS NULL AND coalesce(f.toddler, false) AS toddler_serving,
               coalesce(f.serving_unit, 'g') = 'ml' AS basis_ml,
               coalesce(o.size, f.size) AS size, o.nova, o.image_url,
               coalesce(f.discontinued, false) AS discontinued, greatest(o.updated, f.updated) AS updated,
               f.updated AS fdc_updated, o.updated AS off_updated, o.unique_scans, o.completeness,
               concat_ws(',', CASE WHEN f.g IS NOT NULL OR o.region LIKE '%us%' THEN 'us' END,
                              CASE WHEN o.region LIKE '%id%' THEN 'id' END) AS region,
               coalesce(recipe_changed(f.ingredients, o.ingredients), false) AS recipe_changed,
               (f.g IS NOT NULL)::INTEGER + 2 * (o.g IS NOT NULL)::INTEGER AS sources,
               false AS is_stub, {', '.join(values)}, {' + '.join(bits)} AS from_off_mask
        FROM fdc f {join} off o ON o.g = f.g
        LEFT JOIN fdc_nutrients n ON n.fdc_id = f.fdc_id""")

    # job 3: identity check of each OFF record that shares its barcode with FDC (match/matcher.py,
    #        method same_barcode): a volunteer may have put another product's name or photo under the barcode
    #        (Cheerios was "My Bff" in the 2026-10-23 dump). Only an accepted record keeps its photo.
    pairs = con.execute("""SELECT f.g, f.name, f.brand, f.brand_owner, f.ingredients, o.name, o.brand, o.ingredients
                            FROM fdc f JOIN off o ON o.g = f.g""").fetchall()
    checks = []
    for g, f_name, f_brand, f_owner, f_ingredients, o_name, o_brand, o_ingredients in pairs:
        s = matcher.score_pair({"gtin": g, "name": f_name, "brand": f_brand, "brand_owner": f_owner,
                                "ingredients": f_ingredients},
                               {"item_name": o_name, "brand": o_brand, "gtins": {g}, "ingredients": o_ingredients},
                               "same_barcode")
        checks.append((int(g), s["tier"], s["confidence"], ",".join(s["reasons"])))
    checks_df = pandas.DataFrame(checks, columns=["gtin", "tier", "confidence", "reasons"])  # executemany is slow
    con.execute("CREATE OR REPLACE TABLE off_check AS SELECT * FROM checks_df")
    con.execute("""ALTER TABLE merged ADD COLUMN off_match_tier VARCHAR;
        ALTER TABLE merged ADD COLUMN off_match_confidence DOUBLE;
        UPDATE merged SET off_match_tier = c.tier, off_match_confidence = c.confidence FROM off_check c
        WHERE merged.gtin = c.gtin;
        UPDATE merged SET image_url = NULL WHERE sources & 1 > 0 AND coalesce(off_match_tier, '') <> 'accept'""")

    # job 4: clean up FDC formatting: a space after joined sentences ("FRESHNESS.VITAMINS")
    con.execute("""ALTER TABLE merged ADD COLUMN ingredients VARCHAR;
        UPDATE merged SET ingredients = trim(regexp_replace(ingredients_raw, '\\.([A-Za-z])', '. \\1', 'g'));
        ALTER TABLE merged DROP COLUMN ingredients_raw""")

    # job 5: language and quality of each ingredient list (shared/ingredients_text.py). The known words are
    #        those in 30+ lists of the catalog, 3+ Indonesian lists, or the Indonesian allergen draft.
    vocabulary = {w for (w,) in con.execute("""
        WITH w AS (SELECT DISTINCT gtin, region, unnest(regexp_extract_all(lower(ingredients), '[a-zà-ÿ]{2,}')) AS word
                   FROM merged WHERE ingredients IS NOT NULL)
        SELECT word FROM w GROUP BY word
        HAVING count(*) >= 30 OR count(*) FILTER (WHERE region LIKE '%id%') >= 3""").fetchall()}
    vocabulary |= ingredients_text.draft_terms()
    con.create_function("ingredients_ok", lambda text: ingredients_text.looks_ok(text, vocabulary), [VARCHAR], BOOLEAN)
    con.create_function("ingredients_lang", ingredients_text.language, [VARCHAR], VARCHAR)
    con.execute("""ALTER TABLE merged ADD COLUMN ingredients_ok BOOLEAN;
        ALTER TABLE merged ADD COLUMN ingredients_lang VARCHAR;
        UPDATE merged SET ingredients_ok = ingredients_ok(ingredients), ingredients_lang = ingredients_lang(ingredients)
        WHERE ingredients IS NOT NULL""")

    # job 6: a category from the name for Indonesian products Open Food Facts left without one
    con.create_function("category_from_name", categories.from_name, [VARCHAR], VARCHAR, null_handling="special")
    con.execute("""ALTER TABLE merged ADD COLUMN category_source VARCHAR;
        UPDATE merged SET category_source = CASE WHEN category IS NULL THEN NULL
                                                 WHEN sources & 1 > 0 AND category IS NOT NULL THEN 'fdc' ELSE 'off' END;
        UPDATE merged SET category = category_from_name(name), category_source = 'name'
        WHERE category IS NULL AND region LIKE '%id%' AND category_from_name(name) IS NOT NULL""")

    # job 7: generic foods without barcodes, one row per FDC food
    con.execute(f"""CREATE OR REPLACE TABLE generic_food AS
        SELECT CAST(g.fdc_id AS INTEGER) AS fdc_id, g.name, g.category,
               {', '.join(_clean('n.' + name, name) + ' AS ' + name for name in NUTRIENTS)}
        FROM generic_names g LEFT JOIN ({_pivot_nutrients('generic_nutrient_rows')}) n USING (fdc_id)""")


# ------ PHASE 4: TRANSFORM PART 4, ENRICH --------

def enrich(con):
    """Recalls become stubs when we have no product for their barcode; counts for the run log."""

    # job 1: a recalled barcode with no product becomes a stub, so a scan still shows the recall
    con.execute("""INSERT INTO merged (gtin, name, sources, is_stub, discontinued, basis_ml, toddler_serving,
                                       ingredients_from_off, from_off_mask, updated, region)
        SELECT l.gtin, arg_max(trim(regexp_extract(r.product_description, '^[^.,]*')), r.report_date), 4, true,
               false, false, false, false, 0, max(r.report_date), 'us'
        FROM recall_link l JOIN recall r USING (recall_number)
        WHERE l.gtin NOT IN (SELECT gtin FROM merged)
        GROUP BY l.gtin""")  # one stub per barcode, named after its newest recall

    # job 2: mark products that have a recall
    con.execute("UPDATE merged SET sources = sources | 4 WHERE gtin IN (SELECT gtin FROM recall_link) AND NOT is_stub")

    # job 3: how sure we are (0 low, 1 medium, 2 high): two sources, OFF completeness of 0.8 or more,
    #        and a source record under three years old; a changed recipe lowers it one level.
    #        Placeholder thresholds from the merge prototype (team decision).
    con.execute("""ALTER TABLE merged ADD COLUMN confidence TINYINT;
        UPDATE merged SET confidence = CASE WHEN is_stub THEN 0 ELSE greatest(0,
            CASE (sources & 3 = 3)::INTEGER + (coalesce(completeness, 0) >= 0.8)::INTEGER
                 + (coalesce(updated, DATE '1970-01-01') >= current_date - INTERVAL 3 YEAR)::INTEGER
                 WHEN 3 THEN 2 WHEN 2 THEN 1 ELSE 0 END - coalesce(recipe_changed, false)::INTEGER) END""")

    # job 4: counts for the run log
    one = lambda sql: con.execute(sql).fetchone()[0]
    return {"products": one("SELECT count(*) FROM merged"),
            "with_ingredients": one("SELECT count(*) FROM merged WHERE ingredients IS NOT NULL"),
            "with_nutrients": one("SELECT count(*) FROM merged WHERE kcal IS NOT NULL OR protein_g IS NOT NULL"),
            "in_both_sources": one("SELECT count(*) FROM merged WHERE sources & 3 = 3"),
            "off_check_accept_review_reject": [one(f"SELECT count(*) FROM merged WHERE off_match_tier = '{t}'")
                                               for t in ("accept", "review", "reject")],
            "with_image": one("SELECT count(*) FROM merged WHERE image_url IS NOT NULL"),
            "recall_stubs": one("SELECT count(*) FROM merged WHERE is_stub"),
            "recipe_changed": one("SELECT count(*) FROM merged WHERE recipe_changed"),
            "confidence_high_medium_low": [one(f"SELECT count(*) FROM merged WHERE confidence = {c}") for c in (2, 1, 0)],
            "scanned_on_off": one("SELECT count(*) FROM merged WHERE unique_scans > 0"),
            "indonesian": one("SELECT count(*) FROM merged WHERE region LIKE '%id%'"),
            "indonesian_with_ingredients": one("SELECT count(*) FROM merged WHERE region LIKE '%id%' AND ingredients IS NOT NULL"),
            "indonesian_ingredients_ok": one("SELECT count(*) FROM merged WHERE region LIKE '%id%' AND ingredients_ok"),
            "ingredients_failed_quality_gate": one("SELECT count(*) FROM merged WHERE ingredients IS NOT NULL AND NOT ingredients_ok"),
            "indonesian_category_from_name": one("SELECT count(*) FROM merged WHERE category_source = 'name'"),
            "ingredients_by_language": dict(con.execute("SELECT ingredients_lang, count(*) FROM merged "
                                                       "WHERE ingredients IS NOT NULL GROUP BY 1").fetchall()),
            "recalls_with_barcode": one("SELECT count(DISTINCT recall_number) FROM recall_link"),
            "generic_foods": one("SELECT count(*) FROM generic_food")}


def run(con):
    """All transform phases in order. Returns the counts for the run log."""
    load_sources(con)
    stats = key_and_dedup(con)
    combine_and_clean(con)
    stats.update(enrich(con))
    return stats
