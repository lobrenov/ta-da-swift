// The App Shortcuts Siri, Spotlight and the Shortcuts app offer without setup.
import AppIntents

nonisolated struct TaDaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTaskIntent(), phrases: [
            "Add a task in \(.applicationName)",
            "Add a \(.applicationName) task",
        ], shortTitle: "Add Task", systemImageName: "plus.circle")
        AppShortcut(intent: CompleteTaskIntent(), phrases: [
            "Complete a task in \(.applicationName)",
        ], shortTitle: "Complete Task", systemImageName: "checkmark.circle")
        AppShortcut(intent: ShowViewIntent(), phrases: [
            "Show my agenda in \(.applicationName)",
            "Show \(\.$view) in \(.applicationName)",
        ], shortTitle: "Show View", systemImageName: "calendar")
        AppShortcut(intent: OpenParentIntent(), phrases: [
            "Open \(\.$target) in \(.applicationName)",
        ], shortTitle: "Open Project or Area", systemImageName: "folder")
    }
}
