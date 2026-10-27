import Foundation
import LabelSageCore

/// Where products come from (decision D4 is open, `docs/logic/data-and-privacy.md` › Product source).
///
/// A lookup sends only the barcode or the typed name, plus the region and the store. Nothing about a
/// person goes through this protocol.
///
/// The shape matches `CatalogProductSource` in the `LabelSageCatalog` package (optional region and
/// store, a result limit, plain `throws`), so that type can conform later with an empty extension
/// (`docs/app-engineering/spikes/spike-frontend-backend-integration-2026-10-26.md`). Implementations
/// throw `ProductSourceError` when they can; `ProductSourceError(_:)` maps any other error.
nonisolated protocol ProductSource: Sendable {
    /// The product with this barcode, or nil when the source does not know it (the "not found" state).
    func product(barcode: String, region: Region?) async throws -> Product?
    /// Products whose name or brand matches the typed text, best match first.
    func search(_ query: String, region: Region?, store: Store?, limit: Int) async throws -> [Product]
    /// Other options for this product: the same category, with an ingredient list, at this store.
    func options(like product: Product, region: Region?, store: Store?, limit: Int) async throws -> [Product]
    /// Stores near the region, for onboarding and Family › Settings.
    func stores(near region: Region) async throws -> [Store]
}

/// The two failures a screen shows (`docs/specs/03-check-a-product.md` states).
nonisolated enum ProductSourceError: Error, Sendable, Equatable {
    /// The source does not know this product: the "not found" state with "Report it".
    case notFound
    /// No connection: the offline state with the "Checked before" list.
    case offline
    /// The lookup was cancelled (the person moved on). Screens ignore it and show nothing.
    case cancelled

    /// Maps any error from a source to a screen state: offline stays offline, cancellation stays
    /// cancellation, everything else is "not found" (data-and-privacy.md: "any other error → not found").
    init(_ error: any Error) {
        if let known = error as? ProductSourceError {
            self = known
        } else if error is CancellationError {
            self = .cancelled
        } else {
            self = .notFound
        }
    }
}

extension ProductSource {
    /// The barcode lookup as one typed result for screens: nil and unknown errors become `.notFound`,
    /// cancellation becomes `.cancelled`.
    func requireProduct(barcode: String, region: Region?) async throws(ProductSourceError) -> Product {
        let found: Product?
        do {
            found = try await product(barcode: barcode, region: region)
        } catch {
            let mapped = ProductSourceError(error)
            if mapped != .cancelled {
                Log.lookup.error("Barcode lookup failed: \(String(describing: mapped), privacy: .public) barcode \(barcode, privacy: .private(mask: .hash))")
            }
            throw mapped
        }
        // A result that arrives after cancellation is dropped, not shown as found or not found.
        if Task.isCancelled { throw .cancelled }
        guard let found else {
            Log.lookup.info("Barcode not found: \(barcode, privacy: .private(mask: .hash))")
            throw .notFound
        }
        return found
    }
}

/// Picks the product source. Today it always returns the fixtures: the real source waits for D4.
nonisolated enum ProductSourceFactory {
    /// Feature flag for the real catalog. Off until the team decides D4.
    // shortcut: no real source exists in this app yet; wire CatalogProductSource here once D4 is decided.
    static let useRealSource = false

    /// The source the app uses now.
    static func make() -> any ProductSource {
        if useRealSource {
            Log.lookup.notice("Real product source requested but not built (D4 open); using fixtures")
        }
        return FixtureProductSource(delayMilliseconds: fixtureLatency)
    }

    /// `-fixtureLatency <ms>` fixes the fake network delay (0 turns it off, to time the app alone);
    /// without it, 300 to 600 ms.
    static var fixtureLatency: ClosedRange<Int> {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-fixtureLatency"), args.indices.contains(i + 1),
              let ms = Int(args[i + 1]), ms >= 0 else { return 300...600 }
        return ms...ms
    }
}
