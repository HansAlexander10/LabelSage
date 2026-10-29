import CZlib
import Foundation
import LabelSageCore
import SQLite3

/// A recall that names this product's barcode (openFDA). `Product` has no recall field yet,
/// so recalls are read separately (open question for the app owner).
public struct Recall: Sendable, Equatable {
    public var number: String
    public var reason: String?
    public var classification: Int?   // 1 = Class I (most serious) … 3 = Class III
    public var ongoing: Bool
    public var reportDate: Date?
}

public enum CatalogError: Error, Equatable {
    case cannotOpen(String)
    case query(String)
    /// The file was built for another catalog schema (`catalog_meta.schema_version`); nil when it has none.
    case schemaMismatch(found: String?, expected: Int)
}

/// Reads catalog.sqlite, the weekly US product catalog built by `app/backend/etl`, and returns
/// `LabelSageCore.Product` values. Everything is offline: nothing leaves the phone.
///
/// Method shapes follow `ProductSource` in the handoff (`docs/logic/data-and-privacy.md`), so the app
/// can declare the conformance once that protocol exists in code. Region and store are accepted but
/// not used yet: the catalog covers the whole US and has no store availability.
public final class CatalogProductSource: @unchecked Sendable {
    private let db: OpaquePointer
    private let dictionary: [UInt8]
    private let lock = NSLock()

    /// The snapshot this catalog was built as, e.g. "v2026-43".
    public let snapshot: String?

    /// The catalog schema this reader understands; the ETL writes the same number (`load.SCHEMA_VERSION`).
    public static let schemaVersion = 1

    // MARK: - Open

    public init(url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            throw CatalogError.cannotOpen(url.path)
        }
        // a file built for another schema is refused, so the app falls back instead of reading wrong columns
        let version = Self.text(handle, "SELECT value FROM catalog_meta WHERE key = 'schema_version'")
        guard version == String(Self.schemaVersion) else {
            sqlite3_close(handle)
            throw CatalogError.schemaMismatch(found: version, expected: Self.schemaVersion)
        }
        db = handle
        dictionary = Self.blob(db, "SELECT dict FROM zlib_dictionary WHERE id = 1") ?? []
        snapshot = Self.text(db, "SELECT value FROM catalog_meta WHERE key = 'snapshot'")
    }

    deinit { sqlite3_close(db) }

    // MARK: - ProductSource shape

    /// The product for a scanned barcode, or nil when the catalog does not know it ("Report it").
    public func product(barcode: String, region: Region? = nil) async throws -> Product? {
        guard let gtin = Self.gtin(barcode) else { return nil }
        return try products(where: "p.gtin = ?", [gtin]).first
    }

    /// Products whose name or brand match the typed words, best match first.
    public func search(_ query: String, region: Region? = nil, store: Store? = nil, limit: Int = 20) async throws -> [Product] {
        let words = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map { "\"\($0)\"*" }
        guard !words.isEmpty else { return [] }
        let ids = try lock.withLock {
            try rows("SELECT rowid FROM search WHERE search MATCH ? AND rowid > 0 LIMIT ?",
                     [words.joined(separator: " "), Int64(limit)]) { sqlite3_column_int64($0, 0) }
        }
        let found = try products(where: "p.gtin IN (\(ids.map(String.init).joined(separator: ",")))", [])
        return ids.compactMap { id in found.first { Self.gtin($0.barcode ?? "") == id } }
    }

    /// "Other options": products in the same category with an ingredient list, closest in nutrients first.
    /// The app's verdict engine then keeps only those that fit each person.
    public func options(like product: Product, region: Region? = nil, store: Store? = nil, limit: Int = 20) async throws -> [Product] {
        guard let gtin = Self.gtin(product.barcode ?? "") else { return [] }
        let sql = """
            SELECT o.gtin FROM product p
            JOIN product o ON o.category_id = p.category_id AND o.gtin != p.gtin
            JOIN ingredients i ON i.gtin = o.gtin
            LEFT JOIN nutrient pn ON pn.gtin = p.gtin LEFT JOIN nutrient onu ON onu.gtin = o.gtin
            WHERE p.gtin = ? AND p.category_id IS NOT NULL
            ORDER BY abs(coalesce(onu.kcal, 0) - coalesce(pn.kcal, 0))
                   + abs(coalesce(onu.sugar_cg, 0) - coalesce(pn.sugar_cg, 0)) / 100.0
                   + abs(coalesce(onu.sodium_mg, 0) - coalesce(pn.sodium_mg, 0)) / 10.0
            LIMIT ?
            """
        let ids = try lock.withLock { try rows(sql, [gtin, Int64(limit)]) { sqlite3_column_int64($0, 0) } }
        let found = try products(where: "p.gtin IN (\(ids.map(String.init).joined(separator: ",")))", [])
        return ids.compactMap { id in found.first { Self.gtin($0.barcode ?? "") == id } }
    }

    /// No store data in the catalog yet (open question Q11): the app keeps its fixture store list.
    public func stores(near region: Region) async throws -> [Store] { [] }

    /// Recalls that name this barcode, newest first.
    public func recalls(barcode: String) async throws -> [Recall] {
        guard let gtin = Self.gtin(barcode) else { return [] }
        let sql = """
            SELECT r.recall_number, r.reason, r.class, r.ongoing, r.report_date FROM recall_link l
            JOIN recall r USING (recall_number) WHERE l.gtin = ? ORDER BY r.report_date DESC
            """
        return try lock.withLock {
            try rows(sql, [gtin]) { s in
                Recall(number: Self.string(s, 0) ?? "", reason: Self.string(s, 1), classification: Self.int(s, 2),
                       ongoing: sqlite3_column_int(s, 3) == 1, reportDate: Self.int(s, 4).map(Self.date))
            }
        }
    }

    // MARK: - Product rows

    private func products(where condition: String, _ binds: [Any]) throws -> [Product] {
        let sql = """
            SELECT p.gtin, p.name, b.name, c.name, p.size, p.serving_size, p.basis_ml, p.nova, p.image,
                   nullif(max(coalesce(p.fdc_date, 0), coalesce(p.off_date, 0)), 0),
                   n.kcal, n.protein_cg, n.carbs_cg, n.added_sugar_cg, n.fiber_cg, n.fat_cg, n.sat_fat_cg, n.sodium_mg,
                   i.text_z
            FROM product p
            LEFT JOIN brand b ON b.brand_id = p.brand_id
            LEFT JOIN category c ON c.category_id = p.category_id
            LEFT JOIN nutrient n ON n.gtin = p.gtin
            LEFT JOIN ingredients i ON i.gtin = p.gtin
            WHERE \(condition)
            """
        return try lock.withLock {
            try rows(sql, binds) { s in self.product(from: s) }
        }
    }

    private func product(from s: OpaquePointer) -> Product {
        let gtin = sqlite3_column_int64(s, 0)
        let serving = Self.double(s, 5)
        let unit = sqlite3_column_int(s, 6) == 1 ? "ml" : "g"
        let ingredients = Self.bytes(s, 18).flatMap { Self.unpack($0, dictionary: dictionary) }

        // nutrients are stored per 100 g as whole numbers; the app wants them per serving
        var nutrition: Nutrition?
        if let serving, serving > 0, sqlite3_column_type(s, 10) != SQLITE_NULL || sqlite3_column_type(s, 11) != SQLITE_NULL {
            let f = serving / 100
            let grams = { (i: Int32) in Self.double(s, i).map { $0 / 100 * f } }   // hundredths of a gram
            let whole = { (i: Int32) in Self.double(s, i).map { $0 * f } }         // kcal and mg
            nutrition = Nutrition(kcal: whole(10), fatG: grams(15), satFatG: grams(16), sodiumMg: whole(17),
                                  carbsG: grams(12), fiberG: grams(14), addedSugarsG: grams(13), proteinG: grams(11))
        }

        return Product(
            barcode: Self.ean(gtin),
            name: Self.string(s, 1) ?? "Unnamed product",
            brand: Self.string(s, 2),
            size: Self.string(s, 4),
            servingSize: serving.map { "\(Self.format($0)) \(unit)" },
            category: Self.string(s, 3),
            ingredientsText: ingredients,
            nutrition: nutrition,
            nova: Self.int(s, 7),
            imageURL: Self.string(s, 8).flatMap { Self.imageURL(gtin: gtin, file: $0) },
            dataUpdatedAt: Self.int(s, 9).map(Self.date)
        )
    }

    // MARK: - SQLite helpers

    private func rows<T>(_ sql: String, _ binds: [Any], _ read: (OpaquePointer) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CatalogError.query(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        for (i, value) in binds.enumerated() {
            let index = Int32(i + 1)
            switch value {
            case let v as Int64: sqlite3_bind_int64(statement, index, v)
            case let v as String: sqlite3_bind_text(statement, index, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            default: sqlite3_bind_null(statement, index)
            }
        }
        var out: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW { out.append(try read(statement)) }
        return out
    }

    private static func text(_ db: OpaquePointer, _ sql: String) -> String? {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { return nil }
        defer { sqlite3_finalize(s) }
        return sqlite3_step(s) == SQLITE_ROW ? string(s, 0) : nil
    }

    private static func blob(_ db: OpaquePointer, _ sql: String) -> [UInt8]? {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { return nil }
        defer { sqlite3_finalize(s) }
        return sqlite3_step(s) == SQLITE_ROW ? bytes(s, 0) : nil
    }

    private static func string(_ s: OpaquePointer, _ i: Int32) -> String? {
        sqlite3_column_text(s, i).map { String(cString: $0) }
    }

    private static func int(_ s: OpaquePointer, _ i: Int32) -> Int? {
        sqlite3_column_type(s, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s, i))
    }

    private static func double(_ s: OpaquePointer, _ i: Int32) -> Double? {
        sqlite3_column_type(s, i) == SQLITE_NULL ? nil : sqlite3_column_double(s, i)
    }

    private static func bytes(_ s: OpaquePointer, _ i: Int32) -> [UInt8]? {
        guard let p = sqlite3_column_blob(s, i) else { return nil }
        return [UInt8](UnsafeRawBufferPointer(start: p, count: Int(sqlite3_column_bytes(s, i))))
    }

    // MARK: - Barcodes, images, dates

    /// GTIN-14 as a number, or nil when the barcode is not valid (same rule as app/backend/etl/shared/barcode.py).
    static func gtin(_ code: String) -> Int64? {
        let digits = code.filter(\.isNumber)
        guard (8...14).contains(digits.count) else { return nil }
        let padded = Array(String(repeating: "0", count: 14 - digits.count) + digits).compactMap(\.wholeNumberValue)
        let total = padded.dropLast().enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 3 : 1) }
        guard (10 - total % 10) % 10 == padded.last else { return nil }
        return Int64(digits)
    }

    /// The barcode as 13 digits (EAN-13 / UPC-A with a leading zero), the form scanners report.
    static func ean(_ gtin: Int64) -> String {
        let s = String(gtin)
        return String(repeating: "0", count: max(0, 13 - s.count)) + s
    }

    /// OFF image folder: the 13-digit barcode split 3/3/3/4 (see app/backend/etl/load/load.py).
    static func imageURL(gtin: Int64, file: String) -> URL? {
        if file.hasPrefix("http") { return URL(string: file) }
        let c = Array(ean(gtin))
        let folder = [String(c[0..<3]), String(c[3..<6]), String(c[6..<9]), String(c[9...])].joined(separator: "/")
        return URL(string: "https://images.openfoodfacts.org/images/products/\(folder)/\(file)")
    }

    static func date(_ days: Int) -> Date { Date(timeIntervalSince1970: Double(days) * 86_400) }

    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: - Ingredients

    /// Unpack one ingredient list: zlib with the catalog's shared dictionary.
    static func unpack(_ input: [UInt8], dictionary: [UInt8]) -> String? {
        var stream = z_stream()
        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var source = input
        var dict = dictionary
        var output: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 16_384)
        return source.withUnsafeMutableBufferPointer { src -> String? in
            stream.next_in = src.baseAddress
            stream.avail_in = uInt(src.count)
            while true {
                let status = buffer.withUnsafeMutableBufferPointer { out -> Int32 in
                    stream.next_out = out.baseAddress
                    stream.avail_out = uInt(out.count)
                    let result = CZlib.inflate(&stream, Z_NO_FLUSH)
                    output.append(contentsOf: out.prefix(out.count - Int(stream.avail_out)))
                    return result
                }
                switch status {
                case Z_NEED_DICT:
                    guard inflateSetDictionary(&stream, &dict, uInt(dict.count)) == Z_OK else { return nil }
                case Z_STREAM_END:
                    return String(decoding: output, as: UTF8.self)
                case Z_OK:
                    continue
                default:
                    return nil
                }
            }
        }
    }
}
