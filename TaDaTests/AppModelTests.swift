import AppKit
import Foundation
import SwiftUI
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct AppModelTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "projects/Ta Da MVP.md": "---\ntype: project\nstatus: Doing\n---\n",
            "projects/Shipped.md": "---\ntype: project\nstatus: Done\n---\n",
            "tasks/Due today.md": "---\ntype: task\nstatus: Doing\ndueDate: 2026-10-02\nproject: \"[[Ta Da MVP]]\"\n---\n",
            "tasks/Done.md": "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nproject: \"[[Ta Da MVP]]\"\n---\n",
            "tasks/Loose.md": "---\ntype: task\nstatus: Not Started\ndeadline: 2026-09-30\n---\n",
            "notes/Note.md": "Just a note\n",
        ])
    }

    @Test func startsWithoutAFolder() async {
        let model = AppModel(defaults: folder.defaults)
        await model.start()
        #expect(model.state == .noFolder)
    }

    @Test func choosingAFolderLoadsItAndCounts() async {
        let model = await folder.model(today: LocalDate("2026-10-02")!)
        #expect(model.state == .ready)
        #expect(model.index.items.count == 5)
        #expect(model.todayCount == 2, "open tasks only; Done-today doesn't count")
        #expect(model.looseCount == 1)
        #expect(model.projects.map { "\($0.project.title) \($0.open)/\($0.total)" } == ["Ta Da MVP 1/2"])
        #expect(model.folderDisplayName == folder.url.lastPathComponent)
    }

    @Test func theListsFollowTheDateTypingAndOutsideChanges() async throws {
        let model = await folder.model(today: LocalDate("2026-10-01")!)
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

        try Data("---\ntype: task\nstatus: Doing\n---\n".utf8).write(to: folder.url.appending(path: "tasks/New.md"))
        await model.refresh()
        #expect(model.looseTasks.map(\.title) == ["New"])
    }

    @Test func theFolderAndThemeSurviveARelaunch() async {
        let first = AppModel(defaults: folder.defaults)
        await first.choose(folder.url)
        first.choose(ThemeSet.named("Nord")!)
        first.appearance = .light

        let second = AppModel(defaults: folder.defaults)
        #expect(second.themeSet.name == "Nord" && second.appearance == .light && second.theme.name == "Nord Light")
        await second.start()
        #expect(second.state == .ready)
        #expect(second.vault?.root.resolvingSymlinksInPath() == folder.url.resolvingSymlinksInPath())
    }

    @Test func aMissingFolderFailsWithAMessage() async throws {
        let first = AppModel(defaults: folder.defaults)
        await first.choose(folder.url)
        try FileManager.default.removeItem(at: folder.url)

        let second = AppModel(defaults: folder.defaults)
        await second.start()
        guard case let .failed(message) = second.state else {
            Issue.record("expected failed, got \(second.state)")
            return
        }
        #expect(message.contains("moved or deleted"))
    }

    @Test func completingAndReopeningChangesOnlyStatusAndCompletedDate() async throws {
        let model = await folder.model(today: LocalDate("2026-10-03")!)
        let url = folder.url.appending(path: "tasks/Due today.md")
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
        let model = await folder.model()
        let stale = try #require(model.index["tasks/Loose.md"])
        // Another app completed it after the index was read.
        let url = folder.url.appending(path: "tasks/Loose.md")
        try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "Not Started", with: "Done")
            .write(to: url, atomically: true, encoding: .utf8)
        await model.toggleCompletion(stale)
        #expect(model.index["tasks/Loose.md"]?.properties.status == .notStarted)
    }

    @Test func aProjectMadeFromTheProjectMenuIsLinkedToTheTask() async throws {
        let model = await folder.model(today: LocalDate("2026-10-06")!)
        await model.newProject(named: "Q4: Launch", linking: ["tasks/Loose.md"])
        #expect(try String(contentsOf: folder.url.appending(path: "projects/Q4 - Launch.md"), encoding: .utf8)
                == "---\ntype: project\nstatus: Not Started\ncreatedDate: 2026-10-06\n---\n")
        #expect(try String(contentsOf: folder.url.appending(path: "tasks/Loose.md"), encoding: .utf8)
                == "---\ntype: task\nstatus: Not Started\ndeadline: 2026-09-30\nproject: \"[[Q4 - Launch]]\"\n---\n")
        #expect(model.index.project(of: try #require(model.index["tasks/Loose.md"]))?.path == "projects/Q4 - Launch.md")
        #expect(model.titleFocus == nil, "the new project's title isn't focused; the task stays open")
    }

    @Test func savingToAMissingFileReportsAnError() async throws {
        let model = await folder.model()
        let item = try #require(model.index["tasks/Loose.md"])
        try FileManager.default.removeItem(at: folder.url.appending(path: "tasks/Loose.md"))
        await model.toggleCompletion(item)
        #expect(model.errorMessage?.contains("Loose") == true)
    }

    @Test func pickingADomainClearsTheSelectionAndProjectsOpenAsPages() async {
        let model = await folder.model()
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

    @Test func autocompleteIsOnUntilASwitchIsTurnedOff() {
        let first = AppModel(defaults: folder.defaults)
        #expect(first.autocomplete == Autocomplete())
        first.autocomplete.formatting = false

        let second = AppModel(defaults: folder.defaults)
        #expect(!second.autocomplete.formatting && second.autocomplete.brackets && second.autocomplete.wikiLinks)
    }

    @Test func unknownThemeNamesFallBackToTomorrow() {
        folder.defaults.set("Monokai", forKey: "themeSet")
        folder.defaults.set("Monokai Light", forKey: "lightScheme")
        folder.defaults.set(true, forKey: "usesSchemePerAppearance")
        folder.defaults.set("Light", forKey: "appearance")
        let model = AppModel(defaults: folder.defaults)
        #expect(model.themeSet.name == "Tomorrow" && model.theme.name == "Tomorrow")
    }

    @Test func theSchemeFollowsTheAppearance() {
        let model = AppModel(defaults: folder.defaults)
        model.choose(ThemeSet.named("Gruvbox")!)
        model.systemIsDark = false
        #expect(model.theme.name == "Gruvbox Light")
        model.systemIsDark = true
        #expect(model.theme.name == "Gruvbox Dark")
        model.appearance = .light
        #expect(model.theme.name == "Gruvbox Light", "a fixed appearance ignores the Mac's")
    }

    @Test func aWindowTakesItsSchemesAppearanceAndTheModelFollowsTheMacs() async throws {
        let model = AppModel(defaults: folder.defaults)
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
        let model = AppModel(defaults: folder.defaults)
        model.choose(ThemeSet.named("Ayu")!)
        model.appearance = .dark
        model.usesSchemePerAppearance = true
        #expect(model.lightScheme.name == "Ayu Light" && model.darkScheme.name == "Ayu Mirage")
        model.darkScheme = Theme.named("Dracula")!
        #expect(model.theme.name == "Dracula")
        #expect(AppModel(defaults: folder.defaults).theme.name == "Dracula", "survives a relaunch")
        model.choose(ThemeSet.named("Nord")!)
        #expect(!model.usesSchemePerAppearance && model.theme.name == "Nord")
    }

    @Test func aNewLinkedTaskIsNotStartedAndLeavesTheProjectPageOpen() async throws {
        let model = await folder.model()
        model.open("projects/Ta Da MVP.md")
        let project = try #require(model.index["projects/Ta Da MVP.md"])
        await model.newLinkedTask(in: project)

        let task = try #require(model.index.tasks(in: project).first { $0.title == "Untitled" })
        #expect(task.properties.status == .notStarted)
        #expect(try folder.read(task.path).contains("project: \"[[Ta Da MVP]]\""))
        #expect(model.selection == "projects/Ta Da MVP.md" && model.domain == .project("projects/Ta Da MVP.md"))
        #expect(model.titleFocus == task.path)
    }

    @Test func foldedGroupsSurviveARelaunchAndFollowARename() async {
        let model = await folder.model()
        model.toggleFolded("Completed", in: "projects/Ta Da MVP.md")
        #expect(model.isFolded("Completed", in: "projects/Ta Da MVP.md"))
        #expect(!model.isFolded("Open", in: "projects/Ta Da MVP.md") && !model.isFolded("Completed", in: "projects/Shipped.md"))
        #expect(AppModel(defaults: folder.defaults).isFolded("Completed", in: "projects/Ta Da MVP.md"), "survives a relaunch")

        await model.rename("projects/Ta Da MVP.md", to: "Ta Da 1.0")
        #expect(model.isFolded("Completed", in: "projects/Ta Da 1.0.md"))
        #expect(!model.isFolded("Completed", in: "projects/Ta Da MVP.md"))

        model.toggleFolded("Completed", in: "projects/Ta Da 1.0.md")
        #expect(!model.isFolded("Completed", in: "projects/Ta Da 1.0.md"))
    }

    @Test func deletingTheSelectedTaskSelectsTheNextOne() async {
        let model = await folder.model()
        model.show(.loose)
        model.arrowKeyList = AppModel.ArrowKeyList(id: UUID(), paths: ["tasks/Due today.md", "tasks/Loose.md"])
        model.selection = "tasks/Due today.md"
        await model.moveToTrash(["tasks/Due today.md"])
        #expect(model.index["tasks/Due today.md"] == nil)
        #expect(model.selection == "tasks/Loose.md")
        #expect(model.trash.map(\.id) == [".trash/Due today.md"])
        #expect(FileManager.default.fileExists(atPath: folder.url.appending(path: ".trash/Due today.md").path(percentEncoded: false)))
    }

    @Test func aDeletedProjectTakesItsTasksAndTheyBringItBack() async {
        let model = await folder.model()
        model.show(.project("projects/Ta Da MVP.md"))
        await model.moveToTrash(["projects/Ta Da MVP.md"])
        #expect(model.domain == .today)
        #expect(model.index.items.keys.sorted() == ["projects/Shipped.md", "tasks/Loose.md"])
        #expect(Set(model.trash.map(\.id)) == [".trash/Ta Da MVP.md", ".trash/Due today.md", ".trash/Done.md"])

        model.show(.trash)
        model.trashSelection = [".trash/Due today.md", ".trash/Done.md"]
        await model.restore(model.trashSelection)
        #expect(model.trash.isEmpty && model.trashSelection.isEmpty)
        #expect(model.index.items.count == 5)
        #expect(model.projects.map { "\($0.project.title) \($0.open)/\($0.total)" } == ["Ta Da MVP 1/2"])
        #expect(model.trashNote == "3 items restored to projects/ and tasks/")
    }

    @Test func shiftAndCommandClicksPickSeveralTasksToDelete() async {
        let model = await folder.model()
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
        let model = await folder.model()
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

    @Test func movesActOnTheRowOrEveryPickedTaskInListOrder() async {
        let model = await folder.model()
        let paths = ["projects/Ta Da MVP.md", "tasks/Loose.md", "tasks/Due today.md", "tasks/Done.md"]
        model.arrowKeyList = AppModel.ArrowKeyList(id: UUID(), paths: paths, allowsMultipleSelection: true)
        model.selection = paths[2]
        #expect(model.moveTargets() == [paths[2]], "the open task")
        #expect(model.moveTargets(for: paths[1]) == [paths[1]], "a row that isn't picked")
        model.selection = paths[0]
        #expect(model.moveTargets().isEmpty, "projects don't move")

        model.extendSelection(to: paths[3])
        #expect(model.moveTargets() == [paths[1], paths[2], paths[3]], "picked tasks, in list order, without the project")
        #expect(model.moveTargets(for: paths[3]) == [paths[1], paths[2], paths[3]], "a picked row takes the others")
    }

    @Test func datesActOnProjectsToo() async {
        let model = await folder.model()
        let paths = ["projects/Ta Da MVP.md", "tasks/Loose.md", "tasks/Due today.md"]
        model.arrowKeyList = AppModel.ArrowKeyList(id: UUID(), paths: paths, allowsMultipleSelection: true)
        model.selection = paths[0]
        #expect(model.dateTargets() == [paths[0]], "the open project")
        #expect(model.dateTargets(for: paths[0]) == [paths[0]], "a right-clicked project")

        model.selection = paths[1]
        model.extendSelection(to: paths[2])
        #expect(model.dateTargets() == [paths[1], paths[2]], "picked tasks, in list order")
    }

    @Test func showMoveMenuAsksTheChipOrTheFirstPickedRow() async {
        let model = await folder.model()
        let paths = ["tasks/Loose.md", "tasks/Due today.md"]
        model.arrowKeyList = AppModel.ArrowKeyList(id: UUID(), paths: paths, allowsMultipleSelection: true)
        model.selection = paths[1]
        model.showMoveMenu()
        #expect(model.propertyMenuRequest?.menu == .project)
        #expect(model.propertyMenuRequest?.paths == [paths[1]] && model.propertyMenuRequest?.anchor == paths[1])
        #expect(model.propertyMenuRequest?.onChip == true)

        model.extendSelection(to: paths[0])
        model.showMoveMenu()
        #expect(model.propertyMenuRequest?.paths == paths && model.propertyMenuRequest?.anchor == paths[0])
        #expect(model.propertyMenuRequest?.onChip == false)
    }

    @Test func showDateMenuAsksTheChipOrTheFirstPickedRow() async {
        let model = await folder.model()
        let paths = ["tasks/Loose.md", "tasks/Due today.md"]
        model.arrowKeyList = AppModel.ArrowKeyList(id: UUID(), paths: paths, allowsMultipleSelection: true)
        model.selection = "projects/Ta Da MVP.md"
        model.showDateMenu(.deadline)
        #expect(model.propertyMenuRequest?.menu == .date(.deadline))
        #expect(model.propertyMenuRequest?.paths == ["projects/Ta Da MVP.md"] && model.propertyMenuRequest?.onChip == true)

        model.selection = paths[0]
        model.extendSelection(to: paths[1])
        model.showDateMenu(.due)
        #expect(model.propertyMenuRequest?.menu == .date(.due))
        #expect(model.propertyMenuRequest?.paths == paths && model.propertyMenuRequest?.anchor == paths[0])
        #expect(model.propertyMenuRequest?.onChip == false)
    }

    @Test func settingSeveralDatesWritesOnlyTheOnesThatChange() async throws {
        let model = await folder.model()
        let files = ["tasks/Due today.md", "tasks/Loose.md", "projects/Ta Da MVP.md"]
        let before = try folder.read(files[1])

        await model.setDate(.deadline, to: LocalDate("2026-09-30"), of: files)
        #expect(try folder.read(files[1]) == before, "already on that deadline")
        #expect(model.index[files[0]]?.properties.deadline == LocalDate("2026-09-30"))
        #expect(model.index[files[2]]?.properties.deadline == LocalDate("2026-09-30"), "projects take dates too")

        await model.setDate(.due, to: nil, of: files)
        #expect(try folder.read(files[1]) == before, "had no due date")
        #expect(model.index[files[0]]?.properties.dueDate == nil)
    }

    @Test func movingSeveralTasksWritesOnlyTheOnesThatChange() async throws {
        let model = await folder.model()
        let tasks = ["tasks/Due today.md", "tasks/Loose.md"]
        let before = try folder.read(tasks[0])
        let project = try #require(model.index["projects/Ta Da MVP.md"])

        await model.setParent(project, of: tasks)
        #expect(try folder.read(tasks[0]) == before, "already in the project")
        #expect(try folder.read(tasks[1]) == "---\ntype: task\nstatus: Not Started\ndeadline: 2026-09-30\nproject: \"[[Ta Da MVP]]\"\n---\n")

        await model.setParent(nil, of: tasks)
        #expect(try folder.read(tasks[0]) == before.replacingOccurrences(of: "project: \"[[Ta Da MVP]]\"", with: "project:"))
        #expect(model.looseTasks.map(\.path).sorted() == tasks.sorted())

        await model.makeDueToday(tasks)
        #expect(try folder.read(tasks[1]) == "---\ntype: task\nstatus: Not Started\ndeadline: 2026-09-30\nproject:\ndueDate: 2026-10-03\n---\n")
        #expect(model.index[tasks[0]]?.properties.dueDate == LocalDate("2026-10-03"))
    }

    @Test func aNewProjectFromTheMenuTakesEveryTask() async throws {
        let model = await folder.model()
        await model.newProject(named: "Launch", linking: ["tasks/Due today.md", "tasks/Loose.md"])
        #expect(model.index.tasks(in: try #require(model.index["projects/Launch.md"])).map(\.path).sorted()
                == ["tasks/Due today.md", "tasks/Loose.md"])
    }

    @Test(arguments: [
        ("/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Ta Da", "iCloud Drive/Ta Da"),
        ("/Users/me/Library/Mobile Documents/iCloud~md~obsidian/Documents/Personal", "Obsidian/Personal"),
        ("/Users/me/Projects/Ta Da/SampleVault", "SampleVault"),
    ])
    func folderNamesReadLikeFinder(_ path: String, _ expected: String) {
        #expect(AppModel.displayName(for: URL(filePath: path)) == expected)
    }
}
