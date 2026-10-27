import Foundation
import LabelSageCore

// Compare's logic, apart from the views (spec 05): which side is better, the why lines, the key
// ingredient and nutrition rows. Every level here comes from `VerdictEngine` through `VerdictService`.

/// One side of the comparison.
nonisolated enum CompareSide: Hashable, Sendable {
    case left, right
}

/// One line of the why card: a level symbol and a sentence.
nonisolated struct CompareWhyLine: Hashable, Sendable {
    var level: Level
    var text: String
}

/// One row of a compare table (key ingredients or nutrition).
nonisolated struct CompareRow: Identifiable, Equatable, Sendable {
    /// "Avoid seed oils, for you", "Sodium".
    var label: String
    var left: String
    var right: String
    /// Engine levels for ingredient cells; nil for nutrition.
    var leftLevel: Level?
    var rightLevel: Level?
    /// The side with the better value; nil when equal or not comparable.
    var better: CompareSide?
    /// Counted in "3 of 4 differ" and shown in Differences. Missing data on one side is not a difference.
    var differs: Bool

    var id: String { label }

    /// "Sodium: Crunchwell 105 mg, Canyon Kettle 140 mg. Crunchwell is better."
    func spoken(leftName: String, rightName: String) -> String {
        var text = "\(label): \(leftName) \(left), \(rightName) \(right)."
        if let better { text += " \(better == .left ? leftName : rightName) is better." }
        return text
    }
}

/// Everything Compare shows for two products and one household.
nonisolated struct CompareSummary: Equatable, Sendable {
    var left: ProductOption
    var right: ProductOption
    /// The side with the better household verdict; nil when both have the same level.
    var better: CompareSide?
    var whyTitle: String
    /// At most three.
    var whyLines: [CompareWhyLine]
    var ingredientRows: [CompareRow]
    var nutritionRows: [CompareRow]
    /// "Per 28 g serving", or "Per serving" when a serving's grams are unknown.
    var servingNote: String

    static let maxWhyLines = 3

    var isSameProduct: Bool { left.product.id == right.product.id }
    /// The product in the bottom bar and the one "Save to go-tos" saves: the better one, else the picked one.
    var barSide: CompareSide { better ?? .right }

    func option(_ side: CompareSide) -> ProductOption { side == .left ? left : right }

    /// The short name in table headers and sentences: the brand, else the name.
    static func shortName(_ product: Product) -> String {
        let brand = product.brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return brand.isEmpty ? product.name : brand
    }

    static func make(left: ProductOption, right: ProductOption, household: Household, catalog: Catalog) -> CompareSummary {
        let better: CompareSide? = left.verdict.overall == right.verdict.overall ? nil
            : (left.verdict.overall < right.verdict.overall ? .left : .right)
        let serving = Serving(left.product, right.product)
        let nutrition = nutritionRows(left.product, right.product, serving: serving)
        return CompareSummary(
            left: left, right: right, better: better,
            whyTitle: whyTitle(better.map { $0 == .left ? left : right }),
            whyLines: whyLines(left: left, right: right, better: better, nutrition: nutrition, catalog: catalog),
            ingredientRows: ingredientRows(left: left, right: right, household: household, catalog: catalog),
            nutritionRows: nutrition,
            servingNote: serving.note
        )
    }

    /// "3 of 4 differ".
    static func differCount(_ rows: [CompareRow]) -> String {
        "\(rows.filter(\.differs).count) of \(rows.count) differ"
    }

    // MARK: Why card

    static func whyTitle(_ better: ProductOption?) -> String {
        guard let better else { return "How they differ" }
        let name = shortName(better.product)
        return better.verdict.overall == .ok ? "Why \(name) works for you" : "Why \(name) is the better pick"
    }

    /// Engine findings first, then one nutrition trade-off. A Can't confirm side leads.
    static func whyLines(left: ProductOption, right: ProductOption, better: CompareSide?,
                         nutrition: [CompareRow], catalog: Catalog) -> [CompareWhyLine] {
        var lines: [CompareWhyLine] = []
        for option in [left, right] where option.verdict.overall == .cantConfirm {
            let other = option == left ? right : left
            guard other.verdict.overall != .cantConfirm else { continue }
            let reason = ProductPage.worst(in: option.verdict)?.reason ?? ""
            lines.append(CompareWhyLine(level: .cantConfirm,
                                        text: "Can\u{2019}t confirm \(shortName(option.product)): \(lowerFirst(reason))"))
        }
        guard let better else {
            if lines.isEmpty {
                lines.append(CompareWhyLine(level: left.verdict.overall, text: "Same verdict for both: \(left.verdict.line)."))
            }
            return Array(lines.prefix(maxWhyLines))
        }
        let winner = better == .left ? left : right
        let loser = better == .left ? right : left
        // What the worse one has that the better one does not, one line per rule.
        let winnerFamilies = Set(findings(winner.verdict).compactMap(\.rule?.familyId))
        var seen: Set<String> = []
        for finding in findings(loser.verdict) {
            guard let rule = finding.rule, !winnerFamilies.contains(rule.familyId), seen.insert(rule.familyId).inserted,
                  finding.source != .missingIngredients else { continue }
            let family = (catalog.family(rule.familyId)?.name ?? rule.familyId).lowercased()
            let matched = finding.matched ?? family
            lines.append(CompareWhyLine(level: .ok, text: "No \(family). \(shortName(loser.product)) has \(matched)."))
        }
        // One trade-off: the better one has more calories.
        if let calories = nutrition.first(where: { $0.label == "Calories" }), calories.differs,
           calories.better != nil, calories.better != better {
            let mine = better == .left ? calories.left : calories.right
            let theirs = better == .left ? calories.right : calories.left
            lines.append(CompareWhyLine(level: .checkFirst,
                                        text: "Trade-off: more calories, \(mine) kcal vs \(theirs) kcal per serving."))
        }
        return Array(lines.prefix(maxWhyLines))
    }

    private static func findings(_ verdict: HouseholdVerdict) -> [Finding] {
        verdict.people.flatMap(\.findings).filter { $0.level != .ok }.sorted { $0.level > $1.level }
    }

    private static func lowerFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    // MARK: Key ingredients

    /// One row per thing someone avoids (the "What you avoid" choices): the matched ingredient on each
    /// side, or "None", colored by the engine's level for that choice.
    static func ingredientRows(left: ProductOption, right: ProductOption, household: Household, catalog: Catalog) -> [CompareRow] {
        let leftRows = AvoidRow.rows(for: household, verdict: left.verdict, catalog: catalog)
        let rightRows = AvoidRow.rows(for: household, verdict: right.verdict, catalog: catalog)
        let showsPerson = household.people.count > 1
        return zip(leftRows, rightRows).map { a, b in
            let leftText = cell(a, verdict: left.verdict, catalog: catalog)
            let rightText = cell(b, verdict: right.verdict, catalog: catalog)
            let better: CompareSide? = a.level == b.level ? nil : (a.level < b.level ? .left : .right)
            return CompareRow(label: showsPerson ? "\(a.label), for \(a.personName)" : a.label,
                              left: leftText, right: rightText, leftLevel: a.level, rightLevel: b.level,
                              better: better, differs: a.level != b.level || leftText != rightText)
        }
    }

    private static func cell(_ row: AvoidRow, verdict: HouseholdVerdict, catalog: Catalog) -> String {
        guard verdict.label.hasList else { return "No list" }
        let findings = verdict.people.first { $0.id == row.personId }?.findings ?? []
        var words: [String] = []
        for f in findings where f.level != .ok && AvoidRow.owns(row.choice, f, catalog: catalog) {
            let word = IngredientRow.capitalized(f.matched ?? row.label)
            if !words.contains(word) { words.append(word) }
        }
        return words.isEmpty ? "None" : words.joined(separator: ", ")
    }

    // MARK: Nutrition

    /// Both sides at the smaller serving's grams (spec 05 "Different serving sizes").
    struct Serving: Equatable, Sendable {
        var leftFactor: Double = 1
        var rightFactor: Double = 1
        var note = "Per serving"

        init(_ left: Product, _ right: Product) {
            let a = NutritionFacts.grams(inServing: left.servingSize)
            let b = NutritionFacts.grams(inServing: right.servingSize)
            guard let a, let b, a > 0, b > 0 else { return }
            let target = min(a, b)
            leftFactor = target / a
            rightFactor = target / b
            note = "Per \(NutritionFacts.format(target)) g serving"
        }
    }

    private struct Line: Sendable {
        var label: String
        var unit: String
        var lowerIsBetter: Bool
        var value: @Sendable (Product) -> Double?
        /// NOVA is a group, not an amount: it is never scaled.
        var scales = true
    }

    // shortcut: fixed directions (less is better except fiber and protein). Upgrade to read the household's
    // avoid choices and goals once the engine exposes them per nutrient (Q-T10-4).
    private static let lines: [Line] = [
        Line(label: "Calories", unit: "", lowerIsBetter: true) { $0.nutrition?.kcal },
        Line(label: "Total fat", unit: " g", lowerIsBetter: true) { $0.nutrition?.fatG },
        Line(label: "Saturated fat", unit: " g", lowerIsBetter: true) { $0.nutrition?.satFatG },
        Line(label: "Sodium", unit: " mg", lowerIsBetter: true) { $0.nutrition?.sodiumMg },
        Line(label: "Carbohydrate", unit: " g", lowerIsBetter: true) { $0.nutrition?.carbsG },
        Line(label: "Fiber", unit: " g", lowerIsBetter: false) { $0.nutrition?.fiberG },
        Line(label: "Added sugar", unit: " g", lowerIsBetter: true) { $0.nutrition?.addedSugarsG },
        Line(label: "Protein", unit: " g", lowerIsBetter: false) { $0.nutrition?.proteinG },
        Line(label: "Processing", unit: "", lowerIsBetter: true, value: { $0.nova.map(Double.init) }, scales: false),
    ]

    static func nutritionRows(_ left: Product, _ right: Product, serving: Serving) -> [CompareRow] {
        lines.map { line in
            let a = line.value(left).map { round1($0 * (line.scales ? serving.leftFactor : 1)) }
            let b = line.value(right).map { round1($0 * (line.scales ? serving.rightFactor : 1)) }
            var better: CompareSide?
            if let a, let b, a != b {
                better = (a < b) == line.lowerIsBetter ? .left : .right
            }
            return CompareRow(label: line.label, left: text(a, line), right: text(b, line),
                              better: better, differs: better != nil)
        }
    }

    private static func text(_ value: Double?, _ line: Line) -> String {
        guard let value else { return "No data" }
        return line.scales ? NutritionFacts.format(value) + line.unit : "NOVA \(Int(value))"
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}

// MARK: - Compare with

nonisolated enum CompareWithLogic {
    /// "Other options": not the base product, never Not for, OK for everyone first, then the rest.
    static func offered(_ options: [ProductOption], base: Product) -> [ProductOption] {
        let shown = options.filter { $0.id != base.id && $0.verdict.overall != .notFor }
        return shown.filter { $0.verdict.overall == .ok } + shown.filter { $0.verdict.overall != .ok }
    }

    /// The deciding attribute on the right of an option row: the matched ingredient when it is not OK,
    /// else the option's ingredient in the place where the base product's worst finding sits
    /// ("Olive oil" where the base has sunflower oil).
    static func decidingAttribute(_ option: ProductOption, base: HouseholdVerdict) -> String? {
        if option.verdict.overall != .ok {
            let worst = option.verdict.people.flatMap(\.findings).max { $0.level < $1.level }
            return worst?.matched.map(IngredientRow.capitalized)
        }
        guard let index = base.people.flatMap(\.findings).filter({ $0.level != .ok }).max(by: { $0.level < $1.level })?.index,
              let ingredient = option.verdict.label.ingredients.first(where: { $0.parent == nil && $0.index == index })
        else { return nil }
        return IngredientRow.capitalized(ingredient.text)
    }
}
