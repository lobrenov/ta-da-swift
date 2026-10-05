// UI tests launch with `-uiTesting`: throwaway settings and a small folder in the app's own container,
// so they never touch the folder you use. Edits wait a minute to be saved, so a test can quit before they
// are. Adding `-uiTestingRelaunch` keeps the settings and folder as the last launch left them. Debug builds only.
import Foundation
import TaDaCore

extension AppModel {
    static func forLaunch() -> AppModel {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTesting"), let model = try? uiTesting(fresh: !arguments.contains("-uiTestingRelaunch")) {
            model.saveDelay = .seconds(60)
            return model
        }
        #endif
        return AppModel()
    }

    #if DEBUG
    private static func uiTesting(fresh: Bool) throws -> AppModel {
        let suite = "TaDaUITesting"
        let defaults = UserDefaults(suiteName: suite)!
        guard fresh else { return AppModel(defaults: defaults) }
        defaults.removePersistentDomain(forName: suite)
        let folder = FileManager.default.temporaryDirectory.appending(path: "UI Testing Vault", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        let today = LocalDate(Date()).description
        for (path, text) in [
            ("tasks/Alpha.md", "---\ntype: task\nstatus: Not Started\ndueDate: \(today)\n---\nFirst line.\n"),
            ("tasks/Beta.md", "---\ntype: task\nstatus: Not Started\ndueDate: \(today)\n---\n"),
        ] {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        defaults.set(try Vault.bookmark(for: folder), forKey: Keys.bookmark)
        return AppModel(defaults: defaults)
    }
    #endif
}
