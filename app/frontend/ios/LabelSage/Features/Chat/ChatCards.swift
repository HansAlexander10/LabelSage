import SwiftUI
import LabelSageCore

// The answer cards in the thread (spec 02 › Components). Content layer: white cards, no glass.

/// A white card with the chat's radius.
private struct ChatCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
    }
}

extension View {
    fileprivate func chatCard() -> some View { modifier(ChatCardBackground()) }
}

/// `ProductResultCard`: the full product row (board 65) with the verdict line, the reason chips and
/// the nutrition line. The whole card is the tap target and opens the product page.
struct ProductResultCard: View {
    let answer: ProductAnswer
    let onOpen: () -> Void

    var body: some View {
        ProductSummaryCard(product: answer.product, verdict: answer.verdict, action: onOpen)
    }
}

/// "Which one?" for an ambiguous name: the same full product rows; a tap picks that product.
struct ChoicesCard: View {
    let answers: [ProductAnswer]
    let onPick: (Product) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            Text("Which one?")
                .themeText(.cardTitle)
                .foregroundStyle(Theme.color.ink)
                .padding(.leading, Theme.spacing.xxs)
                .accessibilityAddTraits(.isHeader)
            ForEach(answers) { answer in
                ProductSummaryCard(product: answer.product, verdict: answer.verdict, hint: "Checks this one") {
                    onPick(answer.product)
                }
            }
        }
    }
}

/// `OptionsResult`: a carousel of product tiles (board 65), then Compare both, More options and Check another.
struct OptionsResultCard: View {
    let anchor: Product?
    let answers: [ProductAnswer]
    let onOpen: (Product) -> Void
    let onCompare: (Product, Product) -> Void
    let onMore: () -> Void
    let onCheckAnother: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// "Compare both": the product these replace and the first option, else the first two options.
    private var comparePair: (Product, Product)? {
        if let anchor, let first = answers.first { return (anchor, first.product) }
        if answers.count >= 2 { return (answers[0].product, answers[1].product) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            ProductTileCarousel(items: answers, horizontalPadding: 0) { answer in
                ProductTile(product: answer.product, verdict: answer.verdict) { onOpen(answer.product) }
            }
            .scrollClipDisabled()

            let buttons = Group {
                if let pair = comparePair {
                    chatButton("Compare both", systemImage: "arrow.left.arrow.right") { onCompare(pair.0, pair.1) }
                }
                chatButton("More options", systemImage: "sparkles", action: onMore)
                chatButton("Check another", systemImage: "barcode.viewfinder", action: onCheckAnother)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.spacing.s) { buttons }
            } else {
                ViewThatFits {
                    HStack(spacing: Theme.spacing.s) { buttons }
                    VStack(alignment: .leading, spacing: Theme.spacing.s) { buttons }
                }
            }
        }
    }
}

/// A content-layer pill under a card (white, ink, no glass).
func chatButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Label(title, systemImage: systemImage)
            .themeText(.chip)
            .foregroundStyle(Theme.color.ink)
            .padding(.horizontal, Theme.spacing.m)
            .frame(minHeight: Theme.size.minTap)
            .background(Theme.color.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.color.controlBorder))
    }
    .buttonStyle(PressableStyle())
}

/// `ChangeCard`: the exact change for one person; Cancel and Confirm change. Saved and cancelled
/// cards stay in the thread, read-only.
struct ChangeCard: View {
    let proposal: ChangeProposal
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var who: String { proposal.personName == "you" ? "You" : proposal.personName }
    private var avoidsLine: String {
        let verb = proposal.personName == "you" ? "avoid" : "avoids"
        let items = proposal.state == .saved ? proposal.currentItems + [proposal.label] : proposal.currentItems
        return items.isEmpty ? "" : "\(who) \(verb): \(items.formatted(.list(type: .and)))"
    }
    private var whose: String { proposal.personName == "you" ? "your" : "\(proposal.personName)’s" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            HStack {
                Text("\(who) · 1 change \(status)")
                    .themeText(.cardTitle)
                    .foregroundStyle(Theme.color.ink)
                Spacer()
            }
            Chip(kind: .avoid, iconKey: proposal.familyID ?? "allergy", text: proposal.label.capitalizedFirst)
            if !avoidsLine.isEmpty {
                Text(avoidsLine)
                    .themeText(.callout)
                    .foregroundStyle(Theme.color.inkSecondary)
            }
            if proposal.isAllergen {
                Text("I avoid it, and “may contain \(proposal.label)” too.")
                    .themeText(.footnote)
                    .foregroundStyle(Theme.color.muted)
            } else if proposal.familyID == nil {
                Text("I’ll flag “\(proposal.label)” in ingredient lists.")
                    .themeText(.footnote)
                    .foregroundStyle(Theme.color.muted)
            }
            switch proposal.state {
            case .proposed:
                Text("After you confirm, I re-check \(whose) go-tos.")
                    .themeText(.footnote)
                    .foregroundStyle(Theme.color.muted)
                HStack(spacing: Theme.spacing.s) {
                    Button("Cancel", action: onCancel)
                        .themeText(.bodyStrong)
                        .foregroundStyle(Theme.color.ink)
                        .frame(maxWidth: .infinity, minHeight: Theme.size.minTap)
                        .background(Theme.color.surface, in: .capsule)
                        .overlay(Capsule().strokeBorder(Theme.color.controlBorder))
                        .buttonStyle(PressableStyle())
                    Button("Confirm change", action: onConfirm)
                        .themeText(.bodyStrong)
                        .foregroundStyle(Theme.color.ink)
                        .frame(maxWidth: .infinity, minHeight: Theme.size.minTap)
                        .background(Theme.color.amber, in: .capsule)
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("chat.confirmChange")
                }
            case .saved:
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .themeText(.callout)
                    .foregroundStyle(Theme.color.brandGreen)
            case .cancelled, .undone:
                Text("No changes made.")
                    .themeText(.callout)
                    .foregroundStyle(Theme.color.muted)
            }
        }
        .chatCard()
        .animation(.easeInOut(duration: 0.2), value: proposal)
    }

    private var status: String {
        switch proposal.state {
        case .proposed: "to confirm"
        case .saved: "saved"
        case .cancelled, .undone: "not made"
        }
    }
}

/// The inline person picker from the "Change allergies" tile.
