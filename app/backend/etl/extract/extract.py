"""Extract: download the full source files and read them row by row.

Sources (full downloads, no API):
  - openFDA food recalls        one JSON file inside a zip
  - FDC Branded Foods           CSV files inside a zip (packaged products with barcodes)
  - FDC Foundation, SR Legacy   CSV files inside a zip (generic foods: apples, raw chicken)
  - Open Food Facts             one tab-separated CSV, gzip-compressed

Raw files live outside git in RAW_DIR/<source>/<download-date>/ and are never changed.
"""
import csv
import datetime as dt
import gzip
import io
import json
import pathlib
import shutil
import urllib.request
import zipfile

RAW_DIR = pathlib.Path.home() / "Projects/ai-shopping-agent-data/raw"
WORK_DIR = RAW_DIR.parent / "work"  # unpacked copies for DuckDB; safe to delete

SOURCES = {
    "openfda": {
        "folder": "openfda",
        "file": "food-enforcement-0001-of-0001.json.zip",
        "url": "https://download.open.fda.gov/food/enforcement/food-enforcement-0001-of-0001.json.zip",
    },
    "fdc_branded": {
        "folder": "fdc",
        "file": "FoodData_Central_branded_food_csv_2026-04-30.zip",
        "url": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_branded_food_csv_2026-04-30.zip",
    },
    "fdc_foundation": {
        "folder": "fdc",
        "file": "FoodData_Central_foundation_food_csv_2026-04-30.zip",
        "url": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_csv_2026-04-30.zip",
    },
    "fdc_sr_legacy": {
        "folder": "fdc",
        "file": "FoodData_Central_sr_legacy_food_csv_2018-04.zip",
        "url": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip",
    },
    "off": {
        "folder": "off",
        "file": "en.openfoodfacts.org.products.csv.gz",
        "url": "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz",
    },
}

csv.field_size_limit(10_000_000)  # OFF and FDC have very long text fields


# ------ PHASE 1: FIND OR DOWNLOAD THE RAW FILES --------

def latest_file(source):
    """Return the newest downloaded copy of a source file, or None."""

    # job 1: look in every dated folder of this source
    spec = SOURCES[source]
    copies = sorted((RAW_DIR / spec["folder"]).glob(f"*/{spec['file']}"))

    # job 2: the folder names are dates, so the last one is the newest
    return copies[-1] if copies else None


def download(source, day=None):
    """Download a source file into RAW_DIR/<folder>/<day>/ unless that copy exists."""

    # job 1: build the target path for today's copy
    spec = SOURCES[source]
    day = day or dt.date.today().isoformat()
    target = RAW_DIR / spec["folder"] / day / spec["file"]
    if target.exists():
        return target

    # job 2: download to a temporary name, then rename, so a broken download never looks complete
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(target.suffix + ".part")
    urllib.request.urlretrieve(spec["url"], partial)
    partial.rename(target)
    return target


def unpack(source, tables):
    """Unpack FDC CSV tables from a zip into WORK_DIR, because DuckDB cannot read inside a zip."""

    # job 1: one work folder per downloaded zip, named after it
    path = latest_file(source)
    folder = WORK_DIR / source / path.stem
    folder.mkdir(parents=True, exist_ok=True)

    # job 2: copy each table out once; a finished file is never unpacked again
    with zipfile.ZipFile(path) as zf:
        for table in tables:
            out = folder / f"{table}.csv"
            if out.exists():
                continue
            name = next(n for n in zf.namelist() if n.endswith(f"/{table}.csv"))
            partial = out.with_suffix(".part")
            with zf.open(name) as src, open(partial, "wb") as dst:
                shutil.copyfileobj(src, dst)
            partial.rename(out)
    return folder


# ------ PHASE 2: READ THE RAW FILES ROW BY ROW --------

def read_openfda(path):
    """Yield one dict per food recall."""

    # job 1: the zip holds one JSON file with "meta" and "results"
    with zipfile.ZipFile(path) as zf:
        data = json.loads(zf.read(zf.namelist()[0]))

    # job 2: hand out the recalls one by one
    yield from data["results"]


def read_fdc(path, table):
    """Yield one dict per row of one FDC CSV table, e.g. "branded_food" or "food_nutrient"."""

    # job 1: find the table inside the zip (it sits in a dated subfolder)
    with zipfile.ZipFile(path) as zf:
        name = next(n for n in zf.namelist() if n.endswith(f"/{table}.csv") or n == f"{table}.csv")

        # job 2: stream the rows without unzipping to disk
        with zf.open(name) as raw:
            yield from csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8"))


def read_off(path, us_only=True):
    """Yield one dict per Open Food Facts product."""

    # job 1: stream the tab-separated file straight from the gzip
    with gzip.open(path, "rt", encoding="utf-8", newline="") as fh:
        for row in csv.DictReader(fh, delimiter="\t", quoting=csv.QUOTE_NONE):

            # job 2: keep only products sold in the United States
            if us_only and "en:united-states" not in (row.get("countries_tags") or ""):
                continue
            yield row


# ------ PHASE 3: PROFILE (HOW MUCH DATA DO WE HAVE?) --------

def profile():
    """Count the rows in every downloaded source, to check the full databases are complete."""
    report = {}

    # job 1: openFDA recalls, and how many mention a UPC
    path = latest_file("openfda")
    if path:
        recalls = list(read_openfda(path))
        with_upc = sum("UPC" in (r.get("product_description", "") + r.get("code_info", "")).upper() for r in recalls)
        report["openfda"] = {"file": str(path), "recalls": len(recalls), "mention_upc": with_upc}

    # job 2: FDC tables (products are one row per fdc_id in "food")
    for source in ("fdc_branded", "fdc_foundation", "fdc_sr_legacy"):
        path = latest_file(source)
        if path:
            report[source] = {"file": str(path), "foods": sum(1 for _ in read_fdc(path, "food"))}

    # job 3: Open Food Facts, all products and US products
    path = latest_file("off")
    if path:
        total = us = 0
        for row in read_off(path, us_only=False):
            total += 1
            us += "en:united-states" in (row.get("countries_tags") or "")
        report["off"] = {"file": str(path), "products": total, "us_products": us}

    return report


if __name__ == "__main__":
    print(json.dumps(profile(), indent=2))
