import Foundation
import Testing
import LabelSageCore
@testable import LabelSage

/// T8: the "Check a product" state machine on fixtures (spec 03 states).
@MainActor
struct ScanModelTests {
    private let household = Household(people: [
        Person(id: "you", name: "Alex", isOwner: true,
               profile: Profile(allergens: [AllergenChoice(id: "peanut")])),
    ])

    private let peanutButter = Product(barcode: "0000000000062", name: "Creamy Peanut Butter",
                                       ingredientsText: "Peanuts, salt.")
    private let crackers = Product(barcode: "0000000000079", name: "Rice Crackers",
                                   ingredientsText: "Rice, salt.")
    private let trailMix = Product(barcode: "0000000000086", name: "Trail Mix, Classic", ingredientsText: nil)

    private func model(offline: Bool = false, delay: ClosedRange<Int> = 0...0,
                       timeout: Duration = .seconds(8)) -> ScanModel {
        ScanModel(source: FixtureProductSource(products: [peanutButter, crackers, trailMix],
                                               delayMilliseconds: delay, isOffline: offline),
                  verdictService: VerdictService(), household: household, region: nil, timeout: timeout)
    }

    @Test func barcodeGoesThroughCheckingToProduct() async {
        let m = model()
        m.barcodeRead("0000000000079")
        #expect(m.phase == .checking(barcode: "0000000000079"))
        #expect(m.foundCount == 1)
        await m.lookupTask?.value
        guard case .product(let result) = m.phase else { Issue.record("expected product, got \(m.phase)"); return }
        #expect(result.product == crackers)
        #expect(result.verdict.verdict.overall == .ok)
    }

    @Test func verdictComesFromTheEngine() async {
        let m = model()
        await m.startLookup("0000000000062").value
        guard case .product(let result) = m.phase else { Issue.record("expected product"); return }
        #expect(result.verdict.verdict.overall == .notFor)
        #expect(result.verdict.pose == .guard)
        #expect(!result.reason.isEmpty)
    }

    @Test func unknownBarcodeIsNotFound() async {
        let m = model()
        await m.startLookup("012345678905").value
        #expect(m.phase == .notFound(barcode: "012345678905"))
    }

    @Test func offlineSourceShowsOffline() async {
        let m = model(offline: true)
        await m.startLookup("0000000000079").value
        #expect(m.phase == .offline)
    }

    @Test func tryAgainRepeatsTheLastLookup() async {
        let m = model(offline: true)
        await m.startLookup("0000000000079").value
        m.tryAgain()
        #expect(m.phase == .checking(barcode: "0000000000079"))
    }

    @Test func noIngredientListIsItsOwnState() async {
        let m = model()
        await m.startLookup("0000000000086").value
        guard case .noIngredients(let result) = m.phase else { Issue.record("expected noIngredients, got \(m.phase)"); return }
        #expect(result.verdict.verdict.overall == .cantConfirm)
    }

    @Test func cancelledLookupIsIgnored() async {
        let m = model(delay: 50...50)
        m.barcodeRead("012345678905")
        let task = m.lookupTask
        m.checkAnother()
        await task?.value
        // Never "not found" after a cancel.
        #expect(m.phase == .idle)
    }

    @Test func slowLookupTimesOutAsOffline() async {
        let m = model(delay: 2000...2000, timeout: .milliseconds(30))
        await m.startLookup("0000000000079").value
        #expect(m.phase == .offline)
    }

    @Test func sameCodeIsDebounced() async {
        let m = model()
        m.barcodeRead("0000000000079")
        await m.lookupTask?.value
        m.checkAnother()
        m.barcodeRead("0000000000079")
        #expect(m.phase == .idle)
        m.barcodeRead("0000000000062")
        #expect(m.phase == .checking(barcode: "0000000000062"))
    }

    @Test func readsAreIgnoredWhenNotIdleOrInIngredientsMode() {
        let m = model()
        m.mode = .ingredients
        m.barcodeRead("0000000000079")
        #expect(m.phase == .idle)
        m.mode = .barcode
        m.phase = .notFound(barcode: "1")
        m.barcodeRead("0000000000079")
        #expect(m.phase == .notFound(barcode: "1"))
    }

    @Test func enteredCodeNeeds12Or13Digits() {
        #expect(ScanModel.isValidEnteredCode("012345678905"))
        #expect(ScanModel.isValidEnteredCode("0000000000079"))
        #expect(!ScanModel.isValidEnteredCode("12345"))
        let m = model()
        m.codeEntered("12345")
        #expect(m.phase == .idle)
        m.mode = .ingredients
        m.codeEntered("0 12345 67890 5")
        #expect(m.phase == .checking(barcode: "012345678905"))
        #expect(m.mode == .barcode)
    }

    @Test func ingredientsPhotoBecomesYourPhoto() {
        let m = model()
        m.readingStarted()
        #expect(m.phase == .reading)
        m.ingredientsRecognized(["Nutrition Facts 120 kcal", "INGREDIENTS: Rice, peanuts,", "salt.", "May contain milk."])
        guard case .product(let result) = m.phase else { Issue.record("expected product, got \(m.phase)"); return }
        #expect(result.product.name == ScanModel.photoName)
        #expect(result.product.ingredientsText?.hasPrefix("INGREDIENTS") == true)
        #expect(result.verdict.verdict.overall == .notFor)
    }

    @Test func photoWithoutAListIsUnreadable() {
        let m = model()
        m.readingStarted()
        m.ingredientsRecognized([])
        #expect(m.phase == .unreadable)
    }

    @Test func lateOcrAfterCheckAnotherIsIgnored() {
        let m = model()
        m.readingStarted()
        m.checkAnother()
        m.ingredientsRecognized(["Ingredients: rice."])
        #expect(m.phase == .idle)
    }

    @Test func closingWhileAPhotoIsReadDropsIt() {
        let m = model()
        m.mode = .ingredients
        m.readingStarted()
        m.stop()
        #expect(m.phase == .idle)
        m.ingredientsRecognized(["Ingredients: rice, peanuts."])
        #expect(m.phase == .idle)
    }

    @Test func closingDuringALookupDropsIt() async {
        let m = model(delay: 300...300)
        let lookup = m.startLookup("0000000000062")
        m.stop()
        await lookup.value
        #expect(m.phase == .idle)
    }

    @Test func cameraOffAndBack() {
        let m = model()
        m.cameraAccess(granted: false)
        #expect(m.phase == .cameraOff)
        m.cameraAccess(granted: true)
        #expect(m.phase == .idle)
    }

    @Test func photoTheIngredientsSwitchesMode() async {
        let m = model()
        await m.startLookup("012345678905").value
        m.markReported()
        m.photoTheIngredients()
        #expect(m.phase == .idle)
        #expect(m.mode == .ingredients)
        #expect(!m.reported)
    }
}

struct ScanFormatTests {
    @Test func barcodeDisplay() {
        #expect(BarcodeFormat.display("028400590318") == "0 28400 59031 8")
        #expect(BarcodeFormat.display("4006381333931") == "4 006381 333931")
        #expect(BarcodeFormat.display("96385074") == "9638 5074")
        #expect(BarcodeFormat.display("123") == "123")
    }

    @Test func ingredientsTextStartsAtTheWordIngredients() {
        #expect(IngredientsText.extract(from: ["Calories 90", "Ingredients: oats, honey."]) == "Ingredients: oats, honey.")
        #expect(IngredientsText.extract(from: ["oats, honey."]) == "oats, honey.")
        #expect(IngredientsText.extract(from: ["  ", ""]) == nil)
    }
}
