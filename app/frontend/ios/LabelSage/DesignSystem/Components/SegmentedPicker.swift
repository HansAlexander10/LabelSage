import SwiftUI

/// Two options on clear Liquid Glass over the camera (00-foundations `SegmentedPicker`, spec 03):
/// "Barcode | Ingredients". The system segmented control, unchanged, in dark mode on a glass
/// capsule, with a selection haptic (native-components.md, "Segmented picker over the camera").
/// The system control keeps its own font: restyling it would mean UIKit appearance proxies.
/// Inside content (per serving | per 100 g, Differences | Everything) use a plain
/// `Picker(.segmented)` without glass, since glass is for floating controls only.
struct SegmentedPicker<Value: Hashable>: View {
    /// VoiceOver label for the control: "Mode".
    let label: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.title).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(Theme.spacing.xxs)
        .glassEffect(.clear, in: .capsule)
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

#Preview("SegmentedPicker - over the camera") {
    @Previewable @State var mode = "barcode"
    ZStack(alignment: .bottom) {
        // Stand-in for the live camera feed.
        LinearGradient(colors: [Theme.color.ink, Theme.color.muted, Theme.color.ink],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        SegmentedPicker(label: "Mode",
                        options: [("barcode", "Barcode"), ("ingredients", "Ingredients")],
                        selection: $mode)
            .padding(.bottom, 80)
    }
}
