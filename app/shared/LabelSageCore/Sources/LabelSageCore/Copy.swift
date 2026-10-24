import Foundation

/// Deterministic lines. Rules (docs/voice-and-strings.md): name the person, name the ingredient,
/// never "safe", one idea per line, a verdict in five words or fewer.
/// English only for the MVP; move these into a String Catalog with the same keys when localizing.
public enum Copy {
    /// The flag text: "OK for Mia", "Check first", "Not for Mia", "Can’t confirm".
    public static func flag(_ level: Level, names: [String]) -> String {
        switch level {
        case .ok: "OK for \(join(names))"
        case .checkFirst: "Check first"
        case .cantConfirm: "Can’t confirm"
        case .notFor: "Not for \(join(names))"
        }
    }

    /// One line for everyone: worst first. "Not for Mia · OK for you". "Check first for you · OK for Mia".
    /// "OK for everyone" with 3+ people all OK. A level everyone shares has no names: "Can’t confirm".
    public static func householdLine(_ people: [PersonVerdict]) -> String {
        var segments: [String] = []
        for level in [Level.notFor, .cantConfirm, .checkFirst, .ok] {
            let names = people.filter { $0.level == level }.map(\.name)
            if names.isEmpty { continue }
            if level == .ok && names.count == people.count && people.count >= 3 {
                segments.append("OK for everyone")
            } else if (level == .checkFirst || level == .cantConfirm) && names.count < people.count {
                segments.append(flag(level, names: names) + " for " + join(names))  // "Check first for you · OK for Mia"
            } else {
                segments.append(flag(level, names: names))
            }
        }
        return segments.joined(separator: " · ")
    }

    static func join(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    static func familyName(_ catalog: Catalog, _ id: String) -> String {
        (catalog.family(id)?.name ?? id).lowercased()
    }

    /// The reason under the flag, for one person. Mirrors reason_line in tools/reference_engine.py.
    public static func reason(for person: Person, level: Level, finding f: Finding?, catalog: Catalog) -> String {
        let who = person.displayName
        guard level != .ok, let f else {
            return who == "you" ? "OK for you. Nothing you avoid is in it." : "OK for \(who). Nothing \(who) avoids is in it."
        }
        switch f.source {
        case .missingIngredients:
            return "Can’t confirm. No ingredient list for this one yet."
        case .missingNutrient:
            return "Can’t confirm. No \(f.nutrient?.words.name ?? "") value on the label."
        case .limit:
            let n = f.nutrient?.words ?? (name: "", unit: "")
            let v = (f.value ?? 0).isFinite ? (f.value ?? 0) : 0
            let shown = v.rounded() == v ? String(Int(v)) : String(v)
            return "Check first: \(shown) \(n.unit) \(n.name) per serving."
        case .ambiguous:
            return "Can’t confirm. \(f.why ?? "")"
        case .mayContain:
            let m = f.matched ?? ""
            return level == .notFor ? "Not for \(who). May contain \(m)." : "Check first: says ‘may contain \(m)’."
        case .ingredients, .contains:
            break
        }
        guard let r = f.rule else { return "" }
        let m = f.matched ?? ""
        switch r.kind {
        case .allergy, .intolerance, .medical:
            // Name the hidden form: "Contains whey: that’s milk."
            let named = familyName(catalog, f.ownerFamilyId ?? r.familyId)
            let words = m.split(separator: " ").map(String.init)
            let same = " \(m) ".contains(" \(named) ") || words.contains { strip($0) == strip(named) }
            return same ? "Not for \(who). Contains \(m)." : "Not for \(who). Contains \(m): that’s \(named)."
        case .diet, .religion:
            let template = r.diet.flatMap { catalog.diets[$0]?.reason } ?? "{ingredient} isn’t allowed"
            return "Not for \(who): " + template.replacingOccurrences(of: "{ingredient}", with: m) + "."
        case .preference:
            let isA = r.customTerms == nil ? catalog.family(r.familyId)?.isA : nil
            if level == .notFor {
                guard let isA, m != isA else { return "Not for \(who). Contains \(m)." }
                return "Not for \(who): \(m) is \(isA)."
            }
            guard let isA, m != isA else { return "Check first: contains \(m)." }
            return "Check first: \(m) is \(isA)."
        }
    }

    /// Python's rstrip("s")
    static func strip(_ s: String) -> String {
        var t = s
        while t.hasSuffix("s") { t.removeLast() }
        return t
    }

    /// "the 2nd ingredient"
    public static func position(_ index: Int) -> String { "the \(Text.ordinal(index)) ingredient" }
}
