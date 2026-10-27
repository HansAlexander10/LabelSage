---
type: reference
entity: LabelSage native components
owner: Artem
status: current
updated: 2026-10-26
---

# LabelSage native components

The LabelSage native components page maps every element of the design to the Apple API that builds it. Read the table for your screen, build with the named API, then restyle with tokens from `Theme`.

## Rule: native component first

LabelSage uses the native component first. The team restyles a native component with tokens from `design/tokens.json` and keeps its native size, placement and behaviour. HIG `branding.md › Best practices` says: "ensure that details like sizing, placement, and behavior continue to preserve a familiar experience". A custom view is allowed only when no native component can match the design, and the table row says why. Liquid Glass goes only on floating controls, never on content cards (`tokens.json` `materials.glass`). HIG `liquid-glass.md › Where the material belongs`: says the same: "Don't use Liquid Glass in the content layer".

How this page was checked. Every API name below was found in the iOS 27.1 SDK interfaces in Xcode on 2026-10-26 (`SwiftUI`, `SwiftUICore`, `VisionKit`, `Vision`, `TipKit`, `FoundationModels`, `SwiftData`, `Charts`, `_PhotosUI_SwiftUI`, `_CoreLocationUI_SwiftUI`). Context7 (`/websites/developer_apple_swiftui`, read 2026-10-26) confirmed the usage of `GlassEffectContainer`, `glassEffectID(_:in:)`, `safeAreaBar(edge:)` and `scrollEdgeEffectStyle(_:for:)`. Rows marked "judgment" are recommendations without an Apple source.

Facts:
- LabelSage → prefers → native components restyled with `Theme` tokens
- Liquid Glass → applies to → floating controls only
- API names → verified against → iOS 27.1 SDK swiftinterface files

## Shared components (the component map)

| Design element | Native API | How to match the design | Native or custom | HIG |
|---|---|---|---|---|
| Verdict flag badge (36, 48, 60) | `Image(systemName:)` in `Circle().strokeBorder` | Symbols `checkmark.circle`, `exclamationmark.triangle`, `nosign`, `questionmark.circle.fill`; ring and fill from `Theme.verdict`; `.accessibilityLabel("Verdict: Not for Mia")` | Custom: no system badge carries a level ring | `sf-symbols.md`, `color.md` |
| Pulsing photo flag | `keyframeAnimator(initialValue:trigger:)` or `PhaseAnimator` on the ring scale | Two pulses of 1 s; skip when `@Environment(\.accessibilityReduceMotion)` is true; `.sensoryFeedback(.warning, trigger:)` once for an allergy | Custom animation on native animators | `motion.md › Make motion optional` |
| Product row, product line | `Button` with an `HStack`, inside `List` rows or a `LazyVStack` | Image 48 with pack fallback; name `.lineLimit(2)`; price `.monospacedDigit()`; flag overlaid bottom-right of the thumbnail | Custom row: no system cell has a flag on a thumbnail | `lists-and-tables.md › Choose a row style` |
| Product tile, 204 pt option card | `ScrollView(.horizontal)` + `LazyHStack` + `.scrollTargetLayout()` + `.scrollTargetBehavior(.viewAligned)` | Card is `Button` + `.buttonStyle(.pressable)`; white, `Theme.radius.card`, `Theme.shadow.card` | Custom card on a native scroll | `scroll-views.md` |
| Ingredient chip | `Chip` (built) | Tint by finding; `.accessibilityLabel` adds the level | Custom: SwiftUI has no chip view | none |
| Quantity stepper | `Stepper(value:in:step:)` | Label "Protein per meal", value text in `.monospacedDigit()`; system −/+ capsule already matches the board | Native | `steppers.md › Make the value that a stepper affects obvious` |
| Primary button (amber) | `PrimaryButton` (built) on `Button` | 66 pt capsule, ink label, amber glow | Custom size: `.glassProminent` cannot reach 66 pt with the amber glow | `buttons.md › Style` |
| Secondary button | `Button` + `.buttonStyle(.glass)` or a plain text `Button` | Ink label, `systemImage` leading | Native | `buttons.md › Style` |
| Glass circle button (44) | `GlassButton` (built): `.glassEffect(.regular.interactive(), in: .circle)`, frame `Theme.size.minTap`; inside bars use `ToolbarItem` | 44 × 44 matches the iOS default control size | Native material, custom wrapper | `accessibility.md › Mobility` (44x44 pt default) |
| Navigation bar | `NavigationStack` + `.toolbar { ToolbarItem(placement: .topBarLeading / .topBarTrailing / .principal) }` | Bar buttons get Liquid Glass from the system; title `.navigationTitle`, people line `.navigationSubtitle` | Native | `toolbars.md › Use the standard Back and Close buttons` |
| Bottom sheet | `.sheet(item:)` + `.presentationDetents([.medium, .large], selection:)` + `.presentationDragIndicator(.visible)` | `.presentationBackground(Theme.screenTint.product)` | Native | `sheets.md › Include a grabber in a resizable sheet` |
| Segmented control | `Picker` + `.pickerStyle(.segmented)` + `.labelsHidden()` | Two text segments; `.sensoryFeedback(.selection, trigger:)` | Native | `segmented-controls.md › Use nouns or noun phrases` |
| Switch | `Toggle(isOn:)` (default switch style) | Only in a row; `.tint` only if the brand green is needed | Native | `toggles.md › Use the switch toggle style only in a list row` |
| Radio and checkbox row | `Checkbox`, `OptionCard`, `OptionTile` (built) on `Button` with `.accessibilityAddTraits(.isSelected)` | 30 pt box, ink fill, 2 pt ink outline when selected | Custom: `.toggleStyle(.checkbox)` is `@available(iOS, unavailable)` in the SDK | `toggles.md › Checkboxes` |
| Grouped list card | `List` + `.listStyle(.insetGrouped)` + `.scrollContentBackground(.hidden)` | Rows `LabeledContent("Region", value:)` in `NavigationLink`; `.listRowBackground(Theme.color.surface)` | Native | `lists-and-tables.md › Choose a table or list style` |
| Section title | `SectionHeader` (built), or `Section { } header: { }` in a `List` | 22/700 Outfit, `.accessibilityAddTraits(.isHeader)` | Native in lists, custom in scroll views | `typography.md` |
| Search field | `.searchable(text:placement:prompt:)` + `.searchSuggestions { }` | Debounce with `.task(id: query)` and `Task.sleep(for: .milliseconds(250))` | Native | `search-fields.md › Use placeholder text` |
| Chat composer | `TextField(_:text:axis: .vertical)` in `.safeAreaBar(edge: .bottom)` | 54 pt capsules, `GlassEffectContainer` for the three parts | Native parts, custom layout | `text-fields.md › Show a hint`; `liquid-glass.md` |
| Option card, group card, leaf tile, kind badge | `OptionCard`, `GroupCard`, `LeafTile`, `KindBadge` (built) | See `07-states-and-components.md` build notes | Custom: no system selectable card | `buttons.md › Always include a press state` |
| Toast | `.overlay(alignment: .bottom)` + `.transition(.move(edge: .bottom).combined(with: .opacity))` | #232323, white text, 4 s, `AccessibilityNotification.Announcement` | Custom: iOS has no toast component | `feedback.md › Consider integrating status feedback` |
| Info button ("May contain") | `Button` with `info.circle` + `.popover` + `.presentationCompactAdaptation(.popover)` | Short text, no navigation | Native | `lists-and-tables.md › Use an info button only to reveal more information` |

Facts:
- `GlassButton` → wraps → `glassEffect(_:in:)` at 44 pt
- `Toggle` → uses → switch style only in rows
- checkbox toggle style → is unavailable on → iOS
- toast → is → custom overlay with an accessibility announcement

## Launch and onboarding

| Design element | Native API | How to match the design | Native or custom | HIG |
|---|---|---|---|---|
| System launch screen | `UILaunchScreen` in `Info.plist` with `UIColorName` | Green background only, no text, no logo | Native | `launching.md › Avoid including text on your launch screen` |
| Splash (mascot, wordmark, mesh) | `MeshGradient` + `MascotView` | Shown on first open only; tap or 1.5 s goes on | Custom content on native gradient | `launching.md › If you need a splash screen, consider displaying it at the beginning of your onboarding flow` |
| Step skeleton (back, dots, skip, mascot line, answers, Continue) | `ScrollView` + `.safeAreaBar(edge: .bottom) { PrimaryButton }`; top row in `.safeAreaBar(edge: .top)` | Step change `.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))` at 280 ms; mascot outside the transition | Custom container: the mascot stays put while content slides, which `NavigationStack` push cannot do | `onboarding.md › design a brief, enjoyable experience` |
| Glass back button | `GlassButton(systemImage: "chevron.left")` | 44 pt, top-left, 54 pt from top | Native material | `toolbars.md › Use the standard Back and Close buttons` |
| Skip / Set up later | `Button` with `.buttonStyle(.glass)` | Text label "Skip", reads "Skip this step" | Native | `onboarding.md › consider making it optional` |
| Section dots | `HStack` of `Circle()` | Color crossfade 200 ms | Custom: `TabView` page dots track pages, not sections | none |
| Mascot line as title | `Text` + `.accessibilityAddTraits(.isHeader)` | `type.mascotTitle`, `ViewThatFits` for 30, 27, 24 pt | Native | `typography.md › Supporting Dynamic Type` |
| Name field and quick picks | `TextField` + `.textContentType(.givenName)` + `.submitLabel(.done)` + `@FocusState` | Names become `Chip`s | Native | `text-fields.md` |
| Allergen group search | `TextField` with a `magnifyingglass` icon in the content | Inline above the groups | Native field, inline placement | `search-fields.md › Search as an inline field` |
| Related allergens sheet | `.sheet` + `.presentationDetents([.medium])` | Unticked rows; "Add selected" primary; "Just peanut" text button | Native | `sheets.md › consider supporting the medium detent` |
| Resolver "Matching…" | `ProgressView()` + text | Then choices as `OptionCard`s | Native | `progress-indicators.md › Prefer an activity indicator` |
| Strict switch | `Toggle` in a white row | Footnote under the row | Native | `toggles.md › Use the switch toggle style only in a list row` |
| Use my location | `LocationButton(.currentLocation)` from CoreLocationUI | `.labelStyle`, `.tint(Theme.color.ink)`, `.foregroundStyle(.white)`, `.cornerRadius` | Native; the button grants one-time access without an alert | `privacy.md › Location button` |
| City or ZIP search | `.searchable` + `.searchSuggestions` (4 max) | List label "Matching places" | Native | `search-fields.md › Consider showing suggested search terms` |
| Store list | `OptionCard` single choice | "1.2 mi · Downtown" detail | Custom (built) | `toggles.md › Radio buttons` |
| Summary person cards | `PersonCard` with `KindBadge` | Cards fade up with 40 ms stagger | Custom | none |
| Resume after kill | `@SceneStorage` or SwiftData state | Restore the last step | Native | `launching.md › Restore the previous state` |

Facts:
- onboarding step container → is → custom, because the mascot stays in place
- `LocationButton` → fills → the region step without a permission alert
- `MeshGradient` → draws → the splash background

## Chat home and thread

| Design element | Native API | How to match the design | Native or custom | HIG |
|---|---|---|---|---|
| Header avatar → Family | `ToolbarItem(placement: .topBarLeading)` with a `NavigationLink` | Initials on green circle, 44 pt tap | Native | `toolbars.md › Navigation` |
| "New chat ⌄" with history | `.toolbarTitleMenu { }` on `.navigationTitle` | Past chats as `Button`s | Native | `toolbars.md › Titles` |
| People line | `.navigationSubtitle(...)` | Caption, truncated | Native | `toolbars.md › Titles` |
| New chat glass circle | `ToolbarItem(placement: .topBarTrailing)` with `square.and.pencil` | System glass in the bar | Native | `toolbars.md › Prefer system-provided symbols without borders` |
| Big title "What do you need today?" | `Text` in content, `.accessibilityAddTraits(.isHeader)` | 34/700 Outfit | Native text (judgment: content title, not a nav large title) | `toolbars.md › Use a large title` |
| Hero card "Check a product" | `Button` card + `PrimaryButton(systemImage: "barcode.viewfinder")` | White, `radius.card` | Custom card | `buttons.md` |
| Three start tiles | `LazyVGrid(columns: 3)`; one column at AX sizes via `@Environment(\.dynamicTypeSize)` | 3D icons via `IconView` | Custom tile on native grid | `layout.md › Be prepared for text-size changes` |
| Thread | `ScrollView` + `LazyVStack` + `.defaultScrollAnchor(.bottom)` + `.scrollDismissesKeyboard(.interactively)` | New message `.transition(.move(edge: .bottom).combined(with: .opacity))` 220 ms | Native | `scroll-views.md` |
| User bubble, answer cards | `Text` in a white `RoundedRectangle`; `ProductRow` | Content layer, no glass | Custom | `liquid-glass.md › The two layers` |
| Change card segmented Allergy / Intolerance | `Picker` + `.pickerStyle(.segmented)` | Helper line updates with selection | Native | `segmented-controls.md` |
| Mascot dock + bubble | `MascotView` + bubble in the same `.safeAreaBar(edge: .bottom)` as the composer | Bubble hides when `@FocusState` is true (keyboard up) | Custom: no system equivalent | none |
| Composer photo button | `PhotosPicker(selection:matching: .images)` | 54 pt glass circle | Native | `privacy.md` (picker needs no photo permission) |
| Composer camera / Send | `Button` swapping `barcode.viewfinder` and `arrow.up`; Send `.buttonStyle(.glassProminent).tint(Theme.color.ink)` | `.contentTransition(.symbolEffect(.replace))` | Native | `liquid-glass.md › To emphasize a primary action, color the background` |
| Answer announcement | `AccessibilityNotification.Announcement(line).post()` | Post the dock line | Native | `accessibility.md` |

Facts:
- chat header → uses → `toolbarTitleMenu` and `navigationSubtitle`
- composer and mascot dock → share → one `safeAreaBar(edge: .bottom)`
- Send button → uses → `.glassProminent` tinted ink

## Check a product (camera)

| Design element | Native API | How to match the design | Native or custom | HIG |
|---|---|---|---|---|
| Full-screen camera | `.fullScreenCover(isPresented:)` | Black background, `.preferredColorScheme(.dark)` inside | Native | `sheets.md › consider alternatives to sheets` (full-screen for camera views) |
| Camera feed + barcode reading | `DataScannerViewController` in `UIViewControllerRepresentable`; `.barcode(symbologies: [.ean13, .ean8, .upce, .code128])` | `isHighlightingEnabled: false`, `regionOfInterest` = frame rect | Native | `privacy.md › Request permission only when your app clearly needs access` |
| Availability check | `DataScannerViewController.isSupported` and `.isAvailable`; `AVCaptureDevice.authorizationStatus(for: .video)` | Not available → camera off state | Native | `privacy.md` |
| Ingredients photo + OCR | `capturePhoto()` on the scanner, then Vision `RecognizeTextRequest` with `.recognitionLevel = .accurate` | Keep the image in memory only | Native | `privacy.md` |
| Top bar Close, title, torch | `GlassButton` ×2 + `Text` 17/600 white | `.glassEffect(.clear.interactive(), in: .circle)` over the feed | Native material | `liquid-glass.md › Which variant` (clear over rich media) |
| Torch | `AVCaptureDevice.default(for: .video)` + `lockForConfiguration()` + `torchMode` | Hide when `hasTorch` is false | Native (judgment: `DataScannerViewController` has no torch property; test that the torch works while the scanner runs) | none |
| Dim layer with cutout | `Rectangle().fill(.black.opacity(0.55))` masked by a `RoundedRectangle` with `.blendMode(.destinationOut)` + `.compositingGroup()` | #232323 at 55 % | Custom | none |
| Frame brackets | Custom `Shape` (4 corner arcs, 4 pt) | Tighten 6 pt and turn green, 200 ms | Custom | none |
| Barcode / Ingredients | `Picker(.segmented)` on `.glassEffect(.clear, in: .capsule)` | `.environment(\.colorScheme, .dark)` | Native | `segmented-controls.md › Consider a segmented control to switch between closely related subviews` |
| Enter code / Type a name pills | `Button` + `.buttonStyle(.glass)` | Enter code opens `.alert` with a `TextField` and `.keyboardType(.numberPad)` | Native | `text-fields.md › show the appropriate keyboard type` |
| Upload a photo | `.photosPicker(isPresented:selection:matching: .images)` | Same OCR path | Native | none |
| Found haptic | `.sensoryFeedback(.success, trigger: code)` | Debounce the same code for 2 s | Native | `playing-haptics.md › Use system-provided haptic patterns according to their documented meanings` |
| State card (checking, not found, no ingredients, camera off, offline) | `ContentUnavailableView` inside a white card, radius 28 | Slide up 24 pt + fade, 260 ms | Native view, custom card | `feedback.md › Show people when a command can't be carried out` |
| Result | Product page as a sheet over the camera (see next section) | Medium detent | Native | `sheets.md` |
| Offline detection | `NWPathMonitor` (Network) | "Checked before" list from SwiftData `@Query` | Native | `loading.md` |

Facts:
- camera screen → presents with → `fullScreenCover`
- `DataScannerViewController` → reads → EAN-13, EAN-8, UPC-E, Code 128
- `RecognizeTextRequest` → reads → the ingredients photo on device
- torch → needs → `AVCaptureDevice` because the scanner has no torch API

## Product page (page and sheet)

| Design element | Native API | How to match the design | Native or custom | HIG |
|---|---|---|---|---|
| One view, two uses | `ProductPage` pushed with `.navigationDestination(for:)` or shown in `.sheet(item:)` | Sheet: `[.medium, .large]`, grabber, Close (`Button(role: .close)`) replaces Back | Native | `sheets.md › Include a grabber`; `toolbars.md › standard Back and Close` |
| Photo hero, sticky, page dots | `TabView` + `.tabViewStyle(.page(indexDisplayMode: .always))` + `.indexViewStyle(.page(backgroundDisplayMode: .always))` | Sticky with `.visualEffect` offset (snippet below) | Native paging, custom sticky | `scroll-views.md` |
| Back and favorite circles | `ToolbarItem(.topBarLeading)` back is automatic; `ToolbarItem(.topBarTrailing)` heart | `heart` / `heart.fill` + `.symbolEffect(.bounce, value:)` | Native | `toolbars.md` |
| Content sheet overlapping 28 pt | `UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)` background, `.offset(y: -28)` | `screenTint.product` | Custom shape, content layer | none |
| Mini header after 400–480 pt | `.onScrollGeometryChange(for:of:action:)` drives the opacity of a `ToolbarItem(placement: .principal)` | 36 pt thumb, name, small flag | Native bar (judgment: preferred over a custom glass bar) | `toolbars.md › Use a large title to help people stay oriented` |
| Verdict banner | `VStack` card, level wash | Reason crossfade `.contentTransition(.opacity)` + `.animation(.easeInOut(duration: 0.2), value:)` | Custom | `feedback.md` |
| What you avoid ⌄ with per-rule switches | `DisclosureGroup` + `Toggle` per row | Note "For this check only" appears on change | Native | `toggles.md › Clearly identify the setting` |
| Key ingredients rows, open in place | `DisclosureGroup` per row, or a `Button` with `withAnimation(.easeOut(duration: 0.22))` | Level symbol + name + finding | Native | `lists-and-tables.md` |
| Other options (204 pt cards) | `ScrollView(.horizontal)` + `.scrollTargetBehavior(.viewAligned)`; vertical `List` at AX sizes | "See all" pushes a list | Native scroll, custom card | `scroll-views.md` |
| Nutrition donut | Swift Charts `Chart { SectorMark(angle:innerRadius: .ratio(0.62)) }` | Colors carbs #eb9d15, fat #7e9086, protein #26834e; `.accessibilityElement(children: .ignore)` + one label | Native (Charts is a system framework) | `charts.md` |
| Per serving / per 100 g | `Picker(.segmented)` inside the "Full nutrition facts" `DisclosureGroup` | | Native | `segmented-controls.md` |
| Bottom bar: Ask LabelSage + Check another | `.safeAreaBar(edge: .bottom)` with `GlassEffectContainer`; Ask is `.buttonStyle(.glass)`, Check another is `PrimaryButton` | Stack at AX sizes with `ViewThatFits` | Native material, custom bar (66 pt primary does not fit `ToolbarItem(placement: .bottomBar)`) | `toolbars.md › Keep actions with text labels separate` |
| Favorite toast with Undo | Toast (see shared) | | Custom | `feedback.md` |
| Model summary | `LanguageModelSession(instructions:)` + `respond(to:)`; gate on `SystemLanguageModel.default.availability` | Keep the engine line when unavailable | Native, on device | `generative-ai.md` |

Facts:
- `ProductPage` → is presented as → a pushed page or a sheet with medium and large detents
- mini header → is driven by → `onScrollGeometryChange`
- nutrition donut → uses → Swift Charts `SectorMark`
- product bottom bar → uses → `safeAreaBar` with `GlassEffectContainer`

## Compare with and Compare

| Design element | Native API | How to match the design | Native or custom | HIG |
|---|---|---|---|---|
| Compare with sheet | `.sheet` + `.presentationDetents([.large])` + `NavigationStack` | Close `ToolbarItem(.topBarLeading)`, title "Compare with" | Native | `sheets.md › Mobile` (Cancel or Close on the leading edge) |
| Comparing row | `ProductRow` compact | White, radius 18 | Custom | none |
| Search by name | `.searchable(text:, placement: .navigationBarDrawer(displayMode: .automatic))` | Results after 2 characters, 250 ms debounce | Native | `search-fields.md › start search immediately when a person types` |
| Other options list | `List` of `ProductRow`; mascot 30 pt in the section header | Deciding attribute trailing | Native list, custom row | `lists-and-tables.md` |
| Compare columns and tables | `Grid` + `GridRow`; `ViewThatFits` stacks columns at AX sizes | Better cell bold + `checkmark` symbol | Native layout | `lists-and-tables.md › Use descriptive column headings` |
| Differences / Everything | `Picker(.segmented)` | Rows animate with `.animation(.easeOut(duration: 0.22), value: filter)` | Native | `segmented-controls.md` |
| Why card | `VStack` card, 3 lines max | | Custom | none |
| Bottom bar with Save to go-tos | `.safeAreaBar(edge: .bottom)` + `GlassEffectContainer` + `PrimaryButton` | Saved state morphs; `.sensoryFeedback(.success, trigger:)` | Native material, custom layout | `feedback.md › confirm that a significant action or task has completed` |

Facts:
- Compare with → opens as → a large sheet with a `NavigationStack`
- compare tables → use → `Grid` and `GridRow`
- Save to go-tos → plays → `.success` haptic

## Family preferences and settings

| Design element | Native API | How to match the design | Native or custom | HIG |
|---|---|---|---|---|
| Screen and "‹ Chat" back | `NavigationStack` push; system back button | `screenTint.family` via `.background` and `.scrollContentBackground(.hidden)` | Native | `toolbars.md › Use the standard Back and Close buttons` |
| Title "Family" + mascot | `.navigationTitle("Family")` with `.toolbarTitleDisplayMode(.large)`, or a content title | Mascot 56 pt beside the title (judgment) | Native | `toolbars.md › Use a large title` |
| Person card closed / open | `PersonCard` with Edit `Button(.glass)`; height `withAnimation(.easeOut(duration: 0.24))` | 2 pt ink outline when open | Custom | none |
| Item row with badge and switch | `HStack` + `KindBadge` + `Toggle` | Off: chip struck through (`.strikethrough()`) | Native switch, custom badge | `toggles.md` |
| Swipe to remove an item | `.swipeActions(edge: .trailing) { Button(role: .destructive) }` + `.alert` with Remove and Keep | Works only inside `List` rows | Native (build Family as a `List` with sections) | `feedback.md › Warn people when they initiate a task that can cause data loss` |
| Add a person (dashed card) | `Button` with `RoundedRectangle().strokeBorder(style: StrokeStyle(dash:))` | Runs onboarding for one person | Custom | none |
| Macros rows | `Stepper` in a row | "Protein per meal · 25 g" | Native | `steppers.md` |
| Go-tos | `List` section of `ProductRow` with `NavigationLink` | Re-check spinner `ProgressView().controlSize(.mini)` ≤ 600 ms | Native | `lists-and-tables.md` |
| Settings: Region, Store, Language, Units | `NavigationLink { } label: { LabeledContent("Region", value: zip) }` | SF Symbols leading via `Label` | Native | `settings.md` |
| Apple Health | `Toggle` + `HKHealthStore.requestAuthorization(toShare:read:)` | Read height, weight, age only | Native | `privacy.md › Request access only to data that you actually need` |
| Show tips again | `Button` that sets a TipKit `@Parameter` | See explainers | Native | `offering-help.md` |

Facts:
- Family screen → should be → a `List` so that `swipeActions` works
- settings rows → use → `LabeledContent` inside `NavigationLink`
- Apple Health switch → requests → height, weight and age only

## Explainers, coach marks and inline tips

| Design element | Native API | How to match the design | Native or custom | HIG |
|---|---|---|---|---|
| Welcome sheet (step 1 of 3) | `.sheet` + `.presentationDetents([.height(320)])` + `.interactiveDismissDisabled(false)` | Mascot waving; Skip and "Show me how" | Native | `onboarding.md › Consider providing a collection of context-specific tips` |
| Coach mark (steps 2 and 3) | TipKit `Tip` + `TipGroup(.ordered)` + `.popoverTip(_:arrowEdge:action:)` | `image` = mascot pose; `actions` Skip / Next; `.tipBackground(Theme.color.surface)`; `.tipViewStyle` for the bubble | Native; spotlight dimming is custom | `offering-help.md › Display a popover tip when you want to preserve the content flow` |
| Inline tip from the dock | TipKit `Tip` for eligibility; dock bubble renders `tip.title` and calls `tip.invalidate(reason: .actionPerformed)` on Got it | One tip per screen, `MaxDisplayCount(1)` | Native rules, custom rendering (one mascot rule) | `offering-help.md › Define rules` |
| Tour rules | `Tips.configure([.displayFrequency(.immediate)])` at launch | Skip invalidates every tip in the group | Native | `offering-help.md` |
| Loading in the thread | `MascotView(.reading)` + "Checking the ingredients…" | No spinner by design | Custom | `loading.md › Show something as soon as possible` |

Facts:
- coach marks → use → TipKit `popoverTip` with `TipGroup(.ordered)`
- inline tip → uses → TipKit rules with a custom dock bubble
- TipKit → has no → spotlight dimming

## App plumbing used by every screen

| Need | Native API | Note |
|---|---|---|
| App state | `@Observable` `AppModel`, injected with `.environment(model)` | Main actor by default (Swift 6) |
| Storage | SwiftData `@Model` (Household, Person, Rule, GoTo, Check) + `@Query` + `.modelContainer(for:)` | Nothing about a person leaves the device |
| On-device model | FoundationModels `LanguageModelSession`, `SystemLanguageModel.default.availability` (`.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady`) | Do not use `PrivateCloudComputeLanguageModel` (new in the iOS 27 SDK): it sends data off the device |
| Haptics | `.sensoryFeedback(.selection / .success / .warning, trigger:)` | `playing-haptics.md › Avoid overusing haptics` |
| Mascot loops | `PhaseAnimator`, `KeyframeAnimator`; freeze with `accessibilityReduceMotion` | `motion.md › Make motion optional` |
| Fonts | `Font.custom("Outfit", size:, relativeTo:)` (built in `Theme+Type`) | `typography.md › Implement accessibility features for custom fonts` |
| Open Settings | `@Environment(\.openURL)` with `UIApplication.openSettingsURLString` | Camera off state |

Facts:
- `AppModel` → is → `@Observable`
- SwiftData → stores → household, rules and go-tos on device
- `PrivateCloudComputeLanguageModel` → is excluded by → the on-device data rule

## Verified snippets for the non-obvious parts

Liquid Glass button group. Keep neighbours in one `GlassEffectContainer` so they blend and morph; `glassEffectID` animates a button in or out.

```swift
@Namespace private var glassNS
GlassEffectContainer(spacing: Theme.spacing.m) {
    HStack(spacing: Theme.spacing.m) {
        GlassButton(systemImage: "chevron.left", label: "Back", action: back)
            .glassEffectID("back", in: glassNS)
        if canFavorite {
            GlassButton(systemImage: isSaved ? "heart.fill" : "heart", label: "Add to go-tos", action: toggleSave)
                .glassEffectID("heart", in: glassNS)
        }
    }
}
```

Product page as page or sheet. One view, two presentations.

```swift
.navigationDestination(for: Product.ID.self) { id in ProductPage(id: id, style: .page) }
.sheet(item: $sheetProduct) { product in
    NavigationStack {
        ProductPage(id: product.id, style: .sheet)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "xmark", role: .close) { sheetProduct = nil } } }
    }
    .presentationDetents([.medium, .large], selection: $detent)
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.screenTint.product)
}
```

Composer in a glass bottom bar. `safeAreaBar` insets the thread and extends the scroll edge effect, which `safeAreaInset` does not.

```swift
ScrollView { ThreadView(messages) }
    .defaultScrollAnchor(.bottom)
    .scrollDismissesKeyboard(.interactively)
    .safeAreaBar(edge: .bottom) {
        VStack(spacing: Theme.spacing.s) {
            if !isTyping { MascotDock(pose: pose, line: line) }
            GlassEffectContainer(spacing: Theme.spacing.s) {
                HStack(spacing: Theme.spacing.s) {
                    PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo") }
                        .frame(width: 54, height: 54).glassEffect(.regular.interactive(), in: .circle)
                    TextField("Ask LabelSage…", text: $draft, axis: .vertical)
                        .lineLimit(1...5).focused($isTyping)
                        .padding(.horizontal, 18).frame(minHeight: 54).glassEffect(.regular, in: .capsule)
                    SendOrCameraButton(isEmpty: draft.isEmpty)   // .glassProminent + .tint(Theme.color.ink) for Send
                }
            }
        }
        .padding(.horizontal, Theme.spacing.l)
    }
```

Sticky photo hero and mini header. The hero cancels its own scroll offset, so the content slides over it.

```swift
ScrollView {
    VStack(spacing: 0) {
        PhotoHero(product).frame(height: heroHeight)
            .visualEffect { content, proxy in
                let minY = proxy.frame(in: .scrollView).minY
                return content.offset(y: minY < 0 ? -minY : 0)
            }
        ProductContent(product)
            .background(Theme.screenTint.product, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
            .offset(y: -28)
    }
}
.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
    miniHeader = min(max((y - 400) / 80, 0), 1)
}
.toolbar { ToolbarItem(placement: .principal) { MiniHeader(product).opacity(miniHeader) } }
```

Data scanner for barcode and text. `recognizedDataTypes` is a `let`, so switching modes rebuilds the controller with `.id(mode)`.

```swift
struct ScannerView: UIViewControllerRepresentable {
    let mode: ScanMode; let onBarcode: (String) -> Void
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = mode == .barcode
            ? [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])] : [.text()]
        let vc = DataScannerViewController(recognizedDataTypes: types, qualityLevel: .balanced,
                                           recognizesMultipleItems: false, isHighlightingEnabled: false)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }
    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode) }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcode: (String) -> Void
        init(onBarcode: @escaping (String) -> Void) { self.onBarcode = onBarcode }
        func dataScanner(_ s: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let code) in added { if let value = code.payloadStringValue { onBarcode(value); return } }
        }
    }
}
// Ingredients: let image = try await vc.capturePhoto()
// var request = RecognizeTextRequest(); request.recognitionLevel = .accurate
// let lines = try await request.perform(on: image.cgImage!).compactMap { $0.topCandidates(1).first?.string }
```

TipKit coach mark tour. Steps 2 and 3 run in order; Skip ends the tour.

```swift
struct PointAtBarcodeTip: Tip {
    var title: Text { Text("Point at the barcode") }
    var message: Text? { Text("Hold steady. I check the ingredients, \(firstName)’s allergies first.") }
    var image: Image? { Image("mascot-point") }
    var actions: [Action] { Action(id: "skip", title: "Skip"); Action(id: "next", title: "Next") }
    var options: [any TipOption] { MaxDisplayCount(1) }
}
let tour = TipGroup(.ordered) { PointAtBarcodeTip(); OneFlagTip() }
ScanFrame()
    .popoverTip(tour.currentTip as? PointAtBarcodeTip, arrowEdge: .bottom) { action in
        action.id == "skip" ? endTour() : tour.currentTip?.invalidate(reason: .actionPerformed)
    }
// App init: try? Tips.configure([.displayFrequency(.immediate)])
```

Empty and error states with `ContentUnavailableView`. The icon slot takes the mascot, and the actions slot takes the amber button.

```swift
ContentUnavailableView {
    Label { Text("Allow the camera to check products") } icon: { MascotView(pose: .listen).frame(width: 74, height: 74) }
} description: {
    Text("The barcode is read on your iPhone. No photos are saved or sent.")
} actions: {
    PrimaryButton(title: "Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
    Button("Type a name instead", action: typeName)
}
```

Segmented picker over the camera. Clear glass suits controls over live video.

```swift
Picker("Mode", selection: $mode) {
    Text("Barcode").tag(ScanMode.barcode)
    Text("Ingredients").tag(ScanMode.ingredients)
}
.pickerStyle(.segmented)
.labelsHidden()
.fixedSize()
.padding(4)
.glassEffect(.clear, in: .capsule)
.environment(\.colorScheme, .dark)
.sensoryFeedback(.selection, trigger: mode)
```

Facts:
- `GlassEffectContainer` → groups → neighbouring glass buttons
- `safeAreaBar(edge:)` → extends → the scroll edge effect under the composer
- `DataScannerViewController` → is rebuilt on → a mode change
- `ContentUnavailableView` → renders → scan and empty states

## Where the design departs from the HIG

Each item names the design choice, the HIG source when one exists, and a recommendation. Items without a quote are judgment.

1. **Compare opens as a second sheet over the product sheet.** See HIG `sheets.md › Best practices`: "Display only one sheet at a time from the main interface." Recommendation: push Compare inside the product sheet's `NavigationStack` and expand to the large detent.
2. **Coach marks dim the screen with a spotlight.** TipKit has no spotlight. HIG `offering-help.md › Creating tips` prefers popover tips that "preserve the content flow". Recommendation (judgment): ship `popoverTip` without the dim layer; add the dim only if testing shows people miss the target.
3. **"Show tips again" in Settings.** `Tips.resetDatastore()` is meant for launch before `Tips.configure`. Recommendation (judgment): gate tips on a TipKit `@Parameter` that the button flips, instead of resetting the store.
4. **Swipe left to remove an item inside a white card.** `swipeActions` works only in `List` rows. Recommendation: build Family as an inset-grouped `List`, or add Remove to an Edit menu.
5. **66 pt amber primary button.** System prominent buttons are smaller. HIG `branding.md › Best practices` asks to keep size and placement familiar. Recommendation (judgment): keep 66 pt for the one primary per screen (onboarding, camera result), and use `.glassProminent` with `.tint(Theme.color.amber)` in compact bars if the bar looks crowded.
6. **Custom glass mini header on the product page.** Recommendation (judgment): use the system nav bar with a `.principal` item, which already has glass and the scroll edge effect (`scroll-views.md › Prefer the automatic scroll edge effect style`).
7. **No tab bar.** HIG `tab-bars.md › Use a tab bar to support navigation, not to provide actions`. LabelSage has one hub (chat), one pushed area (Family) and one action (camera). Recommendation (judgment): no tab bar is right; keep the camera as an action, not a tab.
8. **Splash for 1.5 s before Welcome.** HIG `launching.md › Launch instantly`. Recommendation: show the splash on first open only; later launches go straight to the chat with state restored.
Facts:
- stacked sheets → conflict with → `sheets.md` one sheet at a time
- coach mark spotlight → is not provided by → TipKit
- no tab bar → fits → a chat hub with one pushed area

## More HIG departures and a board conflict

The LabelSage design has four more items that depart from the HIG or from its own spec.

9. **Terms and Privacy line on Welcome.** HIG `onboarding.md › Avoid displaying licensing details within your onboarding flow`. Recommendation (judgment): keep two links only, no text body.
10. **Outfit for body and captions.** HIG `branding.md › Consider using a custom font`: custom for headlines, "system fonts for body copy and captions". Recommendation (judgment): test Outfit at 13 pt and AX5; switch captions to SF if legibility drops.
11. **Board 65 composer differs from spec 02.** Board 65 shows a plus menu (Upload photo, Take a photo, Scan barcode), a mic and a stop button. Spec `02-chat-home.md` shows a photo button and a camera/Send button. Board 65 also shows add (+) buttons and steppers on product rows and tiles, which look like a basket that `CLAUDE.md` parks. This page does not pick one: list both in `docs/open-questions.md`.
12. **Glass circles at 44 pt and composer controls at 54 pt.** Both meet HIG `accessibility.md › Mobility` (44x44 pt default). No change.

Facts:
- board 65 composer → conflicts with → `02-chat-home.md` composer
- 44 pt glass circles → meet → HIG default control size
