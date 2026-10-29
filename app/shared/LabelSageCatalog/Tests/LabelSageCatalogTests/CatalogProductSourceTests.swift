import Foundation
import SQLite3
import LabelSageCore
import Testing
@testable import LabelSageCatalog

/// The fixture is a 23-product cut of the real 2026-10-25 catalog (Scripts/make_fixture.py):
/// Cheerios, 20 products from its category, and two recalled products without ingredients.
@Suite("Catalog product source")
struct CatalogProductSourceTests {
    let source: CatalogProductSource

    init() throws {
        let url = try #require(Bundle.module.url(forResource: "catalog-fixture", withExtension: "sqlite"))
        source = try CatalogProductSource(url: url)
    }

    @Test func scannedBarcodeReturnsTheMergedProduct() async throws {
        let product = try #require(try await source.product(barcode: "016000275287"))  // UPC-A as scanned
        #expect(product.name == "Cheerios Cereal")          // FDC name: the OFF name "My Bff" was rejected
        #expect(product.brand == "Cheerios")
        #expect(product.barcode == "0016000275287")
        #expect(product.ingredientsText?.hasPrefix("Whole Grain Oats") == true)  // unpacked with the dictionary
        #expect(product.servingSize == "39 g")
    }

    @Test func nutrientsArePerServing() async throws {
        let n = try #require(try await source.product(barcode: "0016000275287")?.nutrition)
        // stored per 100 g: 487 mg sodium, 12.82 g protein; serving 39 g
        #expect(abs((n.sodiumMg ?? 0) - 189.93) < 0.01)
        #expect(abs((n.proteinG ?? 0) - 4.9998) < 0.001)
    }

    @Test func unknownOrBrokenBarcodesAreNotFound() async throws {
        #expect(try await source.product(barcode: "0016000275288") == nil)   // bad check digit
        #expect(try await source.product(barcode: "0000000000017") == nil)   // valid, not in the catalog
        #expect(try await source.product(barcode: "abc") == nil)
    }

    @Test func recalledProductWithoutIngredientsCarriesItsRecall() async throws {
        let pizza = try #require(try await source.product(barcode: "666186277621"))
        #expect(pizza.ingredientsText == nil)                // the app shows "Can't confirm"
        let recalls = try await source.recalls(barcode: "666186277621")
        #expect(recalls.first?.reason?.contains("soy") == true)
    }

    @Test func searchFindsByNameWords() async throws {
        let found = try await source.search("cheerio")
        #expect(found.contains { $0.barcode == "0016000275287" })
    }

    @Test func optionsComeFromTheSameCategory() async throws {
        let cheerios = try #require(try await source.product(barcode: "0016000275287"))
        let options = try await source.options(like: cheerios, limit: 5)
        #expect(options.count == 5)
        #expect(options.allSatisfy { $0.category == cheerios.category && $0.barcode != cheerios.barcode })
        #expect(options.allSatisfy { $0.ingredientsText != nil })
    }

    @Test func catalogProductsGoThroughTheAppsVerdictEngine() async throws {
        let engine = VerdictEngine(catalog: try Catalog.bundled())
        let mia = Person(id: "mia", name: "Mia", profile: Profile(allergens: [AllergenChoice(id: "milk")]))
        let household = Household(people: [mia])

        let cheerios = try #require(try await source.product(barcode: "0016000275287"))
        #expect(engine.check(cheerios, for: household).overall != .notFor)   // no milk in Cheerios

        let pizza = try #require(try await source.product(barcode: "666186277621"))
        #expect(engine.check(pizza, for: household).overall == .cantConfirm) // no ingredient list
    }

    /// Safe default: Indonesian ingredient lists stay off the phone until LabelSageCore knows Indonesian words.
    /// Bear Brand's label says "susu sapi steril" (cow's milk); with the list the engine could say "OK for Mia".
    @Test func indonesianProductsGiveCantConfirmNotOK() async throws {
        let engine = VerdictEngine(catalog: try Catalog.bundled())
        let mia = Person(id: "mia", name: "Mia", profile: Profile(allergens: [AllergenChoice(id: "milk")]))

        let bearBrand = try #require(try await source.product(barcode: "8992696404441"))
        #expect(bearBrand.ingredientsText == nil)
        #expect(engine.check(bearBrand, for: Household(people: [mia])).overall == .cantConfirm)
    }

    @Test func barcodeRulesMatchTheETL() {
        #expect(CatalogProductSource.gtin("6 66186 27762 1") == 666186277621)
        #expect(CatalogProductSource.gtin("016000275287") == 16000275287)
        #expect(CatalogProductSource.imageURL(gtin: 16000275287, file: "front_en.8.400.jpg")?.absoluteString
                == "https://images.openfoodfacts.org/images/products/001/600/027/5287/front_en.8.400.jpg")
    }

    @Test func catalogOfAnotherSchemaIsRefused() throws {
        // a copy of the fixture that says it was built for another schema version
        let fixture = try #require(Bundle.module.url(forResource: "catalog-fixture", withExtension: "sqlite"))
        let copy = FileManager.default.temporaryDirectory.appending(path: "catalog-other-schema-\(UUID()).sqlite")
        try FileManager.default.copyItem(at: fixture, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        try Self.execute("UPDATE catalog_meta SET value = '999' WHERE key = 'schema_version'", in: copy)

        #expect(throws: CatalogError.schemaMismatch(found: "999", expected: CatalogProductSource.schemaVersion)) {
            try CatalogProductSource(url: copy)
        }
    }

    private static func execute(_ sql: String, in url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw CatalogError.cannotOpen(url.path) }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw CatalogError.query(sql) }
    }
}
