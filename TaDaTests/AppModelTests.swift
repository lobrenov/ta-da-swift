import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct AppModelTests {
    let defaults: UserDefaults
    let suite = "TaDaTests-\(UUID().uuidString)"
    let folder = FileManager.default.temporaryDirectory.appending(path: "TaDaVault-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        for (path, text) in [
            ("projects/Ta Da MVP.md", "---\ntype: project\nstatus: Doing\n---\n"),
            ("projects/Shipped.md", "---\ntype: project\nstatus: Done\n---\n"),
            ("tasks/Due today.md", "---\ntype: task\nstatus: Doing\ndueDate: 2026-10-02\nproject: \"[[Ta Da MVP]]\"\n---\n"),
            ("tasks/Done.md", "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nproject: \"[[Ta Da MVP]]\"\n---\n"),
            ("tasks/Loose.md", "---\ntype: task\nstatus: Not Started\ndeadline: 2026-09-30\n---\n"),
            ("notes/Note.md", "Just a note\n"),
        ] {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }

    private func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func startsWithoutAFolder() async {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        await model.start()
        #expect(model.state == .noFolder)
    }

    @Test func choosingAFolderLoadsItAndCounts() async {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        model.today = LocalDate("2026-10-02")!
        await model.choose(folder)
        #expect(model.state == .ready)
        #expect(model.index.items.count == 5)
        #expect(model.todayCount == 2, "open tasks only; Done-today doesn't count")
        #expect(model.looseCount == 1)
        #expect(model.projects.map { "\($0.project.title) \($0.open)/\($0.total)" } == ["Ta Da MVP 1/2"])
        #expect(model.folderDisplayName == folder.lastPathComponent)
    }

    @Test func theFolderAndThemeSurviveARelaunch() async {
        defer { cleanUp() }
        let first = AppModel(defaults: defaults)
        await first.choose(folder)
        first.themeName = "Nord"

        let second = AppModel(defaults: defaults)
        #expect(second.themeName == "Nord" && second.theme.name == "Nord")
        await second.start()
        #expect(second.state == .ready)
        #expect(second.vault?.root.resolvingSymlinksInPath() == folder.resolvingSymlinksInPath())
    }

    @Test func aMissingFolderFailsWithAMessage() async throws {
        defer { cleanUp() }
        let first = AppModel(defaults: defaults)
        await first.choose(folder)
        try FileManager.default.removeItem(at: folder)

        let second = AppModel(defaults: defaults)
        await second.start()
        guard case let .failed(message) = second.state else {
            Issue.record("expected failed, got \(second.state)")
            return
        }
        #expect(message.contains("moved or deleted"))
    }

    @Test func unknownThemeNamesFallBackToTheFirstScheme() {
        defer { cleanUp() }
        defaults.set("Monokai", forKey: "themeName")
        #expect(AppModel(defaults: defaults).theme.name == "Tomorrow Night")
    }

    @Test(arguments: [
        ("/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Ta Da", "iCloud Drive/Ta Da"),
        ("/Users/me/Library/Mobile Documents/iCloud~md~obsidian/Documents/Personal", "Obsidian/Personal"),
        ("/Users/me/Projects/Ta Da/SampleVault", "SampleVault"),
    ])
    func folderNamesReadLikeFinder(_ path: String, _ expected: String) {
        defer { cleanUp() }
        #expect(AppModel.displayName(for: URL(filePath: path)) == expected)
    }
}
