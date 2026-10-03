// App entry: one main window plus Settings, sharing one AppModel.
import SwiftUI

@main
struct TaDaApp: App {
    @State private var model = AppModel.forLaunch()

    var body: some Scene {
        Window("Ta Da", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 1280, height: 800)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView(model: model)
        }
    }
}
