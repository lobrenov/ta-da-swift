// The window's sidebar beside the workspace. When the window is too narrow for both, the sidebar hides, and the
// sidebar button (or View ▸ Toggle Sidebar) floats it over the workspace until a click elsewhere or a pick in it.
// While the sidebar is hidden, a two-finger swipe to the right floats it too; a swipe to the left hides a floating
// sidebar. Over the docked sidebar a swipe switches Projects (right) and Tags (left), as the mouse's back and forward
// buttons do over the docked or floating sidebar.
#if os(macOS)
import SwiftUI

struct SidebarSplitView: View {
    let model: AppModel
    @State private var state = SidebarState()
    @State private var sidebarWidth: CGFloat = 240
    @State private var anchor = ScreenAnchor()
    @State private var swipe = SidebarSwipe()
    @State private var swipeMonitor: Any?
    @State private var mouseButtonMonitor: Any?

    var body: some View {
        NavigationSplitView(columnVisibility: $state.columns) {
            SidebarView(model: model, takesSearchFocus: state.columns != .detailOnly)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                    if state.columns == .all { sidebarWidth = min(max($0, 200), 340) }
                }
                .toolbar(removing: state.usesOwnToggle ? .sidebarToggle : nil)
        } detail: {
            WorkspaceView(model: model)
                .toolbar {
                    if state.usesOwnToggle { ToolbarItem(placement: .navigation) { toggleButton } }
                }
        }
        .overlay(alignment: .leading) { floatingSidebar }
        .background(ScreenAnchorReader(anchor: anchor))
        .background(WindowReader { fit(width: $0.frame.width) })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { note in
            if let window = note.object as? NSWindow, window === anchor.window { fit(width: window.frame.width) }
        }
        .onAppear { watchSwipes() }
        .onDisappear { stopWatchingSwipes() }
        .onChange(of: state.columns) { slide(to: state.columnsChanged()) }
        .onChange(of: model.sidebarToggleRequest) { slide(to: state.toggle()) }
        .onChange(of: model.searchFocusRequest) { state.searchRequested() }
        .onChange(of: model.domain) { state.floats = false }
    }

    /// The sidebar button in a narrow window, where the split view's own would show the sidebar beside the workspace.
    /// It takes the split view's place beside the window's buttons.
    private var toggleButton: some View {
        Button { slide(to: state.toggle()) } label: { Label("Toggle Sidebar", systemImage: "sidebar.left") }
            .help(state.floats ? "Hide Sidebar" : "Show Sidebar")
    }

    /// The sidebar over the workspace, sliding in from the left, with a click anywhere else hiding it.
    private var floatingSidebar: some View {
        ZStack(alignment: .leading) {
            if state.floats {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { state.floats = false }
                    .accessibilityHidden(true)
                SidebarView(model: model, focusesSearch: state.floatsForSearch) { state.floats = false }
                    .frame(width: sidebarWidth)
                    .background { model.theme.color(\.side).ignoresSafeArea() }
                    .overlay(alignment: .trailing) { Hairline(axis: .vertical).ignoresSafeArea() }
                    .shadow(color: .black.opacity(0.18), radius: 16)
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.sidebarSlide, value: state.floats)
    }

    /// Hides the sidebar when the window is too narrow for it, as it opens or resizes, and shows it again when there's
    /// room.
    private func fit(width: CGFloat) {
        slide(to: state.fit(narrow: width < sidebarWidth + WorkspaceView.minWidth))
    }

    /// Slides the split view's sidebar in or out to `columns`, if there are any.
    private func slide(to columns: NavigationSplitViewVisibility?) {
        guard let columns else { return }
        withAnimation(.sidebarSlide) { state.columns = columns } completion: { state.slid() }
    }

    /// Two-finger swipes, for `SidebarState.swiped` or the sidebar's view, and the mouse's back (button 3) and forward
    /// (button 4) buttons over the sidebar.
    private func watchSwipes() {
        stopWatchingSwipes()
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated {
                guard let window = anchor.window, event.window === window,
                      let direction = swipe.track(event.phase, dx: SidebarSwipe.fingersDX(event), dy: event.scrollingDeltaY)
                else { return }
                if state.switchesViews(overSidebar: event.locationInWindow.x < sidebarWidth, swiping: true) {
                    model.sidebarMode = direction == .left ? model.sidebarMode.next : model.sidebarMode.previous
                } else {
                    state.swiped(direction) { SidebarSwipe.scrollsLeft(event) }
                }
            }
            return event
        }
        mouseButtonMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            let (button, x, eventWindow) = (event.buttonNumber, event.locationInWindow.x, event.window)
            let used = MainActor.assumeIsolated {
                guard let window = anchor.window, eventWindow === window, [3, 4].contains(button),
                      state.switchesViews(overSidebar: x < sidebarWidth, swiping: false) else { return false }
                model.sidebarMode = button == 3 ? model.sidebarMode.previous : model.sidebarMode.next
                return true
            }
            return used ? nil : event
        }
    }

    private func stopWatchingSwipes() {
        for monitor in [swipeMonitor, mouseButtonMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        swipeMonitor = nil
        mouseButtonMonitor = nil
    }
}

/// Hands over the window its view joins. Clicks pass through it.
private struct WindowReader: NSViewRepresentable {
    let joined: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { WindowView(joined: joined) }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class WindowView: NSView {
        let joined: (NSWindow) -> Void

        init(joined: @escaping (NSWindow) -> Void) {
            self.joined = joined
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            if let window { joined(window) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension Animation {
    /// The sidebar's slide, and the sidebar lists' sliding past each other.
    static let sidebarSlide = Animation.snappy(duration: 0.25)
}
#endif

extension AppModel.SidebarMode {
    /// Tasks, Tags, Notes: 0, 1, 2.
    var position: Int {
        switch self {
        case .projects: 0
        case .tags: 1
        case .notes: 2
        }
    }

    /// Tasks → Tags → Notes; Notes stays.
    var next: Self {
        switch self {
        case .projects: .tags
        case .tags, .notes: .notes
        }
    }

    /// Notes → Tags → Tasks; Tasks stays.
    var previous: Self {
        switch self {
        case .notes: .tags
        case .tags, .projects: .projects
        }
    }
}
