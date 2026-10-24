import Foundation
import Testing
@testable import LabelSageCore

/// data/verdict-cases.json is the executable spec. tools/reference_engine.py passes every case;
/// this suite must pass the same cases with the same lines.
struct VerdictCases: Decodable {
    struct Expect: Decodable, Sendable {
        var levels: [String: Level]?
        var reasons: [String: String]?
        var line: String?
        var index: [String: Int]?
    }
    enum HouseholdRef: Decodable, Sendable {
        case named(String)
        case inline(Household)
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .named(s) } else { self = .inline(try c.decode(Household.self)) }
        }
    }
    struct Case: Decodable, Sendable, CustomTestStringConvertible {
        var id: String
        var household: HouseholdRef
        var product: Product
        var expect: Expect
        var testDescription: String { id }
    }
    var households: [String: Household]
    var cases: [Case]

    static func load() throws -> VerdictCases {
        let url = try #require(Bundle.module.url(forResource: "verdict-cases", withExtension: "json"))
        return try JSONDecoder().decode(VerdictCases.self, from: Data(contentsOf: url))
    }

    static let all: [Case] = (try? load().cases) ?? []
}

@Suite("Verdict engine fixtures")
struct VerdictEngineFixtureTests {
    let engine: VerdictEngine
    let fixtures: VerdictCases

    init() throws {
        engine = VerdictEngine(catalog: try Catalog.bundled())
        fixtures = try VerdictCases.load()
    }

    @Test func `fixtures load`() {
        #expect(fixtures.cases.count >= 40)
    }

    @Test(arguments: VerdictCases.all)
    func `case matches the reference engine`(_ c: VerdictCases.Case) throws {
        let household: Household
        switch c.household {
        case .named(let key): household = try #require(fixtures.households[key])
        case .inline(let h): household = h
        }
        let result = engine.check(c.product, for: household)
        for (pid, level) in c.expect.levels ?? [:] {
            let p = try #require(result.people.first { $0.id == pid })
            #expect(p.level == level, "\(c.id) \(pid)")
        }
        for (pid, reason) in c.expect.reasons ?? [:] {
            let p = try #require(result.people.first { $0.id == pid })
            #expect(p.reason == reason, "\(c.id) \(pid)")
        }
        if let line = c.expect.line { #expect(result.line == line) }
        for (pid, index) in c.expect.index ?? [:] {
            let p = try #require(result.people.first { $0.id == pid })
            #expect(p.findings.first?.index == index)
        }
    }
}

@Suite("Parser and matcher")
struct ParserTests {
    @Test func `normalizes like the reference`() {
        #expect(Text.norm("Brewer’s Yeast, Gluten-Free!") == " brewer's yeast gluten free ")
        #expect(Text.norm("Crème fraîche") == " creme fraiche ")
    }

    @Test func `splits statements from the list`() throws {
        let catalog = try Catalog.bundled()
        let p = Product(name: "Demo", ingredientsText: "Ingredients: Oats, sugar (cane), salt. Contains: milk. May contain peanuts and tree nuts.")
        let label = LabelParser.parse(p, catalog: catalog)
        #expect(label.ingredients.map(\.text) == ["oats", "sugar", "cane", "salt"])
        #expect(label.ingredients.map(\.index) == [1, 2, 2, 3])
        #expect(label.contains == ["milk"])
        #expect(label.mayContain == ["peanuts", "tree nuts"])
        #expect(label.hasContainsStatement)
    }

    @Test func `keeps decimals inside a sentence`() {
        #expect(LabelParser.sentences("salt, 2.5% citric acid. may contain milk") == ["salt, 2.5% citric acid", "may contain milk"])
    }

    @Test(arguments: ["eggplant", "cocoa butter", "nutmeg", "buckwheat flour", "gluten free oats"])
    func `does not match look-alikes`(_ phrase: String) throws {
        let catalog = try Catalog.bundled()
        for fid in ["egg", "milk", "treenuts", "wheat", "gluten"] {
            #expect(catalog.match(familyId: fid, in: Text.norm(phrase)) == nil, "\(phrase) matched \(fid)")
        }
    }

    @Test func `ordinals`() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22].map(Text.ordinal) == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd"])
    }
}
