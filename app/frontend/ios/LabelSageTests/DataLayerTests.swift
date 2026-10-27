import Foundation
import SwiftData
import Testing
import LabelSageCore
@testable import LabelSage

/// T6: SwiftData records ↔ LabelSageCore values, the fixture product source, the verdict service and
/// the explanation check and fallback.
@MainActor
struct RecordMappingTests {
    private func context() throws -> ModelContext {
        ModelContext(try SchemaV1.makeContainer(inMemory: true))
    }

    private var fullHousehold: Household {
        Household(people: [
            Person(id: "you", name: "Alex", isOwner: true, profile: Profile(
                allergens: [AllergenChoice(id: "treenuts", severity: .allergy, leaves: ["almond", "cashew"])],
                mayContain: false, medical: ["celiac"], diets: ["vegan"],
                avoid: [AvoidChoice(id: "seed", strength: .preferNot)],
                custom: [CustomChoice(label: "Cilantro", terms: ["cilantro", "coriander leaf"])],
                goals: Goals(proteinG: 25, kcal: 2000))),
            Person(id: "mia", name: "Mia", profile: Profile(allergens: [AllergenChoice(id: "peanut", severity: .intolerance)])),
            Person(id: "leo", name: "Leo"),
        ], region: Region(zip: "78701", city: "Austin, TX"), store: Store(id: "wfm", name: "Whole Foods Market", distanceMiles: 1.2))
    }

    @Test func householdRoundTripsThroughTheStore() throws {
        let ctx = try context()
        ctx.insert(try HouseholdRecord(fullHousehold))
        try ctx.save()
        let fetched = try #require(try ctx.fetch(FetchDescriptor<HouseholdRecord>()).first)
        #expect(try fetched.household == fullHousehold)
    }

    @Test func sampleHouseholdRoundTrips() throws {
        let sample = try SampleData.household()
        #expect(try HouseholdRecord(sample).household == sample)
    }

    @Test func noRegionOrStoreStaysNil() throws {
        let h = Household(people: [Person(id: "you", name: "Alex", isOwner: true)])
        #expect(try HouseholdRecord(h).household == h)
    }

    @Test func corruptProfileFailsClosed() throws {
        let ctx = try context()
        let record = try HouseholdRecord(fullHousehold, onboardingDone: true)
        ctx.insert(record)
        let mia = try #require(record.people.first { $0.personId == "mia" })
        mia.profileData = Data("{not json".utf8)
        try ctx.save()

        #expect(throws: RecordError.unreadableProfile) { try mia.person }
        #expect(throws: RecordError.unreadableProfile) { try record.household }

        let model = AppModel(context: ctx)
        #expect(model.household == nil)
        #expect(model.needsProfileRecheck)
        #expect(model.onboardingDone)

        // Saving the profiles again clears the state.
        try model.save(fullHousehold)
        #expect(!model.needsProfileRecheck)
        #expect(AppModel(context: ctx).household == fullHousehold)
    }

    @Test func updateReplacesPeopleWithoutOrphans() throws {
        let ctx = try context()
        let record = try HouseholdRecord(fullHousehold)
        ctx.insert(record)
        try ctx.save()
        var changed = fullHousehold
        changed.people.removeLast()
        changed.people[1].profile.allergens.append(AllergenChoice(id: "sesame"))
        try record.update(from: changed)
        try ctx.save()
        #expect(try record.household == changed)
        #expect(try ctx.fetch(FetchDescriptor<PersonRecord>()).count == 2)
    }

    @Test func goToAndCheckKeepTheProduct() throws {
        let product = try #require(try SampleData.products().first)
        let goTo = try GoToRecord(product)
        #expect(goTo.product == product)
        #expect(goTo.ingredientsHash == GoToRecord.hash(product.ingredientsText ?? ""))
        let verdict = VerdictService().check(product, for: try SampleData.household()).verdict
        let check = try CheckRecord(product, verdict: verdict)
        #expect(check.product == product)
        #expect(check.level == verdict.overall)
        #expect(check.line == verdict.line)
    }

    @Test func appModelSeedsAndReloadsTheDemoHousehold() throws {
        let ctx = try context()
        let model = AppModel(context: ctx)
        #expect(model.household == nil)
        #expect(!model.onboardingDone)
        try model.seedDemoHousehold()
        #expect(model.onboardingDone)
        let reloaded = AppModel(context: ctx)
        #expect(reloaded.household == (try SampleData.household()))
        #expect(reloaded.onboardingDone)
    }

    @Test func lookupsFillTheProductCache() async throws {
        let model = AppModel(context: try context())
        let product = try await model.lookup(barcode: "0000000000062", region: nil, in: FixtureProductSource(delayMilliseconds: 0...0))
        #expect(model.product(id: product.id) == product)
        #expect(model.product(id: "unknown") == nil)
    }
}

@MainActor
struct RouterTests {
    @Test func productSheetOpensOverTheCamera() {
        let router = Router()
        router.openCamera()
        router.present(.product(id: "a"))
        #expect(router.sheet == nil)
        #expect(router.cameraSheet?.sheet == .product(id: "a"))
        #expect(router.topLayer === router.cameraSheet)
    }

    @Test func openingTheCameraClosesAHomeSheet() {
        let router = Router()
        router.present(.product(id: "a"))
        router.openCamera()
        router.present(.product(id: "b"))
        #expect(router.sheet == nil)
        #expect(router.cameraSheet?.sheet == .product(id: "b"))
    }

    @Test func otherLevelWordingMatchesWholeWordsOnly() {
        #expect(!ExplanationCheck.containsOtherLevel("look for whey in the list.", level: .notFor))
        #expect(ExplanationCheck.containsOtherLevel("ok for [person].", level: .notFor))
        #expect(ExplanationCheck.containsOtherLevel("we can't confirm it.", level: .notFor))
    }

    @Test func pushesAndSheetsFromInsideASheet() throws {
        let router = Router()
        router.present(.product(id: "a"))
        router.push(.product(id: "b"))
        #expect(router.path.isEmpty)
        #expect(router.sheet?.path == [.product(id: "b")])
        router.present(.product(id: "c"))
        let child = try #require(router.sheet?.child)
        #expect(child.sheet == .product(id: "c"))
        router.push(.product(id: "d"))
        #expect(child.path == [.product(id: "d")])
        router.dismissTop()
        #expect(router.sheet?.child == nil)
        router.dismissTop()
        #expect(router.sheet == nil)
        router.push(.product(id: "e"))
        #expect(router.path == [.product(id: "e")])
        router.popToRoot()
        #expect(router.path.isEmpty)
    }
}

struct FixtureProductSourceTests {
    private let source = FixtureProductSource(delayMilliseconds: 0...0)
    private let region = Region(zip: "78701")

    @Test func findsABarcode() async throws {
        let product = try await source.product(barcode: "0000000000062", region: region)
        #expect(product?.name == "Creamy Peanut Butter")
    }

    @Test func unknownBarcodeIsNotFound() async throws {
        #expect(try await source.product(barcode: "1234567890128", region: region) == nil)
        await #expect(throws: ProductSourceError.notFound) {
            try await source.requireProduct(barcode: "1234567890128", region: region)
        }
    }

    @Test func offlineThrowsOfflineEverywhere() async throws {
        let offline = FixtureProductSource(delayMilliseconds: 0...0, isOffline: true)
        await #expect(throws: ProductSourceError.offline) { try await offline.product(barcode: "0000000000062", region: region) }
        await #expect(throws: ProductSourceError.offline) { try await offline.search("chips", region: region, store: nil, limit: 5) }
        await #expect(throws: ProductSourceError.offline) { try await offline.requireProduct(barcode: "0000000000062", region: region) }
        await offline.setOffline(false)
        #expect(try await offline.product(barcode: "0000000000062", region: region) != nil)
    }

    @Test func searchMatchesEveryWordAndRespectsTheLimit() async throws {
        let hits = try await source.search("kettle chips", region: region, store: nil, limit: 10)
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { $0.name.lowercased().contains("kettle") && $0.name.lowercased().contains("chips") })
        #expect(try await source.search("kettle", region: region, store: nil, limit: 1).count == 1)
        #expect(try await source.search("  ", region: region, store: nil, limit: 5).isEmpty)
    }

    @Test func optionsAreTheSameCategoryWithIngredients() async throws {
        let chips = try #require(try await source.product(barcode: "0000000000017", region: region))
        let options = try await source.options(like: chips, region: region, store: nil, limit: 10)
        #expect(!options.isEmpty)
        #expect(options.allSatisfy { $0.category == chips.category && $0.id != chips.id && $0.ingredientsText != nil })
    }

    @Test func storesComeFromTheSampleHousehold() async throws {
        #expect(try await source.stores(near: region).map(\.id) == ["wfm"])
    }

    @Test func otherErrorsMapToNotFound() {
        #expect(ProductSourceError(CocoaError(.fileReadCorruptFile)) == .notFound)
        #expect(ProductSourceError(ProductSourceError.offline) == .offline)
        #expect(ProductSourceError(CancellationError()) == .cancelled)
    }

    @Test func cancellationIsNotNotFound() async {
        let slow = FixtureProductSource(delayMilliseconds: 5_000...5_000)
        // Repeated: the cancel races the task's start, and both orders must give `.cancelled`.
        // `task.result` and a plain comparison: `#expect(throws:)` around a typed-throws `Task.value`
        // crashed Swift Testing's value reflection on this toolchain.
        for _ in 0 ..< 50 {
            let task = Task { try await slow.requireProduct(barcode: "0000000000062", region: nil) }
            task.cancel()
            let error: (any Error)?
            switch await task.result {
            case .success: error = nil
            case .failure(let failure): error = failure
            }
            #expect(error as? ProductSourceError == .cancelled)
        }
    }

    @Test func barcodeAndQueryAreTrimmed() async throws {
        #expect(try await source.product(barcode: " 0000000000062\n", region: region) != nil)
        #expect(try await source.search("  peanut butter  ", region: region, store: nil, limit: 5).count == 1)
    }

    @Test func factoryReturnsTheFixturesToday() {
        #expect(ProductSourceFactory.make() is FixtureProductSource)
    }
}

struct VerdictServiceTests {
    @Test func posesFollowTheLevel() {
        #expect(VerdictService.pose(for: .notFor) == .guard)
        #expect(VerdictService.pose(for: .checkFirst) == .thinking)
        #expect(VerdictService.pose(for: .ok) == .done)
        #expect(VerdictService.pose(for: .cantConfirm) == .thinking)
    }

    @Test func peanutButterIsNotForMia() throws {
        let product = try #require(try SampleData.products().first { $0.barcode == "0000000000062" })
        let result = VerdictService().check(product, for: try SampleData.household())
        #expect(result.verdict.overall == .notFor)
        #expect(result.pose == .guard)
        #expect(result.verdict.line.contains("Not for Mia"))
    }

    @Test func serviceMatchesTheEngineForEveryFixture() throws {
        let household = try SampleData.household()
        let service = VerdictService()
        for product in try SampleData.products() {
            let result = service.check(product, for: household)
            #expect(result.verdict == service.engine.check(product, for: household))
            #expect(result.pose == VerdictService.pose(for: result.verdict.overall))
        }
    }
}

struct ExplanationTests {
    /// Mia's real verdict from the engine on the fixture peanut butter.
    private let product: Product
    private let mia: PersonVerdict

    init() throws {
        product = try #require(try SampleData.products().first { $0.barcode == "0000000000062" })
        let verdict = VerdictService().check(product, for: try SampleData.household()).verdict
        mia = try #require(verdict.people.first { $0.id == "mia" })
    }

    private var facts: ExplanationService.Facts { ExplanationService.facts(for: mia, product: product) }

    @Test func promptNeverCarriesTheName() {
        #expect(!facts.prompt.contains("Mia"))
        #expect(facts.prompt.contains("[person]"))
        #expect(facts.prompt.lowercased().contains("peanut"))
        #expect(!ExplanationService.instructions.contains("Mia"))
    }

    @Test func maskIsWholeWordAndSkipsYou() {
        #expect(ExplanationService.mask("Ann", in: "Not for Ann. Contains annatto.") == "Not for [person]. Contains annatto.")
        #expect(ExplanationService.mask("you", in: "OK for you.") == "OK for you.")
    }

    @Test func maskHandlesShortNamesRegexCharactersAndSpaces() {
        #expect(ExplanationService.mask("Al", in: "Not for Al. Contains almond. Almond is Al\u{2019}s.")
                == "Not for [person]. Contains almond. Almond is [person]\u{2019}s.")
        #expect(ExplanationService.mask("A.J.", in: "Not for A.J. Contains AxJx.") == "Not for [person] Contains AxJx.")
        #expect(ExplanationService.mask("Leo Jr.", in: "OK for Leo Jr. Nothing Leo Jr. avoids is in it.")
                == "OK for [person] Nothing [person] avoids is in it.")
        #expect(ExplanationService.mask("Mary Ann", in: "Not for Mary Ann. Mary and Ann differ.")
                == "Not for [person]. Mary and Ann differ.")
        let both = ExplanationService.mask("Leo", in: ExplanationService.mask("Mia", in: "Mia and Leo, not Miami."))
        #expect(both == "[person] and [person], not Miami.")
    }

    @Test func checkAcceptsAGoodRewrite() {
        #expect(ExplanationCheck.failure("Not for [person]: the first ingredient is peanuts.", facts: facts) == nil)
    }

    @Test func checkRejectsEachBrokenRule() {
        #expect(ExplanationCheck.failure("  ", facts: facts) == .empty)
        #expect(ExplanationCheck.failure(String(repeating: "peanuts [person] ", count: 20), facts: facts) == .tooLong)
        for word in ["safe", "Safer", "unsafe", "100%", "guaranteed", "allergy-proof", "protected"] {
            #expect(ExplanationCheck.failure("[person] has peanuts, \(word).", facts: facts) == .denyWord, "\(word)")
        }
        #expect(ExplanationCheck.failure("Sorry, I can't help with peanuts for [person].", facts: facts) == .refusal)
        #expect(ExplanationCheck.failure("Not for [person] \u{2014} peanuts.", facts: facts) == .dash)
        #expect(ExplanationCheck.failure("Not for [person]. It has nuts.", facts: facts) == .missingMatchedTerm)
        #expect(ExplanationCheck.failure("Not for her. Contains peanuts.", facts: facts) == .missingPerson)
    }

    @Test func safflowerIsNotADenyWord() {
        #expect(!ExplanationCheck.containsDenyWord("safflower oil"))
        #expect(!ExplanationCheck.containsDenyWord("proof of allergy"))
    }

    @Test func hyphenatedDenyWordsAreCaught() {
        for text in ["safe-to-eat", "not-safe", "100%-safe", "allergy proof", "Allergy-Proof bar", "it is 100% fine"] {
            #expect(ExplanationCheck.containsDenyWord(text.lowercased()), "\(text)")
        }
    }

    @Test func checkRejectsAnotherLevelsWording() {
        #expect(facts.level == .notFor)
        #expect(ExplanationCheck.failure("OK for [person], peanuts are fine.", facts: facts) == .otherLevel)
        #expect(ExplanationCheck.failure("Check first: [person] and peanuts.", facts: facts) == .otherLevel)
        #expect(ExplanationCheck.failure("Can't confirm peanuts for [person].", facts: facts) == .otherLevel)
        #expect(ExplanationCheck.failure("Can\u{2019}t confirm peanuts for [person].", facts: facts) == .otherLevel)
        #expect(ExplanationCheck.failure("Not for [person]: peanuts come first.", facts: facts) == nil)
    }

    @Test func acceptedTextGetsTheNameBack() async {
        let service = ExplanationService { _ in "Not for [person]: peanuts come first." }
        #expect(await service.explain(mia, product: product) == Explanation(text: "Not for Mia: peanuts come first.", fromModel: true))
    }

    @Test func fallsBackWhenUnavailableFailingOrRejected() async {
        let template = Explanation(text: mia.reason, fromModel: false)
        #expect(await ExplanationService { _ in "OK for [person], peanuts." }.explain(mia, product: product) == template)
        #expect(await ExplanationService { _ in nil }.explain(mia, product: product) == template)
        #expect(await ExplanationService { _ in throw CancellationError() }.explain(mia, product: product) == template)
        #expect(await ExplanationService { _ in "It is safe for [person], peanuts." }.explain(mia, product: product) == template)
        #expect(await ExplanationService { _ in "Not for [person]." }.explain(mia, product: product) == template)
    }
}
