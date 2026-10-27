import Foundation

public enum Nutrient: String, Codable, Sendable {
    case sodiumMg, addedSugarsG, netCarbsG

    var words: (name: String, unit: String) {
        switch self {
        case .sodiumMg: ("sodium", "mg")
        case .addedSugarsG: ("added sugar", "g")
        case .netCarbsG: ("net carbs", "g")
        }
    }
}

/// One thing a person avoids, expanded from their profile.
public struct Rule: Sendable, Equatable {
    public enum Kind: String, Sendable { case allergy, intolerance, medical, diet, religion, preference }
    public var familyId: String
    public var strength: Strength
    public var kind: Kind
    public var mayContain: Bool
    public var diet: String?
    /// Only for custom rules: the terms the person confirmed.
    public var customTerms: [String]?
}

public struct LimitRule: Sendable, Equatable {
    public var nutrient: Nutrient
    public var perDay: Double
}

public struct Finding: Sendable, Equatable {
    public enum Source: String, Sendable { case ingredients, contains, mayContain, ambiguous, missingIngredients, missingNutrient, limit }
    public var level: Level
    public var source: Source
    public var rule: Rule?
    /// The family that owns the matched term ("almond" when the rule is "treenuts" and the label says praline).
    public var ownerFamilyId: String?
    /// The matched words, normalized ("whey", "sunflower oil").
    public var matched: String?
    /// 1-based position in the ingredient list ("the 2nd ingredient").
    public var index: Int?
    public var why: String?
    public var nutrient: Nutrient?
    public var value: Double?
}

public struct PersonVerdict: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var level: Level
    /// Worst first, then by position in the list.
    public var findings: [Finding]
    /// The deterministic reason line shown under the flag. The on-device model may rewrite it later, never the level.
    public var reason: String
}

public struct HouseholdVerdict: Sendable, Equatable {
    /// The worst level across everyone. Drives the photo signal and the mascot pose.
    public var overall: Level
    /// "Not for Mia · OK for you", "OK for everyone".
    public var line: String
    public var people: [PersonVerdict]
    public var label: ParsedLabel
}

/// Deterministic: same product + same household = same answer, offline, no model involved.
/// "Code decides, LabelSage explains."
public struct VerdictEngine: Sendable {
    /// A serving over 20% of a daily limit is "Check first" (FDA: 20% DV or more is high). Open question Q4.
    public var servingShare: Double = 0.2
    public let catalog: Catalog

    public init(catalog: Catalog) { self.catalog = catalog }

    public func check(_ product: Product, for household: Household) -> HouseholdVerdict {
        let label = LabelParser.parse(product, catalog: catalog)
        let people = household.people.enumerated()
            .sorted { a, b in a.element.isOwner != b.element.isOwner ? a.element.isOwner : a.offset < b.offset }
            .map(\.element)
        let per = people.map { evaluate($0, product: product, label: label) }
        let overall = per.map(\.level).max() ?? .ok
        return HouseholdVerdict(overall: overall, line: Copy.householdLine(per), people: per, label: label)
    }

    // MARK: rules

    public func rules(for profile: Profile) -> (rules: [Rule], limits: [LimitRule]) {
        var rules: [Rule] = []
        var limits: [LimitRule] = []
        for a in profile.allergens {
            let kind: Rule.Kind = a.severity == .allergy ? .allergy : .intolerance
            for fid in (a.leaves?.isEmpty == false ? a.leaves! : [a.id]) {
                rules.append(Rule(familyId: fid, strength: .avoid, kind: kind, mayContain: profile.mayContain && a.severity == .allergy))
            }
        }
        for m in profile.medical {
            guard let spec = catalog.medical[m] else { continue }
            for fid in spec.avoid ?? [] {
                rules.append(Rule(familyId: fid, strength: .avoid, kind: .medical, mayContain: profile.mayContain))
            }
            limits += (spec.limits ?? []).map { LimitRule(nutrient: $0.nutrient, perDay: $0.perDay) }
        }
        for d in profile.diets {
            guard let spec = catalog.diets[d] else { continue }
            let kind: Rule.Kind = ["halal", "kosher", "nobeef"].contains(d) ? .religion : .diet
            for fid in spec.avoid ?? [] {
                rules.append(Rule(familyId: fid, strength: .avoid, kind: kind, mayContain: false, diet: d))
            }
            limits += (spec.limits ?? []).map { LimitRule(nutrient: $0.nutrient, perDay: $0.perDay) }
        }
        for a in profile.avoid {
            rules.append(Rule(familyId: a.id, strength: a.strength, kind: .preference, mayContain: false))
        }
        for c in profile.custom {
            rules.append(Rule(familyId: "custom:" + c.label.lowercased(), strength: c.strength, kind: .preference,
                              mayContain: false, customTerms: c.terms))
        }
        return (rules, limits)
    }

    func match(_ rule: Rule, in phrase: String) -> (owner: String, words: String)? {
        if let terms = rule.customTerms {
            return Matcher.firstMatch(terms: terms.map { ($0, rule.familyId) }, notTerms: [], in: phrase, negations: catalog.negationSuffixes)
        }
        return catalog.match(familyId: rule.familyId, in: phrase)
    }

    // MARK: evaluation (mirrors evaluate_person in tools/reference_engine.py)

    func evaluate(_ person: Person, product: Product, label: ParsedLabel) -> PersonVerdict {
        let (rules, limits) = self.rules(for: person.profile)
        var findings: [Finding] = []
        let hasList = label.hasList
        let containsNorm = label.containsNorm
        let mayNorm = label.mayContainNorm

        for r in rules where hasList {
            // 1. the ingredient list, then the Contains line
            var hit: Finding?
            for it in label.ingredients {
                if let m = match(r, in: it.norm) {
                    hit = Finding(level: r.strength == .avoid ? .notFor : .checkFirst, source: .ingredients, rule: r,
                                  ownerFamilyId: m.owner, matched: m.words, index: it.index)
                    break
                }
            }
            if hit == nil {
                for p in containsNorm {
                    if let m = match(r, in: p) {
                        hit = Finding(level: r.strength == .avoid ? .notFor : .checkFirst, source: .contains, rule: r,
                                      ownerFamilyId: m.owner, matched: m.words)
                        break
                    }
                }
            }
            if let hit { findings.append(hit); continue }

            // 2. "may contain": only for allergies and medical diets (cross-contamination)
            var mayHit = false
            if r.kind == .allergy || r.kind == .medical {
                for p in mayNorm {
                    if let m = match(r, in: p) {
                        findings.append(Finding(level: r.mayContain ? .notFor : .checkFirst, source: .mayContain, rule: r,
                                                ownerFamilyId: m.owner, matched: m.words))
                        mayHit = true
                        break
                    }
                }
            }
            if mayHit || r.strength != .avoid { continue }

            // 3. terms whose source the label doesn't say: Can't confirm, never OK
            let targets = Set([r.familyId] + catalog.ancestors(r.familyId))
            for (amb, table) in zip(catalog.ambiguous, catalog.ambiguousTables) {
                let overlap = Set(amb.couldBe).intersection(targets)
                if overlap.isEmpty { continue }
                if overlap.isSubset(of: catalog.majors) && label.hasContainsStatement { continue }
                if let it = label.ingredients.first(where: {
                    Matcher.firstMatch(table, in: $0.norm, negations: catalog.negationSuffixes) != nil
                }) {
                    let m = Matcher.firstMatch(table, in: it.norm, negations: catalog.negationSuffixes)
                    findings.append(Finding(level: .cantConfirm, source: .ambiguous, rule: r, matched: m?.words, index: it.index, why: amb.why))
                    break
                }
            }
        }
        if !hasList && (!rules.isEmpty || !limits.isEmpty) {
            findings.append(Finding(level: .cantConfirm, source: .missingIngredients))
        }
        for l in limits {
            guard let v = product.nutrition?.value(l.nutrient) else {
                findings.append(Finding(level: .cantConfirm, source: .missingNutrient, nutrient: l.nutrient))
                continue
            }
            if v > l.perDay * servingShare {
                findings.append(Finding(level: .checkFirst, source: .limit, nutrient: l.nutrient, value: v))
            }
        }
        // stable: worst first, then by position, then in the order found
        findings = findings.enumerated().sorted { a, b in
            if a.element.level != b.element.level { return a.element.level > b.element.level }
            let ia = a.element.index ?? 999, ib = b.element.index ?? 999
            return ia != ib ? ia < ib : a.offset < b.offset
        }.map(\.element)
        let level = findings.first?.level ?? .ok
        return PersonVerdict(id: person.id, name: person.displayName, level: level, findings: findings,
                             reason: Copy.reason(for: person, level: level, finding: findings.first, catalog: catalog))
    }
}
