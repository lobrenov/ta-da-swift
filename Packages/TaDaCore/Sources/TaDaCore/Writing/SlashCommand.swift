import Foundation

/// A markdown format offered by the editor's slash menu, in menu order.
public enum SlashCommand: CaseIterable, Sendable {
    case heading1, heading2, heading3, bulletedList, numberedList, task, quote, callout, divider, codeBlock, table
    case wikiLink, link, image
    case bold, italic, strikethrough, highlight, inlineCode

    public enum Group: String, CaseIterable, Sendable {
        case blocks = "Blocks"
        case links = "Links & media"
        case inline = "Inline"
    }

    public var title: String {
        switch self {
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bulletedList: "Bulleted list"
        case .numberedList: "Numbered list"
        case .task: "Task"
        case .quote: "Quote"
        case .callout: "Callout"
        case .divider: "Divider"
        case .codeBlock: "Code block"
        case .table: "Table"
        case .wikiLink: "Wikilink"
        case .link: "Link"
        case .image: "Image"
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .highlight: "Highlight"
        case .inlineCode: "Inline code"
        }
    }

    public var group: Group {
        switch self {
        case .heading1, .heading2, .heading3, .bulletedList, .numberedList, .task, .quote, .callout, .divider, .codeBlock,
             .table: .blocks
        case .wikiLink, .link, .image: .links
        case .bold, .italic, .strikethrough, .highlight, .inlineCode: .inline
        }
    }

    /// Other words that find it: `/todo` finds Task.
    var aliases: [String] {
        switch self {
        case .heading1: ["h1", "title"]
        case .heading2: ["h2", "subtitle"]
        case .heading3: ["h3"]
        case .bulletedList: ["ul", "unordered", "bullet"]
        case .numberedList: ["ol", "ordered", "number"]
        case .task: ["todo", "checkbox", "check"]
        case .quote: ["blockquote"]
        case .callout: ["admonition", "aside", "info", "warning", "tip"]
        case .divider: ["hr", "rule", "separator", "line"]
        case .codeBlock: ["fence", "pre", "snippet"]
        case .table: ["grid", "columns", "rows"]
        case .wikiLink: ["note", "page", "internal"]
        case .link: ["url", "href", "web"]
        case .image: ["picture", "photo", "embed"]
        case .bold: ["strong"]
        case .italic: ["emphasis", "em"]
        case .strikethrough: ["strike", "del"]
        case .highlight: ["mark"]
        case .inlineCode: ["code", "mono"]
        }
    }

    /// The markdown shown beside the title.
    public var hint: String {
        switch self {
        case .heading1: "#"
        case .heading2: "##"
        case .heading3: "###"
        case .bulletedList: "-"
        case .numberedList: "1."
        case .task: "- [ ]"
        case .quote: ">"
        case .callout: "> [!]"
        case .divider: "---"
        case .codeBlock: "```"
        case .table: "| |"
        case .wikiLink: "[[ ]]"
        case .link: "[ ]( )"
        case .image: "![ ]( )"
        case .bold: "**"
        case .italic: "*"
        case .strikethrough: "~~"
        case .highlight: "=="
        case .inlineCode: "`"
        }
    }

    /// What replaces the `/query`. One `§` marks the caret; a pair marks a selection.
    private var template: String {
        switch self {
        case .heading1: "# §"
        case .heading2: "## §"
        case .heading3: "### §"
        case .bulletedList: "- §"
        case .numberedList: "1. §"
        case .task: "- [ ] §"
        case .quote: "> §"
        case .callout: "> [!note] §"
        case .divider: "---\n§"
        case .codeBlock: "```\n§\n```"
        case .table: "| §Column§ | Column |\n| --- | --- |\n|  |  |"
        case .wikiLink: "[[§]]"
        case .link: "[§]()"
        case .image: "![](§)"
        case .bold: "**§**"
        case .italic: "*§*"
        case .strikethrough: "~~§~~"
        case .highlight: "==§=="
        case .inlineCode: "`§`"
        }
    }

    /// The text that replaces the `/query`, and the range to select in it (UTF-16).
    /// `followsBlankLine: false` puts a blank line before a divider, which would
    /// otherwise turn the paragraph above into a heading.
    public func insertion(followsBlankLine: Bool = true) -> (text: String, selection: NSRange) {
        var template = template
        if self == .divider && !followsBlankLine { template = "\n" + template }
        let parts = template.components(separatedBy: "§")
        let start = (parts[0] as NSString).length
        let length = parts.count > 2 ? (parts[1] as NSString).length : 0
        return (parts.joined(), NSRange(location: start, length: length))
    }

    /// Commands for `query`, best match first; all of them, in menu order, when it's empty.
    /// Block formats replace the line, so they're offered only when the `/` starts it.
    public static func matching(_ query: String, atLineStart: Bool) -> [SlashCommand] {
        let candidates = allCases.filter { atLineStart || $0.group != .blocks }
        let query = query.lowercased()
        guard !query.isEmpty else { return candidates }
        let ranked = candidates.enumerated().compactMap { index, command -> (rank: Int, index: Int, command: SlashCommand)? in
            guard let rank = command.rank(for: query) else { return nil }
            return (rank, index, command)
        }
        return ranked.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.command)
    }

    /// 0: the title starts with it, 1: a title word does, 2: an alias does, 3: the title contains
    /// it (three letters or more, so `/li` doesn't find Italic).
    private func rank(for query: String) -> Int? {
        let title = title.lowercased()
        if title.hasPrefix(query) { return 0 }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 1 }
        if aliases.contains(where: { $0.hasPrefix(query) }) { return 2 }
        if query.count >= 3 && title.contains(query) { return 3 }
        return nil
    }
}
