import Foundation

/// The attributes a checkbox line can carry after its box (see Subtasks in `docs/file-format.md`): a due date,
/// `>YYYY-MM-DD`, and a parent, `@[[Title]]`. Each starts the text or follows a space or tab; the first of each counts;
/// code spans and links hold none. Ranges are UTF-16, in the text parsed.
public struct InlineAttributes: Equatable, Sendable {
    public struct Due: Equatable, Sendable {
        public var date: LocalDate
        /// `>YYYY-MM-DD`.
        public var range: NSRange
    }

    public struct Parent: Equatable, Sendable {
        /// The link's target title: no folder, alias or heading.
        public var title: String
        /// `@[[…]]`.
        public var range: NSRange
    }

    public var due: Due?
    public var parent: Parent?

    private static let (space, tab, backtick, greater, at, open, close, paren, closeParen, newline): (UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16)
        = (0x20, 0x09, 0x60, 0x3E, 0x40, 0x5B, 0x5D, 0x28, 0x29, 0x0A)

    /// The attributes in `text`, the text after a checkbox's box.
    public static func parse(_ text: String) -> InlineAttributes {
        var found = InlineAttributes()
        let u = Array(text.utf16)
        guard u.contains(greater) || u.contains(at) else { return found }
        var i = 0
        while i < u.count, found.due == nil || found.parent == nil {
            let atBoundary = i == 0 || u[i - 1] == space || u[i - 1] == tab
            switch u[i] {
            case backtick:
                i = afterCodeSpan(u, at: i)
            case open:
                i = afterLink(u, at: i)
            case greater where atBoundary && found.due == nil:
                if let date = date(u, at: i + 1) { found.due = Due(date: date, range: NSRange(location: i, length: 11)) }
                i += 1
            case at where atBoundary && found.parent == nil && i + 2 < u.count && u[i + 1] == open && u[i + 2] == open:
                if let (title, end) = parentLink(u, at: i) {
                    found.parent = Parent(title: title, range: NSRange(location: i, length: end - i))
                    i = end
                } else {
                    i += 1
                }
            default:
                i += 1
            }
        }
        return found
    }

    /// `text` without the attributes that count, each with the space or tab before it (after it, at the start of the
    /// text), and without surrounding whitespace.
    public func stripped(from text: String) -> String {
        var result = text as NSString
        for range in [due?.range, parent?.range].compactMap({ $0 }).sorted(by: { $0.location > $1.location }) {
            result = Self.removing(range, from: result) as NSString
        }
        return (result as String).trimmingCharacters(in: .whitespaces)
    }

    /// `text` less `range` and the whitespace run before it, or after it when the range starts the text.
    static func removing(_ range: NSRange, from text: NSString) -> String {
        var (start, end) = (range.location, NSMaxRange(range))
        func isSpace(_ i: Int) -> Bool { text.character(at: i) == space || text.character(at: i) == tab }
        if start > 0 {
            while start > 0, isSpace(start - 1) { start -= 1 }
        } else {
            while end < text.length, isSpace(end) { end += 1 }
        }
        return text.replacingCharacters(in: NSRange(location: start, length: end - start), with: "")
    }

    /// `YYYY-MM-DD` at `i`, valid and not followed by a letter or digit.
    private static func date(_ u: [UInt16], at i: Int) -> LocalDate? {
        guard i + 10 <= u.count else { return nil }
        if i + 10 < u.count, let scalar = Unicode.Scalar(u[i + 10]), CharacterSet.alphanumerics.contains(scalar) { return nil }
        return LocalDate(String(decoding: u[i..<(i + 10)], as: UTF16.self))
    }

    /// The title and end of the `@[[…]]` at `i`; nil when it has no closing `]]` on the line or links no file.
    private static func parentLink(_ u: [UInt16], at i: Int) -> (String, Int)? {
        var j = i + 3
        while j + 1 < u.count, u[j] != close, u[j] != open, u[j] != newline { j += 1 }
        guard j + 1 < u.count, u[j] == close, u[j + 1] == close,
              let link = WikiLink(inner: String(decoding: u[(i + 3)..<j], as: UTF16.self)) else { return nil }
        return (link.title, j + 2)
    }

    /// The index after the code span opened by the backtick run at `i`, or after the run when nothing closes it.
    private static func afterCodeSpan(_ u: [UInt16], at i: Int) -> Int {
        var length = 0
        while i + length < u.count, u[i + length] == backtick { length += 1 }
        var j = i + length
        while j < u.count {
            guard u[j] == backtick else { j += 1; continue }
            var run = 0
            while j + run < u.count, u[j + run] == backtick { run += 1 }
            if run == length { return j + run }
            j += run
        }
        return i + length
    }

    /// The index after the `[[…]]` or `[text](target)` that starts at `i`, or after the bracket when it isn't one.
    private static func afterLink(_ u: [UInt16], at i: Int) -> Int {
        if i + 1 < u.count, u[i + 1] == open {
            var j = i + 2
            while j + 1 < u.count {
                if u[j] == close, u[j + 1] == close { return j + 2 }
                j += 1
            }
            return i + 1
        }
        guard let end = u[(i + 1)...].firstIndex(of: close), end + 1 < u.count, u[end + 1] == paren,
              let closing = u[(end + 2)...].firstIndex(of: closeParen) else { return i + 1 }
        return closing + 1
    }
}
