import Foundation
import MarkdownEngineSyntax

/// What Add Subtask (⌘L) does to the line the caret is on, or to each line a selection touches. The edit is minimal and undoes in one step.
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

    /// The whole edit for a selection, as one replacement.
    public struct Plan: Equatable, Sendable {
        /// The UTF-16 range to replace, and its replacement.
        public let range: NSRange
        public let text: String
        /// Where the selection goes afterwards.
        public let selection: NSRange
        /// "Add Subtask", "Complete Subtask" or "Reopen Subtask".
        public let actionName: String
    }

    /// The edit for `selection` (UTF-16, in `string`), or nil if there is nothing to do. A selection within
    /// one line acts as `edit(for:)` does on the caret's line (the selection's start). Over several lines,
    /// plain lines become subtasks and subtasks stay; blank lines are skipped. If every line is already a
    /// subtask they are all completed, or all reopened when none is open.
    public static func plan(in string: String, selection: NSRange) -> Plan? {
        let text = string as NSString
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: selection)
        let caretLine = text.lineRange(for: NSRange(location: selection.location, length: 0))
        guard NSMaxRange(caretLine) < end else {
            return singleLine(in: text, caret: selection.location)
        }

        var lines: [(start: Int, edit: Edit)] = []
        var location = start
        while location < end {
            var lineStart = 0, lineEnd = 0, lineContentsEnd = 0
            text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &lineContentsEnd, for: NSRange(location: location, length: 0))
            let line = text.substring(with: NSRange(location: lineStart, length: lineContentsEnd - lineStart))
            if !line.allSatisfy(\.isWhitespace) { lines.append((lineStart, edit(for: line[...]))) }
            location = lineEnd
        }

        let converts = lines.filter { if case .convert = $0.edit { true } else { false } }
        let markers = lines.filter { if case .setMarker = $0.edit { true } else { false } }
        let chosen: [(start: Int, edit: Edit)], actionName: String
        if !converts.isEmpty {
            chosen = converts
            actionName = "Add Subtask"
        } else if markers.contains(where: { if case .setMarker(_, "x") = $0.edit { true } else { false } }) {
            chosen = markers.filter { if case .setMarker(_, "x") = $0.edit { true } else { false } }
            actionName = "Complete Subtask"
        } else if !markers.isEmpty {
            chosen = markers
            actionName = "Reopen Subtask"
        } else {
            return nil
        }

        let changes: [(range: NSRange, text: String)] = chosen.compactMap { lineStart, edit in
            switch edit {
            case let .convert(offset, text): (NSRange(location: lineStart + offset, length: 0), text)
            case let .setMarker(offset, marker): (NSRange(location: lineStart + offset, length: 1), String(marker))
            case .none: nil
            }
        }
        var replacement = "", delta = 0
        var cursor = changes[0].range.location
        for (range, inserted) in changes {
            replacement += text.substring(with: NSRange(location: cursor, length: range.location - cursor)) + inserted
            delta += (inserted as NSString).length - range.length
            cursor = NSMaxRange(range)
        }
        let span = NSRange(location: changes[0].range.location, length: cursor - changes[0].range.location)
        return Plan(range: span, text: replacement,
                    selection: NSRange(location: start, length: contentsEnd - start + delta), actionName: actionName)
    }

    private static func singleLine(in text: NSString, caret: Int) -> Plan? {
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        let line = text.substring(with: NSRange(location: start, length: contentsEnd - start))
        switch edit(for: line[...]) {
        case let .convert(offset, inserted):
            let location = start + offset
            return Plan(range: NSRange(location: location, length: 0), text: inserted,
                        selection: NSRange(location: caret >= location ? caret + (inserted as NSString).length : caret, length: 0),
                        actionName: "Add Subtask")
        case let .setMarker(offset, marker):
            return Plan(range: NSRange(location: start + offset, length: 1), text: String(marker),
                        selection: NSRange(location: caret, length: 0),
                        actionName: marker == "x" ? "Complete Subtask" : "Reopen Subtask")
        case .none:
            return nil
        }
    }

    // MARK: Attributes

    /// The line with its due date set to `date`: an existing `>YYYY-MM-DD` is replaced, or removed for nil, else the
    /// token is added at the end of the text. Only that token changes. `line` is a subtask's content without its line
    /// ending, or with a `\r` that's kept; nil when it isn't one (an icon box isn't).
    public static func settingDue(_ date: LocalDate?, inLine line: String) -> String? {
        splicing(line) { rest in
            let attributes = InlineAttributes.parse(rest)
            return (attributes.due?.range, date.map { ">\($0)" })
        }
    }

    /// The line with its parent set to `@[[title]]`, as `settingDue` does. Nil also when `title` has a bracket or a
    /// line break.
    public static func settingParent(_ title: String?, inLine line: String) -> String? {
        if let title, title.isEmpty || title.contains(where: { "[]\n\r".contains($0) }) { return nil }
        return splicing(line) { rest in
            let attributes = InlineAttributes.parse(rest)
            return (attributes.parent?.range, title.map { "@[[\($0)]]" })
        }
    }

    /// `settingDue` on line `line` (0-based) of `text`, keeping every other byte, line endings included. Nil when the
    /// text has no such line.
    public static func setDue(_ date: LocalDate?, in text: String, line: Int) -> String? {
        replacingLine(line, in: text) { settingDue(date, inLine: $0) }
    }

    /// `settingParent` on line `line` (0-based) of `text`.
    public static func setParent(_ title: String?, in text: String, line: Int) -> String? {
        replacingLine(line, in: text) { settingParent(title, inLine: $0) }
    }

    /// `line` with the text after its box edited by `edit`, which gets that text and says which token to replace (if any)
    /// and with what (nil removes it, or adds nothing).
    private static func splicing(_ line: String, _ edit: (String) -> (range: NSRange?, token: String?)) -> String? {
        var bytes = Array(line.utf8)
        let ending = bytes.last == UInt8(ascii: "\r") ? "\r" : ""
        if !ending.isEmpty { bytes.removeLast() }
        let line = String(decoding: bytes, as: UTF8.self)
        guard let markerEnd = CheckboxSyntax.markerEnd(in: bytes, at: CheckboxSyntax.markerStart(in: bytes)),
              let box = CheckboxSyntax.box(in: bytes, after: markerEnd),
              let state = Checkbox.State(marker: box.marker), state != .icon else { return nil }
        var start = box.offset + 2
        while start < bytes.count, bytes[start] == UInt8(ascii: " ") || bytes[start] == UInt8(ascii: "\t") { start += 1 }
        let head = String(decoding: bytes[..<start], as: UTF8.self)
        let rest = String(decoding: bytes[start...], as: UTF8.self)
        let (range, token) = edit(rest)
        let text = rest as NSString
        switch (range, token) {
        case let (range?, token?):
            return head + text.replacingCharacters(in: range, with: token) + ending
        case let (range?, nil):
            return head + InlineAttributes.removing(range, from: text) + ending
        case let (nil, token?):
            let trailing = String(rest.suffix(rest.reversed().prefix(while: { $0 == " " || $0 == "\t" }).count))
            let base = rest.dropLast(trailing.count)
            return head + (base.isEmpty ? token : base + " " + token) + trailing + ending
        case (nil, nil):
            return line + ending
        }
    }

    /// `text` with line `line` replaced by `edit`'s result, its `\r` before the line ending kept.
    private static func replacingLine(_ line: Int, in text: String, _ edit: (String) -> String?) -> String? {
        var bytes = Array(text.utf8)
        var start = 0
        for _ in 0..<line {
            guard let newline = bytes[start...].firstIndex(of: UInt8(ascii: "\n")) else { return nil }
            start = newline + 1
        }
        var end = bytes[start...].firstIndex(of: UInt8(ascii: "\n")) ?? bytes.count
        if end > start, bytes[end - 1] == UInt8(ascii: "\r") { end -= 1 }
        guard let replaced = edit(String(decoding: bytes[start..<end], as: UTF8.self)) else { return nil }
        bytes.replaceSubrange(start..<end, with: Array(replaced.utf8))
        return String(decoding: bytes, as: UTF8.self)
    }
}
