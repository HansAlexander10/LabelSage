---
type: reference
entity: backend/
owner: Artem
status: current
updated: 2026-10-23
---

# backend/

Nothing runs here yet. The app uses fixture data behind the `ProductSource` protocol (handoff decision D4, register
Q-06: the product data source is open). This folder is reserved so the backend lands in a known place.

| Folder | Will hold | Plan |
|---|---|---|
| `api/` | the HTTP contract (`openapi.yaml`); the iOS client and the server are generated from it | `docs/app-engineering/PRD/PRD AI Shopping Agent backend.md`, `docs/app-engineering/architecture.md` |
| `etl/` | the weekly import of FoodData Central, Open Food Facts and openFDA into the product database | `docs/app-engineering/architecture.md`, "ETL pipeline" |
| `schemas/` | database schema and migrations (product, ingredients, nutrients, recalls) | `docs/app-engineering/architecture.md`, "Product database schema" |
| `server/` | the read-only product API (barcode lookup, search, config) | stack open (Swift server reusing `shared/LabelSageCore`, or Python) |

Rules that already apply: the backend never receives a profile, rules or names; keys live only on the server.
