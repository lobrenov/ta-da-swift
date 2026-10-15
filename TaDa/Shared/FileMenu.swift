// The file menu: a compact themed menu of file actions in a borderless panel, opened by a right-click on an area,
// project, task or note. Rows add it with `.fileMenu(model, path:)`. A note's menu (also its page's Note ▾) has Task…,
// Project… and Area… to convert it, Tags… and Move to Folder… (a row's), Reveal in Finder and Move to Trash. Move, Schedule, Set Deadline…, Tags… (one file),
// Reveal in Finder and Delete for tasks and projects; New Task and New Project in it, Open Area File, Tags…,
// Reveal in Finder and Delete for an area; Restore, Reveal in Finder and Delete Forever in Trash.
#if os(macOS)
import SwiftUI
import AppKit
import TaDaCore

extension View {
    /// Opens the file menu on a right-click or control-click, and rings the row while it's open.
    func fileMenu(_ model: AppModel, path: String, cornerRadius: CGFloat = 7) -> some View {
        modifier(FileMenuTrigger(model: model, path: path, cornerRadius: cornerRadius))
    }

    /// Opens a menu of `actions` the same way, for something that isn't a file, such as a notes folder. `target` names
    /// it in `model.menuTarget` while the menu is open.
    func actionMenu(_ model: AppModel, target: String, cornerRadius: CGFloat = 7,
                    actions: @escaping () -> [FileMenuAction]) -> some View {
        modifier(FileMenuTrigger(model: model, path: target, cornerRadius: cornerRadius, actions: actions))
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

    /// Move (to a project or area for tasks, to an area for projects), Schedule, Set Deadline…, Tags… (only when the
    /// menu acts on one file), Reveal in Finder and Delete for a file in the folder; Restore, Reveal in Finder and Delete Forever for one in `.trash/`. A
    /// right-click on a picked file acts on every picked file. Move, Schedule, Set Deadline… and Tags… open their menu at `point` (screen coordinates) in `window`, else under
    /// the row or the open file's chip.
    static func actions(for path: String, model: AppModel, at point: CGPoint? = nil, in window: NSWindow? = nil) -> [FileMenuAction] {
        if let area = model.index[path], area.properties.kind == .area {
            return areaActions(for: area, model: model, at: point, in: window)
        }
        if model.index[path]?.properties.kind == .note {
            return noteActions(for: path, model: model, onRow: true, at: point, in: window)
        }
        guard path.hasPrefix(Vault.trashFolder + "/") else {
            let paths = model.multiSelection.contains(path) ? model.multiSelection.sorted() : [path]
            let isProject = model.index[path]?.properties.kind == .project
            let moved = isProject ? model.areaTargets(for: path) : model.moveTargets(for: path)
            let noun = isProject ? "Projects" : "Tasks"
            let move = FileMenuAction(title: moved.count == 1 ? "Move" : "Move \(moved.count) \(noun)",
                                      systemImage: "folder", shortcut: "⌘P") {
                let items = moved.compactMap { model.index[$0] }
                if let point, let window {
                    let rect = CGRect(origin: point, size: .zero)
                    if isProject {
                        PropertyPicker.shared.pickArea(of: items, model: model, below: rect, gap: 0, in: window, ringing: path)
                    } else {
                        PropertyPicker.shared.pickProject(of: items, model: model, below: rect, gap: 0, in: window, ringing: path)
                    }
                } else {
                    model.propertyMenuRequest = AppModel.PropertyMenuRequest(menu: isProject ? .area : .project, paths: moved,
                                                                             anchor: path, onChip: model.selection == path)
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
            return (moved.isEmpty ? [] : [move]) + [schedule, deadline] + (paths.count == 1 ? [tags(path, model: model, at: point, in: window)] : []) + [reveal(paths, model: model), delete]
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

    /// Task…, Project… and Area… (converting it), each with its kind's icon and the folder it goes to; on a row, Tags… and Move to Folder… (when
    /// there's a folder to move to); then Reveal in Finder and Move to Trash. A right-click on a picked note reveals or
    /// trashes every picked file. Without a point (VoiceOver's actions), Tags… opens the note first and Move to Folder…
    /// is left out.
    static func noteActions(for path: String, model: AppModel, onRow: Bool, at point: CGPoint?, in window: NSWindow?) -> [FileMenuAction] {
        let paths = onRow && model.multiSelection.contains(path) ? model.multiSelection.sorted() : [path]
        let trash = FileMenuAction(title: paths.count == 1 ? "Move to Trash" : "Move \(paths.count) Files to Trash",
                                   systemImage: "trash", shortcut: "⌘⌫", startsGroup: paths.count == 1) {
            Task { await model.moveToTrash(paths) }
        }
        guard paths.count == 1 else { return [reveal(paths, model: model), trash] }
        let convert: [FileMenuAction] = [(Item.Kind.task, "Task", "checkmark.square", Vault.taskFolder),
                                         (.project, "Project", "checklist", Vault.projectFolder),
                                         (.area, "Area", "cube", Vault.areaFolder)].map { kind, name, icon, folder in
            FileMenuAction(title: "\(name)…", systemImage: icon, shortcut: folder + "/") {
                model.convertRequest = AppModel.ConvertRequest(path: path, kind: kind)
            }
        }
        var actions = convert
        if onRow {
            // Without a row to open it under, the note's page opens and its Tags row takes the request.
            var tagsAction = point != nil ? tags(path, model: model, at: point, in: window)
                : FileMenuAction(title: "Tags…", systemImage: "tag", shortcut: "⌘T") {
                    model.selection = path
                    model.propertyMenuRequest = AppModel.PropertyMenuRequest(menu: .tags, paths: [path], anchor: path, onChip: true)
                }
            tagsAction.startsGroup = true
            actions.append(tagsAction)
            let folders = moveTargets(for: path, model: model)
            if let point, let window, !folders.isEmpty {
                actions.append(FileMenuAction(title: "Move to Folder…", systemImage: "folder", shortcut: "") {
                    showFolders(folders, for: path, model: model, at: point, in: window)
                })
            }
        }
        var revealAction = reveal([path], model: model)
        revealAction.startsGroup = true
        return actions + [revealAction, trash]
    }

    /// The folders a note can move to: Loose, then the tree, indented, less its own folder.
    static func moveTargets(for path: String, model: AppModel) -> [(path: String, title: String)] {
        func rows(_ nodes: [FolderNode], depth: Int) -> [(path: String, title: String)] {
            nodes.flatMap { [($0.path, String(repeating: "   ", count: depth) + $0.name)] + rows($0.children, depth: depth + 1) }
        }
        let current = Vault.folder(of: path)
        return ([("", "Loose")] + rows(model.folderTree, depth: 0)).filter { $0.path != current }
    }

    /// A menu of `folders` that moves the note at `path` to the one picked.
    private static func showFolders(_ folders: [(path: String, title: String)], for path: String, model: AppModel,
                                    at point: CGPoint, in window: NSWindow) {
        let actions = folders.map { folder in
            FileMenuAction(title: folder.title, systemImage: folder.path.isEmpty ? "tray" : "folder", shortcut: "") {
                Task { await model.moveNote(path, to: folder.path) }
            }
        }
        model.menuTarget = path
        FileMenu.shared.show(actions, at: point, in: window, theme: model.theme) { model.menuTarget = nil }
    }

    /// An area's page opens before a new file is made in it, so the file lands there.
    private static func areaActions(for area: Item, model: AppModel, at point: CGPoint?, in window: NSWindow?) -> [FileMenuAction] {
        [
            FileMenuAction(title: "New Task in \(area.title)", systemImage: "plus", shortcut: "") {
                model.show(.area(area.path))
                Task { await model.newTask() }
            },
            FileMenuAction(title: "New Project in \(area.title)", systemImage: "plus", shortcut: "") {
                model.show(.area(area.path))
                Task { await model.newProject() }
            },
            FileMenuAction(title: "Open Area File", systemImage: "doc", shortcut: "", startsGroup: true) {
                model.open(area.path)
            },
            tags(area.path, model: model, at: point, in: window),
            reveal([area.path], model: model),
            FileMenuAction(title: "Delete", systemImage: "trash", shortcut: "⌘⌫", startsGroup: true) {
                Task { await model.moveToTrash([area.path]) }
            },
        ]
    }

    /// Opens tagMenu for the file at `path`, at `point` in `window`, else under the row or the open file's chip.
    private static func tags(_ path: String, model: AppModel, at point: CGPoint?, in window: NSWindow?) -> FileMenuAction {
        FileMenuAction(title: "Tags…", systemImage: "tag", shortcut: "⌘T") {
            guard let item = model.index[path] else { return }
            if let point, let window {
                PropertyPicker.shared.pickTags(of: item, model: model, below: CGRect(origin: point, size: .zero), gap: 0,
                                               in: window, ringing: path)
            } else {
                model.propertyMenuRequest = AppModel.PropertyMenuRequest(menu: .tags, paths: [path], anchor: path,
                                                                         onChip: model.selection == path)
            }
        }
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

/// Shows the file menu, or the embed menu (`EmbedMenu.swift`), moves through it and runs its actions. One is open at
/// a time.
final class FileMenu {
    static let shared = FileMenu()

    private let menu = PopupMenu(style: .compact, takesKeys: true, row: FileMenuRow.init)
    private weak var model: AppModel?
    private var onClose: (() -> Void)?

    var isOpen: Bool { menu.isOpen }

    private init() {
        menu.onDismiss = { [weak self] in self?.hide() }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FileMenu.shared.hide() }
        }
    }

    /// Opens the menu for `path` (or `actions`, when given) with its top-left corner at `point` (screen coordinates) in
    /// `window`.
    func show(for path: String, actions: [FileMenuAction]? = nil, at point: CGPoint, in window: NSWindow, model: AppModel) {
        show(actions ?? FileMenuAction.actions(for: path, model: model, at: point, in: window), at: point, in: window, theme: model.theme)
        self.model = model
        model.menuTarget = path
    }

    /// Opens a menu of `actions` with its top-left corner at `point` (screen coordinates) in `window`. `onClose` runs
    /// when it closes.
    func show(_ actions: [FileMenuAction], at point: CGPoint, in window: NSWindow, theme: Theme, onClose: (() -> Void)? = nil) {
        hide()
        self.onClose = onClose
        var sections: [PopupMenuSection<FileMenuAction>] = []
        for action in actions {
            if action.startsGroup || sections.isEmpty {
                sections.append(PopupMenuSection(items: [action]))
            } else {
                sections[sections.count - 1].items.append(action)
            }
        }
        menu.show(sections, highlight: nil, theme: theme, below: CGRect(origin: point, size: .zero),
                  inset: 0, gap: 0, in: window) { [weak self] action in
            self?.hide()
            action.run()
        }
    }

    func hide() {
        menu.hide()
        model?.menuTarget = nil
        model = nil
        let onClose = onClose
        self.onClose = nil
        onClose?()
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
    /// The menu's actions; a file's own when nil.
    var actions: (() -> [FileMenuAction])? = nil
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .overlay {
                RightClickReader { point, window in
                    FileMenu.shared.show(for: path, actions: actions?(), at: point, in: window, model: model)
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
                ForEach(Array((actions?() ?? FileMenuAction.actions(for: path, model: model)).enumerated()), id: \.offset) { _, action in
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
