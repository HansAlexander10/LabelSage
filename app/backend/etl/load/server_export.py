"""Load, part C: export the processed data for the server (data migration).

The ETL runs on premise; the server only receives finished tables. Every table of labelsage-full.sqlite is
written as one Parquet file (zstd), a format any server database can import (Postgres, MySQL, DuckDB, BigQuery).
A manifest lists each file with its rows and size, so the transfer can be checked on arrival.
"""
import json


# ------ PHASE 1: ONE PARQUET FILE PER TABLE --------

def run(con, full_path, folder):
    """Export every table of the full database to folder/<table>.parquet. Returns sizes for the run log."""

    # job 1: a clean folder and the full database attached read-only
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("*.parquet"):
        old.unlink()
    con.execute("INSTALL sqlite; LOAD sqlite;")
    con.execute(f"ATTACH '{full_path}' AS src (TYPE sqlite, READ_ONLY)")
    tables = [t for (t,) in con.execute(
        f"SELECT name FROM sqlite_scan('{full_path}', 'sqlite_master') WHERE type = 'table' ORDER BY name").fetchall()]

    # job 2: one compressed Parquet file per table
    manifest = {}
    for table in tables:
        out = folder / f"{table}.parquet"
        con.execute(f"COPY (SELECT * FROM src.{table}) TO '{out}' (FORMAT parquet, COMPRESSION zstd)")
        rows = con.execute(f"SELECT count(*) FROM src.{table}").fetchone()[0]
        manifest[table] = {"file": out.name, "rows": rows, "bytes": out.stat().st_size}
    con.execute("DETACH src")

    # job 3: the manifest the server checks after the transfer
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2))
    total = sum(m["bytes"] for m in manifest.values())
    return {"server_path": str(folder), "server_mb": round(total / 1e6, 1)}
