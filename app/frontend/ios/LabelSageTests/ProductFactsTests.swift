import Foundation
import Testing
import LabelSageCore
@testable import LabelSage

/// The facts on chat product cards and product tiles: reason chips from the engine's findings and the
/// product data, the nutrition line and the spoken label.
@MainActor
struct ProductFactsTests {
    let household = try! SampleData.household()
    let products = try! SampleData.products()
    let service = VerdictService()
    let catalog = VerdictService.bundledCatalog

    func product(_ barcode: String) -> Product { products.first { $0.barcode == barcode }! }
    var chips: Product { product("0000000000017") }
    var oliveOilChips: Product { product("0000000000024") }

    func notes(_ p: Product, household: Household? = nil, limit: Int = 3) -> [ProductRow.Note] {
        ProductFacts.notes(product: p, verdict: service.check(p, for: self.household).verdict,
                           household: household ?? self.household, catalog: catalog, limit: limit)
    }

    @Test func whatDecidedNotForComesFirstInRed() {
        let found = notes(chips)
        #expect(found.first == ProductRow.Note(level: .notFor, text: "Sunflower oil"))
        #expect(found.count <= 3)
        #expect(found.map(\.level) == found.map(\.level).sorted(by: >)) // worst first
    }

    @Test func anOKProductGetsGoodFactsInGreen() {
        let found = notes(oliveOilChips)
        #expect(!found.isEmpty)
        #expect(found.allSatisfy { $0.level == .ok })
        #expect(found.contains { $0.text == "No seed oils listed" })
    }

    @Test func noHouseholdMeansNoNoXChips() {
        let verdict = service.check(oliveOilChips, for: household).verdict
        let found = ProductFacts.notes(product: oliveOilChips, verdict: verdict, household: nil, catalog: catalog)
        #expect(!found.contains { $0.text.hasPrefix("No seed") })
    }

    @Test func limitCapsTheChips() {
        #expect(notes(chips, limit: 1).count == 1)
    }

    @Test func noChipEverSaysSafe() {
        for p in products {
            for note in notes(p) { #expect(!note.text.lowercased().contains("safe")) }
        }
    }

    @Test func nutritionLineIsPerServing() {
        #expect(ProductFacts.nutritionLine(Nutrition(kcal: 120, addedSugarsG: 4, proteinG: 1))
                == "120 kcal \u{00B7} 1 g protein \u{00B7} 4 g added sugar per serving")
        #expect(ProductFacts.nutritionLine(Nutrition(addedSugarsG: 0)) == "0 g added sugar per serving")
        #expect(ProductFacts.nutritionLine(Nutrition()) == nil)
        #expect(ProductFacts.nutritionLine(nil) == nil)
    }

    @Test func spokenLabelReadsNameVerdictPriceThenChips() {
        let label = ProductFacts.spokenLabel(name: "Popped Corn Chips", verdictLine: "Not for you \u{00B7} OK for Mia",
                                             price: "$4.29", notes: ["Sunflower oil"], extra: [nil, "3 oz"])
        #expect(label == "Popped Corn Chips. Not for you, OK for Mia. $4.29. Sunflower oil. 3 oz")
    }
}
