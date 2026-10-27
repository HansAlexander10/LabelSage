# LabelSage

LabelSage is a personalized food-scanning app that empowers you and your family to make better food choices by scanning products, understanding ingredients, and finding the best products and alternatives that fit your needs.

Point the camera at a barcode or the ingredient list, and it gives one flag per person with the ingredient that decided it: *"Not for Mia. Contains whey: that's milk."* Native iOS 27, SwiftUI, on-device Apple Intelligence. Nothing about your family leaves the phone.

---

## What it does

You tell LabelSage who you shop for and what each person avoids — allergies, intolerances, diets, religious rules. Then you check products:

- **Scan a barcode** — LabelSage looks it up in a million-product US catalog and reads the ingredients
- **Photo the ingredient list** — Vision OCR reads the text, the engine parses it
- **Ask in the chat** — *"Is this OK for Mia?"*, *"What about the granola?"*, *"Find me something without milk"*

For every product, every person gets a flag:

| Flag | Means | Example |
|---|---|---|
| **OK** | Nothing they avoid is in the ingredients | *"OK for Mia. No milk in these ingredients."* |
| **Check first** | A daily limit is high, or "may contain" with the switch off | *"Check first: 24% of daily sodium."* |
| **Can't confirm** | The label is vague or missing | *"Can't confirm. 'Natural flavors' isn't specific."* |
| **Not for** | An ingredient they avoid is in the product | *"Not for Mia. Contains whey: that's milk."* |

The app never says "safe." It tells you what it checked and names the ingredient that decided it.

---

## How it works

The verdict always comes from deterministic code. The on-device model reads your intent and writes the reply, but it never changes a flag.

```
Barcode / ingredient photo / typed name
        │
        ▼
  LabelSageCatalog ──► Product { ingredients, contains, mayContain, nutrition }
        │
        ▼
  LabelParser ──► ingredient list with positions, "Contains" line, "May contain" line
        │
        ▼
  VerdictEngine (per person, per rule)
     1. ingredients + "Contains" line   → Avoid: Not for · Prefer not: Check first
     2. "may contain" (allergy only)    → switch on: Not for · switch off: Check first
     3. ambiguous terms ("natural flavors", "lecithin") → Can't confirm
     4. no ingredient list              → Can't confirm
     5. daily limits (sodium, added sugar, net carbs)   → Check first
        │
        ▼
  HouseholdVerdict { overall, line: "Not for Mia · OK for you", people[ level, reason ] }
        │
        ├──► UI: flag, reason line, mascot pose (notFor → guard, checkFirst → thinking, ok → done)
        └──► Chat: the model writes the summary from the findings — it never changes the level
```

**Hidden names** are the hard part. "Whey" is milk. "Lecithin" might be soy or egg. The catalog (`catalog.json`) maps every allergen family to its hidden names and its look-alikes that are *not* it (cocoa butter is not dairy, eggplant is not egg, nutmeg is not a tree nut). A clinician review is pending before launch.

---

## The mascot

LabelSage is also the name of the guide — a label tag in a cape with rubber-hose arms, a magnifier, and 13 animated states. He reads the ingredients so you don't have to. He stands guard on a "Not for" result (still, serious, no joke). He sits on a stack of books while learning someone's allergies. He hums and strolls when nothing's happening.

Hard rule: **one LabelSage on screen at a time.** Two is a bug. There's a UI test for it.

He's built natively from 21 PNG parts placed by a rig file, animated with SwiftUI keyframes. The rig is Rive-ready for later.

---

## Architecture

```
app/
├── frontend/ios/                  SwiftUI app (XcodeGen → LabelSage.xcodeproj)
│   ├── LabelSage/
│   │   ├── App/                   entry point, Brand, AppModel, routing
│   │   ├── DesignSystem/          Theme (tokens), components, icons, design gallery
│   │   ├── Mascot/                MascotView, 13 states, motion, one-mascot presence
│   │   ├── Features/
│   │   │   ├── Onboarding/        14-step decision tree, per-person allergies, region + store
│   │   │   ├── Chat/              AI-first home, intents, product cards, explainers
│   │   │   ├── Scan/              barcode + ingredient photo, every scan state
│   │   │   ├── Product/           product page (page and sheet)
│   │   │   ├── Compare/           compare two products side by side
│   │   │   └── Family/            person cards, settings, go-tos
│   │   ├── Services/              ProductSource protocol, verdicts, explanations
│   │   └── Data/                  SwiftData models, fixture source
│   ├── LabelSageTests/            unit tests (Swift Testing)
│   └── LabelSageUITests/          UI tests: mascot presence, onboarding path, flags
│
├── shared/
│   ├── LabelSageCore/             the verdict engine — pure Swift, no model, tests on Mac
│   │   ├── LabelParser            "Water, sugar, whey…" → structured ingredient list
│   │   ├── VerdictEngine           per person, per rule, deterministic
│   │   ├── Catalog                 hidden names, allergen families, look-alikes
│   │   ├── Copy                    reason lines: "Not for Mia. Contains whey: that's milk."
│   │   └── Models                  Product, Profile, Household, Level, Finding
│   │
│   ├── LabelSageCatalog/          reads catalog.sqlite (999K products, 192 MB on phone)
│   │   └── CatalogProductSource    barcode lookup, name search, "other options" by category, recalls
│   │
│   └── LabelSageAgent/            on-device Foundation Models layer
│       ├── ChatAgent               IntentReader → Actions → Writer pipeline
│       ├── IntentReader            guided generation to extract intent; keyword router fallback
│       ├── Actions                 check, ask, otherOptions, compare, changeAllergies
│       └── Writer                  rewrites the engine's line in ≤20 words; guardrails on the output
│
├── backend/
│   ├── etl/                       weekly US product catalog build (Python + DuckDB, ~90 s)
│   │   ├── extract/               downloads FoodData Central, Open Food Facts, openFDA
│   │   ├── transform/             GTIN-14 normalization, source merge, recall linking
│   │   └── load/                  writes catalog.sqlite with compressed ingredients + FTS
│   ├── schemas/                   catalog.sql — the database schema
│   ├── api/                       reserved: OpenAPI contract for a future product API
│   └── server/                    reserved: read-only product API (stack open)
│
└── docs/labelsage-handoff/        the design handoff
    ├── HANDOFF.md                 the brief — scope, decisions, logic, build order
    ├── docs/                      specs per screen, voice, mascot, icons, milestones
    ├── design/                    tokens.json, 20 screen exports, onboarding decision tree
    ├── data/                      catalog.json (hidden names), verdict-cases.json (45 cases)
    ├── assets/                    Fluent icons, mascot parts + rig, app icon, Outfit font
    └── tools/                     reference_engine.py (the executable spec)
```

**Design rule:** a feature imports the design system and services, never another feature. The verdict engine is a library with no UI dependency — it runs on a Mac, in tests, and (later) on a server.

---

## The product catalog

The app ships with a US product catalog built by the ETL from three public sources:

| Source | What it gives | License |
|---|---|---|
| Open Food Facts | names, brands, ingredients, images | ODbL |
| FoodData Central (USDA) | manufacturer label nutrients, categories | CC0 |
| openFDA | food recall enforcement reports | public domain |

The ETL merges them per barcode (GTIN-14), picks the best field from each source, and writes `catalog.sqlite`. On the first build (2026-10-25): **999,426 US products**, 192 MB on the phone, 108 MB to download.

The catalog stores no allergen results. The app's `VerdictEngine` reads the ingredients text and decides on the phone.

---

## Requirements

- **macOS 26** with **Xcode 27**
- **iOS 27 Simulator** (or a device with Apple Intelligence)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Swift 6.2, Approachable Concurrency
- Python 3 + DuckDB (ETL only)

No third-party Swift dependencies. Icons from Microsoft Fluent Emoji 3D (MIT). Font: Outfit (OFL).

---

## Build & run

```bash
# Generate the Xcode project and open it
cd app/frontend/ios && xcodegen generate && open LabelSage.xcodeproj

# Run the verdict engine tests on the Mac (no simulator needed)
cd app/shared/LabelSageCore && swift test

# Run the catalog tests
cd app/shared/LabelSageCatalog && swift test

# Run the agent tests
cd app/shared/LabelSageAgent && swift test

# Rebuild the product catalog from source (downloads ~2 GB the first time)
python3 app/backend/etl/run.py download
python3 app/backend/etl/run.py build
```

The default scheme (`LabelSage`) opens chat home with a demo household (Alex and Mia, in memory). To see onboarding from the start, switch to the `LabelSage Onboarding` scheme or untick `-demoHousehold` and tick `-resetHousehold` in Edit Scheme → Run → Arguments.

---

## Tests

| Suite | Tests | Runs on | What it covers |
|---|---|---|---|
| LabelSageCore | 7 (45 verdict cases) | Mac (`swift test`) | every verdict path against the executable spec |
| LabelSageCatalog | 8 | Mac (`swift test`) | barcode lookup, search, category, recalls (23-product fixture) |
| LabelSageAgent | 10 | Mac (`swift test`) | intent reading, actions, writer guardrails |
| iOS unit tests | 111 | iOS 27 simulator | data layer, scan states, product page, mascot, icons, controls |
| iOS UI tests | 2 | iOS 27 simulator | launch, onboarding → first check flow |

The verdict engine has an executable spec: `data/verdict-cases.json` holds 45 cases. The Python reference engine (`tools/reference_engine.py`) and the Swift engine must produce the same flags and the same reason lines for all of them.

---

## Key decisions

These are documented in full at `docs/labelsage-handoff/docs/decisions.md`:

- **D1:** Home is the AI chat. Onboarding ends by guiding into the first check.
- **D8:** Code decides, LabelSage explains. The flag always comes from the deterministic engine. The model may only rewrite the reason in place, never the flag.
- **D9:** Only one LabelSage on screen. Two at once is a bug.
- **D10:** Icons from Microsoft Fluent Emoji 3D, bundled. No generated icons.

---

## What's not in the MVP

Lists, basket, restock, Instacart, recipe shopping, share. These are parked on the design canvas. The product data source is behind a `ProductSource` protocol — the app ships with a fixture source today, and the live `CatalogProductSource` is ready behind a feature flag.

---

## License

MIT — see [LICENSE](LICENSE).

Icons: Microsoft Fluent Emoji 3D (MIT). Font: Outfit (OFL). Open Food Facts data: ODbL. Licenses in `app/docs/labelsage-handoff/assets/`.
