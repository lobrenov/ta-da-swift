import Foundation
import MarkdownEngineSyntax

/// Obsidian's callout types, opened in a body by `> [!type] Title`, in menu order.
public enum CalloutType: String, CaseIterable, Sendable {
    case note, abstract, info, todo, tip, success, question, warning, failure, danger, bug, example, quote

    public var title: String { rawValue.capitalized }

    /// Other names that take this type's look (`CalloutSyntax`).
    public var aliases: [String] {
        CalloutSyntax.types.first { $0.id == rawValue }?.aliases ?? []
    }

    /// The type `name` (as written between `[!` and `]`) names, ignoring case; nil for an unknown type, which
    /// draws as a note.
    public init?(named name: String) {
        guard let id = CalloutSyntax.type(named: name), let type = Self(rawValue: id) else { return nil }
        self = type
    }
}
