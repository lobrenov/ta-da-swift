import Foundation

/// How a browser list groups its tasks.
public enum Grouping: String, CaseIterable, Sendable {
    /// By area ▸ project, as `VaultIndex.grouped` does.
    case project = "Project"
    case status = "Status"
    /// Today, Upcoming and Someday by `dueDate` and `deadline` together, then Completed.
    case date = "Date"
    /// Open, then Completed.
    case open = "Open"
}

/// A group of a Status, Date or Open list.
public struct ListSection: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case status(Status)
        case date(DateGroup)
        case open
        case completed
    }

    /// Open tasks by their nearer date.
    public enum DateGroup: String, CaseIterable, Sendable {
        /// Due or at its deadline today or earlier.
        case today = "Today"
        /// A due date or deadline after today, and none by today.
        case upcoming = "Upcoming"
        /// Neither date.
        case someday = "Someday"
    }

    public var kind: Kind
    public var tasks: [Item]

    public var title: String {
        switch kind {
        case .status(let status): status.rawValue
        case .date(let group): group.rawValue
        case .open: "Open"
        case .completed: "Completed"
        }
    }

    public var id: String { title }

    /// Status groups' order, top to bottom. Ongoing, a project's status, follows Doing.
    public static let statusOrder: [Status] = [.doing, .ongoing, .blocked, .notStarted, .done, .cancelled]

    /// `tasks` split by `grouping`, keeping their order within each section and leaving empty sections out.
    /// `.project` isn't a section grouping and gives one Open section.
    public static func sections(_ tasks: [Item], by grouping: Grouping, today: LocalDate) -> [ListSection] {
        let open = tasks.filter { !$0.properties.status.isClosed }
        let closed = tasks.filter { $0.properties.status.isClosed }
        let sections: [ListSection]
        switch grouping {
        case .status:
            sections = statusOrder.map { status in ListSection(kind: .status(status), tasks: tasks.filter { $0.properties.status == status }) }
        case .date:
            sections = DateGroup.allCases.map { group in
                ListSection(kind: .date(group), tasks: open.filter { dateGroup(of: $0, today: today) == group })
            } + [ListSection(kind: .completed, tasks: closed)]
        case .open, .project:
            sections = [ListSection(kind: .open, tasks: open), ListSection(kind: .completed, tasks: closed)]
        }
        return sections.filter { !$0.tasks.isEmpty }
    }

    /// Where an open item goes when grouped by date.
    public static func dateGroup(of item: Item, today: LocalDate) -> DateGroup {
        let dates = [item.properties.dueDate, item.properties.deadline].compactMap { $0 }
        if dates.contains(where: { $0 <= today }) { return .today }
        return dates.isEmpty ? .someday : .upcoming
    }
}

/// The tags picked to narrow a list. A file passes when it carries a picked tag or a child of one; with none picked,
/// every file passes.
public struct TagFilter: Hashable, Sendable {
    /// Picked tags' paths.
    public var picked: Set<String>

    public init(picked: Set<String> = []) {
        self.picked = picked
    }

    public var isActive: Bool { !picked.isEmpty }

    public func matches(_ item: Item) -> Bool {
        guard isActive else { return true }
        return item.tags.contains { use in
            picked.contains(use.tag.path) || picked.contains { use.tag.path.hasPrefix($0 + "/") }
        }
    }

    public func apply(_ items: [Item]) -> [Item] {
        isActive ? items.filter(matches) : items
    }

    /// The tags `items` carry, each with how many of them carry it, by path. Each tag keeps its first spelling.
    public static func tags(of items: [Item]) -> [(tag: Tag, count: Int)] {
        var found: [String: (tag: Tag, count: Int)] = [:]
        for use in items.flatMap(\.tags) {
            found[use.tag.path] = (found[use.tag.path]?.tag ?? use.tag, (found[use.tag.path]?.count ?? 0) + 1)
        }
        return found.values.sorted { $0.tag.path < $1.tag.path }
    }
}
