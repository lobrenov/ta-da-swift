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
}
