// swift-tools-version: 5.9
import PackageDescription

// TaDaMarkdown: Ta Da's live markdown editor, from swift-markdown-engine 0.13.0
// (see ORIGIN.md). Apache-2.0 (LICENSE, NOTICE). No external dependencies.
let package = Package(
    name: "TaDaMarkdown",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TaDaMarkdown", targets: ["TaDaMarkdown"]),
    ],
    targets: [
        .target(name: "TaDaMarkdown"),
        .testTarget(
            name: "TaDaMarkdownTests",
            dependencies: ["TaDaMarkdown"]
        ),
    ]
)
