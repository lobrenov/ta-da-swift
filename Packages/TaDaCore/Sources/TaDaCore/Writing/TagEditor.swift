import Yams

/// Adds and removes tags in `tags:` by splicing only that key's lines. The body's tags are never touched.
extension FrontmatterEditor {
    /// Adds a tag to `tags:`, unless it's there already (ignoring case). A flow list stays flow and a block list stays
    /// block; an empty key, or a string of comma-separated tags, becomes a flow list. A missing key is added as
    /// `tags: [name]` after `createdDate`, or before the closing `---` without one. Text without frontmatter is left
    /// unchanged.
    public static func addTag(_ tag: Tag, in text: String) -> String {
        var file = Lines(text)
        guard let closing = closingFence(file) else { return text }
        guard let range = keyRange("tags", in: file, closing: closing) else {
            let at = keyRange("createdDate", in: file, closing: closing)?.upperBound ?? closing
            let ending = endingOf(file.lines[at - 1])
            file.lines.insert(Substring("tags: [\(flowItem(tag.name))]" + ending), at: at)
            return file.text
        }
        let value = TagsValue(file, range)
        guard !value.items.contains(where: { $0.tag?.path == tag.path }) else { return text }
        switch value.style {
        case let .block(indent):
            let last = value.items.last?.line ?? range.lowerBound
            let ending = endingOf(file.lines[last])
            file.lines.insert(Substring("\(indent)- \(scalar(tag.name))" + ending), at: last + 1)
        case .flow, .string, .empty:
            replace(range, in: &file, with: flowLine(value.items.map(\.raw) + [flowItem(tag.name)], suffix: value.suffix))
        }
        return file.text
    }

    /// Removes a tag from `tags:`, ignoring case, keeping the list's style. Removing the last one leaves `tags:` with no
    /// value. A tag that isn't in `tags:` leaves the text unchanged.
    public static func removeTag(_ tag: Tag, in text: String) -> String {
        var file = Lines(text)
        guard let closing = closingFence(file), let range = keyRange("tags", in: file, closing: closing) else { return text }
        let value = TagsValue(file, range)
        guard value.items.contains(where: { $0.tag?.path == tag.path }) else { return text }
        let kept = value.items.filter { $0.tag?.path != tag.path }
        switch value.style {
        case .block where !kept.isEmpty:
            for line in value.items.filter({ $0.tag?.path == tag.path }).compactMap(\.line).reversed() { file.lines.remove(at: line) }
        case _ where kept.isEmpty:
            replace(range, in: &file, with: "tags:")
        default:
            replace(range, in: &file, with: flowLine(kept.map(\.raw), suffix: value.suffix))
        }
        return file.text
    }

    private static func replace(_ range: Range<Int>, in file: inout Lines, with line: String) {
        let ending = endingOf(file.lines[range.upperBound - 1])
        file.lines.replaceSubrange(range, with: [Substring(line + ending)])
    }

    private static func flowLine(_ items: [String], suffix: String) -> String {
        "tags: [\(items.joined(separator: ", "))]\(suffix)"
    }

    /// As `scalar`, also quoting the characters that end an item in a flow list.
    static func flowItem(_ text: String) -> String {
        text.contains(where: { ",[]{}".contains($0) }) ? quoted(text) : scalar(text)
    }

    /// The `tags:` key's value as written, read item by item so items keep their spelling and quoting.
    private struct TagsValue {
        enum Style { case flow, block(indent: String), string, empty }
        struct Item {
            /// The item as written, quotes included.
            var raw: String
            /// The file line of a block item.
            var line: Int?
            var tag: Tag? { (try? Yams.compose(yaml: raw))?.scalar.flatMap { Tag($0.string) } }
        }

        var style: Style = .empty
        var items: [Item] = []
        /// What follows a flow list's `]`, such as a comment.
        var suffix = ""

        init(_ file: Lines, _ range: Range<Int>) {
            let value = Lines.content(file.lines[range.lowerBound]).dropFirst("tags:".count).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("[") {
                let joined = ([value] + range.dropFirst().map { Lines.content(file.lines[$0]).trimmingCharacters(in: .whitespaces) })
                    .joined(separator: " ")
                let parts = Self.flowItems(joined)
                style = .flow
                items = parts.items.map { Item(raw: $0) }
                suffix = parts.suffix
            } else if value.isEmpty || value.hasPrefix("#") || ["~", "null", "Null", "NULL"].contains(value) {
                for line in range.dropFirst() {
                    let content = Lines.content(file.lines[line])
                    let indent = content.prefix { $0 == " " || $0 == "\t" }
                    let rest = content.dropFirst(indent.count)
                    guard rest == "-" || rest.hasPrefix("- ") else { continue }
                    if case .empty = style { style = .block(indent: String(indent)) }
                    let raw = rest.dropFirst().trimmingCharacters(in: .whitespaces)
                    if !raw.isEmpty { items.append(Item(raw: raw, line: line)) }
                }
            } else {
                style = .string
                let text = (try? Yams.compose(yaml: value))?.scalar?.string ?? value
                items = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    .map { Item(raw: flowItem($0)) }
            }
        }

        /// The items between `[` and its `]`, split at commas outside quotes and brackets, and the text after `]`.
        private static func flowItems(_ text: String) -> (items: [String], suffix: String) {
            var items: [String] = [], current = "", depth = 0, quote: Character?
            var index = text.index(after: text.startIndex)
            while index < text.endIndex {
                let c = text[index]
                index = text.index(after: index)
                if let open = quote {
                    current.append(c)
                    if c == "\\", open == "\"", index < text.endIndex {
                        current.append(text[index])
                        index = text.index(after: index)
                    } else if c == open {
                        quote = nil
                    }
                    continue
                }
                switch c {
                case "\"", "'": quote = c; current.append(c)
                case "[", "{": depth += 1; current.append(c)
                case "]" where depth == 0, "," where depth == 0:
                    let item = current.trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty { items.append(item) }
                    current = ""
                    if c == "]" { return (items, String(text[index...])) }
                case "]", "}": depth -= 1; current.append(c)
                default: current.append(c)
                }
            }
            let item = current.trimmingCharacters(in: .whitespaces)
            return (item.isEmpty ? items : items + [item], "")
        }
    }
}
