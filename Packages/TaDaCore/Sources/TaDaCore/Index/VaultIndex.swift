import Foundation

/// Every Ta Da item in the vault, held in memory. Files are the only truth; this is built at launch
/// and patched as files change. Each patch touches only the changed item's entries in the maps.
public struct VaultIndex: Sendable {
    public private(set) var items: [String: Item] = [:]
    /// Every item's title, lowercased.
    public private(set) var titles: Set<String> = []
    /// Lowercased title → paths, sorted, so resolution is stable when titles repeat across folders.
    private var pathsByTitle: [String: [String]] = [:]
    /// Lowercased title of a task's `project` link → the tasks' paths.
    private var tasksByProjectTitle: [String: Set<String>] = [:]
    /// Lowercased title of a link in a body → the paths of the items that link to it.
    private var linkersByTitle: [String: Set<String>] = [:]

    public init(_ items: [Item] = []) {
        for item in items { update(item) }
    }

    public subscript(path: String) -> Item? { items[path] }

    /// Adds or replaces an item.
    public mutating func update(_ item: Item) {
        if let old = items.updateValue(item, forKey: item.path) {
            removeLinks(of: old)
        } else {
            addTitle(of: item.path)
        }
        addLinks(of: item)
    }

    public mutating func remove(_ path: String) {
        guard let old = items.removeValue(forKey: path) else { return }
        removeTitle(of: path)
        removeLinks(of: old)
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
        return project(titled: link.title)
    }

    /// Tasks whose `project` resolves to this project, sorted by title.
    public func tasks(in project: Item) -> [Item] {
        guard self.project(titled: project.title)?.path == project.path else { return [] }
        return (tasksByProjectTitle[project.title.lowercased()] ?? []).compactMap { items[$0] }.sorted(by: Self.byTitle)
    }

    /// Items whose body links to this item's title, sorted by title.
    public func backlinks(to item: Item) -> [Item] {
        (linkersByTitle[item.title.lowercased()] ?? []).filter { $0 != item.path }.compactMap { items[$0] }.sorted(by: Self.byTitle)
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

    /// The project a link to this title resolves to: the first project by path.
    private func project(titled title: String) -> Item? {
        items(titled: title).first { $0.properties.kind == .project }
    }

    private mutating func addTitle(of path: String) {
        let title = Item.title(ofPath: path).lowercased()
        pathsByTitle[title, default: []].append(path)
        pathsByTitle[title]?.sort()
        titles.insert(title)
    }

    private mutating func removeTitle(of path: String) {
        let title = Item.title(ofPath: path).lowercased()
        pathsByTitle[title]?.removeAll { $0 == path }
        if pathsByTitle[title]?.isEmpty == true {
            pathsByTitle[title] = nil
            titles.remove(title)
        }
    }

    /// Files the item under the titles it links to: a task's `project`, and the links in its body.
    private mutating func addLinks(of item: Item) {
        if let title = projectTitle(of: item) { tasksByProjectTitle[title, default: []].insert(item.path) }
        for link in item.links { linkersByTitle[link.title.lowercased(), default: []].insert(item.path) }
    }

    private mutating func removeLinks(of item: Item) {
        if let title = projectTitle(of: item) { Self.remove(item.path, at: title, from: &tasksByProjectTitle) }
        for link in item.links { Self.remove(item.path, at: link.title.lowercased(), from: &linkersByTitle) }
    }

    /// The lowercased title a task's `project` links to; nil for a project or a task without one.
    private func projectTitle(of item: Item) -> String? {
        guard item.properties.kind == .task else { return nil }
        return item.properties.project?.title.lowercased()
    }

    /// Takes the path out of the key's set, and the key out of the map once its set is empty.
    private static func remove(_ path: String, at key: String, from map: inout [String: Set<String>]) {
        map[key]?.remove(path)
        if map[key]?.isEmpty == true { map[key] = nil }
    }
}
