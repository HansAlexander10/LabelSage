import SwiftUI

/// Press feedback for every card, tile and button (00-foundations "Any card or tile: Pressed"):
/// scale 0.98 on touch down over `Theme.motion.cardPress` (120 ms ease-out), springs back on
/// release, no color change. With Reduce Motion on nothing scales (the prototype's
/// `prefers-reduced-motion` rule sets `transform: none`).
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration)
    }
}

private struct PressableBody: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let configuration: ButtonStyleConfiguration

    /// tokens.json has no release curve; the spec only says "release springs back".
    private static let release = Animation.spring(duration: 0.3, bounce: 0.3)

    var body: some View {
        // The animation covers only the scale, so a label change (isOn, the loading spinner)
        // never picks up the press curve.
        configuration.label
            .contentShape(.rect)
            .animation(configuration.isPressed ? Theme.motion.cardPress : Self.release) {
                $0.scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            }
    }
}

extension ButtonStyle where Self == PressableStyle {
    /// `.buttonStyle(.pressable)`: see `PressableStyle`.
    static var pressable: PressableStyle { PressableStyle() }
}

extension View {
    /// The shared tail of `OptionCard`, `OptionTile` and `LeafTile`: press feedback, the
    /// Selected trait, and a `.selection` haptic on `taps`, which the card bumps in its own
    /// button action. Keyed on taps rather than `isOn`, so only the user's own tap buzzes, not
    /// every leaf that "All tree nuts" switches on, nor the card a single choice switches off.
    func selectableCard(isOn: Bool, taps: Int) -> some View {
        buttonStyle(.pressable)
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .sensoryFeedback(.selection, trigger: taps)
    }
}

#Preview("PressableStyle") {
    Button {} label: {
        Text("Press and hold")
            .themeText(.cardTitle)
            .foregroundStyle(Theme.color.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.size.optionCardMinHeight)
            .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
    }
    .buttonStyle(.pressable)
    .padding(Theme.spacing.screenGutter)
    .background(Theme.screenTint.goal)
}
