import Foundation
import Synchronization
import LabelSageCore

/// A household verdict and the pose LabelSage takes for it.
nonisolated struct VerdictResult: Sendable, Equatable {
    /// From `VerdictEngine` only. Nothing else sets a level.
    var verdict: HouseholdVerdict
    var pose: MascotState
}

extension HouseholdVerdict {
    /// The person whose verdict is the household's, whose reason the flag shows: the first one at
    /// the overall level (the owner comes first), else the first person.
    nonisolated var decidingPerson: PersonVerdict? {
        people.first { $0.level == overall } ?? people.first
    }
}

/// Runs `VerdictEngine` for the household: "code decides, LabelSage explains". Offline, no model.
nonisolated struct VerdictService: Sendable {
    let engine: VerdictEngine

    init(engine: VerdictEngine = VerdictEngine(catalog: VerdictService.bundledCatalog)) {
        self.engine = engine
    }

    /// The ingredient catalog shipped in `LabelSageCore`, loaded once.
    static let bundledCatalog: Catalog = {
        do {
            return try Catalog.bundled()
        } catch {
            // The catalog is a resource of the linked package; without it no verdict is possible,
            // so this is a broken build, not a runtime state. VerdictServiceTests loads it.
            Log.verdict.failure("Bundled catalog failed to load", error, level: .fault)
            fatalError("LabelSageCore catalog.json is missing or invalid: \(error)")
        }
    }()

    /// The verdict, from the memo when this product was already checked for this household. The
    /// engine is deterministic, so a memo hit is the same answer.
    func check(_ product: Product, for household: Household) -> VerdictResult {
        if let hit = memo.result(for: product, household: household) { return hit }
        let verdict = Perf.measure("verdict.check") { engine.check(product, for: household) }
        let findings = verdict.people.reduce(0) { $0 + $1.findings.count }
        Log.verdict.debug("Flag \(verdict.overall.rawValue, privacy: .public) for \(verdict.people.count, privacy: .public) people, \(findings, privacy: .public) findings")
        if verdict.overall != .ok, findings == 0 {
            Log.verdict.fault("Flag \(verdict.overall.rawValue, privacy: .public) without evidence")
        }
        let result = VerdictResult(verdict: verdict, pose: Self.pose(for: verdict.overall))
        memo.store(result, for: product, household: household)
        return result
    }

    /// The product with its verdict for the household, as option cards and Compare take it.
    func option(_ product: Product, for household: Household) -> ProductOption {
        ProductOption(product: product, verdict: check(product, for: household).verdict)
    }

    private let memo = Memo()

    /// Verdicts for one household by product id. A different household (a saved change, a
    /// switched-off row) clears it; a product with the same id but other data is checked again.
    private final class Memo: Sendable {
        private struct State {
            var household: Household?
            var results: [String: (product: Product, result: VerdictResult)] = [:]
        }

        private static let limit = 200
        private let state = Mutex(State())

        func result(for product: Product, household: Household) -> VerdictResult? {
            state.withLock { state in
                guard state.household == household, let hit = state.results[product.id], hit.product == product else { return nil }
                return hit.result
            }
        }

        func store(_ result: VerdictResult, for product: Product, household: Household) {
            state.withLock { state in
                if state.household != household || state.results.count >= Self.limit {
                    state = State(household: household)
                }
                state.results[product.id] = (product, result)
            }
        }
    }

    /// `docs/mascot.md`: Not for → guard (never disguise), Check first and Can't confirm → thinking,
    /// OK → done.
    static func pose(for level: Level) -> MascotState {
        switch level {
        case .notFor: .guard
        case .checkFirst, .cantConfirm: .thinking
        case .ok: .done
        }
    }
}
