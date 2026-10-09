// App entry. On the Mac: one main window plus Settings, sharing one AppModel, which the app delegate owns.
// On iOS: one window group; the model refreshes when the scene becomes active and saves when it leaves.
import Combine
import SwiftUI
import TaDaCore
#if os(macOS)
import AppKit

@main
struct TaDaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Ta Da", id: "main") {
            ContentView(model: appDelegate.model)
        }
        .defaultSize(width: 1280, height: 800)
        .commands { AppCommands(model: appDelegate.model) }

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

/// Refreshes when the app becomes active, saves when it resigns and before it quits, and moves `today`
/// on when the day changes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.forLaunch()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [model] _ in
            MainActor.assumeIsolated { model.today = LocalDate(Date()) }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Catches anything the folder watcher missed (or everything, if it couldn't start).
        Task { await model.refresh() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard let document = model.document else { return }
        Task { await model.save(document) }
    }

    /// Quitting, including by closing the window, waits until the open file is saved.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.document?.isDirty == true else { return .terminateNow }
        Task {
            await model.saveBeforeQuitting()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#else

@main
struct TaDaApp: App {
    @State private var model = AppModel.forLaunch()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                    model.today = LocalDate(Date())
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.refresh() }
            case .inactive:
                if let document = model.document { Task { await model.save(document) } }
            case .background:
                saveInBackground()
            @unknown default:
                break
            }
        }
    }

    /// Saves the open file, and keeps unsaved edits in a copy if it changed outside Ta Da, under a background task
    /// so the system lets it finish after the app is suspended.
    private func saveInBackground() {
        guard model.document?.isDirty == true else { return }
        let application = UIApplication.shared
        let task = BackgroundTask()
        task.id = application.beginBackgroundTask(withName: "Save edits") { [task] in task.end() }
        Task { [model] in
            await model.saveBeforeQuitting()
            task.end()
        }
    }
}

/// A background task that ends once, whether its work finishes or the system's time runs out.
private final class BackgroundTask {
    var id = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif
