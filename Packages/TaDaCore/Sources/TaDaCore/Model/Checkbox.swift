import MarkdownEngineSyntax

/// A checkbox in a file's body: a list item whose marker is followed by `[c]` and a space or tab.
public struct Checkbox: Hashable, Sendable {
    public enum State: Sendable {
        case open, done, cancelled
        /// Reference-set markers that render as a box but aren't subtasks.
        case icon

        /// The spec's reading (`TaskMarker.state(of:)`). Nil for characters outside the Alternative Checkboxes
        /// Reference Set.
        public init?(marker: Character) {
            switch TaskMarker.state(of: marker) {
            case .open: self = .open
            case .done: self = .done
            case .cancelled: self = .cancelled
            case .icon: self = .icon
            case nil: return nil
            }
        }

        /// What a click sets (`TaskMarker.toggled`): `x` completes an open box, a space reopens a done or cancelled one.
        /// Icons ignore clicks.
        public var markerAfterClick: Character? {
            switch self {
            case .open: "x"
            case .done, .cancelled: " "
            case .icon: nil
            }
        }
    }

    /// The character between the brackets.
    public var marker: Character
    /// 0-based line in the whole file.
    public var lineIndex: Int
    /// UTF-8 offset of `marker` within its line.
    public var column: Int

    /// The rest of the box's first line, trimmed, as written: its attributes included.
    public var text: String = ""
    /// The first `>YYYY-MM-DD` in `text` (see `InlineAttributes`).
    public var due: LocalDate?
    /// The target title of the first `@[[…]]` in `text`.
    public var parent: String?
    /// Indented under another checkbox, which lists it as a subtask line of its own.
    public var isNested = false
    /// In a quote or callout.
    public var isQuoted = false

    public var state: State { State(marker: marker)! }

    /// `text` without its due date and parent.
    public var title: String {
        let attributes = InlineAttributes.parse(text)
        return attributes.stripped(from: text)
    }

    public init(marker: Character, lineIndex: Int, column: Int, text: String = "", due: LocalDate? = nil, parent: String? = nil,
                isNested: Bool = false, isQuoted: Bool = false) {
        self.marker = marker
        self.lineIndex = lineIndex
        self.column = column
        self.text = text
        self.due = due
        self.parent = parent
        self.isNested = isNested
        self.isQuoted = isQuoted
    }
}
