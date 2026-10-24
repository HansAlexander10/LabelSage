import SwiftUI

nonisolated extension Theme {
    /// Motion curves from tokens.json `motion`, as SwiftUI `Animation` values.
    enum motion {
        /// tokens.json motion.easeOut: `cubic-bezier(0.23, 1, 0.32, 1)`.
        static func easeOut(duration: Double) -> Animation {
            .timingCurve(0.23, 1, 0.32, 1, duration: duration)
        }

        /// tokens.json motion.easeInOut: `cubic-bezier(0.77, 0, 0.175, 1)`.
        static func easeInOut(duration: Double) -> Animation {
            .timingCurve(0.77, 0, 0.175, 1, duration: duration)
        }

        // Named presets from the "Animation / Motion" table in
        // docs/specs/00-foundations.md, all built on the two curves above.

        /// Card press: scale 0.98, 120 ms, `easeOut`. Also stands in for tokens.json's generic
        /// `motion.press` ("100 to 160 ms"): every press in the MVP is a card press, so there is
        /// no second preset to keep.
        static let cardPress = easeOut(duration: 0.12)
        /// Onboarding step continue/back: content slides and fades, 280 ms, `easeOut`.
        static let onboardingStep = easeOut(duration: 0.28)
        /// Group card open: leaves fade in, card height animates, 240 ms, `easeOut`.
        static let groupCardOpen = easeOut(duration: 0.24)
        /// Progress dot color crossfade on section change, 200 ms, ease.
        static let progressDotCrossfade = easeInOut(duration: 0.2)
        /// Reason line opacity crossfade when the on-device summary replaces the deterministic
        /// reason, 200 ms. tokens.json motion.reasonSwap: "no skeleton, no shimmer".
        static let reasonCrossfade = easeInOut(duration: 0.2)
        /// Mascot pose change: crossfade between poses, 150 ms.
        static let mascotPoseCrossfade = easeInOut(duration: 0.15)

        /// tokens.json motion.reduceMotion: "Mascot holds its pose; transitions become fades."
        /// Returns `animation` unchanged, unless Reduce Motion is on, in which case it returns a
        /// short plain fade — pair it with an opacity-only transition instead of a slide, and skip
        /// the mascot pose change entirely at the call site. Prefer `View.themeAnimation(_:value:)`
        /// below over calling this directly; it reads the environment for you.
        static func reduceMotionAware(_ animation: Animation, reduceMotion: Bool, fadeDuration: Double = 0.2) -> Animation {
            reduceMotion ? easeInOut(duration: fadeDuration) : animation
        }
    }
}

/// Applies `animation`, substituting `Theme.motion.reduceMotionAware`'s short fade when the
/// viewer has Reduce Motion on — the `.animation(_:value:)` call site doesn't need to read
/// `accessibilityReduceMotion` itself.
private struct ThemeAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(Theme.motion.reduceMotionAware(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// Reduce-Motion-aware `.animation(_:value:)`: plays `animation` normally, or a short plain
    /// fade when the viewer has Reduce Motion on.
    func themeAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(ThemeAnimationModifier(animation: animation, value: value))
    }
}
