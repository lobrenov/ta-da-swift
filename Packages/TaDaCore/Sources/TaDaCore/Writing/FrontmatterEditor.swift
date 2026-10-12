/// A value Ta Da writes into frontmatter, formatted per the writing rules in docs/file-format.md.
public enum PropertyValue: Equatable, Sendable {
    /// Written plain when YAML would read it back unchanged, otherwise double-quoted.
    case text(String)
    /// Unquoted `YYYY-MM-DD`.
    case date(LocalDate)
    /// `"[[Title]]"`.
    case link(title: String)
    /// Block style with quoted items; `[]` when empty.
    case list([String])
}

/// Edits one frontmatter key by splicing only its line(s). Everything else stays byte for byte.
public enum FrontmatterEditor {
    /// Replaces the key's line(s), appends the key before the closing `---` if it's missing,
    /// or creates the frontmatter block if there is none.
    public static func set(_ key: String, to value: PropertyValue, in text: String) -> String {
        var file = Lines(text)
        guard let closing = closingFence(file) else {
            let ending = file.ending
            let block = ["---"] + rendered(key, value) + ["---"]
            return block.map { $0 + ending }.joined() + text
        }
        if let range = keyRange(key, in: file, closing: closing) {
            let ending = endingOf(file.lines[range.lowerBound])
            file.lines.replaceSubrange(range, with: rendered(key, value).map { Substring($0 + ending) })
        } else {
            let ending = endingOf(file.lines[closing - 1])
            file.lines.insert(contentsOf: rendered(key, value).map { Substring($0 + ending) }, at: closing)
        }
        return file.text
    }

    /// Empties an existing key, leaving `key:`. A missing key stays missing.
    public static func clear(_ key: String, in text: String) -> String {
        var file = Lines(text)
        guard let closing = closingFence(file), let range = keyRange(key, in: file, closing: closing) else { return text }
        let ending = endingOf(file.lines[range.lowerBound])
        file.lines.replaceSubrange(range, with: [Substring(key + ":" + ending)])
        return file.text
    }

    // MARK: Locating

    /// The closing `---` line, when line 0 opens frontmatter.
    static func closingFence(_ file: Lines) -> Int? {
        guard let first = file.lines.first, FrontmatterSplitter.isFenceLine(Lines.content(first).unicodeScalars) else { return nil }
        return file.lines.indices.dropFirst().first { FrontmatterSplitter.isFenceLine(Lines.content(file.lines[$0]).unicodeScalars) }
    }

    /// The unindented `key:` line plus its continuation lines (indented lines and `- ` items).
    static func keyRange(_ key: String, in file: Lines, closing: Int) -> Range<Int>? {
        guard let start = (1..<closing).first(where: { isKeyLine(Lines.content(file.lines[$0]), key) }) else { return nil }
        var end = start + 1
        while end < closing, isContinuation(Lines.content(file.lines[end])) { end += 1 }
        return start..<end
    }

    private static func isKeyLine(_ line: Substring, _ key: String) -> Bool {
        guard line.hasPrefix(key + ":") else { return false }
        let after = line.dropFirst(key.count + 1).first
        return after == nil || after == " " || after == "\t"
    }

    static func isContinuation(_ line: Substring) -> Bool {
        line.first == " " || line.first == "\t" || line == "-" || line.hasPrefix("- ")
    }

    static func endingOf(_ line: Substring) -> String {
        line.unicodeScalars.last != "\n" ? "" : line.unicodeScalars.dropLast().last == "\r" ? "\r\n" : "\n"
    }

    // MARK: Formatting

    private static func rendered(_ key: String, _ value: PropertyValue) -> [String] {
        switch value {
        case let .text(text): ["\(key): \(scalar(text))"]
        case let .date(date): ["\(key): \(date)"]
        case let .link(title): ["\(key): \(quoted("[[\(title)]]"))"]
        case let .list(items) where items.isEmpty: ["\(key): []"]
        case let .list(items): ["\(key):"] + items.map { "  - \(quoted($0))" }
        }
    }

    /// Plain when the text starts with a letter and YAML can't read it as anything but that string.
    static func scalar(_ text: String) -> String {
        let reserved: Set<String> = ["y", "n", "yes", "no", "on", "off", "true", "false", "null"]
        let plain = text.first?.isLetter == true
            && text.last.map { !$0.isWhitespace && $0 != ":" } == true
            && !text.contains(": ") && !text.contains(" #")
            && !text.contains(where: { $0.isNewline || $0 == "\t" || $0 == "\"" || $0 == "'" || $0 == "\\" })
            && !reserved.contains(text.lowercased())
        return plain ? text : quoted(text)
    }

    static func quoted(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }
}
