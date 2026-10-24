# Data, storage and privacy

## Models

The value types are in `LabelSageCore/Sources/LabelSageCore/Models.swift` (`Product`, `Nutrition`, `Household`, `Person`, `Profile`, `AllergenChoice`, `AvoidChoice`, `CustomChoice`, `Goals`, `Region`, `Store`). Persist them with SwiftData models in the app that wrap or mirror these:

| SwiftData model | Holds | Notes |
|---|---|---|
| `HouseholdRecord` | the `Household` (people, region, store) | one per install |
| `GoToRecord` | product snapshot (barcode, name, brand, image URL, `ingredientsText` hash), saved date | re-checked on open and after profile changes (D15) |
| `CheckRecord` | product snapshot, date, the `HouseholdVerdict.line` | "Checked before" (offline list) and chat history |
| `ChatRecord` | title, messages (role, text, attached product ids), context | history menu |
| `TipRecord` | tip id, dismissed | explainers shown once |
| `ReportRecord` | barcode, reason, date | "Report it", local until a backend exists |

Profiles are stored as Codable values on the person; the engine reads them directly.

## Product source (D4 open)

```swift
protocol ProductSource: Sendable {
    func product(barcode: String, region: Region) async throws -> Product?          // nil = not found
    func search(_ query: String, region: Region, store: Store?) async throws -> [Product]
    func options(like product: Product, region: Region, store: Store) async throws -> [Product]  // same category, at this store
    func stores(near region: Region) async throws -> [Store]
}
```

- `FixtureProductSource` reads `data/sample-products.json` and a fixture store list. It's the only source in the MVP until D4 is decided.
- `ProductSourceError.offline` → the offline state; any other error → not found with "Report it".
- Cache products by barcode (SwiftData) for the offline "Checked before" list. Always re-run the engine on cached products with today's profiles.

## What leaves the device

| Data | Leaves? | When |
|---|---|---|
| Barcode, typed product name | yes | lookups through `ProductSource` |
| ZIP code and store id | yes | lookups and options (D6) |
| People's names, allergies, diets, goals | **never** | |
| Photos of ingredients | **never** (OCR on device; kept in memory only) | |
| Chat text | **never** (on-device model) | |
| Apple Health values | **never** (read only for targets) | |

Copy that promises this: "Stays on your iPhone", "Only your ZIP code is kept, on this iPhone.", "The barcode is read on your iPhone. No photos are saved or sent.", "Runs on your iPhone. Your data stays here." If an implementation choice would break one of these, stop and raise it.

## Permissions

| Permission | Asked when | Purpose string |
|---|---|---|
| Camera | first "Open the camera" | "LabelSage reads barcodes and ingredient lists. Nothing is saved or sent." |
| Location (when in use) | "Use my location" on the region step | "LabelSage uses your location once to fill in your ZIP code." |
| Photos (picker, no full access) | "Upload a photo" | uses `PhotosPicker`, no permission prompt |
| Health (read) | "Help me set them" on the targets source step | "LabelSage reads height, weight and age to suggest daily targets." |

## Sample data

- `data/sample-household.json`: the demo household (Alex as "you": avoid seed oils and gluten, prefer less added sugar; Mia: peanut and tree nut allergies, "may contain" on), Austin 78701, Whole Foods Market.
- `data/sample-products.json`: 10 made-up products with fake barcodes that cover every verdict path (the stories on the Flows board). The canvas shows real brands as placeholders; the app's fixtures use made-up names on purpose.
