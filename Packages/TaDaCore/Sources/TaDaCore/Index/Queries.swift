import Foundation

/// One dated entry in Upcoming. An item gets one entry on its `dueDate` and another on its `deadline`.
public struct AgendaEntry: Hashable, Sendable, Identifiable {
    public enum Kind: Sendable { case due, deadline }

    public var item: Item
    public var date: LocalDate
    public var kind: Kind

    public var id: String { "\(item.path)#\(kind)" }
}

/// A sidebar project: done/total of its linked tasks.
public struct ProjectProgress: Hashable, Sendable, Identifiable {
    public var project: Item
    public var done: Int
    public var total: Int

    public var open: Int { total - done }
    /// 0…1; 0 for a project without tasks.
    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    public var id: String { project.path }
}

/// Tasks shown under one project heading, or under no heading for loose tasks.
public struct TaskGroup: Hashable, Sendable, Identifiable {
    public var project: Item?
    public var tasks: [Item]

    public var id: String { project?.path ?? "" }
}

/// The saved queries behind the sidebar domains. `today` is always passed in. Today, Upcoming and
/// Loose list tasks; projects show their dates on their own page.
extension VaultIndex {
    /// Open tasks due or at their deadline today or earlier, plus tasks completed today.
    /// Sorted by their earliest date, then title.
    public func today(_ today: LocalDate) -> [Item] {
        tasks.filter { task in
            let p = task.properties
            if p.status == .done { return p.completedDate == today }
            return [p.dueDate, p.deadline].contains { $0.map { $0 <= today } ?? false }
        }
        .sorted { Self.byDate($0, $1) }
    }

    /// An open item whose due date or deadline has passed.
    public func isOverdue(_ item: Item, today: LocalDate) -> Bool {
        let p = item.properties
        return p.status != .done && [p.dueDate, p.deadline].contains { $0.map { $0 < today } ?? false }
    }

    /// Entries for open tasks dated after today, by date, due before deadline, then title.
    public func upcoming(after today: LocalDate) -> [AgendaEntry] {
        tasks.filter { $0.properties.status != .done }
            .flatMap { task -> [AgendaEntry] in
                let p = task.properties
                return [p.dueDate.map { AgendaEntry(item: task, date: $0, kind: .due) },
                        p.deadline.map { AgendaEntry(item: task, date: $0, kind: .deadline) }]
                    .compactMap { $0 }
            }
            .filter { $0.date > today }
            .sorted { a, b in
                if a.date != b.date { return a.date < b.date }
                if a.kind != b.kind { return a.kind == .due }
                return Self.byTitle(a.item, b.item)
            }
    }

    /// Open tasks without a resolvable project, sorted by title.
    public func loose() -> [Item] {
        tasks.filter { $0.properties.status != .done && project(of: $0) == nil }.sorted(by: Self.byTitle)
    }

    /// Projects that aren't Done, with progress over all their linked tasks, sorted by title.
    public func activeProjects() -> [ProjectProgress] {
        projects.filter { $0.properties.status != .done }
            .sorted(by: Self.byTitle)
            .map { project in
                let tasks = tasks(in: project)
                return ProjectProgress(project: project, done: tasks.count { $0.properties.status == .done }, total: tasks.count)
            }
    }

    /// Splits tasks into the loose group first, then one group per project by title. Order within a group is kept.
    public func grouped(_ tasks: [Item]) -> [TaskGroup] {
        var loose: [Item] = []
        var byProject: [String: [Item]] = [:]
        for task in tasks {
            if let project = project(of: task) { byProject[project.path, default: []].append(task) } else { loose.append(task) }
        }
        let projectGroups = byProject.compactMap { path, tasks in items[path].map { TaskGroup(project: $0, tasks: tasks) } }
            .sorted { Self.byTitle($0.project!, $1.project!) }
        return (loose.isEmpty ? [] : [TaskGroup(project: nil, tasks: loose)]) + projectGroups
    }

    /// Items whose title, summary, area or contexts contain every word of the query,
    /// ignoring case and diacritics. Titles that match rank first.
    public func search(_ query: String) -> [Item] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        func matches(_ text: String) -> Bool {
            words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        let hits = items.values.filter { item in
            let p = item.properties
            return matches([item.title, item.summary ?? "", p.area ?? "", p.contexts.joined(separator: " ")].joined(separator: "\n"))
        }
        return hits.sorted { a, b in
            let (ta, tb) = (matches(a.title), matches(b.title))
            return ta != tb ? ta : Self.byTitle(a, b)
        }
    }

    private static func byDate(_ a: Item, _ b: Item) -> Bool {
        func earliest(_ item: Item) -> LocalDate? { [item.properties.dueDate, item.properties.deadline].compactMap { $0 }.min() }
        switch (earliest(a), earliest(b)) {
        case let (x?, y?) where x != y: return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return byTitle(a, b)
        }
    }
}
