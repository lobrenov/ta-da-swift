import Foundation

/// The `status` property. The raw value is the canonical written form.
public enum Status: String, CaseIterable, Sendable {
    case notStarted = "Not Started"
    case doing = "Doing"
    case done = "Done"
    case blocked = "Blocked"
    case cancelled = "Cancelled"
    /// A project with no end: open, without progress.
    case ongoing = "Ongoing"

    /// Done or Cancelled: completed, with a `completedDate`.
    public var isClosed: Bool { self == .done || self == .cancelled }

    /// The statuses a file of `kind` can be set to, in menu order. Ongoing is for projects only.
    public static func choices(for kind: Item.Kind) -> [Status] {
        [.notStarted, .doing] + (kind == .project ? [.ongoing] : []) + [.blocked, .done, .cancelled]
    }

    /// Matches a written value case-insensitively, ignoring surrounding whitespace.
    public init?(reading text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let match = Self.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame
        }) else { return nil }
        self = match
    }
}
