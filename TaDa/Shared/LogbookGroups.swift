// The Logbook's groups, on the Mac and iPhone: the completed files that log tonight, those waiting for a project's open
// tasks, then the logged ones by the day they were completed in the last week, then by month.
import Foundation
import TaDaCore

struct LogbookGroup: Identifiable {
    enum Kind { case logsTonight, waitsForOpenTasks, logged }

    /// "Completed today", "Waiting for open tasks", "Thursday 1 Oct", "September" or "September 2025".
    let title: String
    let kind: Kind
    var items: [Item]

    var id: String { title }
    /// Whether the group holds files not logged yet.
    var isWaiting: Bool { kind != .logged }

    /// Newest first, then by title (`items` in title order skip the sort). Files not logged yet come first: those that log tonight, then those `index` holds
    /// back for a project's open tasks. A file without a `completedDate` goes in `today`'s group. A repeating task that
    /// logging moves forward isn't logged, so it's left out; one whose series ends stays.
    static func groups(_ items: [Item], index: VaultIndex, today: LocalDate) -> [LogbookGroup] {
        func date(_ item: Item) -> LocalDate { item.properties.completedDate ?? today }
        let byTitle = items.isSorted(by: VaultIndex.byTitle) ? items : items.sorted(by: VaultIndex.byTitle)
        let byDate = Dictionary(grouping: byTitle.indices) { date(byTitle[$0]) }
        var live: [Item] = []
        var logged: [LogbookGroup] = []
        var current: (title: String, items: [Item])?
        for day in byDate.keys.sorted(by: >) {
            let title = title(for: day, today: today)
            for item in byDate[day]!.map({ byTitle[$0] }) {
                guard item.isLogged else { live.append(item); continue }
                if current?.title == title {
                    current?.items.append(item)
                } else {
                    if let current { logged.append(LogbookGroup(title: current.title, kind: .logged, items: current.items)) }
                    current = (title, [item])
                }
            }
        }
        if let current { logged.append(LogbookGroup(title: current.title, kind: .logged, items: current.items)) }
        let held = live.filter(index.waitsForOpenTasks)
        let tonight = live.filter {
            if case .moves = index.repeatMove(of: $0, today: today) { return false }
            return !index.waitsForOpenTasks($0)
        }
        var groups: [LogbookGroup] = []
        if !tonight.isEmpty { groups.append(LogbookGroup(title: "Completed today", kind: .logsTonight, items: tonight)) }
        if !held.isEmpty { groups.append(LogbookGroup(title: "Waiting for open tasks", kind: .waitsForOpenTasks, items: held)) }
        groups += logged
        return groups
    }

    /// "Today", "Thursday 1 Oct" in the last week, then the month, with its year when it isn't this year's.
    private static func title(for date: LocalDate, today: LocalDate) -> String {
        if date == today { return "Today" }
        if date > today.adding(days: -7) { return date.formatted(.wideWeekdayDayMonth) }
        return date.year == today.year ? date.formatted(.month) : date.formatted(.monthYear)
    }

    /// A row's date: "Today", "1 Oct", or "1 Oct 2025" in another year.
    static func shortDate(_ item: Item, today: LocalDate) -> String {
        let date = item.properties.completedDate ?? today
        if date == today { return "Today" }
        return date.year == today.year ? date.formatted(.dayMonth) : date.formatted(.dayMonthYear)
    }

    /// A row's meta line: a task's project or area, or "Loose task"; "Project · 4 tasks · Personal" for a project.
    static func meta(_ item: Item, index: VaultIndex) -> String {
        guard item.properties.kind == .project else { return index.parent(of: item)?.title ?? "Loose task" }
        let tasks = index.tasks(in: item, includingLogged: true).count
        return (["Project", tasks == 1 ? "1 task" : "\(tasks) tasks"] + [index.area(of: item)?.title].compactMap { $0 })
            .joined(separator: " · ")
    }
}

private extension Array {
    /// Whether no element sorts before the one ahead of it.
    func isSorted(by areInOrder: (Element, Element) -> Bool) -> Bool {
        zip(self, dropFirst()).allSatisfy { !areInOrder($1, $0) }
    }
}
