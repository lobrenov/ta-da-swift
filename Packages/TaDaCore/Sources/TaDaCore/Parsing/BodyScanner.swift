import Markdown

/// What a file's body contributes to its item.
public struct BodyScan: Equatable, Sendable {
    /// The first top-level paragraph as plain text.
    public var summary: String?
    /// Every checkbox at any depth, in document order. Items in code blocks aren't list items, so they're skipped.
    public var checkboxes: [Checkbox]
    /// Every `[[…]]` in the body's text, skipping code and HTML.
    public var links: [WikiLink]
    /// Every `![[…]]`, as `links` finds them.
    public var embeds: [WikiLink]
    /// Every inline `#tag`, first spelling kept, in order. Code, HTML, links' text and `[[…]]` hold none.
    public var tags: [Tag]
}

public enum BodyScanner {
    /// - Parameter firstLineIndex: the file line the body starts on, so checkbox lines are file lines.
    public static func scan(_ body: String, firstLineIndex: Int = 0) -> BodyScan {
        let document = Document(parsing: body, options: [.disableSmartOpts])
        var walker = Walker(bytes: Array(body.utf8), firstLineIndex: firstLineIndex)
        walker.visit(document)
        let summary = document.children.lazy.compactMap { $0 as? Paragraph }.first?.plainText
        return BodyScan(summary: summary, checkboxes: walker.checkboxes, links: walker.links, embeds: walker.embeds, tags: walker.tags.unique)
    }

    /// Where each `![[…]]` that `scan` finds sits in `body`: the range of its target (the text before any `#` or
    /// `|`, without surrounding spaces), in order.
    public static func embedTargets(in body: String) -> [(range: Range<String.Index>, link: WikiLink)] {
        targets(in: body, embeds: true)
    }

    /// Where each `[[…]]` link (not an embed) that `scan` finds sits in `body`, as `embedTargets(in:)` gives them.
    public static func linkTargets(in body: String) -> [(range: Range<String.Index>, link: WikiLink)] {
        targets(in: body, embeds: false)
    }

    private static func targets(in body: String, embeds: Bool) -> [(range: Range<String.Index>, link: WikiLink)] {
        var walker = Walker(bytes: Array(body.utf8), firstLineIndex: 0)
        walker.visit(Document(parsing: body, options: [.disableSmartOpts]))
        let utf8 = body.utf8
        var found: [(range: Range<String.Index>, link: WikiLink)] = []
        for span in walker.textSpans {
            let start = utf8.index(utf8.startIndex, offsetBy: span.lowerBound)
            let end = utf8.index(utf8.startIndex, offsetBy: span.upperBound)
            for match in body[start..<end].matches(of: #/(!?)\[\[([^\[\]\n]+)\]\]/#) where match.1.isEmpty != embeds {
                let inner = match.2
                guard let link = WikiLink(inner: String(inner)) else { continue }
                let targetEnd = inner.firstIndex { $0 == "#" || $0 == "|" } ?? inner.endIndex
                let target = inner[..<targetEnd]
                let first = target.firstIndex { !$0.isWhitespace } ?? targetEnd
                let last = target.lastIndex { !$0.isWhitespace }.map { target.index(after: $0) } ?? first
                found.append((first..<last, link))
            }
        }
        return found
    }

    private struct Walker: MarkupWalker {
        let bytes: [UInt8]
        let firstLineIndex: Int
        /// UTF-8 offset of each line's start in `bytes`.
        let lineStarts: [Int]
        var checkboxes: [Checkbox] = []
        var links: [WikiLink] = []
        var embeds: [WikiLink] = []
        var tags: [Tag] = []
        /// The UTF-8 offsets in `bytes` of each text node that holds `[[`.
        var textSpans: [Range<Int>] = []
        private var spanCursor = 0

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
            let found = WikiLink.scan(text.string)
            links += found.links
            embeds += found.embeds
            if text.string.contains("#"), !Self.isInLink(text) {
                tags += InlineTags.scan(source(of: text) ?? text.string, atBoundary: Self.startsAtBoundary(text))
            }
            if text.string.contains("[["), let range = text.range { textSpans.append(span(of: text.string, reportedAt: range.lowerBound)) }
        }

        /// Where `string` sits in `bytes`, from the line and column the parser reported. After a backslash hard break
        /// the reported line falls behind the real one, and in an indented block its column falls short, so later lines
        /// are tried, never before the previous span's end: first for the exact column, then for the first match in
        /// the line. The reported position stands when none match.
        private mutating func span(of string: String, reportedAt start: SourceLocation) -> Range<Int> {
            let expected = Array(string.utf8)
            let (bytes, lineStarts, cursor) = (bytes, lineStarts, spanCursor)
            func matches(at offset: Int) -> Bool {
                offset >= cursor && offset + expected.count <= bytes.count && bytes[offset..<offset + expected.count].elementsEqual(expected)
            }
            let lines = (start.line - 1)..<lineStarts.count
            let exact = lines.map { lineStarts[$0] + start.column - 1 }.first(where: matches)
            let found = exact ?? lines.lazy.compactMap { line in
                let end = line + 1 < lineStarts.count ? lineStarts[line + 1] : bytes.count
                let from = max(lineStarts[line], cursor)
                return from < end ? (from..<end).first(where: matches) : nil
            }.first
            let offset = found ?? min(lineStarts[start.line - 1] + start.column - 1, bytes.count)
            if found != nil { spanCursor = offset + expected.count }
            return offset..<min(offset + expected.count, bytes.count)
        }

        /// The text as written, escapes and `#` entities kept, when the parser's reported range holds it.
        private func source(of text: Text) -> String? {
            guard let range = text.range, range.lowerBound.line == range.upperBound.line, range.lowerBound.line <= lineStarts.count
            else { return nil }
            let lineStart = lineStarts[range.lowerBound.line - 1]
            let (start, end) = (lineStart + range.lowerBound.column - 1, lineStart + range.upperBound.column - 1)
            guard start <= end, end <= bytes.count, let source = String(bytes: bytes[start..<end], encoding: .utf8) else { return nil }
            guard source != text.string else { return source }
            let decoded = source.replacing(#/\\([!-\/:-@\[-`{-~])/#) { String($0.1) }
                .replacing("&#35;", with: "#").replacing("&num;", with: "#")
            return decoded == text.string ? source : nil
        }

        /// Whether the text is a link's or an image's text, or an autolink.
        private static func isInLink(_ markup: Markup) -> Bool {
            var node = markup.parent
            while let current = node {
                if current is Link || current is Image { return true }
                node = current.parent
            }
            return false
        }

        /// Whether the markup starts a line or follows whitespace in the source. Inline containers, such as emphasis,
        /// take the boundary of their own start.
        private static func startsAtBoundary(_ markup: Markup) -> Bool {
            guard let parent = markup.parent else { return true }
            guard markup.indexInParent > 0, let previous = parent.child(at: markup.indexInParent - 1) else {
                return parent is InlineMarkup ? startsAtBoundary(parent) : true
            }
            if previous is SoftBreak || previous is LineBreak { return true }
            if let text = previous as? Text { return text.string.last?.isWhitespace ?? true }
            return false
        }

        /// Reads `[c]` from the source after the item's list marker. swift-markdown only recognises
        /// `[ ]`/`[x]`, so the alternative markers are found here for every item alike.
        private func checkbox(_ item: ListItem) -> Checkbox? {
            // Five or more spaces after the marker start an indented code block, not a checkbox.
            guard let start = item.range?.lowerBound, !(item.child(at: 0) is CodeBlock) else { return nil }
            let lineStart = lineStarts[start.line - 1]
            guard let markerEnd = CheckboxSyntax.markerEnd(in: bytes, at: lineStart + start.column - 1),
                  let box = CheckboxSyntax.box(in: bytes, after: markerEnd) else { return nil }
            return Checkbox(marker: box.marker, lineIndex: firstLineIndex + start.line - 1, column: box.offset - lineStart)
        }
    }
}
