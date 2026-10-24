# LabelSage iOS MVP: handoff

**Date:** 23 Oct 2026  
**From:** Artem (product, design)  
**To:** the coding agent building the native app  
**Design source:** the LabelSage design canvas (Claude artifact). Every board is exported to `design/screens/`, and the board sources are in `design/prototype/`.

---

## 1. What we are building

LabelSage checks the ingredients of a grocery product for **everyone you shop for**. You point the camera at a barcode, or at the ingredient list. LabelSage then gives one flag per person with the ingredient that decided it: "Not for Mia. Contains whey: that’s milk."

The app's guide is **LabelSage**, a label-tag hero in a cape. He asks the onboarding questions, explains results in the chat, and stands guard when an allergen is found. He is one character, so he is on screen in one place at a time.

**Who it is for:** households with a food allergy, celiac or a strict diet. Many are parents shopping for a child. They read every label twice and still can't tell what is hidden in it.

**The promise:** "Check the ingredients for everyone you shop for." LabelSage says what it checked and never promises an outcome. It never says "safe".

## 2. MVP scope

| In the MVP | Parked (after the MVP) | Removed |
|---|---|---|
| New onboarding: per person, then the region and the store | Shopping lists, basket, restock | Recipe shopping and recipe swaps |
| Preferences: "Family", one card per person | Instacart and ordering | Share (D5) |
| Checking a product: barcode, ingredients photo, type a name | Store aisles, prices across stores | |
| Product page (as a page and as a sheet) | Budget-based ranking beyond a simple sort | |
| Compare with, then Compare | | |
| The AI chat as home: check, ask, other options, compare, change allergies, pivot | | |
| Go-tos (saved products), checked again on every open | | |
| The edge states: not found, no ingredients yet, camera off, offline | | |

The parked boards are still on the canvas, under "Parked". Do not build them.

## 3. Key decisions

Full log with reasons: `docs/decisions.md`.

| # | Decision | Status |
|---|---|---|
| D1 | **Home is the AI chat.** Onboarding ends by guiding straight into the first check ("Check my first product" opens the camera). | Decided |
| D2 | Lists, basket, restock and Instacart are **parked**. | Decided |
| D3 | Severity is **per allergen**: Allergy or Intolerance. **Allergy is the default.** Allergy also checks "may contain" when the person's switch is on. Intolerance checks the ingredients only. | Decided |
| D4 | **Product data and availability source.** | **Open.** Build against a `ProductSource` protocol and ship the fixture source. |
| D5 | **Share is cut** from the MVP. | Decided |
| D6 | **The store stays and the region is required.** Onboarding asks both once for the household, after everyone's allergies and before the summary. The region can't be skipped; the store can ("Set up later", as in `PRD_front_end.md`). "Other options" come from the store, or the region when none is set. Both can be changed in Family > Settings. | Decided (23 Oct) |
| D7 | **Flows are AI-first:** chat, then camera, then the product page sheet, then compare. | Decided |
| D8 | **Code decides, LabelSage explains.** The flag always comes from the deterministic engine. The on-device model may only rewrite the reason in place, never the flag. | Decided |
| D9 | **Only one LabelSage on screen.** Two at once is a bug. | Decided (hard rule) |
| D10 | Icons come from **Microsoft Fluent Emoji 3D (MIT)**, bundled in the app. Where no exact icon exists, the nearest one stands in. No generated icons. | Decided |
| D11 | The app and mascot names come from **one config value** (`Brand.app`, `Brand.mascot`) so they can change. | Decided |
| D16 | **The name is LabelSage** (it was LabelWard until 23 Oct). | Decided (23 Oct) |

## 4. How it works (the logic in one page)

```
Barcode / ingredients photo / typed name
        │
        ▼
ProductSource (D4) ──► Product { ingredientsText, contains, mayContain, nutrition }
        │
        ▼
LabelParser ──► ingredients with positions, "Contains" items, "May contain" items
        │
        ▼
VerdictEngine (per person, per rule)
   1. ingredients, then the Contains line  → Avoid: Not for · Prefer not: Check first
   2. "may contain" (allergy and medical only) → switch on: Not for · off: Check first
   3. ambiguous terms ("natural flavors", "lecithin", "gelatin") → Can’t confirm
   4. no ingredient list → Can’t confirm
   5. daily limits (sodium, added sugar, net carbs) per serving → Check first
        │
        ▼
HouseholdVerdict { overall, line: "Not for Mia · OK for you", people[ level, reason, findings ] }
        │
        ├──► UI: flag, reason line, mascot pose (notFor → guard, checkFirst → thinking, ok → done)
        └──► Chat: the on-device model writes the summary from the findings. It never changes the level.
```

- **Levels**, from best to worst: `ok`, `checkFirst`, `cantConfirm`, `notFor`. A person's level is their worst finding. The product's level is the worst person's level.
- **Hidden names** live in `data/catalog.json`. Each family (milk, peanut, seed oils…) lists its terms ("whey", "casein"…) and its look-alikes that are *not* it ("cocoa butter", "eggplant", "nutmeg").
- **The reason line names the person and the ingredient:** "Not for Mia. Contains whey: that’s milk." · "Not for you: sunflower oil is a seed oil." · "Can’t confirm. ‘Natural flavors’ isn’t specific."
- **Executable spec:** `data/verdict-cases.json` holds 45 cases. `tools/reference_engine.py` passes all of them. `LabelSageCore` (Swift) must pass the same cases with the same lines.

Details: `docs/logic/verdict-engine.md`.

## 5. Screens

| # | Screen | Spec | Board export |
|---|---|---|---|
| 0 | Launch | `docs/specs/01-launch-and-onboarding.md` | `design/screens/00-launch.png` |
| 1 | Onboarding: 14 key steps, a decision tree | same | `design/screens/onboarding/*.png`, `72-onboarding-decision-tree.png` |
| 2 | Chat home and thread | `docs/specs/02-chat-home.md` | `10-chat-home.png`, `70-flows-ai-first.png`, `71-chat-intents.png` |
| 3 | Check a product (camera) | `docs/specs/03-check-a-product.md` | `20-…`, `60-states-scan.png`, `61-states-scan-edge-cases.png` |
| 4 | Product page (page and sheet) | `docs/specs/04-product-page.md` | `30-…`, `31-product-page-full.png` |
| 5 | Compare with, then Compare | `docs/specs/05-compare.md` | `40-compare-with.png`, `41-compare.png` |
| 6 | Family (preferences and settings) | `docs/specs/06-family.md` | `50-family-preferences.png` |
| 7 | States, explainers, components | `docs/specs/07-states-and-components.md` | `62-…` to `65-…` |

Foundations (tokens, type, components, motion, accessibility): `docs/specs/00-foundations.md`, `design/tokens.json`.

## 6. Stack

- **Build in `app/`:** XcodeGen `app/frontend/ios/project.yml` (a standalone LabelSage project). The engine `LabelSageCore` lives in `app/shared/LabelSageCore` and checks US labels.
- **iOS 27 (per `PRD_front_end.md`), SwiftUI, Swift 6.2** with Approachable Concurrency. The app target uses main-actor-by-default. `LabelSageCore` stays `nonisolated` (it is a library).
- **SwiftData** for the household, go-tos and the check history. Everything stays on the device.
- **VisionKit `DataScannerViewController`** for barcodes and text. **Vision** text recognition for an uploaded photo of the ingredients.
- **Foundation Models** (on-device) for the chat: it reads the intent and writes the summary, using guided generation. A keyword router is the fallback when the model is unavailable.
- **The mascot** is drawn natively from PNG parts with SwiftUI transforms (see `docs/mascot.md`). A Rive file can come later; the rig is ready for it.
- **No third-party SDKs** in the MVP. No analytics until the team decides.

## 7. Build order

Milestones and acceptance criteria are in `docs/milestones.md`. Short version:

1. **Core:** wire `LabelSageCore`; all 45 fixture cases pass in `swift test`.
2. **Design system:** tokens, Outfit, the components and the Icon view with its fallbacks.
3. **Onboarding:** the decision tree, the per-person loop, region and store, the summary. Saves the Household.
4. **Check a product:** the scanner, every scan state, the product page sheet.
5. **Product page, Compare with, Compare.**
6. **Chat home:** start screen, thread, intents, the profile change confirm, the mascot dock.
7. **Family:** person cards, settings with region and store, go-tos checked again.
8. **Polish:** VoiceOver, Dynamic Type, Reduce Motion, offline, mascot motion.

## 8. Open questions (do not decide these in code)

Full list, including where this handoff (23 Oct) differs from the older repo docs (`PRD_front_end.md` of 19 Oct, register D-11 and D-12): `docs/open-questions.md`.

- **D4:** which product data and availability source. Until it is decided, ship `FixtureProductSource` and keep a feature flag for a real one.
- **Q2:** with "may contain" on, should an allergy give **Not for** (the current build) or **Check first**? The voice doc example uses Check first. The engine has one switch for this.
- **Q3:** a vegan diet hides the milk, egg and fish allergens in onboarding. Diets don't check "may contain", so a vegan with a real milk allergy would lose that check. Proposal: always let people add the allergy too.
- **Q4:** thresholds for the daily limits per serving (now 20% of the daily value).
- **Q7:** a clinician or dietitian has not reviewed the catalog's hidden names yet. This is required before launch.

## 9. What is in this folder

```
HANDOFF.md            this file
CLAUDE.md             how the coding agent works in this repo (read first)
README.md             map of the folder and the first commands
docs/                 specs per screen, logic, voice, mascot, icons, decisions, milestones, open questions
design/tokens.json    colors, type, radius, shadow, spacing, motion
design/screens/       2x PNG exports of every MVP board (onboarding/ has the 14 key steps)
design/prototype/     the canvas sources (.dc.html): exact styles, copy and state logic, for reference
assets/               Fluent icons (xcassets, 256 px) + icons.json, mascot parts + rig, app icon, Outfit font, licenses
data/                 catalog.json (hidden names), verdict-cases.json (spec), sample household and products
LabelSageCore/        Swift package: models, parser, matcher, verdict engine, reason lines, tests
tools/                reference_engine.py (the spec, runnable), sync-data.sh
```

Not included on purpose: research material, transcripts, and anything about the project LabelSage grew out of.
