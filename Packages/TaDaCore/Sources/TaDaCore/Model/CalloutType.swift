import Foundation

/// Obsidian's callout types, opened in a body by `> [!type] Title`, in menu order.
public enum CalloutType: String, CaseIterable, Sendable {
    case note, abstract, info, todo, tip, success, question, warning, failure, danger, bug, example, quote

    public var title: String { rawValue.capitalized }

    /// Other names that take this type's look.
    public var aliases: [String] {
        switch self {
        case .abstract: ["summary", "tldr"]
        case .tip: ["hint", "important"]
        case .success: ["check", "done"]
        case .question: ["help", "faq"]
        case .warning: ["caution", "attention"]
        case .failure: ["fail", "missing"]
        case .danger: ["error"]
        case .quote: ["cite"]
        case .note, .info, .todo, .bug, .example: []
        }
    }

    /// The type `name` (as written between `[!` and `]`) names, ignoring case; nil for an unknown type, which
    /// draws as a note.
    public init?(named name: String) {
        let name = name.lowercased()
        guard let type = Self.allCases.first(where: { $0.rawValue == name || $0.aliases.contains(name) }) else { return nil }
        self = type
    }
}
