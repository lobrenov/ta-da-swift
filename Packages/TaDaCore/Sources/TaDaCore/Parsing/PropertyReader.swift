import Foundation
import Yams

public enum PropertyReader {
    /// Reads frontmatter YAML from Yams' node tree, so values stay the strings that were written:
    /// no YAML 1.1 coercion of dates, `yes`/`no` or numbers.
    /// Nil when the YAML doesn't declare `type: task`, `type: project` or `type: area` (matched case-insensitively).
    /// Invalid YAML falls back to a line scan for `type`, so a broken Ta Da file still loads with a warning.
    public static func read(_ yaml: String) -> (properties: Properties, warnings: [Warning])? {
        let root: Node?
        do {
            root = try Yams.compose(yaml: yaml)
        } catch {
            guard let kind = scanKind(yaml) else { return nil }
            return (Properties(kind: kind), [invalidYAML(error)])
        }
        guard let root, root.mapping != nil else { return nil }

        var reader = Reader(root: root)
        guard let kind = reader.text("type").flatMap({ Item.Kind(rawValue: $0.lowercased()) }) else { return nil }
        var properties = Properties(kind: kind)

        if kind != .area {
            if let status = reader.text("status") {
                if let parsed = Status(reading: status) {
                    properties.status = parsed
                } else {
                    reader.warnings.append(.unknownStatus(status))
                }
            } else {
                reader.warnings.append(.missingStatus)
            }
        }
        let project = kind == .task ? reader.text("project") : nil
        if let project {
            properties.project = WikiLink(project)
            if properties.project == nil { reader.warnings.append(.invalidProject(project)) }
        }
        if kind != .area, let area = reader.text("area").flatMap(Self.areaLink) {
            if project == nil { properties.area = area } else { reader.warnings.append(.areaIgnored(area.title)) }
        }
        properties.createdDate = reader.date("createdDate")
        properties.completedDate = reader.date("completedDate")
        properties.dueDate = reader.date("dueDate")
        properties.deadline = reader.date("deadline")
        properties.repeatRule = reader.text("repeat")
        properties.tags = reader.tags()
        return (properties, reader.warnings)
    }

    private struct Reader {
        let root: Node
        var warnings: [Warning] = []

        /// A scalar's text; nil when missing or empty.
        mutating func text(_ key: String) -> String? {
            guard let node = root[key] else { return nil }
            guard let scalar = node.scalar else {
                warnings.append(.unexpectedValue(key: key))
                return nil
            }
            return isEmpty(scalar) ? nil : scalar.string
        }

        mutating func date(_ key: String) -> LocalDate? {
            guard let text = text(key) else { return nil }
            guard let date = LocalDate(text) else {
                warnings.append(.invalidDate(key: key, value: text))
                return nil
            }
            return date
        }

        /// `tags:` as a list of strings, or one string split on commas. Other items are skipped.
        mutating func tags() -> [Tag] {
            guard let node = root["tags"] else { return [] }
            let texts: [String]
            if let sequence = node.sequence {
                texts = sequence.compactMap { $0.scalar.flatMap { isEmpty($0) ? nil : $0.string } }
            } else if let scalar = node.scalar {
                texts = isEmpty(scalar) ? [] : scalar.string.split(separator: ",").map(String.init)
            } else {
                warnings.append(.unexpectedValue(key: "tags"))
                return []
            }
            return texts.compactMap(Tag.init).unique
        }

        /// Empty, or an unquoted YAML null (`~`, `null`).
        private func isEmpty(_ scalar: Node.Scalar) -> Bool {
            scalar.string.isEmpty
                || (scalar.style == .plain && ["~", "null", "Null", "NULL"].contains(scalar.string))
        }
    }

    /// An `area` value: a `"[[Title]]"` link, or plain text read as the title.
    private static func areaLink(_ text: String) -> WikiLink? {
        WikiLink(text) ?? WikiLink(inner: text)
    }

    /// Finds an unindented `type: task|project|area` line, with optional quotes.
    private static func scanKind(_ yaml: String) -> Item.Kind? {
        for line in yaml.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            guard line.hasPrefix("type:") else { continue }
            let value = line.dropFirst("type:".count)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return Item.Kind(rawValue: value.lowercased())
        }
        return nil
    }

    private static func invalidYAML(_ error: any Error) -> Warning {
        // Yams' marks are 1-based within the YAML, which starts on the file's second line.
        switch error {
        case let YamlError.scanner(_, problem, mark, _),
             let YamlError.parser(_, problem, mark, _),
             let YamlError.composer(_, problem, mark, _):
            return .invalidYAML(problem: problem, line: mark.line + 1)
        default:
            return .invalidYAML(problem: String(describing: error), line: nil)
        }
    }
}
