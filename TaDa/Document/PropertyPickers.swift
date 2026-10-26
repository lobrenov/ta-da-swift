// The pickers under the property chips: status, a task's project or area, a project's area and tagMenu in popup
// menus, and dates in a calendar. One is open at a time; its chip keeps an accent ring until it closes.
#if os(macOS)
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
    @ObservationIgnored private let areaMenu = PopupMenu(style: .full(confirm: "Set", maxListHeight: 312), takesKeys: true,
                                                         searchPrompt: AreaChoice.findPrompt, row: AreaChoiceRow.init)
    @ObservationIgnored private let tagMenu = PopupMenu(style: .full(confirm: "Toggle", maxListHeight: 312), takesKeys: true,
                                                        searchPrompt: TagChoice.prompt, row: TagChoiceRow.init)
    @ObservationIgnored private let calendar = CalendarPicker()
    /// The last repeat write, which the next waits for so the writes land in the order they were made.
    @ObservationIgnored private var repeatWrite: Task<Void, Never>?
    /// The open picker's chip, in screen coordinates.
    @ObservationIgnored private var anchor = CGRect.zero
    /// The chip whose picker a mouse-down on it closed, and when, so the click's own action doesn't reopen it.
    @ObservationIgnored private var closedByClick: (target: Target, time: TimeInterval)?
    /// What the project or area menu needs to refresh as its search changes.
    @ObservationIgnored private var projectMenuContext: ProjectMenuContext?
    /// What tagMenu needs to refresh as its search changes and after each pick.
    @ObservationIgnored private var tagMenuContext: (path: String, model: AppModel, anchor: CGRect, window: NSWindow, gap: CGFloat)?
    /// The row the file menu's Move, Schedule or Set Deadline… came from, ringed while the picker is open.
    @ObservationIgnored private var ringed: (model: AppModel, path: String)?

    private struct ProjectMenuContext {
        /// Tasks for the project menu; projects for the area menu.
        let tasks: [Item]
        let model: AppModel
        let anchor: CGRect
        let gap: CGFloat
        let window: NSWindow
        /// New project… or New Area… was picked with nothing typed, so the search field takes the name.
        var naming = false
    }

    private init() {
        statusMenu.onDismiss = { [weak self] in self?.dismiss() }
        projectMenu.onDismiss = { [weak self] in self?.dismiss() }
        areaMenu.onDismiss = { [weak self] in self?.dismiss() }
        tagMenu.onDismiss = { [weak self] in self?.dismiss() }
        calendar.onDismiss = { [weak self] in self?.dismiss() }
        projectMenu.onSearch = { [weak self] _ in self?.showProjects() }
        areaMenu.onSearch = { [weak self] _ in self?.showAreas() }
        tagMenu.onSearch = { [weak self] _ in self?.showTags() }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PropertyPicker.shared.close() }
        }
    }

    func isOpen(_ path: String, _ key: String) -> Bool { open == Target(path: path, key: key) }

    /// Opens the status menu under `anchor`, or closes it when it's open.
    func pickStatus(of item: Item, model: AppModel, anchor: ScreenAnchor) {
        guard let window = anchor.window, toggle(item.path, "status", anchor: anchor.rect) else { return }
        let current = item.properties.status
        let (repeating, move) = RepeatWording.statusContext(of: [item], index: model.index, today: model.today)
        let choices = Status.choices(for: item.properties.kind).map {
            StatusChoice(status: $0, isCurrent: $0 == current, repeating: repeating,
                         note: repeating && $0.isClosed && $0 != current ? move.map { RepeatWording.note($0, today: model.today) } : nil)
        }
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

    /// Opens the area menu for `projects` under `anchor`, or closes it when it's open.
    func pickArea(of projects: [Item], model: AppModel, anchor: ScreenAnchor, gap: CGFloat = 6) {
        guard let window = anchor.window else { return }
        pickArea(of: projects, model: model, below: anchor.rect, gap: gap, in: window)
    }

    /// Opens the area menu for `projects` below `rect` (screen coordinates), or closes it when it's open. `ringed`
    /// is a row to ring while it's open.
    func pickArea(of projects: [Item], model: AppModel, below rect: CGRect, gap: CGFloat = 6, in window: NSWindow,
                  ringing ringed: String? = nil) {
        guard let first = projects.first, toggle(first.path, "area", anchor: rect) else { return }
        projectMenuContext = ProjectMenuContext(tasks: projects, model: model, anchor: rect, gap: gap, window: window)
        ring(ringed, model: model)
        areaMenu.query = ""
        areaMenu.searchPrompt = AreaChoice.findPrompt
        showAreas()
    }

    /// Opens tagMenu for `item` under `anchor`, or closes it when it's open. A pick adds or removes the tag and the menu
    /// stays open.
    func pickTags(of item: Item, model: AppModel, anchor: ScreenAnchor, gap: CGFloat = 6) {
        guard let window = anchor.window else { return }
        pickTags(of: item, model: model, below: anchor.rect, gap: gap, in: window)
    }

    /// Opens tagMenu for `item` below `rect` (screen coordinates), or closes it when it's open. `ringed` is a row to
    /// ring while it's open.
    func pickTags(of item: Item, model: AppModel, below rect: CGRect, gap: CGFloat = 6, in window: NSWindow,
                  ringing ringed: String? = nil) {
        guard toggle(item.path, "tags", anchor: rect) else { return }
        tagMenuContext = (item.path, model, rect, window, gap)
        ring(ringed, model: model)
        tagMenu.query = ""
        showTags()
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
        // A task's due date menu has the Repeat section; several files show the rule only when they all share it.
        var repeating: CalendarPickerModel.Repeating?
        if kind == .due, items.allSatisfy({ $0.properties.kind == .task }) {
            repeating = CalendarPickerModel.Repeating(items: items, index: model.index) { [weak self] rule, closing in
                if closing { self?.close() }
                let previous = self?.repeatWrite
                let write = Task {
                    await previous?.value
                    await model.setRepeat(rule, of: paths)
                }
                self?.repeatWrite = write
            }
        }
        calendar.show(kind, selected: current, other: agreed(kind == .due ? \.deadline : \.dueDate), today: model.today,
                      theme: model.theme, repeating: repeating, below: rect, gap: gap, in: window) { [weak self] date in
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
        areaMenu.hide()
        tagMenu.hide()
        calendar.hide()
        if let ringed, ringed.model.menuTarget == ringed.path {
            ringed.model.menuTarget = nil
        }
        ringed = nil
        projectMenuContext = nil
        tagMenuContext = nil
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
        guard open?.key == "project", let context = projectMenuContext else { return }
        let index = context.model.index
        let existing = Set(index.projects.map { String($0.path.split(separator: "/").last ?? "") })
        let menu = ProjectChoice.menu(index: index, tasks: context.tasks, query: projectMenu.query,
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
            if !isCurrent { Task { await model.setParent(progress.project, of: paths) } }
        case .area(let area, let isCurrent):
            if !isCurrent { Task { await model.setParent(area, of: paths) } }
        case .loose(let isCurrent):
            if !isCurrent { Task { await model.setParent(nil, of: paths) } }
        case .createArea(let name):
            Task { await model.newArea(named: name) }
        case .new(let name, _):
            Task { await model.newProject(named: name, linking: paths) }
        }
    }

    /// Shows tagMenu for the file as it is now, highlighting the tag at `keeping` when it has a row.
    private func showTags(keeping: String? = nil) {
        guard open?.key == "tags", let context = tagMenuContext, let item = context.model.item(at: context.path) else { return }
        let menu = TagChoice.menu(item: item, tree: context.model.tagTree, query: tagMenu.query, keeping: keeping,
                                  ownLabel: context.path == AppModel.quickEntryDraftPath ? "Added" : "In this file")
        tagMenu.show(menu.sections, highlight: menu.highlight, theme: context.model.theme, below: context.anchor,
                     inset: 0, gap: context.gap, in: context.window) { [weak self] choice in
            self?.pickTag(choice)
        }
    }

    private func pickTag(_ choice: TagChoice) {
        guard let context = tagMenuContext else { return }
        let model = context.model, path = context.path
        switch choice {
        case .tag(_, _, _, true):
            return
        case .tag(let tag, _, true, _):
            Task { await model.removeTag(tag, from: path); showTags(keeping: tag.path) }
        case .tag(let tag, _, false, _), .create(let tag):
            tagMenu.query = ""
            Task { await model.addTag(tag, to: path); showTags(keeping: tag.path) }
        }
    }

    private func showAreas() {
        guard open?.key == "area", let context = projectMenuContext else { return }
        let index = context.model.index
        let existing = Set(index.areas.map { String($0.path.split(separator: "/").last ?? "") })
        let menu = AreaChoice.menu(index: index, projects: context.tasks, query: areaMenu.query, naming: context.naming,
                                   existing: existing)
        areaMenu.show(menu.sections, highlight: menu.highlight, theme: context.model.theme, below: context.anchor,
                      inset: 0, gap: context.gap, in: context.window) { [weak self] choice in
            self?.pickArea(choice)
        }
    }

    private func pickArea(_ choice: AreaChoice) {
        guard let context = projectMenuContext else { return }
        if case .new(let name, _) = choice, name.isEmpty {
            projectMenuContext?.naming = true
            areaMenu.searchPrompt = AreaChoice.namePrompt
            showAreas()
            return
        }
        close()
        let model = context.model, paths = context.tasks.map(\.path)
        switch choice {
        case .area(let area, _, let isCurrent):
            if !isCurrent { Task { await model.setParent(area, of: paths) } }
        case .none(let isCurrent):
            if !isCurrent { Task { await model.setParent(nil, of: paths) } }
        case .create(let name):
            Task { await model.newArea(named: name) }
        case .new(let name, _):
            Task { await model.newArea(named: name, filing: paths) }
        }
    }
}

/// Where a chip is on screen, for its picker to open under it.
final class ScreenAnchor {
    /// The reader views, held weakly: while SwiftUI replaces one there are two, and either can update last.
    private let views = NSHashTable<NSView>.weakObjects()

    fileprivate func add(_ view: NSView) { views.add(view) }

    /// The reader view in a window.
    private var view: NSView? { views.allObjects.first { $0.window != nil } }

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
        anchor.add(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchor.add(view) }

    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A row of the status menu.
struct StatusChoice: PopupMenuItem {
    let status: Status
    let isCurrent: Bool
    /// Whether the file is a repeating task, whose Cancelled reads "Skip this time".
    var repeating = false
    /// What Done and Skip do to a repeating task ("moves to Mon 9 Nov"), instead of "sets completedDate".
    var note: String?

    var title: String { RepeatWording.title(of: status, repeating: repeating) }
    var accessibilityValue: String { isCurrent ? "Current" : status.isClosed ? note?.capitalizedFirst ?? "Sets completedDate" : "" }
}

/// The status's checkbox, its name, and a tick on the current one. Done and Cancelled say they also set completedDate,
/// or on a repeating task where it moves.
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
            if choice.status.isClosed, !choice.isCurrent {
                Text(choice.note ?? "sets completedDate")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.color(\.muted))
            }
            if choice.isCurrent { CurrentTick(theme: theme) }
        }
    }
}

/// A row of the move menu.
enum ProjectChoice: PopupMenuItem {
    case project(ProjectProgress, isCurrent: Bool)
    case area(Item, isCurrent: Bool)
    /// Takes the task out of its project or area.
    case loose(isCurrent: Bool)
    /// Creates the area the tasks name that has no file.
    case createArea(String)
    /// Creates a project called `name` at `path` and files the task in it; with no name, asks for one.
    case new(name: String, path: String)

    static let findPrompt = "Move to project or area"
    static let namePrompt = "Name the new project"

    var title: String {
        switch self {
        case .project(let progress, _): progress.project.title
        case .area(let area, _): area.title
        case .loose: "Loose tasks"
        case .createArea(let name): "Create Area “\(name)”"
        case .new(let name, _): name.isEmpty ? "New project…" : "New project “\(name)”"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .project(let progress, let isCurrent): (isCurrent ? "Current, " : "") + "\(progress.open) open"
        case .area(_, let isCurrent): (isCurrent ? "Current, " : "") + "area"
        case .loose(let isCurrent): isCurrent ? "Current" : ""
        case .createArea(let name): "\(Vault.areaFolder)/\(FileNaming.sanitise(name)).md"
        case .new(_, let path): path
        }
    }

    var isCurrent: Bool {
        switch self {
        case .project(_, let isCurrent), .area(_, let isCurrent), .loose(let isCurrent): isCurrent
        case .createArea, .new: false
        }
    }

    /// The move menu for `tasks` and what's typed in its search field, and the row to highlight. Create Area first
    /// when the tasks all name the same area that has no file; Loose tasks; the active projects without an area; each
    /// area followed by its active projects; then New project. The tasks' own project is listed when it isn't active.
    /// Typing keeps the rows whose titles contain the text and drops Create Area and Loose tasks. While naming a new
    /// project, New project is the only row. The current row is highlighted, or the first when the text doesn't match it.
    static func menu(index: VaultIndex, tasks: [Item], query: String, naming: Bool, existing: Set<String>)
        -> (sections: [PopupMenuSection<ProjectChoice>], highlight: Int?) {
        let name = query.trimmingCharacters(in: .whitespaces)
        let path = name.isEmpty ? "" : "\(Vault.projectFolder)/\(FileNaming.filename(for: name, existing: existing))"
        let new = ProjectChoice.new(name: name, path: path)
        if naming { return ([PopupMenuSection(items: [new])], 0) }

        // Several tasks have a current parent, or are loose, only when they all agree.
        let parents = Set(tasks.map { index.parent(of: $0)?.path })
        let current = parents.count == 1 ? tasks.first.flatMap { index.parent(of: $0) } : nil
        let isLoose = tasks.allSatisfy { $0.properties.project == nil && $0.properties.area == nil }
        let unresolved = Set(tasks.map { task in
            task.properties.area.flatMap { index.parent(of: task) == nil ? $0.title : nil }
        })
        func matches(_ title: String) -> Bool { name.isEmpty || title.localizedStandardContains(name) }
        /// The project rows under `area` (nil for those without one), with the current project when it's done.
        func rows(_ projects: [ProjectProgress], in area: Item?) -> [ProjectChoice] {
            var projects = projects
            if let current, current.properties.kind == .project, current.properties.status.isClosed,
               index.area(of: current)?.path == area?.path {
                projects = (projects + [index.progress(of: current)]).sorted { VaultIndex.byTitle($0.project, $1.project) }
            }
            return projects.filter { matches($0.project.title) }
                .map { .project($0, isCurrent: $0.project.path == current?.path) }
        }

        var sections: [PopupMenuSection<ProjectChoice>] = []
        if name.isEmpty, unresolved.count == 1, let area = unresolved.first ?? nil {
            sections.append(PopupMenuSection(items: [.createArea(area)]))
        }
        if name.isEmpty { sections.append(PopupMenuSection(items: [.loose(isCurrent: isLoose)])) }
        sections.append(PopupMenuSection(items: rows(index.looseProjects(), in: nil)))
        for entry in index.areaProjects() {
            let area: [ProjectChoice] = matches(entry.area.title) ? [.area(entry.area, isCurrent: entry.area.path == current?.path)] : []
            sections.append(PopupMenuSection(items: area + rows(entry.projects, in: entry.area)))
        }
        sections.append(PopupMenuSection(items: [new]))
        sections = sections.filter { !$0.items.isEmpty }
        let items = sections.flatMap(\.items)
        let currentRow = items.firstIndex(where: \.isCurrent)
        return (sections, name.isEmpty ? currentRow : currentRow ?? 0)
    }
}

/// A project's ring, title and open tasks; an area's cube and title; Loose tasks; Create Area; or New project with
/// the file it would make.
private struct ProjectChoiceRow: View {
    let choice: ProjectChoice
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 16)
            Text(choice.title)
                .fontWeight(isArea ? .semibold : .regular)
                .foregroundStyle(theme.color(isHighlighted || isArea ? \.strong : \.fg))
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
            case .area(_, let isCurrent), .loose(let isCurrent):
                if isCurrent { CurrentTick(theme: theme) }
            case .createArea:
                EmptyView()
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

    private var isArea: Bool { if case .area = choice { true } else { false } }

    @ViewBuilder private var icon: some View {
        switch choice {
        case .project(let progress, _):
            ProgressRing(progress).foregroundStyle(theme.color(\.accent))
        case .area, .createArea:
            AreaIcon().environment(\.theme, theme)
        case .loose:
            Image(systemName: "tray").font(.system(size: 12)).foregroundStyle(theme.color(\.accent))
        case .new:
            Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(theme.color(\.muted))
        }
    }
}

/// A row of a project's area menu.
enum AreaChoice: PopupMenuItem {
    case area(Item, projects: Int, isCurrent: Bool)
    /// Takes the project out of its area.
    case none(isCurrent: Bool)
    /// Creates the area the projects name that has no file.
    case create(String)
    /// Creates an area called `name` at `path` and files the project in it; with no name, asks for one.
    case new(name: String, path: String)

    static let findPrompt = "Search areas"
    static let namePrompt = "Name the new area"

    var title: String {
        switch self {
        case .area(let area, _, _): area.title
        case .none: "No area"
        case .create(let name): "Create Area “\(name)”"
        case .new(let name, _): name.isEmpty ? "New Area…" : "New Area “\(name)”"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .area(_, let projects, let isCurrent): (isCurrent ? "Current, " : "") + (projects == 1 ? "1 project" : "\(projects) projects")
        case .none(let isCurrent): isCurrent ? "Current" : ""
        case .create(let name): "\(Vault.areaFolder)/\(FileNaming.sanitise(name)).md"
        case .new(_, let path): path
        }
    }

    var isCurrent: Bool {
        switch self {
        case .area(_, _, let isCurrent), .none(let isCurrent): isCurrent
        case .create, .new: false
        }
    }

    /// The area menu for `projects`: Create Area when they all name the same area that has no file, the areas whose
    /// titles contain what's typed, then No area (until something's typed) and New Area. While naming a new area,
    /// New Area is the only row. The current row is highlighted, or the first when the text doesn't match it.
    static func menu(index: VaultIndex, projects: [Item], query: String, naming: Bool, existing: Set<String>)
        -> (sections: [PopupMenuSection<AreaChoice>], highlight: Int?) {
        let name = query.trimmingCharacters(in: .whitespaces)
        let path = name.isEmpty ? "" : "\(Vault.areaFolder)/\(FileNaming.filename(for: name, existing: existing))"
        let new = AreaChoice.new(name: name, path: path)
        if naming { return ([PopupMenuSection(items: [new])], 0) }

        let areas = Set(projects.map { index.area(of: $0)?.path })
        let current = areas.count == 1 ? areas.first ?? nil : nil
        let unresolved = Set(projects.map { project in project.properties.area.flatMap { index.area(of: project) == nil ? $0.title : nil } })
        let rows = index.areaProjects().filter { name.isEmpty || $0.area.title.localizedStandardContains(name) }
            .map { AreaChoice.area($0.area, projects: index.projects(in: $0.area).count, isCurrent: $0.area.path == current) }
        let isNone = projects.allSatisfy { $0.properties.area == nil }
        var sections: [PopupMenuSection<AreaChoice>] = []
        if name.isEmpty, unresolved.count == 1, let area = unresolved.first ?? nil {
            sections.append(PopupMenuSection(items: [.create(area)]))
        }
        sections.append(PopupMenuSection(label: "Areas", items: rows))
        sections.append(PopupMenuSection(items: (name.isEmpty ? [AreaChoice.none(isCurrent: isNone)] : []) + [new]))
        sections = sections.filter { !$0.items.isEmpty }
        let currentRow = sections.flatMap(\.items).firstIndex(where: \.isCurrent)
        return (sections, name.isEmpty ? currentRow : currentRow ?? 0)
    }
}

/// An area's cube, title and project count; No area; Create Area; or New Area with the file it would make.
private struct AreaChoiceRow: View {
    let choice: AreaChoice
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
            case .area(_, let projects, let isCurrent):
                if projects > 0 {
                    Text("\(projects)")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(theme.color(\.muted))
                }
                if isCurrent { CurrentTick(theme: theme) }
            case .none(let isCurrent):
                if isCurrent { CurrentTick(theme: theme) }
            case .create:
                EmptyView()
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
        case .area, .create:
            AreaIcon().environment(\.theme, theme)
        case .none:
            Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(theme.color(\.muted))
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
#endif
