// Menu commands: ⌘N/⇧⌘N new task/project; ⌥⌘F search; ⌘1–3 switch domains; ⌘E Live/Source; View ▸ Theme.
import SwiftUI

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
            Divider()
            Button(model.isSourceMode ? "Show Live Preview" : "Show Source") { model.isSourceMode.toggle() }
                .keyboardShortcut("e")
                .disabled(model.document == nil)
            Divider()
            Picker("Theme", selection: $model.themeName) {
                ForEach(Theme.all) { Text($0.name).tag($0.name) }
            }
            Divider()
        }
    }
}
