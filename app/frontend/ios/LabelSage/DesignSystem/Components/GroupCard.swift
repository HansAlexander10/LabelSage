import SwiftUI

/// The selection rules behind a `GroupCard`, kept apart from the view so they can be unit tested.
/// The group's first leaf, "All tree nuts", is not one of `leaves`: it is on when every leaf is,
/// and tapping it picks or clears all of them (prototype `OnboardSimple.dc.html`, `agroups`).
nonisolated enum GroupSelection {
    /// "All tree nuts" for the group "Tree nuts".
    static func allTitle(group: String) -> String { "All \(group.lowercased())" }

    static func count(_ selection: Set<String>, leaves: [String]) -> Int {
        leaves.filter(selection.contains).count
    }

    /// The count pill: "2/9".
    static func countText(_ selection: Set<String>, leaves: [String]) -> String {
        "\(count(selection, leaves: leaves))/\(leaves.count)"
    }

    static func isAllOn(_ selection: Set<String>, leaves: [String]) -> Bool {
        !leaves.isEmpty && leaves.allSatisfy(selection.contains)
    }

    /// Tapping "All …": clears every leaf when all are on, otherwise picks every leaf.
    static func toggledAll(_ selection: Set<String>, leaves: [String]) -> Set<String> {
        isAllOn(selection, leaves: leaves) ? selection.subtracting(leaves) : selection.union(leaves)
    }

    static func toggled(_ leaf: String, in selection: Set<String>) -> Set<String> {
        selection.symmetricDifference([leaf])
    }
}

/// An allergen group that opens in place (00-foundations `GroupCard`): a header card with icon,
/// title, count pill ("2/9", ink once any leaf is on) and chevron; open, a 2-column grid of
/// `LeafTile`s whose first leaf, "All tree nuts", spans both columns. Leaves fade in with a
/// 30 ms stagger while the card height animates (`Theme.motion.groupCardOpen`, 240 ms). At
/// accessibility text sizes the grid becomes one column.
struct GroupCard: View {
    let iconKey: String
    let title: String
    /// The group's leaves, without the "All …" leaf.
    let leaves: [String]
    @Binding var selection: Set<String>
    @Binding var isOpen: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var count: Int { GroupSelection.count(selection, leaves: leaves) }

    var body: some View {
        VStack(spacing: Theme.spacing.m) {
            header
            if isOpen {
                leafGrid
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(Theme.motion.reduceMotionAware(Theme.motion.groupCardOpen, reduceMotion: reduceMotion)) {
                isOpen.toggle()
            }
        } label: {
            HStack(spacing: Theme.spacing.l) {
                IconView(key: iconKey, size: Theme.size.iconInCard, decorative: true)
                Text(title)
                    .themeText(.optionTitle)
                    .foregroundStyle(Theme.color.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                countPill
                Image(systemName: isOpen ? "chevron.up" : "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.color.ink)
            }
            .padding(.vertical, Theme.spacing.cardPaddingV)
            .padding(.horizontal, Theme.spacing.cardPaddingH)
            .frame(maxWidth: .infinity, minHeight: Theme.size.optionCardMinHeight)
            .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: count > 0)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(count) of \(leaves.count) selected, \(isOpen ? "expanded" : "collapsed")")
        .accessibilityAddTraits(.isButton)
    }

    /// Prototype count pill: min width 52, height 32, 15 px; `#eceeec` off, ink with white on.
    private var countPill: some View {
        Text(GroupSelection.countText(selection, leaves: leaves))
            .themeText(.callout)
            .monospacedDigit()
            .foregroundStyle(count > 0 ? Theme.color.surface : Theme.color.ink)
            .padding(.horizontal, Theme.spacing.s)
            .frame(minWidth: 52, minHeight: 32)
            // shortcut: `#eceeec` is not a token; ink at 8% on white renders #edeeed. Swap for a
            // token if the designer adds one.
            .background(Capsule().fill(count > 0 ? Theme.color.ink : Theme.color.ink.opacity(0.08)))
    }

    @ViewBuilder
    private var leafGrid: some View {
        let allTile = LeafTile(
            title: GroupSelection.allTitle(group: title),
            iconKey: iconKey,
            isOn: GroupSelection.isAllOn(selection, leaves: leaves)
        ) {
            selection = GroupSelection.toggledAll(selection, leaves: leaves)
        }
        .staggeredFadeIn(index: 0)

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Theme.spacing.m) {
                allTile
                ForEach(Array(leaves.enumerated()), id: \.element) { index, leaf in
                    leafTile(leaf, index: index + 1)
                }
            }
        } else {
            Grid(horizontalSpacing: Theme.spacing.m, verticalSpacing: Theme.spacing.m) {
                GridRow {
                    allTile.gridCellColumns(2)
                }
                ForEach(Array(stride(from: 0, to: leaves.count, by: 2)), id: \.self) { start in
                    GridRow {
                        leafTile(leaves[start], index: start + 1)
                        if start + 1 < leaves.count {
                            leafTile(leaves[start + 1], index: start + 2)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        }
    }

    private func leafTile(_ leaf: String, index: Int) -> some View {
        LeafTile(title: leaf, isOn: selection.contains(leaf)) {
            selection = GroupSelection.toggled(leaf, in: selection)
        }
        .staggeredFadeIn(index: index)
    }
}

/// Fades a leaf in on appear, 30 ms after the one before it (00-foundations "Group card: Open").
/// A fade only, so it stays as is with Reduce Motion.
private struct StaggeredFadeIn: ViewModifier {
    let index: Int
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(Theme.motion.groupCardOpen.delay(Double(index) * 0.03)) {
                    isVisible = true
                }
            }
    }
}

private extension View {
    func staggeredFadeIn(index: Int) -> some View { modifier(StaggeredFadeIn(index: index)) }
}

private let treeNuts = ["Almond", "Cashew", "Walnut", "Pecan", "Pistachio", "Hazelnut", "Brazil nut", "Macadamia", "Pine nut"]

#Preview("GroupCard - closed") {
    @Previewable @State var selection: Set<String> = []
    @Previewable @State var isOpen = false
    GroupCard(iconKey: "treenuts", title: "Tree nuts", leaves: treeNuts, selection: $selection, isOpen: $isOpen)
        .padding(Theme.spacing.screenGutter)
        .background(Theme.screenTint.allergens)
}

#Preview("GroupCard - closed, some picked") {
    @Previewable @State var selection: Set<String> = ["Almond", "Cashew"]
    @Previewable @State var isOpen = false
    GroupCard(iconKey: "treenuts", title: "Tree nuts", leaves: treeNuts, selection: $selection, isOpen: $isOpen)
        .padding(Theme.spacing.screenGutter)
        .background(Theme.screenTint.allergens)
}

#Preview("GroupCard - open") {
    @Previewable @State var selection: Set<String> = ["Cashew"]
    @Previewable @State var isOpen = true
    ScrollView {
        GroupCard(iconKey: "treenuts", title: "Tree nuts", leaves: treeNuts, selection: $selection, isOpen: $isOpen)
            .padding(Theme.spacing.screenGutter)
    }
    .background(Theme.screenTint.allergens)
}
