// The Logbook's groups, on the Mac and iPhone: the completed files not logged yet, then the logged ones by the day they
// were completed in the last week, then by month.
import Foundation
import TaDaCore

struct LogbookGroup: Identifiable {
    /// "Completed today", "Thursday 1 Oct", "September" or "September 2025".
    let title: String
    /// Whether the group holds the files not logged yet.
    let isWaiting: Bool
    let items: [Item]

    var id: String { title }

    /// Newest first, then by title. Files not logged yet come first; a file without a `completedDate` goes in
    /// `today`'s group.
    static func groups(_ items: [Item], today: LocalDate) -> [LogbookGroup] {
        func date(_ item: Item) -> LocalDate { item.properties.completedDate ?? today }
        let sorted = items.sorted { date($0) != date($1) ? date($0) > date($1) : VaultIndex.byTitle($0, $1) }
        var groups: [LogbookGroup] = []
        let waiting = sorted.filter { !$0.isLogged }
        if !waiting.isEmpty { groups.append(LogbookGroup(title: "Completed today", isWaiting: true, items: waiting)) }
        for item in sorted where item.isLogged {
            let title = title(for: date(item), today: today)
            if groups.last?.title == title, groups.last?.isWaiting == false {
                groups[groups.count - 1] = LogbookGroup(title: title, isWaiting: false, items: groups[groups.count - 1].items + [item])
            } else {
                groups.append(LogbookGroup(title: title, isWaiting: false, items: [item]))
            }
        }
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
