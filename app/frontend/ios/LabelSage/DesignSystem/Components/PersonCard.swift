import SwiftUI

/// One thing a person avoids or follows, as the Family card shows it.
struct PersonItem: Identifiable, Hashable {
    var id: String
    /// `IconView` key: "peanut".
    var iconKey: String
    /// "Peanut".
    var title: String
    /// "Allergy · “may contain” too".
    var detail: String
    var kind: KindBadge.Kind
    /// Off keeps the item but the engine ignores it (spec 06 "Item switch").
    var isOn: Bool = true
}

/// The rules behind `PersonCard`'s summary line, kept apart from the view for unit tests.
nonisolated enum PersonSummary {
    /// "2 to avoid · 1 prefer not", "1 diet", "Nothing to avoid yet". Only items that are on.
    static func line(_ items: [PersonItem]) -> String {
        let on = items.filter(\.isOn)
        func count(_ kind: KindBadge.Kind) -> Int { on.filter { $0.kind == kind }.count }
        var parts: [String] = []
        if count(.avoid) > 0 { parts.append("\(count(.avoid)) to avoid") }
        if count(.preferNot) > 0 { parts.append("\(count(.preferNot)) prefer not") }
        if count(.diet) > 0 { parts.append(count(.diet) == 1 ? "1 diet" : "\(count(.diet)) diets") }
        if count(.goal) > 0 { parts.append(count(.goal) == 1 ? "1 goal" : "\(count(.goal)) goals") }
        return parts.isEmpty ? "Nothing to avoid yet" : parts.joined(separator: " \u{00B7} ")
    }

    /// "Alex (you)" for the owner, else the name. Onboarding saves an unnamed owner as "You",
    /// which reads "You", not "You (you)".
    static func title(name: String, isOwner: Bool) -> String {
        guard isOwner else { return name }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.lowercased() == "you" ? "You" : "\(trimmed) (you)"
    }

    /// The avatar's letter; "?" for a person without a name yet.
    static func initial(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }
}

/// One person on the Family screen and the onboarding summary (spec 06 `PersonCard`, prototype
/// `Profile.dc.html`). Closed: avatar initial on a tint, name, "2 to avoid · 1 prefer not", Edit,
/// and a chip for each item that is on. Open (Edit → Done, 2 pt ink outline): one row per item with
/// its icon, detail, `KindBadge` and a switch, then "Add an allergy by telling LabelSage".
// Custom: no system card opens in place with an outline (native-components.md, "Person card").
struct PersonCard: View {
    let name: String
    var isOwner: Bool = false
    /// Position in the household, for the avatar tint.
    var index: Int = 0
    @Binding var items: [PersonItem]
    @Binding var isOpen: Bool
    /// "Add an allergy by telling LabelSage": opens the chat with "Add an allergy for Mia".
    var addByChat: () -> Void = {}

    private static let avatarSide: CGFloat = 48
    private static let itemIconSide: CGFloat = 32

    private var title: String { PersonSummary.title(name: name, isOwner: isOwner) }
    private var summary: String { PersonSummary.line(items) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            header
            if isOpen {
                openRows.transition(.opacity)
            } else if items.contains(where: \.isOn) {
                chips.transition(.opacity)
            }
        }
        .padding(Theme.spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: isOpen)
        // Spec 06: "Person card Edit / Done: height + outline, 240 ms easeOut" (same curve as GroupCard).
        .themeAnimation(Theme.motion.groupCardOpen, value: isOpen)
    }

    private var header: some View {
        HStack(spacing: Theme.spacing.m) {
            Text(PersonSummary.initial(name))
                .font(.custom("Outfit", fixedSize: 20).weight(.bold))
                .foregroundStyle(Theme.color.ink)
                .frame(width: Self.avatarSide, height: Self.avatarSide)
                .background(Circle().fill(Theme.screenTint.avatarTints[max(index, 0) % Theme.screenTint.avatarTints.count]))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).themeText(.personName)
                Text(summary).themeText(.caption).foregroundStyle(Theme.color.mutedGreen)
            }
            .foregroundStyle(Theme.color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenSummary)
            Button(isOpen ? "Done" : "Edit") { isOpen.toggle() }
                .themeText(.callout)
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Theme.color.ink)
                .accessibilityLabel(isOpen ? "Done editing \(name)" : "Edit \(name)")
        }
    }

    /// Closed: "Mia. 2 to avoid: peanut, tree nuts." (spec 06 accessibility).
    private var spokenSummary: String {
        let on = items.filter(\.isOn).map { $0.title.lowercased() }
        return on.isEmpty ? "\(title). \(summary)." : "\(title). \(summary): \(on.joined(separator: ", "))."
    }

    private var chips: some View {
        FlowLayout(spacing: Theme.spacing.xs) {
            ForEach(items.filter(\.isOn)) { item in
                Chip(kind: Chip.Kind(item.kind), iconKey: item.iconKey, text: item.title)
            }
        }
        .accessibilityHidden(true) // The header's summary already names every item.
    }

    private var openRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach($items) { $item in
                Divider().overlay(Theme.color.ink.opacity(0.08))
                HStack(spacing: Theme.spacing.s) {
                    IconView(key: item.iconKey, size: Self.itemIconSide, decorative: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title).themeText(.bodyStrong)
                        Text(item.detail).themeText(.footnote).foregroundStyle(Theme.color.mutedGreen)
                    }
                    .foregroundStyle(Theme.color.ink)
                    .strikethrough(!item.isOn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    KindBadge(ruleName: item.title, kind: $item.kind)
                        .opacity(item.isOn ? 1 : 0.4)
                    Toggle(item.title, isOn: $item.isOn)
                        .labelsHidden()
                        .tint(Theme.color.brandGreen)
                }
                .frame(minHeight: 60)
            }
            Divider().overlay(Theme.color.ink.opacity(0.08))
            Button(action: addByChat) {
                Label("Add an allergy by telling \(Brand.mascot)", systemImage: "plus")
                    .themeText(.bodyStrong)
                    .foregroundStyle(Theme.color.brandGreenDeep)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
            .buttonStyle(.pressable)
            Text("Avoid hides it. Prefer not only shows it lower. Tap to switch.")
                .themeText(.footnote)
                .foregroundStyle(Theme.color.mutedGreen)
        }
    }
}

private extension Chip.Kind {
    init(_ kind: KindBadge.Kind) {
        switch kind {
        case .avoid: self = .avoid
        case .preferNot: self = .preferNot
        case .diet, .goal: self = .dietGoal
        }
    }
}

/// Lays chips out left to right and wraps them onto new lines (prototype `flex-wrap: wrap`).
// Custom: SwiftUI has no wrapping stack.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            let needed = row.indices.isEmpty ? itemWidth : row.width + spacing + itemWidth
            if needed > width + 0.5, !row.indices.isEmpty { // 0.5: pixel rounding of the bounds
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? itemWidth : row.width + spacing + itemWidth
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

#if DEBUG
enum PersonCardSamples {
    /// From `Profile.dc.html` and `sample-household.json`.
    static let alex: [PersonItem] = [
        PersonItem(id: "seed", iconKey: "seed", title: "Seed oils", detail: "Sunflower, canola, soybean and similar", kind: .avoid),
        PersonItem(id: "sugar", iconKey: "sugar", title: "Added sugar", detail: "More than 2 g a serving", kind: .preferNot),
        PersonItem(id: "gluten", iconKey: "gluten", title: "Gluten", detail: "Wheat, barley, rye", kind: .avoid),
    ]
    static let mia: [PersonItem] = [
        PersonItem(id: "peanut", iconKey: "peanut", title: "Peanut", detail: "Allergy \u{00B7} \u{201C}may contain\u{201D} too", kind: .avoid),
        PersonItem(id: "treenuts", iconKey: "treenuts", title: "Tree nuts",
                   detail: "Allergy \u{00B7} almond, cashew, walnut and the rest", kind: .avoid),
    ]
}

#Preview("PersonCard - closed and open") {
    @Previewable @State var alex = PersonCardSamples.alex
    @Previewable @State var mia = PersonCardSamples.mia
    @Previewable @State var alexOpen = false
    @Previewable @State var miaOpen = true
    ScrollView {
        VStack(spacing: Theme.spacing.m) {
            PersonCard(name: "Alex", isOwner: true, index: 0, items: $alex, isOpen: $alexOpen)
            PersonCard(name: "Mia", index: 1, items: $mia, isOpen: $miaOpen)
            PersonCard(name: "Sam", index: 2, items: .constant([]), isOpen: .constant(false))
        }
        .padding(Theme.spacing.l)
    }
    .background(Theme.screenTint.family)
}
#endif
