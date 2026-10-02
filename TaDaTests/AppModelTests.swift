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

    @Test func completingAndReopeningChangesOnlyStatusAndCompletedDate() async throws {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        model.today = LocalDate("2026-10-03")!
        await model.choose(folder)
        let url = folder.appending(path: "tasks/Due today.md")
        func expected(_ status: String, _ completed: String) -> String {
            "---\ntype: task\nstatus: \(status)\ndueDate: 2026-10-02\nproject: \"[[Ta Da MVP]]\"\ncompletedDate:\(completed)\n---\n"
        }

        await model.toggleCompletion(try #require(model.index["tasks/Due today.md"]))
        #expect(try String(contentsOf: url, encoding: .utf8) == expected("Done", " 2026-10-03"))
        #expect(model.index["tasks/Due today.md"]?.properties.status == .done)
        #expect(model.projects.first?.open == 0)

        await model.toggleCompletion(try #require(model.index["tasks/Due today.md"]))
        #expect(try String(contentsOf: url, encoding: .utf8) == expected("Not Started", ""))
        #expect(model.index["tasks/Due today.md"]?.properties.status == .notStarted)
    }

    @Test func completionReadsTheStatusFromTheFileNotTheList() async throws {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        await model.choose(folder)
        let stale = try #require(model.index["tasks/Loose.md"])
        // Another app completed it after the index was read.
        let url = folder.appending(path: "tasks/Loose.md")
        try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "Not Started", with: "Done")
            .write(to: url, atomically: true, encoding: .utf8)
        await model.toggleCompletion(stale)
        #expect(model.index["tasks/Loose.md"]?.properties.status == .notStarted)
    }

    @Test func savingToAMissingFileReportsAnError() async throws {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        await model.choose(folder)
        let item = try #require(model.index["tasks/Loose.md"])
        try FileManager.default.removeItem(at: folder.appending(path: "tasks/Loose.md"))
        await model.toggleCompletion(item)
        #expect(model.errorMessage?.contains("Loose") == true)
    }

    @Test func pickingADomainClearsTheSelectionAndProjectsOpenAsPages() async {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        await model.choose(folder)
        model.selection = "tasks/Loose.md"
        model.domain = .today
        #expect(model.selection == "tasks/Loose.md", "same domain keeps the selection")
        model.domain = .upcoming
        #expect(model.selection == nil)

        model.open("projects/Ta Da MVP.md")
        #expect(model.domain == .project("projects/Ta Da MVP.md"))
        #expect(model.selection == "projects/Ta Da MVP.md")
        model.open("tasks/Due today.md")
        #expect(model.domain == .project("projects/Ta Da MVP.md"))
        #expect(model.selection == "tasks/Due today.md")
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
