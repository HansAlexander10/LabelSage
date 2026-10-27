import SwiftUI

/// Names as removable chips over an "Add a name" row, on a white card (prototype `team`, `others`).
struct NameListCard: View {
    let names: [String]
    var systemImage = "plus"
    var fieldLabel = "Add someone else at home"
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var trimmed: String { draft.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !names.isEmpty {
                ChipFlow(spacing: Theme.spacing.s) {
                    ForEach(names, id: \.self) { name in
                        HStack(spacing: Theme.spacing.xs) {
                            Text(name).themeText(.chip).lineLimit(1)
                            Button { onRemove(name) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Theme.color.brandGreenDeep.opacity(0.14)))
                                    .contentShape(.interaction, Circle().inset(by: -10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(name)")
                        }
                        .foregroundStyle(Theme.color.ink)
                        .padding(.leading, Theme.spacing.m)
                        .padding(.trailing, Theme.spacing.xs)
                        .frame(minHeight: 34)
                        .background(Capsule().fill(Theme.color.ink.opacity(0.07)))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, Theme.spacing.m)
                .padding(.bottom, Theme.spacing.xxs)
            }
            HStack(spacing: 10) {
                Image(systemName: systemImage).font(.system(size: 18)).foregroundStyle(Theme.color.ink)
                TextField("Add a name", text: $draft)
                    .themeText(.body)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(add)
                    .accessibilityLabel(fieldLabel)
                Button("Add", action: add)
                    .themeText(.callout)
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.color.ink)
                    .disabled(trimmed.isEmpty)
            }
            .padding(.leading, 14)
            .padding(.trailing, Theme.spacing.s)
            .frame(minHeight: 56)
        }
        .background(RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous).fill(Theme.color.surface))
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        onAdd(String(trimmed.prefix(24)))
        draft = ""
    }
}

/// Step 3 (My family): the first person's name with quick picks, then everyone else at home.
struct FirstProfileStep: View {
    @Bindable var model: OnboardingModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            Text("Name or nickname").themeText(.onboardingLabel).padding(.horizontal, Theme.spacing.xxs)
            TextField("e.g. Mia", text: $model.firstName)
                .themeText(.onboardingField)
                .foregroundStyle(Theme.color.ink)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($nameFocused)
                .padding(.horizontal, Theme.spacing.xl)
                .frame(minHeight: 66)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.color.surface))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.color.ink, lineWidth: 1.5))
                .onChange(of: model.firstName) { _, new in if new.count > 24 { model.firstName = String(new.prefix(24)) } }
            HStack(spacing: Theme.spacing.s) {
                ForEach(["Me", "My child", "My partner"], id: \.self) { pick in
                    Button(pick) { model.firstName = pick }
                        .themeText(.chip)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .tint(Theme.color.ink)
                }
            }
            Text("Anyone else at home?")
                .themeText(.onboardingLabel)
                .padding(.horizontal, Theme.spacing.xxs)
                .padding(.top, Theme.spacing.m)
            NameListCard(names: model.team, onAdd: model.addTeamMember) { name in
                model.team.removeAll { $0 == name }
            }
            OnboardingFootnote(systemImage: "person.2", text: "Every product is checked for everyone you add.")
        }
        .foregroundStyle(Theme.color.ink)
    }
}

/// Step 12: the "may contain" switch and who shares these allergies.
struct StrictStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            Toggle(isOn: $model.mayContain) {
                VStack(alignment: .leading, spacing: Theme.spacing.xxs) {
                    Text("Also avoid “may contain”").themeText(.body)
                    Text("Shared lines and cross-contamination warnings." + (model.mayContainDefault ? " On because of your answers." : ""))
                        .themeText(.footnote)
                        .foregroundStyle(Theme.color.muted)
                }
                .foregroundStyle(Theme.color.ink)
            }
            .tint(Theme.color.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: 76)
            .background(RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous).fill(Theme.color.surface))

            Text("Same allergies for anyone else?")
                .themeText(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.color.muted)
                .padding(.horizontal, Theme.spacing.xxs)
                .padding(.top, Theme.spacing.l)
            NameListCard(names: model.current.sameFor, systemImage: "person.2", fieldLabel: "Add a name") { name in
                model.addSameFor(name)
            } onRemove: { name in
                model.current.sameFor.removeAll { $0 == name }
            }
            Text("Each name gets these allergies. No need to answer again.")
                .themeText(.footnote)
                .foregroundStyle(Theme.color.muted)
                .padding(.horizontal, Theme.spacing.xxs)
        }
    }
}

/// Step 14 (My family): who is done, who is next, and "Leo has the same allergies as Mia".
struct NextPersonStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        let names = [model.firstName.trimmingCharacters(in: .whitespaces)] + model.team
        VStack(spacing: Theme.spacing.m) {
            VStack(spacing: 0) {
                ForEach(Array(names.enumerated()), id: \.offset) { i, name in
                    if i > 0 { Divider().overlay(Theme.color.hairline) }
                    personRow(name, done: i <= model.personIndex, next: i == model.personIndex + 1)
                }
            }
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.color.surface))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            if let next = model.nextPersonName, let who = model.currentName {
                Button(action: model.nextPersonSharesAllergies) {
                    Label("\(next) has the same allergies as \(who)", systemImage: "person.2")
                        .themeText(.body)
                        .foregroundStyle(Theme.color.ink)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, Theme.spacing.l)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.color.surface))
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func personRow(_ name: String, done: Bool, next: Bool) -> some View {
        HStack(spacing: Theme.spacing.m) {
            ZStack {
                if done {
                    Circle().fill(Theme.color.ink)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.color.surface)
                } else {
                    Circle().strokeBorder(next ? Theme.color.ink : Theme.color.controlBorder, lineWidth: 1.5)
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).themeText(.bodyStrong).lineLimit(1)
                Text(done ? "Allergies set" : next ? "Next: a few questions" : "After that")
                    .themeText(.footnote).foregroundStyle(Theme.color.muted)
            }
            .foregroundStyle(Theme.color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.spacing.l)
        .frame(minHeight: 60)
        .background(next ? Theme.screenTint.summary : .clear)
        .accessibilityElement(children: .combine)
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

#Preview("First profile, empty") {
    let model = OnboardingModel()
    model.household = .family
    model.show(.firstProfile)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}

#Preview("First profile, Mia, Leo, Sam") {
    let model = OnboardingModel()
    model.household = .family
    model.firstName = "Mia"
    model.team = ["Leo", "Sam"]
    model.show(.firstProfile)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}

#Preview("Strict") {
    let model = OnboardingModel()
    model.current.goals = [.avoid]
    model.current.why = [.allergy]
    model.current.allergens = ["peanut"]
    model.current.sameFor = ["Dad"]
    model.show(.strict)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}

#Preview("Next person") {
    let model = OnboardingModel()
    model.household = .family
    model.firstName = "Mia"
    model.team = ["Leo", "Sam"]
    model.current.goals = [.avoid]
    model.show(.nextPerson)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}
