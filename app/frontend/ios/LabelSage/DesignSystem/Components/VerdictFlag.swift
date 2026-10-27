import SwiftUI
import LabelSageCore

/// The verdict flag (00-foundations `VerdictFlag`, board 62): a white circle with a 3 pt ring in the
/// level's color and the level's SF Symbol inside. Color and symbol always travel together, and
/// VoiceOver reads the word: "Verdict: Not for Mia".
///
/// On first show the ring pulses gently twice (2 × 1 s), never with Reduce Motion; a Not for flag
/// also plays one `.warning` haptic. The level always comes from `VerdictEngine`.
// Custom: no system badge carries a level ring (native-components.md, "Verdict flag badge").
struct VerdictFlag: View {
    enum Size: CaseIterable {
        /// 36 pt: rows and small headers.
        case small
        /// 48 pt.
        case medium
        /// 60 pt: the photo signal (`Theme.size.verdictSignal`).
        case large

        var side: CGFloat {
            switch self {
            case .small: 36
            case .medium: 48
            case .large: Theme.size.verdictSignal
            }
        }

        /// Prototype photo signal: a 30 pt symbol in the 48 pt circle (0.625 of the side).
        var symbolSize: CGFloat { (side * 0.625).rounded() }
    }

    let level: Level
    /// Who the verdict is for, for the spoken word: `["Mia"]` reads "Not for Mia".
    var names: [String] = ["you"]
    var size: Size = .medium
    /// Off when another flag on the same screen already buzzes, so a screen plays one haptic.
    var playsHaptic = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flips once, on first appearance; drives the haptic.
    @State private var hasAppeared = false
    /// Set once on first appearance, only without Reduce Motion; drives the pulse.
    @State private var pulses = 0

    private var style: Theme.VerdictStyle { Theme.verdict.style(for: level) }
    /// 3 pt ring (00-foundations).
    private static let ringWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().fill(Theme.color.surface)
            Circle().strokeBorder(style.color, lineWidth: Self.ringWidth)
            Image(systemName: style.symbol)
                .font(.system(size: size.symbolSize, weight: .semibold))
                .foregroundStyle(style.color)
        }
        .frame(width: size.side, height: size.side)
        .background {
            // The pulse: a copy of the ring that grows and fades, twice.
            Circle()
                .strokeBorder(style.color, lineWidth: Self.ringWidth)
                .keyframeAnimator(initialValue: PulseFrame(), trigger: pulses) { ring, frame in
                    ring.scaleEffect(frame.scale).opacity(frame.opacity)
                } keyframes: { _ in
                    // Two pulses of 1 s each.
                    KeyframeTrack(\.scale) {
                        MoveKeyframe(1)
                        CubicKeyframe(1.25, duration: 1)
                        MoveKeyframe(1)
                        CubicKeyframe(1.25, duration: 1)
                    }
                    KeyframeTrack(\.opacity) {
                        MoveKeyframe(0.6)
                        CubicKeyframe(0, duration: 1)
                        MoveKeyframe(0.6)
                        CubicKeyframe(0, duration: 1)
                    }
                }
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            if !reduceMotion { pulses = 1 }
        }
        .sensoryFeedback(.warning, trigger: hasAppeared) { _, appeared in appeared && playsHaptic && level == .notFor }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(level, names: names))
        .accessibilityAddTraits(.isImage)
    }

    /// "Verdict: Not for Mia".
    nonisolated static func spokenLabel(_ level: Level, names: [String]) -> String {
        "Verdict: \(Copy.flag(level, names: names))"
    }
}

/// One step of the ring pulse. At rest the halo is invisible.
private struct PulseFrame {
    var scale: CGFloat = 1
    var opacity: Double = 0
}

#Preview("VerdictFlag - levels × sizes") {
    Grid(horizontalSpacing: Theme.spacing.l, verticalSpacing: Theme.spacing.l) {
        ForEach(VerdictFlag.Size.allCases, id: \.self) { size in
            GridRow {
                ForEach(Level.allCases, id: \.self) { level in
                    VerdictFlag(level: level, names: ["Mia"], size: size)
                }
            }
        }
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.screenTint.product)
}
