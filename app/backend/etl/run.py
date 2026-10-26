"""Run the ETL phases in order.

Usage:
  python3 app/backend/etl/run.py download   # fetch any missing source files
  python3 app/backend/etl/run.py profile    # count what the downloaded files hold
  python3 app/backend/etl/run.py build      # transform and load: write catalog.sqlite for the phone

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


if __name__ == "__main__":
    {"download": run_download, "profile": run_profile, "build": run_build}[sys.argv[1] if len(sys.argv) > 1 else "profile"]()
