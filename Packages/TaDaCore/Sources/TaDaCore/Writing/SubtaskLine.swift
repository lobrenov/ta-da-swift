/// What Add Subtask (⌘L) inserts into the line the caret is on. It only ever inserts, so the edit is
/// minimal and undoes in one step.
public enum SubtaskLine {
    public enum Insertion: Equatable, Sendable {
        /// Make the line a subtask: insert `text` at UTF-16 `offset` in the line. Text after it moves along.
        case convert(offset: Int, text: String)
        /// The line is already a subtask: append `text` (a line ending and an empty subtask) to the line.
        case newSubtask(text: String)
    }

    /// `line` is the line's content without its line ending; `ending` is the file's line ending.
    /// A plain line gets `- [ ] ` after its indent (and any `>` quote markers); a list item gets `[ ] `
    /// after its marker; a subtask gets an empty subtask below it, at the same depth.
    public static func insertion(for line: Substring, ending: String = "\n") -> Insertion {
        let scalars = Array(line.unicodeScalars)
        var i = 0
        while i < scalars.count, scalars[i] == " " || scalars[i] == "\t" || scalars[i] == ">" { i += 1 }
        let lead = String(String.UnicodeScalarView(scalars[..<i]))
        guard let (marker, afterMarker) = listMarker(scalars, at: i) else {
            return .convert(offset: i, text: "- [ ] ")
        }
        if isCheckbox(scalars, at: afterMarker) {
            return .newSubtask(text: ending + lead + nextMarker(marker) + " [ ] ")
        }
        return .convert(offset: afterMarker, text: "[ ] ")
    }

    /// `-`, `*`, `+` or `1.`/`1)` followed by a space or tab: the marker and the index after the whitespace.
    private static func listMarker(_ s: [Unicode.Scalar], at start: Int) -> (String, Int)? {
        var i = start
        if i < s.count, s[i] == "-" || s[i] == "*" || s[i] == "+" {
            i += 1
        } else {
            while i < s.count, i - start < 9, ("0"..."9").contains(s[i]) { i += 1 }
            guard i > start, i < s.count, s[i] == "." || s[i] == ")" else { return nil }
            i += 1
        }
        guard i < s.count, s[i] == " " || s[i] == "\t" else { return nil }
        return (String(String.UnicodeScalarView(s[start..<i])), i + 1)
    }

    /// `[c]` followed by whitespace or the end of the line.
    private static func isCheckbox(_ s: [Unicode.Scalar], at i: Int) -> Bool {
        guard i + 2 < s.count, s[i] == "[", s[i + 2] == "]" else { return false }
        return i + 3 == s.count || s[i + 3] == " " || s[i + 3] == "\t"
    }

    /// The same bullet, or the next number for an ordered list.
    private static func nextMarker(_ marker: String) -> String {
        guard let number = Int(marker.dropLast()) else { return marker }
        return "\(number + 1)\(marker.last!)"
    }
}
