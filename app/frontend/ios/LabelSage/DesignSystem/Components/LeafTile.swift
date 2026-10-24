import SwiftUI

/// One leaf inside an open `GroupCard` (00-foundations `LeafTile`): icon, title, 26 pt checkbox,
/// at least 64 pt tall, radius 22. Selected swaps the shadow for the 2 pt ink outline.
struct LeafTile: View {
    let title: String
    /// Defaults to the title: `IconView` resolves names like "Almond" through icons.json aliases,
    /// and shows the letter tile when it can't.
    var iconKey: String? = nil
    let isOn: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Prototype leaf icon: `Icon size="34"`; tokens.json has no size between 22 and 48.
    private static let iconSize: CGFloat = 34

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.spacing.s) {
                IconView(key: iconKey ?? title, size: Self.iconSize, decorative: true)
                Text(title)
                    .themeText(.bodyStrong)
                    .foregroundStyle(Theme.color.ink)
                    .multilineTextAlignment(.leading)
                    // Two columns leave about 100 pt for the name, and wrapping would break one
                    // word ("Pistachi-o"), so it shrinks a little instead. At accessibility sizes
                    // the grid is one column and the name wraps freely.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Checkbox(isOn: isOn, style: .leaf)
            }
            .padding(.leading, Theme.spacing.cardPaddingH)
            .padding(.trailing, Theme.spacing.m)
            .padding(.vertical, Theme.spacing.s)
            .frame(maxWidth: .infinity, minHeight: Theme.size.leafTileMinHeight)
            .themeCardBackground(cornerRadius: Theme.radius.leafTile, isSelected: isOn)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

#Preview("LeafTile - off and on") {
    HStack(spacing: Theme.spacing.m) {
        LeafTile(title: "Almond", isOn: false) {}
        LeafTile(title: "Cashew", isOn: true) {}
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.screenTint.allergens)
}
