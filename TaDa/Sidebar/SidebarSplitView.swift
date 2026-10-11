// The window's sidebar beside the workspace. When the window is too narrow for both, the sidebar hides, and the
// sidebar button (or View ▸ Toggle Sidebar) floats it over the workspace until a click elsewhere or a pick in it.
// While the sidebar is hidden, a two-finger swipe to the right floats it too; a swipe to the left hides a floating
// sidebar, or the docked one when the pointer is over it.
#if os(macOS)
import SwiftUI

struct SidebarSplitView: View {
    let model: AppModel
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var sidebarWidth: CGFloat = 240
    /// The window is too narrow for the sidebar beside the workspace.
    @State private var isNarrow = false
    /// The sidebar hid because the window got narrow; it comes back when there's room.
    @State private var sidebarAutoHidden = false
    @State private var sidebarFloats = false
    /// The sidebar floats for Search Files, with its search field taking the keyboard.
    @State private var floatsForSearch = false
    /// Our sidebar button in place of the split view's, once the sidebar has slid away in a narrow window.
    @State private var usesOwnToggle = false
    @State private var anchor = ScreenAnchor()
    @State private var swipe = SidebarSwipe()
    @State private var swipeMonitor: Any?

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(model: model, takesSearchFocus: columns != .detailOnly)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                    if columns == .all { sidebarWidth = min(max($0, 200), 340) }
                }
                .toolbar(removing: usesOwnToggle ? .sidebarToggle : nil)
        } detail: {
            WorkspaceView(model: model)
                .toolbar {
                    if usesOwnToggle { ToolbarItem(placement: .navigation) { toggleButton } }
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
        .onChange(of: columns) { if columns != .detailOnly { showedDockedSidebar() } }
        .onChange(of: model.sidebarToggleRequest) { toggle() }
        .onChange(of: model.searchFocusRequest) {
            if columns == .detailOnly, !sidebarFloats { floatsForSearch = true; sidebarFloats = true }
        }
        .onChange(of: sidebarFloats) { if !sidebarFloats { floatsForSearch = false } }
        .onChange(of: model.domain) { sidebarFloats = false }
    }

    /// The sidebar button in a narrow window, where the split view's own would show the sidebar beside the workspace.
    /// It takes the split view's place beside the window's buttons.
    private var toggleButton: some View {
        Button { toggle() } label: { Label("Toggle Sidebar", systemImage: "sidebar.left") }
            .help(sidebarFloats ? "Hide Sidebar" : "Show Sidebar")
    }

    /// The sidebar over the workspace, sliding in from the left, with a click anywhere else hiding it.
    private var floatingSidebar: some View {
        ZStack(alignment: .leading) {
            if sidebarFloats {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { sidebarFloats = false }
                    .accessibilityHidden(true)
                SidebarView(model: model, focusesSearch: floatsForSearch)
                    .frame(width: sidebarWidth)
                    .background { model.theme.color(\.side).ignoresSafeArea() }
                    .overlay(alignment: .trailing) { Hairline(axis: .vertical).ignoresSafeArea() }
                    .shadow(color: .black.opacity(0.18), radius: 16)
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.snappy(duration: 0.25), value: sidebarFloats)
    }

    /// Hides the sidebar when the window is too narrow for it, as it opens or resizes, and shows it again when there's
    /// room.
    private func fit(width: CGFloat) {
        let narrow = width < sidebarWidth + WorkspaceView.minWidth
        guard narrow != isNarrow else { return }
        isNarrow = narrow
        if narrow {
            if columns != .detailOnly {
                withAnimation { columns = .detailOnly } completion: { if isNarrow { usesOwnToggle = true } }
                sidebarAutoHidden = true
            } else {
                usesOwnToggle = true
            }
        } else {
            sidebarFloats = false
            usesOwnToggle = false
            if sidebarAutoHidden {
                withAnimation { columns = .all }
                sidebarAutoHidden = false
            }
        }
    }

    private func toggle() {
        if isNarrow || sidebarFloats {
            sidebarFloats.toggle()
        } else {
            hideDockedSidebar(columns != .detailOnly)
        }
    }

    /// The split view showed its sidebar: the floating one hides, and in a narrow window the docked one slides away
    /// again.
    private func showedDockedSidebar() {
        sidebarFloats = false
        guard isNarrow else { return }
        withAnimation { columns = .detailOnly }
        sidebarAutoHidden = true
    }

    private func hideDockedSidebar(_ hide: Bool) {
        sidebarAutoHidden = false
        withAnimation { columns = hide ? .detailOnly : .all }
    }

    /// Two-finger swipes: to the right floats the hidden sidebar, unless something under the pointer scrolls left; to
    /// the left hides the floating sidebar, or the docked one when the pointer is over it.
    private func watchSwipes() {
        stopWatchingSwipes()
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated {
                guard event.window === anchor.window,
                      let direction = swipe.track(event.phase, dx: SidebarSwipe.fingersDX(event), dy: event.scrollingDeltaY)
                else { return }
                switch direction {
                case .right:
                    if columns == .detailOnly, !sidebarFloats, !SidebarSwipe.scrollsLeft(event) { sidebarFloats = true }
                case .left:
                    if sidebarFloats {
                        sidebarFloats = false
                    } else if columns != .detailOnly, event.locationInWindow.x < sidebarWidth {
                        hideDockedSidebar(true)
                    }
                }
            }
            return event
        }
    }

    private func stopWatchingSwipes() {
        if let swipeMonitor { NSEvent.removeMonitor(swipeMonitor) }
        swipeMonitor = nil
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
#endif
