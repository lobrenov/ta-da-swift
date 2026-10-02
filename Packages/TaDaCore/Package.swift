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
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "TaDaCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .testTarget(
            name: "TaDaCoreTests",
            dependencies: [
                "TaDaCore",
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
    ]
)
