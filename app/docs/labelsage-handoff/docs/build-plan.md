# LabelSage iOS build plan (subagent-driven)

Branch `labelsage-ios-mvp`. Base commit `e2229e8` (M0: handoff unpacked, `LabelSageCore` passes 45/45, app target builds).
Phase 1 builds components and animations; phase 2 builds the pages on mock data. The backend, ETL and real schemas
come later: every data access goes through a protocol with a fixture implementation.

## Shared context (every task)

- **Repo paths:** app target sources `app/frontend/ios/LabelSage/`, UI tests `app/frontend/ios/LabelSageUITests/`, XcodeGen
  spec `app/frontend/ios/project.yml` (do not edit unless the task says so), unit tests `app/frontend/ios/LabelSageTests/`, core package `app/shared/LabelSageCore`
  (do not change behavior; the 45 cases must stay green), handoff `app/docs/labelsage-handoff/` (specs, PNGs, prototypes,
  tokens, voice).
- **Sources of truth, in order** (`app/docs/labelsage-handoff/CLAUDE.md`): verdict cases and reference engine; `docs/specs/*.md`;
  `design/screens/*.png` (look); `design/prototype/*.dc.html` (exact values and copy; reference only, never port
  HTML/JS); `design/tokens.json` (values); `docs/voice-and-strings.md` (every word). If two disagree, add the conflict
  to `app/docs/labelsage-handoff/docs/open-questions.md` with the default you used, and continue.
- **Hard rules:** never "safe" (or safer, unsafe, 100%, guaranteed, allergy-proof, protected); the flag comes only from
  `VerdictEngine`, the model only rewrites reason text; one `MascotView` on screen; "Check the package. Not medical
  advice." under every verdict; nothing about a person leaves the device; names from `Brand.app` / `Brand.mascot`;
  no em dashes in copy; accessible by default (labels, Dynamic Type to AX5, Reduce Motion, never color alone); MVP
  only (no lists, basket, Instacart, recipes, share).
- **Swift and Apple practice:** Swift 6 language mode, main actor by default in the app target, `@Observable` models,
  async/await only, value types first, `Sendable` where crossing actors, no force unwraps without a reason, no
  retain cycles, doc comments on public types, no third-party dependencies. Native only: SwiftUI, SwiftData,
  VisionKit, Vision, Foundation Models.
- **Ponytail (smallest complete change):** before writing code, take the first option that fully works: does it
  need to exist; already in this codebase; Swift standard library or an Apple framework; one line; otherwise the
  minimum code. No abstraction, wrapper, option or "for later" code nobody asked for. Finish every part the task
  needs (callers, previews, tests). Never cut validation, error handling, accessibility or anything the spec asks
  for. Mark a known shortcut in code as `// shortcut: <limit>, <when to upgrade>`. End the report with what you
  skipped or did not check.
- **Liquid Glass (native glassmorphism):** floating controls use `.glassEffect(.regular.interactive(), in: .circle)` or
  `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)`; group nearby glass with `GlassEffectContainer(spacing:)`;
  morph with `.glassEffectID(_:in:)`. Glass only on floating controls (back, close, favorite, new chat, camera
  controls, segmented picker over the camera), never on content cards.
- **Build:** `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; cd app/frontend/ios && xcodegen generate && xcodebuild -project LabelSage.xcodeproj -scheme LabelSage -destination 'platform=iOS Simulator,name=LabelSage iPhone 17 Pro,OS=27.0' -derivedDataPath /tmp/ls-dd build`.
  Re-run `xcodegen generate` after adding files. Core tests: `cd app/shared/LabelSageCore && swift test`.
- **Visual check:** the app opens `DesignGallery` when launched with `-gallery` and a screen with `-screen <name>`
  (added in T3 and T13). Install and screenshot:
  `xcrun simctl boot "LabelSage iPhone 17 Pro" 2>/dev/null; xcrun simctl install "LabelSage iPhone 17 Pro" /tmp/ls-dd/Build/Products/Debug-iphonesimulator/LabelSage.app; xcrun simctl launch "LabelSage iPhone 17 Pro" app.labelsage.ios -gallery; sleep 3; xcrun simctl io "LabelSage iPhone 17 Pro" screenshot /tmp/shot.png`,
  then open the screenshot and the board PNG with the Read tool and compare.
- **Previews:** every component and screen state gets a `#Preview`.
- **Commit** on branch `labelsage-ios-mvp` when the task is done, message `app: <what>`, ending with
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Never push. Never touch files outside the
  task's folders except `open-questions.md` and the spec's "Decisions made in build" list.

## Phase 1: components and animations

### T1 Theme and typography
Folder: `DesignSystem/Theme/`. Read `docs/specs/00-foundations.md`, `design/tokens.json`.
- `Theme` exposing every token group as typed Swift values: `Theme.color.*`, `Theme.verdict.*` (color, wash, symbol),
  `Theme.chip.*`, `Theme.screenTint.*`, `Theme.radius.*`, `Theme.shadow.*` (as a `ViewModifier` for the two-layer card
  shadow and the selected outline), `Theme.spacing.*`, `Theme.size.*`, `Theme.motion.*` (SwiftUI `Animation` values
  with the exact cubic curves; a helper that returns the Reduce Motion variant).
- Outfit variable font registered (already in `UIAppFonts`); `Theme.type.*` as `Font.custom("Outfit", size:, relativeTo:)`
  with the token weights and tracking, scaling with Dynamic Type; tabular figures for numbers.
- `Color(hex:)` helper used only inside `Theme`. Views never use raw hex.
- Unit-free check: a preview listing every color swatch and type style.
Done when: builds, preview shows all tokens, values match `tokens.json` exactly.

### T2 IconView
Folder: `DesignSystem/Icons/`. Read `docs/icons.md`, `assets/icons.json` (bundled as `Resources/icons.json`).
- `IconCatalog` loads `icons.json` once (keys, aliases, asset names, labels, standIn).
- `IconView(key:size:)`: resolves key or alias (case-insensitive, trims) → image set in `LabelSageIcons.xcassets`;
  states loaded / missing (letter tile: #f3ead8 tile, first letter #8a6a3a at 46% size, radius 28%) / failed (same
  tile). Loading shimmer only as a component state for previews (no remote images in the MVP).
- VoiceOver: hidden when `decorative: true`, else reads `label`.
- Unit tests in `LabelSageTests/` (Swift Testing, `@testable import LabelSage`): resolution, aliases, unknown key.
Done when: all 116 assets resolve, aliases work (prawn → shrimp), unknown key shows the letter tile.

### T3 Controls and DesignGallery
Folder: `DesignSystem/Components/` and `DesignSystem/Gallery/`. Read `docs/specs/00-foundations.md`, boards
`65-components-cards-composer.png`, onboarding PNGs for option cards, prototypes `Button.dc.html`, `OnboardSimple.dc.html`.
- `PressableStyle` (scale 0.98, 120 ms easeOut, springs back; no color change).
- `PrimaryButton` (enabled, disabled with "dimmed" + hint, loading; height 66, capsule, amber, ink label, amber glow,
  optional trailing chevron).
- `GlassButton` (44 circle, SF Symbol, label; Liquid Glass interactive).
- `Checkbox` (square radius 9, circle variant, leaf 26 pt), `OptionCard` (single, multi), `OptionTile`, `GroupCard`
  (closed/open in place, 2-column `LeafTile` grid, first leaf spans both columns, count pill, 30 ms stagger),
  `LeafTile`, `Chip` (avoid, preferNot, dietGoal), `KindBadge` (flips Avoid ↔ Prefer not), `SectionHeader`.
- Selection haptic (`.sensoryFeedback(.selection, trigger:)`).
- `DesignGallery` view: a scrolling list of sections; `LabelSageApp` shows it when launched with `-gallery`
  (edit `App/LabelSageApp.swift` only for this switch). Add a section per component with every state.
Done when: every state has a preview and a gallery entry; a simulator screenshot of the gallery matches the board
styling (sizes, radii, shadows, colors).

### T4 Verdict, product and message components
Folders: `DesignSystem/Components/`. Read `docs/specs/00-foundations.md`, `07-states-and-components.md`, boards
`62-states-verdict-flags.png`, `64-product-row-stress-test.png`, `65-…`, prototypes `States.dc.html`, `ProductRow.dc.html`,
`ProductRowStress.dc.html`, `Cards.dc.html`.
- `VerdictFlag` (4 levels × small 36 / medium 48 / large 60; white circle, 3 pt ring, SF Symbol; one gentle pulse 2 × 1 s
  on first show, none with Reduce Motion; `.warning` haptic once for notFor; VoiceOver "Verdict: Not for Mia").
  Takes `LabelSageCore.Level`.
- `VerdictBanner` (wash, symbol, title, reason, then "Check the package. Not medical advice."; reason crossfades when
  replaced, 200 ms).
- `PersonLine`, `ProductRow` (row, card 204 wide, compact; 48/120 image with pack fallback and brand or name initial;
  2-line name; price tabular, hidden when nil keeping height), `Bubble` (mascot, user), `Toast` (info, action; 4 s;
  swipe down), `PersonCard`, `SegmentedPicker` on glass (2 options).
- Gallery sections for all of them, including the stress cases from `07-…`.
Done when: previews and gallery match boards 62, 64 and 65.

### T5 Mascot rig and the 13 animated states
Folder: `Mascot/`. Read `docs/mascot.md`, `assets/Mascot/rig.json` (bundled under `Resources/Mascot/` as a folder
reference: `Bundle.main.url(forResource: "rig", withExtension: "json", subdirectory: "Mascot")`), board
`80-mascot-states.png`, prototypes `Mascot.dc.html` and `MascotStates.dc.html` (the `@keyframes tg-*` are the motion
source).
- `MascotState` enum (13 states), `MascotView(state:size:)`: parts placed from `rig.json` in draw order on the
  960 × 1210 artboard, scaled so the artboard height maps to `size × 1.26`; choose `parts-full` or `parts-prototype`
  per the rig notes and say which.
- Motion for all 13 states from the CSS keyframes, transform and opacity only, via `KeyframeAnimator` /
  `PhaseAnimator` / `TimelineView`; loops `easeInOut` (0.77, 0, 0.175, 1), jump and entrances `easeOut`
  (0.23, 1, 0.32, 1); 150 ms crossfade between states; `idle` → `hum` after 15 s without a tap; `guard` still.
- Reduce Motion renders the first key frame, no timeline.
- `accessibilityHidden(true)`; an accessibility identifier `mascot` on every instance for the one-mascot UI test.
- `MascotPresence` (environment object) that enforces one mascot: a host (dock, sheet, tip) claims it; others render
  nothing.
- Gallery section showing all 13 states at size 74 and the sizes 64, 56, 40, 30.
Done when: every state animates in the simulator and matches the board's poses; Reduce Motion freezes them.

## Phase 2: pages on mock data

### T6 Data and app model (mock backend)
Folders: `Data/`, `App/`. Read `docs/logic/data-and-privacy.md`, `verdict-engine.md`, `chat-agent.md`,
`data/sample-household.json`, `data/sample-products.json`, and `LabelSageCore` public API.
- SwiftData models: `HouseholdRecord`, `PersonRecord` (rules), `GoToRecord`, `CheckRecord` (history); mapping to
  `LabelSageCore` `Person`/`Rule`/`Household`.
- `ProductSource` protocol (barcode lookup, name search, other options by region/store) and `FixtureProductSource`
  reading `Resources/Data/sample-products.json`, with an artificial 300–600 ms delay and an offline switch for states.
  A feature flag stub `ProductSourceFactory` for a future real source (D4 open).
- `VerdictService`: runs `VerdictEngine` for the household and returns `HouseholdVerdict` plus pose.
- `ExplanationService`: Foundation Models rewrites the reason only (fresh session, instructions bundled, tool calling
  disallowed, output checked: no deny words, contains the matched term), template fallback when unavailable
  (`docs/app-engineering/spikes/spike-foundation-models-ios27-prompts-tools-2026-10-23.md` in the repo).
- `AppModel` (`@Observable`): household, onboarding done flag, router (tabs/sheets), sample data seeding with
  launch arg `-demoHousehold`.
Done when: builds; a preview or debug screen runs a fixture product through the engine and shows the line.

### T7 Launch and onboarding
Folder: `Features/Onboarding/`. Read `docs/specs/01-launch-and-onboarding.md`, `docs/logic/onboarding-tree.md`, all
`design/screens/onboarding/*.png`, `00-launch.png`, `72-…`, prototypes `OnboardSimple*.dc.html`, `OnboardTree.dc.html`,
`Splash.dc.html`, `Stepper.dc.html`.
- Launch, Welcome, the full decision tree with the per-person loop, allergens (groups open in place, peanut suggests
  tree nuts and lupin never pre-ticked, search knows other names), allergy or intolerance per allergen (allergy
  default), may contain, anything else (groups, catalog search, custom filter), region (required), store (optional,
  "Set up later"), summary (flip Avoid / Prefer not), "Check my first product" saves the household and routes to the
  camera. Mascot poses per step. Step transitions per foundations motion.
Done when: every step matches its PNG; Skip never passes the region; previews for every step.

### T8 Check a product (camera)
Folder: `Features/Scan/`. Read `docs/specs/03-check-a-product.md`, boards `20-…`, `60-…`, `61-…`, prototypes
`Scan.dc.html`, `ScanStates.dc.html`, `MvpStates.dc.html`.
- `DataScannerViewController` wrapper (barcode EAN-13, UPC-E, EAN-8; text mode), simulator fallback (fixture picker
  so the flow works without a camera), glass controls, Barcode | Ingredients segmented picker on glass, Enter code,
  Type a name, Upload a photo (PhotosPicker → Vision `RecognizeTextRequest`) → `Product(ingredientsText:)`.
- States: idle, checking, product (sheet), not found, no ingredients, camera off, offline. Result opens the product
  sheet over the camera (from T9; use a placeholder sheet view if T9 is not merged yet and leave a TODO).
Done when: all states reachable with fixtures; screenshots match boards.

### T9 Product page (page and sheet)
Folder: `Features/Product/`. Read `docs/specs/04-product-page.md`, boards `30-…`, `31-…`, prototype `Main.dc.html`.
- One view, `as: .page | .sheet`, `photo: .shown | .hidden`; flag, person line, reason (crossfades to the model text),
  disclaimer, What you avoid rows, Key ingredients, Nutrition (per serving / per 100 g), Other options for you,
  toolbar (glass), go-to save. Mascot moves into the sheet.
Done when: all spec states have previews; matches boards.

### T10 Compare with and Compare
Folder: `Features/Compare/`. Read `docs/specs/05-compare.md`, boards `40-…`, `41-…`, prototypes `Compare.dc.html`, `Pick.dc.html`.
Done when: Differences and Everything, Save to go-tos, matches boards.

### T11 Chat home
Folder: `Features/Chat/`. Read `docs/specs/02-chat-home.md`, `docs/logic/chat-agent.md`, boards `10-…`, `70-…`, `71-…`,
prototypes `Chat.dc.html`, `ChatIntents.dc.html`, `Flows.dc.html`, `Explainer*.dc.html`.
- Start screen, header with people line, history menu, new chat, thread, the six intents (keyword router; Foundation
  Models guided intent when available), product cards and sheets, pivots, change allergies card with confirm, re-check
  go-tos, Undo, the mascot dock, explainers (welcome sheet, coach marks, inline tip).
Done when: the seven stories in the spec run on fixtures; matches boards.

### T12 Family
Folder: `Features/Family/`. Read `docs/specs/06-family.md`, board `50-…`, prototype `Profile.dc.html`.
Done when: person cards, add a person (reuses onboarding), go-tos re-checked, settings (region, store, language,
units, Apple Health placeholder, Show tips again) match the board.

### T13 App shell and UI tests
Folders: `App/`, `app/frontend/ios/LabelSageUITests/`.
- Root: onboarding when no household, else chat home; sheets and navigation per the flows board; `-screen <name>`
  launch argument for direct screenshots; `-demoHousehold` seeding.
- UI tests: one mascot on every screen; onboarding path always reaches region before summary; verdict flag
  symbols per level.
Done when: UI tests pass on the iOS 27 simulator.
