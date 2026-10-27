import SwiftUI
import LabelSageCore

/// An inline search field in the content (native-components.md › Allergen group search): a
/// magnifying glass and a `TextField` on a white capsule.
struct InlineSearchField: View {
    let prompt: String
    @Binding var text: String
    var accessibilityLabel: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.color.muted)
            TextField(prompt, text: $text)
                .themeText(.body)
                .foregroundStyle(Theme.color.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityLabel(accessibilityLabel)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.color.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, Theme.spacing.l)
        .frame(minHeight: 54)
        .themeCardBackground(cornerRadius: 27, isSelected: false)
    }
}

/// Step 6: allergen groups that open in place, with a search that knows other names.
struct AllergensStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(spacing: Theme.spacing.m) {
            InlineSearchField(prompt: "Search, like prawns or mustard", text: $model.allergenQuery,
                              accessibilityLabel: "Search allergens")
            let groups = model.visibleGroups
            if groups.isEmpty {
                Text("Not in this list. Add “\(model.allergenQuery.trimmingCharacters(in: .whitespaces))” on the next step, and I’ll look for it under other names too.")
                    .themeText(.callout)
                    .foregroundStyle(Theme.color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.spacing.l)
                    .background(RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous).fill(Theme.color.surface))
            }
            ForEach(groups, id: \.id) { group in
                if let leaves = group.leaves {
                    GroupCard(iconKey: group.icon, title: group.label, leaves: leaves.map(OnboardingCatalog.name),
                              selection: selection(group), isOpen: openBinding(group))
                } else {
                    OptionCard(iconKey: group.icon, title: group.label, mode: .multi,
                               isOn: model.current.allergens.contains(group.id)) { model.toggleAllergen(group.id) }
                }
            }
            if let footnote = model.coveredFootnote {
                OnboardingFootnote(systemImage: "info.circle", text: footnote)
            }
        }
        .sheet(isPresented: Binding(get: { model.relatedFor != nil }, set: { if !$0 { model.relatedFor = nil } })) {
            if let id = model.relatedFor {
                RelatedSheet(allergen: id, suggestions: (OnboardingCatalog.related[id] ?? []).filter { !model.isPicked($0) }) { picked in
                    model.addRelated(picked)
                }
            }
        }
    }

    /// `GroupCard` selects leaf titles; the model keeps catalog ids.
    private func selection(_ group: OnboardingCatalog.AllergenGroup) -> Binding<Set<String>> {
        let leaves = group.leaves ?? []
        return Binding {
            Set(model.leaves(of: group).map(OnboardingCatalog.name))
        } set: { titles in
            model.setLeaves(Set(leaves.filter { titles.contains(OnboardingCatalog.name($0)) }), of: group)
        }
    }

    private func openBinding(_ group: OnboardingCatalog.AllergenGroup) -> Binding<Bool> {
        Binding {
            model.isOpen(group)
        } set: { open in
            if open { model.openGroups.insert(group.id) } else { model.openGroups.remove(group.id) }
        }
    }
}

/// "Peanut is added. Some people with a peanut allergy also react to tree nuts or lupin." Nothing
/// is ticked until the person ticks it (spec `RelatedSheet`).
struct RelatedSheet: View {
    let allergen: String
    let suggestions: [String]
    /// The ticked ids; empty for "Just peanut".
    let onDone: ([String]) -> Void

    @State private var picked: [String] = []

    private var name: String { OnboardingCatalog.name(allergen) }

    private var text: String {
        let list = suggestions.map { OnboardingCatalog.name($0).lowercased() }.joined(separator: " or ")
        return "\(name) is added. Some people with a \(name.lowercased()) allergy also react to \(list). Add either? Nothing is added unless you tick it."
    }

    var body: some View {
        VStack(spacing: Theme.spacing.m) {
            Text(text)
                .font(.custom("Outfit", size: 18, relativeTo: .body))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.color.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(suggestions, id: \.self) { id in
                    let on = picked.contains(id)
                    Button {
                        if on { picked.removeAll { $0 == id } } else { picked.append(id) }
                    } label: {
                        HStack(spacing: Theme.spacing.l) {
                            Checkbox(isOn: on)
                            IconView(key: id, size: 32, decorative: true)
                                .frame(width: 52, height: 52)
                                .background(Circle().fill(Theme.color.ink.opacity(0.05)))
                            Text(OnboardingCatalog.name(id))
                                .font(.custom("Outfit", size: 19, relativeTo: .body))
                                .foregroundStyle(Theme.color.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 72)
                        .contentShape(.rect)
                    }
                    .selectableCard(isOn: on, taps: picked.count)
                    .accessibilityLabel(OnboardingCatalog.name(id))
                }
            }
            PrimaryButton(title: picked.isEmpty ? "Add selected" : "Add \(picked.count) more", showsChevron: false) {
                onDone(picked)
            }
            Button {
                onDone([])
            } label: {
                Text("Just \(name.lowercased())")
                    .themeText(.primaryButton)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.color.ink)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .overlay(Capsule().strokeBorder(Theme.color.ink, lineWidth: 1.5))
                    .contentShape(.capsule)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 22)
        .padding(.top, Theme.spacing.xl)
        .padding(.bottom, Theme.spacing.s)
        .presentationDetents([.height(500), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.color.surface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Related allergens")
    }
}

/// Step 7: allergy (default) or intolerance, per allergen (D3).
struct SeverityStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            ForEach(model.allergenChoices, id: \.id) { choice in
                HStack(spacing: 10) {
                    IconView(key: choice.id, size: 32, decorative: true)
                    Text(OnboardingCatalog.name(choice.id)).themeText(.bodyStrong).foregroundStyle(Theme.color.ink)
                }
                .padding(.horizontal, Theme.spacing.xxs)
                .padding(.top, Theme.spacing.m)
                .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    row(choice.id, .allergy, "Allergy", "Avoid it, and “may contain” too")
                    Divider().overlay(Theme.color.hairline).padding(.leading, Theme.spacing.l)
                    row(choice.id, .intolerance, "Intolerance", "Only when it’s in the ingredients")
                }
                .background(RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous).fill(Theme.color.surface))
            }
        }
    }

    private func row(_ id: String, _ severity: Severity, _ title: String, _ detail: String) -> some View {
        let on = model.severity(of: id) == severity
        return Button {
            model.setSeverity(severity, for: id)
        } label: {
            HStack(spacing: Theme.spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).themeText(.bodyStrong)
                    Text(detail).themeText(.caption).foregroundStyle(Theme.color.muted)
                }
                .foregroundStyle(Theme.color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.color.ink)
                    .opacity(on ? 1 : 0)
            }
            .padding(.horizontal, Theme.spacing.l)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(OnboardingCatalog.name(id)): \(title). \(detail)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: on)
    }
}

#Preview("Allergens") {
    let model = OnboardingModel()
    model.current.goals = [.avoid]
    model.current.why = [.allergy]
    model.openGroups = ["treenuts"]
    model.show(.allergens)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}

#Preview("Allergens, search prawns") {
    let model = OnboardingModel()
    model.current.goals = [.avoid]
    model.current.why = [.allergy]
    model.allergenQuery = "prawns"
    model.show(.allergens)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}

#Preview("Allergens, vegan covers some") {
    let model = OnboardingModel()
    model.current.goals = [.avoid]
    model.current.why = [.allergy, .diet]
    model.current.diets = ["vegan"]
    model.show(.allergens)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}

#Preview("Peanut related sheet") {
    let model = OnboardingModel()
    model.current.goals = [.avoid]
    model.current.why = [.allergy]
    model.show(.allergens)
    model.toggleAllergen("peanut")
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}

#Preview("Severity") {
    let model = OnboardingModel()
    model.household = .family
    model.firstName = "Mia"
    model.current.goals = [.avoid]
    model.current.why = [.allergy]
    model.current.allergens = Set(["peanut"] + (OnboardingCatalog.allergenGroups[1].leaves ?? []))
    model.show(.severity)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}
