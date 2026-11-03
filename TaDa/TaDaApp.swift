// App entry. On the Mac: one main window plus Settings, sharing one AppModel, which the app delegate owns.
// On iOS: one window group; the model refreshes (and takes the date) when the scene becomes active and saves when it leaves.
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
        .commands { AppCommands(model: appDelegate.model, updater: appDelegate.updater) }

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

/// Refreshes when the app becomes active, saves when it resigns and before it quits, moves `today` on when the day
/// changes, and keeps Quick Entry's hotkey registered.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.forLaunch()
    let updater = Updater()
    private let hotkeys = HotkeyService()
    private lazy var quickEntry = QuickEntryPanel(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [model] _ in
            MainActor.assumeIsolated { model.today = LocalDate(Date()) }
        }
        hotkeys.onPress = { [weak self] in self?.hotkeyPressed() }
        registerHotkey()
    }

    /// Opens or closes Quick Entry; with no folder open, brings Ta Da forward to choose one.
    private func hotkeyPressed() {
        guard model.state == .ready else { return NSApp.activate() }
        quickEntry.toggle()
    }

    /// Registers the hotkey in the settings, and again whenever it changes or recording starts or stops.
    private func registerHotkey() {
        withObservationTracking { _ = (model.quickEntryHotkey, model.isRecordingHotkey) } onChange: { [weak self] in
            Task { @MainActor in self?.registerHotkey() }
        }
        refreshHotkey()
    }

    /// Registers the hotkey, or none while a new one is recorded, and notes whether its keys are taken.
    private func refreshHotkey() {
        guard !model.isRecordingHotkey else {
            hotkeys.register(nil)
            return
        }
        model.quickEntryHotkeyTaken = !hotkeys.register(model.quickEntryHotkey)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Catches anything the folder watcher missed (or everything, if it couldn't start).
        Task { await model.refresh() }
        // Calendar or Reminders access may have changed in System Settings.
        model.integrations.refresh()
        // So could badges.
        Task { await model.notifications.refresh() }
        // The keys may have been freed in System Settings.
        refreshHotkey()
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
                // A suspended app can miss the day change.
                model.today = LocalDate(Date())
                model.integrations.refresh()
                Task { await model.notifications.refresh() }
                Task { await model.becomeActive() }
            case .inactive:
                if let document = model.document { Task { await model.save(document) } }
            case .background:
                saveInBackground()
            @unknown default:
                break
            }
        }
    }

    /// Saves the open file (keeping unsaved edits in a copy if it changed outside Ta Da) and stops presenting files,
    /// under a background task so the app isn't suspended before it finishes.
    private func saveInBackground() {
        let application = UIApplication.shared
        let task = BackgroundTask()
        task.id = application.beginBackgroundTask(withName: "Save edits") { [task] in task.end() }
        Task { [model] in
            await model.enterBackground()
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
