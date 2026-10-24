# Milestones

Build in this order. Each milestone ends with a demo on a device and every box ticked. Don't start the next one with a red test.

## M0 · Project and core (half a day)

- [ ] Work in the existing `app/` (D-08): `app/frontend/ios/project.yml` (XcodeGen, standalone LabelSage project), iOS 27, Swift 6.2, Approachable Concurrency, main actor by default for the app target.
- [ ] `LabelSageCore` copied to `app/shared/LabelSageCore` and added to `project.yml`. **It has never been compiled:** build it, fix compile errors without changing behavior.
- [ ] `swift test` in `LabelSageCore`: all 45 fixture cases and the parser tests pass.
- [ ] `Brand.swift` with `app` and `mascot` names ("LabelSage"), read from `Brand.plist` or a single constant file.

## M1 · Design system

Spec: `specs/00-foundations.md`, `design/tokens.json`, `icons.md`, `mascot.md`.

- [ ] Outfit registered; `Theme` exposes colors, type styles (Dynamic Type), radii, shadows, spacing from `tokens.json`.
- [ ] Components with previews for every state: `PrimaryButton`, `OptionCard` (single and multi), `OptionTile`, `LeafTile`, `Checkbox`, `Switch` (system), `Chip` (Avoid, Prefer not, Diet), `VerdictFlag` (4 levels, 3 sizes), `VerdictBanner`, `ProductRow` (row, card, with image fallback), `IconView` (loaded, loading, missing, failed), `Bubble`, `Toast`, `SectionHeader`, `PersonCard`.
- [ ] `LabelSageIcons.xcassets` and `icons.json` in the app; `IconView(key:)` resolves keys and aliases; unknown keys show the letter tile.
- [ ] `MascotView(state:size:)` shows all 13 poses as still images (motion comes in M8). Reduce Motion is respected from day one.

## M2 · Onboarding

Spec: `specs/01-launch-and-onboarding.md`, `logic/onboarding-tree.md`.

- [ ] Launch screen and Welcome.
- [ ] The decision tree exactly as in `logic/onboarding-tree.md`, including the per-person loop for "My family".
- [ ] Allergens: groups open in place; peanut suggests tree nuts and lupin (never pre-ticked); search knows other names (prawns → Fish and shellfish).
- [ ] Allergy or intolerance per allergen, Allergy by default. "May contain" step.
- [ ] Anything else: groups, catalog search, "Make ‘…’ a custom filter".
- [ ] **Region (required) and store (optional, "Set up later")** once for the household, then the summary with one card per person and the region and store row.
- [ ] Summary: flip Avoid and Prefer not; "Check my first product" saves the Household and opens the camera (D1).
- [ ] UI test: every path reaches the region before the summary; Skip never jumps past it.

## M3 · Check a product

Spec: `specs/03-check-a-product.md`.

- [ ] Camera with barcode and ingredients modes, Enter code, Type a name, Upload a photo.
- [ ] States: idle, barcode found (checking), product, not found, found without ingredients, camera access off, offline.
- [ ] Ingredients photo: Vision text → `Product(ingredientsText:)` → the same engine.
- [ ] Result opens the product page as a sheet over the camera; the mascot moves into the sheet.

## M4 · Product page, Compare with, Compare

Specs: `specs/04-product-page.md`, `specs/05-compare.md`.

- [ ] Product page as a page and as a sheet, from one view.
- [ ] Flag, person line, reason, "Check the package. Not medical advice.", What you avoid rows, Key ingredients, Nutrition, Other options for you, toolbar.
- [ ] The reason crossfades to the model summary when ready (D8); no skeleton.
- [ ] Compare with: camera first, search, options; Compare: Differences and Everything, Save to go-tos.

## M5 · Chat home

Spec: `specs/02-chat-home.md`, `logic/chat-agent.md`.

- [ ] Start screen, header with people line, history menu, new chat.
- [ ] Thread with the six intents; results as product cards and sheets; pivots keep context.
- [ ] Change allergies: exact change card, Allergy or Intolerance, Confirm, re-check go-tos, Undo.
- [ ] Mascot dock: one LabelSage, moves into sheets (UI test).
- [ ] Foundation Models with guided generation; keyword fallback when unavailable.

## M6 · Family

Spec: `specs/06-family.md`.

- [ ] Person cards with Avoid and Prefer not switches; add a person (runs the onboarding questions for them).
- [ ] Macros and calories, Go-tos (checked again on open and after changes, with "Heads up" when ingredients changed).
- [ ] Settings: **Region, Store**, Language, Units, Apple Health.

## M7 · Polish and hardening

- [ ] Mascot motion for all 13 states (`mascot.md`), Reduce Motion holds the pose.
- [ ] VoiceOver order and labels per spec; Dynamic Type to AX5; contrast checks on every tint.
- [ ] Offline: checked-before products work; new ones say so.
- [ ] `specs/07-states-and-components.md` stress cases (long names, missing photos, zero items).
- [ ] Every string checked against `voice-and-strings.md` (grep for "safe" must return nothing user-facing).
