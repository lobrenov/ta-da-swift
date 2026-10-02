/// A text's lines, each keeping its own line ending, so joining them gives back the exact text.
struct Lines {
    var lines: [Substring]

    init(_ text: String) {
        lines = []
        let utf8 = text.utf8
        var start = utf8.startIndex
        while start < utf8.endIndex {
            let newline = utf8[start...].firstIndex(of: UInt8(ascii: "\n"))
            let end = newline.map { utf8.index(after: $0) } ?? utf8.endIndex
            lines.append(text[start..<end])
            start = end
        }
    }

    var text: String { lines.joined() }

    /// The file's line ending, taken from its first line. LF when there is none.
    var ending: String {
        guard let first = lines.first, first.unicodeScalars.last == "\n" else { return "\n" }
        return first.unicodeScalars.dropLast().last == "\r" ? "\r\n" : "\n"
    }

    /// A line without its line ending.
    static func content(_ line: Substring) -> Substring {
        var scalars = line.unicodeScalars[...]
        if scalars.last == "\n" { scalars.removeLast() }
        if scalars.last == "\r" { scalars.removeLast() }
        return Substring(scalars)
    }
}
