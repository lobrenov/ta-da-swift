// The pickers under the property chips: status and project in popup menus, and dates in a calendar. One is open
// at a time; its chip keeps an accent ring until it closes.
import SwiftUI
import AppKit
import TaDaCore

/// Opens a chip's picker under it and writes what's picked.
@Observable
final class PropertyPicker {
    static let shared = PropertyPicker()

    /// The file and key whose picker is open.
    private(set) var open: Target?

    struct Target: Hashable {
        let path: String
        let key: String
    }

    @ObservationIgnored private let statusMenu = PopupMenu(style: .full(confirm: "Set", maxListHeight: 400), takesKeys: true,
                                                           row: StatusChoiceRow.init)
    @ObservationIgnored private let projectMenu = PopupMenu(style: .full(confirm: "Set", maxListHeight: 312), takesKeys: true,
                                                            searchPrompt: ProjectChoice.findPrompt, row: ProjectChoiceRow.init)
    @ObservationIgnored private let calendar = CalendarPicker()
    /// The open picker's chip, in screen coordinates.
    @ObservationIgnored private var anchor = CGRect.zero
    /// The chip whose picker a mouse-down on it closed, and when, so the click's own action doesn't reopen it.
    @ObservationIgnored private var closedByClick: (target: Target, time: TimeInterval)?
    /// What the project menu needs to refresh as its search changes.
    @ObservationIgnored private var projectMenuContext: ProjectMenuContext?
    /// The row the file menu's Move, Schedule or Set Deadline… came from, ringed while the picker is open.
    @ObservationIgnored private var ringed: (model: AppModel, path: String)?

    private struct ProjectMenuContext {
        let tasks: [Item]
        let model: AppModel
        let anchor: CGRect
        let gap: CGFloat
        let window: NSWindow
        /// New project… was picked with nothing typed, so the search field takes the name.
        var naming = false
    }

    private init() {
        statusMenu.onDismiss = { [weak self] in self?.dismiss() }
        projectMenu.onDismiss = { [weak self] in self?.dismiss() }
        calendar.onDismiss = { [weak self] in self?.dismiss() }
        projectMenu.onSearch = { [weak self] _ in self?.showProjects() }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PropertyPicker.shared.close() }
        }
    }

    func isOpen(_ path: String, _ key: String) -> Bool { open == Target(path: path, key: key) }

    /// Opens the status menu under `anchor`, or closes it when it's open.
    func pickStatus(of item: Item, model: AppModel, anchor: ScreenAnchor) {
        guard let window = anchor.window, toggle(item.path, "status", anchor: anchor.rect) else { return }
        let current = item.properties.status
        let choices = StatusChoice.order.map { StatusChoice(status: $0, isCurrent: $0 == current) }
        statusMenu.show([PopupMenuSection(label: "Status", items: choices)], highlight: choices.firstIndex(where: \.isCurrent),
                        theme: model.theme, below: anchor.rect, inset: 0, gap: 6, in: window) { [weak self] choice in
            self?.close()
            if choice.status != current { Task { await model.setStatus(choice.status, in: item.path) } }
        }
    }

    /// Opens the project menu for `tasks` under `anchor`, or closes it when it's open.
    func pickProject(of tasks: [Item], model: AppModel, anchor: ScreenAnchor, gap: CGFloat = 6) {
        guard let window = anchor.window else { return }
        pickProject(of: tasks, model: model, below: anchor.rect, gap: gap, in: window)
    }

    /// Opens the project menu for `tasks` below `rect` (screen coordinates), or closes it when it's open. `ringed`
    /// is a row to ring while it's open.
    func pickProject(of tasks: [Item], model: AppModel, below rect: CGRect, gap: CGFloat = 6, in window: NSWindow,
                     ringing ringed: String? = nil) {
        guard let first = tasks.first, toggle(first.path, "project", anchor: rect) else { return }
        projectMenuContext = ProjectMenuContext(tasks: tasks, model: model, anchor: rect, gap: gap, window: window)
        ring(ringed, model: model)
        projectMenu.query = ""
        projectMenu.searchPrompt = ProjectChoice.findPrompt
        showProjects()
    }

    /// Opens `kind`'s calendar for `items` under `anchor`, or closes it when it's open.
    func pickDate(_ kind: AgendaEntry.Kind, of items: [Item], model: AppModel, anchor: ScreenAnchor, gap: CGFloat = 6) {
        guard let window = anchor.window else { return }
        pickDate(kind, of: items, model: model, below: anchor.rect, gap: gap, in: window)
    }

    /// Opens `kind`'s calendar for `items` below `rect` (screen coordinates), or closes it when it's open.
    /// `ringed` is a row to ring while it's open.
    func pickDate(_ kind: AgendaEntry.Kind, of items: [Item], model: AppModel, below rect: CGRect, gap: CGFloat = 6,
                  in window: NSWindow, ringing ringed: String? = nil) {
        guard let first = items.first, toggle(first.path, kind.key, anchor: rect) else { return }
        ring(ringed, model: model)
        // Several files have a date, and the other date's dot, only when they all agree.
        func agreed(_ date: KeyPath<Properties, LocalDate?>) -> LocalDate? {
            let dates = Set(items.map { $0.properties[keyPath: date] })
            return dates.count == 1 ? dates.first ?? nil : nil
        }
        let current = agreed(kind.date)
        let paths = items.map(\.path)
        calendar.show(kind, selected: current, other: agreed(kind == .due ? \.deadline : \.dueDate), today: model.today,
                      theme: model.theme, below: rect, gap: gap, in: window) { [weak self] date in
            self?.close()
            if date != current { Task { await model.setDate(kind, to: date, of: paths) } }
        }
    }

    /// Closes the picker open for `path`, if there is one.
    func close(path: String) {
        if open?.path == path { close() }
    }

    func close() {
        statusMenu.hide()
        projectMenu.hide()
        calendar.hide()
        if let ringed, ringed.model.menuTarget == ringed.path {
            ringed.model.menuTarget = nil
        }
        ringed = nil
        projectMenuContext = nil
        open = nil
    }

    private func ring(_ path: String?, model: AppModel) {
        guard let path else { return }
        ringed = (model, path)
        model.menuTarget = path
    }

    /// Closes the open picker. True when `key`'s picker is to open under `anchor`; false when it was the one
    /// open, or a mouse-down on its chip has just closed it.
    private func toggle(_ path: String, _ key: String, anchor: CGRect) -> Bool {
        let target = Target(path: path, key: key)
        let closedByThisClick = closedByClick.map { closed in
            closed.target == target && (NSApp.currentEvent?.timestamp ?? .infinity) - closed.time < NSEvent.doubleClickInterval
        } ?? false
        closedByClick = nil
        let wasOpen = open == target
        close()
        guard !wasOpen, !closedByThisClick else { return false }
        open = target
        self.anchor = anchor
        return true
    }

    /// Closes the picker on a click elsewhere, a scroll or esc, noting a click on its own chip.
    private func dismiss() {
        if let open, let event = NSApp.currentEvent, event.type == .leftMouseDown, let window = event.window,
           anchor.contains(window.convertPoint(toScreen: event.locationInWindow)) {
            closedByClick = (open, event.timestamp)
        }
        close()
    }

    private func showProjects() {
        guard let context = projectMenuContext else { return }
        let index = context.model.index
        // Several tasks have a current project, or are loose, only when they all agree.
        let projects = Set(context.tasks.map { index.project(of: $0)?.path })
        let current = projects.count == 1 ? context.tasks.first.flatMap { index.project(of: $0) }.map { index.progress(of: $0) } : nil
        let existing = Set(index.projects.map { String($0.path.split(separator: "/").last ?? "") })
        let menu = ProjectChoice.menu(projects: context.model.projects, current: current,
                                      isLoose: context.tasks.allSatisfy { $0.properties.project == nil }, query: projectMenu.query,
                                      naming: context.naming, existing: existing)
        projectMenu.show(menu.sections, highlight: menu.highlight, theme: context.model.theme, below: context.anchor,
                         inset: 0, gap: context.gap, in: context.window) { [weak self] choice in
            self?.pick(choice)
        }
    }

    private func pick(_ choice: ProjectChoice) {
        guard let context = projectMenuContext else { return }
        if case .new(let name, _) = choice, name.isEmpty {
            projectMenuContext?.naming = true
            projectMenu.searchPrompt = ProjectChoice.namePrompt
            showProjects()
            return
        }
        close()
        let model = context.model, paths = context.tasks.map(\.path)
        switch choice {
        case .project(let progress, let isCurrent):
            if !isCurrent { Task { await model.setProject(progress.project, of: paths) } }
        case .loose(let isCurrent):
            if !isCurrent { Task { await model.setProject(nil, of: paths) } }
        case .new(let name, _):
            Task { await model.newProject(named: name, linking: paths) }
        }
    }
}

/// Where a chip is on screen, for its picker to open under it.
final class ScreenAnchor {
    fileprivate weak var view: NSView?

    var window: NSWindow? { view?.window }

    /// The view's frame in screen coordinates.
    var rect: CGRect {
        guard let view, let window = view.window else { return .zero }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

/// Puts its view in a `ScreenAnchor`. Clicks pass through it.
struct ScreenAnchorReader: NSViewRepresentable {
    let anchor: ScreenAnchor

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }

    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A row of the status menu.
struct StatusChoice: PopupMenuItem {
    /// The order the menu lists them in.
    static let order: [Status] = [.notStarted, .doing, .blocked, .done]

    let status: Status
    let isCurrent: Bool

    var title: String { status.rawValue }
    var accessibilityValue: String { isCurrent ? "Current" : status == .done ? "Sets completedDate" : "" }
}

/// The status's checkbox, its name, and a tick on the current one. Done says it also sets completedDate.
private struct StatusChoiceRow: View {
    let choice: StatusChoice
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        let (marker, tint) = StatusCheckbox.box(for: choice.status, theme: theme)
        HStack(spacing: 10) {
            InlineCheckboxView(marker: marker, tint: tint, background: theme.bg)
                .frame(width: 16, height: 16)
            Text(choice.title)
                .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            if choice.status == .done, !choice.isCurrent {
                Text("sets completedDate")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.color(\.muted))
            }
            if choice.isCurrent { CurrentTick(theme: theme) }
        }
    }
}

/// A row of the project menu.
enum ProjectChoice: PopupMenuItem {
    case project(ProjectProgress, isCurrent: Bool)
    /// Takes the task out of its project.
    case loose(isCurrent: Bool)
    /// Creates a project called `name` at `path` and links the task to it; with no name, asks for one.
    case new(name: String, path: String)

    static let findPrompt = "Find a project"
    static let namePrompt = "Name the new project"

    var title: String {
        switch self {
        case .project(let progress, _): progress.project.title
        case .loose: "No project"
        case .new(let name, _): name.isEmpty ? "New project…" : "New project “\(name)”"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .project(let progress, let isCurrent): (isCurrent ? "Current, " : "") + "\(progress.open) open"
        case .loose(let isCurrent): (isCurrent ? "Current, " : "") + "loose task"
        case .new(_, let path): path
        }
    }

    var isCurrent: Bool {
        switch self {
        case .project(_, let isCurrent), .loose(let isCurrent): isCurrent
        case .new: false
        }
    }

    /// The menu for what's typed in its search field, and the row to highlight. It lists the active projects,
    /// and the task's own project when that isn't active, whose titles contain the text; then No project (until
    /// something's typed) and New project. While naming a new project, New project is the only row. The current
    /// row is highlighted, or the first when the text doesn't match it.
    static func menu(projects: [ProjectProgress], current: ProjectProgress?, isLoose: Bool, query: String,
                     naming: Bool, existing: Set<String>) -> (sections: [PopupMenuSection<ProjectChoice>], highlight: Int?) {
        let name = query.trimmingCharacters(in: .whitespaces)
        let path = name.isEmpty ? "" : "\(Vault.projectFolder)/\(FileNaming.filename(for: name, existing: existing))"
        let new = ProjectChoice.new(name: name, path: path)
        if naming { return ([PopupMenuSection(items: [new])], 0) }

        var listed = projects
        if let current, !listed.contains(where: { $0.project.path == current.project.path }) {
            listed.append(current)
            listed.sort { a, b in
                let order = a.project.title.localizedStandardCompare(b.project.title)
                return order == .orderedSame ? a.project.path < b.project.path : order == .orderedAscending
            }
        }
        let rows = listed.filter { name.isEmpty || $0.project.title.localizedStandardContains(name) }
            .map { ProjectChoice.project($0, isCurrent: $0.project.path == current?.project.path) }
        let others = (name.isEmpty ? [ProjectChoice.loose(isCurrent: isLoose)] : []) + [new]
        let currentRow = (rows + others).firstIndex(where: \.isCurrent)
        return ([PopupMenuSection(label: "Projects", items: rows), PopupMenuSection(items: others)],
                name.isEmpty ? currentRow : currentRow ?? 0)
    }
}

/// A project's ring, title and open tasks; No project; or New project with the file it would make.
private struct ProjectChoiceRow: View {
    let choice: ProjectChoice
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 16)
            Text(choice.title)
                .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            switch choice {
            case .project(let progress, let isCurrent):
                if isCurrent { CurrentTick(theme: theme) }
                Text("\(progress.open)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.color(\.muted))
                    .frame(minWidth: 14, alignment: .trailing)
            case .loose(let isCurrent):
                if isCurrent { CurrentTick(theme: theme) }
                Text("Loose task")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.color(\.muted))
            case .new(_, let path):
                if !path.isEmpty {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.color(\.muted))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder private var icon: some View {
        switch choice {
        case .project(let progress, _):
            ProgressRing(fraction: progress.fraction).foregroundStyle(theme.color(\.accent))
        case .loose:
            Image(systemName: "tray").font(.system(size: 12)).foregroundStyle(theme.color(\.muted))
        case .new:
            Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(theme.color(\.muted))
        }
    }
}

/// The tick on a menu's current row.
private struct CurrentTick: View {
    let theme: Theme

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.color(\.accent))
    }
}
