import SwiftUI
import LabelSageCore

/// The summary: the person's card, the region and store (first run only), a "Try it" line from
/// the engine, and the notes. Avoid and Prefer not flip on each "Anything else" rule (D12).
struct SummaryStep: View {
    @Bindable var model: OnboardingModel
    /// A sample product for "Try it"; the line is hidden without one.
    let tryItProduct: Product?

    @Environment(\.verdictService) private var verdictService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: Theme.spacing.m) {
            SummaryPersonCard(name: model.summaryName, index: model.existing.count,
                              items: OnboardingModel.summaryItems(model.current), compact: false) { key in
                model.flip(key)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 12)
            .animation(Theme.motion.easeOut(duration: 0.6), value: appeared)
            if !model.isAddingPerson { placeRow }
            tryIt
            // "Check the package. Not medical advice." removed by the product owner (D-33).
            Text("Avoid hides it. Prefer not only shows it lower. Tap to switch.")
            .themeText(.caption)
            .foregroundStyle(Theme.color.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacing.xxs)
        }
        .onAppear { appeared = true }
    }

    private var placeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "storefront")
            VStack(alignment: .leading, spacing: 0) {
                Text(model.region.map(RegionStep.regionLine) ?? "Region not set")
                Text(model.store.map { "\($0.name) · change in Profile" } ?? "Store: set up later in Profile")
                    .foregroundStyle(Theme.color.muted)
            }
            .themeText(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Theme.color.ink)
        .padding(.horizontal, 14).padding(.vertical, Theme.spacing.s)
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.color.surface))
    }

    /// "Try it: Popped Corn Chips would be **Not for Mia**: sunflower oil is a seed oil." The flag
    /// and reason come from `VerdictEngine` over the household built so far.
    @ViewBuilder private var tryIt: some View {
        if let product = tryItProduct, let household = model.tryItHousehold,
           let worst = verdictService.check(product, for: household).verdict.people.max(by: { $0.level < $1.level }) {
            let flag = Copy.flag(worst.level, names: [worst.name == "You" ? "you" : worst.name])
            let tail = worst.reason.hasPrefix(flag) ? String(worst.reason.dropFirst(flag.count)) : ". " + worst.reason
            let style = Theme.verdict.style(for: worst.level)
            HStack(spacing: 10) {
                Image(systemName: style.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(style.color)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(style.wash))
                    .accessibilityHidden(true)
                Text("\(Text("Try it:").foregroundStyle(Theme.color.muted)) \(product.name) would be \(Text(flag).bold())\(tail)")
                    .themeText(.caption)
                    .foregroundStyle(Theme.color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, Theme.spacing.m)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.color.surface))
        }
    }
}

/// One person on the summary (spec `PersonSummaryCard`): avatar initial on a tint, name,
/// "3 to avoid · 1 other", Edit. Full: a row per rule with its `KindBadge`. Compact (three or more
/// people): chips so everyone fits; Edit opens the rows.
// Custom, not `PersonCard`: allergies here are fixed Avoid (only "Anything else" rules flip), and
// the onboarding card has no per-rule switch or "Add an allergy" row.
struct SummaryPersonCard: View {
    let name: String
    let index: Int
    let items: [OnboardingModel.SummaryItem]
    let compact: Bool
    let flip: (String) -> Void

    @State private var editing = false

    private var showsRows: Bool { !compact || editing }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.m) {
            HStack(spacing: 14) {
                Text(PersonSummary.initial(name))
                    .font(.custom("Outfit", fixedSize: compact ? 21 : 25).weight(.bold))
                    .foregroundStyle(Theme.color.ink)
                    .frame(width: compact ? 48 : 58, height: compact ? 48 : 58)
                    .background(Circle().fill(Theme.screenTint.avatarTints[index % Theme.screenTint.avatarTints.count]))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.custom("Outfit", size: 22, relativeTo: .title2).weight(.bold)).lineLimit(1)
                    Text(OnboardingModel.summaryLine(items)).themeText(.caption).foregroundStyle(Theme.color.mutedGreen)
                }
                .foregroundStyle(Theme.color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if compact {
                    Button(editing ? "Done" : "Edit") { editing.toggle() }
                        .themeText(.callout).fontWeight(.semibold)
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
                        .tint(Theme.color.ink)
                        .accessibilityLabel(editing ? "Done editing \(name)" : "Edit \(name)")
                }
            }
            if items.isEmpty {
                Text("Nothing to avoid yet. Add allergies any time.").themeText(.callout).foregroundStyle(Theme.color.mutedGreen)
            } else if showsRows {
                VStack(spacing: Theme.spacing.s) { ForEach(items) { row($0) } }
            } else {
                ChipFlow(spacing: Theme.spacing.xs) {
                    ForEach(items) { item in
                        Chip(kind: chipKind(item.kind), iconKey: item.iconKey, text: item.title)
                    }
                }
            }
        }
        .padding(compact ? 14 : Theme.spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
        .themeAnimation(Theme.motion.groupCardOpen, value: editing)
    }

    private func row(_ item: OnboardingModel.SummaryItem) -> some View {
        HStack(spacing: Theme.spacing.m) {
            IconView(key: item.iconKey, size: 36, decorative: true)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).themeText(.bodyStrong)
                Text(item.detail).themeText(.footnote).foregroundStyle(Theme.color.mutedGreen).lineLimit(1)
            }
            .foregroundStyle(Theme.color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.isFlippable {
                KindBadge(ruleName: item.title, kind: Binding(get: { item.kind }, set: { _ in flip(item.id) }))
            } else {
                Text(item.kind.title)
                    .themeText(.badge)
                    .foregroundStyle(Theme.color.ink)
                    .padding(.horizontal, Theme.spacing.m)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(item.kind.style.badge))
                    .accessibilityLabel("\(item.title): \(item.kind.title)")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, Theme.spacing.s)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.color.ink.opacity(0.03)))
    }

    private func chipKind(_ kind: KindBadge.Kind) -> Chip.Kind {
        switch kind {
        case .avoid: .avoid
        case .preferNot: .preferNot
        case .diet, .goal: .dietGoal
        }
    }
}

#if DEBUG
#Preview("Summary, owner") {
    OnboardingFlow(model: .sampleOwner(), showsLaunch: false, tryItProduct: try? SampleData.products().first) { _ in }
}

#Preview("Summary, adding Leo") {
    OnboardingFlow(model: .sampleAddPerson(.summary), showsLaunch: false, tryItProduct: try? SampleData.products().first) { _ in }
}

#Preview("Summary, milk") {
    let model = OnboardingModel()
    model.current.goals = [.avoid]
    model.current.why = [.allergy]
    model.current.allergens = ["milk"]
    model.current.avoid = ["seed", "sugar"]
    model.region = Region(zip: "78701", city: "Austin, TX")
    model.show(.summary)
    return OnboardingFlow(model: model, showsLaunch: false, tryItProduct: try? SampleData.products().first) { _ in }
}
#endif
