// App entry: one main window plus Settings, sharing one AppModel, which the app delegate owns.
import AppKit
import SwiftUI
import TaDaCore

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
