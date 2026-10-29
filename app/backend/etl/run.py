"""Run the ETL phases in order.

Usage:
  python3 app/backend/etl/run.py download   # fetch any missing source files
  python3 app/backend/etl/run.py profile    # count what the downloaded files hold
  python3 app/backend/etl/run.py build      # transform, load, check: write the three outputs
  python3 app/backend/etl/run.py app        # copy the newest checked catalog.sqlite into the iOS app
  python3 app/backend/etl/run.py amazon 1000   # ask Amazon about the next 1,000 barcodes, then score them
                                               # (needs SP_API_* credentials; the next build uses the result)

Raw files, work files and the output stay in ~/Projects/ai-shopping-agent-data/, outside git.
"""
import json
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from extract import extract  # noqa: E402


# ------ PHASE 1: EXTRACT --------

def run_download():

    # job 1: download every source that has no copy yet
    for source in extract.SOURCES:
        if extract.latest_file(source) is None:
            print("downloading", source)
            extract.download(source)

    # job 2: show where each copy is
    for source in extract.SOURCES:
        print(source, extract.latest_file(source))


def run_profile():

    # job 1: count the rows in every downloaded file
    print(json.dumps(extract.profile(), indent=2))


# ------ PHASE 2: TRANSFORM AND LOAD --------

def run_build():
    import duckdb
    from load import load
    from transform import transform

    # job 1: a DuckDB work file, so large joins can spill to disk instead of memory
    extract.WORK_DIR.mkdir(parents=True, exist_ok=True)
    work_db = extract.WORK_DIR / "build.duckdb"
    work_db.unlink(missing_ok=True)
    con = duckdb.connect(str(work_db))
    con.execute("SET enable_progress_bar = false")

    # job 2: transform, then load
    start = time.time()
    stats = transform.run(con)
    print("transform", json.dumps(stats), f"{time.time() - start:.0f}s")
    result = load.run(con, stats)
    print("load", json.dumps(result), f"{time.time() - start:.0f}s")
    con.close()


# ------ PHASE 3: SHIP THE CATALOG IN THE APP --------

APP_DATA = pathlib.Path(__file__).resolve().parents[2] / "frontend" / "ios" / "LabelSage" / "Resources" / "Data"


def run_app():
    import shutil
    import sqlite3
    from load import load

    # job 1: the newest build that passed the check (out/latest), never an unchecked one
    source = load.OUT_DIR / "latest" / "catalog.sqlite"
    if not source.exists():
        sys.exit("no checked build yet: run `run.py build` first")

    # job 2: copy it into the app's resources, where the app finds it as catalog.sqlite in its bundle
    target = APP_DATA / "catalog.sqlite"
    shutil.copyfile(source, target)
    with sqlite3.connect(f"file:{target}?mode=ro", uri=True) as db:
        meta = dict(db.execute("SELECT key, value FROM catalog_meta WHERE key IN ('snapshot', 'schema_version')"))
    print("copied", source.resolve(), "->", target, f"{target.stat().st_size / 1e6:.1f} MB", meta)


# ------ PHASE 4: AMAZON (API, NOT PART OF THE WEEKLY BUILD) --------

def run_amazon():
    from extract import amazon
    from match import amazon_match

    # job 1: fetch the next barcodes into amazon.sqlite, then score and pick one Amazon item per barcode
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
    print("fetch", json.dumps(amazon.fetch(limit)))
    print("match", json.dumps(amazon_match.run()))


if __name__ == "__main__":
    {"download": run_download, "profile": run_profile, "build": run_build, "app": run_app,
     "amazon": run_amazon}[sys.argv[1] if len(sys.argv) > 1 else "profile"]()
