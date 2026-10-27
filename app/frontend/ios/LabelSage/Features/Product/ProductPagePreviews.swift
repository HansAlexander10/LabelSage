#if DEBUG
import SwiftUI
import LabelSageCore

/// Fixture products and the demo household (Alex "you" and Mia) for the product page previews.
enum ProductPagePreviewData {
    static let household = (try? SampleData.household()) ?? Household(people: [Person(id: "you", name: "Alex", isOwner: true)])
    static let products = (try? SampleData.products()) ?? []

    static func product(_ barcode: String) -> Product {
        products.first { $0.barcode == barcode } ?? Product(name: "Missing fixture \(barcode)", ingredientsText: nil)
    }

    /// Not for: sunflower oil (Alex avoids seed oils), cane sugar (Alex limits added sugars).
    static let chips = product("0000000000017")
    /// OK for you and Mia.
    static let oliveOilChips = product("0000000000024")
    /// Check first: cane sugar only.
    static let poppedChips = product("0000000000055")
    /// No ingredient list and no nutrition: Can't confirm.
    static let trailMix = product("0000000000086")
    /// Can't confirm with a list: "natural flavors" could be gluten, which Alex avoids.
    static let riceCrackers = Product(barcode: "preview-rice", name: "Rice Crackers, Sea Salt", brand: "Meadow", size: "3.5 oz",
                                      servingSize: "30 g", category: "Crackers",
                                      ingredientsText: "Brown rice, olive oil, natural flavors, sea salt.",
                                      nutrition: Nutrition(kcal: 130, fatG: 3, sodiumMg: 160, carbsG: 24, fiberG: 1, addedSugarsG: 0, proteinG: 2))
    static var noNutrition: Product {
        var product = oliveOilChips
        product.nutrition = nil
        return product
    }
    /// The chips with a stand-in pack photo: a drawn bag written to a temporary PNG (no real brand photos in the app).
    @MainActor static var withPhoto: Product {
        var product = chips
        let url = FileManager.default.temporaryDirectory.appending(path: "labelsage-preview-pack.png")
        let renderer = ImageRenderer(content: Image(systemName: "bag.fill").resizable().scaledToFit()
            .foregroundStyle(Theme.verdict.notFor.color).frame(width: 300, height: 360))
        renderer.scale = 2
        if let data = renderer.uiImage?.pngData() { try? data.write(to: url) }
        product.imageURL = url
        return product
    }
    static let longName = Product(barcode: "preview-long",
                                  name: "Organic Unsweetened Vanilla Almond and Coconut Barista Blend Plant-Based Beverage, Family Size",
                                  brand: "Some Really Long Brand Name Natural Foods Company", size: "96 fl oz", servingSize: "240 ml",
                                  category: "Plant-based drinks and milk alternatives",
                                  ingredientsText: "Almondmilk (filtered water, almonds), coconut cream, cane sugar, sunflower lecithin, natural flavors.",
                                  nutrition: Nutrition(kcal: 80, fatG: 6, sodiumMg: 150, carbsG: 6, addedSugarsG: 5, proteinG: 1))

    static func verdict(_ product: Product, for household: Household = household) -> HouseholdVerdict {
        VerdictService().check(product, for: household).verdict
    }

    static func page(_ product: Product, presentation: ProductPage.Presentation = .page, photo: ProductPage.Photo = .shown,
                     detent: PresentationDetent = .medium) -> ProductPage {
        ProductPage(product: product, verdict: verdict(product), household: household,
                    presentation: presentation, photo: photo, sheetDetent: detent)
    }
}

private extension View {
    /// Fixtures without the network delay, and the one-mascot presence.
    func productPreviewEnvironment() -> some View {
        environment(\.productSource, FixtureProductSource(delayMilliseconds: 0...0))
            .environment(MascotPresence())
    }
}

#Preview("Product page - notFor") {
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.chips) }.productPreviewEnvironment()
}

#Preview("Product page - checkFirst") {
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.poppedChips) }.productPreviewEnvironment()
}

#Preview("Product page - ok") {
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.oliveOilChips) }.productPreviewEnvironment()
}

#Preview("Product page - cantConfirm") {
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.riceCrackers) }.productPreviewEnvironment()
}

#Preview("Product page - no ingredients") {
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.trailMix) }.productPreviewEnvironment()
}

#Preview("Product page - no photo (pack tile)") {
    // The fixtures have no imageURL: the hero shows the pack tile and the flag sits by the name.
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.chips) }.productPreviewEnvironment()
}

#Preview("Product page - photo") {
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.withPhoto) }.productPreviewEnvironment()
}

#Preview("Product page - photo hidden") {
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.chips, photo: .hidden) }.productPreviewEnvironment()
}

#Preview("Product page - no nutrition") {
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.noNutrition) }.productPreviewEnvironment()
}

#Preview("Product page - long names") {
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.longName) }.productPreviewEnvironment()
}

#Preview("Product page - one person") {
    let alone = Household(people: Array(ProductPagePreviewData.household.people.prefix(1)))
    let product = ProductPagePreviewData.oliveOilChips
    NavigationStack {
        ProductPage(product: product, verdict: ProductPagePreviewData.verdict(product, for: alone), household: alone)
    }
    .productPreviewEnvironment()
}

#Preview("Product page - AX size") {
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.chips) }
        .productPreviewEnvironment()
        .dynamicTypeSize(.accessibility3)
}

#Preview("Product page - model reason crossfade") {
    // A stub model that answers after 1.5 s; the output check still runs.
    let service = ExplanationService { _ in
        try await Task.sleep(for: .seconds(1.5))
        return "Sunflower oil is a seed oil, and you avoid those. Mia\u{2019}s peanut and tree nuts are not in it."
    }
    NavigationStack { ProductPagePreviewData.page(ProductPagePreviewData.chips) }
        .productPreviewEnvironment()
        .environment(\.explanationService, service)
}

#Preview("Product sheet - medium") {
    @Previewable @State var shown = true
    Color.black.ignoresSafeArea()
        .sheet(isPresented: $shown) {
            ProductPagePreviewData.page(ProductPagePreviewData.chips, presentation: .sheet, photo: .hidden)
        }
        .productPreviewEnvironment()
}

#Preview("Product sheet - large") {
    @Previewable @State var shown = true
    Color.black.ignoresSafeArea()
        .sheet(isPresented: $shown) {
            ProductPagePreviewData.page(ProductPagePreviewData.chips, presentation: .sheet, photo: .hidden, detent: .large)
        }
        .productPreviewEnvironment()
}
#endif
