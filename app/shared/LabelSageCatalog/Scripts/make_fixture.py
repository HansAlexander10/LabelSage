"""Cut a small test catalog from a real catalog.sqlite built by app/backend/etl.

Usage: python3 make_fixture.py <path to catalog.sqlite> <output fixture path>
Keeps Cheerios, 20 products in its category, the products of two recalls and Bear Brand (Indonesia).
"""
import pathlib
import sqlite3
import sys

source, target = sys.argv[1], pathlib.Path(sys.argv[2])
target.unlink(missing_ok=True)
src = sqlite3.connect(source)
dst = sqlite3.connect(target)

# job 1: same tables (the search index is rebuilt below)
for (sql,) in src.execute("SELECT sql FROM sqlite_master WHERE type = 'table' AND sql IS NOT NULL "
                          "AND name NOT LIKE 'search%' AND name NOT LIKE 'sqlite_%'"):
    dst.execute(sql)

# job 2: pick the products
cheerios = 16000275287
category = src.execute("SELECT category_id FROM product WHERE gtin = ?", (cheerios,)).fetchone()[0]
picked = {cheerios, 666186277621, 94922980045, 8992696404441}  # + Bear Brand (Indonesia)
picked |= {g for (g,) in src.execute("SELECT p.gtin FROM product p JOIN ingredients i USING (gtin) "
                                     "WHERE category_id = ? ORDER BY p.gtin LIMIT 20", (category,))}
marks = ",".join("?" * len(picked))

# job 3: copy their rows and what they point to
def copy(table, where, args=()):
    rows = src.execute(f"SELECT * FROM {table} WHERE {where}", args).fetchall()
    if rows:
        dst.executemany(f"INSERT INTO {table} VALUES ({','.join('?' * len(rows[0]))})", rows)

for table in ("product", "nutrient", "ingredients"):
    copy(table, f"gtin IN ({marks})", tuple(picked))
copy("recall_link", f"gtin IN ({marks})", tuple(picked))
copy("recall", "recall_number IN (SELECT recall_number FROM recall_link WHERE gtin IN (%s))" % marks, tuple(picked))
copy("brand", f"brand_id IN (SELECT brand_id FROM product WHERE gtin IN ({marks}))", tuple(picked))
copy("category", f"category_id IN (SELECT category_id FROM product WHERE gtin IN ({marks}))", tuple(picked))
copy("zlib_dictionary", "1")
copy("catalog_meta", "key IN ('snapshot', 'schema_version')")

# job 4: the same contentless search index as the real catalog
dst.executescript("CREATE VIRTUAL TABLE search USING fts5(name, brand, content='', detail='column', columnsize=0);")
dst.executemany("INSERT INTO search (rowid, name, brand) VALUES (?, ?, ?)",
                dst.execute("SELECT p.gtin, p.name, b.name FROM product p LEFT JOIN brand b USING (brand_id)").fetchall())
dst.commit()
dst.execute("VACUUM")
print(target, target.stat().st_size, "bytes,", len(picked), "products")
