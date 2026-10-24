import SwiftUI

/// The screen's one amber button (00-foundations `PrimaryButton`): capsule, at least 66 pt tall,
/// amber with an ink label and the amber glow, optional leading SF Symbol and trailing chevron.
/// - `.disabled(hint:)`: `amberDisabled` with the `amberDisabledText` label and no glow; still
///   focusable, VoiceOver says "dimmed" and reads `hint` ("Pick at least one").
/// - `.loading`: the label stays, a small spinner replaces the chevron, taps do nothing.
struct PrimaryButton: View {
    enum Status: Equatable {
        case enabled
        case disabled(hint: String)
        case loading
    }

    let title: String
    var systemImage: String? = nil
    var showsChevron = true
    var status: Status = .enabled
    let action: () -> Void

    private var isDisabled: Bool {
        if case .disabled = status { true } else { false }
    }

    private var ink: Color { isDisabled ? Theme.color.amberDisabledText : Theme.color.ink }

    var body: some View {
        Button {
            if status == .enabled { action() }
        } label: {
            HStack(spacing: Theme.spacing.s) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
                }
                Text(title)
                    .themeText(.primaryButton)
                    .multilineTextAlignment(.center)
                if status == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.color.ink)
                } else if showsChevron {
                    Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, Theme.spacing.xxl)
            .padding(.vertical, Theme.spacing.m)
            .frame(maxWidth: .infinity, minHeight: Theme.size.primaryButtonHeight)
            .background {
                if isDisabled {
                    Capsule().fill(Theme.color.amberDisabled)
                } else {
                    Capsule().fill(Theme.color.amber).themePrimaryGlow()
                }
            }
        }
        .buttonStyle(.pressable)
        .disabled(isDisabled)
        .accessibilityHint(hint)
        .accessibilityValue(status == .loading ? "Loading" : "")
    }

    private var hint: String {
        if case .disabled(let hint) = status { hint } else { "" }
    }
}

#Preview("PrimaryButton - enabled") {
    PrimaryButton(title: "Continue") {}
        .padding(Theme.spacing.screenGutter)
        .background(Theme.screenTint.goal)
}

#Preview("PrimaryButton - disabled") {
    PrimaryButton(title: "Continue", status: .disabled(hint: "Pick at least one")) {}
        .padding(Theme.spacing.screenGutter)
        .background(Theme.screenTint.allergens)
}

#Preview("PrimaryButton - loading") {
    PrimaryButton(title: "Continue", status: .loading) {}
        .padding(Theme.spacing.screenGutter)
        .background(Theme.screenTint.goal)
}

#Preview("PrimaryButton - symbol, no chevron") {
    PrimaryButton(title: "Check a product", systemImage: "barcode.viewfinder", showsChevron: false) {}
        .padding(Theme.spacing.screenGutter)
        .background(Theme.screenTint.chat)
}
