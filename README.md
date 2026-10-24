# LabelSage

LabelSage checks the ingredients of a grocery product for everyone you shop for. Point the camera at a
barcode or the ingredient list, and it gives one flag per person with the ingredient that decided it:
"Not for Mia. Contains whey: that's milk." Native iOS 27, SwiftUI, on-device only. The demo household and
products are made up.

| Folder | What it holds |
|---|---|
| `app/frontend/ios/` | the iOS app (XcodeGen `project.yml`, SwiftUI, Swift 6) |
| `app/shared/LabelSageCore/` | the verdict engine (Swift package, 45 fixture cases) |
| `app/backend/` | reserved; the app uses fixtures for now |
| `app/docs/labelsage-handoff/` | the design handoff: specs, boards, tokens, voice, build plan |

Build: `cd app/frontend/ios && xcodegen generate && open LabelSage.xcodeproj`.
Engine tests: `cd app/shared/LabelSageCore && swift test`.

Icons: Microsoft Fluent Emoji 3D (MIT). Font: Outfit (OFL). Licenses in `app/docs/labelsage-handoff/assets/`.
