// The iPhone's navigation: the five tabs, each tab's pushed screens, the sheet on top, the rows picked by swiping,
// and the haptic each action plays. Nothing here is iOS-only, so the tests run with the Mac's.
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
    /// Settings, scrolled to a section.
    case settings(SettingsSection)
    case trash
}

enum SettingsSection: String, Hashable, CaseIterable {
    case vault, themes, editor, haptics
}

/// A picker over everything: a due date or deadline, or a project, for one or more files.
enum PhoneSheet: Identifiable {
    case date(AgendaEntry.Kind, paths: [String])
    case project(paths: [String])

    var id: String {
        switch self {
        case let .date(kind, paths): "\(kind)\(paths)"
        case let .project(paths): "project\(paths)"
        }
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

    func stack(_ tab: PhoneTab) -> Binding<[PhoneRoute]> {
        Binding { self.stacks[tab] ?? [] } set: { self.stacks[tab] = $0 }
    }

    // MARK: Picking

    func startPicking(_ path: String? = nil) {
        isPicking = true
        picked = path.map { [$0] } ?? []
        if path != nil { play(.pick) }
    }

    func endPicking() {
        isPicking = false
        picked = []
    }

    /// Picks or unpicks a row; unpicking the last one ends picking.
    func togglePicked(_ path: String) {
        if let i = picked.firstIndex(of: path) {
            picked.remove(at: i)
            if picked.isEmpty { isPicking = false }
        } else {
            picked.append(path)
        }
        play(.pick)
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
        picked = pickable
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
