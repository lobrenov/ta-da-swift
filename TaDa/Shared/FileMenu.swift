// The file menu: a compact themed menu of file actions in a borderless panel, opened by a right-click on a
// project or task. Rows add it with `.fileMenu(model, path:)`. Delete everywhere; Restore and Delete Forever
// in Trash.
import SwiftUI
import AppKit
import TaDaCore

extension View {
    /// Opens the file menu on a right-click or control-click, and rings the row while it's open.
    func fileMenu(_ model: AppModel, path: String, cornerRadius: CGFloat = 7) -> some View {
        modifier(FileMenuTrigger(model: model, path: path, cornerRadius: cornerRadius))
    }
}

/// One row of the file menu.
struct FileMenuAction {
    let title: String
    let systemImage: String
    let shortcut: String
    var isDestructive = false
    /// Drawn after a divider.
    var startsGroup = false
    let run: () -> Void

    /// Delete for a file in the folder; Restore and Delete Forever for one in `.trash/`. A right-click on a
    /// picked file acts on every picked file.
    static func actions(for path: String, model: AppModel) -> [FileMenuAction] {
        guard path.hasPrefix(Vault.trashFolder + "/") else {
            let paths = model.multiSelection.contains(path) ? model.multiSelection.sorted() : [path]
            return [FileMenuAction(title: paths.count == 1 ? "Delete" : "Delete \(paths.count) Tasks",
                                   systemImage: "trash", shortcut: "⌘⌫") {
                Task { await model.moveToTrash(paths) }
            }]
        }
        let paths = model.trashSelection.contains(path) ? model.trashSelection : [path]
        return [
            FileMenuAction(title: "Restore", systemImage: "arrow.counterclockwise", shortcut: "⌘⌫") {
                Task { await model.restore(paths) }
            },
            FileMenuAction(title: "Delete Forever", systemImage: "xmark.bin", shortcut: "⌥⌘⌫",
                           isDestructive: true, startsGroup: true) {
                Task { await model.discard(paths) }
            },
        ]
    }
}

/// Shows the file menu, moves through it and runs its actions. One file menu is open at a time.
final class FileMenu {
    static let shared = FileMenu()

    private let menu = FileMenuModel()
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private weak var model: AppModel?

    var isOpen: Bool { panel?.isVisible == true }

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FileMenu.shared.hide() }
        }
    }

    /// Opens the menu for `path` with its top-left corner at `point` (screen coordinates) in `window`.
    func show(for path: String, at point: CGPoint, in window: NSWindow, model: AppModel) {
        hide()
        self.model = model
        model.menuTarget = path
        menu.actions = FileMenuAction.actions(for: path, model: model)
        menu.selection = nil
        menu.theme = model.theme
        menu.run = { [weak self] action in
            self?.hide()
            action.run()
        }

        let panel = panel ?? makePanel()
        let size = menu.size
        var origin = CGPoint(x: point.x, y: point.y - size.height)
        if let visible = window.screen?.visibleFrame {
            if origin.y < visible.minY { origin.y = point.y }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
        installEventMonitor()
    }

    func hide() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        model?.menuTarget = nil
        guard let panel, panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.contentView = FirstMouseHostingView(rootView: FileMenuView(menu: menu))
        self.panel = panel
        return panel
    }

    /// While open, the menu takes every key: ↑↓ move, ↵ runs, esc closes. A click elsewhere or a scroll closes it.
    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                handle(event)
                return nil
            }
            // A two-finger click on a trackpad also sends scroll events that don't move.
            let isStillScroll = event.type == .scrollWheel && event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0
            if event.window !== panel, !isStillScroll { hide() }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        let count = menu.actions.count
        switch event.keyCode {
        case 125 where count > 0: menu.selection = menu.selection.map { ($0 + 1) % count } ?? 0
        case 126 where count > 0: menu.selection = menu.selection.map { ($0 + count - 1) % count } ?? count - 1
        case 36, 76:
            if let selection = menu.selection, menu.actions.indices.contains(selection) { menu.run(menu.actions[selection]) }
        case 53: hide()
        default: break
        }
    }
}

@Observable
private final class FileMenuModel {
    var actions: [FileMenuAction] = []
    /// The highlighted row; nothing is highlighted when the menu opens.
    var selection: Int?
    var theme = Theme.all[0]
    @ObservationIgnored var run: (FileMenuAction) -> Void = { _ in }

    static let width: CGFloat = 196
    static let rowHeight: CGFloat = 26
    static let dividerHeight: CGFloat = 7

    /// The rows and dividers 1pt apart, with a 4pt pad all round.
    var size: CGSize {
        let dividers = CGFloat(actions.count { $0.startsGroup })
        let rows = CGFloat(actions.count)
        return CGSize(width: Self.width, height: 8 + rows * Self.rowHeight + dividers * Self.dividerHeight + rows + dividers - 1)
    }
}

private struct FileMenuView: View {
    let menu: FileMenuModel

    private var theme: Theme { menu.theme }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(Array(menu.actions.enumerated()), id: \.offset) { index, action in
                if action.startsGroup {
                    Rectangle()
                        .fill(theme.color(\.border))
                        .frame(height: 1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .accessibilityHidden(true)
                }
                row(action, index: index)
            }
        }
        .padding(4)
        .frame(width: FileMenuModel.width)
        .background(theme.color(theme.isDark ? \.side : \.bg), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.color(\.surface)))
        .font(.system(size: 13))
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }

    private func row(_ action: FileMenuAction, index: Int) -> some View {
        let isSelected = menu.selection == index
        let background: Color = switch (isSelected, action.isDestructive) {
        case (false, _): .clear
        case (true, false): theme.color(\.surface)
        case (true, true): theme.color(\.deadline).opacity(theme.isDark ? 0.22 : 0.14)
        }
        return HStack(spacing: 8) {
            Image(systemName: action.systemImage)
                .font(.system(size: 12))
                .frame(width: 14)
                .foregroundStyle(theme.color(action.isDestructive ? \.deadline : isSelected ? \.accent : \.muted))
            Text(action.title)
                .foregroundStyle(theme.color(action.isDestructive ? \.deadline : isSelected ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(action.shortcut)
                .font(.system(size: 11.5))
                .tracking(0.5)
                .foregroundStyle(theme.color(\.muted))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .frame(height: FileMenuModel.rowHeight)
        .background(background, in: .rect(cornerRadius: 5))
        .contentShape(.rect)
        .onHover { inside in
            if inside {
                menu.selection = index
            } else if menu.selection == index {
                menu.selection = nil
            }
        }
        .onTapGesture { menu.run(action) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { menu.run(action) }
    }
}

private struct FileMenuTrigger: ViewModifier {
    let model: AppModel
    let path: String
    let cornerRadius: CGFloat
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .overlay {
                RightClickReader { point, window in
                    FileMenu.shared.show(for: path, at: point, in: window, model: model)
                }
                .accessibilityHidden(true)
            }
            .overlay {
                if model.menuTarget == path {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(theme.color(\.accent), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityActions {
                ForEach(Array(FileMenuAction.actions(for: path, model: model).enumerated()), id: \.offset) { _, action in
                    Button(action.title, action: action.run)
                }
            }
    }
}

/// A transparent view that takes only right-clicks and control-clicks; every other event goes to the row.
private struct RightClickReader: NSViewRepresentable {
    let action: (CGPoint, NSWindow) -> Void

    func makeNSView(context: Context) -> Reader { Reader() }
    func updateNSView(_ view: Reader, context: Context) { view.action = action }

    final class Reader: NSView {
        var action: (CGPoint, NSWindow) -> Void = { _, _ in }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, Self.isContextClick(event) else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) { open(event) }
        override func mouseDown(with event: NSEvent) { open(event) }

        private func open(_ event: NSEvent) {
            guard let window else { return }
            action(window.convertPoint(toScreen: event.locationInWindow), window)
        }

        private static func isContextClick(_ event: NSEvent) -> Bool {
            event.type == .rightMouseDown || event.type == .leftMouseDown && event.modifierFlags.contains(.control)
        }
    }
}
