import SwiftUI
import TipKit

// Explainers on chat home (board 10 and 63, `Chat.dc.html`, `ExplainerStates.dc.html`): a welcome
// sheet, then "Start here" said by LabelSage in the dock with the hero ringed (board 10 `first`),
// then one inline tip the dock bubble says once. No popovers: one mascot, and his bubble talks.

/// The inline tip the dock says once, after the tour.
struct DockTip: Tip {
    /// Set when "Start here" is done or skipped, so the inline tip follows it, never overlaps it.
    @Parameter static var tourDone: Bool = false

    /// The words for the dock bubble (one mascot: the bubble shows them, not a `TipView`).
    static func line(forName name: String) -> String {
        "Tip: ask me anything, like “is this OK for \(name)?” I answer with a flag and the reason."
    }

    var title: Text { Text("Ask me anything") }
    var rules: [Rule] { [#Rule(Self.$tourDone) { $0 == true }] }
    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Step 1: LabelSage says hello in a short sheet. He moves from the dock into the sheet.
struct ChatWelcomeSheet: View {
    let onShowMe: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: Theme.spacing.l) {
            HStack(alignment: .center, spacing: Theme.spacing.m) {
                MascotView(state: .wave, size: Theme.size.mascotOnboarding, host: .sheet)
                VStack(alignment: .leading, spacing: Theme.spacing.xs) {
                    Text("Hi, I’m \(Brand.mascot)")
                        .themeText(.sectionTitle)
                        .foregroundStyle(Theme.color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("I read the ingredients so you don’t have to, for everyone you shop for.")
                        .themeText(.body)
                        .foregroundStyle(Theme.color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            PrimaryButton(title: "Show me how", showsChevron: false, action: onShowMe)
            Button("Skip", action: onSkip)
                .themeText(.bodyStrong)
                .foregroundStyle(Theme.color.ink)
                .frame(minHeight: Theme.size.minTap)
                .accessibilityLabel("Skip the tour")
        }
        .padding(.horizontal, Theme.spacing.screenGutter)
        .padding(.top, Theme.spacing.xxl)
        .presentationDetents([.height(320), .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.color.surface)
    }
}

#Preview("Welcome sheet") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ChatWelcomeSheet(onShowMe: {}, onSkip: {})
    }
}
