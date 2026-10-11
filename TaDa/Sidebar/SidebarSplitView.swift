// The window's sidebar beside the workspace. When the window is too narrow for both, the sidebar hides, and the
// sidebar button (or View ▸ Toggle Sidebar) floats it over the workspace until a click elsewhere or a pick in it.
// While the sidebar is hidden, a two-finger swipe to the right floats it too, as does resting the pointer on the
// window's left edge; the pointer leaving a sidebar floated that way hides it.
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
    /// The floating sidebar came from the pointer on the window's edge, and goes when the pointer leaves it.
    @State private var floatedByHover = false
    @State private var edgeHover: Task<Void, Never>?
    @State private var anchor = ScreenAnchor()
    @State private var swipe = SidebarSwipe()
    @State private var swipeMonitor: Any?

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(model: model)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 > 0 { sidebarWidth = $0 } }
                .toolbar(removing: isNarrow ? .sidebarToggle : nil)
        } detail: {
            WorkspaceView(model: model)
                .toolbar {
                    if isNarrow { ToolbarItem(placement: .navigation) { toggleButton } }
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fit(width: $0) }
        .overlay(alignment: .leading) { floatingSidebar }
        .background(ScreenAnchorReader(anchor: anchor))
        .onContinuousHover { watchEdge($0) }
        .onAppear { watchSwipes() }
        .onDisappear { stopWatchingSwipes() }
        .onChange(of: columns) { if columns != .detailOnly { sidebarFloats = false } }
        .onChange(of: model.sidebarToggleRequest) { toggle() }
        .onChange(of: model.domain) { hideFloatingSidebar() }
    }

    /// The sidebar button while the window is narrow; otherwise the split view's own.
    private var toggleButton: some View {
        Button { toggle() } label: { Label("Toggle Sidebar", systemImage: "sidebar.left") }
            .help(sidebarFloats ? "Hide Sidebar" : "Show Sidebar")
    }

    /// The sidebar over the workspace, with a click anywhere else hiding it.
    @ViewBuilder private var floatingSidebar: some View {
        if sidebarFloats {
            ZStack(alignment: .leading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { hideFloatingSidebar() }
                    .accessibilityHidden(true)
                SidebarView(model: model)
                    .frame(width: sidebarWidth)
                    .background { model.theme.color(\.side).ignoresSafeArea() }
                    .overlay(alignment: .trailing) { Hairline(axis: .vertical).ignoresSafeArea() }
                    .shadow(color: .black.opacity(0.18), radius: 16)
                    .onHover { if !$0, floatedByHover { hideFloatingSidebar() } }
                    .transition(.move(edge: .leading))
            }
        }
    }

    /// Hides the sidebar when the window gets too narrow for it, and shows it again when there's room.
    private func fit(width: CGFloat) {
        let narrow = width < sidebarWidth + WorkspaceView.minWidth
        guard narrow != isNarrow else { return }
        isNarrow = narrow
        if narrow {
            if columns != .detailOnly {
                columns = .detailOnly
                sidebarAutoHidden = true
            }
        } else {
            sidebarFloats = false
            if sidebarAutoHidden {
                columns = .all
                sidebarAutoHidden = false
            }
        }
    }

    private func toggle() {
        if isNarrow || sidebarFloats {
            floatedByHover = false
            withAnimation(.snappy(duration: 0.22)) { sidebarFloats.toggle() }
        } else {
            sidebarAutoHidden = false
            withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
        }
    }

    /// Floats the hidden sidebar on a two-finger swipe to the right, unless something under the pointer scrolls left.
    private func watchSwipes() {
        stopWatchingSwipes()
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated {
                guard event.window === anchor.window, columns == .detailOnly, !sidebarFloats,
                      swipe.track(event.phase, dx: SidebarSwipe.fingersDX(event), dy: event.scrollingDeltaY),
                      !SidebarSwipe.scrollsLeft(event) else { return }
                floatedByHover = false
                withAnimation(.snappy(duration: 0.22)) { sidebarFloats = true }
            }
            return event
        }
    }

    private func stopWatchingSwipes() {
        if let swipeMonitor { NSEvent.removeMonitor(swipeMonitor) }
        swipeMonitor = nil
    }

    /// Floats the hidden sidebar when the pointer rests on the window's left 6pt for 150 ms.
    private func watchEdge(_ phase: HoverPhase) {
        guard case let .active(point) = phase, point.x <= 6, columns == .detailOnly, !sidebarFloats else {
            edgeHover?.cancel()
            edgeHover = nil
            return
        }
        guard edgeHover == nil else { return }
        edgeHover = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            edgeHover = nil
            floatedByHover = true
            withAnimation(.snappy(duration: 0.22)) { sidebarFloats = true }
        }
    }

    private func hideFloatingSidebar() {
        guard sidebarFloats else { return }
        floatedByHover = false
        withAnimation(.snappy(duration: 0.22)) { sidebarFloats = false }
    }
}
#endif
