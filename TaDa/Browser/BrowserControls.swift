// A browser's Group button and menu, and its tag filter: the pill, its menu, the picked tags' chips, the shown count
// and Clear.
#if os(macOS)
import SwiftUI
import AppKit
import TaDaCore

/// Opens the Group menu or the filter menu under its control. One is open at a time.
@Observable
final class BrowserMenus {
    static let shared = BrowserMenus()

    enum Open: Equatable {
        case group(GroupedList)
        case filter(AppModel.Domain)
    }

    private(set) var open: Open?
    /// The window of the open menu's control.
    private(set) var openWindow: ObjectIdentifier?

    @ObservationIgnored private let groupMenu = PopupMenu(style: .groupMenu, takesKeys: true, row: GroupChoiceRow.init)
    @ObservationIgnored private let filterMenu = PopupMenu(style: .full(confirm: "Toggle", maxListHeight: 312), takesKeys: true,
                                                           emptyText: "No tags match", searchPrompt: "Filter tags",
                                                           row: FilterTagChoiceRow.init)
    /// What the filter menu needs to refresh as its search changes and after each pick.
    @ObservationIgnored private var filterContext: (model: AppModel, domain: AppModel.Domain, window: NSWindow)?
    /// The open menu's control, in screen coordinates.
    @ObservationIgnored private var anchorRect = CGRect.zero
    /// The control whose menu a mouse-down on it closed, and when, so the click's own action doesn't reopen it.
    @ObservationIgnored private var closedByClick: (open: Open, time: TimeInterval)?

    private init() {
        groupMenu.onDismiss = { [weak self] in self?.dismiss() }
        filterMenu.onDismiss = { [weak self] in self?.dismiss() }
        filterMenu.onSearch = { [weak self] _ in self?.showFilter() }
    }

    /// Whether `menu` is open from the control `anchor` reads, in its window.
    func isOpen(_ menu: Open, at anchor: ScreenAnchor) -> Bool {
        open == menu && openWindow == anchor.window.map(ObjectIdentifier.init)
    }

    /// Closes `menu` when it's open from the control `anchor` reads, as that control goes.
    func close(_ menu: Open, at anchor: ScreenAnchor) {
        if isOpen(menu, at: anchor) { close() }
    }

    func pickGrouping(of list: GroupedList, model: AppModel, anchor: ScreenAnchor) {
        guard let window = anchor.window, toggle(.group(list), in: window) else { return }
        let current = model.grouping(of: list)
        let items = list.groupings.map { GroupChoice(grouping: $0, isCurrent: $0 == current, isDefault: $0 == list.defaultGrouping) }
        anchorRect = anchor.rect
        groupMenu.show([PopupMenuSection(label: "Group by", items: items)], highlight: items.firstIndex(where: \.isCurrent),
                       theme: model.theme, below: anchor.rect, inset: 0, gap: 6, in: window) { [weak self] choice in
            self?.close()
            model.setGrouping(choice.grouping, of: list)
        }
    }

    /// The menu lists the tags of the page's files before filtering, read again on each search and pick.
    func pickFilterTags(on domain: AppModel.Domain, model: AppModel, anchor: ScreenAnchor) {
        guard let window = anchor.window, toggle(.filter(domain), in: window) else { return }
        anchorRect = anchor.rect
        filterContext = (model, domain, window)
        filterMenu.query = ""
        showFilter()
    }

    func close() {
        groupMenu.hide()
        filterMenu.hide()
        filterContext = nil
        open = nil
        openWindow = nil
    }

    private func toggle(_ menu: Open, in window: NSWindow) -> Bool {
        let closedByThisClick = closedByClick.map { closed in
            closed.open == menu && (NSApp.currentEvent?.timestamp ?? .infinity) - closed.time < NSEvent.doubleClickInterval
        } ?? false
        closedByClick = nil
        let wasOpen = open == menu && openWindow == ObjectIdentifier(window)
        close()
        guard !wasOpen, !closedByThisClick else { return false }
        open = menu
        openWindow = ObjectIdentifier(window)
        return true
    }

    /// Closes the menu on a click elsewhere, a scroll or esc, noting a click on its own control.
    private func dismiss() {
        if let open, let event = NSApp.currentEvent, event.type == .leftMouseDown, let window = event.window,
           anchorRect.contains(window.convertPoint(toScreen: event.locationInWindow)) {
            closedByClick = (open, event.timestamp)
        }
        close()
    }

    private func showFilter(keeping: String? = nil) {
        guard let context = filterContext else { return }
        let picked = context.model.tagFilter(on: context.domain).picked
        let menu = FilterTagChoice.menu(items: context.model.filterItems(on: context.domain), picked: picked, query: filterMenu.query, keeping: keeping)
        filterMenu.show(menu.sections, highlight: menu.highlight, theme: context.model.theme, below: anchorRect,
                        inset: 0, gap: 6, in: context.window) { [weak self] choice in
            context.model.toggleFilterTag(choice.tag.path, on: context.domain)
            self?.showFilter(keeping: choice.tag.path)
        }
    }
}

extension PopupMenuStyle {
    /// The Group menu: the full style's rows, without a footer.
    static let groupMenu = Self(width: 214, padding: 6, rowHeight: 32, rowPadding: 10, rowRadius: 7, fontSize: 13.5,
                                confirmLabel: nil, maxListHeight: .infinity, keepsHighlight: true)
}

/// A row of the Group menu.
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

/// "Group" and the list's choice in a chip on the title line; a click opens the Group menu.
struct GroupButton: View {
    let model: AppModel
    let list: GroupedList
    @State private var anchor = ScreenAnchor()
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        let grouping = model.grouping(of: list)
        let lit = hovering || BrowserMenus.shared.isOpen(.group(list), at: anchor)
        Button { BrowserMenus.shared.pickGrouping(of: list, model: model, anchor: anchor) } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.color(\.muted))
                Text("Group").foregroundStyle(theme.color(\.muted))
                Text(grouping.rawValue).foregroundStyle(theme.color(\.fg))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.color(\.muted))
            }
            .font(.system(size: 12.5))
            .padding(.leading, 10)
            .padding(.trailing, 9)
            .frame(height: 26)
            .background(theme.color(lit ? \.surface : \.code), in: .capsule)
            .overlay(Capsule().strokeBorder(theme.color(lit ? \.surface : \.border)))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .background(ScreenAnchorReader(anchor: anchor))
        .accessibilityLabel("Group by \(grouping.rawValue)")
        .accessibilityHint("Picks how the list is grouped")
        .onDisappear { BrowserMenus.shared.close(.group(list), at: anchor) }
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

/// The filter pill, the picked tags as chips with ×, then the shown count and Clear. Nothing when no file in `items`
/// carries a tag and none is picked.
struct TagFilterRow: View {
    let model: AppModel
    let domain: AppModel.Domain
    /// The page's files before filtering.
    let items: [Item]
    /// How many rows the filter leaves, of how many.
    let shown: (Int, Int)
    @State private var anchor = ScreenAnchor()
    @Environment(\.theme) private var theme

    var body: some View {
        let filter = model.tagFilter(on: domain)
        if filter.isActive || items.contains(where: { !$0.tags.isEmpty }) {
            let tags = TagFilter.tags(of: items)
            WrappingHStack(spacing: 6) {
                Button { BrowserMenus.shared.pickFilterTags(on: domain, model: model, anchor: anchor) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(filter.isActive ? theme.color(\.accent) : .primary)
                        Text("Filter")
                        if filter.picked.count > 1 {
                            Text("\(filter.picked.count)")
                                .font(.system(size: 10.5, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(theme.color(\.bg))
                                .padding(.horizontal, 5)
                                .background(theme.color(\.accent), in: .capsule)
                        }
                    }
                }
                .buttonStyle(FilterPillStyle(isOpen: BrowserMenus.shared.isOpen(.filter(domain), at: anchor), isActive: filter.isActive))
                .background(ScreenAnchorReader(anchor: anchor))
                .accessibilityLabel(filter.isActive ? "Filter, \(filter.picked.count) tags picked" : "Filter by tag")
                .accessibilityHint("Picks tags to show")
                ForEach(filter.picked.sorted(), id: \.self) { path in
                    if let tag = tags.first(where: { $0.tag.path == path })?.tag ?? Tag(path) {
                        PickedTagChip(tag: tag) { model.toggleFilterTag(path, on: domain) }
                    }
                }
                if filter.isActive {
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
            }
            .font(.system(size: 12.5))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tag filter")
            .onDisappear { BrowserMenus.shared.close(.filter(domain), at: anchor) }
        }
    }
}

/// + Tag's dashed capsule: `surface` under the pointer or while its menu is open, and the tag tint while tags are picked.
private struct FilterPillStyle: ButtonStyle {
    let isOpen: Bool
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        FilterPillBody(label: configuration.label, lit: configuration.isPressed || isOpen, isActive: isActive)
    }
}

private struct FilterPillBody<Label: View>: View {
    let label: Label
    let lit: Bool
    let isActive: Bool
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        let lit = lit || hovering
        label
            .foregroundStyle(theme.color(lit || isActive ? \.strong : \.muted))
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .frame(height: 26)
            .background(lit ? theme.color(\.surface) : isActive ? theme.tagFill() : .clear, in: .capsule)
            .overlay {
                if lit {
                    EmptyView()
                } else if isActive {
                    Capsule().strokeBorder(theme.tagRing)
                } else {
                    Capsule().strokeBorder(theme.color(\.surface), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .contentShape(.capsule)
            .onHover { hovering = $0 }
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
