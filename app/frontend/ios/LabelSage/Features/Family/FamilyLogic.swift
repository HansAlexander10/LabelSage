import Foundation
import LabelSageCore

/// One choice in a person's profile, with everything needed to put it back after it was switched off.
nonisolated enum FamilyChoice: Equatable, Sendable {
    case allergen(AllergenChoice)
    case medical(String)
    case diet(String)
    case avoid(AvoidChoice)
    case custom(CustomChoice)

    /// Stable identity of the choice, independent of its strength or severity.
    var key: String {
        switch self {
        case .allergen(let a): "allergen:\(a.id)"
        case .medical(let id): "medical:\(id)"
        case .diet(let id): "diet:\(id)"
        case .avoid(let a): "avoid:\(a.id)"
        case .custom(let c): "custom:\(c.label.lowercased())"
        }
    }

    /// Avoid ↔ Prefer not for a preference; anything else stays as it is.
    var flipped: FamilyChoice {
        switch self {
        case .avoid(var a): a.strength = a.strength == .avoid ? .preferNot : .avoid; return .avoid(a)
        case .custom(var c): c.strength = c.strength == .avoid ? .preferNot : .avoid; return .custom(c)
        case .allergen, .medical, .diet: return self
        }
    }

    /// Allergies and medical diets are always Avoid; only preferences flip (spec 06 accessibility).
    var isFlippable: Bool {
        switch self {
        case .avoid, .custom: true
        case .allergen, .medical, .diet: false
        }
    }
}

/// A choice that was switched off: kept on screen but out of the household the engine sees.
nonisolated struct ParkedChoice: Equatable, Sendable {
    var choice: FamilyChoice
    /// Its position in its profile array when it was switched off, so it goes back to the same place.
    var position: Int
}

/// One row of an open person card.
nonisolated struct FamilyItem: Identifiable, Equatable, Sendable {
    var choice: FamilyChoice
    var iconKey: String
    var title: String
    var detail: String
    var kind: KindBadge.Kind
    var isOn: Bool

    var id: String { choice.key }
}

/// The rules behind the Family screen, apart from the views.
nonisolated enum FamilyLogic {
    // MARK: Items

    /// Every choice of a profile, switched-off ones in their old place.
    static func items(for profile: Profile, parked: [ParkedChoice], catalog: Catalog) -> [FamilyItem] {
        var shown = profile
        for p in parked.sorted(by: { $0.position < $1.position }) { insert(p.choice, into: &shown, at: p.position) }
        let off = Set(parked.map(\.choice.key))
        return choices(of: shown).map { item($0, profile: shown, isOn: !off.contains($0.key), catalog: catalog) }
    }

    /// The profile's choices in display order: allergies, medical, diets, avoid, custom.
    static func choices(of profile: Profile) -> [FamilyChoice] {
        profile.allergens.map(FamilyChoice.allergen) + profile.medical.map(FamilyChoice.medical)
            + profile.diets.map(FamilyChoice.diet) + profile.avoid.map(FamilyChoice.avoid)
            + profile.custom.map(FamilyChoice.custom)
    }

    private static func item(_ choice: FamilyChoice, profile: Profile, isOn: Bool, catalog: Catalog) -> FamilyItem {
        switch choice {
        case .allergen(let a):
            let family = catalog.family(a.id)
            let word = a.severity == .allergy ? "Allergy" : "Intolerance"
            var detail = word
            if let children = family?.children, !children.isEmpty {
                let names = (a.leaves ?? Array(children.prefix(3))).map { (catalog.family($0)?.name ?? $0).lowercased() }
                detail += " \u{00B7} " + (a.leaves == nil ? names.joined(separator: ", ") + " and the rest" : join(names))
            } else if a.severity == .allergy, profile.mayContain {
                detail += " \u{00B7} \u{201C}may contain\u{201D} too"
            }
            return FamilyItem(choice: choice, iconKey: family?.icon ?? a.id, title: family?.name ?? a.id,
                              detail: detail, kind: .avoid, isOn: isOn)
        case .medical(let id):
            let spec = catalog.medical[id]
            return FamilyItem(choice: choice, iconKey: spec?.icon ?? id, title: spec?.name ?? id,
                              detail: "Medical", kind: .avoid, isOn: isOn)
        case .diet(let id):
            let spec = catalog.diets[id]
            return FamilyItem(choice: choice, iconKey: spec?.icon ?? id, title: spec?.name ?? id,
                              detail: "Diet", kind: .diet, isOn: isOn)
        case .avoid(let a):
            let family = catalog.family(a.id)
            let terms = (family?.terms ?? []).prefix(3)
            let detail = terms.isEmpty ? "" : capitalized(terms.joined(separator: ", ")) + " and similar"
            return FamilyItem(choice: choice, iconKey: family?.icon ?? a.id, title: family?.name ?? a.id,
                              detail: detail, kind: a.strength == .avoid ? .avoid : .preferNot, isOn: isOn)
        case .custom(let c):
            return FamilyItem(choice: choice, iconKey: c.label.lowercased(), title: capitalized(c.label),
                              detail: capitalized(join(c.terms)), kind: c.strength == .avoid ? .avoid : .preferNot, isOn: isOn)
        }
    }

    // MARK: Profile changes

    /// Removes a choice; returns its position so it can go back to the same place.
    @discardableResult
    static func remove(_ key: String, from profile: inout Profile) -> ParkedChoice? {
        func take<T>(_ array: inout [T], _ make: (T) -> FamilyChoice) -> ParkedChoice? {
            guard let index = array.firstIndex(where: { make($0).key == key }) else { return nil }
            return ParkedChoice(choice: make(array.remove(at: index)), position: index)
        }
        return take(&profile.allergens, FamilyChoice.allergen) ?? take(&profile.medical, FamilyChoice.medical)
            ?? take(&profile.diets, FamilyChoice.diet) ?? take(&profile.avoid, FamilyChoice.avoid)
            ?? take(&profile.custom, FamilyChoice.custom)
    }

    static func insert(_ choice: FamilyChoice, into profile: inout Profile, at position: Int) {
        func put<T>(_ value: T, _ array: inout [T]) { array.insert(value, at: min(max(position, 0), array.count)) }
        switch choice {
        case .allergen(let a): put(a, &profile.allergens)
        case .medical(let id): put(id, &profile.medical)
        case .diet(let id): put(id, &profile.diets)
        case .avoid(let a): put(a, &profile.avoid)
        case .custom(let c): put(c, &profile.custom)
        }
    }

    /// Avoid ↔ Prefer not for a preference. Allergies, medical and diets stay as they are.
    static func flip(_ key: String, in profile: inout Profile) {
        if let i = profile.avoid.firstIndex(where: { FamilyChoice.avoid($0).key == key }) {
            profile.avoid[i].strength = profile.avoid[i].strength == .avoid ? .preferNot : .avoid
        } else if let i = profile.custom.firstIndex(where: { FamilyChoice.custom($0).key == key }) {
            profile.custom[i].strength = profile.custom[i].strength == .avoid ? .preferNot : .avoid
        }
    }

    // MARK: Copy

    /// "I check every product for you and Mia." Owner first; "for you." alone.
    static func headerLine(_ people: [Person]) -> String {
        let names = people.sorted { $0.isOwner && !$1.isOwner }.map(\.displayName)
        return names.isEmpty ? "Add who you shop for." : "I check every product for \(join(names))."
    }

    /// "Remove peanut from Mia’s allergies?", "Remove seed oils from what you avoid?"
    static func removeQuestion(_ item: FamilyItem, person: Person) -> String {
        let thing = item.title.lowercased()
        let whose = person.isOwner ? "your" : "\(person.name)\u{2019}s"
        switch item.choice {
        case .allergen, .medical: return "Remove \(thing) from \(whose) allergies?"
        case .diet: return "Remove \(thing) from \(whose) diets?"
        case .avoid, .custom:
            return "Remove \(thing) from what \(person.isOwner ? "you avoid" : "\(person.name) avoids")?"
        }
    }

    /// The person line under a go-to that is not OK: "Not for Mia · peanut". nil when OK for everyone.
    static func goToNote(_ verdict: HouseholdVerdict, catalog: Catalog) -> (level: Level, text: String)? {
        guard let worst = verdict.decidingPerson, worst.level != .ok else { return nil }
        var flag = Copy.flag(worst.level, names: [worst.name])
        if worst.level == .checkFirst || worst.level == .cantConfirm, verdict.people.count > 1 { flag += " for \(worst.name)" }
        let finding = worst.findings.filter { $0.level == worst.level }.first
        let what = finding?.rule.flatMap { catalog.family($0.familyId)?.name.lowercased() } ?? finding?.matched
        return (worst.level, what.map { "\(flag) \u{00B7} \($0)" } ?? flag)
    }

    /// "Austin, TX 78701", "78701".
    static func regionLine(_ region: Region?) -> String? {
        guard let region else { return nil }
        return [region.city, region.zip].compactMap { $0 }.joined(separator: " ")
    }

    /// A US ZIP code: five digits.
    static func isZip(_ text: String) -> Bool {
        text.count == 5 && text.allSatisfy(\.isASCII) && text.allSatisfy(\.isNumber)
    }

    static func join(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
