// A browser's Group and Filter capsule and its menu (Group by, then the page's tags), and the picked tags' chips, the
// shown count and Clear.
#if os(macOS)
import SwiftUI
import AppKit
import TaDaCore

/// Opens the Group and Filter menu under its capsule, for one domain at a time.
@Observable
final class BrowserMenus {
    static let shared = BrowserMenus()

    private(set) var open: AppModel.Domain?
    /// The window of the open menu's capsule.
    private(set) var openWindow: ObjectIdentifier?

    @ObservationIgnored private let menu = PopupMenu(style: .full(confirm: "Pick", maxListHeight: 360), takesKeys: true,
                                                     emptyText: "No tags match", searchPrompt: "Filter tags",
                                                     row: GroupFilterChoiceRow.init)
    /// What the menu needs to refresh as its search changes and after each pick.
    @ObservationIgnored private var context: (model: AppModel, domain: AppModel.Domain, list: GroupedList?, window: NSWindow)?
    /// The open menu's capsule, in screen coordinates.
    @ObservationIgnored private var anchorRect = CGRect.zero
    /// The capsule whose menu a mouse-down on it closed, its window, and when, so the click's own action doesn't reopen it.
    @ObservationIgnored private var closedByClick: (open: AppModel.Domain, window: ObjectIdentifier, time: TimeInterval)?

    private init() {
        menu.onDismiss = { [weak self] in self?.dismiss() }
        menu.onSearch = { [weak self] _ in self?.show() }
    }

    /// Whether `domain`'s menu is open from the capsule `anchor` reads, in its window.
    func isOpen(_ domain: AppModel.Domain, at anchor: ScreenAnchor) -> Bool {
        open == domain && openWindow == anchor.window.map(ObjectIdentifier.init)
    }

    /// Closes `domain`'s menu when it's open from the capsule `anchor` reads, as that capsule goes.
    func close(_ domain: AppModel.Domain, at anchor: ScreenAnchor) {
        if isOpen(domain, at: anchor) { close() }
    }

    /// Opens `domain`'s menu: `list`'s Group by choices, when it has them, then the tags of the page's files before
    /// filtering, read again on each search and pick.
    func pick(on domain: AppModel.Domain, grouping list: GroupedList?, model: AppModel, anchor: ScreenAnchor) {
        guard let window = anchor.window, toggle(domain, in: window) else { return }
        anchorRect = anchor.rect
        context = (model, domain, list, window)
        menu.query = ""
        show()
    }

    func close() {
        menu.hide()
        context = nil
        open = nil
        openWindow = nil
    }

    private func toggle(_ domain: AppModel.Domain, in window: NSWindow) -> Bool {
        let closedByThisClick = closedByClick.map { closed in
            closed.open == domain && closed.window == ObjectIdentifier(window)
                && (NSApp.currentEvent?.timestamp ?? .infinity) - closed.time < NSEvent.doubleClickInterval
        } ?? false
        closedByClick = nil
        let wasOpen = open == domain && openWindow == ObjectIdentifier(window)
        close()
        guard !wasOpen, !closedByThisClick else { return false }
        open = domain
        openWindow = ObjectIdentifier(window)
        return true
    }

    /// Closes the menu on a click elsewhere, a scroll or esc, noting a click on its own capsule.
    private func dismiss() {
        if let open, let event = NSApp.currentEvent, event.type == .leftMouseDown, let window = event.window,
           ObjectIdentifier(window) == openWindow, anchorRect.contains(window.convertPoint(toScreen: event.locationInWindow)) {
            closedByClick = (open, ObjectIdentifier(window), event.timestamp)
        }
        close()
    }

    /// A grouping pick closes the menu; a tag pick toggles it and the menu stays. The search field shows while the
    /// page has tags.
    private func show(keeping: String? = nil) {
        guard let context else { return }
        let items = context.model.filterItems(on: context.domain)
        let filter = context.model.tagFilter(on: context.domain)
        let menu = GroupFilterChoice.menu(groupings: context.list.map { (context.model.grouping(of: $0), $0) }, items: items,
                                          picked: filter.picked, query: self.menu.query, keeping: keeping)
        self.menu.searchPrompt = filter.isActive || items.contains(where: { !$0.tags.isEmpty }) ? "Filter tags" : nil
        self.menu.show(menu.sections, highlight: menu.highlight, theme: context.model.theme, below: anchorRect,
                       inset: 0, gap: 6, in: context.window) { [weak self] choice in
            switch choice {
            case let .group(group):
                self?.close()
                if let list = context.list { context.model.setGrouping(group.grouping, of: list) }
            case let .tag(tag):
                context.model.toggleFilterTag(tag.tag.path, on: context.domain)
                self?.show(keeping: tag.tag.path)
            }
        }
    }
}

/// A row of the Group and Filter menu: a grouping or a tag.
enum GroupFilterChoice: PopupMenuItem {
    case group(GroupChoice)
    case tag(FilterTagChoice)

    var title: String {
        switch self {
        case let .group(choice): choice.title
        case let .tag(choice): choice.title
        }
    }

    var accessibilityValue: String {
        switch self {
        case let .group(choice): choice.accessibilityValue
        case let .tag(choice): choice.accessibilityValue
        }
    }

    /// Group by the list's choices (`groupings`: its current grouping and the list), hidden while a search is typed,
    /// then Filter by tag: the tags of `items`. The highlight is the tag at `keeping`, else the first tag while a search
    /// is typed, else the current grouping, else the first tag.
    static func menu(groupings: (current: Grouping, list: GroupedList)?, items: [Item], picked: Set<String>, query: String,
                     keeping: String?) -> (sections: [PopupMenuSection<GroupFilterChoice>], highlight: Int?) {
        let groups = query.isEmpty ? (groupings?.list.groupings ?? []).map { grouping in
            GroupChoice(grouping: grouping, isCurrent: grouping == groupings?.current, isDefault: grouping == groupings?.list.defaultGrouping)
        } : []
        let tags = FilterTagChoice.menu(items: items, picked: picked, query: query, keeping: keeping)
        let tagRows = tags.sections.flatMap(\.items)
        var sections: [PopupMenuSection<GroupFilterChoice>] = []
        if !groups.isEmpty { sections.append(PopupMenuSection(label: "Group by", items: groups.map(GroupFilterChoice.group))) }
        if !tagRows.isEmpty { sections.append(PopupMenuSection(label: "Filter by tag", items: tagRows.map(GroupFilterChoice.tag))) }
        let tagHighlight = tags.highlight.map { groups.count + $0 }
        let highlight = keeping != nil || !query.isEmpty ? tagHighlight : groups.firstIndex(where: \.isCurrent) ?? tagHighlight
        return (sections, highlight)
    }
}

struct GroupFilterChoiceRow: View {
    let choice: GroupFilterChoice
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        switch choice {
        case let .group(group): GroupChoiceRow(choice: group, isHighlighted: isHighlighted, theme: theme)
        case let .tag(tag): FilterTagChoiceRow(choice: tag, isHighlighted: isHighlighted, theme: theme)
        }
    }
}

/// A grouping in the Group and Filter menu.
struct GroupChoice: PopupMenuItem {
    let grouping: Grouping
    let isCurrent: Bool
    let isDefault: Bool

    var title: String { grouping.rawValue }
    var accessibilityValue: String { [isCurrent ? "Current" : "", isDefault ? "Default" : ""].filter { !$0.isEmpty }.joined(separator: ", ") }
}

struct GroupChoiceRow: View {
    let choice: GroupChoice
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: choice.grouping.systemImage)
                .font(.system(size: 12))
                .foregroundStyle(theme.color(choice.grouping.tint))
                .frame(width: 16)
            Text(choice.title).foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
            Spacer(minLength: 8)
            if choice.isDefault {
                Text("Default").font(.system(size: 11)).foregroundStyle(theme.color(\.muted))
            }
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.color(\.accent))
                .opacity(choice.isCurrent ? 1 : 0)
                .frame(width: 12)
        }
        .environment(\.theme, theme)
    }
}

struct FilterTagChoiceRow: View {
    let choice: FilterTagChoice
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.color(\.accent))
                .frame(width: 16)
            TagName(tag: choice.tag)
                .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(choice.count)")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.color(\.muted))
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.color(\.accent))
                .opacity(choice.isPicked ? 1 : 0)
                .frame(width: 12)
        }
        .environment(\.theme, theme)
    }
}

/// The Group and Filter capsule: "Group" and `list`'s choice, or "Filter" on a page with no grouping; a click opens the
/// menu. While tags are picked it takes the tag tint and counts them. Nothing on a page with no grouping while no file in
/// `items` carries a tag and none is picked.
struct GroupFilterButton: View {
    let model: AppModel
    var list: GroupedList? = nil
    let domain: AppModel.Domain
    /// The page's files before filtering.
    let items: [Item]
    @State private var anchor = ScreenAnchor()
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        let filter = model.tagFilter(on: domain)
        if list != nil || filter.isActive || items.contains(where: { !$0.tags.isEmpty }) {
            let grouping = list.map { model.grouping(of: $0) }
            let lit = hovering || BrowserMenus.shared.isOpen(domain, at: anchor)
            Button { BrowserMenus.shared.pick(on: domain, grouping: list, model: model, anchor: anchor) } label: {
                HStack(spacing: 6) {
                    Image(systemName: grouping == nil ? "line.3.horizontal.decrease" : "list.bullet.indent")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(filter.isActive ? theme.color(\.accent) : theme.color(\.muted))
                    if let grouping {
                        Text("Group").foregroundStyle(theme.color(\.muted))
                        Text(grouping.rawValue).foregroundStyle(theme.color(\.fg))
                    } else {
                        Text("Filter").foregroundStyle(theme.color(filter.isActive ? \.strong : \.muted))
                    }
                    if filter.isActive {
                        Text("\(filter.picked.count)")
                            .font(.system(size: 10.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(theme.color(\.bg))
                            .padding(.horizontal, 5)
                            .background(theme.color(\.accent), in: .capsule)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.color(\.muted))
                }
                .font(.system(size: 12.5))
                .padding(.leading, 10)
                .padding(.trailing, 9)
                .frame(height: 26)
                .background(lit ? theme.color(\.surface) : filter.isActive ? theme.tagFill() : theme.color(\.code), in: .capsule)
                .overlay(Capsule().strokeBorder(lit ? theme.color(\.surface) : filter.isActive ? theme.tagRing : theme.color(\.border)))
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .onHover { hovering = $0 }
            .background(ScreenAnchorReader(anchor: anchor))
            .accessibilityLabel(grouping.map { "Group by \($0.rawValue)" } ?? "Filter by tag")
            .accessibilityValue(filter.isActive ? "\(filter.picked.count) tags picked" : "")
            .accessibilityHint(grouping == nil ? "Picks tags to show" : "Picks how the list is grouped and tags to show")
            .onDisappear { BrowserMenus.shared.close(domain, at: anchor) }
        }
    }
}

/// A Status, Date or Open list's sections, each a foldable group of task rows. `foldKey` is the list its folds are kept
/// under; `place` names a task's project or area on its row.
struct TaskSections: View {
    let model: AppModel
    let sections: [ListSection]
    let grouping: Grouping
    let foldKey: String
    let dates: TaskRow.Dates
    var place: ((Item) -> String?)? = nil

    var body: some View {
        ForEach(sections) { section in
            let folded = model.isFolded(section, by: grouping, in: foldKey)
            VStack(alignment: .leading, spacing: 1) {
                CountGroupHeader(title: section.title, count: section.tasks.count, isExpanded: Binding(
                    get: { !folded },
                    set: { _ in model.toggleFolded(section, by: grouping, in: foldKey) }),
                    quiet: section.isClosed)
                ForEach(folded ? [] : section.tasks) { task in
                    TaskRow(item: task, selected: model.isSelected(task.path), today: model.today, dates: dates,
                            place: place?(task),
                            move: model.index.repeatMove(of: task, today: model.today),
                            onToggle: { Task { await model.toggleCompletion(task) } },
                            onSelect: { model.click(task.path) })
                    .fileMenu(model, path: task.path)
                    .taskDrag(model, path: task.path)
                }
            }
        }
    }

    /// The rows on screen, top to bottom, for the arrow keys.
    static func shown(_ sections: [ListSection], by grouping: Grouping, in foldKey: String, model: AppModel) -> [String] {
        sections.filter { !model.isFolded($0, by: grouping, in: foldKey) }.flatMap(\.tasks).map(\.path)
    }
}

/// What a filtered list shows when no file carries the picked tags.
extension EmptyState {
    static let noTagMatch = EmptyState(systemImage: "line.3.horizontal.decrease", title: "No matches",
                                       message: "Nothing here carries the picked tags.")
}

/// An icon-only button that opens the page's own file, with a tooltip.
struct OpenFileButton: View {
    let label: String
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "doc")
                .font(.system(size: 12))
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)))
                .contentShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.color(\.fg))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// While tags are picked: each as a chip with ×, then the shown count and Clear.
struct TagFilterRow: View {
    let model: AppModel
    let domain: AppModel.Domain
    /// The page's files before filtering.
    let items: [Item]
    /// How many rows the filter leaves, of how many.
    let shown: (Int, Int)
    @Environment(\.theme) private var theme

    var body: some View {
        let filter = model.tagFilter(on: domain)
        if filter.isActive {
            let tags = TagFilter.tags(of: items)
            WrappingHStack(spacing: 6) {
                ForEach(filter.picked.sorted(), id: \.self) { path in
                    if let tag = tags.first(where: { $0.tag.path == path })?.tag ?? Tag(path) {
                        PickedTagChip(tag: tag) { model.toggleFilterTag(path, on: domain) }
                    }
                }
                Text("\(shown.0) of \(shown.1) shown")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.leading, 6)
                    .frame(height: 26)
                Button("Clear") { model.clearTagFilter(on: domain) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.accent))
                    .frame(height: 26)
            }
            .font(.system(size: 12.5))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tag filter")
        }
    }
}

/// A picked tag: a filled tag chip whose × unpicks it.
private struct PickedTagChip: View {
    let tag: Tag
    let remove: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.color(\.accent))
            TagName(tag: tag).foregroundStyle(theme.color(\.strong))
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.color(\.muted))
                    .frame(width: 16, height: 16)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop filtering by \(tag.name)")
        }
        .lineLimit(1)
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(height: 26)
        .background(theme.tagFill(), in: .capsule)
        .overlay(Capsule().strokeBorder(theme.tagRing))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filtering by tag \(tag.name)")
        .accessibilityActions { Button("Stop filtering", action: remove) }
    }
}
#endif
