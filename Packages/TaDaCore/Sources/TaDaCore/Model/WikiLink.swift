import Foundation

/// An Obsidian-style link: `[[Title]]`, `[[Title|alias]]`, `[[Title#heading]]` or `[[folder/Title]]`.
public struct WikiLink: Hashable, Sendable {
    /// The link as written before any `#` or `|`, e.g. `folder/Title`.
    public var target: String
    public var heading: String?
    public var alias: String?

    /// The title of the file the link points at: the target's last path component, without `.md`.
    public var title: String {
        let name = target.split(separator: "/").last.map(String.init) ?? target
        return name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    /// Parses the text between `[[` and `]]`. Nil when there's no target (e.g. `[[#heading]]`).
    public init?(inner: String) {
        var rest = Substring(inner)
        if let bar = rest.firstIndex(of: "|") {
            alias = String(rest[rest.index(after: bar)...])
            rest = rest[..<bar]
        }
        if let hash = rest.firstIndex(of: "#") {
            heading = String(rest[rest.index(after: hash)...])
            rest = rest[..<hash]
        }
        target = rest.trimmingCharacters(in: .whitespaces)
        if target.isEmpty { return nil }
    }

    /// Parses a whole `[[…]]` value, such as the `project` property. Surrounding whitespace is allowed.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.wholeMatch(of: Self.pattern) else { return nil }
        self.init(inner: String(match.1))
    }

    /// Every link in a run of text, in order.
    public static func scan(_ text: String) -> [WikiLink] {
        text.matches(of: pattern).compactMap { WikiLink(inner: String($0.1)) }
    }

    private nonisolated(unsafe) static let pattern = #/\[\[([^\[\]\n]+)\]\]/#
}
