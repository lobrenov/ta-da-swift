// The quick switcher (⌘O): a popup menu with a search field near the top of the window. Empty, it lists recent files;
// typed, the matches by kind and a new task with the typed title. ↵ opens a file where it lives, a project or area
// as its browser; ⇧↵, or the last
// row, makes the task in the list on screen.
import SwiftUI
import TaDaCore

/// A quick switcher row: a file, or a new task with the typed title.
enum SwitcherChoice: Hashable, PopupMenuItem {
    case file(LinkChoice)
    case newTask(String)

    var title: String {
        switch self {
        case .file(let choice): choice.title
        case .newTask(let title): "New task “\(title)”"
        }
    }

    var accessibilityValue: String {
        if case .file(let choice) = self { choice.hint } else { "" }
    }
}

/// The quick switcher's rows: recent files while nothing is typed; else the matches, ranked as the link menu ranks
/// them, under Tasks, Projects, Areas and Notes with logged files last in each, then a new task.
final class QuickSwitcherSearch {
    /// The files and the recent ones, and the rows' icons.
    let links = LinkMenuSearch()

    func sections(_ query: String) -> [PopupMenuSection<SwitcherChoice>] {
        let index = links.source.index
        let recent = links.source.recent.compactMap { index[$0] }
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            return recent.isEmpty ? [] : [PopupMenuSection(label: "Recent", items: recent.map { .file(choice($0)) })]
        }
        let others = index.items.values.filter { !recent.contains($0) }.sorted(by: VaultIndex.byTitle)
        let matches = LinkSearch.rank(recent + others, query: query, name: \.title).prefix(LinkMenuSearch.limit)
        let groups: [(label: String, kind: Item.Kind)] = [("Tasks", .task), ("Projects", .project), ("Areas", .area), ("Notes", .note)]
        let sections = groups.map { group in
            let items = matches.filter { $0.properties.kind == group.kind }
            return PopupMenuSection(label: group.label, items: (items.filter { !$0.isLogged } + items.filter(\.isLogged)).map {
                SwitcherChoice.file(choice($0))
            })
        }
        return sections.filter { !$0.items.isEmpty } + [PopupMenuSection(items: [.newTask(query)])]
    }

    /// The link menu's choice, hinted Logbook and the month it was completed when it's logged.
    private func choice(_ item: Item) -> LinkChoice {
        let choice = links.choice(item)
        guard item.isLogged else { return choice }
        let month = item.properties.completedDate.map { " · " + $0.formatted(.shortMonth) } ?? ""
        return LinkChoice(path: choice.path, icon: choice.icon, title: choice.title, hint: "Logbook" + month)
    }
}

#if os(macOS)
import AppKit

/// Shows the quick switcher over the key window and acts on its picks. Owned by ContentView.
final class QuickSwitcher {
    private let search = QuickSwitcherSearch()
    private lazy var menu = makeMenu()
    private weak var model: AppModel?
    private weak var window: NSWindow?

    static let width: CGFloat = 560
    /// From the window's top to the menu's.
    static let top: CGFloat = 92

    /// Shows the switcher over the main window, or closes it when it's open.
    func toggle(_ model: AppModel) {
        guard !menu.isOpen else { return menu.hide() }
        guard let window = NSApp.mainWindow else { return }
        self.model = model
        self.window = window
        menu.query = ""
        refresh()
    }

    private func refresh() {
        guard let model, let window else { return }
        search.links.source = LinkMenuSource(index: model.index, vault: model.vault, recent: model.recentFiles)
        let sections = search.sections(menu.query)
        let typed = !menu.query.trimmingCharacters(in: .whitespaces).isEmpty
        menu.footerHints = [("↑↓", "Navigate"), ("↵", "Open")] + (typed ? [("⇧↵", "New task")] : []) + [("esc", "Close")]
        let anchor = CGRect(x: window.frame.midX - Self.width / 2, y: window.frame.maxY - Self.top, width: Self.width, height: 0)
        menu.show(sections, highlight: sections.isEmpty ? nil : 0, theme: model.theme, below: anchor, inset: 0, gap: 0,
                  in: window) { [weak self] in self?.pick($0) }
    }

    private func pick(_ choice: SwitcherChoice) {
        menu.hide()
        guard let model else { return }
        switch choice {
        case .file(let file): model.switchTo(file.path)
        case .newTask(let title): Task { await model.newTask(titled: title) }
        }
    }

    private func makeMenu() -> PopupMenu<SwitcherChoice, SwitcherRow> {
        var style = PopupMenuStyle.full(confirm: "Open", maxListHeight: 330)
        style.width = Self.width
        let menu = PopupMenu(style: style, takesKeys: true, emptyText: "No recent files",
                             searchPrompt: "Open a file, or type a new task’s title") { [search] choice, isHighlighted, theme in
            SwitcherRow(choice: choice, isHighlighted: isHighlighted, theme: theme, links: search.links)
        }
        menu.onSearch = { [weak self] _ in self?.refresh() }
        menu.onShiftReturn = { [weak self, unowned menu] in
            let title = menu.query.trimmingCharacters(in: .whitespaces)
            if title.isEmpty { menu.pickHighlighted() } else { self?.pick(.newTask(title)) }
        }
        return menu
    }
}

struct SwitcherRow: View {
    let choice: SwitcherChoice
    let isHighlighted: Bool
    let theme: Theme
    let links: LinkMenuSearch

    var body: some View {
        switch choice {
        case .file(let file):
            LinkMenuRow(choice: file, isHighlighted: isHighlighted, theme: theme, search: links)
        case .newTask:
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.color(\.accent))
                    .frame(width: 20)
                Text(choice.title)
                    .foregroundStyle(theme.color(\.strong))
                    .lineLimit(1)
                Spacer(minLength: 8)
                KeyCap(key: "⇧↵", theme: theme)
            }
        }
    }
}
#endif
