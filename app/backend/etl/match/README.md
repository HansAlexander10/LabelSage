---
type: reference
entity: backend/etl/match
owner: Bagus
status: draft
updated: 2026-10-28
---

# match: our products to the Amazon catalog

Gets an Amazon product photo for products we already have. A product never depends on a match: no match means the
app keeps the Open Food Facts photo, or no photo. Run it with `python3 app/backend/etl/run.py amazon 1000`:
`extract/amazon.py` fetches the next 1,000 barcodes, then `amazon_match.py` scores and picks.

| File | What it does |
|---|---|
| `amazon_match.py` | scores what `extract/amazon.py` fetched and writes `amazon_match` and `product_amazon` (steps 4 and 6 below; a reviewer's row is never changed) |
| `matcher.py` | scores one (our product, Amazon item) pair: brand + title similarity, allergen-claim veto, points off for flavor and variant words on one side (organic, colby jack, whipped; list from the golden-set benchmark), tier accept / review / reject; `pick_best` picks one ASIN per barcode |
| `sp_api.py` | SP-API Catalog Items 2022-04-01 client (search by barcode in batches of 20, or by name + brand) and `parse_item` (rows for the tables + the matcher's view) |
| `evaluate.py` | accuracy, precision, recall, F1 per method and threshold on a labelled pair file |
| `golden_set.py` | builds the golden set: 705 random FDC products (15 per big category, plus 20 per edge case) and 4 Open Food Facts candidates each (the same-barcode record plus look-alikes), barcodes hidden; writes `golden-pairs.csv` and a label view to the data folder (`out/golden/`, not in git); `labels <file>` copies labels in |
| `benchmark.py` | scores the labelled golden set with 10 algorithms (exact, Jaccard, Levenshtein, brand + title, the matcher, TF-IDF, two embedding models, logistic regression); threshold from the dev half, metrics on the test half, recall per edge case and category; writes `benchmark-results.md` |
| `eval-pairs-synthetic-2026-10-28.json` | 40 hand-written pairs (30 barcode, 10 name + brand); synthetic, not real Amazon data |
| `../../schemas/amazon.sql` | the tables: `amazon_lookup`, `amazon_item`, `amazon_item_identifier`, `amazon_image`, `amazon_match`, `product_amazon`, `match_eval` |

## What `run.py amazon` does

Steps 1 to 3 and the fetch in step 5 are `extract/amazon.py`; steps 4 and 6 are `amazon_match.py`. In-store
barcodes (EAN-8 starting 0 or 2, EAN-13 prefixes 20-29, UPC number systems 2 and 4) are skipped, and a barcode is
asked again only after 30 days (`REFRESH_DAYS`). A refused call (bad credentials, no access, still throttled) stops
the run without saving anything for that batch.

1. Create `extract.AMAZON_DB` (`~/Projects/ai-shopping-agent-data/amazon/amazon.sqlite`) from `schemas/amazon.sql`
   once. It is never rebuilt: the weekly build only reads `product_amazon` from it.
2. Read the products to match from the `match_input` view of `labelsage-full.sqlite` (most-scanned first). Skip
   GTINs that already have an `amazon_lookup` row unless you want to refresh them.
3. Group the GTIN-14s by kind (starting `00` = UPC, else EAN), 20 per call: `Client().search_barcodes(batch)`.
   Write one `amazon_lookup` row per barcode, and `parse_item` rows into `amazon_item`, `amazon_item_identifier`,
   `amazon_image`.
4. For each barcode, score every returned item whose identifiers list that barcode:
   `matcher.score_pair(ours, item, "barcode")`. Write every score to `amazon_match`.
5. Barcodes with no item: `Client().search_name_brand(name, brand)`, then score with method `"name_brand"`.
6. `matcher.pick_best(scored)` per barcode; write the winner to `product_amazon` with `decided_by = "matcher"`
   and `image_url` = its `main_image`. Rows in tier `review` wait for a person.
   The next `run.py build` puts that image into `labelsage-full.sqlite` and the phone catalog.
7. Run `python3 match/evaluate.py <pairs.json>` and keep its rows in `match_eval`.

`ours` = a `match_input` row: `{"gtin", "name", "brand", "brand_owner", "ingredients"}`. Pass the ingredients when we have them: then a free-from claim
in the Amazon title is checked against our list instead of being sent to review.

## Before a full run

- **Amazon terms.** Check that we may use catalog data and show the images in our app.
- **Account.** Check that our account gets `images` (and `attributes`).
- **Rate limit.** Check the real limit and set `RATE_PER_SECOND`.
- **Credentials.** They come from environment variables only: `SP_API_CLIENT_ID`, `SP_API_CLIENT_SECRET`, `SP_API_REFRESH_TOKEN`.
- **Real labels.** Replace the synthetic pairs with about 200 hand-labelled real pairs, and set the thresholds from those.
