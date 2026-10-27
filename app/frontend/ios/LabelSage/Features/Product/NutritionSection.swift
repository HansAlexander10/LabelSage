import SwiftUI
import Charts
import LabelSageCore

/// "Nutrition" (spec 04): a donut of calories by macro, three macro chips, the added sugar and
/// sodium facts, and "Full nutrition facts" per serving or per 100 g. Macro colors are never the
/// verdict colors. Without nutrition it says "No nutrition facts yet."
struct NutritionSection: View {
    /// nil shows "No nutrition facts yet."
    let nutrition: Nutrition?
    let servingGrams: Double?
    let addedSugarFlagged: Bool
    let sodiumFlagged: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isOpen = false
    @State private var basis: NutritionFacts.Basis = .serving

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.s) {
            SectionHeader("Nutrition").padding(.leading, Theme.spacing.xxs)
            VStack(spacing: 0) {
                if let nutrition {
                    let macros = NutritionFacts.macros(nutrition)
                    if !macros.isEmpty {
                        VStack(spacing: 18) {
                            donut(nutrition, macros: macros)
                            chips(macros)
                        }
                        .padding(.top, Theme.spacing.xl)
                        .padding(.bottom, 18)
                        .padding(.horizontal, Theme.spacing.l)
                        Divider()
                    }
                    facts(nutrition)
                    Divider()
                    fullFacts(nutrition).padding(.horizontal, Theme.spacing.l)
                } else {
                    Text("No nutrition facts yet.")
                        .themeText(.callout).foregroundStyle(Theme.color.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.spacing.l)
                }
            }
            .themeCardBackground(cornerRadius: Theme.radius.card, isSelected: false)
        }
    }

    // MARK: Parts

    private func donut(_ n: Nutrition, macros: [NutritionFacts.Macro]) -> some View {
        Chart(macros) { macro in
            SectorMark(angle: .value("Calories", macro.kcal), innerRadius: .ratio(0.86), angularInset: 1.5)
                .foregroundStyle(Self.color(macro.kind))
        }
        .chartLegend(.hidden)
        .frame(width: 168, height: 168)
        .overlay {
            VStack(spacing: 2) {
                Text(NutritionFacts.calories(n).map(String.init) ?? "")
                    .themeText(.donutNumber).foregroundStyle(Theme.color.ink)
                Text("Calories").themeText(.footnote).fontWeight(.semibold).foregroundStyle(Theme.color.inkSecondary)
                Text("per serving").themeText(.footnote).foregroundStyle(Theme.color.muted)
            }
        }
        // One element for VoiceOver (spec 04).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NutritionFacts.donutLabel(n))
    }

    private func chips(_ macros: [NutritionFacts.Macro]) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.spacing.m)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            ForEach(macros) { macro in
                VStack(spacing: Theme.spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(NutritionFacts.format(macro.grams)).themeText(.chip).monospacedDigit()
                        Text("g").themeText(.footnote).foregroundStyle(Theme.color.muted)
                    }
                    .frame(minWidth: 52, minHeight: 52)
                    .background(Circle().fill(Self.color(macro.kind).opacity(0.18)))
                    .overlay(Circle().strokeBorder(Self.color(macro.kind), lineWidth: 3))
                    Text(macro.kind.rawValue).themeText(.caption).fontWeight(.semibold).foregroundStyle(Theme.color.ink)
                    Text("\(Int(macro.kcal.rounded())) kcal \u{00B7} \(macro.percent)%")
                        .themeText(.footnote).monospacedDigit().foregroundStyle(Theme.color.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(macro.kind.rawValue), \(NutritionFacts.format(macro.grams)) grams, \(macro.percent)% of calories")
            }
        }
    }

    private func facts(_ n: Nutrition) -> some View {
        HStack(spacing: 0) {
            if let sugar = n.addedSugarsG {
                fact(value: "\(NutritionFacts.format(sugar)) g", label: "added sugar", flagged: addedSugarFlagged)
            }
            if n.addedSugarsG != nil, n.sodiumMg != nil { Divider() }
            if let sodium = n.sodiumMg {
                fact(value: "\(NutritionFacts.format(sodium)) mg", label: "sodium", flagged: sodiumFlagged)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, Theme.spacing.m)
    }

    private func fact(value: String, label: String, flagged: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Text(value).themeText(.factNumber).foregroundStyle(Theme.color.ink)
                if flagged {
                    Image(systemName: Theme.verdict.checkFirst.symbol)
                        .foregroundStyle(Theme.verdict.checkFirst.color)
                        .imageScale(.small)
                }
            }
            Text(label).themeText(.footnote).foregroundStyle(Theme.color.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)" + (flagged ? ", check first" : ""))
    }

    private func fullFacts(_ n: Nutrition) -> some View {
        DisclosureGroup(isExpanded: $isOpen) {
            VStack(spacing: 0) {
                if servingGrams != nil {
                    Picker("Amount", selection: $basis) {
                        Text("Per serving").tag(NutritionFacts.Basis.serving)
                        Text("Per 100 g").tag(NutritionFacts.Basis.per100g)
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: basis)
                    .padding(.vertical, Theme.spacing.s)
                }
                let rows = NutritionFacts.rows(n, basis: basis, servingGrams: servingGrams) ?? []
                ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                    HStack(spacing: Theme.spacing.xs) {
                        Text(row.label)
                            .themeText(.callout)
                            .fontWeight(row.isMain ? .semibold : .regular)
                            .foregroundStyle(row.isMain ? Theme.color.ink : Theme.color.inkSecondary)
                            .padding(.leading, row.isMain ? 0 : 14)
                        Spacer()
                        Text(row.amount).themeText(.callout).monospacedDigit().foregroundStyle(Theme.color.ink)
                        Text(row.dailyValue).themeText(.footnote).monospacedDigit().foregroundStyle(Theme.color.muted)
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                    .frame(minHeight: 40)
                    if offset < rows.count - 1 { Divider() }
                }
                Text("% Daily Value based on 2,000 kcal a day.")
                    .themeText(.footnote).foregroundStyle(Theme.color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Theme.spacing.s)
            }
            .padding(.bottom, Theme.spacing.m)
        } label: {
            HStack {
                Text("Full nutrition facts").themeText(.body).foregroundStyle(Theme.color.ink)
                Spacer()
                if let servingGrams {
                    Text("per \(NutritionFacts.format(servingGrams)) g serving").themeText(.callout).foregroundStyle(Theme.color.muted)
                }
            }
            .frame(minHeight: 48)
        }
        .tint(Theme.color.muted)
    }

    /// Spec 04: carbs #eb9d15, fat #7e9086, protein #26834e. Fat has no token; the nearest is
    /// `mutedGreen` #6f7a73 (open question Q-T9-3).
    static func color(_ kind: NutritionFacts.Macro.Kind) -> Color {
        switch kind {
        case .carbs: Theme.color.amber
        case .fat: Theme.color.mutedGreen
        case .protein: Theme.color.brandGreen
        }
    }
}

nonisolated extension Theme.TypeStyle {
    /// Prototype `Main.dc.html`: the donut's calories, 40/700, tabular.
    static let donutNumber = Theme.TypeStyle(size: 40, weight: .bold, trackingEm: -0.02, relativeTo: .largeTitle, isTabularNumber: true)
    /// Prototype: the facts row values, 20/600, tabular.
    static let factNumber = Theme.TypeStyle(size: 20, weight: .semibold, relativeTo: .title3, isTabularNumber: true)
}
