# CLAUDE.md: building LabelSage for iOS

You are building the LabelSage iOS MVP from a finished design. Read `HANDOFF.md` first, then the spec for the screen you are working on. This file says how to work here.

## Sources of truth, in order

1. `data/verdict-cases.json` and `tools/reference_engine.py` for **what a verdict is**. If the Swift engine and the reference disagree, the reference wins. Change the reference only together with a new case, and say why in the commit.
2. `docs/specs/*.md` for **what a screen does**. Each spec links its board export in `design/screens/`.
3. `design/screens/*.png` for **how it looks**. `design/prototype/*.dc.html` has the exact values (CSS inline styles) and the copy when a PNG is not enough. Read it as a reference; never port the HTML or the JS.
4. `design/tokens.json` for **values**. Use tokens in code (`Theme.color.ink`, `Theme.radius.card`), never raw hex in views.
5. `docs/voice-and-strings.md` for **every word** the app shows.

If two sources disagree, stop and list the conflict in `docs/open-questions.md`. Do not pick one silently.

## Hard rules (a screen that breaks one is not done)

- **Never "safe".** No "safe", "safer", "unsafe", "100%", "guaranteed", "allergy-proof", "protected" as a promise. Verdicts are "OK for Mia", "Check first", "Not for Mia", "Can’t confirm". If a user types "is this safe for my son?", answer in the person form ("OK for Leo"); never repeat their word.
- **Code decides, LabelSage explains.** The flag comes only from `VerdictEngine`. The on-device model may write or rewrite the reason text, never the level, and never on its own when the engine is unavailable.
- **One LabelSage per screen.** In the chat he stands in the dock above the composer. When a sheet or tip needs him, he moves there and the dock is empty. Two at once is a bug: write a UI test for it.
- **"Check the package. Not medical advice."** under every verdict.
- **Nothing about a person leaves the device.** Allergies, names and go-tos stay in SwiftData on the phone. Product lookups send the barcode, or the name, plus the region and store. Nothing else is sent.
- **The names come from config.** `Brand.app` and `Brand.mascot` (both "LabelSage" today) come from one file. Never hard-code the name in a string.
- **No em dashes in any copy.** Use a colon, a comma or a full stop.
- **Accessible by default:** every control has a label, Dynamic Type works up to AX5 without clipping, Reduce Motion freezes the mascot, and no meaning lives only in color or animation.
- **The MVP only.** Do not build lists, basket, Instacart, recipes or share. If a design board shows one, it is parked.

## Decisions you must not make

These are open (`docs/open-questions.md`). Build behind a protocol or a flag, with the default noted there, and keep going:

- D4, the product data source: implement `ProductSource`. Ship `FixtureProductSource` (reads `data/sample-products.json`). A real source goes behind a flag once the team picks one.
- Q2, how "may contain" acts for an allergy: `VerdictEngine` reads `Rule.mayContain`. Keep that one switch.
- Q4, the per-serving thresholds: `VerdictEngine.servingShare`.
- Anything clinical: the catalog's terms are a demo until a clinician reviews them. Never add terms from memory without a case in `verdict-cases.json`.

## How to work

- **Start every milestone by reading** its section in `docs/milestones.md` and the specs it names. Make a short plan, then build.
- **Tests first for logic.** `cd LabelSageCore && swift test` must stay green. Add a fixture case for every bug you fix in the engine, then run `tools/sync-data.sh` so both engines see it.
- **SwiftUI previews for every screen state** in the spec's states table, using the sample household and products. A screen is done when every state has a preview and matches its PNG at the same size.
- **Snapshot or UI tests** for: the one-mascot rule, the onboarding path (region and store are never skipped), and the verdict flag colors.
- **Small commits** with a clear message. Commit or push only when the person running you asks.
- **Don't add dependencies** without asking. The MVP needs none.
- When a spec is silent, follow Apple's HIG and the closest existing pattern in the design, then write what you chose in the spec's "Decisions made in build" list so the designer can review it.

## Project layout

The code lives in `app/` with four main folders (see `app/README.md`): `frontend/ios/` (this app, its own XcodeGen spec `app/frontend/ios/project.yml`), `backend/` (reserved; the app uses fixtures), `shared/LabelSageCore` (the engine) and `docs/` (this handoff). The repo's root `CLAUDE.md` and `RULES.md` still apply (no new top-level folders, decisions go in `docs/strategy/01-decision-register.md`). Layout inside `app/frontend/ios/`:

```
LabelSage/                    app target (iOS 27, SwiftUI, main actor by default)
  App/                        LabelSageApp, Brand (names), AppModel (household, router)
  DesignSystem/               Theme (from design/tokens.json), fonts, components
  Features/Onboarding/        decision tree, steps, summary
  Features/Chat/              home, thread, intents, composer, dock
  Features/Scan/              camera, states, OCR
  Features/Product/           product page, sheet, nutrition
  Features/Compare/           compare with, compare
  Features/Family/            person cards, settings, go-tos
  Mascot/                     MascotView, poses, motion
  Services/                   ProductSource and other protocols with their implementations
  Data/                       SwiftData models, fixtures (the mock backend)
  Resources/                  LabelSageIcons.xcassets, icons.json, Outfit, AppIcon
LabelSageTests/               unit tests (Swift Testing)
LabelSageUITests/             UI tests
../../shared/LabelSageCore/   Swift package: engine, models, tests
```

## Commands

```sh
cd ../../shared/LabelSageCore && swift test   # engine and fixtures (from app/docs/labelsage-handoff)
python3 -I tools/reference_engine.py      # the reference spec, 45/45 must pass
sh tools/sync-data.sh                     # after editing data/: copies JSON into the package and runs both
```

## Note on LabelSageCore

The package was written without a Swift toolchain at hand, so it has not been compiled yet. Your first task is to build it and make `swift test` pass. Fix compile errors in place and keep the behavior identical to `tools/reference_engine.py`.
