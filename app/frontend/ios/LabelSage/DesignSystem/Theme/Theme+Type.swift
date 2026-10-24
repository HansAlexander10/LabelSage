import SwiftUI
import CoreText // this module declares `AttributedString.LineHeight`, used by `View.lineHeight(_:)`

nonisolated extension Theme {
    /// One Outfit type style from tokens.json `type`: size, weight, tracking, and the Dynamic Type
    /// text style it scales relative to. Use `.themeText(_:)` rather than reading `.font` alone,
    /// so tracking (and line height, where the token defines one) always comes along with it.
    nonisolated struct TypeStyle: Sendable {
        let size: CGFloat
        let weight: Font.Weight
        /// tokens.json tracking is an em value (a fraction of `size`); SwiftUI's `.tracking(_:)`
        /// wants points, so `trackingPoints` below does the conversion.
        private let trackingEm: CGFloat
        /// tokens.json lineHeight is a multiplier of `size`; `nil` when the token sets none, in
        /// which case the font's own default line height is used.
        private let lineHeightMultiplier: CGFloat?
        let relativeTo: Font.TextStyle
        let isTabularNumber: Bool

        init(
            size: CGFloat,
            weight: Font.Weight,
            trackingEm: CGFloat = 0,
            lineHeightMultiplier: CGFloat? = nil,
            relativeTo: Font.TextStyle,
            isTabularNumber: Bool = false
        ) {
            self.size = size
            self.weight = weight
            self.trackingEm = trackingEm
            self.lineHeightMultiplier = lineHeightMultiplier
            self.relativeTo = relativeTo
            self.isTabularNumber = isTabularNumber
        }

        /// The Outfit variable font (registered family name confirmed to be "Outfit" — see note in
        /// `ThemePreview.swift`), resolved to this style's weight via the font's `wght` axis, and
        /// scaling with Dynamic Type from `relativeTo`. Matches tokens.json's own instruction:
        /// `Font.custom("Outfit", size:, relativeTo:)`. Tabular figures are applied as a font
        /// feature (`.monospacedDigit()`) here rather than as a separate view modifier.
        var font: Font {
            let base = Font.custom("Outfit", size: size, relativeTo: relativeTo).weight(weight)
            return isTabularNumber ? base.monospacedDigit() : base
        }

        var trackingPoints: CGFloat { trackingEm * size }

        /// The token's line-height multiplier as a `View.lineHeight(_:)` value, or `nil` when the
        /// token sets none (Outfit's own natural line height, about 1.26 em, is left alone).
        /// `(multiplier - 1) * size` additive `.lineSpacing` was tried first and rejected: added on
        /// top of the font's already-1.26-em leading it overshoots to roughly 1.42 em instead of
        /// the intended 1.16 em.
        var lineHeight: AttributedString.LineHeight? {
            lineHeightMultiplier.map { .multiple(factor: $0) }
        }
    }

    /// `Theme.type` is `TypeStyle` itself (not a separate namespace enum): that is what lets
    /// `.themeText(.mascotTitle)` resolve via Swift's leading-dot shorthand, since the shorthand
    /// only looks for static members on the parameter's own type.
    typealias type = TypeStyle
}

nonisolated extension Theme.TypeStyle {
    /// LabelSage's line as the onboarding title. tokens.json note: "27 when the line is over
    /// 34 characters, 24 when over 58" — picking that size step is the caller's job; this is
    /// the base (30 pt) style.
    static let mascotTitle = Theme.TypeStyle(
        size: 30, weight: .heavy, trackingEm: -0.02, lineHeightMultiplier: 1.16, relativeTo: .largeTitle
    )
    static let screenTitle = Theme.TypeStyle(size: 34, weight: .bold, relativeTo: .largeTitle)
    /// "For you", "Other options for you", "Key ingredients", "Settings".
    static let sectionTitle = Theme.TypeStyle(size: 22, weight: .bold, relativeTo: .title2)
    static let productName = Theme.TypeStyle(size: 26, weight: .bold, relativeTo: .title)
    static let cardTitle = Theme.TypeStyle(size: 17, weight: .semibold, relativeTo: .headline)
    static let body = Theme.TypeStyle(size: 17, weight: .regular, relativeTo: .body)
    static let bodyStrong = Theme.TypeStyle(size: 17, weight: .semibold, relativeTo: .body)
    static let callout = Theme.TypeStyle(size: 15, weight: .regular, relativeTo: .callout)
    static let caption = Theme.TypeStyle(size: 14, weight: .regular, relativeTo: .subheadline)
    static let footnote = Theme.TypeStyle(size: 13, weight: .regular, relativeTo: .footnote)
    static let chip = Theme.TypeStyle(size: 15, weight: .semibold, relativeTo: .subheadline)
    static let primaryButton = Theme.TypeStyle(size: 20, weight: .semibold, relativeTo: .title3)
    /// Prices, grams, mg: tabular figures (tokens.json type.number.features: `["tnum"]`).
    static let number = Theme.TypeStyle(size: 17, weight: .regular, relativeTo: .body, isTabularNumber: true)
}

/// Applies a `Theme.TypeStyle`: the Outfit font at the right weight (tabular figures baked in for
/// `Theme.type.number`), its tracking, and its line height where the token defines one.
struct ThemeTextModifier: ViewModifier {
    let style: Theme.TypeStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        let styled = content.font(style.font).tracking(style.trackingPoints)
        if let lineHeight = style.lineHeight {
            styled.lineHeight(lineHeight)
        } else {
            styled
        }
    }
}

extension View {
    /// Applies a design-system type style (font, tracking, line height where the token calls for
    /// one). Views call `.themeText(.body)` instead of composing `.font(...)` and `.tracking(...)`
    /// by hand, since tracking is not part of `Font`.
    func themeText(_ style: Theme.TypeStyle) -> some View {
        modifier(ThemeTextModifier(style: style))
    }
}
