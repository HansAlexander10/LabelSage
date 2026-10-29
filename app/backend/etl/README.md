---
type: reference
entity: backend/etl
owner: Bagus
status: draft
updated: 2026-10-29
---

# backend/etl

The ETL (extract, transform, load) runs on premise and builds three outputs from the full downloads of three public
sources, never their APIs: the whole cleaned database for the team, a starter catalog for the phone (under 60 MB),
and a Parquet export for the server. FDC decides which products exist (decision D-31); each product carries a
`region` (`us`, `id` or both). A run takes about 5 minutes and can be repeated: it starts from an empty work file
and overwrites that day's output.

```sh
python3 app/backend/etl/run.py download   # fetch any missing source files
python3 app/backend/etl/run.py profile    # count what the downloaded files hold
python3 app/backend/etl/run.py build      # transform, load, check: write the three outputs
python3 app/backend/etl/run.py app        # copy out/latest/catalog.sqlite into the iOS app
```

The build needs Python 3 and DuckDB (`pip install duckdb`). Raw files, work files and the output stay in
`~/Projects/ai-shopping-agent-data/`, outside git:

| Path | Holds |
|---|---|
| `raw/` | the downloaded source files |
| `work/build.duckdb` | the build's work file, recreated each run |
| `out/<date>/labelsage-full.sqlite` | the full database for the team and the server (about 1.2 GB) |
| `out/<date>/catalog.sqlite`, `.sqlite.gz` | the phone catalog (under 60 MB) and its download copy |
| `out/<date>/server/` | the full database as Parquet plus `manifest.json`, for the server transfer |
| `out/latest` | a link to the newest build that passed the check |

`run.py app` copies the newest checked catalog into `app/frontend/ios/LabelSage/Resources/Data/catalog.sqlite`, so
it ships inside the app (decision D-35). The app reads it when `ProductSourceFactory.useRealSource` is on, or in
debug with the Run argument `-realCatalog`; `-catalog <path>` opens any other file.

Facts:
- The ETL → builds → `catalog.sqlite` for the phone and `labelsage-full.sqlite` for the server, weekly
- The ETL → reads → full downloads only, no APIs
- `out/latest` → points to → the newest build that passed the check
- The build → needs → Python 3 and DuckDB

## Sources and what each one gives

| Source | File | Gives | License |
|---|---|---|---|
| Open Food Facts | `en.openfoodfacts.org.products.csv.gz`, US products only (`transform.OFF_COUNTRIES`; Indonesia skipped, D-34) | names, brands, ingredients, nutrients, images | ODbL (database), DbCL (contents) |
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
| Extract, Amazon | `extract/amazon.py` | asks the SP-API catalog about the most-scanned barcodes (by barcode, then name + brand) and keeps every answer in `amazon.sqlite`; run with `run.py amazon <n>`, not part of the weekly build |
| Match, Amazon | `match/amazon_match.py` | scores the fetched items (`match/matcher.py`) and picks one Amazon item per barcode into `product_amazon` |
| Transform part 1 | `transform/transform.py` | writes every barcode as GTIN-14, drops failed check digits, keeps the newest version per source |
| Transform parts 2 and 3 | `transform/transform.py` | combines FDC and Open Food Facts per barcode, then cleans units and text |
| Transform part 4 | `transform/transform.py` | links recalls; a recalled barcode with no product becomes a stub |
| Load part A | `load/full_database.py` | writes `labelsage-full.sqlite`, the whole readable database with source records and the merge audit (schema: `../schemas/full.sql`) |
| Load part B | `load/load.py` | exports `catalog.sqlite`, the phone catalog (schema: `../schemas/catalog.sql`): every recalled product, then every product with a photo, most-scanned first (Open Food Facts `unique_scans_n`; D-35) |
| Load, check | `load/load.py` (`check`) | stops the build unless both files pass SQLite's own check, the catalog is under 60 MB, has the app's `schema_version`, every row points at a product and every ingredient list unpacks |
| Load part C | `load/server_export.py` | exports every table of the full database as Parquet (zstd) plus `manifest.json`, for the transfer to the server; then `out/latest` moves to this build |

`shared/barcode.py` holds the barcode rules; `LabelSageCatalog` applies the same rules on the phone.

Facts:
- `transform/transform.py` → runs → transform parts 1 to 4 in DuckDB SQL
- `load/full_database.py` → writes → `labelsage-full.sqlite`, the team's database
- `load/load.py` → exports → `catalog.sqlite` for the phone
- A failed check → stops → the build before the gzip copy, the server export and `out/latest`

## Merge rules: preferred source per field

FDC is the main source (decision 2026-10-28): it gives identity, ingredients and nutrients. Open Food Facts
fills fields FDC lacks and gives the photo. With `KEEP_OFF_ONLY = False` (`transform.py`, the default) the
catalog holds only FDC products; `True` also keeps the products only Open Food Facts has, all Indonesian ones included.

| Field | Preferred | Fallback | Reason |
|---|---|---|---|
| Name | FDC | Open Food Facts | manufacturer label data |
| Brand | FDC `brand_name`, then `brand_owner` | Open Food Facts | manufacturer label data |
| Category | FDC | Open Food Facts | FDC categories are more consistent |
| Ingredients | FDC | Open Food Facts | manufacturer label data; `recipe_changed` flags when OFF's newer list differs |
| Nutrients | FDC | Open Food Facts, per nutrient | manufacturer label data |
| Serving size | Open Food Facts | FDC | FDC can list a toddler serving |
| Image | Amazon MAIN image of an accepted match (`amazon.sqlite`) | Open Food Facts, only when its record passes the identity check | a wrong photo next to FDC's ingredients could mislead; see below |
| NOVA group | Open Food Facts | none | only Open Food Facts has it |

The identity check (transform job 3) scores each OFF record against the FDC record with the same barcode
with `match/matcher.py` (method `same_barcode`): name and brand similarity, plus a veto when allergen or flavor
words conflict. Only tier `accept` keeps the OFF photo; `review` and `reject` show no photo. The barcode alone
links the two records; the check catches volunteer errors behind it. Its thresholds are placeholders until a
hand-labelled sample sets them (target: no wrong photo in the sample).

Missing values stay empty and the app shows "unknown". A nutrient above a believable limit per 100 g is dropped.
The catalog stores no allergen results: the app's `LabelSageCore` reads the ingredients text itself.

Facts:
- Nutrients → come from → FDC first
- Ingredients → come from → FDC first
- Allergen results → are computed by → `LabelSageCore` on the phone

## Latest build on 2026-10-29

FDC-first, US only, with `KEEP_OFF_ONLY = False` (open question Q-06); the phone gets products with a photo plus
recalled products. Reruns on the same day give the same counts.

| Measured | Value |
|---|---|
| Products | 439,581 (FDC 430,243; in both FDC and Open Food Facts 358,924; recall stubs 9,338) |
| With ingredients / with nutrients | 428,733 / 429,473 |
| Open Food Facts identity check: accept / review / reject | 317,778 / 21,043 / 20,103 |
| With a photo (OFF, accepted only) | 91,619 |
| Recalls that name a barcode / generic foods without a barcode | 9,366 / 8,262 |
| `labelsage-full.sqlite` | 1.18 GB |
| `catalog.sqlite` (phone): products / size / gzip download | 102,683 (91,619 with a photo, 11,064 recalled without one) / 29.2 MB / 15.2 MB |
| Server export (Parquet, all tables) | 154 MB |
| Recipe may have changed / confidence high, medium, low | 38,835 / 1,244, 110,726, 327,611 |
| Run time | about 5 minutes |

Facts:
- The 2026-10-29 build → holds → 439,581 products, all in FDC or named by a recall
- The 2026-10-29 phone catalog → passed → the build check
- A product without a photo and without a recall → is not on → the phone (Cheerios 0016000275287 among them)

## Language, quality gate and Indonesian products

The phone gets an ingredient list only when the app's engine can read it; without one the app shows "Can't
confirm", never "OK". `HIDDEN_INGREDIENTS` in `load/load.py` leaves out three kinds of lists:

| Hidden on the phone | Why | Lists (2026-10-29) |
|---|---|---|
| failed the quality gate (`shared/ingredients_text.py`): codes such as "RH-30", broken scanned text | unreadable | 1,704 |
| French, Spanish, Italian or German | the engine reads English; "lait" is milk | 228 |
| Indonesian lists from Open Food Facts | safe default until `LabelSageCore` loads Indonesian words | all of them |

The full database and the server export keep every list, with `language` and `looks_ok` columns. Word-based
language detection misses a few lists: a sample of 25 "other" lists held one Polish list and one broken one.

Indonesian work in the ETL (the counts are from the 2026-10-26 build, which kept the products only Open Food Facts
has; Indonesian products are skipped since 2026-10-29, decision D-34):

- `shared/allergen-terms-id.draft.json`: a **draft** Indonesian allergen word list in the shape of `LabelSageCore`'s
  `catalog.json` (same family ids). Words marked `regulation` come from BPOM Regulation 20/2021, Article 49(3);
  words marked `proposed` are common label words for review. It needs review by an Indonesian-speaking dietitian
  (open question Q7) before the app loads it and the safe default is removed.
- Categories: Open Food Facts' English names (`main_category_en`); 1,825 Indonesian products without one get a
  category from name keywords such as "mie" or "biskuit" (`shared/categories.py`, `category_source = 'name'`).
- Quality: of 1,535 Indonesian ingredient lists, 628 pass the gate; the rest are codes, other languages or
  broken text.

The `confidence` thresholds are placeholders: most products score low because few Open Food Facts records reach a
completeness of 0.8. The team should set them.

Facts:
- A list the engine cannot read → is hidden on → the phone, so the app shows "Can't confirm"
- The Indonesian allergen word list → is → a draft that needs review before use
- 628 of 1,535 Indonesian ingredient lists → passed → the quality gate in the 2026-10-26 build
