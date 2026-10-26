// swift-tools-version: 6.2
// LabelSageCatalog: reads catalog.sqlite (built weekly by app/backend/etl) and returns LabelSageCore products.
// Read-only, offline, no networking: the barcode never leaves the phone.
import PackageDescription

let package = Package(
    name: "LabelSageCatalog",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "LabelSageCatalog", targets: ["LabelSageCatalog"]),
    ],
    dependencies: [
        .package(path: "../LabelSageCore"),
    ],
    targets: [
        // zlib from the OS, for ingredient lists packed with a shared dictionary
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(
            name: "LabelSageCatalog",
            dependencies: ["CZlib", .product(name: "LabelSageCore", package: "LabelSageCore")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "LabelSageCatalogTests",
            dependencies: ["LabelSageCatalog"],
            resources: [.copy("Resources/catalog-fixture.sqlite")]
        ),
    ]
)
