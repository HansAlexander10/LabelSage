import SwiftUI
import LabelSageCore

/// The "Add a name" field on a white card: the text and an "Add" capsule, nothing else (product
/// owner, 2026-10-27: no leading plus). Add is green with white text once there is a name
/// (6.6:1), and a light grey capsule with muted text while empty (4.7:1).
struct NameField: View {
    @Binding var text: String
    var prompt = "Add a name"
    var fieldLabel = "Name"
    /// False keeps Add disabled even with text (a name already in the household).
    var isAcceptable = true
    /// Add, or Return on the keyboard.
    let onAdd: () -> Void

    @FocusState private var focused: Bool

    private var canAdd: Bool { isAcceptable && !text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            TextField(fieldLabel, text: $text, prompt: Text(prompt).foregroundStyle(Theme.color.muted))
                .themeText(.onboardingField)
                .foregroundStyle(Theme.color.ink)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { if canAdd { onAdd() } }
                .onChange(of: text) { _, new in if new.count > 24 { text = String(new.prefix(24)) } }
                .accessibilityLabel(fieldLabel)
            Button(action: onAdd) {
                Text("Add")
                    .themeText(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(canAdd ? Theme.color.surface : Theme.color.muted)
                    .padding(.horizontal, Theme.spacing.l)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(canAdd ? Theme.color.brandGreenDeep : Theme.color.disabledFill))
                    .contentShape(.capsule)
            }
            .buttonStyle(.pressable)
            .disabled(!canAdd)
            .accessibilityHint(canAdd ? "" : isAcceptable ? "Type a name first" : "Use another name")
        }
        .padding(.leading, Theme.spacing.l)
        .padding(.trailing, Theme.spacing.s)
        .frame(minHeight: 60)
        .background(RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous).fill(Theme.color.surface))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous)
                .strokeBorder(focused ? Theme.color.ink : Theme.color.controlBorder, lineWidth: focused ? 2 : 1)
        )
    }
}

/// Add a person, step 1: their name.
struct PersonNameStep: View {
    @Bindable var model: OnboardingModel
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            NameField(text: $model.name, fieldLabel: "Their name or nickname",
                      isAcceptable: !model.isNameTaken(model.name), onAdd: onAdd)
            if let missing = model.missingAnswer, model.isNameTaken(model.name) {
                OnboardingFootnote(systemImage: "exclamationmark.circle", text: missing + ".")
            } else {
                OnboardingFootnote(systemImage: "person.2", text: "Every product is checked for everyone you add.")
            }
        }
    }
}

/// Add a person, step 2: start from someone's preferences (a copy) or fresh. One tick.
struct StartFromStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: Theme.spacing.m) {
            OptionCardList(options: options, mode: .single) { model.startFrom == $0 } tap: { model.chooseStart($0) }
            OnboardingFootnote(systemImage: "doc.on.doc",
                               text: "\(model.currentName ?? "They") get\(model.currentName == nil ? "" : "s") a copy to change. It never changes anyone else\u{2019}s.")
        }
    }

    private var options: [ChoiceOption] {
        model.existing.map { person in
            let title = "Start from \(OnboardingModel.possessive(person)) preferences"
            return ChoiceOption(id: person.id, icon: person.isOwner ? "me" : "family",
                                title: title.prefix(1).uppercased() + title.dropFirst(),
                                detail: Self.detail(person.profile))
        } + [ChoiceOption(id: OnboardingModel.freshStart, icon: "add", title: "Start fresh", detail: "Nothing ticked yet")]
    }

    /// "Peanut, tree nuts, seed oils and 1 more", or "Nothing to avoid yet".
    static func detail(_ profile: Profile) -> String {
        let titles = OnboardingModel.summaryItems(OnboardingModel.answers(from: profile)).enumerated()
            .map { $0.offset == 0 ? $0.element.title : $0.element.title.lowercased() }
        guard !titles.isEmpty else { return "Nothing to avoid yet" }
        let shown = titles.prefix(3).joined(separator: ", ")
        return titles.count > 3 ? "\(shown) and \(titles.count - 3) more" : shown
    }
}

/// Lays chips out left to right and wraps them (prototype `flex-wrap: wrap`).
// Custom: SwiftUI has no wrapping stack; `PersonCard`'s FlowLayout is private to the design system.
struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                let w = min(size.width, bounds.width)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: w, height: size.height))
                x += w + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let w = min(size.width, width)
            if !row.indices.isEmpty, row.width + spacing + w > width + 0.5 {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? w : row.width + spacing + w
            row.height = max(row.height, size.height)
            row.indices.append(i)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

#if DEBUG
#Preview("Add a person, name") {
    OnboardingFlow(model: .sampleAddPerson(.name), showsLaunch: false) { _ in }
}

#Preview("Add a person, start from") {
    OnboardingFlow(model: .sampleAddPerson(.startFrom), showsLaunch: false) { _ in }
}

#Preview("Name field, empty and filled") {
    VStack(spacing: Theme.spacing.l) {
        NameField(text: .constant(""), onAdd: {})
        NameField(text: .constant("Leo"), onAdd: {})
    }
    .padding(Theme.spacing.screenGutter)
    .background(Theme.screenTint.household)
}
#endif
