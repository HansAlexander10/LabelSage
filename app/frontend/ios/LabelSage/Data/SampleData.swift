import Foundation
import LabelSageCore

/// The bundled demo data (`Resources/Data/`): the household from the design and 100 made-up products
/// that cover every verdict path, each with a rendered pack photo in `Resources/ProductImages/`
/// (`app/tools/render-product-images.py`). Fictional people, brands and products only.
nonisolated enum SampleData {
    private struct ProductsFile: Decodable { var products: [Product] }

    /// `sample-products.json`. The main bundle's file is decoded once.
    static func products(in bundle: Bundle = .main) throws -> [Product] {
        if bundle == .main { return try mainProducts.get() }
        return try decode(ProductsFile.self, "sample-products", bundle).products
    }

    private static let mainProducts = Result {
        try decode(ProductsFile.self, "sample-products", .main).products.map(withBundledPhoto)
    }

    /// The pack photo `ProductImages/<barcode>.jpg`, when the product has none of its own.
    private static func withBundledPhoto(_ product: Product) -> Product {
        guard product.imageURL == nil, let code = product.barcode,
              let url = Bundle.main.url(forResource: code, withExtension: "jpg", subdirectory: "ProductImages") else {
            return product
        }
        var copy = product
        copy.imageURL = url
        return copy
    }

    /// `sample-household.json`: Alex ("you") and Mia, Austin 78701, Whole Foods Market.
    static func household(in bundle: Bundle = .main) throws -> Household {
        try decode(Household.self, "sample-household", bundle)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ name: String, _ bundle: Bundle) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
