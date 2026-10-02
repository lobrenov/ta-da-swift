import Markdown

/// What a file's body contributes to its item.
public struct BodyScan: Equatable, Sendable {
    /// The first top-level paragraph as plain text.
    public var summary: String?
    /// Every checkbox at any depth, in document order. Items in code blocks aren't list items, so they're skipped.
    public var checkboxes: [Checkbox]
    /// Every `[[…]]` in the body's text, skipping code and HTML.
    public var links: [WikiLink]
}

public enum BodyScanner {
    /// - Parameter firstLineIndex: the file line the body starts on, so checkbox lines are file lines.
    public static func scan(_ body: String, firstLineIndex: Int = 0) -> BodyScan {
        let document = Document(parsing: body, options: [.disableSmartOpts])
        var walker = Walker(bytes: Array(body.utf8), firstLineIndex: firstLineIndex)
        walker.visit(document)
        let summary = document.children.lazy.compactMap { $0 as? Paragraph }.first?.plainText
        return BodyScan(summary: summary, checkboxes: walker.checkboxes, links: walker.links)
    }

    private struct Walker: MarkupWalker {
        let bytes: [UInt8]
        let firstLineIndex: Int
        /// UTF-8 offset of each line's start in `bytes`.
        let lineStarts: [Int]
        var checkboxes: [Checkbox] = []
        var links: [WikiLink] = []

        init(bytes: [UInt8], firstLineIndex: Int) {
            self.bytes = bytes
            self.firstLineIndex = firstLineIndex
            lineStarts = [0] + bytes.indices.filter { bytes[$0] == UInt8(ascii: "\n") }.map { $0 + 1 }
        }

        mutating func visitListItem(_ item: ListItem) {
            if let box = checkbox(item) { checkboxes.append(box) }
            descendInto(item)
        }

        mutating func visitText(_ text: Text) {
            links += WikiLink.scan(text.string)
        }

        /// Reads `[c]` from the source after the item's list marker. swift-markdown only recognises
        /// `[ ]`/`[x]`, so the alternative markers are found here for every item alike.
        private func checkbox(_ item: ListItem) -> Checkbox? {
            // Five or more spaces after the marker start an indented code block, not a checkbox.
            guard let start = item.range?.lowerBound, !(item.child(at: 0) is CodeBlock) else { return nil }
            let lineStart = lineStarts[start.line - 1]
            var i = lineStart + start.column - 1

            func byte(_ offset: Int) -> UInt8? { offset < bytes.count ? bytes[offset] : nil }
            func isSpace(_ b: UInt8?) -> Bool { b == UInt8(ascii: " ") || b == UInt8(ascii: "\t") }

            switch byte(i) {
            case UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "+"):
                i += 1
            default:
                while let b = byte(i), (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b) { i += 1 }
                guard byte(i) == UInt8(ascii: ".") || byte(i) == UInt8(ascii: ")") else { return nil }
                i += 1
            }
            guard isSpace(byte(i)) else { return nil }
            while isSpace(byte(i)) { i += 1 }
            guard byte(i) == UInt8(ascii: "["), let marker = byte(i + 1), marker < 0x80,
                  byte(i + 2) == UInt8(ascii: "]"), isSpace(byte(i + 3)),
                  Checkbox.State(marker: Character(Unicode.Scalar(marker))) != nil else { return nil }
            return Checkbox(
                marker: Character(Unicode.Scalar(marker)),
                lineIndex: firstLineIndex + start.line - 1,
                column: i + 1 - lineStart
            )
        }
    }
}
