// Menu commands: ⌘1–3 switch domains; ⌘E switches Live and Source; View ▸ Theme picks a scheme.
import SwiftUI

struct AppCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button("Today") { model.domain = .today }
                .keyboardShortcut("1")
            Button("Upcoming") { model.domain = .upcoming }
                .keyboardShortcut("2")
            Button("Loose Tasks") { model.domain = .loose }
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
