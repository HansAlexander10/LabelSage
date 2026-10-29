"""Extract, Amazon: look our barcodes up in the SP-API catalog and keep every answer in amazon.sqlite.

Unlike the other sources there is no file to download: each answer costs an API call, so amazon.sqlite
(extract.AMAZON_DB, schema schemas/amazon.sql) is kept across builds and a barcode is not asked again until
REFRESH_DAYS have passed. Scoring the answers is the next step (match/amazon_match.py).

Credentials come from the environment only: SP_API_CLIENT_ID, SP_API_CLIENT_SECRET, SP_API_REFRESH_TOKEN.

Usage:
  python3 app/backend/etl/run.py amazon 1000      # fetch the next 1,000 barcodes, then score them
"""
import datetime as dt
import json
import pathlib
import sqlite3

from extract import extract
from match import sp_api

HERE = pathlib.Path(__file__).resolve().parent
SCHEMA = HERE.parents[1] / "schemas" / "amazon.sql"
OUT_DIR = extract.RAW_DIR.parent / "out"
REFRESH_DAYS = 30            # ask Amazon about a barcode again after this many days
NAME_BRAND_RESULTS = 5       # candidates per keyword search, for barcodes Amazon does not list


def now():
    return dt.datetime.now().isoformat(timespec="seconds")


# ------ PHASE 1: OPEN AMAZON.SQLITE --------

def open_db(path=None):
    """Open amazon.sqlite; create it from the schema the first time. Never deleted: every row cost an API call."""

    # job 1: create the file and its tables once
    path = path or extract.AMAZON_DB
    new = not path.exists()
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    if new:
        db.executescript(SCHEMA.read_text())
    return db


# ------ PHASE 2: CHOOSE THE BARCODES TO ASK ABOUT --------

def latest_full_database():
    """The newest dated build's labelsage-full.sqlite (OUT_DIR/<date>/), which holds the match_input view."""
    builds = sorted(OUT_DIR.glob("????-??-??/labelsage-full.sqlite"))
    if not builds:
        raise FileNotFoundError(f"no labelsage-full.sqlite in {OUT_DIR}/<date>/: run `run.py build` first")
    return builds[-1]


def in_store_code(gtin):
    """True for barcodes a shop prints for itself (no maker behind them, so Amazon cannot list them).

    GTIN-14 forms: EAN-8 starting 0 or 2 ("000000" + "2..."), EAN-13 prefixes 20-29 ("02..."),
    UPC number systems 2 (random weight) and 4 (in-store) ("002...", "004...").
    """
    return ((gtin.startswith("000000") and gtin[6] in "02")
            or (gtin[0] == "0" and gtin[1] == "2")
            or (gtin[:2] == "00" and gtin[2] in "24"))


def barcodes_to_fetch(db, full_db, limit):
    """Up to `limit` match_input rows, most-scanned first, not asked within REFRESH_DAYS and not in-store codes."""

    # job 1: barcodes asked recently (any method)
    since = (dt.datetime.now() - dt.timedelta(days=REFRESH_DAYS)).isoformat(timespec="seconds")
    recent = {g for (g,) in db.execute("SELECT DISTINCT gtin FROM amazon_lookup WHERE requested_at >= ?", (since,))}

    # job 2: walk match_input in its order until we have enough
    rows = []
    with sqlite3.connect(f"file:{full_db}?mode=ro", uri=True) as full:
        full.row_factory = sqlite3.Row
        for row in full.execute("SELECT gtin, name, brand, brand_owner, ingredients FROM match_input"):
            if int(row["gtin"]) in recent or in_store_code(row["gtin"]):
                continue
            rows.append(dict(row))
            if len(rows) == limit:
                break
    return rows


def batches(rows):
    """Groups of up to sp_api.BATCH_SIZE barcodes of one kind (UPC = GTIN-14 starting "00", else EAN)."""
    for kind in (True, False):
        same = [r for r in rows if r["gtin"].startswith("00") == kind]
        for i in range(0, len(same), sp_api.BATCH_SIZE):
            yield same[i:i + sp_api.BATCH_SIZE]


# ------ PHASE 3: SAVE WHAT AMAZON RETURNED --------

def save_items(db, items, marketplace_id):
    """Write each item, its barcodes and its images; a refetched item replaces the old rows."""
    asins = []
    for item in items:
        row, identifiers, images, _ = sp_api.parse_item(item, marketplace_id)
        asins.append(row["asin"])

        # job 1: the item itself
        db.execute("""INSERT OR REPLACE INTO amazon_item (asin, marketplace_id, item_name, brand, manufacturer,
                      product_type, item_classification, parent_asin, package_quantity, size_name, ingredients_text,
                      allergen_info, fetched_at, raw_json)
                      VALUES (:asin, :marketplace_id, :item_name, :brand, :manufacturer, :product_type,
                      :item_classification, :parent_asin, :package_quantity, :size_name, :ingredients_text,
                      :allergen_info, :fetched_at, :raw_json)""", {**row, "fetched_at": now()})

        # job 2: its barcodes and images, replaced as a whole (Amazon adds and removes images)
        for table in ("amazon_item_identifier", "amazon_image"):
            db.execute(f"DELETE FROM {table} WHERE asin = ? AND marketplace_id = ?", (row["asin"], marketplace_id))
        db.executemany("""INSERT OR IGNORE INTO amazon_item_identifier VALUES
                          (:asin, :marketplace_id, :identifier_type, :identifier, :gtin)""",
                       [{**i, "gtin": int(i["gtin"]) if i["gtin"] else None} for i in identifiers])
        db.executemany("INSERT INTO amazon_image VALUES (:asin, :marketplace_id, :variant, :url, :width, :height)",
                       images)
    return asins


def save_lookup(db, gtin, method, query, status, asins, marketplace_id):
    """One amazon_lookup row per barcode and request, plus which items came back for it."""
    cursor = db.execute("""INSERT INTO amazon_lookup (gtin, method, query, marketplace_id, http_status, candidates,
                           requested_at) VALUES (?, ?, ?, ?, ?, ?, ?)""",
                        (int(gtin), method, query, marketplace_id, status, len(asins), now()))
    db.executemany("INSERT INTO amazon_lookup_item VALUES (?, ?, ?, ?)",
                   [(cursor.lastrowid, asin, marketplace_id, rank) for rank, asin in enumerate(asins)])


# ------ PHASE 4: ASK AMAZON --------

class StopFetch(Exception):
    """Amazon refused (bad credentials, no access, still throttled): stop, so no barcode is saved as 'no hit'."""


def fetch(limit=1000, full_db=None, client=None):
    """Ask Amazon about up to `limit` barcodes: by barcode in batches, then by name + brand for the misses."""
    db = open_db()
    client = client or sp_api.Client()
    market = client.marketplace_id
    rows = barcodes_to_fetch(db, full_db or latest_full_database(), limit)
    stats = {"barcodes": len(rows), "calls": 0, "found_by_barcode": 0, "found_by_name_brand": 0, "not_found": 0}

    for batch in batches(rows):

        # job 1: one call per batch of 20 barcodes of one kind
        status, items, _ = client.search_barcodes([r["gtin"] for r in batch])
        stats["calls"] += 1
        if status != 200:
            raise StopFetch(f"searchCatalogItems by barcode returned HTTP {status}; nothing saved for this batch")
        save_items(db, items, market)

        # job 2: hand each item to the barcodes it lists (one ASIN can list several of ours, or none)
        listed = {}
        for item in items:
            _, identifiers, _, _ = sp_api.parse_item(item, market)
            for gtin in {i["gtin"] for i in identifiers if i["gtin"]}:
                listed.setdefault(gtin, []).append(item["asin"])
        misses = []
        for row in batch:
            asins = listed.get(row["gtin"], [])
            code = row["gtin"][2:] if row["gtin"].startswith("00") else row["gtin"][1:]
            save_lookup(db, row["gtin"], "barcode", code, status, asins, market)
            if asins:
                stats["found_by_barcode"] += 1
            else:
                misses.append(row)
        db.commit()

        # job 3: barcodes Amazon does not list: one keyword search each (name + brand); the matcher is stricter here
        for row in misses:
            status, items, query = client.search_name_brand(row["name"], row["brand"], NAME_BRAND_RESULTS)
            stats["calls"] += 1
            if status != 200:
                raise StopFetch(f"searchCatalogItems by keywords returned HTTP {status} for {row['gtin']}")
            asins = save_items(db, items, market)
            save_lookup(db, row["gtin"], "name_brand", query, status, asins, market)
            stats["found_by_name_brand" if asins else "not_found"] += 1
            db.commit()

    db.close()
    return stats


if __name__ == "__main__":
    print(json.dumps(fetch(limit=20), indent=2))
