import SwiftUI

/// A floating 44 pt Liquid Glass circle with one SF Symbol (00-foundations `GlassButton`): back,
/// favorite, close, new chat. Glass goes only on floating controls, never on content cards
/// (tokens.json `materials.glass`). Group neighbours in a `GlassEffectContainer`.
struct GlassButton: View {
    let systemImage: String
    /// VoiceOver label, e.g. "Back".
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.color.ink)
                .frame(width: Theme.size.minTap, height: Theme.size.minTap)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
        // Fixed size like system bar buttons; Large Content Viewer shows it big at AX sizes.
        .accessibilityShowsLargeContentViewer()
    }
}

#Preview("GlassButton") {
    GlassEffectContainer(spacing: Theme.spacing.m) {
        HStack(spacing: Theme.spacing.m) {
            GlassButton(systemImage: "chevron.left", label: "Back") {}
            GlassButton(systemImage: "heart", label: "Add to go-tos") {}
            GlassButton(systemImage: "xmark", label: "Close") {}
            GlassButton(systemImage: "square.and.pencil", label: "New chat") {}
        }
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.screenTint.allergens)
}
