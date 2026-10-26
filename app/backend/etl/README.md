---
type: reference
entity: backend/etl
owner: Bagus
status: draft
updated: 2026-10-26
---

# backend/etl

The ETL (extract, transform, load) builds `catalog.sqlite`, the US product catalog the phone downloads every week.
It reads the full downloads of three public sources, never their APIs, and runs on a build machine in about
90 seconds. The app reads the catalog through `app/shared/LabelSageCatalog`; nothing leaves the phone.

```sh
python3 app/backend/etl/run.py download   # fetch any missing source files
python3 app/backend/etl/run.py profile    # count what the downloaded files hold
python3 app/backend/etl/run.py build      # transform and load: write catalog.sqlite
```

The build needs Python 3 and DuckDB (`pip install duckdb`). Raw files, work files and the output stay in
`~/Projects/ai-shopping-agent-data/` (`raw/`, `work/`, `out/<date>/`), outside git.

Facts:
- The ETL → builds → `catalog.sqlite` for the phone, weekly
- The ETL → reads → full downloads only, no APIs
- The build → needs → Python 3 and DuckDB

## Sources and what each one gives

| Source | File | Gives | License |
|---|---|---|---|
| Open Food Facts | `en.openfoodfacts.org.products.csv.gz`, US products only | names, brands, ingredients, nutrients, images | ODbL (database), DbCL (contents) |
| `FoodData Central` Branded Foods | `FoodData_Central_branded_food_csv_<date>.zip` | manufacturer label nutrients, ingredients, category | CC0 |
| `FoodData Central` Foundation and SR Legacy | `FoodData_Central_foundation_food_csv_<date>.zip`, `..._sr_legacy_food_csv_2018-04.zip` | natural foods without a barcode | CC0 |
| openFDA food enforcement | `food-enforcement-0001-of-0001.json.zip` | food recalls | public domain |

Facts:
- Open Food Facts → is licensed under → ODbL, so a published catalog must credit it and stay ODbL
- `FoodData Central` and openFDA → are → CC0 or public domain

## Pipeline phases

The code follows the team's ETL board. Each module marks its phases with `# ------ PHASE n` banners and its steps
with `# job n` comments.

| Phase | Module | What it does |
|---|---|---|
| Extract | `extract/extract.py` | downloads the files, unpacks the FDC zips for DuckDB, reads openFDA |
| Transform part 1 | `transform/transform.py` | writes every barcode as GTIN-14, drops failed check digits, keeps the newest version per source |
| Transform parts 2 and 3 | `transform/transform.py` | combines FDC and Open Food Facts per barcode, then cleans units and text |
| Transform part 4 | `transform/transform.py` | links recalls; a recalled barcode with no product becomes a stub |
| Load | `load/load.py` | writes `catalog.sqlite` (schema: `../schemas/catalog.sql`), compresses ingredients, builds name search |

`shared/barcode.py` holds the barcode rules; `LabelSageCatalog` applies the same rules on the phone.

Facts:
- `transform/transform.py` → runs → transform parts 1 to 4 in DuckDB SQL
- `load/load.py` → writes → `catalog.sqlite`

## Merge rules: preferred source per field

Each field comes from its preferred source; when that is empty, the other source fills it.

| Field | Preferred | Fallback | Reason |
|---|---|---|---|
| Name | Open Food Facts | FDC | the consumer name; an OFF name that shares no word with FDC's name or brand loses |
| Brand | Open Food Facts | FDC `brand_name`, then `brand_owner` | the consumer brand |
| Category | FDC | Open Food Facts | FDC categories are more consistent |
| Ingredients | the newest record | the older record | recipes change |
| Nutrients | FDC | Open Food Facts, per nutrient | manufacturer label data |
| Serving size | Open Food Facts | FDC | FDC can list a toddler serving |
| Image, NOVA group | Open Food Facts | none | only Open Food Facts has them |

Missing values stay empty and the app shows "unknown". A nutrient above a believable limit per 100 g is dropped.
The catalog stores no allergen results: the app's `LabelSageCore` reads the ingredients text itself.

Facts:
- Nutrients → come from → FDC first
- Ingredients → come from → the newest record
- Allergen results → are computed by → `LabelSageCore` on the phone

## First build on 2026-10-25

| Measured | Value |
|---|---|
| US products | 999,426 (FDC 430,243; Open Food Facts 920,219; in both 358,924) |
| With ingredients / with nutrients | 528,296 / 866,685 |
| Recall stubs / recalls that name a barcode | 7,888 / 9,366 |
| Generic foods without a barcode | 8,262 |
| `catalog.sqlite` / gzip download | 192 MB / 108 MB |

Facts:
- The 2026-10-25 catalog → holds → 999,426 US products
- The 2026-10-25 catalog → measures → 192 MB on the phone, 108 MB to download
