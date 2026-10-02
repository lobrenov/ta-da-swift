import Foundation

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

/// SampleVault/, found from this source file.
let sampleVault = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "../../../../SampleVault").standardized

func sampleFiles() throws -> [URL] {
    (FileManager.default.enumerator(at: sampleVault, includingPropertiesForKeys: nil)?.allObjects ?? [])
        .compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
}
