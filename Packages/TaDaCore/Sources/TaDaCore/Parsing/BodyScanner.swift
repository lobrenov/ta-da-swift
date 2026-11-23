import Foundation
import MarkdownEngineSyntax

/// An ATX heading in a body.
public struct Heading: Hashable, Sendable {
    /// 1 to 6.
    public var level: Int
    /// As plain text, without the `#` markers or inline markup; a wiki link reads as its alias, target or heading.
    public var text: String
    /// The 0-based line in the body, which is the text the Live editor shows (after front matter), whatever `firstLineIndex` is.
    public var line: Int
}

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
    /// Every heading with text, in document order, skipping code and callout titles.
    public var headings: [Heading]
}

/// Reads a body with `MarkdownFacts`, the grammar the spec states.
public enum BodyScanner {
    /// - Parameter firstLineIndex: the file line the body starts on, so checkbox lines are file lines.
    public static func scan(_ body: String, firstLineIndex: Int = 0) -> BodyScan {
        let facts = MarkdownFacts.scan(body, firstLineIndex: firstLineIndex)
        // Lines as the writers split them (`Lines`): on `\n` only.
        let ns = body as NSString
        var newlines: [Int] = []
        if !facts.tasks.isEmpty {
            for i in 0..<ns.length where ns.character(at: i) == 0x0A { newlines.append(i) }
        }
        func lineStart(_ line: Int) -> Int { line == 0 ? 0 : newlines[line - 1] + 1 }
        let lines = facts.tasks.map { task -> (index: Int, marker: Int) in
            let marker = task.box.location + 1
            var (low, high) = (0, newlines.count)
            while low < high {
                let mid = (low + high) / 2
                if newlines[mid] < marker { low = mid + 1 } else { high = mid }
            }
            return (low, marker)
        }
        let boxLines = Set(lines.map(\.index))
        /// A line's indent in columns (a tab moving to the next multiple of 4) and its first other character; nil when blank.
        func indent(ofLine line: Int) -> (columns: Int, first: unichar)? {
            var (i, columns) = (lineStart(line), 0)
            while i < ns.length {
                let c = ns.character(at: i)
                if c == 0x20 { columns += 1 } else if c == 0x09 { columns = columns / 4 * 4 + 4 } else {
                    return c == 0x0A || c == 0x0D ? nil : (columns, c)
                }
                i += 1
            }
            return nil
        }
        func isNested(line: Int, columns: Int) -> Bool {
            guard columns > 0 else { return false }
            for earlier in stride(from: line - 1, through: 0, by: -1) {
                guard let above = indent(ofLine: earlier), above.columns < columns else { continue }
                return boxLines.contains(earlier)
            }
            return false
        }
        let checkboxes = zip(facts.tasks, lines).map { task, line in
            let start = lineStart(line.index)
            let column = ns.substring(with: NSRange(location: start, length: line.marker - start)).utf8.count
            let indented = indent(ofLine: line.index)
            let attributes = InlineAttributes.parse(task.text)
            return Checkbox(marker: task.marker, lineIndex: firstLineIndex + line.index, column: column, text: task.text,
                            due: attributes.due?.date, parent: attributes.parent?.title,
                            isNested: isNested(line: line.index, columns: indented?.columns ?? 0),
                            isQuoted: indented?.first == 0x3E)
        }
        return BodyScan(
            summary: facts.summary,
            checkboxes: checkboxes,
            links: facts.links.compactMap(link),
            embeds: facts.embeds.compactMap(link),
            tags: facts.tags.compactMap { Tag($0.name) }.unique,
            headings: facts.headings.filter { !$0.plainText.isEmpty }.map { Heading(level: $0.level, text: $0.plainText, line: $0.line - firstLineIndex) })
    }

    /// Where each `![[…]]` that `scan` finds sits in `body`: the range of its target (the text before any `#` or
    /// `|`, without surrounding spaces), in order.
    public static func embedTargets(in body: String) -> [(range: Range<String.Index>, link: WikiLink)] {
        let facts = MarkdownFacts.scan(body)
        return facts.embeds.compactMap { embed in
            link(embed).flatMap { link in targetRange(in: body, construct: embed.range, open: 3, target: embed.target).map { ($0, link) } }
        }
    }

    /// Where each `[[…]]` link (not an embed) that `scan` finds sits in `body`, as `embedTargets(in:)` gives them.
    public static func linkTargets(in body: String) -> [(range: Range<String.Index>, link: WikiLink)] {
        let facts = MarkdownFacts.scan(body)
        return facts.links.compactMap { fact in
            link(fact).flatMap { link in targetRange(in: body, construct: fact.range, open: 2, target: fact.parts.target).map { ($0, link) } }
        }
    }

    private static func link(_ fact: MarkdownFacts.Link) -> WikiLink? {
        WikiLink(target: fact.parts.target, heading: fact.parts.heading, block: fact.parts.block, alias: fact.parts.alias)
    }

    /// An embed's `|` segments are its alias, as `WikiLink(inner:)` reads them.
    private static func link(_ fact: MarkdownFacts.Embed) -> WikiLink? {
        let alias = fact.segments.joined(separator: "|")
        return WikiLink(target: fact.target, heading: fact.heading, block: fact.block, alias: alias.isEmpty ? nil : alias)
    }

    /// The target's range in a `[[…]]` or `![[…]]` at `construct`, `open` characters after its start, past any spaces.
    private static func targetRange(in body: String, construct: NSRange, open: Int, target: String) -> Range<String.Index>? {
        let ns = body as NSString
        var start = construct.location + open
        while start < NSMaxRange(construct), UnicodeScalar(ns.character(at: start)).map(CharacterSet.whitespaces.contains) == true {
            start += 1
        }
        let range = NSRange(location: start, length: (target as NSString).length)
        guard NSMaxRange(range) <= NSMaxRange(construct), ns.substring(with: range) == target else { return nil }
        return Range(range, in: body)
    }
}
