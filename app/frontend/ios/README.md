---
type: reference
entity: frontend/ios
owner: Artem
status: current
updated: 2026-10-28
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

## Ship to TestFlight

`testflight.sh` archives a Release build and uploads it to App Store Connect. Release builds have no debug
switches: the first launch shows onboarding and saves to the real store. Products come from the 100 made-up
fixture products (`Resources/Data/sample-products.json`), so a real supermarket barcode answers "not found".

Before the first upload (one time, by the account owner):

1. A paid Apple Developer Program team. The free Personal Team on this Mac can't upload to TestFlight.
2. In App Store Connect, create the app with the bundle ID you'll use (default `app.labelsage.ios`, still a placeholder).
3. Sign in to that team in Xcode (Settings > Accounts), or create an App Store Connect API key.

```sh
cd app/frontend/ios
TEAM_ID=ABCDE12345 ./testflight.sh                        # archive, sign, upload
TEAM_ID=ABCDE12345 BUNDLE_ID=com.example.labelsage ./testflight.sh
TEAM_ID=ABCDE12345 UPLOAD=0 ./testflight.sh               # .ipa only, upload with Transporter
```

The build number is the current time (`YYYYMMDDHHMM`), so every upload is higher than the last. The version is
`MARKETING_VERSION` in `project.yml`. Export compliance is answered in `Info.plist` (no non-exempt encryption),
and `Resources/PrivacyInfo.xcprivacy` declares no tracking, no collected data and the UserDefaults reason CA92.1.
The App Store Connect privacy label, a privacy policy URL and the beta review contact are still to fill in
on the website before external testers can join.

## See onboarding from Xcode

Run with the `LabelSage` scheme opens chat home with the demo household (`-demoHousehold`, in memory), so onboarding is skipped.

- **Scheme "LabelSage Onboarding"**: pick it next to the Run button. It wipes the stored household (`-resetHousehold`), so onboarding starts at the splash, and the answers save to the real store on this simulator. Run the `LabelSage` scheme with `-demoHousehold` unticked to open the saved household again.
- **Or by hand** in the `LabelSage` scheme (Edit Scheme > Run > Arguments): untick `-demoHousehold`, tick `-resetHousehold`.

Debug launch arguments for onboarding:

| Argument | What it does |
|---|---|
| `-resetHousehold` | Deletes the stored household and its people before it loads. Go-tos stay. Ignored with `-demoHousehold`. |
| `-dumpHousehold` | Prints the household read back from the store as one JSON line, `LS_HOUSEHOLD launch ...` and `LS_HOUSEHOLD saved ...`. The same lines are appended to `Documents/household-dump.txt` in the app container (`xcrun simctl get_app_container <device> app.labelsage.ios data`). |
| `-onboardingScript family` | Answers onboarding through `OnboardingModel`'s own actions and presses "Check my first product", so the real save runs. You avoid seed oils and gluten; Mia has peanut and tree nut allergies; Austin 78701; the first store. |
| `-onboardingScriptStop <step>` | With the script: stops on that step after answering it (`welcome`, `region`, `summary`), for a screenshot. |
| `-onboardingScriptThenFamily` | With the script: opens Family 8 s after the save, to see what was stored. |
| `-screen onboarding` | Shows onboarding over a saved household (finishing replaces it). |
