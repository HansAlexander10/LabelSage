"""Load, part B: write catalog.sqlite, the phone's starter catalog (under 60 MB).

Part A (full_database.py) first writes labelsage-full.sqlite, the whole readable database; this part
exports the same merged data for the phone. DuckDB writes the tables into the SQLite file through its
sqlite extension; Python's sqlite3 then adds the compressed ingredients, the name search index and the packing.
"""
import collections
import datetime as dt
import gzip
import json
import os
import pathlib
import re
import shutil
import sqlite3
import zlib

from extract import extract
from load import full_database, server_export
from transform import transform

HERE = pathlib.Path(__file__).resolve().parent
OUT_DIR = extract.RAW_DIR.parent / "out"
IMAGE_PREFIX = "https://images.openfoodfacts.org/images/products/"
AMAZON_IMAGE_PREFIX = "https://m.media-amazon.com/images/I/"
MAX_PHONE_IMAGES = 5       # Amazon photos per product on the phone (MAIN + 4); the server keeps them all
EPOCH = "DATE '1970-01-01'"
SCHEMA_VERSION = 1         # raise with every change to catalog.sql the app must know about;
                           # LabelSageCatalog refuses another version (CatalogProductSource.schemaVersion)
MAX_CATALOG_MB = 60        # the phone catalog's size limit (team target)


def image_folder(gtin_sql):
    """SQL for the OFF image folder of a barcode: the last 13 digits split 3/3/3/4.
    The app rebuilds the same folder from the barcode, so the catalog stores only the file name."""
    code = f"lpad(CAST({gtin_sql} AS VARCHAR), 13, '0')"
    return (f"'{IMAGE_PREFIX}' || substr({code}, 1, 3) || '/' || substr({code}, 4, 3) || '/' "
            f"|| substr({code}, 7, 3) || '/' || substr({code}, 10) || '/'")


def _whole_numbers(prefix=""):
    """SELECT list that turns grams into hundredths of a gram and rounds mg and kcal."""
    parts = []
    for name in transform.NUTRIENTS:
        if name.endswith("_g"):
            parts.append(f"CAST(round({prefix}{name} * 100) AS INTEGER) AS {name[:-2]}_cg")
        else:
            parts.append(f"CAST(round({prefix}{name}) AS INTEGER) AS {name}")
    return ", ".join(parts)


# ------ PHASE 1: CREATE THE EMPTY PHONE FILE --------

def create_catalog(path):
    """Create catalog.sqlite with its tables and keys (DuckDB would not create the primary keys)."""

    # job 1: start from an empty file
    path.parent.mkdir(parents=True, exist_ok=True)
    path.unlink(missing_ok=True)

    # job 2: create every table from the schema file
    with sqlite3.connect(path) as db:
        db.executescript((HERE.parents[1] / "schemas" / "catalog.sql").read_text())


# ------ PHASE 2: CHOOSE THE PHONE'S STARTER PRODUCTS --------

# Lists the phone does not get; without a list the app shows "Can't confirm", never "OK".
#  - lists that fail the quality gate (codes, broken scans, other languages): shared/ingredients_text.py
#  - safe default (2026-10-26): Indonesian lists from Open Food Facts, until LabelSageCore loads the reviewed
#    Indonesian words (shared/allergen-terms-id.draft.json); "susu" (milk) is unknown to the English list
#  - lists in a language the app's engine cannot read yet (French, Spanish, Italian, German): "lait" is milk
HIDDEN_INGREDIENTS = ("NOT ingredients_ok OR (region LIKE '%id%' AND ingredients_from_off) "
                      "OR ingredients_lang IN ('fr', 'es', 'it', 'de')")

PHONE_PRODUCTS = 200_000   # cap on products with a photo; keeps catalog.sqlite under 60 MB


def choose_phone_products(con, limit=PHONE_PRODUCTS):
    """The phone gets the products with a photo (decision 2026-10-29); the server holds every product."""

    # job 1: always every recalled product, photo or not (safety, also offline)
    # job 2: then the products with a photo (accepted OFF photo or Amazon match), most-scanned first, with
    #        ingredients and both sources first; the barcode breaks ties, so a rerun picks the same products
    con.execute(f"""CREATE OR REPLACE TABLE phone AS
        SELECT gtin FROM merged WHERE sources & 4 > 0
        UNION
        SELECT gtin FROM (SELECT gtin FROM merged
            WHERE NOT is_stub AND (image_url IS NOT NULL OR gtin IN (SELECT gtin FROM amazon_pick))
            ORDER BY coalesce(unique_scans, 0) DESC, (ingredients IS NOT NULL) DESC, (sources & 3 = 3) DESC,
                     coalesce(completeness, 0) DESC, updated DESC NULLS LAST, gtin
            LIMIT {limit})""")
    return con.execute("SELECT count(*) FROM phone").fetchone()[0]


# ------ PHASE 3: WRITE THE PHONE TABLES FROM DUCKDB --------

def write_tables(con, path):
    """Copy the phone's products, nutrients, lookups and recalls into the SQLite file."""
    on_phone = "gtin IN (SELECT gtin FROM phone)"

    # job 1: attach the SQLite file to DuckDB
    con.execute("INSTALL sqlite; LOAD sqlite;")
    con.execute(f"ATTACH '{path}' AS cat (TYPE sqlite)")

    # job 2: lookups, so a brand or category name is stored once
    con.execute(f"""CREATE OR REPLACE TABLE brand_ids AS
        SELECT row_number() OVER (ORDER BY brand) AS brand_id, brand
        FROM (SELECT DISTINCT brand FROM merged WHERE brand IS NOT NULL AND {on_phone})""")
    con.execute(f"""CREATE OR REPLACE TABLE category_ids AS
        SELECT row_number() OVER (ORDER BY category) AS category_id, category
        FROM (SELECT DISTINCT category FROM merged WHERE category IS NOT NULL AND {on_phone})""")
    con.execute("INSERT INTO cat.brand SELECT brand_id, brand FROM brand_ids")
    con.execute("INSERT INTO cat.category (category_id, name) SELECT category_id, category FROM category_ids")

    # job 3: products, with their lineage (sources, per-source dates, confidence, region)
    con.execute(f"""INSERT INTO cat.product
        SELECT m.gtin, m.name, b.brand_id, c.category_id, m.size, m.serving_size, m.basis_ml::INTEGER,
               m.is_stub::INTEGER + 2 * m.discontinued::INTEGER + 4 * m.toddler_serving::INTEGER
                   + 8 * coalesce(m.recipe_changed, false)::INTEGER,
               m.sources, m.nova,
               CASE WHEN a.image_url IS NOT NULL THEN a.image_url
                    WHEN starts_with(m.image_url, {image_folder("m.gtin")})
                    THEN substr(m.image_url, length({image_folder("m.gtin")}) + 1) ELSE m.image_url END,
               m.confidence, m.region,
               date_diff('day', {EPOCH}, m.fdc_updated), date_diff('day', {EPOCH}, coalesce(m.off_updated, m.updated))
        FROM merged m LEFT JOIN brand_ids b ON b.brand = m.brand LEFT JOIN category_ids c ON c.category = m.category
        LEFT JOIN amazon_pick a ON a.gtin = m.gtin
        WHERE m.{on_phone}""")

    # job 4: more photos from the matched Amazon item, as file names (the app adds amazon_image_prefix)
    con.execute(f"""INSERT INTO cat.product_image
        SELECT gtin, rank, CASE WHEN starts_with(url, '{AMAZON_IMAGE_PREFIX}')
                                THEN substr(url, {len(AMAZON_IMAGE_PREFIX) + 1}) ELSE url END
        FROM amazon_pick_image WHERE rank < {MAX_PHONE_IMAGES} AND {on_phone}""")

    # job 5: nutrients as whole numbers, only for products that have at least one
    any_value = " OR ".join(f"{name} IS NOT NULL" for name in transform.NUTRIENTS)
    con.execute(f"""INSERT INTO cat.nutrient SELECT gtin, {_whole_numbers()}, from_off_mask FROM merged
                    WHERE ({any_value}) AND {on_phone}""")

    # job 6: the recalls that name a phone product
    con.execute(f"INSERT INTO cat.recall_link SELECT DISTINCT gtin, recall_number FROM recall_link WHERE {on_phone}")
    con.execute(f"""INSERT INTO cat.recall SELECT recall_number, date_diff('day', {EPOCH}, report_date), class,
                    ongoing::INTEGER, reason FROM recall
                    WHERE recall_number IN (SELECT recall_number FROM recall_link WHERE {on_phone})""")
    con.execute("DETACH cat")


# ------ PHASE 4: INGREDIENTS, COMPRESSED --------

def build_dictionary(con, size=32_768, sample=20_000):
    """A shared zlib dictionary of the most common ingredient phrases, so short lists compress better."""

    # job 1: count the phrases of a fixed sample of ingredient lists
    texts = [t for (t,) in con.execute(f"SELECT ingredients FROM merged WHERE ingredients IS NOT NULL "
                                       f"USING SAMPLE {sample} ROWS (reservoir, 42)").fetchall()]
    counts = collections.Counter(p.strip() for t in texts for p in re.split(r"[,()\[\].;:]", t) if p.strip())

    # job 2: most common phrases last, because zlib reaches the end of the dictionary most cheaply
    phrases = ", ".join(p for p, _ in reversed(counts.most_common(4000)))
    return phrases.encode()[-size:]


def write_ingredients(con, path, batch=50_000):
    """Write each ingredient list zlib-compressed with the shared dictionary; the largest part of the catalog."""

    # job 1: build the dictionary and store it in the catalog, so the app can unpack with it
    zdict = build_dictionary(con)
    rows = con.execute("SELECT gtin, ingredients, ingredients_from_off FROM merged "
                       "WHERE ingredients IS NOT NULL AND gtin IN (SELECT gtin FROM phone) "
                       f"AND NOT ({HIDDEN_INGREDIENTS})")
    with sqlite3.connect(path) as db:
        db.execute("INSERT INTO zlib_dictionary VALUES (1, ?)", (zdict,))

        # job 2: compress each list with the dictionary and write it in batches
        while chunk := rows.fetchmany(batch):
            packed = []
            for g, t, off in chunk:
                co = zlib.compressobj(9, zlib.DEFLATED, 15, 9, zlib.Z_DEFAULT_STRATEGY, zdict)
                packed.append((g, co.compress(t.encode()) + co.flush(), int(off)))
            db.executemany("INSERT INTO ingredients VALUES (?, ?, ?)", packed)


# ------ PHASE 5: FINISH --------

def finish(path, stats):
    """Name search index, catalog facts and compaction."""
    with sqlite3.connect(path) as db:

        # job 1: full-text name search, contentless so names are not stored twice; rowid = gtin
        db.executescript("""
            CREATE VIRTUAL TABLE search USING fts5(name, brand, content='', detail='column', columnsize=0);
            INSERT INTO search (rowid, name, brand) SELECT p.gtin, p.name, b.name FROM product p
                LEFT JOIN brand b USING (brand_id) WHERE p.name IS NOT NULL;
            INSERT INTO search (search) VALUES ('optimize');""")

        # job 2: what this catalog is, for the app and for the run log
        meta = {"snapshot": dt.date.today().strftime("v%G-%V"), "schema_version": str(SCHEMA_VERSION),
                "built_at": dt.datetime.now().isoformat(timespec="seconds"),
                "amazon_image_prefix": AMAZON_IMAGE_PREFIX,
                **{f"source_{s}": extract.latest_file(s).name for s in extract.SOURCES}, "stats": json.dumps(stats)}
        db.executemany("INSERT INTO catalog_meta VALUES (?, ?)", meta.items())

    # job 3: compact the file
    with sqlite3.connect(path) as db:
        db.execute("VACUUM")


# ------ PHASE 6: CHECK BEFORE SHIPPING --------

def check(path, full_path):
    """Stop the build when an output is not fit to ship; returns what was checked.
    A build that passes is the definition of "ready to deploy"."""
    problems = []
    with sqlite3.connect(path) as db:
        one = lambda sql: (db.execute(sql).fetchone() or (None,))[0]

        # job 1: the file is sound, small enough, and says which schema it has
        if one("PRAGMA integrity_check") != "ok":
            problems.append("catalog.sqlite fails the SQLite integrity check")
        size_mb = path.stat().st_size / 1e6
        if size_mb > MAX_CATALOG_MB:
            problems.append(f"catalog.sqlite is {size_mb:.1f} MB, over {MAX_CATALOG_MB} MB")
        if one("SELECT value FROM catalog_meta WHERE key = 'schema_version'") != str(SCHEMA_VERSION):
            problems.append(f"catalog_meta has no schema_version {SCHEMA_VERSION}")

        # job 2: every product has a name, and every other table points at a product
        products = one("SELECT count(*) FROM product")
        if products == 0:
            problems.append("catalog.sqlite has no products")
        if one("SELECT count(*) FROM product WHERE name IS NULL"):
            problems.append("products without a name")
        for table in ("nutrient", "ingredients", "product_image", "recall_link"):
            if one(f"SELECT count(*) FROM {table} WHERE gtin NOT IN (SELECT gtin FROM product)"):
                problems.append(f"{table} rows without a product")
        if one("SELECT count(*) FROM recall_link WHERE recall_number NOT IN (SELECT recall_number FROM recall)"):
            problems.append("recall_link rows without a recall")

        # job 3: every ingredient list unpacks with the stored dictionary, as the app will do it
        zdict = one("SELECT dict FROM zlib_dictionary WHERE id = 1")
        broken = 0
        for (blob,) in db.execute("SELECT text_z FROM ingredients"):
            try:
                zlib.decompressobj(15, zdict).decompress(blob).decode()
            except (zlib.error, UnicodeDecodeError):
                broken += 1
        if broken:
            problems.append(f"{broken} ingredient lists do not unpack")

    # job 4: the full database is sound and holds products
    with sqlite3.connect(full_path) as db:
        if db.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            problems.append("labelsage-full.sqlite fails the SQLite quick check")
        if not db.execute("SELECT count(*) FROM product").fetchone()[0]:
            problems.append("labelsage-full.sqlite has no products")

    if problems:
        raise RuntimeError("the build is not fit to ship: " + "; ".join(problems))
    return {"checked": "ok", "schema_version": SCHEMA_VERSION}


# ------ PHASE 7: PACK AND PUBLISH LOCALLY --------

def pack(path):
    """Compressed copy of the phone catalog for the download."""
    packed = path.with_suffix(".sqlite.gz")
    with open(path, "rb") as src, gzip.open(packed, "wb", compresslevel=9) as dst:
        shutil.copyfileobj(src, dst)
    return {"catalog_mb": round(path.stat().st_size / 1e6, 1), "download_mb": round(packed.stat().st_size / 1e6, 1)}


def point_latest(folder):
    """out/latest -> the newest checked build, so the app's -catalog argument and the server upload keep one path."""
    latest = OUT_DIR / "latest"
    tmp = OUT_DIR / ".latest-new"
    tmp.unlink(missing_ok=True)
    os.symlink(folder.name, tmp)     # relative: the out folder can move
    os.replace(tmp, latest)
    return str(latest)


def run(con, stats, folder=None):
    """Choose the phone products, then part A (full database), part B (phone catalog), the check, part C (server
    export). folder: where the outputs go; default OUT_DIR/<today> (the notebook passes one folder per scenario,
    and only the default build moves out/latest)."""
    weekly = folder is None
    folder = folder or OUT_DIR / dt.date.today().isoformat()
    con.execute("INSTALL sqlite; LOAD sqlite;")
    stats["amazon_images"] = full_database.read_amazon_picks(con)   # the phone choice needs the Amazon photos
    stats["phone_products"] = choose_phone_products(con)
    full = full_database.run(con, stats, folder / "labelsage-full.sqlite")
    path = folder / "catalog.sqlite"
    create_catalog(path)
    write_tables(con, path)
    write_ingredients(con, path)
    finish(path, stats)
    checked = check(path, folder / "labelsage-full.sqlite")
    sizes = pack(path)
    server = server_export.run(con, folder / "labelsage-full.sqlite", folder / "server")
    latest = {"latest": point_latest(folder)} if weekly else {}
    return {**full, "path": str(path), "phone_products": stats["phone_products"], **sizes, **checked, **server,
            **latest}
