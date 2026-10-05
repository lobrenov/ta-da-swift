/// Where a checkbox is in a line, for the scanner, Add Subtask and Source mode: a list marker (`-`, `*`, `+`,
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

    /// The box after a list marker that ends at `markerEnd`: its marker and the marker's offset.
    public static func box(in text: [UInt8], after markerEnd: Int) -> (marker: Character, offset: Int)? {
        var i = markerEnd
        while i < text.count, i - markerEnd < 4, isSpace(text[i]) { i += 1 }
        guard i > markerEnd, i + 3 < text.count, text[i] == UInt8(ascii: "["), text[i + 2] == UInt8(ascii: "]"),
              isSpace(text[i + 3]) else { return nil }
        let marker = Character(Unicode.Scalar(text[i + 1]))
        return Checkbox.State(marker: marker) == nil ? nil : (marker, i + 1)
    }

    private static func isSpace(_ byte: UInt8) -> Bool { byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") }
}
