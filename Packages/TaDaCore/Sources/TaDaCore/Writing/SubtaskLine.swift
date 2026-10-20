import MarkdownEngineSyntax

/// What Add Subtask (⌘L) does to the line the caret is on. The edit is minimal and undoes in one step.
public enum SubtaskLine {
    public enum Edit: Equatable, Sendable {
        /// Make the line a subtask: insert `text` at UTF-16 `offset` in the line. Text after it moves along.
        case convert(offset: Int, text: String)
        /// The line is already a subtask: replace the marker at UTF-16 `offset` with `marker`.
        case setMarker(offset: Int, marker: Character)
        /// An icon-only box, which isn't a subtask: nothing to do.
        case none
    }

    /// `line` is the line's content without its line ending. A plain line gets `- [ ] ` after its indent
    /// (and any `>` quote markers); a list item gets `[ ] ` after its marker; a subtask is completed, or
    /// reopened if it's done or cancelled, as a click on its box does.
    public static func edit(for line: Substring) -> Edit {
        let bytes = Array(line.utf8)
        let start = CheckboxSyntax.markerStart(in: bytes)
        guard let markerEnd = CheckboxSyntax.markerEnd(in: bytes, at: start) else {
            return .convert(offset: start, text: "- [ ] ")
        }
        guard let box = CheckboxSyntax.box(in: bytes, after: markerEnd) else {
            return .convert(offset: markerEnd + 1, text: "[ ] ")
        }
        guard let marker = TaskMarker.toggled(box.marker) else { return .none }
        return .setMarker(offset: box.offset, marker: marker)
    }
}
