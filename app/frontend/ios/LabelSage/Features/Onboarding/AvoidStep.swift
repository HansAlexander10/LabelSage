import SwiftUI
import LabelSageCore

/// Step 11, "Anything else": the common groups, a catalog search, and a custom filter that the
/// resolver turns into keywords.
struct AvoidStep: View {
    @Bindable var model: OnboardingModel

    /// Q6: the "in products" shares stay hidden until their source is confirmed.
    static let showShares = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            HStack(spacing: Theme.spacing.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.color.muted)
                TextField("Anything, e.g. nightshades or red dye", text: $model.avoidQuery)
                    .themeText(.body)
                    .foregroundStyle(Theme.color.ink)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { if model.offersCustomFilter, model.avoidResults.isEmpty { model.startResolving() } }
                    .accessibilityLabel("Search any ingredient")
            }
            .padding(.horizontal, Theme.spacing.m)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: Theme.radius.field, style: .continuous).fill(Theme.color.surface))

            if let resolver = model.resolver {
                ResolverCard(model: model, resolver: resolver)
            } else if !model.avoidQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                results
            } else {
                if !model.current.custom.isEmpty { customChips }
                groups
            }
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.avoidResults.enumerated()), id: \.element.id) { i, family in
                if i > 0 { Divider().overlay(Theme.color.hairline) }
                let added = model.current.avoid.contains(family.id)
                resultRow(icon: family.icon, title: family.name,
                          meta: (added ? "Added · " : "") + "Also catches " + family.terms.prefix(3).joined(separator: ", "),
                          symbol: added ? "checkmark" : "plus") { model.toggleAvoid(family.id) }
            }
            if model.offersCustomFilter {
                if !model.avoidResults.isEmpty { Divider().overlay(Theme.color.hairline) }
                let term = model.avoidQuery.trimmingCharacters(in: .whitespaces)
                resultRow(icon: "options", title: "Make “\(term)” a custom filter",
                          meta: "I find the matching ingredients and their hidden names",
                          symbol: "wand.and.stars", action: model.startResolving)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.color.surface))
    }

    private func resultRow(icon: String, title: String, meta: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconView(key: icon, size: 32, decorative: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).themeText(.body)
                    Text(meta).themeText(.footnote).foregroundStyle(Theme.color.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: symbol)
            }
            .foregroundStyle(Theme.color.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }

    private var customChips: some View {
        ChipFlow(spacing: Theme.spacing.xs) {
            ForEach(model.current.custom, id: \.label) { custom in
                Button { model.removeCustom(custom.label) } label: {
                    HStack(spacing: Theme.spacing.xs) {
                        Text(custom.label)
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    }
                    .themeText(.caption)
                    .foregroundStyle(Theme.color.surface)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(Theme.color.ink))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Remove \(custom.label)")
            }
        }
        .padding(.top, Theme.spacing.xxs)
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.xs) {
            HStack {
                Text("Common groups")
                Spacer()
                if Self.showShares { Text("in products") }
            }
            .themeText(.footnote)
            .foregroundStyle(Theme.color.muted)
            .padding(.horizontal, Theme.spacing.xxs)
            .padding(.top, Theme.spacing.s)
            VStack(spacing: 0) {
                ForEach(Array(OnboardingCatalog.anythingElseGroups.enumerated()), id: \.element) { i, id in
                    if i > 0 { Divider().overlay(Theme.color.hairline) }
                    if let family = OnboardingCatalog.catalog.family(id) { groupRow(family) }
                }
            }
            .background(RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous).fill(Theme.color.surface))
        }
    }

    private func groupRow(_ family: Catalog.Family) -> some View {
        let on = model.current.avoid.contains(family.id)
        return Button { model.toggleAvoid(family.id) } label: {
            HStack(spacing: Theme.spacing.m) {
                Checkbox(isOn: on, style: .leaf)
                IconView(key: family.icon, size: 32, decorative: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(family.name).themeText(.body)
                    if on {
                        Text("Also catches " + family.terms.prefix(4).joined(separator: ", "))
                            .themeText(.footnote).foregroundStyle(Theme.color.muted).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if Self.showShares, let share = family.shareInProducts {
                    Text(share.formatted(.percent.precision(.fractionLength(0)))).themeText(.footnote).monospacedDigit()
                }
            }
            .foregroundStyle(Theme.color.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: 50)
            .contentShape(.rect)
        }
        .selectableCard(isOn: on, taps: model.current.avoid.count)
        .accessibilityLabel(family.name)
    }
}

/// Spec `ResolverCard`: "Matching…", then a choice when the term is ambiguous, then the keywords
/// to untick before "Add it".
struct ResolverCard: View {
    @Bindable var model: OnboardingModel
    let resolver: OnboardingModel.Resolver

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            Label(title, systemImage: "wand.and.stars")
                .themeText(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.color.inkSecondary)
            switch resolver {
            case .matching:
                HStack(spacing: Theme.spacing.s) {
                    ProgressView()
                    Text("Matching…").themeText(.footnote).foregroundStyle(Theme.color.inkSecondary)
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(700))
                    model.finishResolving()
                }
            case .ambiguous(let term, let choices):
                Text("“\(term)” could mean a few things. Which one?").themeText(.callout).foregroundStyle(Theme.color.inkSecondary)
                ForEach(choices, id: \.self) { id in
                    if let f = OnboardingCatalog.catalog.family(id) {
                        OptionCard(iconKey: f.icon, title: f.name, detail: f.terms.prefix(3).joined(separator: ", "),
                                   mode: .single, isOn: false) { model.pickResolverChoice(id) }
                    }
                }
                Button("Not right", action: model.cancelResolver)
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Theme.color.ink)
            case .matched(let m):
                HStack(spacing: Theme.spacing.s) {
                    Text("“\(m.term)”").themeText(.bodyStrong)
                    Image(systemName: "arrow.right").foregroundStyle(Theme.color.muted).accessibilityHidden(true)
                    Text(m.label).themeText(.bodyStrong)
                    Text(m.confidence)
                        .themeText(.footnote).fontWeight(.semibold)
                        .padding(.horizontal, Theme.spacing.s).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.color.ink.opacity(0.07)))
                }
                .foregroundStyle(Theme.color.ink)
                if !m.note.isEmpty { Text(m.note).themeText(.footnote).foregroundStyle(Theme.color.muted) }
                Text("I’ll match these on labels. Tap one to exclude it.")
                    .themeText(.footnote).fontWeight(.semibold).foregroundStyle(Theme.color.muted)
                ChipFlow(spacing: Theme.spacing.xs) {
                    ForEach(m.terms, id: \.self) { keyword in
                        let on = !m.off.contains(keyword)
                        Button { model.toggleResolverKeyword(keyword) } label: {
                            Text(keyword)
                                .themeText(.caption)
                                .strikethrough(!on)
                                .foregroundStyle(on ? Theme.color.surface : Theme.color.muted)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 32)
                                .background(Capsule().fill(on ? Theme.color.ink : Theme.color.surface))
                                .overlay(Capsule().strokeBorder(on ? .clear : Theme.color.controlBorder))
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(keyword)
                        .accessibilityValue(on ? "Matched" : "Excluded")
                    }
                }
                HStack(spacing: Theme.spacing.s) {
                    Button(action: model.cancelResolver) {
                        Text("Not right").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered).tint(Theme.color.ink)
                    Button(action: model.confirmResolver) {
                        Text("Add it · \(m.kept.count) keywords").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.color.ink)
                    .disabled(m.kept.isEmpty)
                }
                .themeText(.callout)
                .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radius.tile, style: .continuous).fill(Theme.color.surface))
    }

    private var title: String {
        switch resolver {
        case .matching(let term): "Finding what “\(term)” means"
        case .ambiguous: "Which did you mean?"
        case .matched: "Custom filter"
        }
    }
}

private func avoidPreview(_ setup: (OnboardingModel) -> Void) -> some View {
    let model = OnboardingModel()
    model.household = .family
    model.firstName = "Mia"
    model.current.goals = [.avoid]
    model.current.why = [.allergy]
    setup(model)
    model.show(.avoid)
    return OnboardingFlow(model: model, showsLaunch: false) { _ in }
}

#Preview("Anything else") { avoidPreview { $0.current.avoid = ["seed"] } }
#Preview("Anything else, search") { avoidPreview { $0.avoidQuery = "gelatin" } }
#Preview("Resolver, ambiguous") { avoidPreview { $0.resolver = OnboardingModel.resolve("oil") } }
#Preview("Resolver, matched") { avoidPreview { $0.resolver = OnboardingModel.resolve("cilantro") } }
#Preview("Resolver, matching") { avoidPreview { $0.resolver = .matching(term: "nightshades") } }
