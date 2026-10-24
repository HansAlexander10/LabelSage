import SwiftUI

/// A section heading such as "For you", "Other options for you", "Key ingredients", "Settings":
/// `type.sectionTitle` (22/700) in ink, leading, marked as a header for VoiceOver rotor
/// navigation. The 30 pt LabelSage at its right edge on the product page arrives with the mascot
/// task, not here.
struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .themeText(.sectionTitle)
            .foregroundStyle(Theme.color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("SectionHeader") {
    VStack(spacing: Theme.spacing.l) {
        SectionHeader("For you")
        SectionHeader("Other options for you")
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.screenTint.product)
}
