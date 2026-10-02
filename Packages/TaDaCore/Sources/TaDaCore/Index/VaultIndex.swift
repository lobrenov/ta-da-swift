import Foundation

/// Every Ta Da item in the vault, held in memory. Files are the only truth; this is rebuilt at launch
/// and patched as files change.
public struct VaultIndex: Sendable {
    public private(set) var items: [String: Item] = [:]
    /// Lowercased title → paths, sorted, so resolution is stable when titles repeat across folders.
    private var pathsByTitle: [String: [String]] = [:]
    /// Project path → its tasks' paths.
    private var membersByProject: [String: [String]] = [:]

    public init(_ items: [Item] = []) {
        self.items = Dictionary(items.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
        rebuild()
    }

    public subscript(path: String) -> Item? { items[path] }

    /// Adds or replaces an item.
    public mutating func update(_ item: Item) {
        items[item.path] = item
        rebuild()
    }

    public mutating func remove(_ path: String) {
        guard items.removeValue(forKey: path) != nil else { return }
        rebuild()
    }

    public var tasks: [Item] { items.values.filter { $0.properties.kind == .task } }
    public var projects: [Item] { items.values.filter { $0.properties.kind == .project } }

    /// Items with this title, ignoring case; the first by path wins when titles repeat.
    public func items(titled title: String) -> [Item] {
        (pathsByTitle[title.lowercased()] ?? []).compactMap { items[$0] }
    }

    /// The project file a task's `project` link resolves to. Nil for loose tasks.
    public func project(of task: Item) -> Item? {
        guard task.properties.kind == .task, let link = task.properties.project else { return nil }
        return items(titled: link.title).first { $0.properties.kind == .project }
    }

    /// Tasks whose `project` resolves to this project, sorted by title.
    public func tasks(in project: Item) -> [Item] {
        (membersByProject[project.path] ?? []).compactMap { items[$0] }.sorted(by: Self.byTitle)
    }

    /// Items whose body links to this item's title, sorted by title.
    public func backlinks(to item: Item) -> [Item] {
        let title = item.title.lowercased()
        return items.values
            .filter { $0.path != item.path && $0.links.contains { $0.title.lowercased() == title } }
            .sorted(by: Self.byTitle)
    }

    /// The file's own warnings, plus one for a `project` link that doesn't resolve.
    public func warnings(for item: Item) -> [Warning] {
        guard let link = item.properties.project, project(of: item) == nil else { return item.warnings }
        return item.warnings + [.unresolvedProject(link.title)]
    }

    static func byTitle(_ a: Item, _ b: Item) -> Bool {
        let order = a.title.localizedStandardCompare(b.title)
        return order == .orderedSame ? a.path < b.path : order == .orderedAscending
    }

    private mutating func rebuild() {
        pathsByTitle = Dictionary(grouping: items.keys.sorted()) { Item.title(ofPath: $0).lowercased() }
        membersByProject = [:]
        for task in tasks {
            if let project = project(of: task) { membersByProject[project.path, default: []].append(task.path) }
        }
    }
}
