import Foundation
import LabelSageCore

/// The mock backend: reads `Resources/Data/sample-products.json` and answers like a slow network
/// (300 to 600 ms), so screens show their checking state. `setOffline(true)` makes every call throw
/// `ProductSourceError.offline`, so screens can show the offline state. Region and store are accepted and
/// ignored: the fixtures have no store data.
actor FixtureProductSource: ProductSource {
    private let products: [Product]
    private let stores: [Store]
    private let delayMilliseconds: ClosedRange<Int>
    /// When true, every call throws `.offline`.
    private(set) var isOffline: Bool

    /// - Parameters:
    ///   - products: the catalog; nil reads the bundled `sample-products.json`.
    ///   - delayMilliseconds: artificial latency per call; tests pass `0...0`.
    init(products: [Product]? = nil, delayMilliseconds: ClosedRange<Int> = 300...600,
         isOffline: Bool = false) {
        if let products {
            self.products = products
        } else {
            do {
                self.products = try SampleData.products()
            } catch {
                Log.lookup.failure("Bundled sample-products.json failed to load", error, level: .fault)
                self.products = []
            }
        }
        // The fixture store list is the demo household's store (sample-household.json).
        self.stores = (try? SampleData.household().store).map { [$0] } ?? []
        self.delayMilliseconds = delayMilliseconds
        self.isOffline = isOffline
    }

    /// Turns the offline state on or off.
    func setOffline(_ offline: Bool) { isOffline = offline }

    func product(barcode: String, region: Region?) async throws -> Product? {
        let interval = Perf.begin("lookup")
        defer { Perf.end(interval) }
        try await simulateNetwork()
        let code = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        return products.first { $0.barcode == code }
    }

    func search(_ query: String, region: Region?, store: Store?, limit: Int) async throws -> [Product] {
        let interval = Perf.begin("lookup")
        defer { Perf.end(interval) }
        try await simulateNetwork()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let words = q.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        let hits = products.filter { product in
            let text = "\(product.name) \(product.brand ?? "")".lowercased()
            return words.allSatisfy { text.contains($0) }
        }
        // Best match first: a name that starts with the query, then the file order.
        let ranked = hits.enumerated().sorted { a, b in
            let aStarts = a.element.name.lowercased().hasPrefix(q), bStarts = b.element.name.lowercased().hasPrefix(q)
            return aStarts != bStarts ? aStarts : a.offset < b.offset
        }.map(\.element)
        return Array(ranked.prefix(max(0, limit)))
    }

    func options(like product: Product, region: Region?, store: Store?, limit: Int) async throws -> [Product] {
        let interval = Perf.begin("lookup")
        defer { Perf.end(interval) }
        try await simulateNetwork()
        let options = products.filter {
            $0.id != product.id && $0.category == product.category && $0.ingredientsText != nil
        }
        return Array(options.prefix(max(0, limit)))
    }

    func stores(near region: Region) async throws -> [Store] {
        let interval = Perf.begin("lookup")
        defer { Perf.end(interval) }
        try await simulateNetwork()
        return stores
    }

    private func simulateNetwork() async throws {
        try Task.checkCancellation()
        let ms = Int.random(in: delayMilliseconds)
        if ms > 0 { try await Task.sleep(for: .milliseconds(ms)) }
        if isOffline {
            Log.lookup.info("Fixture source is offline")
            throw ProductSourceError.offline
        }
    }
}
