// swift-tools-version: 6.2
// LabelSageCore: the parts of LabelSage that must be right before anything is pretty.
// Models, the ingredient parser and matcher, the verdict engine and the reason lines.
// No UI, no networking, no main actor: the app decides where this runs.
import PackageDescription

let package = Package(
    name: "LabelSageCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "LabelSageCore", targets: ["LabelSageCore"]),
    ],
    targets: [
        .target(
            name: "LabelSageCore",
            resources: [.copy("Resources/catalog.json")]
        ),
        .testTarget(
            name: "LabelSageCoreTests",
            dependencies: ["LabelSageCore"],
            resources: [.copy("Resources/verdict-cases.json")]
        ),
    ]
)
