// The lists with a Group choice, and how their sections fold.
import SwiftUI
import TaDaCore

/// A list with a Group choice. Every project shares one.
enum GroupedList: String {
    case today, loose, project

    /// The menu's choices, in order.
    var groupings: [Grouping] {
        switch self {
        case .today: [.project, .status, .open]
        case .loose, .project: [.status, .date, .open]
        }
    }

    var defaultGrouping: Grouping {
        switch self {
        case .today: .project
        case .loose: .status
        case .project: .open
        }
    }

    /// The key Today's and Loose tasks' folds are kept under; a project's are under its path.
    var foldKey: String { ":" + rawValue }
}

extension ListSection {
    /// The name its fold is kept under. Open's groups keep the names projects folded them under before grouping.
    func foldName(_ grouping: Grouping) -> String {
        grouping == .open ? title : "\(grouping.rawValue): \(title)"
    }

    /// Done, Cancelled and Date's Completed start folded.
    func startsFolded(_ grouping: Grouping) -> Bool {
        switch kind {
        case .status(let status): status.isClosed
        case .completed: grouping == .date
        case .date, .open: false
        }
    }
}

extension Grouping {
    var systemImage: String {
        switch self {
        case .project: "circle.dotted"
        case .status: "checkmark.square"
        case .date: "calendar"
        case .open: "list.bullet"
        }
    }

    var tint: KeyPath<Theme, PlatformColor> {
        switch self {
        case .project: \.accent
        case .date: \.due
        case .status, .open: \.muted
        }
    }
}

/// A row of the filter menu: a tag in the page, how many of its files carry it, ticked when picked.
struct FilterTagChoice: PopupMenuItem {
    let tag: Tag
    let count: Int
    let isPicked: Bool

    var title: String { tag.name }
    var accessibilityValue: String { [isPicked ? "Picked" : "", count == 1 ? "1 file" : "\(count) files"].filter { !$0.isEmpty }.joined(separator: ", ") }

    /// The page's tags by path, picked ones kept when no file carries them any more, narrowed to those with a segment
    /// starting with what's typed. The row of the tag at `keeping` is highlighted (the one just toggled), else the first.
    static func menu(items: [Item], picked: Set<String>, query: String, keeping: String?)
        -> (sections: [PopupMenuSection<FilterTagChoice>], highlight: Int?) {
        var tags = TagFilter.tags(of: items)
        for path in picked where !tags.contains(where: { $0.tag.path == path }) {
            if let tag = Tag(path) { tags.append((tag, 0)) }
        }
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = tags.sorted { $0.tag.path < $1.tag.path }
            .filter { typed.isEmpty || $0.tag.path.split(separator: "/").contains { $0.hasPrefix(typed) } || $0.tag.path.hasPrefix(typed) }
            .map { FilterTagChoice(tag: $0.tag, count: $0.count, isPicked: picked.contains($0.tag.path)) }
        let kept = keeping.flatMap { path in rows.firstIndex { $0.tag.path == path } }
        return ([PopupMenuSection(label: "Tags in this view", items: rows)], kept ?? (rows.isEmpty ? nil : 0))
    }
}
