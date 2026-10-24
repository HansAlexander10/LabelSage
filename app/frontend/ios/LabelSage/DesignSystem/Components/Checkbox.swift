import SwiftUI

/// The tick drawn inside `OptionCard`, `OptionTile` and `LeafTile`. Off: white with a 2 pt
/// `controlBorder` edge. On: filled ink with a white check. Drawing only: the card around it is
/// the control and the VoiceOver element, so the checkbox is hidden from VoiceOver.
struct Checkbox: View {
    enum Style {
        /// 30 pt rounded square (radius 9): multiple choice.
        case square
        /// 30 pt circle: single choice.
        case circle
        /// 26 pt rounded square (radius 9) inside a `LeafTile`.
        case leaf
    }

    let isOn: Bool
    var style: Style = .square

    private var side: CGFloat { style == .leaf ? Theme.size.leafCheckbox : Theme.size.checkbox }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: style == .circle ? side / 2 : Theme.radius.checkbox,
            style: style == .circle ? .circular : .continuous
        )
        ZStack {
            if isOn {
                shape.fill(Theme.color.ink)
                Image(systemName: "checkmark")
                    // Prototype: check 15 px in the 30 box, 13 px in the 26 leaf box.
                    .font(.system(size: style == .leaf ? 13 : 15, weight: .bold))
                    .foregroundStyle(Theme.color.surface)
            } else {
                shape.fill(Theme.color.surface)
                shape.strokeBorder(Theme.color.controlBorder, lineWidth: 2)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

#Preview("Checkbox - all") {
    Grid(horizontalSpacing: Theme.spacing.l, verticalSpacing: Theme.spacing.l) {
        GridRow {
            Checkbox(isOn: false, style: .square)
            Checkbox(isOn: false, style: .circle)
            Checkbox(isOn: false, style: .leaf)
        }
        GridRow {
            Checkbox(isOn: true, style: .square)
            Checkbox(isOn: true, style: .circle)
            Checkbox(isOn: true, style: .leaf)
        }
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.color.surface)
}
