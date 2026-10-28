import CoreLocation
import MapKit
import LabelSageCore

/// "Use my location" (known issue 2): one location fix, matched to the nearest ZIP in the bundled
/// directory. The location stays on the phone; only the ZIP is kept.
enum LocationLookup {
    /// The region around the person, or nil when location is denied, unavailable or takes over 12 s.
    static func currentRegion() async -> Region? {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        let location = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location { return location }
                        if update.authorizationDenied || update.authorizationDeniedGlobally
                            || update.authorizationRestricted { return nil }
                    }
                } catch {
                    Log.lookup.error("Location updates failed: \(error.localizedDescription, privacy: .public)")
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(12))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let location else { return nil }
        let c = location.coordinate
        return await Task.detached { ZipDirectory.shared.nearest(latitude: c.latitude, longitude: c.longitude)?.region }.value
    }
}

/// Grocery stores near a ZIP for the store step (known issue 3): an Apple Maps "grocery store" search
/// within 5 miles of the ZIP's center, food markets only, without liquor, candy or convenience shops.
/// Apple Maps sees that center, never the person's location.
enum NearbyStores {
    static let radiusMeters: CLLocationDistance = 8_000
    static let limit = 6
    /// Food-market results that aren't where people do a grocery shop.
    static let excluded = ["beer", "wine", "liquor", "spirits", "chocolat", "candy", "vape", "smoke", "tobacco",
                           "7-eleven", "circle k", "convenience", "gas", "bakery", "donut", "coffee"]

    /// Up to six stores in Apple Maps' order (best match first). Empty when the ZIP isn't in the directory.
    static func stores(near region: Region) async throws -> [Store] {
        guard let center = await Task.detached(operation: { ZipDirectory.shared.entry(zip: region.zip) }).value else { return [] }
        let coordinate = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "grocery store"
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.foodMarket])
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: radiusMeters * 2, longitudinalMeters: radiusMeters * 2)
        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var seen = Set<String>()
        let stores = response.mapItems.compactMap { item -> Store? in
            guard let name = item.name, !name.isEmpty, !isExcluded(name) else { return nil }
            let meters = item.location.distance(from: origin)
            guard meters <= radiusMeters else { return nil }
            let id = item.identifier?.rawValue ?? "\(name)|\(item.location.coordinate.latitude)|\(item.location.coordinate.longitude)"
            guard seen.insert(id).inserted else { return nil }
            return Store(id: id, name: name, distanceMiles: (meters / 1_609.344 * 10).rounded() / 10)
        }
        return Array(stores.prefix(limit))
    }

    static func isExcluded(_ name: String) -> Bool {
        let n = name.lowercased()
        return excluded.contains { n.contains($0) }
    }
}
