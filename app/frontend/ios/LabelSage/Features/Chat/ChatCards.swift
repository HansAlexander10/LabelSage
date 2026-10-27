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

/// "Check the package. Not medical advice." under every verdict.
private struct Disclaimer: View {
    var body: some View {
        Text(VerdictBanner.disclaimer)
            .themeText(.footnote)
            .foregroundStyle(Theme.color.muted)
    }
}

/// Ingredient chips colored by finding ("Sunflower oil" red, "Cane sugar" amber): one per matched word, worst first.
func findingNotes(_ verdict: HouseholdVerdict) -> [ProductRow.Note] {
    var seen = Set<String>()
    return verdict.people.flatMap(\.findings)
        .filter { $0.level != .ok }
        .sorted { $0.level > $1.level }
        .compactMap { finding -> ProductRow.Note? in
            guard let matched = finding.matched, !matched.isEmpty, seen.insert(matched.lowercased()).inserted else { return nil }
            return ProductRow.Note(level: finding.level, text: matched.capitalizedFirst)
        }
}

/// `ProductResultCard`: the product row, the person line and the disclaimer. Tap opens the sheet.
struct ProductResultCard: View {
    let answer: ProductAnswer
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            ProductRow(product: answer.product, level: answer.verdict.overall,
                       names: answer.verdict.people.map(\.name), notes: findingNotes(answer.verdict),
                       style: .row, action: onOpen)
            PersonLine(answer.verdict)
            Disclaimer()
        }
        .chatCard()
        .accessibilityElement(children: .contain)
    }
}

/// "Which one?" for an ambiguous name: compact rows.
struct ChoicesCard: View {
    let answers: [ProductAnswer]
    let onPick: (Product) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            Text("Which one?")
                .themeText(.cardTitle)
                .foregroundStyle(Theme.color.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(answers) { answer in
                ProductRow(product: answer.product, level: answer.verdict.overall,
                           names: answer.verdict.people.map(\.name), style: .compact) { onPick(answer.product) }
            }
        }
        .chatCard()
    }
}

/// `OptionsResult`: up to three cards, then Compare both, More options and Check another.
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
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Theme.spacing.m) {
                    ForEach(answers) { answer in
                        ProductRow(product: answer.product, level: answer.verdict.overall,
                                   names: answer.verdict.people.map(\.name),
                                   notes: [ProductRow.Note(level: answer.verdict.overall, text: answer.verdict.line)],
                                   style: .card) { onOpen(answer.product) }
                    }
                }
                .padding(.vertical, Theme.spacing.xs)
            }
            .scrollIndicators(.hidden)
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
            Disclaimer()
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
    let onSeverity: (Severity) -> Void
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var who: String { proposal.personName == "you" ? "You" : proposal.personName }
    private var avoidsLine: String {
        let verb = proposal.personName == "you" ? "avoid" : "avoids"
        let items = proposal.state == .saved ? proposal.currentItems + [proposal.label] : proposal.currentItems
        return items.isEmpty ? "" : "\(who) \(verb): \(items.formatted(.list(type: .and)))"
    }
    private var helper: String {
        proposal.severity == .allergy
            ? "Flags “may contain \(proposal.label)” too."
            : "Flags \(proposal.label) in the ingredients only."
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
                Picker("Kind", selection: Binding(get: { proposal.severity }, set: onSeverity)) {
                    Text("Allergy").tag(Severity.allergy)
                    Text("Intolerance").tag(Severity.intolerance)
                }
                .pickerStyle(.segmented)
                .disabled(proposal.state != .proposed)
                Text(helper)
                    .themeText(.footnote)
                    .foregroundStyle(Theme.color.muted)
                    .contentTransition(.opacity)
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
struct PersonPickerCard: View {
    let people: [Person]
    let onPick: (Person) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            ForEach(people) { person in
                OptionCard(iconKey: person.isOwner ? "me" : "girl", title: person.isOwner ? "You" : person.name,
                           detail: nil, mode: .single, isOn: false) { onPick(person) }
            }
        }
    }
}
