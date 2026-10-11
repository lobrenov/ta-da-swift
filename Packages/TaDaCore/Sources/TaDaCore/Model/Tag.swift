import Foundation

/// A tag, from `tags:` or an inline `#tag`. `/` nests: `home/garden` is a child of `home`.
/// Tags match by `path`, ignoring case; `name` keeps the spelling as written.
public struct Tag: Hashable, Sendable {
    /// As written, without `#` or empty segments, e.g. `Home/Garden`.
    public let name: String
    /// `name` lowercased: the tag's identity, e.g. `home/garden`.
    public let path: String

    /// Reads a tag as written: a leading `#` and empty segments are dropped, and each segment is trimmed.
    /// Nil when nothing is left.
    public init?(_ text: String) {
        var text = Substring(text.trimmingCharacters(in: .whitespaces))
        if text.first == "#" { text = text.dropFirst() }
        let segments = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !segments.isEmpty else { return nil }
        name = segments.joined(separator: "/")
        path = name.lowercased()
    }

    /// `name`'s segments, e.g. `["Home", "Garden"]`.
    public var segments: [String] { name.split(separator: "/").map(String.init) }

    /// The last segment, e.g. `Garden`.
    public var leaf: String { segments.last ?? name }

    /// The tag one level up, spelled as this one; nil for a top-level tag.
    public var parent: Tag? {
        guard let slash = name.lastIndex(of: "/") else { return nil }
        return Tag(String(name[..<slash]))
    }

    /// Whether `other` nests under this tag, at any depth. A tag isn't its own ancestor.
    public func isAncestor(of other: Tag) -> Bool {
        other.path.hasPrefix(path + "/")
    }
}

extension Array where Element == Tag {
    /// The tags without repeats of an earlier one's path.
    var unique: [Tag] {
        var seen: Set<String> = []
        return filter { seen.insert($0.path).inserted }
    }
}
