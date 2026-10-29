"""Match: score what extract/amazon.py fetched and choose one Amazon item (ASIN) per barcode.

Reads amazon.sqlite and the match_input view of labelsage-full.sqlite; writes amazon_match (every scored pair,
per matcher version) and product_amazon (the one ASIN per barcode). Rows a person decided are never changed.
The next `run.py build` puts the chosen item's images into labelsage-full.sqlite and the phone catalog.
"""
import json
import sqlite3

from extract import amazon
from match import matcher, sp_api


# ------ PHASE 1: WHAT TO SCORE --------

def unscored(db):
    """Barcodes with fetched candidates and no score from the current matcher version."""
    return {g for (g,) in db.execute("""
        SELECT DISTINCT l.gtin FROM amazon_lookup l JOIN amazon_lookup_item li USING (lookup_id)
        WHERE NOT EXISTS (SELECT 1 FROM amazon_match m WHERE m.gtin = l.gtin AND m.matcher_version = ?)""",
        (matcher.MATCHER_VERSION,))}


def our_products(full_db, gtins):
    """match_input rows for these barcodes (one pass over the view)."""
    wanted, ours = {f"{g:014d}" for g in gtins}, {}
    with sqlite3.connect(f"file:{full_db}?mode=ro", uri=True) as full:
        full.row_factory = sqlite3.Row
        for row in full.execute("SELECT gtin, name, brand, brand_owner, ingredients FROM match_input"):
            if row["gtin"] in wanted:
                ours[int(row["gtin"])] = dict(row)
    return ours


def candidates(db, gtin):
    """(method, matcher view) of every item returned for this barcode; a barcode hit wins over a keyword hit."""
    found = {}
    for method, raw in db.execute("""
            SELECT l.method, i.raw_json FROM amazon_lookup l JOIN amazon_lookup_item li USING (lookup_id)
            JOIN amazon_item i ON i.asin = li.asin AND i.marketplace_id = li.marketplace_id
            WHERE l.gtin = ? ORDER BY l.method = 'barcode'""", (gtin,)):
        item = json.loads(raw)
        found[item["asin"]] = (method, sp_api.parse_item(item, sp_api.US_MARKETPLACE)[3])
    return list(found.values())


# ------ PHASE 2: SCORE AND PICK --------

def run(full_db=None):
    db = amazon.open_db()
    gtins = unscored(db)
    ours = our_products(full_db or amazon.latest_full_database(), gtins)
    stats = {"barcodes": len(gtins), "scored_pairs": 0, "picked": 0, "no_pick": 0}

    for gtin in gtins:
        if gtin not in ours:            # gone from match_input since the fetch
            continue

        # job 1: score every candidate with the method that found it; keep every score
        scored = []
        for method, item in candidates(db, gtin):
            score = matcher.score_pair(ours[gtin], item, method)
            scored.append((item, score))
            db.execute("""INSERT OR REPLACE INTO amazon_match VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                       (gtin, item["asin"], sp_api.US_MARKETPLACE, matcher.MATCHER_VERSION, method,
                        score["brand_score"], score["title_score"], score["penalty"], score["confidence"],
                        score["tier"], json.dumps(score["reasons"]), amazon.now()))
        stats["scored_pairs"] += len(scored)

        # job 2: one winner, or none (ambiguous winners go to review); a person's decision stays
        best = matcher.pick_best(scored)
        if db.execute("SELECT 1 FROM product_amazon WHERE gtin = ? AND decided_by <> 'matcher'", (gtin,)).fetchone():
            continue
        db.execute("DELETE FROM product_amazon WHERE gtin = ?", (gtin,))
        if best is None:
            stats["no_pick"] += 1
            continue
        item, score = best
        method = next(m for m, i in candidates(db, gtin) if i["asin"] == item["asin"])
        db.execute("INSERT INTO product_amazon VALUES (?, ?, ?, ?, ?, ?, 'matcher', ?, ?)",
                   (gtin, item["asin"], sp_api.US_MARKETPLACE, matcher.MATCHER_VERSION, method,
                    score["confidence"], item["main_image"], amazon.now()))
        stats["picked"] += 1
    db.commit()
    db.close()
    return stats
