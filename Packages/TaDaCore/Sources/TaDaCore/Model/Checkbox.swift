/// A checkbox in a file's body: a list item whose marker is followed by `[c]` and a space or tab.
public struct Checkbox: Hashable, Sendable {
    public enum State: Sendable {
        case open, done, cancelled
        /// Reference-set markers that render as a box but aren't subtasks.
        case icon

        /// Nil for characters outside the Alternative Checkboxes Reference Set.
        public init?(marker: Character) {
            switch marker {
            case " ", "/", ">", "<": self = .open
            case "x", "X": self = .done
            case "-": self = .cancelled
            case "?", "!", "*", "\"", "l", "b", "i", "S", "I", "p", "c", "f", "k", "w", "u", "d": self = .icon
            default: return nil
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
