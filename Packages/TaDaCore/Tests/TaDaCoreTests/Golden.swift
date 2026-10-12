import Foundation
@testable import TaDaCore

/// What an edit changed: the lines outside the longest common subsequence, in order.
/// Lines are split on LF only, so a CRLF line shows its `\r`.
func changedLines(_ before: String, _ after: String) -> (removed: [String], added: [String]) {
    let old = before.components(separatedBy: "\n"), new = after.components(separatedBy: "\n")
    // lcs[i][j] = common subsequence length of old[i...] and new[j...]
    var lcs = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
    for i in old.indices.reversed() {
        for j in new.indices.reversed() {
            lcs[i][j] = old[i] == new[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
        }
    }
    var removed: [String] = [], added: [String] = []
    var i = 0, j = 0
    while i < old.count || j < new.count {
        if i < old.count, j < new.count, old[i] == new[j] {
            i += 1; j += 1
        } else if j < new.count, i == old.count || lcs[i][j + 1] >= lcs[i + 1][j] {
            added.append(new[j]); j += 1
        } else {
            removed.append(old[i]); i += 1
        }
    }
    return (removed, added)
}

/// The design's tasks and projects, frozen as SampleVault was before manual testing changed it
/// (SampleVault itself is free to edit). Found from this source file.
let sampleVault = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "Fixtures/DesignVault").standardized

/// Areas with and without projects, a loose project, area tasks, and both-keys and unresolved cases.
let areaVault = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "Fixtures/AreaVault").standardized

/// Tagged files: nested, frontmatter-only, body-only, both, untagged, logged and trashed.
let tagVault = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "Fixtures/TagVault").standardized

func sampleFiles() throws -> [URL] {
    (FileManager.default.enumerator(at: sampleVault, includingPropertiesForKeys: nil)?.allObjects ?? [])
        .compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
}

/// A fresh folder under the temporary directory, removed when `body` returns.
func withTemporaryFolder(_ body: (URL) async throws -> Void) async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "TaDaTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try await body(folder)
}

func writeFile(_ text: String, _ path: String, in folder: URL) throws {
    let url = folder.appending(path: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

/// An item from frontmatter lines and an optional body.
func makeItem(_ path: String, _ frontmatter: String, body: String = "") -> Item {
    Item(parsing: "---\n\(frontmatter)\n---\n\(body)", path: path)!
}
