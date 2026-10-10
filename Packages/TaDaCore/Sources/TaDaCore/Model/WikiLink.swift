import Foundation

/// An Obsidian-style link: `[[Title]]`, `[[Title|alias]]`, `[[Title#heading]]` or `[[folder/Title]]`. An embed is the
/// same with a leading `!`, e.g. `![[front.jpg]]`.
public struct WikiLink: Hashable, Sendable {
    /// The link as written before any `#` or `|`, e.g. `folder/Title`.
    public var target: String
    public var heading: String?
    public var alias: String?

    /// The title of the file the link points at: the target's last path component, without `.md`.
    public var title: String { Item.title(ofPath: target) }

    /// The image filename the target names, e.g. `front.jpg` for `attachments/front.jpg`; nil when it isn't an image.
    public var attachmentName: String? {
        let name = String(target.split(separator: "/").last ?? "")
        guard let dot = name.lastIndex(of: "."),
              Vault.imageExtensions.contains(name[name.index(after: dot)...].lowercased()) else { return nil }
        return name
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

    /// Every link and embed in a run of text, each in order.
    public static func scan(_ text: String) -> (links: [WikiLink], embeds: [WikiLink]) {
        var links: [WikiLink] = [], embeds: [WikiLink] = []
        for match in text.matches(of: #/(!?)\[\[([^\[\]\n]+)\]\]/#) {
            guard let link = WikiLink(inner: String(match.2)) else { continue }
            if match.1.isEmpty { links.append(link) } else { embeds.append(link) }
        }
        return (links, embeds)
    }

    nonisolated(unsafe) static let pattern = #/\[\[([^\[\]\n]+)\]\]/#
}
