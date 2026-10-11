// Menu commands: ⌘N/⇧⌘N/⌥⌘N new task/project/area; File ▸ Reveal in Finder for the picked or open files; ⌥⌘F search; ⌘1–4 switch domains; ⌘E Live/Source; View ▸ Theme Set and Appearance;
// Task ▸ ⌘K complete or reopen the selected task, ⌘L add a subtask in the editor, or complete the one
// the caret is on, ⇧⌘M move the selected or picked tasks to a project, ⌘S/⌘D set their due date/deadline.
#if os(macOS)
import SwiftUI
import TaDaCore

struct AppCommands: Commands {
    @Bindable var model: AppModel
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { Task { await model.newTask() } }
                .keyboardShortcut("n")
                .disabled(model.state != .ready)
            Button("New Project") { Task { await model.newProject() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.state != .ready)
            Button("New Area") { Task { await model.newArea() } }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(model.state != .ready)
            Divider()
            Button("Reveal in Finder") { model.revealInFinder(model.picked.sorted()) }
                .disabled(model.picked.isEmpty)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Files") { model.searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(model.state != .ready)
        }
        CommandGroup(before: .sidebar) {
            show(.today, key: "1")
            show(.upcoming, key: "2")
            show(.loose, key: "3")
            show(.trash, key: "4")
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
            Divider()
        }
        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") { model.sidebarToggleRequest += 1 }
                .keyboardShortcut("s", modifiers: [.control, .command])
        }
        CommandMenu("Task") {
            let selected = model.selection.flatMap { model.index[$0] }
            Button(selected?.properties.status == .done ? "Mark Not Done" : "Complete") {
                if let selected { Task { await model.toggleCompletion(selected) } }
            }
            .keyboardShortcut("k")
            .disabled(selected == nil)
            Button("Add Subtask") {
                if let textView = editor?.textView { AddSubtask.perform(in: textView) }
            }
            .keyboardShortcut("l")
            .disabled(editor == nil)
            Button("Move…") { model.showMoveMenu() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(model.isSourceMode || model.moveTargets().isEmpty && model.areaTargets().isEmpty)
            Button("Schedule…") { model.showDateMenu(.due) }
                .keyboardShortcut("s")
                .disabled(model.isSourceMode || model.dateTargets().isEmpty)
            Button("Set Deadline…") { model.showDateMenu(.deadline) }
                .keyboardShortcut("d")
                .disabled(model.isSourceMode || model.dateTargets().isEmpty)
        }
    }

    /// Shows a domain, under its name in title case as macOS menu commands are.
    private func show(_ domain: AppModel.Domain, key: KeyEquivalent) -> some View {
        Button(domain.title.capitalized) { model.show(domain) }
            .keyboardShortcut(key)
    }
}
#endif
