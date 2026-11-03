// Menu commands: ⌘N new task, or note in Notes; ⇧⌘N/⌥⌘N new project/area; File ▸ New Folder; ⌘O the quick switcher; File ▸ Convert to for the open or
// picked note; File ▸ Reveal in Finder for the picked or open files; ⌥⌘F search; ⌘1–4 switch domains; ⌘E Live/Source; View ▸ Theme Set and Appearance;
// Task ▸ complete or reopen the selected task, ⌘L add a subtask in the editor, or complete the one
// the caret is on, Extract to Task for the caret's subtask, ⌘P move the selected or picked tasks to a project, ⌘S/⌘D set their due date/deadline, ⌘T opens the open file's tag menu;
// Format ▸ ⌘B/⌘I/⇧⌘H/⇧⌘S bold, italic, highlight, strikethrough in the Live editor.
#if os(macOS)
import SwiftUI
import TaDaCore

struct AppCommands: Commands {
    @Bindable var model: AppModel
    let updater: Updater
    @FocusedValue(\.editor) private var editor

    /// The open or picked file, when it's one note.
    private var pickedNote: String? {
        guard model.picked.count == 1, let path = model.picked.first, model.index[path]?.properties.kind == .note else { return nil }
        return path
    }

    private func convert(to kind: Item.Kind) {
        if let pickedNote { model.convertRequest = AppModel.ConvertRequest(path: pickedNote, kind: kind) }
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Task/Note") { Task { await model.newTaskOrNote() } }
                .keyboardShortcut("n")
                .disabled(model.state != .ready)
            Button("New Project") { Task { await model.newProject() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.state != .ready)
            Button("New Area") { Task { await model.newArea() } }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(model.state != .ready)
            Button("New Folder") { Task { await model.newFolder() } }
                .disabled(model.state != .ready)
            Divider()
            Button("Quick Switcher…") { model.quickSwitcherRequest += 1 }
                .keyboardShortcut("o")
                .disabled(model.state != .ready)
            Divider()
            Menu("Convert to") {
                Button("Task…") { convert(to: .task) }
                Button("Project…") { convert(to: .project) }
                Button("Area…") { convert(to: .area) }
            }
            .disabled(pickedNote == nil)
            Button("Reveal in Finder") { model.revealInFinder(model.picked.sorted()) }
                .disabled(model.picked.isEmpty)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Files") { model.searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(model.state != .ready)
        }
        CommandGroup(before: .toolbar) {
            show(.agenda, key: "1")
            show(.loose, key: "2")
            show(.trash, key: "3")
            show(.logbook, key: "4")
            Button(AppModel.Domain.attachments.title) { model.show(.attachments) }
            Divider()
            Button(model.isSourceMode ? "Show Live Preview" : "Show Source") { model.isSourceMode.toggle() }
                .keyboardShortcut("e")
                .disabled(model.document == nil)
            Divider()
            Picker("Theme Set", selection: Binding { model.themeSet } set: { model.choose($0) }) {
                ForEach(ThemeSet.all) { Text($0.name).tag($0) }
            }
            Picker("Appearance", selection: $model.appearance) {
                ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
            }
        }
        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") { model.sidebarToggleRequest += 1 }
                .keyboardShortcut("s", modifiers: [.control, .command])
        }
        CommandMenu("Task") {
            let selected = model.selection.flatMap { model.index[$0] }
            Button(selected.map { StatusCheckbox.action(for: $0.properties.status).capitalized } ?? "Complete") {
                if let selected { Task { await model.toggleCompletion(selected) } }
            }
            .disabled(selected == nil)
            Button("Add Subtask") {
                if let textView = editor?.textView { AddSubtask.perform(in: textView) }
            }
            .keyboardShortcut("l")
            .disabled(editor == nil)
            Button("Extract to Task") {
                if let textView = editor?.textView { ExtractTask.perform(in: textView, at: textView.selectedRange().location, model: model) }
            }
            .disabled(editor == nil)
            Button("Move…") { model.showMoveMenu() }
                .keyboardShortcut("p")
                .disabled(model.isSourceMode || model.moveTargets().isEmpty && model.areaTargets().isEmpty)
            Button("Schedule…") { model.showDateMenu(.due) }
                .keyboardShortcut("s")
                .disabled(model.isSourceMode || model.dateTargets().isEmpty)
            Button("Set Deadline…") { model.showDateMenu(.deadline) }
                .keyboardShortcut("d")
                .disabled(model.isSourceMode || model.dateTargets().isEmpty)
            Button("Tags…") { model.showTagMenu() }
                .keyboardShortcut("t")
                .disabled(model.isSourceMode || model.selection.flatMap { model.index[$0] } == nil)
        }
        CommandMenu("Format") {
            format("Bold", .bold, key: "b")
            format("Italic", .italic, key: "i")
            format("Highlight", .highlight, key: "h", modifiers: [.command, .shift])
            format("Strikethrough", .strikethrough, key: "s", modifiers: [.command, .shift])
        }
    }

    private func format(_ title: String, _ format: InlineFormat, key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        let formatting = editor as? any InlineFormatting
        return Button(title) { formatting?.apply(format) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(formatting == nil)
    }

    /// Shows a domain, under its name in title case as macOS menu commands are.
    private func show(_ domain: AppModel.Domain, key: KeyEquivalent) -> some View {
        Button(domain.title.capitalized) { model.show(domain) }
            .keyboardShortcut(key)
    }
}
#endif
