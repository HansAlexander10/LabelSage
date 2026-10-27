import Foundation
import LabelSageCore

/// The bundled demo data (`Resources/Data/`): the household from the design and 10 made-up products
/// that cover every verdict path. Fictional people and products only.
nonisolated enum SampleData {
    private struct ProductsFile: Decodable { var products: [Product] }

    /// `sample-products.json`. The main bundle's file is decoded once.
    static func products(in bundle: Bundle = .main) throws -> [Product] {
        if bundle == .main { return try mainProducts.get() }
        return try decode(ProductsFile.self, "sample-products", bundle).products
    }

    private static let mainProducts = Result { try decode(ProductsFile.self, "sample-products", .main).products }

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
