import Foundation

/// One dated entry in Upcoming. An item gets one entry on its `dueDate` and another on its `deadline`.
public struct AgendaEntry: Hashable, Sendable, Identifiable {
    public enum Kind: Sendable { case due, deadline }

    public var item: Item
    public var date: LocalDate
    public var kind: Kind

    public var id: String { "\(item.path)#\(kind)" }
}

/// A sidebar project: done/total of its linked tasks, Cancelled tasks left out of the total.
public struct ProjectProgress: Hashable, Sendable, Identifiable {
    public var project: Item
    public var done: Int
    public var total: Int

    init(project: Item, done: Int, total: Int) {
        self.project = project
        self.done = done
        self.total = total
    }

    /// The progress of `project` over `tasks`, leaving the Cancelled ones out of the total.
    public init(project: Item, tasks: [Item]) {
        let counted = tasks.filter { $0.properties.status != .cancelled }
        self.init(project: project, done: counted.count { $0.properties.status == .done }, total: counted.count)
    }

    public var open: Int { total - done }
    /// An Ongoing project shows no progress.
    public var isOngoing: Bool { project.properties.status == .ongoing }
    /// 0…1; 0 for a project without tasks.
    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    public var id: String { project.path }
}

/// Tasks shown under one project or area heading, or under no heading for tasks without a parent.
/// An area's group can be empty when only its projects have tasks in the list.
public struct TaskGroup: Hashable, Sendable, Identifiable {
    public var parent: Item?
    public var tasks: [Item]

    public var id: String { parent?.path ?? "" }
}

/// A sidebar area and its active projects.
public struct AreaProjects: Hashable, Sendable, Identifiable {
    public var area: Item
    public var projects: [ProjectProgress]

    public var id: String { area.path }
}

/// What a date shows in the Agenda's strip, month and week rows.
public struct DayMarks: Hashable, Sendable {
    /// An open task is due or at its deadline that day.
    public var hasOpenTasks: Bool
    /// That day's daily note has unchecked boxes.
    public var hasOpenBoxes: Bool
}

/// The saved queries behind the sidebar domains. `today` is always passed in. Today, Upcoming and
/// Loose list tasks; projects show their dates on their own page. Each list applies a per-item test to
/// every task, and the tests answer for one file too.
extension VaultIndex {
    /// Open tasks due or at their deadline today or earlier, plus tasks completed (Done or Cancelled) today.
    /// Sorted by their earliest date, then title.
    public func today(_ today: LocalDate) -> [Item] {
        tasks.filter { isInToday($0, today: today) }.sorted { Self.byDate($0, $1) }
    }

    /// The tasks an Agenda day lists. Today's list for `today`; for any other day, tasks due or at their deadline that
    /// day that are open or Done, sorted by their earliest date, then title.
    public func agendaDay(_ date: LocalDate, today: LocalDate) -> [Item] {
        if date == today { return self.today(today) }
        return tasks.filter { !agendaEntries(of: $0, on: [date]).isEmpty }.sorted { Self.byDate($0, $1) }
    }

    /// The entries an Agenda week lists: open or Done tasks' due dates and deadlines within the week, in Upcoming's order.
    public func agendaWeek(_ week: ISOWeek) -> [AgendaEntry] {
        tasks.flatMap { agendaEntries(of: $0, on: Set(week.days)) }.sorted(by: Self.byAgendaOrder)
    }

    /// For each date from `from` through `through` that has either mark. The daily note is looked up by `names`.
    public func dayMarks(from: LocalDate, through: LocalDate,
                         names: DailyNoteNames = DailyNoteNames()) -> [LocalDate: DayMarks] {
        guard from <= through else { return [:] }
        var marks: [LocalDate: DayMarks] = [:]
        for task in tasks where !task.properties.status.isClosed {
            for date in [task.properties.dueDate, task.properties.deadline].compactMap({ $0 }) where (from...through).contains(date) {
                marks[date, default: DayMarks(hasOpenTasks: false, hasOpenBoxes: false)].hasOpenTasks = true
            }
        }
        for offset in 0...from.days(to: through) {
            let date = from.adding(days: offset)
            guard let note = dailyNote(for: date, names: names), openCheckboxCount(note) > 0 else { continue }
            marks[date, default: DayMarks(hasOpenTasks: false, hasOpenBoxes: false)].hasOpenBoxes = true
        }
        return marks
    }

    /// Whether a task is in Today: open and due or at its deadline today or earlier, or completed (Done or Cancelled) today.
    public func isInToday(_ item: Item, today: LocalDate) -> Bool {
        let p = item.properties
        guard p.kind == .task else { return false }
        if p.status.isClosed { return p.completedDate == today }
        return [p.dueDate, p.deadline].contains { $0.map { $0 <= today } ?? false }
    }

    /// An open item whose due date or deadline has passed.
    public func isOverdue(_ item: Item, today: LocalDate) -> Bool {
        let p = item.properties
        return !p.status.isClosed && [p.dueDate, p.deadline].contains { $0.map { $0 < today } ?? false }
    }

    /// Entries for open tasks dated after today, by date, due before deadline, then title.
    public func upcoming(after today: LocalDate) -> [AgendaEntry] {
        tasks.flatMap { upcomingEntries(of: $0, after: today) }.sorted(by: Self.byAgendaOrder)
    }

    /// A task's entries in Upcoming, in its order: one on its due date and one on its deadline, when the task is
    /// open and they're after today.
    public func upcomingEntries(of item: Item, after today: LocalDate) -> [AgendaEntry] {
        let p = item.properties
        guard p.kind == .task, !p.status.isClosed else { return [] }
        return [p.dueDate.map { AgendaEntry(item: item, date: $0, kind: .due) },
                p.deadline.map { AgendaEntry(item: item, date: $0, kind: .deadline) }]
            .compactMap { $0 }
            .filter { $0.date > today }
            .sorted(by: Self.byAgendaOrder)
    }

    /// Open tasks without a parent that resolves, sorted by title.
    public func loose() -> [Item] {
        tasks.filter { isLoose($0) }.sorted(by: Self.byTitle)
    }

    /// Whether a task is in Loose tasks: open, with no project or area that resolves.
    public func isLoose(_ item: Item) -> Bool {
        item.properties.kind == .task && !item.properties.status.isClosed && parent(of: item) == nil
    }

    /// Projects that aren't Done or Cancelled, with progress over all their linked tasks, sorted by title.
    public func activeProjects() -> [ProjectProgress] {
        projects.filter { !$0.properties.status.isClosed }.sorted(by: Self.byTitle).map { progress(of: $0) }
    }

    /// Active projects without an area that resolves, sorted by title.
    public func looseProjects() -> [ProjectProgress] {
        activeProjects().filter { area(of: $0.project) == nil }
    }

    /// Every area by title, each with its active projects by title.
    public func areaProjects() -> [AreaProjects] {
        areas.sorted(by: Self.byTitle).map { area in
            AreaProjects(area: area, projects: projects(in: area).filter { !$0.properties.status.isClosed }.map { progress(of: $0) })
        }
    }

    /// Done/total of the tasks whose `project` resolves to this project, logged ones included. Cancelled tasks are left
    /// out of the total.
    public func progress(of project: Item) -> ProjectProgress {
        ProjectProgress(project: project, tasks: tasks(in: project, includingLogged: true))
    }

    /// Splits tasks into groups: tasks without a parent first, then loose projects' groups by title, then each area by
    /// title with its own tasks followed by its projects' groups. Order within a group is kept.
    public func grouped(_ tasks: [Item]) -> [TaskGroup] {
        var loose: [Item] = []
        var byParent: [String: [Item]] = [:]
        for task in tasks {
            if let parent = parent(of: task) { byParent[parent.path, default: []].append(task) } else { loose.append(task) }
        }
        let projects = byParent.keys.compactMap { items[$0] }.filter { $0.properties.kind == .project }
        let looseProjects = projects.filter { area(of: $0) == nil }.sorted(by: Self.byTitle)
        var areas = Set(byParent.keys.filter { items[$0]?.properties.kind == .area })
        areas.formUnion(projects.compactMap { area(of: $0)?.path })

        var groups = loose.isEmpty ? [] : [TaskGroup(parent: nil, tasks: loose)]
        groups += looseProjects.map { TaskGroup(parent: $0, tasks: byParent[$0.path]!) }
        for area in areas.compactMap({ items[$0] }).sorted(by: Self.byTitle) {
            groups.append(TaskGroup(parent: area, tasks: byParent[area.path] ?? []))
            groups += projects.filter { self.area(of: $0)?.path == area.path }.sorted(by: Self.byTitle)
                .map { TaskGroup(parent: $0, tasks: byParent[$0.path]!) }
        }
        return groups
    }

    /// Items that aren't logged whose title, summary or area (a task's through its project) contain every word of the
    /// query, ignoring case and diacritics. Titles that match rank first.
    public func search(_ query: String) -> [Item] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        func matches(_ text: String) -> Bool {
            words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        let hits = liveItems.filter { item in
            let area = area(of: item)?.title ?? item.properties.area?.title ?? ""
            return matches([item.title, item.summary ?? "", area].joined(separator: "\n"))
        }
        return hits.sorted { a, b in
            let (ta, tb) = (matches(a.title), matches(b.title))
            return ta != tb ? ta : Self.byTitle(a, b)
        }
    }

    /// A task's entries on `dates`, when it's open or Done.
    private func agendaEntries(of item: Item, on dates: Set<LocalDate>) -> [AgendaEntry] {
        let p = item.properties
        guard p.kind == .task, p.status != .cancelled else { return [] }
        return [p.dueDate.map { AgendaEntry(item: item, date: $0, kind: .due) },
                p.deadline.map { AgendaEntry(item: item, date: $0, kind: .deadline) }]
            .compactMap { $0 }
            .filter { dates.contains($0.date) }
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
