/// What a task or project is filed under, by title. A task names one project or one area; a project names an area.
public enum Parent: Hashable, Sendable {
    case project(String)
    case area(String)

    /// The frontmatter key the parent is written in.
    public var key: String {
        switch self {
        case .project: "project"
        case .area: "area"
        }
    }

    public var title: String {
        switch self {
        case let .project(title), let .area(title): title
        }
    }

    /// Writes `parent` as a link and empties the other key; nil empties both. Keys that are missing stay missing.
    public static func set(_ parent: Parent?, in text: String) -> String {
        switch parent {
        case let .project(title):
            FrontmatterEditor.clear("area", in: FrontmatterEditor.set("project", to: .link(title: title), in: text))
        case let .area(title):
            FrontmatterEditor.clear("project", in: FrontmatterEditor.set("area", to: .link(title: title), in: text))
        case nil:
            FrontmatterEditor.clear("area", in: FrontmatterEditor.clear("project", in: text))
        }
    }
}
