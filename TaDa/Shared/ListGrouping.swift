// The lists with a Group choice, and how their sections fold.
import SwiftUI
import TaDaCore

/// A list with a Group choice. Every project shares one.
enum GroupedList: String {
    case today, loose, project

    /// The menu's choices, in order.
    var groupings: [Grouping] {
        switch self {
        case .today: [.project, .status, .open, .tag]
        case .loose, .project: [.status, .date, .open, .tag]
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

    /// The paths of the rows on screen, top to bottom, each once (Tag shows a task under each of its tags), for the
    /// arrow keys and picking.
    static func shownPaths(_ sections: [ListSection], by grouping: Grouping, in foldKey: String, model: AppModel) -> [String] {
        var seen: Set<String> = []
        return sections.filter { !model.isFolded($0, by: grouping, in: foldKey) }.flatMap(\.tasks).map(\.path)
            .filter { seen.insert($0).inserted }
    }

    /// Done, Cancelled, and Date's and Tag's Completed start folded.
    func startsFolded(_ grouping: Grouping) -> Bool {
        switch kind {
        case .status(let status): status.isClosed
        case .completed: grouping == .date || grouping == .tag
        case .date, .open, .tag, .untagged: false
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
        case .tag: "tag"
        }
    }

    var tint: KeyPath<Theme, PlatformColor> {
        switch self {
        case .project, .tag: \.accent
        case .date: \.due
        case .status, .open: \.muted
        }
    }
}

/// A row of the filter menu: a tag in the page, or No tag (`tag` nil), how many of its files carry it, ticked when picked.
struct FilterTagChoice: PopupMenuItem {
    let tag: Tag?
    let count: Int
    let isPicked: Bool

    /// What `AppModel.toggleFilterTag` picks.
    var path: String { tag?.path ?? TagFilter.untagged }
    var title: String { tag?.name ?? "No tag" }
    var accessibilityValue: String { [isPicked ? "Picked" : "", count == 1 ? "1 file" : "\(count) files"].filter { !$0.isEmpty }.joined(separator: ", ") }

    /// No tag while a file in the page has none or it's picked, then the page's tags by path, picked ones kept when no file
    /// carries them any more, narrowed to those with a segment starting with what's typed. The row of the tag at `keeping`
    /// is highlighted (the one just toggled), else the first.
    static func menu(items: [Item], picked: Set<String>, query: String, keeping: String?)
        -> (sections: [PopupMenuSection<FilterTagChoice>], highlight: Int?) {
        var tags = TagFilter.tags(of: items)
        for path in picked where path != TagFilter.untagged && !tags.contains(where: { $0.tag.path == path }) {
            if let tag = Tag(path) { tags.append((tag, 0)) }
        }
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let untagged = items.count(where: \.tags.isEmpty)
        let noTag = (untagged > 0 || picked.contains(TagFilter.untagged)) && (typed.isEmpty || "no tag".hasPrefix(typed))
            ? [FilterTagChoice(tag: nil, count: untagged, isPicked: picked.contains(TagFilter.untagged))] : []
        let rows = noTag + tags.sorted { $0.tag.path < $1.tag.path }
            .filter { typed.isEmpty || $0.tag.path.split(separator: "/").contains { $0.hasPrefix(typed) } || $0.tag.path.hasPrefix(typed) }
            .map { FilterTagChoice(tag: $0.tag, count: $0.count, isPicked: picked.contains($0.tag.path)) }
        let kept = keeping.flatMap { path in rows.firstIndex { $0.path == path } }
        return ([PopupMenuSection(label: "Tags in this view", items: rows)], kept ?? (rows.isEmpty ? nil : 0))
    }
}

/// A filter row's or chip's name: the tag, its parents muted, or No tag.
struct FilterTagName: View {
    let tag: Tag?

    var body: some View {
        if let tag { TagName(tag: tag) } else { Text("No tag") }
    }
}

extension TagFilter {
    /// A picked path's tag, spelled as `items` carry it; nil for No tag. Each picked path but No tag is a tag's.
    static func pickedTag(_ path: String, in items: [Item]) -> Tag? {
        tags(of: items).first(where: { $0.tag.path == path })?.tag ?? Tag(path)
    }
}
