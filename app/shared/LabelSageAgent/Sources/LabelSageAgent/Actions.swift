import Foundation
import LabelSageCatalog
import LabelSageCore

/// The deterministic step: plain Swift over the catalog and the verdict engine. No model here.
public struct ChatActions: Sendable {
    public let catalog: CatalogProductSource
    public let engine: VerdictEngine

    public init(catalog: CatalogProductSource, engine: VerdictEngine) {
        self.catalog = catalog; self.engine = engine
    }

    /// The result of one action, before the Writer: products, verdicts and the deterministic line.
    public struct Result: Sendable {
        public var products: [Product] = []
        public var verdicts: [HouseholdVerdict] = []
        public var recalls: [String: [Recall]] = [:]
        public var line: String
        /// The person the line is about and the flag word it must keep, for the Writer's validation.
        public var mustKeep: [String] = []
        public var proposal: ProfileChangeProposal?
    }

    // MARK: - check: a scanned barcode

    public func check(barcode: String, household: Household) async throws -> Result {
        guard let product = try await catalog.product(barcode: barcode) else {
            return Result(line: "Not in my catalog yet. Report it so I can add it?")
        }
        return try await verdictResult([product], household: household, focus: [])
    }

    // MARK: - ask: "Are the popped corn chips OK for me?"

    public func ask(_ name: String, household: Household, focus: [String]) async throws -> Result {
        guard let product = try await catalog.search(name, limit: 1).first else {
            return Result(line: "I can’t find “\(name)” yet. Scan the barcode and I’ll check it.")
        }
        return try await verdictResult([product], household: household, focus: focus)
    }

    // MARK: - otherOptions: same category, OK for everyone first, then Check first, up to 3

    public func otherOptions(like base: Product, household: Household) async throws -> Result {
        let candidates = try await catalog.options(like: base, limit: 30)
        let checked = candidates.map { ($0, engine.check($0, for: household)) }
        let ok = checked.filter { $0.1.overall == .ok }
        let checkFirst = checked.filter { $0.1.overall == .checkFirst }
        let picked = Array((ok + checkFirst).prefix(3))
        let names = Self.join(household.people.map(\.displayName))
        guard !picked.isEmpty else {
            return Result(line: "Nothing here fits \(names) yet. Want me to check another?", mustKeep: [])
        }
        let allOK = picked.allSatisfy { $0.1.overall == .ok }
        let line = "Found \(picked.count). " + (allOK ? "All OK for \(names)." : "Check first on some of them.")
        var result = Result(products: picked.map(\.0), verdicts: picked.map(\.1), line: line,
                            mustKeep: allOK ? ["OK for"] : ["Check first"])
        result.recalls = try await recalls(for: result.products)
        return result
    }

    /// otherOptions from a typed product ("kettle chips without seed oils"): find the product, then its options.
    public func otherOptions(for name: String, household: Household) async throws -> Result {
        guard let base = try await catalog.search(name, limit: 1).first else {
            return Result(line: "I can’t find “\(name)” yet. Scan one and I’ll find other options.")
        }
        return try await otherOptions(like: base, household: household)
    }

    // MARK: - compare: the last two products

    public func compare(_ a: Product, _ b: Product, household: Household) async throws -> Result {
        let va = engine.check(a, for: household), vb = engine.check(b, for: household)
        let line = "\(a.name): \(va.line). \(b.name): \(vb.line)."
        return Result(products: [a, b], verdicts: [va, vb], recalls: try await recalls(for: [a, b]), line: line)
    }

    // MARK: - changeAllergies: a proposal only, never saved here (D14)

    public func proposeChange(_ intent: ReadIntent) -> Result {
        guard let item = intent.item else {
            return Result(line: "Which ingredient should I add, and for whom?")
        }
        let who = intent.people.first
        let proposal = ProfileChangeProposal(personName: who, item: item, severity: intent.severity)
        return Result(line: "Add \(item) for \(who ?? "you")? Confirm and I’ll check the go-tos again.", proposal: proposal)
    }

    // MARK: - Shared

    private func verdictResult(_ products: [Product], household: Household, focus: [String]) async throws -> Result {
        let verdicts = products.map { engine.check($0, for: household) }
        guard let verdict = verdicts.first else { return Result(line: "") }
        // the line is about the focus people when named, else the worst-off person (worst first)
        let people = verdict.people.filter { focus.isEmpty || focus.contains($0.name) }
        let worst = (people.isEmpty ? verdict.people : people).max { $0.level < $1.level }
        let line = worst?.reason ?? verdict.line
        let keep = worst.map { [Copy.flag($0.level, names: []).components(separatedBy: " ").prefix(2).joined(separator: " ")]
                               + ($0.level == .ok || $0.level == .notFor ? [$0.name] : []) } ?? []
        return Result(products: products, verdicts: verdicts, recalls: try await recalls(for: products), line: line,
                      mustKeep: keep.map { $0.trimmingCharacters(in: .whitespaces) })
    }

    private func recalls(for products: [Product]) async throws -> [String: [Recall]] {
        var out: [String: [Recall]] = [:]
        for p in products {
            guard let code = p.barcode else { continue }
            let found = try await catalog.recalls(barcode: code)
            if !found.isEmpty { out[code] = found }
        }
        return out
    }

    static func join(_ names: [String]) -> String {
        switch names.count {
        case 0: "everyone"
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}
