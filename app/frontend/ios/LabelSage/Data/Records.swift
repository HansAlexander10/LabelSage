import Foundation
import SwiftData
import CryptoKit
import LabelSageCore

// SwiftData models (`docs/logic/data-and-privacy.md` › Models). Everything here stays on the device:
// no CloudKit, no sync. The engine reads the `LabelSageCore` value types; these records only store them.

/// Version 1 of the store. Pass `Schema(versionedSchema: SchemaV1.self)` to the container.
// shortcut: the models are top-level types listed here, not nested in SchemaV1; nest them (and add a
// SchemaMigrationPlan) when the first schema change ships, so V1 and V2 can both exist.
nonisolated enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [HouseholdRecord.self, PersonRecord.self, GoToRecord.self, CheckRecord.self]
    }

    /// The app's container: on this iPhone only (no CloudKit), or in memory for tests, previews and
    /// `-demoHousehold`.
    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}

/// A stored record that cannot be read back. The app never serves a stand-in (an empty profile
/// would hide every allergy): it asks the person to check their profiles again.
nonisolated enum RecordError: Error, Equatable {
    /// A person's profile JSON failed to decode.
    case unreadableProfile
}

/// The household: people, region and store. One per install.
@Model
final class HouseholdRecord {
    @Relationship(deleteRule: .cascade, inverse: \PersonRecord.household)
    var people: [PersonRecord] = []
    /// Only the ZIP code (and the city shown with it) is kept, on this iPhone.
    var zip: String?
    var city: String?
    var storeId: String?
    var storeName: String?
    var storeDistanceMiles: Double?
    /// Set when onboarding saves the household ("Check my first product").
    var onboardingDone: Bool = false

    /// Throws when a profile fails to encode; nothing is stored then.
    init(_ household: Household, onboardingDone: Bool = false) throws {
        self.onboardingDone = onboardingDone
        try update(from: household)
    }

    /// Replaces the stored household with `household`, keeping the people's order. Encodes every
    /// profile first, so a failure leaves the record unchanged.
    func update(from household: Household) throws {
        let newPeople = try household.people.enumerated().map { try PersonRecord($0.element, order: $0.offset) }
        zip = household.region?.zip
        city = household.region?.city
        storeId = household.store?.id
        storeName = household.store?.name
        storeDistanceMiles = household.store?.distanceMiles
        // Replaced people would stay behind as orphans; delete them first.
        if let context = modelContext { people.forEach(context.delete) }
        people = newPeople
    }

    /// The value the engine reads. Throws `RecordError.unreadableProfile` when any profile is unreadable.
    var household: Household {
        get throws {
            Household(
                people: try people.sorted { $0.order < $1.order }.map { try $0.person },
                region: zip.map { Region(zip: $0, city: city) },
                store: storeId.map { Store(id: $0, name: storeName ?? "", distanceMiles: storeDistanceMiles) }
            )
        }
    }
}

/// One person and their rules (the `Profile`: allergens, may contain, diets, avoid, custom, goals).
@Model
final class PersonRecord {
    var personId: String = ""
    var name: String = ""
    var isOwner: Bool = false
    /// SwiftData relationships are unordered; this keeps the onboarding order.
    var order: Int = 0
    /// The `Profile` as JSON. Stored whole so the engine reads exactly what onboarding saved
    /// ("Profiles are stored as Codable values on the person").
    var profileData: Data = Data()
    var household: HouseholdRecord?

    init(_ person: Person, order: Int) throws {
        self.order = order
        try update(from: person)
    }

    /// Throws when the profile fails to encode; the record is unchanged then.
    func update(from person: Person) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(person.profile)
        } catch {
            Log.data.failure("Profile failed to encode", error, level: .fault)
            throw error
        }
        personId = person.id
        name = person.name
        isOwner = person.isOwner
        profileData = data
    }

    /// The value the engine reads. Fails closed: an unreadable profile throws, never becomes empty.
    var person: Person {
        get throws {
            do {
                let profile = try JSONDecoder().decode(Profile.self, from: profileData)
                return Person(id: personId, name: name, isOwner: isOwner, profile: profile)
            } catch {
                Log.data.failure("Profile failed to decode", error, level: .fault)
                throw RecordError.unreadableProfile
            }
        }
    }
}

/// A product the household saved to go-tos. Re-checked on open and after profile changes (D15).
@Model
final class GoToRecord {
    var barcode: String?
    var name: String = ""
    var brand: String?
    var imageURL: URL?
    /// SHA-256 of the ingredient list, to see when the label changed.
    var ingredientsHash: String?
    var savedAt: Date = Date.now
    /// The whole product, so it can be re-checked offline with today's profiles.
    var productData: Data = Data()

    init(_ product: Product, savedAt: Date = .now) throws {
        barcode = product.barcode
        name = product.name
        brand = product.brand
        imageURL = product.imageURL
        ingredientsHash = product.ingredientsText.map(Self.hash)
        self.savedAt = savedAt
        productData = try JSONEncoder().encode(product)
    }

    var product: Product? { try? JSONDecoder().decode(Product.self, from: productData) }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// One check: the product, when, and what the household line said. "Checked before" and chat history.
/// Always re-run the engine on the stored product before showing a verdict; the line is history only.
@Model
final class CheckRecord {
    var barcode: String?
    var name: String = ""
    var checkedAt: Date = Date.now
    /// `HouseholdVerdict.line` at the time, for example "Not for Mia · OK for you".
    var line: String = ""
    /// `HouseholdVerdict.overall.rawValue` at the time.
    var levelRaw: String = Level.cantConfirm.rawValue
    var productData: Data = Data()

    init(_ product: Product, verdict: HouseholdVerdict, checkedAt: Date = .now) throws {
        barcode = product.barcode
        name = product.name
        self.checkedAt = checkedAt
        line = verdict.line
        levelRaw = verdict.overall.rawValue
        productData = try JSONEncoder().encode(product)
    }

    var level: Level { Level(rawValue: levelRaw) ?? .cantConfirm }
    var product: Product? { try? JSONDecoder().decode(Product.self, from: productData) }
}
