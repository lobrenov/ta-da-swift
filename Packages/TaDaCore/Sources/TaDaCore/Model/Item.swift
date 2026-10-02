/// One task or project file, as parsed from its text.
public struct Item: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case task, project
    }

    /// The filename without `.md`.
    public var title: String
    public var properties: Properties
    /// The body's first paragraph as plain text.
    public var summary: String?
    public var checkboxes: [Checkbox]
    /// Links in the body. They never set project membership.
    public var links: [WikiLink]
    public var warnings: [Warning]

    /// Done and total subtasks. Cancelled boxes are left out of the total; icon-only boxes aren't subtasks.
    public var subtasks: (done: Int, total: Int) {
        var done = 0, total = 0
        for box in checkboxes {
            switch box.state {
            case .done: done += 1; total += 1
            case .open: total += 1
            case .cancelled, .icon: break
            }
        }
        return (done, total)
    }

    /// Nil when the text isn't a Ta Da file (no `type: task` or `type: project`).
    public init?(parsing text: String, title: String) {
        let split = FrontmatterSplitter.split(text)
        guard let yaml = split.yaml, let read = PropertyReader.read(yaml) else { return nil }
        let body = BodyScanner.scan(split.body, firstLineIndex: split.bodyFirstLineIndex)
        self.title = title
        properties = read.properties
        summary = body.summary
        checkboxes = body.checkboxes
        links = body.links
        warnings = read.warnings
    }
}

/// The frontmatter keys Ta Da understands. Other keys are left alone.
public struct Properties: Hashable, Sendable {
    public var kind: Item.Kind
    public var status: Status = .notStarted
    public var area: String?
    public var contexts: [String] = []
    /// Tasks only; always nil on projects.
    public var project: WikiLink?
    public var createdDate: LocalDate?
    public var completedDate: LocalDate?
    public var dueDate: LocalDate?
    public var deadline: LocalDate?
    /// The `repeat` text, displayed only.
    public var repeatRule: String?

    public init(kind: Item.Kind) {
        self.kind = kind
    }
}

/// Something in a file Ta Da couldn't read as intended. The file still loads.
public enum Warning: Hashable, Sendable {
    /// The frontmatter isn't valid YAML, so only `type` was read. `line` is 1-based in the file.
    case invalidYAML(problem: String, line: Int?)
    /// Missing or empty `status`; read as Not Started.
    case missingStatus
    /// A `status` that isn't one of the four; read as Not Started.
    case unknownStatus(String)
    case invalidDate(key: String, value: String)
    /// A `project` value that isn't a `"[[Title]]"` link.
    case invalidProject(String)
    /// A list or mapping where text was expected, or vice versa.
    case unexpectedValue(key: String)
}
