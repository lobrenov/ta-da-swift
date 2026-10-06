import AppKit
import Foundation
import SwiftUI
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

    @Test func theListsFollowTheDateTypingAndOutsideChanges() async throws {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        model.today = LocalDate("2026-10-01")!
        await model.choose(folder)
        #expect(model.todayTasks.map(\.title) == ["Loose"] && model.upcoming.map(\.item.title) == ["Due today"])

        model.today = LocalDate("2026-10-02")!
        #expect(model.todayTasks.map(\.title) == ["Loose", "Done", "Due today"] && model.upcoming.isEmpty)

        model.selection = "tasks/Loose.md"
        await model.loading?.value
        let document = try #require(model.document)
        document.text += "- [ ] Step\n"
        #expect(model.todayTasks.map(\.title) == ["Loose", "Done", "Due today"] && model.todayTasks.first?.subtasks.total == 1)
        #expect(model.looseTasks.first?.subtasks.total == 1)
        document.text = document.text.replacingOccurrences(of: "status: Not Started", with: "status: Not Started\nproject: \"[[Ta Da MVP]]\"")
        #expect(model.looseTasks.isEmpty && model.projects.map(\.total) == [3])

        try Data("---\ntype: task\nstatus: Doing\n---\n".utf8).write(to: folder.appending(path: "tasks/New.md"))
        await model.refresh()
        #expect(model.looseTasks.map(\.title) == ["New"])
    }

    @Test func theFolderAndThemeSurviveARelaunch() async {
        defer { cleanUp() }
        let first = AppModel(defaults: defaults)
        await first.choose(folder)
        first.choose(ThemeSet.named("Nord")!)
        first.appearance = .light

        let second = AppModel(defaults: defaults)
        #expect(second.themeSet.name == "Nord" && second.appearance == .light && second.theme.name == "Nord Light")
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

    @Test func aProjectMadeFromTheProjectMenuIsLinkedToTheTask() async throws {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        model.today = LocalDate("2026-10-06")!
        await model.choose(folder)
        await model.newProject(named: "Q4: Launch", linking: "tasks/Loose.md")
        #expect(try String(contentsOf: folder.appending(path: "projects/Q4 - Launch.md"), encoding: .utf8)
                == "---\ntype: project\nstatus: Not Started\ncreatedDate: 2026-10-06\n---\n")
        #expect(try String(contentsOf: folder.appending(path: "tasks/Loose.md"), encoding: .utf8)
                == "---\ntype: task\nstatus: Not Started\ndeadline: 2026-09-30\nproject: \"[[Q4 - Launch]]\"\n---\n")
        #expect(model.index.project(of: try #require(model.index["tasks/Loose.md"]))?.path == "projects/Q4 - Launch.md")
        #expect(model.titleFocus == nil, "the new project's title isn't focused; the task stays open")
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

    @Test func unknownThemeNamesFallBackToTomorrow() {
        defer { cleanUp() }
        defaults.set("Monokai", forKey: "themeSet")
        defaults.set("Monokai Light", forKey: "lightScheme")
        defaults.set(true, forKey: "usesSchemePerAppearance")
        defaults.set("Light", forKey: "appearance")
        let model = AppModel(defaults: defaults)
        #expect(model.themeSet.name == "Tomorrow" && model.theme.name == "Tomorrow")
    }

    @Test func theSchemeFollowsTheAppearance() {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        model.choose(ThemeSet.named("Gruvbox")!)
        model.systemIsDark = false
        #expect(model.theme.name == "Gruvbox Light")
        model.systemIsDark = true
        #expect(model.theme.name == "Gruvbox Dark")
        model.appearance = .light
        #expect(model.theme.name == "Gruvbox Light", "a fixed appearance ignores the Mac's")
    }

    @Test func aWindowTakesItsSchemesAppearanceAndTheModelFollowsTheMacs() async throws {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        let macIsDark = Appearance.systemIsDark
        model.appearance = macIsDark ? .light : .dark
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 900, height: 600),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.orderFrontRegardless()
        let schemes: NSAppearance.Name = macIsDark ? .aqua : .darkAqua
        for _ in 0..<50 where window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) != schemes {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == schemes, "within 5 s")
        #expect(NSApp.appearance == nil && model.systemIsDark == macIsDark)

        // As if the Mac switched.
        NSApp.appearance = NSAppearance(named: macIsDark ? .aqua : .darkAqua)
        defer { NSApp.appearance = nil }
        for _ in 0..<50 where model.systemIsDark == macIsDark { try await Task.sleep(for: .milliseconds(100)) }
        #expect(model.systemIsDark == !macIsDark, "within 5 s")
    }

    @Test func aSchemePerAppearanceStartsFromTheSetAndEndsWhenASetIsChosen() {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        model.choose(ThemeSet.named("Ayu")!)
        model.appearance = .dark
        model.usesSchemePerAppearance = true
        #expect(model.lightScheme.name == "Ayu Light" && model.darkScheme.name == "Ayu Mirage")
        model.darkScheme = Theme.named("Dracula")!
        #expect(model.theme.name == "Dracula")
        #expect(AppModel(defaults: defaults).theme.name == "Dracula", "survives a relaunch")
        model.choose(ThemeSet.named("Nord")!)
        #expect(!model.usesSchemePerAppearance && model.theme.name == "Nord")
    }

    @Test func deletingTheSelectedTaskSelectsTheNextOne() async {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        await model.choose(folder)
        model.show(.loose)
        model.arrowKeyList = AppModel.ArrowKeyList(id: UUID(), paths: ["tasks/Due today.md", "tasks/Loose.md"])
        model.selection = "tasks/Due today.md"
        await model.moveToTrash(["tasks/Due today.md"])
        #expect(model.index["tasks/Due today.md"] == nil)
        #expect(model.selection == "tasks/Loose.md")
        #expect(model.trash.map(\.id) == [".trash/Due today.md"])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: ".trash/Due today.md").path(percentEncoded: false)))
    }

    @Test func aDeletedProjectTakesItsTasksAndComesBackWithThem() async {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        await model.choose(folder)
        model.show(.project("projects/Ta Da MVP.md"))
        await model.moveToTrash(["projects/Ta Da MVP.md"])
        #expect(model.domain == .today)
        #expect(model.index.items.keys.sorted() == ["projects/Shipped.md", "tasks/Loose.md"])
        #expect(Set(model.trash.map(\.id)) == [".trash/Ta Da MVP.md", ".trash/Due today.md", ".trash/Done.md"])

        model.show(.trash)
        model.trashSelection = [".trash/Ta Da MVP.md"]
        await model.restore(model.trashSelection)
        #expect(model.trash.isEmpty && model.trashSelection.isEmpty)
        #expect(model.index.items.count == 5)
        #expect(model.projects.map { "\($0.project.title) \($0.open)/\($0.total)" } == ["Ta Da MVP 1/2"])
        #expect(model.trashNote == "3 items restored to projects/ and tasks/")
    }

    @Test func shiftAndCommandClicksPickSeveralTasksToDelete() async {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        await model.choose(folder)
        let paths = ["tasks/Due today.md", "tasks/Loose.md", "tasks/Done.md"]
        model.arrowKeyList = AppModel.ArrowKeyList(id: UUID(), paths: paths, allowsMultipleSelection: true)
        model.selection = paths[0]
        model.extendSelection(to: paths[2])
        #expect(model.selection == nil && model.multiSelection == Set(paths))
        model.keepPicked(in: [paths[0], paths[1]])
        #expect(model.multiSelection == [paths[0], paths[1]], "tasks the list no longer shows drop out")
        model.extendSelection(to: paths[2])
        model.toggleSelection(paths[1])
        #expect(model.multiSelection == [paths[0], paths[2]])
        model.extendSelection(to: paths[2])
        #expect(model.multiSelection == [paths[1], paths[2]], "a range starts at the last ⌘-clicked task")
        model.extendSelection(to: paths[1])
        #expect(model.selection == paths[1] && model.multiSelection.isEmpty, "a one-task range opens it")
        model.extendSelection(to: paths[0])
        await model.moveToTrash(model.multiSelection.sorted())
        #expect(model.multiSelection.isEmpty && model.errorMessage == nil)
        #expect(model.index.items.keys.sorted() == ["projects/Shipped.md", "projects/Ta Da MVP.md", "tasks/Done.md"])
        #expect(model.trash.count == 2)
    }

    @Test func clicksInTrashPickFilesWithoutOpeningThem() async {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        await model.choose(folder)
        for path in ["tasks/Due today.md", "tasks/Loose.md", "tasks/Done.md"] { await model.moveToTrash([path]) }
        model.show(.trash)
        let paths = model.trash.map(\.id)
        model.arrowKeyList = AppModel.ArrowKeyList(id: UUID(), paths: paths, allowsMultipleSelection: true)
        model.selectOnly(paths[0])
        #expect(model.trashSelection == [paths[0]] && model.selection == nil)
        model.extendSelection(to: paths[2])
        #expect(model.trashSelection == Set(paths))
        model.toggleSelection(paths[1])
        #expect(model.trashSelection == [paths[0], paths[2]])
        #expect(model.moveSelection(by: -1))
        #expect(model.trashSelection == [paths[0]], "the arrow keys pick the row before the last ⌘-clicked one")
        #expect(model.selection == nil && model.multiSelection.isEmpty)
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
