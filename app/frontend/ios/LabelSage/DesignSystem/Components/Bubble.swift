import SwiftUI

/// A chat bubble (00-foundations `Bubble`). Content layer: no glass.
/// - `.mascot`: LabelSage's line, white (red tint on a guard verdict), radius 18, a tail toward him on
///   the leading side, an optional muted sub-line (board 10 dock: "For you and Mia"). One idea,
///   at most 20 words (voice-and-strings.md). VoiceOver reads "LabelSage: …" and, since his bubble
///   is the screen's first element, it sorts first.
/// - `.user`: the person's message, brand green with white text, right-aligned, the tail corner
///   squared (prototype `Chat.dc.html` `me`: `border-radius: 20px 20px 6px 20px; background: #26834e`).
// Custom: SwiftUI has no chat bubble (native-components.md, "User bubble").
struct Bubble: View {
    enum Speaker {
        case mascot
        case user
    }

    let speaker: Speaker
    let text: String
    /// A second, muted line under his text ("For you and Mia", "Check the package. Not medical advice.").
    var detail: String? = nil
    /// A guard verdict: the bubble takes the red tint (prototype `bubble` with `guard`).
    var isGuard = false

    /// Prototype `bubble`: radius 18 for his bubble; 20/6 for the user's.
    private static let mascotRadius: CGFloat = 18
    private static let userRadius: CGFloat = 20
    private static let userTailRadius: CGFloat = 6
    /// Prototype tail: a 13 pt square turned 45°, 16 pt above the bubble's bottom.
    private static let tailSide: CGFloat = 13
    private static let tailBottom: CGFloat = 16
    /// Prototype `max-width: 80%` of the 390 pt thread, as a leading gap.
    private static let userLeadingGap: CGFloat = 64

    var body: some View {
        switch speaker {
        case .mascot: mascotBubble
        case .user: userBubble
        }
    }

    private var mascotBubble: some View {
        let shape = RoundedRectangle(cornerRadius: Self.mascotRadius, style: .continuous)
        let edge = isGuard ? Theme.color.bubbleGuardEdge : Theme.color.bubbleEdge
        let fill = isGuard ? Theme.color.bubbleGuard : Theme.color.surface
        return VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .themeText(.mascotBubble)
                .foregroundStyle(Theme.color.ink)
            if let detail {
                Text(detail)
                    .themeText(.footnote)
                    .foregroundStyle(Theme.color.muted)
            }
        }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background {
                shape.fill(fill)
                shape.strokeBorder(edge, lineWidth: 1.5)
            }
            .overlay(alignment: .bottomLeading) {
                // The tail: a white square turned 45° over the bubble's edge, outlined on its two
                // outer sides only, so it reads as one shape with the bubble.
                TailEdges()
                    .stroke(edge, lineWidth: 1.5)
                    .background(Rectangle().fill(fill))
                    .frame(width: Self.tailSide, height: Self.tailSide)
                    .rotationEffect(.degrees(45))
                    .offset(x: -Self.tailSide / 2 + 1, y: -Self.tailBottom)
                    .accessibilityHidden(true)
            }
            .padding(.leading, Self.tailSide / 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Brand.mascot): \(text)\(detail.map { ". \($0)" } ?? "")")
            .accessibilitySortPriority(1)
    }

    private var userBubble: some View {
        HStack(spacing: 0) {
            Spacer(minLength: Self.userLeadingGap)
            Text(text)
                .themeText(.userBubble)
                .foregroundStyle(.white)
                .padding(.vertical, 9)
                .padding(.horizontal, 14)
                .background(Theme.color.brandGreen, in: UnevenRoundedRectangle(
                    topLeadingRadius: Self.userRadius, bottomLeadingRadius: Self.userRadius,
                    bottomTrailingRadius: Self.userTailRadius, topTrailingRadius: Self.userRadius,
                    style: .continuous))
                .accessibilityLabel("You: \(text)")
        }
    }
}

/// The tail square's left and bottom sides: after the 45° turn they are the two edges that point
/// toward LabelSage.
private struct TailEdges: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

#Preview("Bubble - mascot and user") {
    VStack(alignment: .leading, spacing: Theme.spacing.l) {
        Bubble(speaker: .mascot, text: "Check a product, or ask me about one.")
        Bubble(speaker: .mascot, text: "Not for Mia. Contains whey: that\u{2019}s milk.",
               detail: "Check the package. Not medical advice.", isGuard: true)
        Bubble(speaker: .mascot, text: "Checking the ingredients\u{2026}", detail: "For you and Mia")
        Bubble(speaker: .mascot,
               text: "Tip: ask me anything, like \u{201C}is this OK for Mia?\u{201D} I answer with a flag and the reason.")
        Bubble(speaker: .user, text: "Is this OK for Mia?")
        Bubble(speaker: .user, text: "Add oat milk without seed oils, the barista one we got last week")
    }
    .padding(Theme.spacing.l)
    .background(Theme.screenTint.chat)
}
