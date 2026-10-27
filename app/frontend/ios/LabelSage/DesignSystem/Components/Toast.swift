import SwiftUI

/// One toast to show: "Saved to go-tos" with "View", "Removed from go-tos" with "Undo".
struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    /// "Undo", "View"; `nil` for an info toast.
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
}

/// The toast itself (00-foundations `Toast`): dark, white text, an optional action on a white
/// capsule. Use `.toast(_:)` to show one; it handles placement, the 4 s timer and swipe down.
// Custom: iOS has no toast component (native-components.md, "Toast").
struct Toast: View {
    let message: ToastMessage
    /// Runs after the action, or when the toast is dismissed by a swipe.
    let dismiss: () -> Void

    /// Prototype `Main.dc.html`: `border-radius: 18px`.
    private static let cornerRadius: CGFloat = 18

    var body: some View {
        HStack(spacing: Theme.spacing.m) {
            Text(message.text)
                .themeText(.callout)
                .foregroundStyle(Theme.color.surface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let title = message.actionTitle {
                Button(title) {
                    message.action?()
                    dismiss()
                }
                .themeText(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.color.brandGreenDeep)
                .padding(.horizontal, Theme.spacing.m)
                .frame(minHeight: 32)
                .background(Capsule().fill(Theme.color.surface))
                .contentShape(.interaction, Rectangle().inset(by: -6)) // 44 pt tap height
                .buttonStyle(.pressable)
            }
        }
        .padding(.vertical, Theme.spacing.m)
        .padding(.horizontal, 14)
        // Spec #232323; the nearest token is ink (#1d2b22). Open question Q17.
        .background(Theme.color.ink, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Places a `Toast` at the bottom, slides it in, dismisses it after 4 s or on a swipe down, and
/// announces it to VoiceOver. With VoiceOver on, a toast that has an action stays until it is used
/// or swiped away, so there is time to reach the button.
private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Spec: "4 s".
    private static let duration: Duration = .seconds(4)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                // The animation lives on this container only, so the host screen never animates.
                VStack {
                    if let current = message {
                        Toast(message: current) { message = nil }
                            .padding(.horizontal, Theme.spacing.l)
                            .padding(.bottom, Theme.spacing.s)
                            .gesture(DragGesture(minimumDistance: 10).onEnded { drag in
                                if drag.translation.height > 20 { message = nil }
                            })
                            .accessibilityAction(named: "Dismiss") { message = nil }
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                            .id(current.id)
                    }
                }
                .themeAnimation(Theme.motion.easeOut(duration: 0.28), value: message?.id)
            }
            .task(id: message?.id) {
                guard let current = message else { return }
                AccessibilityNotification.Announcement(current.text).post()
                if voiceOverEnabled && current.actionTitle != nil { return }
                do { try await Task.sleep(for: Self.duration) } catch { return } // cancelled: a newer toast owns it
                if message?.id == current.id { message = nil }
            }
    }
}

extension View {
    /// Shows `message` as a toast at the bottom of this view; sets it back to `nil` when it goes.
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

#Preview("Toast - info and action") {
    VStack(spacing: Theme.spacing.m) {
        Toast(message: ToastMessage(text: "Saved to go-tos")) {}
        Toast(message: ToastMessage(text: "Removed from go-tos", actionTitle: "Undo")) {}
        Toast(message: ToastMessage(text: "Saved: Mia avoids sesame, allergy (\u{201C}may contain\u{201D} too).",
                                    actionTitle: "Undo")) {}
    }
    .padding(Theme.spacing.l)
    .background(Theme.screenTint.product)
}

#Preview("Toast - live (4 s, swipe down)") {
    @Previewable @State var message: ToastMessage?
    VStack(spacing: Theme.spacing.m) {
        Button("Show info toast") { message = ToastMessage(text: "Saved to go-tos", actionTitle: "View") }
        Button("Show undo toast") { message = ToastMessage(text: "Removed from go-tos", actionTitle: "Undo") }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.screenTint.product)
    .toast($message)
}
