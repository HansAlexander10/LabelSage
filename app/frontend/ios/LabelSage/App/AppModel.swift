import Foundation
import Observation
import SwiftData
import LabelSageCore

/// App state: the household (from SwiftData, on this iPhone only), whether onboarding is done, the
/// router, and the products looked up this session. Put one in the environment at the app root.
@Observable
final class AppModel {
    /// The household the engine checks against; nil before onboarding saves one, or when it is unreadable.
    private(set) var household: Household?
    /// True once onboarding saved the household. The root shows onboarding until then.
    private(set) var onboardingDone = false
    /// A stored profile could not be read. No verdict may run on a guess: the root sends the person
    /// to Family to check their profiles again, and saving a household clears this.
    private(set) var needsProfileRecheck = false
    /// The store could not be opened or read. Not a fresh install: the root shows a storage problem
    /// with Try again, never onboarding (which would save over a household that may still be there).
    private(set) var storageProblem = false
    /// Saved products (go-tos), oldest first. Re-checked with today's profiles wherever they show.
    private(set) var goTos: [Product] = []
    let router = Router()

    /// Products by `Product.id` from lookups this session, so routes can carry only the id.
    // shortcut: in memory and unbounded; move to the SwiftData product cache when "Checked before" lands.
    /// Not observed: hosts call `remember` before they route, so a lookup alone re-renders nothing.
    @ObservationIgnored private(set) var products: [String: Product] = [:]

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var record: HouseholdRecord?
    @ObservationIgnored private var goToRecords: [GoToRecord] = []
    /// The persistent store failed to open and the app runs on memory.
    @ObservationIgnored private let storeFellBack: Bool

    /// - Parameter storeFellBack: the app could not open its store and passed an in-memory one.
    init(context: ModelContext, storeFellBack: Bool = false) {
        self.context = context
        self.storeFellBack = storeFellBack
        load()
    }

    /// Reads the stored household. Fails closed: an unreadable profile leaves `household` nil and sets
    /// `needsProfileRecheck`; it never becomes an empty profile.
    func load() {
        do {
            record = try context.fetch(FetchDescriptor<HouseholdRecord>()).first
            goToRecords = try context.fetch(FetchDescriptor<GoToRecord>(sortBy: [SortDescriptor(\.savedAt)]))
            goTos = goToRecords.compactMap(\.product)
            storageProblem = storeFellBack
        } catch {
            Log.data.failure("Household fetch failed", error)
            record = nil
            storageProblem = true
        }
        onboardingDone = record?.onboardingDone ?? false
        do {
            household = try record?.household
            needsProfileRecheck = false
        } catch {
            household = nil
            needsProfileRecheck = true
            Log.data.fault("Household unreadable; asking for a profile re-check")
        }
        Log.data.info("Household loaded: \(self.household?.people.count ?? 0, privacy: .public) people")
    }

    /// Saves the household (onboarding, Family, a confirmed change card) and marks onboarding done.
    /// On failure the store rolls back and the in-memory state stays as it was.
    func save(_ household: Household) throws {
        let saved: HouseholdRecord
        do {
            if let record {
                try record.update(from: household)
                record.onboardingDone = true
                saved = record
            } else {
                saved = try HouseholdRecord(household, onboardingDone: true)
                context.insert(saved)
            }
            try context.save()
        } catch {
            context.rollback()
            Log.data.failure("Household save failed", error)
            throw error
        }
        record = saved
        self.household = household
        onboardingDone = true
        needsProfileRecheck = false
        #if DEBUG
        if Self.wantsHouseholdDump { dumpStoredHousehold("saved") }
        #endif
    }

    /// Whether `product` is saved to go-tos.
    func isGoTo(_ product: Product) -> Bool { goTos.contains { $0.id == product.id } }

    /// The heart and "Save to go-tos": saves (`true`) or removes the product. On failure the store
    /// rolls back and the list stays as it was.
    func setGoTo(_ product: Product, _ saved: Bool) {
        guard saved != isGoTo(product) else { return }
        do {
            if saved {
                context.insert(try GoToRecord(product))
            } else {
                goToRecords.filter { $0.product?.id == product.id }.forEach(context.delete)
            }
            try context.save()
            goToRecords = try context.fetch(FetchDescriptor<GoToRecord>(sortBy: [SortDescriptor(\.savedAt)]))
            goTos = goToRecords.compactMap(\.product)
            remember([product])
        } catch {
            context.rollback()
            Log.data.failure("Go-to save failed", error)
        }
    }

    /// The product a route or sheet names, if a lookup this session found it.
    func product(id: String) -> Product? { products[id] }

    /// Keeps products from a lookup or search so routes can resolve them by id.
    func remember(_ found: [Product]) {
        for product in found { products[product.id] = product }
    }

    /// A barcode lookup that fills the product cache.
    func lookup(barcode: String, region: Region?, in source: any ProductSource) async throws(ProductSourceError) -> Product {
        let product = try await source.requireProduct(barcode: barcode, region: region)
        remember([product])
        return product
    }

    /// Saves `sample-household.json` (Alex and Mia) and board 50's three go-tos. Only with
    /// `-demoHousehold`, which passes an in-memory container, so the demo never touches the real store.
    func seedDemoHousehold() throws {
        try save(try SampleData.household())
        let products = try SampleData.products()
        for code in ["0000000000024", "0000000000079", "0000000000062"] {
            if let product = products.first(where: { $0.barcode == code }) { setGoTo(product, true) }
        }
        Log.data.notice("Demo household seeded")
    }

    #if DEBUG

    /// Whether this launch asks for the demo household.
    static var wantsDemoHousehold: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoHousehold")
    }

    /// `-resetHousehold`: delete the stored household before loading, so onboarding shows.
    static var wantsHouseholdReset: Bool {
        ProcessInfo.processInfo.arguments.contains("-resetHousehold")
    }

    /// `-dumpHousehold`: print the household as read from the store, at launch and after each save.
    static var wantsHouseholdDump: Bool {
        ProcessInfo.processInfo.arguments.contains("-dumpHousehold")
    }

    /// Deletes the stored household and its people (go-tos and checks stay). Debug builds only.
    static func resetHousehold(in context: ModelContext) {
        do {
            // One by one: a batch delete trips over the person -> household inverse.
            try context.fetch(FetchDescriptor<HouseholdRecord>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<PersonRecord>()).forEach(context.delete)
            try context.save()
            Log.data.notice("Household reset (-resetHousehold)")
        } catch {
            context.rollback()
            Log.data.failure("Household reset failed", error)
        }
    }

    /// Reads the household back from the store (not the in-memory copy) and prints it as JSON to
    /// stdout, one line starting `LS_HOUSEHOLD`. Debug builds only; the data stays on the device
    /// and appended to `Documents/household-dump.txt` in the app's container.
    func dumpStoredHousehold(_ when: String) {
        let stored: Household?
        do {
            stored = try context.fetch(FetchDescriptor<HouseholdRecord>()).first?.household
        } catch {
            FileHandle.standardOutput.write(Data("LS_HOUSEHOLD \(when) unreadable: \(error)\n".utf8))
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = stored.flatMap { try? encoder.encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        let line = "LS_HOUSEHOLD \(when) onboardingDone=\(onboardingDone) \(json)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        // Also appended to Documents/household-dump.txt in the app's own container (simulator: `simctl get_app_container`).
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appending(path: "household-dump.txt") {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
    #endif
}
