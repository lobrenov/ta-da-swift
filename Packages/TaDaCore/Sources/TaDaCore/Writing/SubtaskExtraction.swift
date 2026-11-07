import Foundation
import MarkdownEngineSyntax

/// Extract to Task (⌥⌘E): a subtask line, with the lines indented under it, becomes a task file of its own and leaves
/// the text it was in.
public enum SubtaskExtraction {
    public struct Extract: Equatable, Sendable {
        /// The line's text after its box, trimmed.
        public let title: String
        /// From the box: `/` Doing, `x` Done, `-` Cancelled, any other open box Not Started.
        public let status: Status
        /// The lines indented under the subtask, outdented by their least indent; empty without any.
        public let body: String
        /// The UTF-16 range of the subtask line and the lines under it, line endings included, which the edit deletes.
        public let range: NSRange

        public init(title: String, status: Status, body: String, range: NSRange) {
            self.title = title
            self.status = status
            self.body = body
            self.range = range
        }
    }

    /// The subtask on the line holding UTF-16 `location` in `text`. Nil when the line isn't a subtask (an icon box
    /// isn't), has no text after its box, is in a quote or callout, or is inside a ``` or ~~~ code block.
    public static func extract(lineAt location: Int, in text: String) -> Extract? {
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: min(location, ns.length), length: 0))
        let content = ns.substring(with: line).trimmingCharacters(in: .newlines)
        let bytes = Array(content.utf8), indent = indentColumns(content)
        let start = CheckboxSyntax.markerStart(in: bytes)
        guard start == content.prefix(while: isIndent).utf8.count, !isInCode(line.location, in: ns),
              let markerEnd = CheckboxSyntax.markerEnd(in: bytes, at: start),
              let box = CheckboxSyntax.box(in: bytes, after: markerEnd),
              let state = Checkbox.State(marker: box.marker), state != .icon else { return nil }
        let title = String(decoding: bytes[(box.offset + 2)...], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        var end = NSMaxRange(line), children: [String] = [], location = end
        while location < ns.length {
            let next = ns.lineRange(for: NSRange(location: location, length: 0))
            let child = ns.substring(with: next).trimmingCharacters(in: .newlines)
            if child.allSatisfy(\.isWhitespace) {
                children.append("")
            } else if indentColumns(child) > indent {
                children.append(child)
                end = NSMaxRange(next)
            } else {
                break
            }
            location = NSMaxRange(next)
        }
        while children.last == "" { children.removeLast() }
        let outdent = children.filter { !$0.isEmpty }.map(indentColumns).min() ?? 0
        let body = children.map { outdented($0, by: outdent) }.joined(separator: "\n")

        let status: Status = switch state {
        case .done: .done
        case .cancelled: .cancelled
        default: box.marker == "/" ? .doing : .notStarted
        }
        return Extract(title: title, status: status, body: body,
                       range: NSRange(location: line.location, length: end - line.location))
    }

    /// Every subtask in `text` extracted, first to last, each with the lines indented under it (so a subtask under
    /// another goes with its parent's), and the text left.
    public static func extractAll(from text: String) -> (text: String, extracts: [Extract]) {
        var text = text, extracts: [Extract] = [], location = 0
        while location < (text as NSString).length {
            if let extract = extract(lineAt: location, in: text) {
                extracts.append(extract)
                text = (text as NSString).replacingCharacters(in: extract.range, with: "")
            } else {
                location = NSMaxRange((text as NSString).lineRange(for: NSRange(location: location, length: 0)))
            }
        }
        return (text, extracts)
    }

    private static func isIndent(_ character: Character) -> Bool { character == " " || character == "\t" }

    /// The columns a line's leading spaces and tabs take, a tab moving to the next multiple of 4.
    private static func indentColumns(_ line: String) -> Int {
        line.prefix(while: isIndent).reduce(0) { $1 == "\t" ? $0 / 4 * 4 + 4 : $0 + 1 }
    }

    /// `line` less the leading spaces and tabs that take its first `columns` columns.
    private static func outdented(_ line: String, by columns: Int) -> String {
        var rest = Substring(line), used = 0
        while used < columns, let first = rest.first, isIndent(first) {
            used = first == "\t" ? used / 4 * 4 + 4 : used + 1
            rest = rest.dropFirst()
        }
        return String(rest)
    }

    /// Whether a ``` or ~~~ fence before UTF-16 `location` opens a code block that hasn't closed.
    private static func isInCode(_ location: Int, in text: NSString) -> Bool {
        var inCode = false
        text.enumerateSubstrings(in: NSRange(location: 0, length: location), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            let content = text.substring(with: line).trimmingCharacters(in: .whitespaces)
            if content.hasPrefix("```") || content.hasPrefix("~~~") { inCode.toggle() }
        }
        return inCode
    }

    /// The new task's text: a task filed under `project` or else `area`, with the extract's status and its body.
    public static func taskText(_ extract: Extract, project: String? = nil, area: String? = nil, today: LocalDate) -> String {
        let text = Completion.setStatus(extract.status, in: NewFile.task(project: project, area: area, today: today), today: today)
        return extract.body.isEmpty ? text : text + extract.body + "\n"
    }
}
