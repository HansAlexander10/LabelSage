import SwiftUI

extension Theme {
    /// Shadows from tokens.json `shadow`, exposed as `ViewModifier` values. Only `primary` is
    /// still a standalone value: the card shadow and the selected outline are no longer applied on
    /// their own (see `themeCardBackground` below) since applying `.shadow(...)` directly to a
    /// view's content shadows every sub-layer (every glyph, every symbol) instead of just the
    /// card's silhouette — expensive in a list, and visibly wrong (double, offscreen blur per
    /// text run). `ViewModifier` structs stay main-actor; only the plain token data above them
    /// (`Theme.radius`, `Theme.color`, etc.) needs to be `nonisolated`.
    enum shadow {
        /// tokens.json shadow.primary: `0 6px 18px rgba(235,157,21,0.3)` — the glow under the
        /// screen's one primary (amber) button. Apply it to the button's background capsule; the
        /// modifier also flattens its content first (`.compositingGroup()`), so even on a whole
        /// button only the silhouette glows, never the label's glyphs.
        static let primary = ThemePrimaryGlowModifier()
    }
}

/// The card chrome from tokens.json `shadow.card` + `shadow.selected`, drawn once as a background
/// layer behind `content` rather than on `content` itself:
/// - unselected: the two-layer soft shadow (`0 1px 2px rgba(29,43,34,0.04), 0 10px 26px
///   rgba(29,43,34,0.05)`) under a white `Theme.color.surface` rounded rect.
/// - selected: "a 2 pt ink outline instead of the shadow" (tokens.json) — the shadow's color
///   becomes `.clear` (not removed: removing the modifier would change the view's identity and
///   break animation) and a 2 pt ink outline is drawn instead. The outline sits fully outside the
///   card edge, as on the boards and in the prototype (`box-shadow: 0 0 0 2px #1d2b22`, a spread
///   outside the box), so selecting a card never shrinks or shifts its content.
struct ThemeCardBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.color.surface)
                .shadow(color: isSelected ? .clear : Theme.color.ink.opacity(0.04), radius: 1, x: 0, y: 1)
                .shadow(color: isSelected ? .clear : Theme.color.ink.opacity(0.05), radius: 13, x: 0, y: 10)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                            .strokeBorder(Theme.color.ink, lineWidth: 2)
                            .padding(-2)
                    }
                }
        }
    }
}

/// tokens.json shadow.primary: `0 6px 18px rgba(235,157,21,0.3)`. CSS blur radius halves to the
/// SwiftUI `radius` parameter, matching the ratio tokens.json's own `shadow.card.swiftUI`
/// translation uses (blur 2 -> radius 1, blur 26 -> radius 13), so blur 18 -> radius 9 here.
struct ThemePrimaryGlowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .compositingGroup()
            .shadow(color: Theme.color.amber.opacity(0.3), radius: 9, x: 0, y: 6)
    }
}

extension View {
    /// The `OptionCard`/`OptionTile`/card chrome: a white `Theme.color.surface` background on
    /// `cornerRadius`, with the soft two-layer shadow when unselected and a 2 pt ink outline
    /// instead when selected. This is the card's *background*, not a shadow on its content — put
    /// it under the card's text/icon layer, not around it.
    func themeCardBackground(cornerRadius: CGFloat, isSelected: Bool) -> some View {
        modifier(ThemeCardBackgroundModifier(cornerRadius: cornerRadius, isSelected: isSelected))
    }

    /// The amber glow under the screen's one primary button.
    func themePrimaryGlow() -> some View { modifier(Theme.shadow.primary) }
}
