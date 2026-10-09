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
/// Loose list tasks; projects show their dates on their own page. Each list applies a per-item test to
/// every task, and the tests answer for one file too.
extension VaultIndex {
    /// Open tasks due or at their deadline today or earlier, plus tasks completed today.
    /// Sorted by their earliest date, then title.
    public func today(_ today: LocalDate) -> [Item] {
        tasks.filter { isInToday($0, today: today) }.sorted { Self.byDate($0, $1) }
    }

    /// Whether a task is in Today: open and due or at its deadline today or earlier, or completed today.
    public func isInToday(_ item: Item, today: LocalDate) -> Bool {
        let p = item.properties
        guard p.kind == .task else { return false }
        if p.status == .done { return p.completedDate == today }
        return [p.dueDate, p.deadline].contains { $0.map { $0 <= today } ?? false }
    }

    /// An open item whose due date or deadline has passed.
    public func isOverdue(_ item: Item, today: LocalDate) -> Bool {
        let p = item.properties
        return p.status != .done && [p.dueDate, p.deadline].contains { $0.map { $0 < today } ?? false }
    }

    /// Entries for open tasks dated after today, by date, due before deadline, then title.
    public func upcoming(after today: LocalDate) -> [AgendaEntry] {
        tasks.flatMap { upcomingEntries(of: $0, after: today) }.sorted(by: Self.byAgendaOrder)
    }

    /// A task's entries in Upcoming, in its order: one on its due date and one on its deadline, when the task is
    /// open and they're after today.
    public func upcomingEntries(of item: Item, after today: LocalDate) -> [AgendaEntry] {
        let p = item.properties
        guard p.kind == .task, p.status != .done else { return [] }
        return [p.dueDate.map { AgendaEntry(item: item, date: $0, kind: .due) },
                p.deadline.map { AgendaEntry(item: item, date: $0, kind: .deadline) }]
            .compactMap { $0 }
            .filter { $0.date > today }
            .sorted(by: Self.byAgendaOrder)
    }

    /// Open tasks without a resolvable project, sorted by title.
    public func loose() -> [Item] {
        tasks.filter { isLoose($0) }.sorted(by: Self.byTitle)
    }

    /// Whether a task is in Loose tasks: open, with a `project` that doesn't resolve or none.
    public func isLoose(_ item: Item) -> Bool {
        item.properties.kind == .task && item.properties.status != .done && project(of: item) == nil
    }

    /// Projects that aren't Done, with progress over all their linked tasks, sorted by title.
    public func activeProjects() -> [ProjectProgress] {
        projects.filter { $0.properties.status != .done }.sorted(by: Self.byTitle).map { progress(of: $0) }
    }

    /// Done/total of the tasks whose `project` resolves to this project.
    public func progress(of project: Item) -> ProjectProgress {
        let tasks = tasks(in: project)
        return ProjectProgress(project: project, done: tasks.count { $0.properties.status == .done }, total: tasks.count)
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

    /// Items whose title, summary or area contain every word of the query,
    /// ignoring case and diacritics. Titles that match rank first.
    public func search(_ query: String) -> [Item] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        func matches(_ text: String) -> Bool {
            words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        let hits = items.values.filter { item in
            let p = item.properties
            return matches([item.title, item.summary ?? "", p.area?.title ?? ""].joined(separator: "\n"))
        }
        return hits.sorted { a, b in
            let (ta, tb) = (matches(a.title), matches(b.title))
            return ta != tb ? ta : Self.byTitle(a, b)
        }
    }

    /// Upcoming's order: by date, due before deadline, then title.
    private static func byAgendaOrder(_ a: AgendaEntry, _ b: AgendaEntry) -> Bool {
        if a.date != b.date { return a.date < b.date }
        if a.kind != b.kind { return a.kind == .due }
        return byTitle(a.item, b.item)
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
