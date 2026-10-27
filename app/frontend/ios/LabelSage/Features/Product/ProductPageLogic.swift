import Foundation
import LabelSageCore

// The product page's logic, apart from the views so it can be unit tested (ProductPageTests):
// which sections show, the "What you avoid" rows, the key ingredient rows and the nutrition math.

// MARK: - Sections per state

/// What the product page shows for one product, verdict and presentation (spec 04 edge cases).
nonisolated struct ProductPageLayout: Equatable {
    /// The photo hero at the top (`photo: .shown`).
    var showsHero: Bool
    /// The 60 pt photo signal on the hero. Without a real photo it moves next to the name.
    var signalOnHero: Bool
    /// "Try instead" under the banner: the verdict is not OK and an option is OK.
    var showsTryInstead: Bool
    /// Key ingredients, or the "No ingredient list" note.
    var hasIngredients: Bool
    /// Nutrition donut and facts, or "No nutrition facts yet."
    var hasNutrition: Bool
    /// "Other options for you", hidden when there are none.
    var showsOptions: Bool
    /// "Data updated Oct 2026" under the disclaimer.
    var dataAge: String?

    /// Spec 04 "Data age": shown when the data is older than this.
    static let staleAfterDays = 90

    static func make(product: Product, verdict: HouseholdVerdict, photo: ProductPage.Photo,
                     options: [ProductOption], now: Date = .now) -> ProductPageLayout {
        let showsHero = photo == .shown
        var dataAge: String?
        if let updated = product.dataUpdatedAt,
           let days = Calendar(identifier: .gregorian).dateComponents([.day], from: updated, to: now).day,
           days > staleAfterDays {
            dataAge = DataAge.updatedLine(updated)
        }
        return ProductPageLayout(
            showsHero: showsHero,
            signalOnHero: showsHero && product.imageURL != nil,
            showsTryInstead: verdict.overall != .ok && !options.isEmpty,
            hasIngredients: verdict.label.hasList,
            hasNutrition: product.nutrition.map(NutritionFacts.hasAnyValue) ?? false,
            showsOptions: !options.isEmpty,
            dataAge: dataAge
        )
    }
}

/// "Data updated Oct 2026", one wording and one locale for the product page and the scan cards.
nonisolated enum DataAge {
    /// Pinned to `en_US`: the app's copy is English, so the month is too.
    static func updatedLine(_ date: Date) -> String {
        "Data updated " + date.formatted(.dateTime.month(.abbreviated).year().locale(Locale(identifier: "en_US")))
    }
}

/// Another product for this household, with its verdict (an "Other options for you" card).
nonisolated struct ProductOption: Identifiable, Equatable, Sendable {
    var product: Product
    var verdict: HouseholdVerdict
    var id: String { product.id }

    /// Options worth offering: OK for everyone in the household, in the source's order.
    static func offered(_ options: [ProductOption]) -> [ProductOption] {
        options.filter { $0.verdict.overall == .ok }
    }
}

// MARK: - Header lines

nonisolated enum ProductHeader {
    /// "3 oz · 3 servings of 28 g". Skips what the data does not say.
    static func sizeLine(size: String?, servingSize: String?) -> String? {
        var parts: [String] = []
        if let size, !size.isEmpty { parts.append(size) }
        if let grams = NutritionFacts.grams(inServing: servingSize) {
            let shown = NutritionFacts.format(grams)
            if let total = packGrams(size), total >= grams {
                let count = max(1, Int((total / grams).rounded()))
                parts.append("\(count) \(count == 1 ? "serving" : "servings") of \(shown) g")
            } else {
                parts.append("\(shown) g serving")
            }
        } else if let servingSize, !servingSize.isEmpty {
            parts.append("serving \(servingSize)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// The pack weight in grams from "3 oz", "16 oz", "500 g" or "1 kg". nil for volumes ("fl oz") and counts.
    static func packGrams(_ size: String?) -> Double? {
        guard let size = size?.lowercased(), !size.contains("fl") else { return nil }
        let units: [(String, Double)] = [("kg", 1000), ("oz", 28.3495), ("lb", 453.592), ("g", 1)]
        for (unit, factor) in units {
            if let value = number(before: unit, in: size) { return value * factor }
        }
        return nil
    }

    static func number(before unit: String, in text: String) -> Double? {
        let pattern = "(\\d+(?:\\.\\d+)?)\\s*" + unit + "\\b"
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let digits = text[match].prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }
}

// MARK: - What you avoid

/// One thing someone in the household avoids, as a row with a per-check switch (spec 04 "Rows").
/// It is a profile choice, so switching it off removes exactly that choice from this check.
nonisolated struct AvoidRow: Identifiable, Equatable, Sendable {
    enum Choice: Equatable, Sendable {
        case allergen(String)
        case medical(String)
        case diet(String)
        case avoid(String)
        case custom(String)
    }

    var personId: String
    /// "you" or the name.
    var personName: String
    var choice: Choice
    /// "Avoid seed oils", "Limit added sugars", "Peanut allergy", "Vegan".
    var label: String
    /// The worst finding for this choice on this product; OK when none.
    var level: Level

    var id: String { "\(personId)/\(choice)" }

    /// One row per choice per person, owner first, each with the worst finding the engine tied to it.
    static func rows(for household: Household, verdict: HouseholdVerdict, catalog: Catalog) -> [AvoidRow] {
        let byPerson = Dictionary(verdict.people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let people = household.people.sorted { $0.isOwner && !$1.isOwner }
        return people.flatMap { person -> [AvoidRow] in
            let findings = byPerson[person.id]?.findings ?? []
            let noList = findings.contains { $0.source == .missingIngredients }
            return choices(of: person.profile, catalog: catalog).map { choice, label in
                let matched = findings.filter { owns(choice, $0, catalog: catalog) }
                var level = matched.map(\.level).max() ?? .ok
                // Without an ingredient list nothing could be checked for this choice.
                if noList, level == .ok { level = .cantConfirm }
                return AvoidRow(personId: person.id, personName: person.displayName, choice: choice, label: label, level: level)
            }
        }
    }

    /// "1 to avoid · 1 to check", "All OK".
    static func summary(_ rows: [AvoidRow]) -> String {
        let avoid = rows.filter { $0.level == .notFor }.count
        let check = rows.filter { $0.level == .checkFirst }.count
        let unsure = rows.filter { $0.level == .cantConfirm }.count
        var parts: [String] = []
        if avoid > 0 { parts.append("\(avoid) to avoid") }
        if check > 0 { parts.append("\(check) to check") }
        if unsure > 0 { parts.append("\(unsure) can\u{2019}t confirm") }
        return parts.isEmpty ? "All OK" : parts.joined(separator: " \u{00B7} ")
    }

    /// The household for this check only: the switched-off choices removed. Never saved.
    static func household(_ household: Household, without off: Set<String>, rows: [AvoidRow]) -> Household {
        guard !off.isEmpty else { return household }
        var copy = household
        for row in rows where off.contains(row.id) {
            guard let index = copy.people.firstIndex(where: { $0.id == row.personId }) else { continue }
            var profile = copy.people[index].profile
            switch row.choice {
            case .allergen(let id): profile.allergens.removeAll { $0.id == id }
            case .medical(let id): profile.medical.removeAll { $0 == id }
            case .diet(let id): profile.diets.removeAll { $0 == id }
            case .avoid(let id): profile.avoid.removeAll { $0.id == id }
            case .custom(let label): profile.custom.removeAll { $0.label == label }
            }
            copy.people[index].profile = profile
        }
        return copy
    }

    // MARK: private

    private static func choices(of profile: Profile, catalog: Catalog) -> [(Choice, String)] {
        var out: [(Choice, String)] = []
        for a in profile.allergens {
            let name = catalog.family(a.id)?.name ?? a.id
            out.append((.allergen(a.id), name + (a.severity == .allergy ? " allergy" : " intolerance")))
        }
        for m in profile.medical { out.append((.medical(m), catalog.medical[m]?.name ?? m)) }
        for d in profile.diets { out.append((.diet(d), catalog.diets[d]?.name ?? d)) }
        for a in profile.avoid {
            let name = (catalog.family(a.id)?.name ?? a.id).lowercased()
            out.append((.avoid(a.id), (a.strength == .avoid ? "Avoid " : "Limit ") + name))
        }
        for c in profile.custom {
            out.append((.custom(c.label), (c.strength == .avoid ? "Avoid " : "Limit ") + c.label.lowercased()))
        }
        return out
    }

    /// Whether the engine's finding came from this choice (mirrors `VerdictEngine.rules(for:)`).
    static func owns(_ choice: Choice, _ f: Finding, catalog: Catalog) -> Bool {
        switch choice {
        case .allergen(let id):
            guard let r = f.rule, r.kind == .allergy || r.kind == .intolerance else { return false }
            return r.familyId == id || catalog.family(r.familyId)?.parent == id
        case .medical(let id):
            guard let spec = catalog.medical[id] else { return false }
            if let r = f.rule { return r.kind == .medical && (spec.avoid ?? []).contains(r.familyId) }
            return f.nutrient.map { n in (spec.limits ?? []).contains { $0.nutrient == n } } ?? false
        case .diet(let id):
            if let r = f.rule { return r.diet == id }
            guard let spec = catalog.diets[id] else { return false }
            return f.nutrient.map { n in (spec.limits ?? []).contains { $0.nutrient == n } } ?? false
        case .avoid(let id):
            guard let r = f.rule else { return false }
            return r.kind == .preference && r.customTerms == nil && r.familyId == id
        case .custom(let label):
            return f.rule?.familyId == "custom:" + label.lowercased()
        }
    }
}

// MARK: - Key ingredients

/// One row of "Key ingredients": the ingredient, its worst finding across the household and why.
nonisolated struct IngredientRow: Identifiable, Equatable, Sendable {
    var index: Int
    /// As printed, capitalized: "Sunflower oil".
    var name: String
    var level: Level
    /// "Not for you · Avoid seed oils", "OK".
    var tone: String
    /// The open row's line: "The 2nd ingredient. Avoid seed oils, for you."
    var why: String

    var id: Int { index }

    /// How many rows show before "See all".
    static let collapsedCount = 3
    /// Spec 04: with more than this many ingredients, "See all" pushes a full list.
    static let pushListAfter = 40

    static func rows(verdict: HouseholdVerdict, avoidRows: [AvoidRow], catalog: Catalog) -> [IngredientRow] {
        let top = verdict.label.ingredients.filter { $0.parent == nil }
        return top.map { ingredient in
            // Every person's findings on this ingredient, worst first.
            let hits: [(person: PersonVerdict, finding: Finding)] = verdict.people.flatMap { p in
                p.findings.filter { $0.index == ingredient.index }.map { (p, $0) }
            }.sorted { $0.finding.level > $1.finding.level }
            let name = capitalized(ingredient.text)
            let position = Copy.position(ingredient.index)
            guard let worst = hits.first else {
                return IngredientRow(index: ingredient.index, name: name, level: .ok, tone: "OK",
                                     why: capitalized(position) + ". Nothing anyone here avoids.")
            }
            var names: [String] = []
            for hit in hits where hit.finding.level == worst.finding.level && !names.contains(hit.person.name) {
                names.append(hit.person.name)
            }
            let ruleLabel = label(for: worst.finding, person: worst.person, avoidRows: avoidRows, catalog: catalog)
            let tone = [Copy.flag(worst.finding.level, names: names), ruleLabel].compactMap { $0 }.joined(separator: " \u{00B7} ")
            var why = capitalized(position) + "."
            if let extra = worst.finding.why {
                why += " " + extra
            } else if let ruleLabel {
                why += " \(ruleLabel), for \(join(names))."
            }
            return IngredientRow(index: ingredient.index, name: name, level: worst.finding.level, tone: tone, why: why)
        }
    }

    /// The label of the avoid row this finding came from.
    private static func label(for finding: Finding, person: PersonVerdict, avoidRows: [AvoidRow], catalog: Catalog) -> String? {
        avoidRows.first { $0.personId == person.id && AvoidRow.owns($0.choice, finding, catalog: catalog) }?.label
    }

    /// "you", "you and Mia", "you, Mia and Leo".
    static func join(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

// MARK: - Nutrition

/// The nutrition card's numbers: the donut, the two facts and the full facts per serving or per 100 g.
nonisolated enum NutritionFacts {
    enum Basis: String, Hashable, Sendable { case serving, per100g }

    struct Macro: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable { case carbs = "Carbs", fat = "Fat", protein = "Protein" }
        var kind: Kind
        var grams: Double
        var kcal: Double
        /// Share of the macro calories, 0...1.
        var share: Double
        var id: Kind { kind }
        var percent: Int { Int((share * 100).rounded()) }
    }

    struct Row: Equatable, Sendable, Identifiable {
        var label: String
        /// "4.5 g", "120".
        var amount: String
        /// "6%", empty per 100 g or without a daily value.
        var dailyValue: String
        /// Bold top-level rows; sub-rows (saturated fat, fiber, added sugars) are indented.
        var isMain: Bool
        var id: String { label }
    }

    /// 4 kcal per gram of carbs and protein, 9 per gram of fat.
    static func macros(_ n: Nutrition) -> [Macro] {
        let parts: [(Macro.Kind, Double?, Double)] = [(.carbs, n.carbsG, 4), (.fat, n.fatG, 9), (.protein, n.proteinG, 4)]
        let kcal = parts.map { ($0.1 ?? 0) * $0.2 }
        let total = kcal.reduce(0, +)
        guard total > 0 else { return [] }
        return zip(parts, kcal).map { part, k in
            Macro(kind: part.0, grams: part.1 ?? 0, kcal: k, share: k / total)
        }
    }

    /// The number in the donut: the label's calories, else the sum of the macros.
    static func calories(_ n: Nutrition) -> Int? {
        if let kcal = n.kcal { return Int(kcal.rounded()) }
        let sum = macros(n).reduce(0) { $0 + $1.kcal }
        return sum > 0 ? Int(sum.rounded()) : nil
    }

    /// "120 calories per serving. Carbs 64%, fat 33%, protein 3% of calories."
    static func donutLabel(_ n: Nutrition) -> String {
        let kcal = calories(n).map { "\($0) calories per serving." } ?? ""
        let parts = macros(n).map { "\($0.kind.rawValue.lowercased()) \($0.percent)%" }
        guard !parts.isEmpty else { return kcal }
        return kcal + " " + IngredientRow.capitalized(parts.joined(separator: ", ")) + " of calories."
    }

    static func hasAnyValue(_ n: Nutrition) -> Bool {
        [n.kcal, n.fatG, n.satFatG, n.sodiumMg, n.carbsG, n.fiberG, n.addedSugarsG, n.proteinG].contains { $0 != nil }
    }

    /// FDA daily values for a 2,000 kcal day.
    private static let dailyValues: [String: Double] = [
        "Total fat": 78, "Saturated fat": 20, "Sodium": 2300, "Total carbohydrate": 275, "Dietary fiber": 28, "Added sugars": 50,
    ]

    /// The full facts. Per 100 g needs the serving's grams; returns nil without them.
    static func rows(_ n: Nutrition, basis: Basis, servingGrams: Double?) -> [Row]? {
        let factor: Double
        switch basis {
        case .serving: factor = 1
        case .per100g:
            guard let servingGrams, servingGrams > 0 else { return nil }
            factor = 100 / servingGrams
        }
        let lines: [(String, Double?, String, Bool)] = [
            ("Calories", n.kcal, "", true), ("Total fat", n.fatG, "g", true), ("Saturated fat", n.satFatG, "g", false),
            ("Sodium", n.sodiumMg, "mg", true), ("Total carbohydrate", n.carbsG, "g", true),
            ("Dietary fiber", n.fiberG, "g", false), ("Added sugars", n.addedSugarsG, "g", false), ("Protein", n.proteinG, "g", true),
        ]
        return lines.compactMap { label, value, unit, isMain in
            guard let value else { return nil }
            let scaled = basis == .serving ? value : round100(value * factor)
            var dv = ""
            if basis == .serving, let daily = dailyValues[label] { dv = "\(Int((value / daily * 100).rounded()))%" }
            return Row(label: label, amount: format(scaled) + (unit.isEmpty ? "" : " " + unit), dailyValue: dv, isMain: isMain)
        }
    }

    /// Per 100 g values: whole numbers from 50 up, one decimal below (prototype `Main.dc.html`).
    static func round100(_ value: Double) -> Double {
        value >= 50 ? value.rounded() : (value * 10).rounded() / 10
    }

    /// "4.5", "4", "105".
    static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// The grams in a serving size: "28 g (about 15 chips)" → 28. nil for "1 cup".
    static func grams(inServing servingSize: String?) -> Double? {
        guard let text = servingSize?.lowercased() else { return nil }
        return ProductHeader.number(before: "g", in: text)
    }

    /// Whether a rule cares about this nutrient, so its fact is flagged amber.
    static func isFlagged(_ nutrient: Nutrient, verdict: HouseholdVerdict) -> Bool {
        verdict.people.flatMap(\.findings).contains { f in
            if f.nutrient == nutrient && f.level != .ok { return true }
            // An added-sugar rule matched an ingredient ("cane sugar" under "Limit added sugars").
            return nutrient == .addedSugarsG && f.rule?.familyId == "sugar"
        }
    }
}
