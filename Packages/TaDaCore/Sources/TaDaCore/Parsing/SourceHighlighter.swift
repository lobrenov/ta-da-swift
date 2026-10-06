import Foundation

/// Source-mode colouring: splits a file into runs by role, from the Editor artboard's table.
public enum SourceHighlighter {
    public enum Role: Equatable, Sendable {
        /// Fences, `:`, list dashes, brackets, `#` and `[[`/`]]`.
        case punct
        /// A frontmatter key.
        case key
        /// A plain frontmatter value.
        case value
        /// A quoted frontmatter value.
        case string
        case date
        /// A heading's text.
        case heading
        /// An open or icon-only checkbox marker, e.g. `- [ ] `.
        case check
        /// A done checkbox marker, `- [x] `.
        case checkDone
        /// The text of a done checkbox item.
        case doneText
        /// A wikilink's target.
        case link
    }

    public struct Run: Equatable, Sendable {
        public var range: NSRange
        public var role: Role
    }

    /// Runs in document order; later runs override earlier ones where they overlap. Text not covered is body text.
    /// The frontmatter is the block `FrontmatterSplitter` finds.
    public static func runs(in text: String) -> [Run] {
        let ns = text as NSString
        let frontmatterEnd = (FrontmatterSplitter.split(text).block as NSString).length
        var runs: [Run] = []
        var inCode = false

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, line, enclosing, _ in
            let content = ns.substring(with: line)
            if line.location < frontmatterEnd {
                // The block's first and last lines are its fences.
                let isFence = line.location == 0 || NSMaxRange(enclosing) == frontmatterEnd
                runs += isFence ? [Run(range: line, role: .punct)] : yamlLine(content, at: line.location)
            } else if content.trimmingCharacters(in: .whitespaces).hasPrefix("```") || content.trimmingCharacters(in: .whitespaces).hasPrefix("~~~") {
                inCode.toggle()
                runs.append(Run(range: line, role: .punct))
            } else if !inCode {
                runs += bodyLine(content, at: line.location)
            }
        }
        return runs
    }

    // MARK: Frontmatter

    private nonisolated(unsafe) static let keyLine = #/^([^\s:#][^:]*)(:)(.*)$/#
    private nonisolated(unsafe) static let listItem = #/^(\s*-)(\s+)(.*)$/#

    private static func yamlLine(_ line: String, at start: Int) -> [Run] {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            return [Run(range: NSRange(location: start, length: utf16(line)), role: .punct)]
        }
        if let match = line.wholeMatch(of: listItem) {
            let dash = Run(range: range(match.1, in: line, at: start), role: .punct)
            return [dash] + value(match.3, in: line, at: start)
        }
        if let match = line.wholeMatch(of: keyLine) {
            return [Run(range: range(match.1, in: line, at: start), role: .key),
                    Run(range: range(match.2, in: line, at: start), role: .punct)]
                + value(match.3, in: line, at: start)
        }
        return []
    }

    /// A value after `key:` or `- `: a trailing comment, a flow list, a quoted string, a date or plain text.
    private static func value(_ value: Substring, in line: String, at start: Int) -> [Run] {
        var text = value
        var runs: [Run] = []
        if let comment = commentStart(in: text) {
            runs.append(Run(range: range(text[comment...], in: line, at: start), role: .punct))
            text = text[..<comment]
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let first = text.firstIndex(where: { !$0.isWhitespace }) else { return runs }
        let body = text[first...].prefix(trimmed.count)
        if body.hasPrefix("[") {
            var items: [Run] = []
            var itemStart: Substring.Index?
            for index in body.indices {
                let character = body[index]
                if "[],".contains(character) {
                    if let s = itemStart { items += [scalarRun(body[s..<index], in: line, at: start)].compactMap { $0 } }
                    itemStart = nil
                    items.append(Run(range: range(body[index...index], in: line, at: start), role: .punct))
                } else if itemStart == nil, !character.isWhitespace {
                    itemStart = index
                }
            }
            if let s = itemStart { items += [scalarRun(body[s...], in: line, at: start)].compactMap { $0 } }
            return items + runs
        }
        return [scalarRun(body, in: line, at: start)].compactMap { $0 } + runs
    }

    /// Where a ` # comment` starts (at its space), ignoring `#` inside quotes.
    private static func commentStart(in text: Substring) -> Substring.Index? {
        var quote: Character?
        var previous = text.startIndex
        for index in text.indices {
            let character = text[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#", index == text.startIndex || text[previous].isWhitespace {
                return index == text.startIndex ? index : previous
            }
            previous = index
        }
        return nil
    }

    private static func scalarRun(_ scalar: Substring, in line: String, at start: Int) -> Run? {
        let trimmed = scalar.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let role: Role = trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") ? .string
            : LocalDate(trimmed) != nil ? .date : .value
        return Run(range: range(scalar, in: line, at: start), role: role)
    }

    // MARK: Body

    private nonisolated(unsafe) static let heading = #/^(#{1,6}\s+)(.*)$/#

    private static func bodyLine(_ line: String, at start: Int) -> [Run] {
        var runs: [Run] = []
        let bytes = Array(line.utf8)
        let markerStart = CheckboxSyntax.markerStart(in: bytes)
        if let match = line.wholeMatch(of: heading) {
            runs = [Run(range: range(match.1, in: line, at: start), role: .punct),
                    Run(range: range(match.2, in: line, at: start), role: .heading)]
        } else if let markerEnd = CheckboxSyntax.markerEnd(in: bytes, at: markerStart),
                  let box = CheckboxSyntax.box(in: bytes, after: markerEnd) {
            let done = Checkbox.State(marker: box.marker) == .done
            let syntaxEnd = box.offset + 3
            runs = [Run(range: NSRange(location: start + markerStart, length: syntaxEnd - markerStart), role: done ? .checkDone : .check)]
            if done { runs.append(Run(range: NSRange(location: start + syntaxEnd, length: utf16(line) - syntaxEnd), role: .doneText)) }
        }
        for match in line.matches(of: WikiLink.pattern) where WikiLink(inner: String(match.1)) != nil {
            runs += [Run(range: range(match.0.prefix(2), in: line, at: start), role: .punct),
                     Run(range: range(match.1, in: line, at: start), role: .link),
                     Run(range: range(match.0.suffix(2), in: line, at: start), role: .punct)]
        }
        return runs
    }

    // MARK: Ranges

    private static func utf16(_ text: some StringProtocol) -> Int { text.utf16.count }

    /// The UTF-16 range of `part` (a slice of `line`) in the whole text.
    private static func range(_ part: Substring, in line: String, at start: Int) -> NSRange {
        NSRange(location: start + line.utf16.distance(from: line.startIndex, to: part.startIndex), length: part.utf16.count)
    }
}
