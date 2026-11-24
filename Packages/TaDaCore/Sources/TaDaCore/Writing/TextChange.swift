import Foundation

/// A change to a file's text, kept so it can be undone: the text up to the end of the change, before and after it.
public struct TextChange: Equatable, Sendable {
    /// The text before the change, up to the end of what changed.
    public let before: String
    /// The text after the change, up to the end of what changed.
    public let after: String

    /// The change from `before` to `after`, without the text the two end with.
    public init(from before: String, to after: String) {
        let shared = zip(before.reversed(), after.reversed()).prefix { $0 == $1 }.count
        self.before = String(before.dropLast(shared))
        self.after = String(after.dropLast(shared))
    }

    private init(before: String, after: String) {
        self.before = before
        self.after = after
    }

    /// `text` with the change undone, while the text up to its end is still as the change left it; nil otherwise.
    /// Text after the change may have changed since.
    public func undone(in text: String) -> String? {
        guard text.hasPrefix(after) else { return nil }
        return before + text.dropFirst(after.count)
    }

    /// The change that undoes this one.
    public var inverse: TextChange { TextChange(before: after, after: before) }
}
