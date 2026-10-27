import SwiftUI

/// The rule kind at the end of a summary or Family row (00-foundations `KindBadge`): Avoid,
/// Prefer not, Diet or Goal on a tinted capsule. Avoid and Prefer not carry a small chevron and
/// flip into each other on tap (D12); Diet and Goal are plain labels. VoiceOver: "Seed oils:
/// always avoided. Double-tap to only show it lower."
struct KindBadge: View {
    nonisolated enum Kind: Equatable, Sendable {
        case avoid
        case preferNot
        case diet
        case goal

        var title: String {
            switch self {
            case .avoid: "Avoid"
            case .preferNot: "Prefer not"
            case .diet: "Diet"
            case .goal: "Goal"
            }
        }

        var isFlippable: Bool { self == .avoid || self == .preferNot }

        /// Avoid ↔ Prefer not; Diet and Goal stay as they are.
        var flipped: Kind {
            switch self {
            case .avoid: .preferNot
            case .preferNot: .avoid
            case .diet, .goal: self
            }
        }

        var style: Theme.ChipStyle {
            switch self {
            case .avoid: Theme.chip.avoid
            case .preferNot: Theme.chip.preferNot
            case .diet, .goal: Theme.chip.dietGoal
            }
        }
    }

    /// The rule the badge belongs to, for VoiceOver: "Seed oils".
    let ruleName: String
    @Binding var kind: Kind

    /// Prototype `badgeS`: `min-height: 32px`.
    private static let minHeight: CGFloat = 32

    var body: some View {
        if kind.isFlippable {
            Button {
                kind = kind.flipped
            } label: {
                HStack(spacing: Theme.spacing.xxs) {
                    Text(kind.title)
                    Image(systemName: "chevron.down").imageScale(.small)
                }
                .modifier(BadgeChrome(kind: kind, minHeight: Self.minHeight))
                // 44 pt tap target around the 32 pt capsule.
                .contentShape(.interaction, Capsule().inset(by: -(Theme.size.minTap - Self.minHeight) / 2))
            }
            .buttonStyle(.pressable)
            .sensoryFeedback(.selection, trigger: kind)
            .accessibilityLabel(kind == .avoid ? "\(ruleName): always avoided" : "\(ruleName): shown lower")
            .accessibilityHint(kind == .avoid ? "Double-tap to only show it lower." : "Double-tap to always avoid it.")
            .accessibilityInputLabels([kind.title, ruleName])
        } else {
            Text(kind.title)
                .modifier(BadgeChrome(kind: kind, minHeight: Self.minHeight))
                .accessibilityLabel("\(ruleName): \(kind.title)")
        }
    }
}

private struct BadgeChrome: ViewModifier {
    let kind: KindBadge.Kind
    let minHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .themeText(.badge)
            .lineLimit(1)
            .foregroundStyle(Theme.color.ink)
            .padding(.horizontal, Theme.spacing.m)
            .frame(minHeight: minHeight)
            .background(Capsule().fill(kind.style.badge))
    }
}

#Preview("KindBadge - all kinds") {
    @Previewable @State var seedOils = KindBadge.Kind.avoid
    @Previewable @State var sugar = KindBadge.Kind.preferNot
    VStack(alignment: .trailing, spacing: Theme.spacing.m) {
        KindBadge(ruleName: "Seed oils", kind: $seedOils)
        KindBadge(ruleName: "Added sugars", kind: $sugar)
        KindBadge(ruleName: "Vegetarian", kind: .constant(.diet))
        KindBadge(ruleName: "Protein", kind: .constant(.goal))
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.color.surface)
}
