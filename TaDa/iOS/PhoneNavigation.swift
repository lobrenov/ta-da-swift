// The iPhone's navigation: the five tabs, each tab's pushed screens, the sheet on top, the rows picked by swiping,
// the rows the move and area sheets list, and the haptic each action plays. Nothing here is iOS-only, so the tests
// run with the Mac's.
import SwiftUI
import TaDaCore

enum PhoneTab: Hashable {
    case today, upcoming, loose, projects, other
}

/// A screen pushed onto a tab's stack.
enum PhoneRoute: Hashable {
    /// A task's or project's file.
    case file(String)
    /// A project's tasks.
    case project(String)
    /// An area's projects and tasks.
    case area(String)
    /// Settings, scrolled to a section.
    case settings(SettingsSection)
    case trash

    /// The file the screen shows, if it shows one.
    var path: String? {
        switch self {
        case let .file(path), let .project(path), let .area(path): path
        case .settings, .trash: nil
        }
    }
}

enum SettingsSection: String, Hashable, CaseIterable {
    case vault, themes, editor, haptics
}

/// A picker over everything: a due date or deadline for one or more files, a project or area for tasks, or an area
/// for projects.
enum PhoneSheet: Identifiable {
    case date(AgendaEntry.Kind, paths: [String])
    case move(paths: [String])
    case area(paths: [String])

    var id: String {
        switch self {
        case let .date(kind, paths): "\(kind)\(paths)"
        case let .move(paths): "move\(paths)"
        case let .area(paths): "area\(paths)"
        }
    }
}

/// A row of the move sheet (for tasks) or the area sheet (for projects).
enum PhoneMoveRow: Hashable, Identifiable {
    /// Takes the files out of their project or area: Loose tasks, or No area.
    case none
    case project(ProjectProgress)
    case area(Item)
    /// Creates the area the files all name that has no file.
    case createArea(String)

    var id: String {
        switch self {
        case .none: "none"
        case let .project(progress): progress.project.path
        case let .area(area): area.path
        case let .createArea(name): "create \(name)"
        }
    }

    /// The move sheet for `tasks` and what's typed in its search: Create Area when the tasks all name the same area
    /// that has no file; Loose tasks and the active projects without an area; then each area with its active projects.
    /// The tasks' own project is listed when it's done. Typing keeps the rows whose titles contain the text and drops
    /// Create Area and Loose tasks.
    static func moveGroups(index: VaultIndex, tasks: [Item], query: String) -> [[PhoneMoveRow]] {
        let name = query.trimmingCharacters(in: .whitespaces)
        func matches(_ title: String) -> Bool { name.isEmpty || title.localizedStandardContains(name) }
        let current = currentParent(index: index, files: tasks) ?? nil
        func projects(_ projects: [ProjectProgress], in area: Item?) -> [PhoneMoveRow] {
            var projects = projects
            if let current, current.properties.kind == .project, current.properties.status == .done,
               index.area(of: current)?.path == area?.path {
                projects = (projects + [index.progress(of: current)]).sorted { VaultIndex.byTitle($0.project, $1.project) }
            }
            return projects.filter { matches($0.project.title) }.map { .project($0) }
        }
        var groups: [[PhoneMoveRow]] = []
        if name.isEmpty, let area = unresolvedArea(index: index, files: tasks) { groups.append([.createArea(area)]) }
        groups.append((name.isEmpty ? [.none] : []) + projects(index.looseProjects(), in: nil))
        for entry in index.areaProjects() {
            groups.append((matches(entry.area.title) ? [.area(entry.area)] : []) + projects(entry.projects, in: entry.area))
        }
        return groups.filter { !$0.isEmpty }
    }

    /// The area sheet for `projects`: Create Area when they all name the same area that has no file; the areas whose
    /// titles contain what's typed; then No area until something's typed.
    static func areaGroups(index: VaultIndex, projects: [Item], query: String) -> [[PhoneMoveRow]] {
        let name = query.trimmingCharacters(in: .whitespaces)
        var groups: [[PhoneMoveRow]] = []
        if name.isEmpty, let area = unresolvedArea(index: index, files: projects) { groups.append([.createArea(area)]) }
        groups.append(index.areas.sorted(by: VaultIndex.byTitle)
            .filter { name.isEmpty || $0.title.localizedStandardContains(name) }.map { .area($0) })
        if name.isEmpty { groups.append([.none]) }
        return groups.filter { !$0.isEmpty }
    }

    /// The parent `files` share: `.some(parent)`, `.some(nil)` when none of them names a project or area, or nil when
    /// they differ or name one that has no file.
    static func currentParent(index: VaultIndex, files: [Item]) -> Item?? {
        let parents = Set(files.map { index.parent(of: $0)?.path })
        guard parents.count == 1, let path = parents.first else { return nil }
        if let path { return .some(index[path]) }
        return files.allSatisfy { $0.properties.project == nil && $0.properties.area == nil } ? .some(nil) : nil
    }

    /// The area title every one of `files` names when no area has it.
    private static func unresolvedArea(index: VaultIndex, files: [Item]) -> String? {
        let names = Set(files.map { file in file.properties.area.flatMap { index.parent(of: file) == nil ? $0.title : nil } })
        return names.count == 1 ? names.first ?? nil : nil
    }
}

/// What the device plays for an action (the canvas's haptics note).
enum Haptic: Equatable {
    /// A task completed.
    case complete
    /// A subtask checked or unchecked.
    case subtask
    /// The floating + pressed, or a swipe passing its threshold.
    case press
    /// A row picked, or a status, date or project picked.
    case pick
    /// Files moved to the trash.
    case trash
    /// Empty Trash confirmed.
    case emptyTrash

    var feedback: SensoryFeedback {
        switch self {
        case .complete: .success
        case .subtask: .impact(weight: .light)
        case .press: .impact(weight: .medium)
        case .pick: .selection
        case .trash: .impact(flexibility: .rigid)
        case .emptyTrash: .warning
        }
    }
}

@Observable final class PhoneNavigation {
    var tab = PhoneTab.today
    /// Each tab's pushed screens, so a tab keeps its place while another is shown.
    var stacks: [PhoneTab: [PhoneRoute]] = [:]
    var sheet: PhoneSheet?

    /// Rows picked by swiping or Select, in the order they were picked. Picking hides the tab bar for the action bar.
    var picked: [String] = []
    var isPicking = false
    /// The rows of the list being picked from, top to bottom, for Select All.
    var pickable: [String] = []

    /// The last haptic asked for; each new one plays once.
    private(set) var haptic: (Haptic, Int)?
    private var hapticCount = 0

    func play(_ haptic: Haptic) {
        hapticCount += 1
        self.haptic = (haptic, hapticCount)
    }

    func push(_ route: PhoneRoute) {
        stacks[tab, default: []].append(route)
    }

    func pop() {
        _ = stacks[tab]?.popLast()
    }

    /// Points every tab's screens for `route` at `replacement`, as after a rename.
    func replace(_ route: PhoneRoute, with replacement: PhoneRoute) {
        stacks = stacks.mapValues { routes in routes.map { $0 == route ? replacement : $0 } }
    }

    /// Takes the screens for files that are gone out of every tab, as after a delete.
    func dropScreens(where isGone: (String) -> Bool) {
        stacks = stacks.mapValues { routes in routes.filter { $0.path.map { !isGone($0) } ?? true } }
    }

    func stack(_ tab: PhoneTab) -> Binding<[PhoneRoute]> {
        Binding { self.stacks[tab] ?? [] } set: { self.stacks[tab] = $0 }
    }

    // MARK: Picking

    /// The spring every picking change shares: a swiped row's return, its highlight, the circles and the bars.
    static let pickSpring = Animation.spring(duration: 0.25, bounce: 0.3)

    func startPicking(_ path: String? = nil) {
        withAnimation(Self.pickSpring) {
            isPicking = true
            picked = path.map { [$0] } ?? []
        }
        if path != nil { play(.pick) }
    }

    func endPicking() {
        withAnimation(Self.pickSpring) {
            isPicking = false
            picked = []
        }
    }

    /// Picks or unpicks a row; unpicking the last one ends picking.
    func togglePicked(_ path: String) {
        withAnimation(Self.pickSpring) {
            if let i = picked.firstIndex(of: path) {
                picked.remove(at: i)
                if picked.isEmpty { isPicking = false }
            } else {
                picked.append(path)
            }
        }
        play(.pick)
    }

    /// Picks or unpicks a row, starting picking if it hasn't started.
    func pick(_ path: String) {
        isPicking ? togglePicked(path) : startPicking(path)
    }

    /// Sets the rows of the list on screen; picked rows it no longer shows are unpicked, and picking ends when that
    /// leaves none.
    func setPickable(_ paths: [String]) {
        pickable = paths
        let shown = Set(paths)
        let kept = picked.filter(shown.contains)
        guard kept.count != picked.count else { return }
        picked = kept
        if kept.isEmpty { endPicking() }
    }

    func pickAll() {
        withAnimation(Self.pickSpring) { picked = pickable }
        play(.pick)
    }
}

extension View {
    /// Plays the navigation's haptics, unless Settings ▸ Haptics is off.
    func phoneHaptics(_ nav: PhoneNavigation, enabled: Bool) -> some View {
        sensoryFeedback(trigger: nav.haptic?.1) { _, _ in
            enabled ? nav.haptic?.0.feedback : nil
        }
    }
}

extension AgendaEntry.Kind {
    /// What the date sheet writes: the dates of the kinds the user changed, due date first; nil clears one.
    static func changes(_ changed: Set<Self>, in days: [Self: LocalDate?]) -> [(Self, LocalDate?)] {
        [Self.due, .deadline].filter(changed.contains).map { ($0, days[$0] ?? nil) }
    }
}
