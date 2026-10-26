"""Load: write the merged products into catalog.sqlite, the file the phone downloads.

DuckDB writes the tables into the SQLite file through its sqlite extension; Python's sqlite3
then adds the compressed ingredients, the name search index and the final packing.
"""
import collections
import datetime as dt
import gzip
import re
import json
import pathlib
import shutil
import sqlite3
import zlib

from extract import extract
from transform import transform

HERE = pathlib.Path(__file__).resolve().parent
OUT_DIR = extract.RAW_DIR.parent / "out"
IMAGE_PREFIX = "https://images.openfoodfacts.org/images/products/"
EPOCH = "DATE '1970-01-01'"


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


# ------ PHASE 2: WRITE THE TABLES FROM DUCKDB --------

def write_tables(con, path):
    """Copy products, nutrients, lookups, recalls and generic foods into the SQLite file."""

    # job 1: attach the SQLite file to DuckDB
    con.execute("INSTALL sqlite; LOAD sqlite;")
    con.execute(f"ATTACH '{path}' AS cat (TYPE sqlite)")

    # job 2: lookups, so a brand or category name is stored once
    con.execute("""CREATE OR REPLACE TABLE brand_ids AS
        SELECT row_number() OVER (ORDER BY brand) AS brand_id, brand FROM (SELECT DISTINCT brand FROM merged WHERE brand IS NOT NULL)""")
    con.execute("""CREATE OR REPLACE TABLE category_ids AS
        SELECT row_number() OVER (ORDER BY category) AS category_id, category FROM
        (SELECT category FROM merged UNION SELECT category FROM generic_food) WHERE category IS NOT NULL""")
    con.execute("INSERT INTO cat.brand SELECT brand_id, brand FROM brand_ids")
    con.execute("INSERT INTO cat.category (category_id, name) SELECT category_id, category FROM category_ids")

    # job 3: products
    con.execute(f"""INSERT INTO cat.product
        SELECT m.gtin, m.name, b.brand_id, c.category_id, m.size, m.serving_size, m.basis_ml::INTEGER,
               m.is_stub::INTEGER + 2 * m.discontinued::INTEGER + 4 * m.toddler_serving::INTEGER, m.sources, m.nova,
               CASE WHEN starts_with(m.image_url, {image_folder("m.gtin")})
                    THEN substr(m.image_url, length({image_folder("m.gtin")}) + 1) ELSE m.image_url END,
               date_diff('day', {EPOCH}, m.updated)
        FROM merged m LEFT JOIN brand_ids b ON b.brand = m.brand LEFT JOIN category_ids c ON c.category = m.category""")

    # job 4: nutrients as whole numbers, only for products that have at least one
    any_value = " OR ".join(f"{name} IS NOT NULL" for name in transform.NUTRIENTS)
    con.execute(f"INSERT INTO cat.nutrient SELECT gtin, {_whole_numbers()}, from_off_mask FROM merged WHERE {any_value}")

    # job 5: recalls that name a barcode, and the natural foods
    con.execute(f"""INSERT INTO cat.recall SELECT recall_number, date_diff('day', {EPOCH}, report_date), class,
                    ongoing::INTEGER, reason FROM recall WHERE recall_number IN (SELECT recall_number FROM recall_link)""")
    con.execute("INSERT INTO cat.recall_link SELECT gtin, recall_number FROM recall_link")
    con.execute(f"""INSERT INTO cat.generic_food SELECT g.fdc_id, g.name, c.category_id, {_whole_numbers('g.')}
                    FROM generic_food g LEFT JOIN category_ids c ON c.category = g.category""")
    con.execute("DETACH cat")


# ------ PHASE 3: INGREDIENTS, COMPRESSED --------

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
    rows = con.execute("SELECT gtin, ingredients, ingredients_from_off FROM merged WHERE ingredients IS NOT NULL")
    with sqlite3.connect(path) as db:
        db.execute("INSERT INTO zlib_dictionary VALUES (1, ?)", (zdict,))

        # job 2: compress each list with the dictionary and write it in batches
        while chunk := rows.fetchmany(batch):
            packed = []
            for g, t, off in chunk:
                co = zlib.compressobj(9, zlib.DEFLATED, 15, 9, zlib.Z_DEFAULT_STRATEGY, zdict)
                packed.append((g, co.compress(t.encode()) + co.flush(), int(off)))
            db.executemany("INSERT INTO ingredients VALUES (?, ?, ?)", packed)


# ------ PHASE 4: FINISH AND PACK --------

def finish(path, stats):
    """Name search index, catalog facts, compaction, and a gzip copy for download."""
    with sqlite3.connect(path) as db:

        # job 1: full-text name search, contentless so names are not stored twice;
        #        rowid = gtin for a product, -fdc_id for a generic food
        db.executescript("""
            CREATE VIRTUAL TABLE search USING fts5(name, brand, content='', detail='column', columnsize=0);
            INSERT INTO search (rowid, name, brand) SELECT p.gtin, p.name, b.name FROM product p
                LEFT JOIN brand b USING (brand_id) WHERE p.name IS NOT NULL;
            INSERT INTO search (rowid, name, brand) SELECT -fdc_id, name, NULL FROM generic_food;
            INSERT INTO search (search) VALUES ('optimize');""")

        # job 2: what this catalog is, for the app and for the run log
        meta = {"snapshot": dt.date.today().strftime("v%G-%V"), "built_at": dt.datetime.now().isoformat(timespec="seconds"),
                **{f"source_{s}": extract.latest_file(s).name for s in extract.SOURCES}, "stats": json.dumps(stats)}
        db.executemany("INSERT INTO catalog_meta VALUES (?, ?)", meta.items())

    # job 3: compact the file
    with sqlite3.connect(path) as db:
        db.execute("VACUUM")

    # job 4: compressed copy for the download
    packed = path.with_suffix(".sqlite.gz")
    with open(path, "rb") as src, gzip.open(packed, "wb", compresslevel=9) as dst:
        shutil.copyfileobj(src, dst)
    return {"catalog_mb": round(path.stat().st_size / 1e6, 1), "download_mb": round(packed.stat().st_size / 1e6, 1)}


def run(con, stats):
    """All load phases in order. Returns the file sizes."""
    path = OUT_DIR / dt.date.today().isoformat() / "catalog.sqlite"
    create_catalog(path)
    write_tables(con, path)
    write_ingredients(con, path)
    sizes = finish(path, stats)
    return {"path": str(path), **sizes}
