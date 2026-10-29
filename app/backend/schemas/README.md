---
type: reference
entity: backend/schemas
owner: Bagus
status: draft
updated: 2026-10-29
---

# backend/schemas

The ETL writes two databases in one run. `full.sql` is the whole cleaned database for the team, on the build
machine. `catalog.sql` is the slim export the phone downloads. `amazon.sql` is a third, separate file that the
Amazon match step fills and the build only reads.

## Full database: labelsage-full.sqlite

`full.sql` defines the whole cleaned database: readable values, plain ingredient lists, each source's cleaned
record and the audit of every merge decision. The 2026-10-29 build is 1.18 GB, in
`~/Projects/ai-shopping-agent-data/out/latest/`, outside git.

| Table | One row per | Holds | Rows (2026-10-29) |
|---|---|---|---|
| `product` | barcode | merged name, brand, category, size, serving, NOVA group, image URL, which sources have it, source dates | 439,581 |
| `product_image` | product photo | every photo in display order: the matched Amazon item's images (MAIN first), else the one OFF photo | 91,619 |
| `nutrient` | product | 12 nutrients per 100 g as decimals; `from_off` lists those taken from Open Food Facts | 430,046 |
| `ingredients` | product | the ingredient list as printed, its source and date | 428,733 |
| `product_field_source` | product field | the winning source of name, brand, category, ingredients and serving size | 2,146,411 |
| `merge_conflict` | product field | the losing value when FDC and Open Food Facts disagree | 1,098,546 |
| `source_fdc` | FDC barcode | the FDC record, cleaned, before the merge | 430,243 |
| `source_off` | Open Food Facts barcode | the Open Food Facts record, cleaned, before the merge | 920,219 |
| `recall`, `recall_link` | recall; recall and barcode | all 29,505 openFDA food recalls; 12,989 barcode links | |
| `generic_food` | FDC food | natural foods without a barcode, per 100 g | 8,262 |
| `build_info` | key | build date, source files, counts | |
| `match_input` (view) | US product with a name | input for the Amazon match step: GTIN-14 text, name, brand, brand owner, checked ingredients, most-scanned first | |

`product` also holds `brand_owner` (FDC's company name), `image_source` (amazon or off) and `amazon_asin`.

Facts:
- `labelsage-full.sqlite` → holds → the whole cleaned database with its audit trail
- `merge_conflict` → keeps → every losing value
- `catalog.sqlite` → is → a slim export of the full database

## Phone catalog: catalog.sqlite

`catalog.sql` is the schema of `catalog.sqlite`, the phone catalog, replaced every week and shipped inside the app:
every recalled product and every product with a photo (102,683 products, 29.2 MB on 2026-10-29; decision D-35).
The server holds every product for the rest.
`app/backend/etl/load/load.py` creates the file from it; `app/shared/LabelSageCatalog` reads it.

`catalog_meta.schema_version` says which version of this schema the file has. Raise `SCHEMA_VERSION` in
`load.py` and `CatalogProductSource.schemaVersion` together with every change the app must know about: the app
refuses a file of another version and falls back to its fixtures, instead of reading wrong columns.

| Table | One row per | Holds |
|---|---|---|
| `product` | barcode (GTIN-14 as a number) | name, brand, category, size, serving size, flags (incl. recipe changed), sources, NOVA group, image file, confidence, region, FDC and OFF dates |
| `product_image` | product photo | up to 5 Amazon photos per matched product, MAIN first, as file names after `catalog_meta.amazon_image_prefix`; rank 0 is also `product.image` |
| `nutrient` | product | 12 nutrients per 100 g as whole numbers (`_cg` = hundredths of a gram) |
| `ingredients` | product | the ingredient list as printed, zlib-compressed with the shared dictionary |
| `zlib_dictionary` | catalog | the dictionary needed to unpack ingredients |
| `brand`, `category` | value | lookups, so each name is stored once |
| `recall`, `recall_link` | recall; recall and barcode | recalls that name a barcode |
| `search` | product | contentless FTS5 name index: `rowid` = barcode |
| `catalog_meta` | key | snapshot version, schema version, source files, build counts |

Facts:
- `catalog.sql` → defines → the tables of `catalog.sqlite`
- `full.sql` → defines → the tables of `labelsage-full.sqlite`
- `load.py` → creates → `catalog.sqlite` from `catalog.sql`
- The app → refuses → a `catalog.sqlite` of another `schema_version`

## Amazon matches: amazon.sqlite

`amazon.sql` is the schema of `amazon.sqlite` (`extract.AMAZON_DB`, in `~/Projects/ai-shopping-agent-data/amazon/`).
`extract/amazon.py` and `match/amazon_match.py` fill it (`run.py amazon <n>`); the weekly build never rebuilds it,
because every row cost an SP-API call. The build reads `product_amazon` and `amazon_image`, to put the matched
item's images into both other databases.

| Table | One row per | Holds |
|---|---|---|
| `amazon_lookup` | request | which barcode or name we searched, when, HTTP status, how many items came back |
| `amazon_lookup_item` | request, ASIN | which items a request returned, in Amazon's order |
| `amazon_item` | ASIN | name, brand, product type, parent, pack quantity, ingredients if returned, raw item JSON |
| `amazon_item_identifier` | ASIN barcode | every UPC/EAN/GTIN Amazon lists, also as GTIN-14 |
| `amazon_image` | ASIN image variant | the largest image link of MAIN, PT01 ... |
| `amazon_match` | barcode, ASIN, matcher version | brand and title scores, penalty, confidence, tier (accept, review, reject), reasons |
| `product_amazon` | barcode | the one ASIN we use and its image; written by the matcher or a reviewer |
| `match_eval` | eval run, method, threshold | accuracy, precision, recall, F1 |

Facts:
- `amazon.sqlite` → is kept across → weekly builds
- the build → reads → `product_amazon` and `amazon_image` only
- a product → never depends on → an Amazon match
