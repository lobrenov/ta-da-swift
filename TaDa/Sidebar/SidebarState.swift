// Whether the window's sidebar is docked, hidden or floating over the workspace, as the window narrows and widens and
// as the sidebar is toggled, swiped and picked from. Changes to the split view's columns come back for the view to
// slide to.
#if os(macOS)
import SwiftUI

struct SidebarState {
    /// The split view's columns.
    var columns = NavigationSplitViewVisibility.all
    /// The window is too narrow for the sidebar beside the workspace.
    private(set) var isNarrow = false
    /// The sidebar hid because the window got narrow; it comes back when there's room.
    private(set) var autoHidden = false
    var floats = false {
        didSet { if !floats { floatsForSearch = false } }
    }
    /// The sidebar floats for Search Files, with its search field taking the keyboard.
    private(set) var floatsForSearch = false
    /// Our sidebar button in place of the split view's, once the sidebar has slid away in a narrow window.
    private(set) var usesOwnToggle = false

    /// The window became `narrow` or not: the sidebar hides when it's narrow, and comes back when there's room if it
    /// hid for that. Gives the columns to slide to.
    mutating func fit(narrow: Bool) -> NavigationSplitViewVisibility? {
        guard narrow != isNarrow else { return nil }
        isNarrow = narrow
        if narrow {
            guard columns != .detailOnly else {
                usesOwnToggle = true
                return nil
            }
            autoHidden = true
            return .detailOnly
        }
        floats = false
        usesOwnToggle = false
        guard autoHidden else { return nil }
        autoHidden = false
        return .all
    }

    /// The sidebar has slid to its columns.
    mutating func slid() {
        if isNarrow { usesOwnToggle = true }
    }

    /// The sidebar button or Toggle Sidebar: floats or hides the sidebar in a narrow window or while it floats,
    /// otherwise shows or hides the docked one. Gives the columns to slide to.
    mutating func toggle() -> NavigationSplitViewVisibility? {
        if isNarrow || floats {
            floats.toggle()
            return nil
        }
        return dock(columns == .detailOnly)
    }

    /// The columns changed: once the split view shows its sidebar, the floating one hides, and in a narrow window the
    /// docked one slides away again. Gives the columns to slide to.
    mutating func columnsChanged() -> NavigationSplitViewVisibility? {
        guard columns != .detailOnly else { return nil }
        floats = false
        guard isNarrow else { return nil }
        autoHidden = true
        return .detailOnly
    }

    /// Search Files: the hidden sidebar floats, with its search field taking the keyboard.
    mutating func searchRequested() {
        guard columns == .detailOnly, !floats else { return }
        floats = true
        floatsForSearch = true
    }

    /// Whether a swipe, or the mouse's back and forward buttons, with the pointer `overSidebar` switch its Projects |
    /// Tags view: over the docked sidebar, or the floating one for the buttons.
    func switchesViews(overSidebar: Bool, swiping: Bool) -> Bool {
        overSidebar && (swiping ? columns != .detailOnly && !floats : columns != .detailOnly || floats)
    }

    /// A swipe to the right floats the hidden sidebar, unless something under the pointer `scrollsLeft`; to the left,
    /// it hides the floating sidebar. Over the docked sidebar a swipe switches its view instead (`switchesViews`).
    mutating func swiped(_ direction: SidebarSwipe.Direction, scrollsLeft: () -> Bool) {
        switch direction {
        case .right:
            if columns == .detailOnly, !floats, !scrollsLeft() { floats = true }
        case .left:
            floats = false
        }
    }

    private mutating func dock(_ show: Bool) -> NavigationSplitViewVisibility {
        autoHidden = false
        return show ? .all : .detailOnly
    }
}
#endif
