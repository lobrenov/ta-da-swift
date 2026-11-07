import Foundation

/// Every Ta Da item in the vault, held in memory. Files are the only truth; this is built at launch
/// and patched as files change. Each patch touches only the changed item's entries in the maps.
/// Logged files (in `Ta Da/logbook/`) are held too: links to them resolve, but the lists of tasks, projects and areas, the
/// files filed under a parent, and the tag map leave them out.
public struct VaultIndex: Sendable {
    public private(set) var items: [String: Item] = [:]
    /// Every item's title, lowercased.
    public private(set) var titles: Set<String> = []
    /// Lowercased title → the status of the item `items(titled:)` lists first, for titles whose first item is a task (logged
    /// included).
    public var taskStatuses: [String: Status] {
        pathsByTitle.compactMapValues { paths in
            paths.first.flatMap { items[$0] }.flatMap { $0.properties.kind == .task ? $0.properties.status : nil }
        }
    }
    /// Lowercased title → paths: live tasks, projects and areas first, then notes, then logged files, each by path, so
    /// resolution is stable when titles repeat across folders and prefers a live Ta Da file.
    private var pathsByTitle: [String: [String]] = [:]
    /// Lowercased title of a task's `project` link → the tasks' paths.
    private var tasksByProjectTitle: [String: Set<String>] = [:]
    /// Lowercased title of a project's or task's `area` link → their paths.
    private var filedByAreaTitle: [String: Set<String>] = [:]
    /// Lowercased title of a link in a body → the paths of the items that link to it.
    private var linkersByTitle: [String: Set<String>] = [:]
    /// Lowercased image filename → the paths of the items that embed it.
    private var embeddersByName: [String: Set<String>] = [:]
    /// Tag path → the paths of the items that carry it (not counting its children).
    private var pathsByTag: [String: Set<String>] = [:]
    /// Folder (`""` for the top level) → the paths of the notes straight in it.
    private var notesByFolder: [String: Set<String>] = [:]
    /// Tag path → the tag as spelled by the first carrier (live before logged, then by path), and that path, for each tag in `pathsByTag`.
    private var tagsByPath: [String: (tag: Tag, path: String)] = [:]

    public init(_ items: [Item] = []) {
        for item in items { update(item) }
    }

    public subscript(path: String) -> Item? { items[path] }

    /// Adds or replaces an item.
    public mutating func update(_ item: Item) {
        if let old = items.updateValue(item, forKey: item.path) {
            removeLinks(of: old)
            removeTags(of: old)
            Self.remove(old.path, at: Vault.folder(of: old.path), from: &notesByFolder)
            if (old.properties.kind == .note) != (item.properties.kind == .note) { sortTitle(of: item.path) }
        } else {
            addTitle(of: item.path)
        }
        addLinks(of: item)
        addTags(of: item)
        if item.properties.kind == .note, !item.isLogged { notesByFolder[Vault.folder(of: item.path), default: []].insert(item.path) }
    }

    public mutating func remove(_ path: String) {
        guard let old = items.removeValue(forKey: path) else { return }
        removeTitle(of: path)
        removeLinks(of: old)
        removeTags(of: old)
        Self.remove(path, at: Vault.folder(of: path), from: &notesByFolder)
    }

    /// Items that aren't logged.
    public var liveItems: [Item] { items.values.filter { !$0.isLogged } }
    public var tasks: [Item] { liveItems.filter { $0.properties.kind == .task } }
    public var projects: [Item] { liveItems.filter { $0.properties.kind == .project } }
    public var areas: [Item] { liveItems.filter { $0.properties.kind == .area } }
    public var notes: [Item] { notesByFolder.values.flatMap { $0 }.compactMap { items[$0] } }
    /// Logged tasks and projects.
    public var logged: [Item] { items.values.filter(\.isLogged) }

    /// Every tag carried by an item, spelled as in the first carrier (live before logged, then by path), in no order.
    /// Parents carried by no file are left out.
    var carriedTags: [Tag] { tagsByPath.values.map(\.tag) }

    /// The paths of the notes straight in `folder`, by folder.
    var notePathsByFolder: [String: Set<String>] { notesByFolder }

    /// The paths of the items that carry this tag path itself, not its children.
    func paths(carrying path: String) -> Set<String> { pathsByTag[path] ?? [] }

    /// Items with this title, ignoring case: live tasks, projects and areas, then notes, then logged files, each by path.
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
        case .area, .note: return nil
        case .project: return item.properties.area.flatMap { area(titled: $0.title) }
        case .task:
            if item.properties.project != nil { return project(of: item).flatMap { area(of: $0) } }
            return item.properties.area.flatMap { area(titled: $0.title) }
        }
    }

    /// The file a task or project is filed under: a task's project, else its area; a project's area.
    public func parent(of item: Item) -> Item? {
        switch item.properties.kind {
        case .area, .note: nil
        case .project: area(of: item)
        case .task: project(of: item) ?? item.properties.area.flatMap { area(titled: $0.title) }
        }
    }

    /// Tasks filed straight under this project or area, sorted by their earliest date, then title; logged ones only when
    /// `includingLogged`.
    public func tasks(in parent: Item, includingLogged: Bool = false) -> [Item] {
        filed(under: parent).filter { $0.properties.kind == .task && (includingLogged || !$0.isLogged) }.sorted(by: Self.byDate)
    }

    /// Projects whose `area` resolves to this area, sorted by title; logged ones only when `includingLogged`.
    public func projects(in area: Item, includingLogged: Bool = false) -> [Item] {
        filed(under: area).filter { $0.properties.kind == .project && (includingLogged || !$0.isLogged) }
    }

    /// A project's tasks that aren't Done or Cancelled, sorted by their earliest date, then title.
    public func openTasks(in project: Item) -> [Item] {
        tasks(in: project).filter { !$0.properties.status.isClosed }
    }

    /// An area's own tasks, then its projects' tasks, each sorted by their earliest date, then title.
    public func allTasks(in area: Item) -> [Item] {
        tasks(in: area) + projects(in: area).flatMap { tasks(in: $0) }
    }

    /// Items whose body links to this item's title, sorted by title.
    public func backlinks(to item: Item) -> [Item] {
        (linkersByTitle[item.title.lowercased()] ?? []).filter { $0 != item.path }.compactMap { items[$0] }.sorted(by: Self.byTitle)
    }

    /// The links in this item's body, each title once in first-appearance order, with the item it resolves to (the first
    /// by path) or nil. Embeds and frontmatter links aren't included.
    public func links(from item: Item) -> [(title: String, item: Item?)] {
        var seen = Set<String>()
        return item.links.compactMap { link in
            seen.insert(link.title.lowercased()).inserted ? (link.title, items(titled: link.title).first) : nil
        }
    }

    /// Items whose body embeds this image filename (e.g. `front.jpg`), ignoring case and folders, with how many times
    /// each embeds it, sorted by title.
    public func embedders(of name: String) -> [(item: Item, count: Int)] {
        let name = name.lowercased()
        return (embeddersByName[name] ?? []).compactMap { items[$0] }.sorted(by: Self.byTitle).map { item in
            (item, item.embeds.count { $0.attachmentName?.lowercased() == name })
        }
    }

    /// Items whose body embeds the image at `path`, as `Vault.attachmentPath(for:in:)` finds it among `paths`, with
    /// how many times each embeds it, sorted by title.
    public func embedders(ofAttachment path: String, among paths: [String]) -> [(item: Item, count: Int)] {
        embedders(of: String(path.split(separator: "/").last ?? "")).compactMap { entry in
            let count = entry.item.embeds.count { Vault.attachmentPath(for: $0, in: paths) == path }
            return count > 0 ? (entry.item, count) : nil
        }
    }

    /// The file's own warnings, plus one for a `project` or `area` link that doesn't resolve.
    public func warnings(for item: Item) -> [Warning] {
        var warnings = item.warnings
        if let link = item.properties.project, project(of: item) == nil { warnings.append(.unresolvedProject(link.title)) }
        if let link = item.properties.area, area(titled: link.title) == nil { warnings.append(.unresolvedArea(link.title)) }
        return warnings
    }

    public static func byTitle(_ a: Item, _ b: Item) -> Bool {
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
        case .task, .note:
            return []
        }
    }

    private mutating func addTitle(of path: String) {
        let title = Item.title(ofPath: path).lowercased()
        pathsByTitle[title, default: []].append(path)
        sortTitle(of: path)
        titles.insert(title)
    }

    /// Re-sorts the paths that share this path's title.
    private mutating func sortTitle(of path: String) {
        func rank(_ path: String) -> Int { Item.isLogged(path) ? 2 : items[path]?.properties.kind == .note ? 1 : 0 }
        pathsByTitle[Item.title(ofPath: path).lowercased()]?.sort { (rank($0), $0) < (rank($1), $1) }
    }

    private mutating func removeTitle(of path: String) {
        let title = Item.title(ofPath: path).lowercased()
        pathsByTitle[title]?.removeAll { $0 == path }
        if pathsByTitle[title]?.isEmpty == true {
            pathsByTitle[title] = nil
            titles.remove(title)
        }
    }

    /// Files the item under the titles it links to (a task's `project`, an `area`, and the links in its body) and the
    /// images it embeds.
    private mutating func addLinks(of item: Item) {
        if let title = projectTitle(of: item) { tasksByProjectTitle[title, default: []].insert(item.path) }
        if let title = item.properties.area?.title.lowercased() { filedByAreaTitle[title, default: []].insert(item.path) }
        for link in item.links { linkersByTitle[link.title.lowercased(), default: []].insert(item.path) }
        for name in Self.attachmentNames(of: item) { embeddersByName[name, default: []].insert(item.path) }
    }

    private mutating func removeLinks(of item: Item) {
        if let title = projectTitle(of: item) { Self.remove(item.path, at: title, from: &tasksByProjectTitle) }
        if let title = item.properties.area?.title.lowercased() { Self.remove(item.path, at: title, from: &filedByAreaTitle) }
        for link in item.links { Self.remove(item.path, at: link.title.lowercased(), from: &linkersByTitle) }
        for name in Self.attachmentNames(of: item) { Self.remove(item.path, at: name, from: &embeddersByName) }
    }

    private mutating func addTags(of item: Item) {
        for use in item.tags {
            pathsByTag[use.tag.path, default: []].insert(item.path)
            if tagsByPath[use.tag.path].map({ Self.spells(item.path, before: $0.path) }) ?? true { tagsByPath[use.tag.path] = (use.tag, item.path) }
        }
    }

    /// Whether the carrier at `a` sets a tag's spelling before the one at `b`: live files before logged ones, each by path.
    private static func spells(_ a: String, before b: String) -> Bool {
        (Item.isLogged(a) ? 1 : 0, a) < (Item.isLogged(b) ? 1 : 0, b)
    }

    private mutating func removeTags(of item: Item) {
        for use in item.tags {
            Self.remove(item.path, at: use.tag.path, from: &pathsByTag)
            guard tagsByPath[use.tag.path]?.path == item.path else { continue }
            tagsByPath[use.tag.path] = pathsByTag[use.tag.path]?.min(by: Self.spells).flatMap { path in
                items[path]?.tags.first { $0.tag.path == use.tag.path }.map { ($0.tag, path) }
            }
        }
    }

    /// The lowercased image filenames an item embeds.
    private static func attachmentNames(of item: Item) -> Set<String> {
        Set(item.embeds.compactMap { $0.attachmentName?.lowercased() })
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
