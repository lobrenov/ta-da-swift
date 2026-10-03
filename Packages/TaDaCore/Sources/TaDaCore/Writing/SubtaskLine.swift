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
        let scalars = Array(line.unicodeScalars)
        var i = 0
        while i < scalars.count, scalars[i] == " " || scalars[i] == "\t" || scalars[i] == ">" { i += 1 }
        guard let afterMarker = listMarkerEnd(scalars, at: i) else {
            return .convert(offset: i, text: "- [ ] ")
        }
        guard let state = checkbox(scalars, at: afterMarker) else {
            return .convert(offset: afterMarker, text: "[ ] ")
        }
        switch state {
        case .open: return .setMarker(offset: afterMarker + 1, marker: "x")
        case .done, .cancelled: return .setMarker(offset: afterMarker + 1, marker: " ")
        case .icon: return .none
        }
    }

    /// `-`, `*`, `+` or `1.`/`1)` followed by a space or tab: the index after the whitespace.
    private static func listMarkerEnd(_ s: [Unicode.Scalar], at start: Int) -> Int? {
        var i = start
        if i < s.count, s[i] == "-" || s[i] == "*" || s[i] == "+" {
            i += 1
        } else {
            while i < s.count, i - start < 9, ("0"..."9").contains(s[i]) { i += 1 }
            guard i > start, i < s.count, s[i] == "." || s[i] == ")" else { return nil }
            i += 1
        }
        guard i < s.count, s[i] == " " || s[i] == "\t" else { return nil }
        return i + 1
    }

    /// A reference-set `[c]` followed by whitespace or the end of the line.
    private static func checkbox(_ s: [Unicode.Scalar], at i: Int) -> Checkbox.State? {
        guard i + 2 < s.count, s[i] == "[", s[i + 2] == "]",
              i + 3 == s.count || s[i + 3] == " " || s[i + 3] == "\t" else { return nil }
        return Checkbox.State(marker: Character(s[i + 1]))
    }
}
