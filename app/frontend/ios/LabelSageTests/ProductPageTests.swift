import Foundation
import Testing
import LabelSageCore
@testable import LabelSage

/// The product page's real logic (spec 04): sections per state, the "What you avoid" rows from the
/// engine's findings, key ingredients, and nutrition per serving vs per 100 g.
@MainActor
struct ProductPageTests {
    let household = try! SampleData.household()
    let products = try! SampleData.products()
    let service = VerdictService()
    let catalog = VerdictService.bundledCatalog

    func product(_ barcode: String) -> Product { products.first { $0.barcode == barcode }! }
    var chips: Product { product("0000000000017") }
    var trailMix: Product { product("0000000000086") }
    var oliveOilChips: Product { product("0000000000024") }

    func option(_ p: Product) -> ProductOption { ProductOption(product: p, verdict: service.check(p, for: household).verdict) }

    // MARK: sections per state

    @Test func notForWithAnOptionShowsTryInsteadAndEverySection() {
        let verdict = service.check(chips, for: household).verdict
        #expect(verdict.overall == .notFor)
        let layout = ProductPageLayout.make(product: chips, verdict: verdict, photo: .shown, options: [option(oliveOilChips)])
        #expect(layout.showsHero)
        #expect(!layout.signalOnHero) // no photo: the flag moves next to the name
        #expect(layout.showsTryInstead)
        #expect(layout.hasIngredients)
        #expect(layout.hasNutrition)
        #expect(layout.showsOptions)
        #expect(layout.dataAge == nil)
    }

    @Test func noIngredientsNoNutritionAndNoOptions() {
        let verdict = service.check(trailMix, for: household).verdict
        #expect(verdict.overall == .cantConfirm)
        let layout = ProductPageLayout.make(product: trailMix, verdict: verdict, photo: .hidden, options: [])
        #expect(!layout.showsHero)
        #expect(!layout.hasIngredients)
        #expect(!layout.hasNutrition)
        #expect(!layout.showsOptions)
        #expect(!layout.showsTryInstead)
    }

    @Test func okHasNoTryInsteadAndAPhotoPutsTheSignalOnTheHero() {
        var withPhoto = oliveOilChips
        withPhoto.imageURL = URL(string: "file:///tmp/pack.png")
        let verdict = service.check(withPhoto, for: household).verdict
        #expect(verdict.overall == .ok)
        let layout = ProductPageLayout.make(product: withPhoto, verdict: verdict, photo: .shown, options: [option(chips)])
        #expect(layout.signalOnHero)
        #expect(!layout.showsTryInstead)
    }

    @Test func oldDataShowsItsAge() {
        var old = chips
        old.dataUpdatedAt = Date(timeIntervalSince1970: 1_780_000_000) // 28 May 2026
        let now = Date(timeIntervalSince1970: 1_793_000_000) // Oct 2026
        let layout = ProductPageLayout.make(product: old, verdict: service.check(old, for: household).verdict,
                                            photo: .shown, options: [], now: now)
        #expect(layout.dataAge == "Data updated May 2026")
    }

    @Test func onlyOptionsOKForEveryoneAreOffered() {
        let offered = ProductOption.offered([option(chips), option(oliveOilChips)])
        #expect(offered.map(\.product.name) == [oliveOilChips.name])
    }

    @Test func bannerTitleIsThePersonLineWithMoreThanOnePerson() {
        let verdict = service.check(chips, for: household).verdict
        #expect(ProductPage.bannerTitle(verdict) == verdict.line)
        let alone = Household(people: [household.people[0]])
        #expect(ProductPage.bannerTitle(service.check(chips, for: alone).verdict) == "Not for you")
    }

    // MARK: What you avoid

    @Test func findingsMapToWhatYouAvoidRows() {
        let verdict = service.check(chips, for: household).verdict
        let rows = AvoidRow.rows(for: household, verdict: verdict, catalog: catalog)
        let byLabel = Dictionary(uniqueKeysWithValues: rows.map { ($0.label, $0) })
        // Alex: seed oils (sunflower oil), gluten, added sugars (cane sugar, prefer not). Mia: peanut, tree nuts.
        #expect(rows.map(\.label) == ["Avoid seed oils", "Avoid gluten", "Limit added sugars", "Peanut allergy", "Tree nuts allergy"])
        #expect(byLabel["Avoid seed oils"]?.level == .notFor)
        #expect(byLabel["Avoid gluten"]?.level == .ok)
        #expect(byLabel["Limit added sugars"]?.level == .checkFirst)
        #expect(byLabel["Peanut allergy"]?.level == .ok)
        #expect(byLabel["Peanut allergy"]?.personName == "Mia")
        #expect(AvoidRow.summary(rows) == "1 to avoid \u{00B7} 1 to check")
    }

    @Test func noIngredientListMakesEveryRowCantConfirm() {
        let rows = AvoidRow.rows(for: household, verdict: service.check(trailMix, for: household).verdict, catalog: catalog)
        #expect(rows.allSatisfy { $0.level == .cantConfirm })
    }

    @Test func switchingARowOffRechecksWithoutThatChoiceOnly() {
        let verdict = service.check(chips, for: household).verdict
        let rows = AvoidRow.rows(for: household, verdict: verdict, catalog: catalog)
        let seed = rows.first { $0.label == "Avoid seed oils" }!
        let checked = AvoidRow.household(household, without: [seed.id], rows: rows)
        #expect(checked.people[0].profile.avoid.map(\.id) == ["gluten", "sugar"])
        #expect(checked.people[1] == household.people[1])
        #expect(service.check(chips, for: checked).verdict.overall == .checkFirst)
        // The household passed in is never changed.
        #expect(household.people[0].profile.avoid.count == 3)
    }

    // MARK: Key ingredients

    @Test func keyIngredientsCarryTheWorstFindingAndItsRule() {
        let verdict = service.check(chips, for: household).verdict
        let rows = IngredientRow.rows(verdict: verdict, avoidRows: AvoidRow.rows(for: household, verdict: verdict, catalog: catalog),
                                      catalog: catalog)
        #expect(rows.map(\.name) == ["Yellow corn", "Sunflower oil", "Cane sugar", "Sea salt"])
        #expect(rows.map(\.level) == [.ok, .notFor, .checkFirst, .ok])
        #expect(rows[1].tone == "Not for you \u{00B7} Avoid seed oils")
        #expect(rows[2].tone == "Check first \u{00B7} Limit added sugars")
        #expect(rows[1].why.hasPrefix("The 2nd ingredient."))
    }

    // MARK: Nutrition

    @Test func perServingAndPer100gMath() throws {
        let n = try #require(chips.nutrition)
        let grams = NutritionFacts.grams(inServing: chips.servingSize)
        #expect(grams == 28)
        let serving = try #require(NutritionFacts.rows(n, basis: .serving, servingGrams: grams))
        let per100 = try #require(NutritionFacts.rows(n, basis: .per100g, servingGrams: grams))
        let s = Dictionary(uniqueKeysWithValues: serving.map { ($0.label, $0) })
        let h = Dictionary(uniqueKeysWithValues: per100.map { ($0.label, $0) })
        #expect(s["Calories"]?.amount == "120")
        #expect(s["Total fat"]?.amount == "4.5 g")
        #expect(s["Total fat"]?.dailyValue == "6%")
        #expect(s["Sodium"]?.dailyValue == "5%")
        #expect(s["Added sugars"]?.dailyValue == "8%")
        // 120 × 100 / 28 = 428.6 → 429; 4.5 × 100 / 28 = 16.07 → 16.1; 105 mg → 375
        #expect(h["Calories"]?.amount == "429")
        #expect(h["Total fat"]?.amount == "16.1 g")
        #expect(h["Sodium"]?.amount == "375 mg")
        #expect(h["Total fat"]?.dailyValue == "")
        // Per 100 g needs the serving's grams.
        #expect(NutritionFacts.rows(n, basis: .per100g, servingGrams: nil) == nil)
        #expect(NutritionFacts.grams(inServing: "1 cup (240 ml)") == nil)
    }

    @Test func donutSharesOfCalories() throws {
        let n = try #require(chips.nutrition)
        let macros = NutritionFacts.macros(n)
        #expect(macros.map(\.percent) == [64, 33, 3])
        #expect(macros.map(\.kcal) == [80, 40.5, 4])
        #expect(NutritionFacts.donutLabel(n) == "120 calories per serving. Carbs 64%, fat 33%, protein 3% of calories.")
        #expect(NutritionFacts.macros(Nutrition(kcal: 0)).isEmpty)
    }

    @Test func addedSugarIsFlaggedWhenARuleCares() {
        #expect(NutritionFacts.isFlagged(.addedSugarsG, verdict: service.check(chips, for: household).verdict))
        #expect(!NutritionFacts.isFlagged(.sodiumMg, verdict: service.check(chips, for: household).verdict))
    }

    @Test func sizeLineCountsServings() {
        #expect(ProductHeader.sizeLine(size: "3 oz", servingSize: "28 g (about 15 chips)") == "3 oz \u{00B7} 3 servings of 28 g")
        #expect(ProductHeader.sizeLine(size: "96 fl oz", servingSize: "240 ml") == "96 fl oz \u{00B7} serving 240 ml")
        #expect(ProductHeader.sizeLine(size: nil, servingSize: "30 g") == "30 g serving")
        #expect(ProductHeader.sizeLine(size: nil, servingSize: nil) == nil)
    }
}
