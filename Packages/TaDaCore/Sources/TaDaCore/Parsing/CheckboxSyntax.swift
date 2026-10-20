import MarkdownEngineSyntax

/// Where a checkbox is in a line, for Add Subtask and Source mode: a list marker (`-`, `*`, `+`,
/// `1.` or `1)`), one to four spaces or tabs, then `[c]` with `c` from the reference set and a space or tab
/// after it. Offsets count UTF-8 code units in `text`; the syntax is ASCII, so in a line they are UTF-16
/// offsets too.
public enum CheckboxSyntax {
    /// Where a line's list marker would start: after its indent and any `>` quote markers.
    public static func markerStart(in line: [UInt8]) -> Int {
        line.firstIndex { !isSpace($0) && $0 != UInt8(ascii: ">") } ?? line.count
    }

    /// The end of a list marker at `start`, when one is there and a space or tab follows it.
    public static func markerEnd(in text: [UInt8], at start: Int) -> Int? {
        var i = start
        if i < text.count, text[i] == UInt8(ascii: "-") || text[i] == UInt8(ascii: "*") || text[i] == UInt8(ascii: "+") {
            i += 1
        } else {
            while i < text.count, i - start < 9, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(text[i]) { i += 1 }
            guard i > start, i < text.count, text[i] == UInt8(ascii: ".") || text[i] == UInt8(ascii: ")") else { return nil }
            i += 1
        }
        return i < text.count && isSpace(text[i]) ? i : nil
    }

    /// The box after a list marker that ends at `markerEnd` (`TaskMarker.box(inTextAfterListMarker:)`): its marker and
    /// the marker's offset. What precedes the marker is ASCII, so its UTF-16 offset is its UTF-8 one.
    public static func box(in text: [UInt8], after markerEnd: Int) -> (marker: Character, offset: Int)? {
        guard markerEnd <= text.count else { return nil }
        let lineEnd = text[markerEnd...].firstIndex { $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\r") } ?? text.count
        guard let box = TaskMarker.box(inTextAfterListMarker: String(decoding: text[markerEnd..<lineEnd], as: UTF8.self))
        else { return nil }
        return (box.marker, markerEnd + box.offset)
    }

    private static func isSpace(_ byte: UInt8) -> Bool { byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") }
}
