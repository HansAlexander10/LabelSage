---
type: reference
entity: backend/schemas
owner: Bagus
status: draft
updated: 2026-10-26
---

# backend/schemas

`catalog.sql` is the schema of `catalog.sqlite`, the read-only product catalog the phone downloads every week.
`app/backend/etl/load/load.py` creates the file from it; `app/shared/LabelSageCatalog` reads it.

| Table | One row per | Holds |
|---|---|---|
| `product` | barcode (GTIN-14 as a number) | name, brand, category, size, serving size, flags, sources, NOVA group, image file, date |
| `nutrient` | product | 12 nutrients per 100 g as whole numbers (`_cg` = hundredths of a gram) |
| `ingredients` | product | the ingredient list as printed, zlib-compressed with the shared dictionary |
| `zlib_dictionary` | catalog | the dictionary needed to unpack ingredients |
| `brand`, `category` | value | lookups, so each name is stored once |
| `recall`, `recall_link` | recall; recall and barcode | recalls that name a barcode |
| `generic_food` | FDC food | natural foods without a barcode |
| `search` | product or generic food | contentless FTS5 name index: `rowid` = barcode, or `-fdc_id` for a generic food |
| `catalog_meta` | key | snapshot version, source files, build counts |

Facts:
- `catalog.sql` → defines → the tables of `catalog.sqlite`
- `load.py` → creates → `catalog.sqlite` from `catalog.sql`
