// Menu commands: ⌘N/⇧⌘N new task/project; ⌥⌘F search; ⌘1–4 switch domains; ⌘E Live/Source; View ▸ Theme Set and Appearance;
// Task ▸ ⌘K complete or reopen the selected task, ⌘L add a subtask in the editor, or complete the one
// the caret is on.
import SwiftUI
import TaDaCore

struct AppCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { Task { await model.newTask() } }
                .keyboardShortcut("n")
                .disabled(model.state != .ready)
            Button("New Project") { Task { await model.newProject() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.state != .ready)
        }
        CommandGroup(after: .textEditing) {
            Button("Search Files") { model.searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(model.state != .ready)
        }
        CommandGroup(before: .sidebar) {
            Button("Today") { model.show(.today) }
                .keyboardShortcut("1")
            Button("Upcoming") { model.show(.upcoming) }
                .keyboardShortcut("2")
            Button("Loose Tasks") { model.show(.loose) }
                .keyboardShortcut("3")
            Button("Trash") { model.show(.trash) }
                .keyboardShortcut("4")
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
        CommandMenu("Task") {
            let selected = model.selection.flatMap { model.index[$0] }
            Button(selected?.properties.status == .done ? "Mark Not Done" : "Complete") {
                if let selected { Task { await model.toggleCompletion(selected) } }
            }
            .keyboardShortcut("k")
            .disabled(selected == nil)
            Button("Add Subtask") {
                if let editor = AddSubtask.focusedEditor { AddSubtask.perform(in: editor) } else { NSSound.beep() }
            }
            .keyboardShortcut("l")
            .disabled(model.document == nil)
        }
    }
}
