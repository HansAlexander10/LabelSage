import Foundation

/// data/catalog.json: families of ingredients with the names they hide under.
public struct Catalog: Codable, Sendable {
    public struct Family: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var kind: String
        public var icon: String
        public var terms: [String]
        public var notTerms: [String]?
        public var parent: String?
        public var children: [String]?
        public var isA: String?
        public var note: String?
        public var shareInProducts: Double?
    }

    public struct Limit: Codable, Sendable, Equatable {
        public var nutrient: Nutrient
        public var perDay: Double
    }

    public struct Diet: Codable, Sendable, Equatable {
        public var name: String
        public var icon: String
        public var avoid: [String]?
        public var limits: [Limit]?
        public var reason: String?
        public var note: String?
    }

    public struct Medical: Codable, Sendable, Equatable {
        public var name: String
        public var icon: String
        public var avoid: [String]?
        public var limits: [Limit]?
        public var strength: String?
        public var mayContainDefault: Bool?
    }

    public struct Ambiguous: Codable, Sendable, Equatable {
        public var term: String
        public var alt: [String]
        public var couldBe: [String]
        public var why: String
        public var resolvedBy: [String]?
    }

    public var version: Int
    public var usMajorAllergens: [String]
    public var mayContainMarkers: [String]
    public var negationSuffixes: [String]
    public var families: [Family]
    public var diets: [String: Diet]
    public var medical: [String: Medical]
    public var ambiguous: [Ambiguous]

    // Lookups built once.
    private var byId: [String: Family] = [:]

    enum CodingKeys: String, CodingKey {
        case version, usMajorAllergens, mayContainMarkers, negationSuffixes, families, diets, medical, ambiguous
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        usMajorAllergens = try c.decode([String].self, forKey: .usMajorAllergens)
        mayContainMarkers = try c.decode([String].self, forKey: .mayContainMarkers)
        negationSuffixes = try c.decode([String].self, forKey: .negationSuffixes)
        families = try c.decode([Family].self, forKey: .families)
        diets = try c.decode([String: Diet].self, forKey: .diets)
        medical = try c.decode([String: Medical].self, forKey: .medical)
        ambiguous = try c.decode([Ambiguous].self, forKey: .ambiguous)
        byId = Dictionary(families.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The catalog shipped in this package.
    public static func bundled() throws -> Catalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    public func family(_ id: String) -> Family? { byId[id] }

    var majors: Set<String> { Set(usMajorAllergens) }

    /// A family plus all its children: a group matches every child.
    func expand(_ id: String) -> [Family] {
        guard let f = byId[id] else { return [] }
        return [f] + (f.children ?? []).flatMap { expand($0) }
    }

    func ancestors(_ id: String) -> [String] {
        var out: [String] = []
        var cur = byId[id]
        while let p = cur?.parent, let pf = byId[p] {
            out.append(p)
            cur = pf
        }
        return out
    }

    /// First term of the family (or its children) in a normalized phrase.
    /// Returns the id of the family that owns the term and the matched words.
    func match(familyId: String, in phrase: String) -> (owner: String, words: String)? {
        let fams = expand(familyId)
        guard !fams.isEmpty else { return nil }
        let terms = fams.flatMap { f in f.terms.map { ($0, f.id) } }
        let nots = Set(fams.flatMap { $0.notTerms ?? [] })
        return Matcher.firstMatch(terms: terms, notTerms: Array(nots), in: phrase, negations: negationSuffixes)
    }
}

/// Matching on normalized phrases (" whey protein concentrate "). Word boundaries come from the padding spaces.
enum Matcher {
    static func firstMatch(terms: [(String, String)], notTerms: [String], in phrase: String, negations: [String]) -> (owner: String, words: String)? {
        var q = phrase
        // Blank out phrases that contain a term but are not it: "cocoa butter" is not milk.
        for nt in notTerms.sorted(by: Matcher.longestFirst) {
            for v in Text.variants(nt) {
                let needle = " \(v) "
                while q.contains(needle) { q = q.replacingOccurrences(of: needle, with: " # ") }
            }
        }
        let ordered = terms.sorted { a, b in Matcher.longestFirst(a.0, b.0) }
        for (term, owner) in ordered {
            for v in Text.variants(term) {
                let needle = " \(v) "
                var searchStart = q.startIndex
                while let r = q.range(of: needle, range: searchStart..<q.endIndex) {
                    // "gluten free" is a claim, not an ingredient
                    let after = q[r.upperBound...].split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
                    if !negations.contains(after) { return (owner, v) }
                    searchStart = r.upperBound
                }
            }
        }
        return nil
    }

    /// Longest first; ties alphabetical, so every implementation picks the same term.
    static func longestFirst(_ a: String, _ b: String) -> Bool {
        a.count != b.count ? a.count > b.count : a < b
    }
}
