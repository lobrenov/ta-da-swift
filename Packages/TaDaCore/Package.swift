// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TaDaCore",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "TaDaCore", targets: ["TaDaCore"]),
    ],
    dependencies: [
        // Pinned exactly: the app must never pick up a parser change silently.
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        // The grammar the Live editor reads with; the Xcode project pins the same tag.
        .package(url: "https://github.com/lobrenov/swift-markdown-engine-extended.git", exact: "0.15.0-live.3"),
    ],
    targets: [
        .target(
            name: "TaDaCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "MarkdownEngineSyntax", package: "swift-markdown-engine-extended"),
            ]
        ),
        // Test data. The app's tests compile GeneratedVault.swift themselves, so it isn't a product.
        .target(name: "TaDaCoreTesting", dependencies: ["TaDaCore"]),
        .testTarget(
            name: "TaDaCoreTests",
            dependencies: [
                "TaDaCore",
                "TaDaCoreTesting",
                .product(name: "Yams", package: "Yams"),
                .product(name: "MarkdownEngineSyntax", package: "swift-markdown-engine-extended"),
            ],
            // Read from disk by path, not bundled.
            exclude: ["Fixtures"]
        ),
    ]
)
