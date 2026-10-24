---
type: reference
entity: frontend/ios
owner: Artem
status: current
updated: 2026-10-23
---

# frontend/ios: the LabelSage iPhone app

SwiftUI, iOS 27, Swift 6 language mode, main actor by default. No third-party dependencies.

## Layout

| Folder | What lives there | Rule |
|---|---|---|
| `LabelSage/App/` | entry point, `Brand`, `AppModel`, routing | no feature UI |
| `LabelSage/DesignSystem/` | `Theme` (tokens), components, icons, the design gallery | no business logic |
| `LabelSage/Mascot/` | `MascotView`, the 13 states, motion, one-mascot presence | |
| `LabelSage/Features/<Feature>/` | one folder per screen family: Onboarding, Chat, Scan, Product, Compare, Family | a feature imports the design system and services, never another feature |
| `LabelSage/Services/` | protocols and their implementations: `ProductSource`, verdicts, explanations | the only place that knows where data comes from |
| `LabelSage/Data/` | SwiftData models and the fixture (mock backend) data | nothing about a person leaves the device |
| `LabelSage/Resources/` | icons, font, mascot parts, app icon, sample data | |
| `LabelSageTests/` | unit tests (Swift Testing) | |
| `LabelSageUITests/` | UI tests: one mascot per screen, onboarding path, flags | |

The verdict engine is the `LabelSageCore` package in `../../shared/LabelSageCore`.

## Build

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd app/frontend/ios && xcodegen generate
xcodebuild -project LabelSage.xcodeproj -scheme LabelSage \
  -destination 'platform=iOS Simulator,name=LabelSage iPhone 17 Pro,OS=27.0' -derivedDataPath /tmp/ls-dd build
```

Specs, designs and the build plan: `../../labelsage-ios/` (start with `HANDOFF.md` and `docs/build-plan.md`).
