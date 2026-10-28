import SwiftUI

/// The first-run tour of chat home (product owner, 2026-10-27): each key control in turn, one plain
/// line each. It covers the screen so nothing else can be tapped; a tap anywhere goes to the next
/// step, and Skip ends it.
enum ChatTourTarget: Int, CaseIterable, Hashable {
    case account, newChat, scan, voice, field

    var title: String {
        switch self {
        case .account: "Preferences & settings"
        case .newChat: "Start a new chat"
        case .scan: "Scan a barcode in the shop"
        case .voice: "Just say it"
        case .field: "Or type a question"
        }
    }

    func line(example name: String) -> String {
        switch self {
        case .account: "Tap here to change what I check for you and your family."
        case .newChat: "A fresh chat. Your old ones stay in the menu at the top."
        case .scan: "Point the camera at any barcode. I check it for everyone."
        case .voice: "Tap the mic and talk. I send it when you stop."
        case .field: "Like “Is this OK for \(name)?”"
        }
    }
}

/// Where each tour target sits on screen, in global coordinates.
struct ChatTourFrames: Equatable {
    var frames: [ChatTourTarget: CGRect] = [:]
}

extension View {
    /// Reports this view's frame as a tour target. For views in the screen's content (the composer);
    /// the toolbar's two buttons are placed by `ChatTourFrames.toolbarFrame`.
    func tourTarget(_ target: ChatTourTarget, in frames: Binding<ChatTourFrames>) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frames.wrappedValue.frames[target] = $0 }
    }
}

extension ChatTourFrames {
    /// The bar turns toolbar buttons into native items, so SwiftUI can't measure them. On iPhone they
    /// sit 16 pt in from the edges, 44 pt round, centered in the 44 pt row under the status bar.
    static func toolbarFrame(_ target: ChatTourTarget, width: CGFloat) -> CGRect? {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        let top = scene?.keyWindow?.safeAreaInsets.top ?? 62
        let side: CGFloat = 44, inset: CGFloat = 16
        switch target {
        case .account: return CGRect(x: inset, y: top, width: side, height: side)
        case .newChat: return CGRect(x: width - inset - side, y: top, width: side, height: side)
        default: return nil
        }
    }
}

struct ChatTourOverlay: View {
    let step: ChatTourTarget
    let frames: ChatTourFrames
    let exampleName: String
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var number: Int { step.rawValue + 1 }
    private var count: Int { ChatTourTarget.allCases.count }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let measured = ChatTourFrames.toolbarFrame(step, width: proxy.size.width) ?? frames.frames[step]
            let target = measured.map { $0.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -6, dy: -6) }
            ZStack(alignment: .topLeading) {
                // The dim layer with a hole over the target.
                Rectangle()
                    .fill(Color.black.opacity(0.62))
                    .overlay {
                        if let target {
                            RoundedRectangle(cornerRadius: min(target.height, target.width) / 2, style: .continuous)
                                .frame(width: target.width, height: target.height)
                                .position(x: target.midX, y: target.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                if let target {
                    RoundedRectangle(cornerRadius: min(target.height, target.width) / 2, style: .continuous)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: target.width, height: target.height)
                        .position(x: target.midX, y: target.midY)
                }
                callout
                    .frame(maxWidth: min(proxy.size.width - 2 * Theme.spacing.screenGutter, 420))
                    .padding(.horizontal, Theme.spacing.screenGutter)
                    .frame(maxWidth: .infinity)
                    .offset(y: calloutY(target: target, height: proxy.size.height))
            }
            .contentShape(.rect)
            .onTapGesture(perform: onNext)
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: step)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// Below a target in the top half, above one in the bottom half.
    private func calloutY(target: CGRect?, height: CGFloat) -> CGFloat {
        guard let target else { return height / 3 }
        return target.midY < height / 2 ? target.maxY + 16 : max(60, target.minY - 190)
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            Text(step.title)
                .themeText(.sectionTitle)
                .foregroundStyle(Theme.color.ink)
            Text(step.line(example: exampleName))
                .themeText(.body)
                .foregroundStyle(Theme.color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(number) of \(count) · Tap anywhere")
                    .themeText(.footnote)
                    .foregroundStyle(Theme.color.muted)
                Spacer()
                Button("Skip", action: onSkip)
                    .themeText(.bodyStrong)
                    .foregroundStyle(Theme.color.ink)
                    .frame(minWidth: Theme.size.minTap, minHeight: Theme.size.minTap)
                    .accessibilityLabel("Skip the tour")
                    .accessibilityIdentifier("chat.tour.skip")
            }
        }
        .padding(Theme.spacing.l)
        .background(Theme.color.surface, in: .rect(cornerRadius: Theme.radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title). \(step.line(example: exampleName)). Step \(number) of \(count).")
        .accessibilityAction(named: number == count ? "Done" : "Next", onNext)
        .accessibilityAction(named: "Skip the tour", onSkip)
        .accessibilityIdentifier("chat.tour")
    }
}
