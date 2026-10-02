/// A file split at its frontmatter. `block + body` is always the original text.
public struct FrontmatterSplit: Equatable, Sendable {
    /// The text between the fences, or nil when the file has no frontmatter.
    public var yaml: String?
    /// From the opening `---` through the closing `---` line's line ending. Empty without frontmatter.
    public var block: String
    public var body: String
    /// The 0-based file line the body starts on.
    public var bodyFirstLineIndex: Int
}

public enum FrontmatterSplitter {
    /// Frontmatter is a `---` first line up to the next `---` line (trailing spaces allowed, LF or CRLF).
    /// Without a closing fence the whole file is body.
    public static func split(_ text: String) -> FrontmatterSplit {
        let noFrontmatter = FrontmatterSplit(yaml: nil, block: "", body: text, bodyFirstLineIndex: 0)
        let utf8 = text.utf8
        var lineStart = utf8.startIndex
        var lineIndex = 0
        var yamlStart: String.Index?

        while lineStart < utf8.endIndex {
            let newline = utf8[lineStart...].firstIndex(of: UInt8(ascii: "\n"))
            let lineEnd = newline ?? utf8.endIndex
            let next = newline.map { utf8.index(after: $0) } ?? utf8.endIndex
            let isFence = isFenceLine(text.unicodeScalars[lineStart..<lineEnd])

            if lineIndex == 0 {
                guard isFence else { return noFrontmatter }
                yamlStart = next
            } else if isFence, let yamlStart {
                return FrontmatterSplit(
                    yaml: String(text[yamlStart..<lineStart]),
                    block: String(text[..<next]),
                    body: String(text[next...]),
                    bodyFirstLineIndex: lineIndex + 1
                )
            }
            lineStart = next
            lineIndex += 1
        }
        return noFrontmatter
    }

    private static func isFenceLine(_ line: Substring.UnicodeScalarView) -> Bool {
        var rest = line
        while let last = rest.last, last == " " || last == "\t" || last == "\r" { rest.removeLast() }
        return rest.elementsEqual("---".unicodeScalars)
    }
}
