import Foundation
import LabelSageCore

/// Every US ZIP code with its city, state, county and center, from `us-zips.tsv` (GeoNames, CC BY 4.0,
/// built by `app/tools/make-zip-directory.py`). The region step searches it on the phone: a ZIP gives
/// "Austin, TX", a city gives its ZIP, a location gives the nearest ZIP. Nothing is sent anywhere.
nonisolated struct ZipDirectory: Sendable {
    struct Entry: Sendable, Equatable {
        let zip: String
        let city: String
        let stateCode: String
        let county: String
        let latitude: Double
        let longitude: Double
    }

    /// Sorted by ZIP.
    let entries: [Entry]
    /// "TX" → "Texas".
    let stateNames: [String: String]
    /// Each entry's city, folded once for the search.
    private let cityKeys: [String]

    /// The bundled directory; empty when the file is missing. Loaded on first use (about 41,000 rows).
    static let shared = ZipDirectory(url: Bundle.main.url(forResource: "us-zips", withExtension: "tsv"))

    init(entries: [Entry], stateNames: [String: String]) {
        self.entries = entries.sorted { $0.zip < $1.zip }
        self.stateNames = stateNames
        self.cityKeys = self.entries.map { Self.fold($0.city) }
    }

    init(url: URL?) {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            self.init(entries: [], stateNames: [:])
            return
        }
        self.init(tsv: text)
    }

    /// "S\tTX\tTexas" lines name the states; the rest are "zip\tcity\tstate\tcounty\tlat\tlon".
    init(tsv text: String) {
        var entries: [Entry] = []
        var states: [String: String] = [:]
        entries.reserveCapacity(42_000)
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            if f.count == 3, f[0] == "S" {
                states[String(f[1])] = String(f[2])
            } else if f.count == 6, let lat = Double(f[4]), let lon = Double(f[5]) {
                entries.append(Entry(zip: String(f[0]), city: String(f[1]), stateCode: String(f[2]),
                                     county: String(f[3]), latitude: lat, longitude: lon))
            }
        }
        self.init(entries: entries, stateNames: states)
    }

    /// The place for a five-digit ZIP, or nil when no such ZIP exists.
    func place(zip: String) -> OnboardingCatalog.Place? { entry(zip: zip).map(place) }

    /// The row for a five-digit ZIP, with its center.
    func entry(zip: String) -> Entry? {
        var lo = 0, hi = entries.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if entries[mid].zip == zip { return entries[mid] }
            if entries[mid].zip < zip { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    /// Up to `limit` places for what the person typed: ZIPs starting with the digits, or cities whose
    /// name starts with the words ("san fr", "austin, tx", "austin tx"). One row per city, at its
    /// lowest ZIP; an exact city name first, then cities with more ZIP codes (bigger places).
    func places(matching query: String, limit: Int = 4) -> [OnboardingCatalog.Place] {
        let q = Self.fold(query)
        guard q.count >= 2 else { return [] }
        if q.allSatisfy(\.isNumber) {
            return entries.lazy.filter { $0.zip.hasPrefix(q) }.prefix(limit).map(place)
        }
        // "austin, tx" or "austin tx": the last word may be a state code.
        var cityPart = q.replacingOccurrences(of: ",", with: " ").split(separator: " ").joined(separator: " ")
        var state: String?
        let words = cityPart.split(separator: " ")
        if words.count > 1, let last = words.last, last.count == 2, stateNames[last.uppercased()] != nil {
            state = last.uppercased()
            cityPart = words.dropLast().joined(separator: " ")
        }
        var groups: [String: (entry: Entry, count: Int)] = [:]
        for (e, key) in Swift.zip(entries, cityKeys) where state == nil || e.stateCode == state {
            guard key.hasPrefix(cityPart) else { continue }
            let key = e.city + "|" + e.stateCode
            if let g = groups[key] { groups[key] = (g.entry, g.count + 1) } else { groups[key] = (e, 1) }
        }
        let ranked = groups.values.sorted { a, b in
            let aExact = Self.fold(a.entry.city) == cityPart, bExact = Self.fold(b.entry.city) == cityPart
            if aExact != bExact { return aExact }
            if a.count != b.count { return a.count > b.count }
            return a.entry.zip < b.entry.zip
        }
        return ranked.prefix(limit).map { place($0.entry) }
    }

    /// The ZIP whose center is closest to a location, or nil when the directory is empty.
    func nearest(latitude: Double, longitude: Double) -> OnboardingCatalog.Place? {
        let k = cos(latitude * .pi / 180)
        let best = entries.min { a, b in
            let da = pow(a.latitude - latitude, 2) + pow((a.longitude - longitude) * k, 2)
            let db = pow(b.latitude - latitude, 2) + pow((b.longitude - longitude) * k, 2)
            return da < db
        }
        return best.map(place)
    }

    private func place(_ e: Entry) -> OnboardingCatalog.Place {
        OnboardingCatalog.Place(city: e.city, stateCode: e.stateCode, state: stateNames[e.stateCode] ?? e.stateCode,
                                zip: e.zip, area: e.county.isEmpty ? e.stateCode : "\(e.county) County")
    }

    /// Lowercased, without accents or extra spaces: "Cañon City " → "canon city".
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespaces)
    }
}
