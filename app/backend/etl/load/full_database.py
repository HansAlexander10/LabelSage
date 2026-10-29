"""Load, part A: write labelsage-full.sqlite, the whole cleaned database, readable, for the team.

It is the source of truth on the build machine: merged products, nutrients as decimals, plain ingredient
lists, each source's cleaned record, which source won each field, and every losing value. catalog.sqlite
(load.py) is then a slim export of the same data for the phone. Schema: app/backend/schemas/full.sql.
"""
import datetime as dt
import json
import pathlib
import sqlite3

from extract import extract
from transform import transform

SCHEMA = pathlib.Path(__file__).resolve().parents[2] / "schemas" / "full.sql"
FULL_NAME = {n: ("energy_kcal" if n == "kcal" else n) for n in transform.NUTRIENTS}   # internal -> table column
TEXT_FIELDS = ("name", "brand", "category", "ingredients")


def _nutrients(prefix, internal=True):
    """SELECT list of the 12 nutrients, rounded, named as in full.sql."""
    return ", ".join(f"round({prefix}{('off_' if not internal else '') + n}, 3) AS {FULL_NAME[n]}"
                     for n in transform.NUTRIENTS)


# ------ PHASE 1: CREATE THE EMPTY DATABASE --------

def create(path):
    """Create labelsage-full.sqlite with the tables, keys and indexes from full.sql."""

    # job 1: start from an empty file
    path.parent.mkdir(parents=True, exist_ok=True)
    path.unlink(missing_ok=True)

    # job 2: create every table from the schema file
    with sqlite3.connect(path) as db:
        db.executescript(SCHEMA.read_text())


# ------ PHASE 2: THE MERGED PRODUCTS --------

def read_amazon_picks(con):
    """amazon_pick: the ASIN and image chosen per barcode by the match step; empty when it has not run yet.
    load.py reads the same table for the phone catalog."""

    # job 1: empty tables first, so the build works without amazon.sqlite
    con.execute("CREATE OR REPLACE TEMP TABLE amazon_pick (gtin BIGINT, asin VARCHAR, image_url VARCHAR)")
    con.execute("""CREATE OR REPLACE TEMP TABLE amazon_pick_image
                   (gtin BIGINT, rank INTEGER, url VARCHAR, variant VARCHAR, width INTEGER, height INTEGER)""")
    if not extract.AMAZON_DB.exists():
        return 0

    # job 2: the chosen ASIN per barcode, read-only, so the build never changes match results
    con.execute(f"ATTACH '{extract.AMAZON_DB}' AS amz (TYPE sqlite, READ_ONLY)")
    con.execute("INSERT INTO amazon_pick SELECT CAST(gtin AS BIGINT), asin, image_url FROM amz.product_amazon")

    # job 3: all its images, MAIN first, then PT01, PT02 ...; swatches (SWCH) are color chips, not photos
    con.execute("""INSERT INTO amazon_pick_image
        SELECT CAST(p.gtin AS BIGINT), row_number() OVER (PARTITION BY p.gtin ORDER BY i.variant <> 'MAIN', i.variant) - 1,
               i.url, i.variant, i.width, i.height
        FROM amz.product_amazon p JOIN amz.amazon_image i ON i.asin = p.asin AND i.marketplace_id = p.marketplace_id
        WHERE i.variant <> 'SWCH'""")
    con.execute("DETACH amz")
    return con.execute("SELECT count(*) FROM amazon_pick").fetchone()[0]


def write_products(con):
    """product, nutrient and ingredients: the merged result, readable."""

    # job 1: one row per barcode with both source records beside it, used by every insert below
    con.execute("""CREATE OR REPLACE TEMP TABLE j AS
        SELECT m.*, f.fdc_id, f.name AS f_name, f.brand AS f_brand, f.category AS f_category,
               f.ingredients AS f_ingredients, f.serving_size AS f_serving, f.updated AS f_updated,
               o.name AS o_name, o.brand AS o_brand, o.category AS o_category, o.ingredients AS o_ingredients,
               o.serving_size AS o_serving, o.updated AS o_updated, a.asin AS amazon_asin, a.image_url AS amazon_image
        FROM merged m
        LEFT JOIN fdc f ON CAST(f.g AS BIGINT) = m.gtin
        LEFT JOIN off o ON CAST(o.g AS BIGINT) = m.gtin
        LEFT JOIN amazon_pick a ON a.gtin = m.gtin""")

    # job 2: the products
    con.execute("""INSERT INTO fulldb.product
        SELECT gtin, lpad(CAST(gtin AS VARCHAR), 13, '0'), name, brand, category, size, serving_size,
               CASE WHEN serving_size IS NULL THEN NULL WHEN basis_ml THEN 'ml' ELSE 'g' END,
               toddler_serving::INTEGER, discontinued::INTEGER, nova, coalesce(amazon_image, image_url),
               (sources & 1 > 0)::INTEGER, (sources & 2 > 0)::INTEGER, is_stub::INTEGER, (sources & 4 > 0)::INTEGER,
               off_match_tier, off_match_confidence, CAST(f_updated AS VARCHAR), CAST(o_updated AS VARCHAR),
               confidence, coalesce(recipe_changed, false)::INTEGER, unique_scans,
               (gtin IN (SELECT gtin FROM phone))::INTEGER, region, category_source, brand_owner,
               CASE WHEN amazon_image IS NOT NULL THEN 'amazon' WHEN image_url IS NOT NULL THEN 'off' END, amazon_asin
        FROM j""")

    # job 3: every photo: the matched Amazon item's images, else the one OFF photo
    con.execute("""INSERT INTO fulldb.product_image
        SELECT gtin, rank, url, 'amazon', variant, width, height FROM amazon_pick_image
        UNION ALL
        SELECT gtin, 0, image_url, 'off', NULL, NULL, NULL FROM j
        WHERE image_url IS NOT NULL AND gtin NOT IN (SELECT gtin FROM amazon_pick_image)""")

    # job 4: nutrients per 100 g, with the names of those that came from OFF
    from_off = ", ".join(f"CASE WHEN from_off_mask & {1 << i} > 0 THEN '{FULL_NAME[n]}' END"
                         for i, n in enumerate(transform.NUTRIENTS))
    any_value = " OR ".join(f"{n} IS NOT NULL" for n in transform.NUTRIENTS)
    con.execute(f"""INSERT INTO fulldb.nutrient
        SELECT gtin, {_nutrients('')}, nullif(concat_ws(',', {from_off}), '') FROM merged WHERE {any_value}""")

    # job 5: the ingredient list as printed, from the newest record
    con.execute("""INSERT INTO fulldb.ingredients
        SELECT gtin, ingredients, CASE WHEN ingredients_from_off THEN 'off' ELSE 'fdc' END,
               CAST(CASE WHEN ingredients_from_off THEN o_updated ELSE f_updated END AS VARCHAR),
               ingredients_lang, ingredients_ok::INTEGER
        FROM j WHERE ingredients IS NOT NULL""")


# ------ PHASE 3: AUDIT, WHICH SOURCE WON AND WHAT LOST --------

def write_audit(con):
    """product_field_source and merge_conflict, from the same rules the transform used."""

    # job 1: the winning source per field (rules: app/backend/etl/README.md)
    winners = {
        "name": "CASE WHEN f_name IS NOT NULL THEN 'fdc' ELSE 'off' END",
        "brand": "CASE WHEN f_brand IS NOT NULL THEN 'fdc' ELSE 'off' END",
        "category": "CASE WHEN nullif(f_category, '') IS NOT NULL THEN 'fdc' ELSE 'off' END",
        "ingredients": "CASE WHEN ingredients_from_off THEN 'off' ELSE 'fdc' END",
        "serving_size": "CASE WHEN o_serving IS NOT NULL THEN 'off' ELSE 'fdc' END",
    }
    for field, winner in winners.items():
        con.execute(f"""INSERT INTO fulldb.product_field_source
            SELECT gtin, '{field}', {winner} FROM j WHERE {field} IS NOT NULL AND NOT is_stub""")

    # job 2: text fields where both sources have a value that differs (case and punctuation ignored)
    for field in TEXT_FIELDS:
        same = f"regexp_replace(lower(f_{field}), '[^a-z0-9]', '', 'g') = regexp_replace(lower(o_{field}), '[^a-z0-9]', '', 'g')"
        con.execute(f"""INSERT INTO fulldb.merge_conflict
            SELECT gtin, '{field}', w, CASE w WHEN 'off' THEN o_{field} ELSE f_{field} END,
                   CASE w WHEN 'off' THEN 'fdc' ELSE 'off' END, CASE w WHEN 'off' THEN f_{field} ELSE o_{field} END
            FROM (SELECT *, {winners[field]} AS w FROM j)
            WHERE f_{field} IS NOT NULL AND o_{field} IS NOT NULL AND NOT ({same})""")
    con.execute("""INSERT INTO fulldb.merge_conflict
        SELECT gtin, 'serving_size', 'off', CAST(o_serving AS VARCHAR), 'fdc', CAST(f_serving AS VARCHAR)
        FROM j WHERE o_serving IS NOT NULL AND f_serving IS NOT NULL AND abs(o_serving - f_serving) > 0.5""")

    # job 3: nutrients where FDC and OFF differ by more than 5% (FDC always wins)
    for n in transform.NUTRIENTS:
        a, b = f"n.{n}", f"o.off_{n}"
        con.execute(f"""INSERT INTO fulldb.merge_conflict
            SELECT CAST(f.g AS BIGINT), 'nutrient.{FULL_NAME[n]}', 'fdc', CAST(round({a}, 3) AS VARCHAR),
                   'off', CAST(round({b}, 3) AS VARCHAR)
            FROM fdc f JOIN off o ON o.g = f.g JOIN fdc_nutrients n ON n.fdc_id = f.fdc_id
            WHERE {a} IS NOT NULL AND {b} IS NOT NULL
              AND abs({a} - {b}) > greatest(0.1, 0.05 * greatest(abs({a}), abs({b})))""")


# ------ PHASE 4: SOURCES, RECALLS, NATURAL FOODS, BUILD INFO --------

def write_sources_and_rest(con, stats):
    """Each source's cleaned record, the recalls, the generic foods and what this build was."""

    # job 1: each source, cleaned, before the merge
    con.execute(f"""INSERT INTO fulldb.source_fdc
        SELECT CAST(f.g AS BIGINT), CAST(f.fdc_id AS BIGINT), f.name, f.brand, f.category, f.ingredients,
               f.serving_size, f.serving_unit, f.size, f.discontinued::INTEGER, CAST(f.updated AS VARCHAR),
               {_nutrients('n.')}
        FROM fdc f LEFT JOIN fdc_nutrients n ON n.fdc_id = f.fdc_id""")
    con.execute(f"""INSERT INTO fulldb.source_off
        SELECT CAST(g AS BIGINT), name, brand, category, ingredients, serving_size, size, nova, image_url,
               CAST(updated AS VARCHAR), {_nutrients('', internal=False)}
        FROM off""")

    # job 2: recalls and the barcodes they name
    con.execute("""INSERT INTO fulldb.recall SELECT recall_number, CAST(report_date AS VARCHAR), class, ongoing::INTEGER,
                   reason, product_description FROM recall""")
    con.execute("INSERT INTO fulldb.recall_link SELECT DISTINCT recall_number, gtin FROM recall_link")

    # job 3: natural foods without a barcode
    con.execute(f"INSERT INTO fulldb.generic_food SELECT fdc_id, name, category, {_nutrients('')} FROM generic_food")

    # job 4: what this build was
    info = {"built_at": dt.datetime.now().isoformat(timespec="seconds"), "stats": json.dumps(stats),
            **{f"source_{s}": extract.latest_file(s).name for s in extract.SOURCES}}
    con.executemany("INSERT INTO fulldb.build_info VALUES (?, ?)", list(info.items()))


def run(con, stats, path):
    """All phases of the full database (load.run reads the Amazon picks first). Returns its size and row counts."""
    create(path)
    con.execute(f"ATTACH '{path}' AS fulldb (TYPE sqlite)")
    write_products(con)
    write_audit(con)
    write_sources_and_rest(con, stats)
    con.execute("DETACH fulldb")
    with sqlite3.connect(path) as db:
        tables = [t for (t,) in db.execute("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")]
        counts = {t: db.execute(f"SELECT count(*) FROM {t}").fetchone()[0] for t in tables}
    return {"full_path": str(path), "full_mb": round(path.stat().st_size / 1e6, 1), "full_rows": counts}
