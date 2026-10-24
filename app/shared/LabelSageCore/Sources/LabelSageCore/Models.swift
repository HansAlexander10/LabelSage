import Foundation

// MARK: - Verdict levels

/// One flag per person per product. Ordered from best to worst; the worst finding decides.
/// Never rename these to "safe" or "unsafe" anywhere, including in code comments shown to users.
public enum Level: String, Codable, Sendable, CaseIterable, Comparable {
    case ok
    case checkFirst
    case cantConfirm
    case notFor

    var rank: Int {
        switch self {
        case .ok: 0
        case .checkFirst: 1
        case .cantConfirm: 2
        case .notFor: 3
        }
    }

    public static func < (a: Level, b: Level) -> Bool { a.rank < b.rank }
}

// MARK: - Product

public struct Nutrition: Codable, Sendable, Equatable {
    /// All values are per serving.
    public var kcal: Double?
    public var fatG: Double?
    public var satFatG: Double?
    public var sodiumMg: Double?
    public var carbsG: Double?
    public var fiberG: Double?
    public var addedSugarsG: Double?
    public var proteinG: Double?
    public var netCarbsG: Double?

    public init(kcal: Double? = nil, fatG: Double? = nil, satFatG: Double? = nil, sodiumMg: Double? = nil, carbsG: Double? = nil,
                fiberG: Double? = nil, addedSugarsG: Double? = nil, proteinG: Double? = nil, netCarbsG: Double? = nil) {
        self.kcal = kcal; self.fatG = fatG; self.satFatG = satFatG; self.sodiumMg = sodiumMg; self.carbsG = carbsG
        self.fiberG = fiberG; self.addedSugarsG = addedSugarsG; self.proteinG = proteinG; self.netCarbsG = netCarbsG
    }

    func value(_ n: Nutrient) -> Double? {
        switch n {
        case .sodiumMg: sodiumMg
        case .addedSugarsG: addedSugarsG
        case .netCarbsG: netCarbsG ?? carbsG.map { $0 - (fiberG ?? 0) }
        }
    }
}

public struct Product: Codable, Sendable, Equatable, Identifiable {
    public var id: String { barcode ?? name }
    public var barcode: String?
    public var name: String
    public var brand: String?
    public var size: String?
    public var servingSize: String?
    public var category: String?
    /// The ingredient list as printed. nil means "no ingredient list yet" and gives Can't confirm.
    public var ingredientsText: String?
    /// Separate "Contains: milk, soy." line when the source keeps it apart from the list.
    public var containsStatement: String?
    /// Separate "May contain ..." line when the source keeps it apart from the list.
    public var mayContainStatement: String?
    public var nutrition: Nutrition?
    public var nova: Int?
    public var imageURL: URL?
    public var price: Decimal?
    public var dataUpdatedAt: Date?

    public init(barcode: String? = nil, name: String, brand: String? = nil, size: String? = nil, servingSize: String? = nil,
                category: String? = nil, ingredientsText: String?, containsStatement: String? = nil, mayContainStatement: String? = nil,
                nutrition: Nutrition? = nil, nova: Int? = nil, imageURL: URL? = nil, price: Decimal? = nil, dataUpdatedAt: Date? = nil) {
        self.barcode = barcode; self.name = name; self.brand = brand; self.size = size; self.servingSize = servingSize
        self.category = category; self.ingredientsText = ingredientsText; self.containsStatement = containsStatement
        self.mayContainStatement = mayContainStatement; self.nutrition = nutrition; self.nova = nova; self.imageURL = imageURL
        self.price = price; self.dataUpdatedAt = dataUpdatedAt
    }
}

// MARK: - Household and people

public enum Severity: String, Codable, Sendable {
    /// Default (decision D3). Checks the ingredients and, when the person's "may contain" switch is on, "may contain" lines.
    case allergy
    /// Checks the ingredients only.
    case intolerance
}

public enum Strength: String, Codable, Sendable {
    /// "Avoid": hides it. A match gives Not for.
    case avoid
    /// "Prefer not": shows it lower. A match gives Check first.
    case preferNot
}

public struct AllergenChoice: Codable, Sendable, Equatable {
    /// A family id from the catalog: "peanut", "treenuts", "milk", or a leaf like "mustard".
    public var id: String
    public var severity: Severity
    /// For groups (tree nuts, fish and shellfish): only these leaves. nil means the whole group.
    public var leaves: [String]?

    public init(id: String, severity: Severity = .allergy, leaves: [String]? = nil) {
        self.id = id; self.severity = severity; self.leaves = leaves
    }
}

public struct AvoidChoice: Codable, Sendable, Equatable {
    public var id: String
    public var strength: Strength
    public init(id: String, strength: Strength = .avoid) { self.id = id; self.strength = strength }
}

/// Something the person typed ("cilantro"). The chat agent proposes the terms; the person confirms them.
public struct CustomChoice: Codable, Sendable, Equatable {
    public var label: String
    public var terms: [String]
    public var strength: Strength
    public init(label: String, terms: [String], strength: Strength = .avoid) { self.label = label; self.terms = terms; self.strength = strength }
}

public struct Goals: Codable, Sendable, Equatable {
    public var proteinG: Int?
    public var kcal: Int?
    public init(proteinG: Int? = nil, kcal: Int? = nil) { self.proteinG = proteinG; self.kcal = kcal }
}

public struct Profile: Codable, Sendable, Equatable {
    public var allergens: [AllergenChoice] = []
    /// "May contain" too. On by default when the person has an allergy or celiac.
    public var mayContain: Bool = true
    public var medical: [String] = []
    public var diets: [String] = []
    public var avoid: [AvoidChoice] = []
    public var custom: [CustomChoice] = []
    /// Macros and calories. Shown as information; never changes a flag.
    public var goals: Goals?

    public init(allergens: [AllergenChoice] = [], mayContain: Bool = true, medical: [String] = [], diets: [String] = [],
                avoid: [AvoidChoice] = [], custom: [CustomChoice] = [], goals: Goals? = nil) {
        self.allergens = allergens; self.mayContain = mayContain; self.medical = medical; self.diets = diets
        self.avoid = avoid; self.custom = custom; self.goals = goals
    }

    enum CodingKeys: String, CodingKey { case allergens, mayContain, medical, diets, avoid, custom, goals }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        allergens = try c.decodeIfPresent([AllergenChoice].self, forKey: .allergens) ?? []
        mayContain = try c.decodeIfPresent(Bool.self, forKey: .mayContain) ?? true
        medical = try c.decodeIfPresent([String].self, forKey: .medical) ?? []
        diets = try c.decodeIfPresent([String].self, forKey: .diets) ?? []
        avoid = try c.decodeIfPresent([AvoidChoice].self, forKey: .avoid) ?? []
        custom = try c.decodeIfPresent([CustomChoice].self, forKey: .custom) ?? []
        goals = try c.decodeIfPresent(Goals.self, forKey: .goals)
    }
}

public struct Person: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// The person holding the phone. Shown as "you" in every line.
    public var isOwner: Bool
    public var profile: Profile

    public init(id: String, name: String, isOwner: Bool = false, profile: Profile = Profile()) {
        self.id = id; self.name = name; self.isOwner = isOwner; self.profile = profile
    }

    /// "you" for the owner, the name for everyone else. Names, not roles.
    public var displayName: String { isOwner ? "you" : name }
}

public struct Region: Codable, Sendable, Equatable {
    /// Required in onboarding. Only the ZIP code is kept, on the device.
    public var zip: String
    public var city: String?
    public init(zip: String, city: String? = nil) { self.zip = zip; self.city = city }
}

public struct Store: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var distanceMiles: Double?
    public init(id: String, name: String, distanceMiles: Double? = nil) { self.id = id; self.name = name; self.distanceMiles = distanceMiles }
}

public struct Household: Codable, Sendable, Equatable {
    public var people: [Person]
    /// Required before the first check (onboarding asks it once for the household).
    public var region: Region?
    /// Where "Other options" come from. Picked in onboarding after the region; changed in Family > Settings.
    public var store: Store?

    public init(people: [Person], region: Region? = nil, store: Store? = nil) {
        self.people = people; self.region = region; self.store = store
    }
}
