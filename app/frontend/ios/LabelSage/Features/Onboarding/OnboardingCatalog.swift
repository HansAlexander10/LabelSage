import Foundation
import LabelSageCore

/// The onboarding lists: allergen groups, related allergens, search synonyms, what a diet covers,
/// the "Anything else" groups (all from `catalog.json` › `onboarding`), plus the demo places and
/// stores from `OnboardSimple.dc.html`.
///
/// `LabelSageCore.Catalog` does not decode the `onboarding` section, and the core package is not
/// this task's to change, so the section is mirrored here.
// shortcut: mirrors catalog.json › onboarding by hand; decode it in LabelSageCore once the core
// package exposes it, then delete these tables.
nonisolated enum OnboardingCatalog {
    /// One allergen group card. `leaves` are catalog family ids; nil means a single card.
    struct AllergenGroup: Sendable, Equatable {
        let id: String
        let label: String
        let icon: String
        let leaves: [String]?
    }

    /// The 9 group cards in board order (`onboarding.allergenGroups`).
    static let allergenGroups: [AllergenGroup] = [
        AllergenGroup(id: "peanut", label: "Peanuts", icon: "peanut", leaves: nil),
        AllergenGroup(id: "treenuts", label: "Tree nuts", icon: "treenuts",
                      leaves: ["almond", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "macadamia", "brazilnut", "pinenut"]),
        AllergenGroup(id: "milk", label: "Milk", icon: "milk", leaves: nil),
        AllergenGroup(id: "egg", label: "Eggs", icon: "egg", leaves: nil),
        AllergenGroup(id: "soy", label: "Soy", icon: "soy", leaves: nil),
        AllergenGroup(id: "wheat", label: "Wheat", icon: "wheat", leaves: nil),
        AllergenGroup(id: "fish", label: "Fish and shellfish", icon: "fish",
                      leaves: ["fish2", "shrimp", "crab", "lobster", "oyster", "mussel", "squid"]),
        AllergenGroup(id: "sesame", label: "Sesame", icon: "sesame", leaves: nil),
        AllergenGroup(id: "other", label: "Other", icon: "add",
                      leaves: ["mustard", "celery", "lupin", "sulfites", "corn", "coconut"]),
    ]

    /// The "Other" group is not an allergen itself: each of its leaves is its own allergen.
    static let otherGroupId = "other"

    /// `onboarding.related`: picking Peanut suggests these. Never pre-ticked.
    static let related: [String: [String]] = ["peanut": ["treenuts", "lupin"]]

    /// `onboarding.searchSynonyms`: other names the allergen search knows.
    static let searchSynonyms: [String: String] = [
        "prawn": "fish", "prawns": "fish", "shrimp": "fish", "shellfish": "fish", "crab": "fish",
        "lobster": "fish", "scallop": "fish", "dairy": "milk", "lactose": "milk", "cheese": "milk",
        "whey": "milk", "casein": "milk", "gluten": "wheat", "flour": "wheat", "nut": "treenuts",
        "nuts": "treenuts", "tahini": "sesame", "albumin": "egg", "soya": "soy",
    ]

    /// `onboarding.dietCovers`: a diet that already rules these allergen groups out (Q3).
    static let dietCovers: [String: [String]] = ["vegan": ["milk", "egg", "fish"], "vegetarian": ["fish"]]

    /// `onboarding.anythingElseGroups`, in board order.
    static let anythingElseGroups = ["sugar", "flavors", "seed", "gluten", "gums", "preserv", "palm", "msg", "sweet", "colors"]

    /// The catalog shipped in `LabelSageCore` (names, terms, icons).
    static var catalog: Catalog { VerdictService.bundledCatalog }

    /// "Peanut", "Tree nuts", "Fish" (catalog `fish2`).
    static func name(_ familyId: String) -> String { catalog.family(familyId)?.name ?? familyId }

    /// The group a leaf belongs to ("almond" → tree nuts), or the group itself.
    static func group(containing id: String) -> AllergenGroup? {
        allergenGroups.first { $0.id == id || ($0.leaves ?? []).contains(id) }
    }

    // MARK: Places and stores (demo)

    /// A US place for the region search.
    struct Place: Sendable, Equatable, Identifiable {
        let city: String
        let stateCode: String
        let state: String
        let zip: String
        let area: String
        var id: String { zip }
        /// "Austin, TX".
        var cityLine: String { "\(city), \(stateCode)" }
        var region: Region { Region(zip: zip, city: cityLine) }
    }

    /// `OnboardSimple.dc.html` › `PLACES`.
    // shortcut: a demo list until a place source exists (Q11); swap for MapKit search later.
    static let places: [Place] = [
        Place(city: "New York", stateCode: "NY", state: "New York", zip: "10001", area: "Manhattan"),
        Place(city: "Newark", stateCode: "NJ", state: "New Jersey", zip: "07102", area: "Essex County"),
        Place(city: "Jersey City", stateCode: "NJ", state: "New Jersey", zip: "07302", area: "Hudson County"),
        Place(city: "New Orleans", stateCode: "LA", state: "Louisiana", zip: "70112", area: "Orleans Parish"),
        Place(city: "New Haven", stateCode: "CT", state: "Connecticut", zip: "06510", area: "New Haven County"),
        Place(city: "Newport Beach", stateCode: "CA", state: "California", zip: "92660", area: "Orange County"),
        Place(city: "Austin", stateCode: "TX", state: "Texas", zip: "78701", area: "Travis County"),
        Place(city: "Nashville", stateCode: "TN", state: "Tennessee", zip: "37201", area: "Davidson County"),
        Place(city: "Denver", stateCode: "CO", state: "Colorado", zip: "80202", area: "Denver County"),
        Place(city: "Seattle", stateCode: "WA", state: "Washington", zip: "98101", area: "King County"),
        Place(city: "San Francisco", stateCode: "CA", state: "California", zip: "94103", area: "San Francisco County"),
        Place(city: "Chicago", stateCode: "IL", state: "Illinois", zip: "60601", area: "Cook County"),
    ]

    /// Places whose city or state starts with the query, whose state code is the query, or whose
    /// ZIP starts with it. Two characters at least, four results at most (spec `PlaceSearch`).
    static func places(matching query: String) -> [Place] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        let hits = places.filter {
            $0.city.lowercased().hasPrefix(q) || $0.state.lowercased().hasPrefix(q)
                || $0.stateCode.lowercased() == q || $0.zip.hasPrefix(q)
        }
        return Array(hits.prefix(4))
    }

    /// The demo stores near 78701 (Q11), with the neighborhood the board shows.
    static let demoStores: [Store] = [
        Store(id: "wfm", name: "Whole Foods Market", distanceMiles: 1.2),
        Store(id: "safeway", name: "Safeway", distanceMiles: 2.0),
        Store(id: "heb", name: "H-E-B", distanceMiles: 2.4),
        Store(id: "target", name: "Target", distanceMiles: 3.1),
    ]
}
