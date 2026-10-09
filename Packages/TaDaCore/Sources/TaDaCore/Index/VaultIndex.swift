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
    /// Lowercased title of a project's or task's `area` link → their paths.
    private var filedByAreaTitle: [String: Set<String>] = [:]
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
    public var areas: [Item] { items.values.filter { $0.properties.kind == .area } }

    /// Items with this title, ignoring case; the first by path wins when titles repeat.
    public func items(titled title: String) -> [Item] {
        (pathsByTitle[title.lowercased()] ?? []).compactMap { items[$0] }
    }

    /// The project file a task's `project` link resolves to. Nil for loose tasks.
    public func project(of task: Item) -> Item? {
        guard task.properties.kind == .task, let link = task.properties.project else { return nil }
        return project(titled: link.title)
    }

    /// The area file a project's `area` link resolves to, or a task's through its project; a task without a
    /// `project` uses its own `area`. Nil when there's none or it doesn't resolve.
    public func area(of item: Item) -> Item? {
        switch item.properties.kind {
        case .area: return nil
        case .project: return item.properties.area.flatMap { area(titled: $0.title) }
        case .task:
            if item.properties.project != nil { return project(of: item).flatMap { area(of: $0) } }
            return item.properties.area.flatMap { area(titled: $0.title) }
        }
    }

    /// The file a task or project is filed under: a task's project, else its area; a project's area.
    public func parent(of item: Item) -> Item? {
        switch item.properties.kind {
        case .area: nil
        case .project: area(of: item)
        case .task: project(of: item) ?? item.properties.area.flatMap { area(titled: $0.title) }
        }
    }

    /// Tasks filed straight under this project or area, sorted by title.
    public func tasks(in parent: Item) -> [Item] {
        filed(under: parent).filter { $0.properties.kind == .task }
    }

    /// Projects whose `area` resolves to this area, sorted by title.
    public func projects(in area: Item) -> [Item] {
        filed(under: area).filter { $0.properties.kind == .project }
    }

    /// An area's own tasks, then its projects' tasks, each sorted by title.
    public func allTasks(in area: Item) -> [Item] {
        tasks(in: area) + projects(in: area).flatMap { tasks(in: $0) }
    }

    /// Items whose body links to this item's title, sorted by title.
    public func backlinks(to item: Item) -> [Item] {
        (linkersByTitle[item.title.lowercased()] ?? []).filter { $0 != item.path }.compactMap { items[$0] }.sorted(by: Self.byTitle)
    }

    /// The file's own warnings, plus one for a `project` or `area` link that doesn't resolve.
    public func warnings(for item: Item) -> [Warning] {
        var warnings = item.warnings
        if let link = item.properties.project, project(of: item) == nil { warnings.append(.unresolvedProject(link.title)) }
        if let link = item.properties.area, area(titled: link.title) == nil { warnings.append(.unresolvedArea(link.title)) }
        return warnings
    }

    static func byTitle(_ a: Item, _ b: Item) -> Bool {
        let order = a.title.localizedStandardCompare(b.title)
        return order == .orderedSame ? a.path < b.path : order == .orderedAscending
    }

    /// The project a link to this title resolves to: the first project by path.
    private func project(titled title: String) -> Item? {
        items(titled: title).first { $0.properties.kind == .project }
    }

    /// The area a link to this title resolves to: the first area by path.
    private func area(titled title: String) -> Item? {
        items(titled: title).first { $0.properties.kind == .area }
    }

    /// Items whose link resolves to this project or area, sorted by title.
    private func filed(under parent: Item) -> [Item] {
        let title = parent.title.lowercased()
        switch parent.properties.kind {
        case .project:
            guard project(titled: title)?.path == parent.path else { return [] }
            return (tasksByProjectTitle[title] ?? []).compactMap { items[$0] }.sorted(by: Self.byTitle)
        case .area:
            guard area(titled: title)?.path == parent.path else { return [] }
            return (filedByAreaTitle[title] ?? []).compactMap { items[$0] }.sorted(by: Self.byTitle)
        case .task:
            return []
        }
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

    /// Files the item under the titles it links to: a task's `project`, an `area`, and the links in its body.
    private mutating func addLinks(of item: Item) {
        if let title = projectTitle(of: item) { tasksByProjectTitle[title, default: []].insert(item.path) }
        if let title = item.properties.area?.title.lowercased() { filedByAreaTitle[title, default: []].insert(item.path) }
        for link in item.links { linkersByTitle[link.title.lowercased(), default: []].insert(item.path) }
    }

    private mutating func removeLinks(of item: Item) {
        if let title = projectTitle(of: item) { Self.remove(item.path, at: title, from: &tasksByProjectTitle) }
        if let title = item.properties.area?.title.lowercased() { Self.remove(item.path, at: title, from: &filedByAreaTitle) }
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
