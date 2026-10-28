import SwiftUI
import LabelSageCore

/// The verdict at the top of "For you" (00-foundations `VerdictBanner`, spec 04, prototype
/// `Main.dc.html`): a white card whose top is the level's wash, with the level's symbol, the title
/// ("Not for you", or the person line with more than one person) and the reason. When the on-device
/// summary replaces the reason, the reason crossfades (200 ms, `Theme.motion.reasonCrossfade`).
// Custom: a plain VStack card; SwiftUI has no verdict banner (native-components.md, "Verdict banner").
struct VerdictBanner: View {
    let level: Level
    /// "Not for you", "OK for you and Mia", "Not for you · OK for Mia".
    let title: String
    /// The engine's reason, later the model's rewrite of it. Never changes the level.
    let reason: String

    private var style: Theme.VerdictStyle { Theme.verdict.style(for: level) }
    /// Prototype: 28 pt symbol.
    private static let symbolSize: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing.m) {
            Image(systemName: style.symbol)
                .font(.system(size: Self.symbolSize, weight: .semibold))
                .foregroundStyle(style.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                Text(title)
                    .themeText(.bodyStrong)
                    .foregroundStyle(Theme.color.ink)
                Text(reason)
                    .themeText(.callout)
                    .foregroundStyle(Theme.color.inkSecondary)
                    .contentTransition(.opacity)
                    .themeAnimation(Theme.motion.reasonCrossfade, value: reason)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.spacing.cardPaddingV)
        .padding(.horizontal, Theme.spacing.l)
        .background(style.wash)
        .clipShape(.rect(cornerRadius: Theme.radius.card, style: .continuous))
        .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verdict: \(title). \(reason)")
    }
}

#Preview("VerdictBanner - 4 levels") {
    ScrollView {
        VStack(spacing: Theme.spacing.m) {
            VerdictBanner(level: .notFor, title: "Not for you",
                          reason: "Sunflower oil is the 2nd ingredient, so it\u{2019}s not for you. Watch 4 g added sugar per serving.")
            VerdictBanner(level: .checkFirst, title: "Check first",
                          reason: "Cane sugar is the 3rd ingredient.")
            VerdictBanner(level: .ok, title: "OK for you and Mia",
                          reason: "Nothing you or Mia avoid is in these ingredients.")
            VerdictBanner(level: .cantConfirm, title: "Can\u{2019}t confirm",
                          reason: "\u{2018}Natural flavors\u{2019} isn\u{2019}t specific.")
        }
        .padding(Theme.spacing.screenGutter)
    }
    .background(Theme.screenTint.product)
}

#Preview("VerdictBanner - reason crossfade") {
    @Previewable @State var summarized = false
    VStack(spacing: Theme.spacing.l) {
        VerdictBanner(level: .notFor, title: "Not for you \u{00B7} OK for Mia",
                      reason: summarized
                        ? "Sunflower oil is a seed oil you avoid. Mia\u{2019}s peanut and tree nuts are not in it."
                        : "Sunflower oil is the 2nd ingredient, so it\u{2019}s not for you.")
        Button("Swap the reason") { summarized.toggle() }
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.screenTint.product)
}
