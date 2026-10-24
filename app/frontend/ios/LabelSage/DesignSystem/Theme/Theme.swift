import SwiftUI

/// The single source of truth for LabelSage's design tokens (`design/tokens.json` in the handoff,
/// `app/docs/labelsage-handoff/design/tokens.json` in this repo).
///
/// Views never use a raw hex string, point size, radius, curve or duration: they read
/// `Theme.color.*`, `Theme.verdict.*`, `Theme.chip.*`, `Theme.screenTint.*`, `Theme.radius.*`,
/// `Theme.spacing.*`, `Theme.size.*`, `Theme.type.*` (via `.themeText(_:)`), the `Theme.shadow.*`
/// view modifiers, and `Theme.motion.*`.
///
/// Token group in `tokens.json` -> file in this folder:
/// - `color`, `verdict`, `chips`, `screenTint` -> `Theme+Color.swift`
/// - `radius`, `spacing`, `size`               -> `Theme+Layout.swift`
/// - `shadow`                                  -> `Theme+Shadow.swift`
/// - `font`, `type`                            -> `Theme+Type.swift`
/// - `motion`                                  -> `Theme+Motion.swift`
///
/// `materials.glass` (tokens.json): "Liquid Glass only on floating controls (back, favorite,
/// composer, the bottom action bar). Content stays flat." That's a placement rule, not a numeric
/// value, so there is nothing to type here: components that need Liquid Glass (e.g. `GlassButton`)
/// should reach for `.glassEffect()` directly and follow that rule, and never put glass on card
/// or tile content.
///
/// The namespaces below (`color`, `verdict`, `chip`, `screenTint`, `radius`, `spacing`, `size`,
/// `type`, `motion`) are deliberately lowercase: they're named to match `tokens.json`'s own group
/// names exactly, not Swift's usual type-naming convention.
///
/// `nonisolated`: this target's default actor isolation is `MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`), so without this every token below would implicitly
/// be main-actor-isolated — which breaks the moment a `Shape.path(in:)`, `Layout`, or `Animatable`
/// curve (all `nonisolated` by protocol requirement) tries to read `Theme.radius.card` or similar
/// off the main actor. `Theme` and its namespace extensions are `nonisolated` so tokens are plain,
/// actor-independent data, readable from anywhere. The `ViewModifier`s built on top of them (in
/// `Theme+Shadow.swift`, `Theme+Type.swift`, `Theme+Motion.swift`) stay main-actor, which is where
/// `View` bodies run anyway.
nonisolated enum Theme {}
