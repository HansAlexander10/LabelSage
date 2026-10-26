// swift-tools-version: 6.2
// LabelSageAgent: the chat pipeline from docs/logic/chat-agent.md.
// IntentReader (on-device model, keyword fallback) -> Actions (catalog + VerdictEngine) -> Writer (validated line).
// Code decides, LabelSage explains (D8): the model never returns a verdict.
import PackageDescription

let package = Package(
    name: "LabelSageAgent",
    platforms: [.iOS(.v26), .macOS(.v26)],   // Foundation Models
    products: [
        .library(name: "LabelSageAgent", targets: ["LabelSageAgent"]),
    ],
    dependencies: [
        .package(path: "../LabelSageCore"),
        .package(path: "../LabelSageCatalog"),
    ],
    targets: [
        .target(
            name: "LabelSageAgent",
            dependencies: [
                .product(name: "LabelSageCore", package: "LabelSageCore"),
                .product(name: "LabelSageCatalog", package: "LabelSageCatalog"),
            ]
        ),
        .testTarget(
            name: "LabelSageAgentTests",
            dependencies: ["LabelSageAgent"],
            exclude: ["Resources/DATA-NOTICE.md"],
            resources: [.copy("Resources/catalog-fixture.sqlite")]
        ),
    ]
)
