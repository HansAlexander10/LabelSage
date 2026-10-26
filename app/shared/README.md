---
type: reference
entity: shared/
owner: Artem
status: current
updated: 2026-10-26
---

# shared/

Code used by more than one side. `LabelSageCore` (Swift package) holds the ingredient parser, the matcher, the verdict
engine and the reason lines. The iOS app uses it today; a Swift server could use it later for search-time checks.
Its spec is `../labelsage-ios/data/verdict-cases.json` and `../labelsage-ios/tools/reference_engine.py` (45/45).

```sh
cd app/shared/LabelSageCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

`LabelSageCatalog` (Swift package) reads `catalog.sqlite`, the weekly US product catalog built by `app/backend/etl`
(999,426 products, 192 MB on the phone on 2026-10-25). It returns `LabelSageCore.Product` values for a barcode, a
name search or "Other options" in the same category, plus the recalls that name a barcode. Its methods follow the
`ProductSource` shape in the handoff, so the app can switch from the fixtures behind `useLiveProductSource`. Its
tests run against a 23-product fixture cut from the real catalog by `Scripts/make_fixture.py`.

```sh
cd app/shared/LabelSageCatalog && swift test
```
