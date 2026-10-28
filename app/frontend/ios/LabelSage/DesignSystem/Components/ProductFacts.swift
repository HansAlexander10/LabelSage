import Foundation
import LabelSageCore

/// What a product card or tile says about a product, from the product data and the engine's findings
/// only (no model text): the reason chips, the nutrition line and the spoken label. Kept apart from the
/// views so it can be unit tested (ProductFactsTests).
nonisolated enum ProductFacts {
    /// Protein per serving at or above this shows as a good fact ("17 g protein").
    static let proteinChipFrom: Double = 10
    /// A list this short shows as a good fact ("3 ingredients").
    static let shortListUpTo = 5

    /// Reason chips, worst first: what decided Not for (red), what to check (amber), what can't be
    /// confirmed, then good facts (green): "No seed oils listed" for an avoid choice the engine found nothing
    /// for, "17 g protein", "3 ingredients", "No added sugar". Good facts need an ingredient list.
    static func notes(product: Product, verdict: HouseholdVerdict, household: Household?, catalog: Catalog,
                      limit: Int = 3) -> [ProductRow.Note] {
        var seen = Set<String>()
        var notes: [ProductRow.Note] = []
        func add(_ level: Level, _ text: String) {
            guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { return }
            notes.append(ProductRow.Note(level: level, text: text))
        }

        let findings = verdict.people.flatMap(\.findings).filter { $0.level != .ok }.sorted { $0.level > $1.level }
        for finding in findings {
            if let text = findingText(finding) { add(finding.level, text) }
        }

        if verdict.label.hasList {
            if let household {
                for row in AvoidRow.rows(for: household, verdict: verdict, catalog: catalog) where row.level == .ok {
                    guard case .avoid = row.choice, row.label.hasPrefix("Avoid ") else { continue }
                    // "listed": says what was checked, never a "free from" promise (D-31).
                    add(.ok, "No " + row.label.dropFirst("Avoid ".count) + " listed")
                }
            }
            if let protein = product.nutrition?.proteinG, protein >= proteinChipFrom {
                add(.ok, "\(NutritionFacts.format(protein)) g protein")
            }
            let count = verdict.label.ingredients.filter { $0.parent == nil }.count
            if count > 0, count <= shortListUpTo {
                add(.ok, count == 1 ? "1 ingredient" : "\(count) ingredients")
            }
            if product.nutrition?.addedSugarsG == 0 {
                add(.ok, "No added sugar")
            }
        }
        return Array(notes.prefix(max(0, limit)))
    }

    /// The chip for one finding: the matched ingredient ("Sunflower oil"), the amount over a limit
    /// ("12 g added sugar"), or what is missing.
    static func findingText(_ finding: Finding) -> String? {
        switch finding.source {
        case .missingIngredients:
            return "No ingredient list"
        case .missingNutrient:
            return finding.nutrient.map { "No \(words($0).name) value" }
        case .limit:
            guard let nutrient = finding.nutrient, let value = finding.value, value.isFinite else { return nil }
            let w = words(nutrient)
            return "\(NutritionFacts.format(value)) \(w.unit) \(w.name)"
        case .ingredients, .contains, .mayContain, .ambiguous:
            guard let matched = finding.matched, !matched.isEmpty else { return nil }
            let text = IngredientRow.capitalized(matched)
            return finding.source == .mayContain ? "May contain \(matched)" : text
        }
    }

    /// "120 kcal · 17 g protein · 4 g added sugar per serving". nil without any of the three.
    static func nutritionLine(_ nutrition: Nutrition?) -> String? {
        guard let n = nutrition else { return nil }
        var parts: [String] = []
        if let kcal = NutritionFacts.calories(n) { parts.append("\(kcal) kcal") }
        if let protein = n.proteinG { parts.append("\(NutritionFacts.format(protein)) g protein") }
        if let sugar = n.addedSugarsG { parts.append("\(NutritionFacts.format(sugar)) g added sugar") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " \u{00B7} ") + " per serving"
    }

    /// One VoiceOver label per card or tile: name, verdict line, price, then the chips and extras.
    static func spokenLabel(name: String, verdictLine: String, price: String?, notes: [String],
                            extra: [String?] = []) -> String {
        ([name, verdictLine.replacingOccurrences(of: " \u{00B7} ", with: ", "), price] + notes + extra)
            .compactMap { $0?.replacingOccurrences(of: " \u{00B7} ", with: ", ") }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private static func words(_ nutrient: Nutrient) -> (name: String, unit: String) {
        switch nutrient {
        case .sodiumMg: ("sodium", "mg")
        case .addedSugarsG: ("added sugar", "g")
        case .netCarbsG: ("net carbs", "g")
        }
    }
}
