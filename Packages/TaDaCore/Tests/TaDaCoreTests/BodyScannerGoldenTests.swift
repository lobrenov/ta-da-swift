import Foundation
import Testing
@testable import TaDaCore
import TaDaCoreTesting

/// `BodyScanner` over the fixture vaults and the generated vault, against what it read when it replaced swift-markdown
/// (`Fixtures/BodyScans.txt`).
@Suite struct BodyScannerGoldenTests {
    private static let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures")

    /// One block per file: its path, then each non-empty part of its scan and its link and embed targets.
    static func render(_ name: String, _ text: String) -> String {
        let split = FrontmatterSplitter.split(text)
        let body = split.body
        let scan = BodyScanner.scan(body, firstLineIndex: split.bodyFirstLineIndex)
        func link(_ link: WikiLink) -> String {
            link.target + (link.heading.map { "#" + $0 } ?? "") + (link.alias.map { "|" + $0 } ?? "")
        }
        func targets(_ found: [(range: Range<String.Index>, link: WikiLink)]) -> String {
            found.map { "\(body.utf8.distance(from: body.startIndex, to: $0.range.lowerBound))+\(body[$0.range].utf8.count)" }
                .joined(separator: " ")
        }
        var lines = ["## \(name)"]
        if let summary = scan.summary { lines.append("summary: \(summary)") }
        let parts = [
            ("checkboxes", scan.checkboxes.map { "[\($0.marker)]\($0.lineIndex):\($0.column)" }.joined(separator: " ")),
            ("links", scan.links.map(link).joined(separator: ", ")),
            ("embeds", scan.embeds.map(link).joined(separator: ", ")),
            ("tags", scan.tags.map(\.name).joined(separator: ", ")),
            ("linkTargets", targets(BodyScanner.linkTargets(in: body))),
            ("embedTargets", targets(BodyScanner.embedTargets(in: body))),
        ]
        for (label, value) in parts where !value.isEmpty { lines.append("\(label): \(value)") }
        return lines.joined(separator: "\n")
    }

    /// Every fixture vault's `.md` files, by path under `Fixtures`.
    static func fixtureScans() -> String {
        let files = FileManager.default.enumerator(at: fixtures, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "md" } ?? []
        return files.sorted { $0.path < $1.path }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return render(String(url.path.dropFirst(fixtures.path.count + 1)), text)
        }.joined(separator: "\n\n") + "\n"
    }

    @Test func fixtureVaults() throws {
        let golden = try String(contentsOf: Self.fixtures.appending(path: "BodyScans.txt"), encoding: .utf8)
        let scans = Self.fixtureScans()
        let changed = zip(golden.components(separatedBy: "\n\n"), scans.components(separatedBy: "\n\n")).filter { $0 != $1 }
        #expect(scans == golden, "\(changed.prefix(10).map { "was\n\($0)\nnow\n\($1)" }.joined(separator: "\n\n"))")
    }

    /// The generated vault's totals, so a change anywhere in its 1,200 files shows.
    @Test func generatedVault() {
        var counts = (summaries: 0, checkboxes: 0, links: 0, embeds: 0, tags: 0, linkTargets: 0, embedTargets: 0)
        for file in GeneratedVault.files(today: LargeVaultTests.today) {
            let split = FrontmatterSplitter.split(file.text)
            let scan = BodyScanner.scan(split.body, firstLineIndex: split.bodyFirstLineIndex)
            counts.summaries += scan.summary == nil ? 0 : 1
            counts.checkboxes += scan.checkboxes.count
            counts.links += scan.links.count
            counts.embeds += scan.embeds.count
            counts.tags += scan.tags.count
            counts.linkTargets += BodyScanner.linkTargets(in: split.body).count
            counts.embedTargets += BodyScanner.embedTargets(in: split.body).count
        }
        #expect("\(counts)" == "(summaries: 1200, checkboxes: 2792, links: 194, embeds: 0, tags: 0, linkTargets: 194, embedTargets: 0)")
    }
}
