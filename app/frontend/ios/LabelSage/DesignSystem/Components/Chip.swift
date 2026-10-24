import SwiftUI

/// A rule on a compact summary or Family card (00-foundations `Chip`): 22 pt icon and text on a
/// capsule tinted by kind, at least 36 pt tall, one line with tail truncation. The tint is not the
/// only carrier of the kind: VoiceOver reads it ("Peanut, Avoid").
struct Chip: View {
    enum Kind {
        case avoid
        case preferNot
        case dietGoal

        var style: Theme.ChipStyle {
            switch self {
            case .avoid: Theme.chip.avoid
            case .preferNot: Theme.chip.preferNot
            case .dietGoal: Theme.chip.dietGoal
            }
        }

        /// The word VoiceOver adds after the chip's text.
        var spokenKind: String {
            switch self {
            case .avoid: "Avoid"
            case .preferNot: "Prefer not"
            case .dietGoal: "Diet or goal"
            }
        }
    }

    let kind: Kind
    let iconKey: String
    let text: String

    /// Spec: "Height 36". A minimum so the chip grows with Dynamic Type.
    private static let minHeight: CGFloat = 36

    var body: some View {
        HStack(spacing: Theme.spacing.xs) {
            IconView(key: iconKey, size: Theme.size.iconInChip, decorative: true)
            Text(text)
                .themeText(.chip)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(Theme.color.ink)
        .padding(.leading, Theme.spacing.s)
        .padding(.trailing, Theme.spacing.m)
        .frame(minHeight: Self.minHeight)
        .background(Capsule().fill(kind.style.background))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text), \(kind.spokenKind)")
    }
}

#Preview("Chip - kinds") {
    VStack(alignment: .leading, spacing: Theme.spacing.s) {
        Chip(kind: .avoid, iconKey: "peanut", text: "Peanut")
        Chip(kind: .preferNot, iconKey: "sugar", text: "Added sugars")
        Chip(kind: .dietGoal, iconKey: "vegetarian", text: "Vegetarian")
        Chip(kind: .avoid, iconKey: "seed", text: "Seed oils, sunflower, canola and rapeseed")
    }
    .frame(width: 260, alignment: .leading)
    .padding(Theme.spacing.screenGutter)
    .background(Theme.color.surface)
}
