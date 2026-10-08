// The file menu: a compact themed menu of file actions in a borderless panel, opened by a right-click on a
// project or task. Rows add it with `.fileMenu(model, path:)`. Move (tasks), Schedule, Set Deadline…, Reveal in
// Finder and Delete everywhere; Restore, Reveal in Finder and Delete Forever in Trash.
#if os(macOS)
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
struct FileMenuAction: PopupMenuItem {
    let title: String
    let systemImage: String
    let shortcut: String
    var isDestructive = false
    /// Drawn after a divider.
    var startsGroup = false
    let run: () -> Void

    /// Move for tasks, Schedule, Set Deadline…, Reveal in Finder and Delete for a file in the folder; Restore,
    /// Reveal in Finder and Delete Forever for one in `.trash/`. A right-click on a picked file acts on every picked
    /// file. Move, Schedule and Set Deadline… open their menu at `point` (screen coordinates) in `window`, else under
    /// the row or the open file's chip.
    static func actions(for path: String, model: AppModel, at point: CGPoint? = nil, in window: NSWindow? = nil) -> [FileMenuAction] {
        guard path.hasPrefix(Vault.trashFolder + "/") else {
            let paths = model.multiSelection.contains(path) ? model.multiSelection.sorted() : [path]
            let tasks = model.moveTargets(for: path)
            let move = FileMenuAction(title: tasks.count == 1 ? "Move" : "Move \(tasks.count) Tasks",
                                      systemImage: "folder", shortcut: "⇧⌘M") {
                if let point, let window {
                    PropertyPicker.shared.pickProject(of: tasks.compactMap { model.index[$0] }, model: model,
                                                      below: CGRect(origin: point, size: .zero), gap: 0, in: window,
                                                      ringing: path)
                } else {
                    model.propertyMenuRequest = AppModel.PropertyMenuRequest(menu: .project, paths: tasks, anchor: path,
                                                                             onChip: false)
                }
            }
            let files = model.dateTargets(for: path)
            func date(_ kind: AgendaEntry.Kind, title: String, shortcut: String) -> FileMenuAction {
                FileMenuAction(title: title, systemImage: kind.systemImage, shortcut: shortcut) {
                    if let point, let window {
                        PropertyPicker.shared.pickDate(kind, of: files.compactMap { model.index[$0] }, model: model,
                                                       below: CGRect(origin: point, size: .zero), gap: 0, in: window,
                                                       ringing: path)
                    } else {
                        model.propertyMenuRequest = AppModel.PropertyMenuRequest(menu: .date(kind), paths: files,
                                                                                 anchor: path, onChip: model.selection == path)
                    }
                }
            }
            let schedule = date(.due, title: files.count == 1 ? "Schedule" : "Schedule \(files.count) Tasks", shortcut: "⌘S")
            let deadline = date(.deadline, title: "Set Deadline…", shortcut: "⌘D")
            let delete = FileMenuAction(title: paths.count == 1 ? "Delete" : "Delete \(paths.count) Tasks",
                                        systemImage: "trash", shortcut: "⌘⌫") {
                Task { await model.moveToTrash(paths) }
            }
            return (tasks.isEmpty ? [] : [move]) + [schedule, deadline, reveal(paths, model: model), delete]
        }
        let paths = model.trashSelection.contains(path) ? model.trashSelection : [path]
        return [
            FileMenuAction(title: "Restore", systemImage: "arrow.counterclockwise", shortcut: "⌘⌫") {
                Task { await model.restore(paths) }
            },
            reveal(paths.sorted(), model: model),
            FileMenuAction(title: "Delete Forever", systemImage: "xmark.bin", shortcut: "⌥⌘⌫",
                           isDestructive: true, startsGroup: true) {
                Task { await model.discard(paths) }
            },
        ]
    }

    private static func reveal(_ paths: [String], model: AppModel) -> FileMenuAction {
        FileMenuAction(title: "Reveal in Finder", systemImage: "arrow.up.forward.square", shortcut: "") {
            model.revealInFinder(paths)
        }
    }
}

extension AppModel {
    /// Selects the files at `paths` in a Finder window.
    func revealInFinder(_ paths: [String]) {
        guard let vault, !paths.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { vault.url(for: $0) })
    }
}

/// Shows the file menu, moves through it and runs its actions. One file menu is open at a time.
final class FileMenu {
    static let shared = FileMenu()

    private let menu = PopupMenu(style: .compact, takesKeys: true, row: FileMenuRow.init)
    private weak var model: AppModel?

    var isOpen: Bool { menu.isOpen }

    private init() {
        menu.onDismiss = { [weak self] in self?.hide() }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FileMenu.shared.hide() }
        }
    }

    /// Opens the menu for `path` with its top-left corner at `point` (screen coordinates) in `window`.
    func show(for path: String, at point: CGPoint, in window: NSWindow, model: AppModel) {
        hide()
        self.model = model
        model.menuTarget = path
        var sections: [PopupMenuSection<FileMenuAction>] = []
        for action in FileMenuAction.actions(for: path, model: model, at: point, in: window) {
            if action.startsGroup || sections.isEmpty {
                sections.append(PopupMenuSection(items: [action]))
            } else {
                sections[sections.count - 1].items.append(action)
            }
        }
        menu.show(sections, highlight: nil, theme: model.theme, below: CGRect(origin: point, size: .zero),
                  inset: 0, gap: 0, in: window) { [weak self] action in
            self?.hide()
            action.run()
        }
    }

    func hide() {
        menu.hide()
        model?.menuTarget = nil
    }
}

private struct FileMenuRow: View {
    let action: FileMenuAction
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: action.systemImage)
                .font(.system(size: 12))
                .frame(width: 14)
                .foregroundStyle(theme.color(action.isDestructive ? \.deadline : isHighlighted ? \.accent : \.muted))
            Text(action.title)
                .foregroundStyle(theme.color(action.isDestructive ? \.deadline : isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(action.shortcut)
                .font(.system(size: 11.5))
                .tracking(0.5)
                .foregroundStyle(theme.color(\.muted))
        }
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
#endif
