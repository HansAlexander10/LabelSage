import SwiftUI

/// A 2-column grid answer for short choices like diet, religion, medical (00-foundations
/// `OptionTile`): centered 64 pt icon, title, optional detail, square checkbox top-right, at
/// least 158 pt tall. Selected swaps the shadow for the 2 pt ink outline. Radius 26 as on board
/// `onboarding/09-diet.png` and the prototype's `tileS` (tokens.json `radius.tile` says 22; see
/// `open-questions.md`). The caller lays tiles out, one column at accessibility text sizes.
struct OptionTile: View {
    let iconKey: String
    let title: String
    var detail: String? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.spacing.xs) {
                IconView(key: iconKey, size: Theme.size.iconInTile, decorative: true)
                Text(title)
                    .themeText(.tileTitle)
                    .foregroundStyle(Theme.color.ink)
                if let detail {
                    Text(detail)
                        .themeText(.footnote)
                        .foregroundStyle(Theme.color.mutedGreen)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, Theme.spacing.xl)
            .padding(.horizontal, Theme.spacing.m)
            .padding(.bottom, Theme.spacing.l)
            .frame(maxWidth: .infinity, minHeight: Theme.size.tileMinHeight)
            .overlay(alignment: .topTrailing) {
                Checkbox(isOn: isOn).padding(Theme.spacing.m)
            }
            .themeCardBackground(cornerRadius: Theme.radius.optionCard, isSelected: isOn)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

#Preview("OptionTile - off and on") {
    Grid(horizontalSpacing: Theme.spacing.m, verticalSpacing: Theme.spacing.m) {
        GridRow {
            OptionTile(iconKey: "vegan", title: "Vegan", detail: "No meat, fish, dairy, eggs, honey", isOn: false) {}
            OptionTile(iconKey: "vegetarian", title: "Vegetarian", detail: "No meat or fish", isOn: true) {}
        }
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.screenTint.diet)
}
