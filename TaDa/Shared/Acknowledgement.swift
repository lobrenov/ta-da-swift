import Foundation

/// A package Ta Da ships with: its name, URL and licence name, read from `Acknowledgements.txt`.
nonisolated struct Acknowledgement: Equatable, Sendable {
    let name: String
    let url: String
    let licence: String

    /// The bundled file's packages, in its order.
    static let all: [Acknowledgement] = {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }()

    /// Each `=====` banner around a name line and a URL line starts a package; its licence is the parenthesis of the first `--- LICENSE (…) ---` line after.
    static func parse(_ text: String) -> [Acknowledgement] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [Acknowledgement] = []
        var i = 0
        while i < lines.count {
            if lines[i].hasPrefix("==="), i + 3 < lines.count, lines[i + 3].hasPrefix("===") {
                result.append(Acknowledgement(name: lines[i + 1], url: lines[i + 2], licence: ""))
                i += 4
            } else {
                if lines[i].lowercased().hasPrefix("--- license ("), let open = lines[i].firstIndex(of: "("),
                   let close = lines[i].lastIndex(of: ")"), let last = result.indices.last, result[last].licence.isEmpty {
                    result[last] = Acknowledgement(name: result[last].name, url: result[last].url, licence: String(lines[i][lines[i].index(after: open)..<close]))
                }
                i += 1
            }
        }
        return result
    }
}
