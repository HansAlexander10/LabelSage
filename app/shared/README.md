---
type: reference
entity: shared/
owner: Artem
status: current
updated: 2026-10-23
---

# shared/

Code used by more than one side. `LabelSageCore` (Swift package) holds the ingredient parser, the matcher, the verdict
engine and the reason lines. The iOS app uses it today; a Swift server could use it later for search-time checks.
Its spec is `../labelsage-ios/data/verdict-cases.json` and `../labelsage-ios/tools/reference_engine.py` (45/45).

```sh
cd app/shared/LabelSageCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```
