"""Golden set for product matching without a shared ID: random FDC products and their candidate OFF records.

The task it measures: given an FDC product (name, brand, brand owner, size, ingredients) and an Open Food Facts
record, are they the same product? Barcodes are hidden from the algorithms; we only use them to build the set:
the OFF record with the same barcode (the "twin", when OFF has one) is always a candidate, so recall is not
limited by how candidates were found. The other candidates are the OFF records most similar by name and brand
(hard negatives, and sometimes the same product under another barcode).

Queries are random, with a fixed seed:
  - N_PER_CATEGORY from each of the TOP_CATEGORIES largest FDC categories, plus N_PER_CATEGORY from all other
    categories together (diversity)
  - EDGE_EXTRA more per edge case (flags in edge_flags()), so rare cases have enough pairs to measure recall

Writes golden-pairs.csv (one row per pair, label empty) and label-view.txt (what a labeler reads: no barcodes,
no scores, twin position shuffled) to OUT_DIR. Labels go into golden-pairs.csv; match/benchmark.py scores it.

Usage (from backend/etl):
  python3 match/golden_set.py                          # sample and write the pairs (overwrites the labels)
  python3 match/golden_set.py labels labels-model.txt   # copy a label file (in OUT_DIR) into golden-pairs.csv

Label file: one line per query, "Q12 1020" = labels for candidates a b c d; lines starting # are comments.
1 = same product (pack size may differ), 0 = different, 2 = can't tell (left out of the metrics).
"""
import csv
import pathlib
import random
import re
import sqlite3
import sys

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from extract import extract  # noqa: E402
from match import matcher  # noqa: E402

SEED = 20261028
TOP_CATEGORIES = 30
N_PER_CATEGORY = 15
EDGE_EXTRA = 20
CANDIDATES = 4                       # OFF records per query, the twin included
OUT_DIR = extract.RAW_DIR.parent / "out" / "golden"
FULL_DB = extract.RAW_DIR.parent / "out" / "notebook" / "fdc-first" / "labelsage-full.sqlite"

FLAVOR_WORDS = matcher.CRITICAL_WORDS - set().union(*matcher.ALLERGEN_GROUPS.values()) - {
    "natural", "unsweetened", "sweetened", "decaf", "variety", "assorted", "reduced", "light", "lite", "diet", "zero",
    "milk", "oat", "oats", "mustard", "celery", "lupin", "sulfite"}
DIET_WORDS = {"diet", "zero", "light", "lite", "reduced", "unsweetened", "decaf", "low", "fat", "nonfat", "skim"}
PACK = re.compile(r"\b(variety|assorted|multi ?pack|\d+ ?(ct|count|pack|pk))\b")


# ------ PHASE 1: READ BOTH SOURCES --------

def read_sources():
    """FDC products (US, named) with brand owner and whether OFF has the barcode; every named OFF record."""
    with sqlite3.connect(f"file:{FULL_DB}?mode=ro", uri=True) as db:

        # job 1: FDC side
        fdc = [dict(zip(("gtin", "name", "brand", "brand_owner", "category", "size", "ingredients"), r)) for r in db.execute("""
            SELECT f.gtin, f.name, f.brand, p.brand_owner, f.category, f.size, f.ingredients
            FROM source_fdc f JOIN product p USING (gtin)
            WHERE f.name IS NOT NULL AND p.region LIKE '%us%' ORDER BY f.gtin""")]

        # job 2: OFF side
        off = [dict(zip(("gtin", "name", "brand", "size", "ingredients"), r)) for r in db.execute("""
            SELECT gtin, name, brand, size, ingredients FROM source_off
            WHERE name IS NOT NULL AND length(trim(name)) > 2 ORDER BY gtin""")]
    return fdc, off


# ------ PHASE 2: CHOOSE THE QUERIES --------

def edge_flags(product, twin, big_brands):
    """Edge cases a query belongs to, from its own text and (when OFF has the barcode) its twin's."""
    name = " ".join(matcher.words(product["name"]))
    tokens = set(name.split())
    claims, _ = matcher.claims_and_contents(product["name"])
    flags = set()

    # job 1: from the FDC product alone
    if claims:
        flags.add("free_from")
    if tokens & DIET_WORDS:
        flags.add("diet_light")
    if tokens & FLAVOR_WORDS:
        flags.add("flavor")
    if PACK.search(name):
        flags.add("pack_variety")
    if matcher.PLANT_DAIRY.search(name) or tokens & matcher.PLANT_MARKERS:
        flags.add("plant_based")
    if len(tokens) <= 2:
        flags.add("short_name")
    if matcher.clean_brand(product["brand"]) in big_brands:
        flags.add("big_brand")
    if twin is None:
        flags.add("no_twin")
        return flags

    # job 2: from the twin
    ours, theirs = matcher.clean_brand(product["brand"]), matcher.clean_brand(twin["brand"])
    if not theirs:
        flags.add("off_brand_missing")
    elif ours != theirs and f" {ours} " not in f" {theirs} " and f" {theirs} " not in f" {ours} ":
        flags.add("brand_text_differs")
    if re.search(r"[^\x00-\x7f]", twin["name"] or ""):
        flags.add("off_non_ascii")
    if len(matcher.words(twin["name"])) <= len(tokens) // 2:
        flags.add("off_name_shorter")
    return flags


def choose_queries(fdc, off_by_gtin, rng):
    """Random queries per category, then extra random queries for each edge case."""

    # job 1: the biggest brands (store brands and big makers with many look-alike products)
    counts = {}
    for p in fdc:
        b = matcher.clean_brand(p["brand"])
        counts[b] = counts.get(b, 0) + 1
    big_brands = {b for b, _ in sorted(counts.items(), key=lambda x: -x[1])[:50] if b}

    # job 2: flags for every product
    for p in fdc:
        p["flags"] = edge_flags(p, off_by_gtin.get(p["gtin"]), big_brands)

    # job 3: N_PER_CATEGORY per big category, and as many from the rest together
    by_category = {}
    for p in fdc:
        by_category.setdefault(p["category"] or "(none)", []).append(p)
    top = sorted(by_category, key=lambda c: -len(by_category[c]))[:TOP_CATEGORIES]
    rest = [p for c, ps in by_category.items() if c not in top for p in ps]
    chosen = {}
    for stratum, pool in [(c, by_category[c]) for c in top] + [("other categories", rest)]:
        for p in rng.sample(pool, N_PER_CATEGORY):
            chosen[p["gtin"]] = dict(p, stratum=stratum)

    # job 4: EDGE_EXTRA more for each edge case, not already chosen
    for flag in sorted({f for p in fdc for f in p["flags"]}):
        pool = [p for p in fdc if flag in p["flags"] and p["gtin"] not in chosen]
        for p in rng.sample(pool, min(EDGE_EXTRA, len(pool))):
            chosen[p["gtin"]] = dict(p, stratum=f"edge: {flag}")
    return list(chosen.values())


# ------ PHASE 3: FIND THE CANDIDATES --------

def text(record):
    return " ".join(matcher.words(f"{record.get('brand') or ''} {record['name']}"))


def candidates(queries, off, off_by_gtin):
    """For each query: its twin (if any) plus the most similar other OFF records, by char n-gram TF-IDF."""

    # job 1: one vector per OFF record and per query
    vectorizer = TfidfVectorizer(analyzer="char_wb", ngram_range=(3, 4), min_df=2, sublinear_tf=True,
                                 dtype=np.float32)
    off_matrix = vectorizer.fit_transform([text(o) for o in off])
    query_matrix = vectorizer.transform([text(q) for q in queries])

    # job 2: top matches per query, in chunks (cosine = dot product of the normalised vectors)
    result = []
    for start in range(0, len(queries), 50):
        sims = (query_matrix[start:start + 50] @ off_matrix.T).toarray()
        for row, q in enumerate(queries[start:start + 50]):
            top = np.argpartition(-sims[row], CANDIDATES + 1)[:CANDIDATES + 1]
            top = top[np.argsort(-sims[row][top])]
            picked = []
            twin = off_by_gtin.get(q["gtin"])
            if twin:
                picked.append((twin, True, None))
            for rank, i in enumerate(top, 1):
                if len(picked) == CANDIDATES:
                    break
                if off[i]["gtin"] != q["gtin"]:
                    picked.append((off[i], False, rank))
            result.append((q, picked))
    return result


# ------ PHASE 4: WRITE THE PAIRS AND THE LABEL VIEW --------

FIELDS = ["pair_id", "query_id", "split", "stratum", "query_flags", "fdc_gtin", "off_gtin", "is_twin",
          "retrieval_rank", "fdc_name", "fdc_brand", "fdc_brand_owner", "fdc_category", "fdc_size",
          "fdc_ingredients", "off_name", "off_brand", "off_size", "off_ingredients",
          "label", "label_source", "label_note"]


def short(value, n):
    value = " ".join((value or "").split())
    return value if len(value) <= n else value[:n] + "…"


def write(pairs, rng):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rows, view = [], []
    order = list(range(len(pairs)))
    rng.shuffle(order)

    for query_id, i in enumerate(order, 1):
        q, picked = pairs[i]
        rng.shuffle(picked)                        # the twin is not always first
        split = "dev" if rng.random() < 0.5 else "test"

        # job 1: one row per pair
        view.append(f"Q{query_id} | {short(q['name'], 90)} | brand: {q['brand'] or '-'} | owner: "
                    f"{q['brand_owner'] or '-'} | size: {q['size'] or '-'} | ingr: {short(q['ingredients'], 70)}")
        for letter, (o, is_twin, rank) in zip("abcd", picked):
            rows.append({"pair_id": f"Q{query_id}{letter}", "query_id": f"Q{query_id}", "split": split,
                         "stratum": q["stratum"], "query_flags": ",".join(sorted(q["flags"])),
                         "fdc_gtin": f"{q['gtin']:014d}", "off_gtin": f"{o['gtin']:014d}", "is_twin": int(is_twin),
                         "retrieval_rank": rank or "", "fdc_name": q["name"], "fdc_brand": q["brand"],
                         "fdc_brand_owner": q["brand_owner"], "fdc_category": q["category"], "fdc_size": q["size"],
                         "fdc_ingredients": q["ingredients"], "off_name": o["name"], "off_brand": o["brand"],
                         "off_size": o["size"], "off_ingredients": o["ingredients"],
                         "label": "", "label_source": "", "label_note": ""})

            # job 2: the labeler's line: no barcode, no score, no twin marker
            view.append(f"   {letter}) {short(o['name'], 90)} | brand: {o['brand'] or '-'} | size: {o['size'] or '-'}"
                        f" | ingr: {short(o['ingredients'], 70)}")

    # job 3: files
    with open(OUT_DIR / "golden-pairs.csv", "w", newline="") as f:
        writer = csv.DictWriter(f, FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    (OUT_DIR / "label-view.txt").write_text("\n".join(view) + "\n")
    return rows


# ------ PHASE 5: COPY THE LABELS IN --------

def apply_labels(label_file, source):
    """Write each pair's label from a label file into golden-pairs.csv; every pair must get exactly one."""

    # job 1: read "Q12 1020" lines into {"Q12a": "1", ...}
    labels = {}
    for line in (OUT_DIR / label_file).read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            query_id, letters = line.split()
            labels.update({f"{query_id}{c}": v for c, v in zip("abcd", letters)})

    # job 2: fill the column, refuse a pair without a label
    with open(OUT_DIR / "golden-pairs.csv", newline="") as f:
        rows = list(csv.DictReader(f))
    missing = [r["pair_id"] for r in rows if r["pair_id"] not in labels]
    if missing:
        raise SystemExit(f"{len(missing)} pairs have no label, first {missing[:5]}")
    for r in rows:
        r["label"], r["label_source"] = labels[r["pair_id"]], source
    with open(OUT_DIR / "golden-pairs.csv", "w", newline="") as f:
        writer = csv.DictWriter(f, FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    return {v: sum(r["label"] == v for r in rows) for v in "102"}


if __name__ == "__main__" and sys.argv[1:2] == ["labels"]:
    print(apply_labels(sys.argv[2], "model"))
elif __name__ == "__main__":
    rng = random.Random(SEED)
    fdc, off = read_sources()
    off_by_gtin = {o["gtin"]: o for o in off}
    queries = choose_queries(fdc, off_by_gtin, rng)
    rows = write(candidates(queries, off, off_by_gtin), rng)
    print(f"{len(queries)} queries, {len(rows)} pairs, {sum(r['is_twin'] for r in rows)} twins -> {OUT_DIR}")
