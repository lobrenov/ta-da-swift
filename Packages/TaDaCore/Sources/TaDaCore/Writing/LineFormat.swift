import Foundation

/// The iPhone formatting keyboard's edits to the caret's line: headings, lists, quotes and subtask boxes, each toggled
/// by splicing the line's prefix; block formats inserted on a line of their own; and which formats the caret is in.
public enum LineFormat: Equatable, Sendable {
    /// `#` to `######`.
    case heading(Int)
    case bulletedList, numberedList, quote
    /// A subtask with this marker.
    case box(Character)

    /// The formats a line carries.
    public struct State: Equatable, Sendable {
        public var heading: Int?
        /// `.bulletedList` or `.numberedList`.
        public var list: LineFormat?
        public var quote = false
        public var box: Character?
    }

    public static func state(of line: Substring) -> State {
        let bytes = Array(line.utf8)
        let start = CheckboxSyntax.markerStart(in: bytes)
        var state = State()
        state.quote = quoteMarker(in: bytes) != nil
        state.heading = headingLevel(in: bytes, at: contentStart(in: bytes))
        if let markerEnd = CheckboxSyntax.markerEnd(in: bytes, at: start) {
            state.list = isDigit(bytes[start]) ? .numberedList : .bulletedList
            state.box = CheckboxSyntax.box(in: bytes, after: markerEnd)?.marker
        }
        return state
    }

    /// The edit that applies `format` to the line holding `caret` (UTF-16, in `string`), as one replacement:
    /// - a heading of the same level is removed, any other replaced; on a list item it goes after the marker and box;
    /// - a list of the same kind is removed with its box, the other kind swaps its marker;
    /// - a quote's `>` is removed, else `> ` is added after the indent;
    /// - a box gets the marker; a list item gets a box; a plain line becomes a subtask.
    public static func plan(_ format: LineFormat, in string: String, caret: Int) -> SubtaskLine.Plan {
        let text = string as NSString
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        let bytes = Array(text.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart)).utf8)
        let start = CheckboxSyntax.markerStart(in: bytes)
        let markerEnd = CheckboxSyntax.markerEnd(in: bytes, at: start)

        let (range, replacement): (Range<Int>, String)
        switch format {
        case let .heading(level):
            let content = contentStart(in: bytes)
            let current = headingLevel(in: bytes, at: content)
            let prefix = current.map { content..<min(content + $0 + 1, bytes.count) } ?? content..<content
            (range, replacement) = (prefix, current == level ? "" : String(repeating: "#", count: level) + " ")
        case .bulletedList, .numberedList:
            let marker = format == .bulletedList ? "-" : "1."
            if let markerEnd {
                let isSame = isDigit(bytes[start]) == (format == .numberedList)
                if isSame {
                    var end = markerEnd + 1
                    if let box = CheckboxSyntax.box(in: bytes, after: markerEnd) {
                        end = box.offset + 2
                        if end < bytes.count, bytes[end] == UInt8(ascii: " ") { end += 1 }
                    }
                    (range, replacement) = (start..<end, "")
                } else {
                    (range, replacement) = (start..<markerEnd, marker)
                }
            } else {
                (range, replacement) = (start..<start, marker + " ")
            }
        case .quote:
            if let quote = quoteMarker(in: bytes) {
                (range, replacement) = (quote, "")
            } else {
                let indent = bytes.firstIndex { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\t") } ?? bytes.count
                (range, replacement) = (indent..<indent, "> ")
            }
        case let .box(marker):
            if let markerEnd, let box = CheckboxSyntax.box(in: bytes, after: markerEnd) {
                (range, replacement) = (box.offset..<box.offset + 1, String(marker))
            } else if let markerEnd {
                (range, replacement) = (markerEnd + 1..<markerEnd + 1, "[\(marker)] ")
            } else {
                (range, replacement) = (start..<start, "- [\(marker)] ")
            }
        }

        let location = lineStart + range.lowerBound
        let delta = (replacement as NSString).length - range.count
        let selection = caret >= lineStart + range.upperBound ? caret + delta : caret > location ? location : caret
        return SubtaskLine.Plan(range: NSRange(location: location, length: range.count), text: replacement,
                                selection: NSRange(location: selection, length: 0), actionName: "Format Line")
    }

    /// `insertion` (a slash command's text and selection) placed at `caret` on a line of its own: after a line break
    /// when text precedes the caret on its line, and before one when text follows it. A divider gets a blank line
    /// before it unless one is there, so it doesn't turn the line above into a heading.
    public static func blockInsertion(_ command: SlashCommand, callout: CalloutType = .note, in string: String,
                                      caret: Int) -> (text: String, selection: NSRange) {
        let text = string as NSString
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        let before = text.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        let after = text.substring(with: NSRange(location: caret, length: contentsEnd - caret))
        let opensLine = !before.allSatisfy(\.isWhitespace)
        let aboveIsBlank: Bool = {
            guard !opensLine else { return false }
            guard lineStart > 0 else { return true }
            let above = text.lineRange(for: NSRange(location: lineStart - 1, length: 0))
            return text.substring(with: above).allSatisfy(\.isWhitespace)
        }()
        var (inserted, selection) = command.insertion(followsBlankLine: aboveIsBlank)
        if command == .callout, callout != .note {
            inserted = inserted.replacingOccurrences(of: "[!note]", with: "[!\(callout.rawValue)]")
            selection.location += (callout.rawValue as NSString).length - 4
        }
        if opensLine {
            inserted = "\n" + inserted
            selection.location += 1
        }
        if !after.allSatisfy(\.isWhitespace) { inserted += "\n" }
        return (inserted, selection)
    }

    // MARK: Inline

    /// An inline format the formatting keyboard toggles.
    public enum Inline: CaseIterable, Sendable {
        case bold, italic, strikethrough, highlight, code
    }

    /// The inline formats around UTF-16 `offset` in `line`: a delimiter opened an odd number of times between the
    /// line's text start (after any list marker and box) and the offset, and seen again after it. Inside a code span
    /// only `code` counts.
    public static func inlineFormats(in line: String, at offset: Int) -> Set<Inline> {
        let text = line as NSString
        let offset = min(offset, text.length)
        let content = min(contentStart(in: Array(line.utf8)), offset)
        let before = text.substring(with: NSRange(location: content, length: offset - content))
        let after = text.substring(from: offset)
        func isInside(_ delimiter: String, _ before: String, _ after: String) -> Bool {
            before.components(separatedBy: delimiter).count % 2 == 0 && after.contains(delimiter)
        }
        if isInside("`", before, after) { return [.code] }
        var formats: Set<Inline> = []
        if isInside("**", before, after) { formats.insert(.bold) }
        if isInside("~~", before, after) { formats.insert(.strikethrough) }
        if isInside("==", before, after) { formats.insert(.highlight) }
        let single = (before.replacingOccurrences(of: "**", with: ""), after.replacingOccurrences(of: "**", with: ""))
        if isInside("*", single.0, single.1) { formats.insert(.italic) }
        return formats
    }

    // MARK: Parsing

    /// Where the line's text starts: after its indent, quote markers, list marker and box (and the space after them).
    /// The prefix is ASCII, so this is a UTF-16 offset too.
    private static func contentStart(in bytes: [UInt8]) -> Int {
        let start = CheckboxSyntax.markerStart(in: bytes)
        guard let markerEnd = CheckboxSyntax.markerEnd(in: bytes, at: start) else { return start }
        guard let box = CheckboxSyntax.box(in: bytes, after: markerEnd) else { return markerEnd + 1 }
        let end = box.offset + 2
        return end < bytes.count && bytes[end] == UInt8(ascii: " ") ? end + 1 : min(end, bytes.count)
    }

    private static func headingLevel(in bytes: [UInt8], at start: Int) -> Int? {
        var i = start
        while i < bytes.count, bytes[i] == UInt8(ascii: "#") { i += 1 }
        let level = i - start
        guard (1...6).contains(level), i == bytes.count || bytes[i] == UInt8(ascii: " ") || bytes[i] == UInt8(ascii: "\t")
        else { return nil }
        return level
    }

    /// The first `>` after the indent, with the space after it.
    private static func quoteMarker(in bytes: [UInt8]) -> Range<Int>? {
        guard let i = bytes.firstIndex(where: { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\t") }),
              bytes[i] == UInt8(ascii: ">") else { return nil }
        return i..<(i + 1 < bytes.count && bytes[i + 1] == UInt8(ascii: " ") ? i + 2 : i + 1)
    }

    private static func isDigit(_ byte: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }
}
