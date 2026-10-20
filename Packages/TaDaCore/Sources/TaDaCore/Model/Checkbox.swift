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

    public var state: State { State(marker: marker)! }
}
