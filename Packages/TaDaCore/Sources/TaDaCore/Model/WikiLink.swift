import Foundation
import MarkdownEngineSyntax

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

    /// Parses the text between `[[` and `]]` (`WikiLinkParts`). A block reference is a heading starting with `^`.
    /// Nil when there's no target: a link within the same file (`[[#heading]]`) links no file.
    public init?(inner: String) {
        guard let parts = WikiLinkParts(inner: inner) else { return nil }
        self.init(target: parts.target, heading: parts.heading, block: parts.block, alias: parts.alias)
    }

    /// Nil when `target` is empty.
    init?(target: String, heading: String?, block: String?, alias: String?) {
        guard !target.isEmpty else { return nil }
        self.target = target
        self.heading = heading ?? block.map { "^" + $0 }
        self.alias = alias
    }

    /// Parses a whole `[[…]]` value, such as the `project` property. Surrounding whitespace is allowed.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.wholeMatch(of: Self.pattern) else { return nil }
        self.init(inner: String(match.1))
    }

    nonisolated(unsafe) static let pattern = #/\[\[([^\[\]\n]+)\]\]/#
}
