import SwiftUI

nonisolated extension Theme {
    /// Corner radii from tokens.json `radius`.
    enum radius {
        /// Cards and option cards.
        static let card: CGFloat = 26
        /// Tiles and leaf tiles.
        static let tile: CGFloat = 22
        static let optionCard: CGFloat = 26
        static let leafTile: CGFloat = 22
        static let field: CGFloat = 12
        static let searchField: CGFloat = 22
        static let chip: CGFloat = 999
        static let button: CGFloat = 999
        static let checkbox: CGFloat = 9
        static let productThumb: CGFloat = 12
        static let phoneSheet: CGFloat = 28

        /// tokens.json radius.letterTile: "28% of size". `size` is the fallback tile's side length.
        static func letterTile(size: CGFloat) -> CGFloat { size * 0.28 }

        /// Not in tokens.json's `radius` group: `icons.md` and `Icon.dc.html` give the fallback
        /// tile's letter its own proportion, "46% of size, bold" (`Icon.dc.html`: `font-size:
        /// Math.round(size * 0.46) + 'px'; font-weight: 700`). Kept beside `letterTile(size:)`
        /// since both describe the same fallback tile.
        static func letterTileFont(size: CGFloat) -> CGFloat { size * 0.46 }
    }

    /// Spacing scale from tokens.json `spacing`.
    enum spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let section: CGFloat = 28
        /// Cards go edge to this gutter.
        static let screenGutter: CGFloat = 20
        static let cardPaddingV: CGFloat = 14
        static let cardPaddingH: CGFloat = 18
    }

    /// Fixed sizes from tokens.json `size`.
    enum size {
        /// Minimum touch target, every direction.
        static let minTap: CGFloat = 44
        static let optionCardMinHeight: CGFloat = 80
        static let tileMinHeight: CGFloat = 158
        static let leafTileMinHeight: CGFloat = 64
        /// A minimum, not a fixed height: this is a text-bearing control, so at larger Dynamic
        /// Type sizes it grows taller to fit its label. Apply with `.frame(minHeight:)`, never
        /// `.frame(height:)`.
        static let primaryButtonHeight: CGFloat = 66
        static let checkbox: CGFloat = 30
        static let leafCheckbox: CGFloat = 26
        /// tokens.json size.switch: `[51, 31]`. Named `switchControl` since `switch` is reserved.
        static let switchControl = CGSize(width: 51, height: 31)
        static let iconInCard: CGFloat = 48
        static let iconInTile: CGFloat = 64
        static let iconInChip: CGFloat = 22
        static let mascotOnboarding: CGFloat = 74
        static let mascotChatDock: CGFloat = 84 // board 10 dock (`Chat.dc.html` size="84")
        static let mascotSectionHeading: CGFloat = 30
        static let verdictSignal: CGFloat = 60
    }
}
