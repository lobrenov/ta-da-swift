// swift-tools-version: 5.9
import PackageDescription

// Ta Da fork of swift-markdown-engine 0.13.0 (see FORK.md). Only the core
// `MarkdownEngine` library is kept; the optional HighlighterSwift and SwiftMath
// bridges were removed so the fork has no external dependencies.
let package = Package(
    name: "MarkdownEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownEngine", targets: ["MarkdownEngine"]),
    ],
    targets: [
        .target(name: "MarkdownEngine"),
        .testTarget(
            name: "MarkdownEngineTests",
            dependencies: ["MarkdownEngine"]
        ),
    ]
)
