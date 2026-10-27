import SwiftUI

/// A full-width onboarding answer (00-foundations `OptionCard`): 3D icon, title, optional detail,
/// and a checkbox (square for multi, circle for single). White, radius 26, at least 80 pt tall;
/// selected swaps the shadow for a 2 pt ink outline. The whole card is one button and one
/// VoiceOver element ("Allergies and ingredients, Allergies, diets and anything you avoid.
/// Selected."). The caller owns the state and flips it in `action`.
struct OptionCard: View {
    enum Mode {
        case single
        case multi
    }

    let iconKey: String
    let title: String
    var detail: String? = nil
    let mode: Mode
    let isOn: Bool
    let action: () -> Void

    /// Counts the user's own taps, for the haptic (see `selectableCard`).
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: Theme.spacing.l) {
                IconView(key: iconKey, size: Theme.size.iconInCard, decorative: true)
                VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                    Text(title)
                        .themeText(.optionTitle)
                        .foregroundStyle(Theme.color.ink)
                    if let detail {
                        Text(detail)
                            .themeText(.caption)
                            .foregroundStyle(Theme.color.mutedGreen)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Checkbox(isOn: isOn, style: mode == .multi ? .square : .circle)
            }
            .padding(.vertical, Theme.spacing.cardPaddingV)
            .padding(.horizontal, Theme.spacing.cardPaddingH)
            .frame(maxWidth: .infinity, minHeight: Theme.size.optionCardMinHeight)
            .themeCardBackground(cornerRadius: Theme.radius.optionCard, isSelected: isOn)
        }
        .selectableCard(isOn: isOn, taps: taps)
    }
}

#Preview("OptionCard - multi off and on") {
    VStack(spacing: Theme.spacing.m) {
        OptionCard(iconKey: "notfor", title: "Allergies and ingredients",
                   detail: "Allergies, diets and anything you avoid", mode: .multi, isOn: true) {}
        OptionCard(iconKey: "macros", title: "Macros and calories",
                   detail: "Protein and calories for a goal", mode: .multi, isOn: false) {}
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.screenTint.goal)
}

#Preview("OptionCard - single off and on") {
    VStack(spacing: Theme.spacing.m) {
        OptionCard(iconKey: "me", title: "Just me",
                   detail: "Just my allergies and diets", mode: .single, isOn: false) {}
        OptionCard(iconKey: "family", title: "My family",
                   detail: "Everyone at home, one at a time", mode: .single, isOn: true) {}
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.screenTint.household)
}

#Preview("OptionCard - no detail") {
    OptionCard(iconKey: "peanut", title: "Peanuts", mode: .multi, isOn: false) {}
        .padding(Theme.spacing.screenGutter)
        .background(Theme.screenTint.allergens)
}
