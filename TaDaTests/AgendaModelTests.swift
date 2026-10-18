import Foundation
import Testing
import TaDaCore
@testable import TaDa

/// The Agenda's selection, its lists and settings, and the daily and week notes it opens or creates.
@MainActor
struct AgendaModelTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "tasks/Due today.md": "---\ntype: task\nstatus: Doing\ndueDate: 2026-10-02\n---\n",
            "tasks/Due Monday.md": "---\ntype: task\nstatus: Doing\ndueDate: 2026-10-05\n---\n",
            "periodic notes/daily notes/2026-10-02.md": "- [ ] Call\n",
            "Templates/Daily.md": "---\ntype: note\n---\n## Plan\n- [ ] \n",
        ])
    }

    @Test func opensOnTodayAndFollowsANewDay() async {
        let model = await folder.model(today: LocalDate("2026-10-02")!)
        #expect(model.domain == .agenda && model.agendaSelection == .day(LocalDate("2026-10-02")!) && !model.agendaMonthOpen)

        model.today = LocalDate("2026-10-03")!
        #expect(model.agendaSelection == .day(LocalDate("2026-10-03")!), "it was on the old today")

        model.agendaSelection = .day(LocalDate("2026-10-10")!)
        model.today = LocalDate("2026-10-04")!
        #expect(model.agendaSelection == .day(LocalDate("2026-10-10")!), "another day stays")
        model.agendaSelection = .week(LocalDate("2026-10-10")!.isoWeek)
        model.today = LocalDate("2026-10-05")!
        #expect(model.agendaSelection == .week(LocalDate("2026-10-10")!.isoWeek))
    }

    @Test func steppingMovesADayOrAWeek() async {
        let model = await folder.model(today: LocalDate("2026-10-02")!)
        model.stepAgenda(by: -3)
        #expect(model.agendaSelection == .day(LocalDate("2026-09-29")!))
        model.stepAgenda(by: 5)
        #expect(model.agendaSelection == .day(LocalDate("2026-10-04")!))
        model.showAgendaToday()
        #expect(model.agendaSelection == .day(LocalDate("2026-10-02")!))

        model.agendaSelection = .week(LocalDate("2026-12-28")!.isoWeek)
        model.stepAgenda(by: 1)
        #expect(model.agendaSelection == .week(LocalDate("2027-01-04")!.isoWeek))
        model.stepAgenda(by: -2)
        #expect(model.agendaSelection == .week(LocalDate("2026-12-21")!.isoWeek))
    }

    @Test func theListsAndMarksFollowTheSelection() async {
        let model = await folder.model(today: LocalDate("2026-10-01")!)
        #expect(model.agendaTasks.isEmpty)

        model.agendaSelection = .day(LocalDate("2026-10-02")!)
        #expect(model.agendaTasks.map(\.title) == ["Due today"])
        #expect(model.agendaMarks[LocalDate("2026-10-02")!]?.hasOpenTasks == true && model.agendaMarks[LocalDate("2026-10-02")!]?.hasOpenBoxes == true)

        model.agendaSelection = .week(LocalDate("2026-10-02")!.isoWeek)
        #expect(model.agendaTasks.isEmpty && model.agendaWeekEntries.map(\.item.title) == ["Due today"], "Monday the 5th is the next week")
        #expect(model.agendaMarks[LocalDate("2026-10-05")!] == nil, "outside the shown week")

        model.agendaMonthOpen = true
        #expect(model.agendaMarks[LocalDate("2026-10-05")!]?.hasOpenTasks == true && model.agendaMarks[LocalDate("2026-10-05")!]?.hasOpenBoxes == false)
    }

    @Test func aNewTaskIsDueOnTheSelectedDayOrTodayForAWeek() async throws {
        let model = await folder.model(today: LocalDate("2026-10-03")!)
        model.agendaSelection = .day(LocalDate("2026-10-09")!)
        await model.newTask()
        let first = try #require(model.selection.flatMap { model.index[$0] })
        #expect(model.domain == .agenda && first.properties.dueDate == LocalDate("2026-10-09"))

        model.agendaSelection = .week(LocalDate("2026-10-09")!.isoWeek)
        await model.newTask()
        let second = try #require(model.selection.flatMap { model.index[$0] })
        #expect(second.properties.dueDate == LocalDate("2026-10-03"))

        model.agendaSelection = .day(LocalDate("2026-10-12")!)
        await model.makeDueOnAgendaDay([first.path])
        #expect(model.index[first.path]?.properties.dueDate == LocalDate("2026-10-12"))
    }

    @Test func settingsStartAtTheirDefaultsAndAreKept() async {
        let model = AppModel(defaults: folder.defaults)
        #expect(model.dailyNoteNames == DailyNoteNames(dailyFolder: "Periodic Notes/Daily Notes", weekFolder: "Periodic Notes/Weekly Notes"))
        #expect(model.weekNotes && model.dailyTemplate == nil && model.weekTemplate == nil)

        model.dailyFolder = "Journal"
        model.weekFolder = ""
        model.weekNotes = false
        model.dailyTemplate = "Templates/Daily.md"
        let reopened = AppModel(defaults: folder.defaults)
        #expect(reopened.dailyNoteNames == DailyNoteNames(dailyFolder: "Journal", weekFolder: ""))
        #expect(!reopened.weekNotes && reopened.dailyTemplate == "Templates/Daily.md" && reopened.weekTemplate == nil)
    }

    @Test func openingADaysNoteFindsItInAFolderOfAnotherCase() async throws {
        let model = await folder.model(today: LocalDate("2026-10-02")!)
        await model.openOrCreateNote(for: .day(LocalDate("2026-10-02")!))
        #expect(model.selection == "periodic notes/daily notes/2026-10-02.md")
        #expect(!FileManager.default.fileExists(atPath: folder.url.appending(path: "Periodic Notes/Daily Notes/2026-10-02 2.md").path))
    }

    @Test func aMissingNoteIsCreatedOnceWithTheTemplateAndItsFolders() async throws {
        let model = await folder.model(today: LocalDate("2026-10-02")!)
        model.dailyFolder = "Journal/Days"
        model.dailyTemplate = "Templates/Daily.md"
        let day = LocalDate("2026-10-03")!
        await model.openOrCreateNote(for: .day(day))
        #expect(model.selection == "Journal/Days/2026-10-03.md")
        #expect(try folder.read("Journal/Days/2026-10-03.md") == NewFile.dailyNote(template: "---\ntype: note\n---\n## Plan\n- [ ] \n", today: model.today))
        #expect(try folder.read("Journal/Days/2026-10-03.md").hasSuffix("## Plan\n- [ ] \n"))
        #expect(model.index.dailyNote(for: day, names: model.dailyNoteNames) != nil)

        model.selection = nil
        await model.openOrCreateNote(for: .day(day))
        #expect(model.selection == "Journal/Days/2026-10-03.md")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.appending(path: "Journal/Days").path) == ["2026-10-03.md"])
    }

    @Test func aWeekNoteUsesItsOwnFolderAndTemplate() async throws {
        let model = await folder.model(today: LocalDate("2026-10-02")!)
        model.weekTemplate = "Templates/Missing.md"
        let week = LocalDate("2026-10-02")!.isoWeek
        await model.openOrCreateNote(for: .week(week))
        #expect(model.selection == "periodic notes/Weekly Notes/2026-W40.md")
        #expect(try folder.read("Periodic Notes/Weekly Notes/2026-W40.md") == NewFile.dailyNote(template: nil, today: model.today),
                "a template that can't be read is left out")
    }

    @Test func aNameTakenOnDiskButNotIndexedIsSelectedNotNumbered() async throws {
        let model = await folder.model(today: LocalDate("2026-10-02")!)
        try folder.write("Typed elsewhere\n", "Periodic Notes/Daily Notes/2026-10-04.md")
        await model.openOrCreateNote(for: .day(LocalDate("2026-10-04")!))
        #expect(model.selection == "periodic notes/daily notes/2026-10-04.md", "the file as the folder is on disk")
        #expect(try folder.read("Periodic Notes/Daily Notes/2026-10-04.md") == "Typed elsewhere\n")
    }

    @Test func aNewNoteGoesInTheExistingFolderInItsOwnCase() async throws {
        let model = await folder.model(today: LocalDate("2026-10-02")!)
        // Only "periodic notes/daily notes" exists, in lower case.
        await model.openOrCreateNote(for: .day(LocalDate("2026-10-03")!))
        #expect(model.selection == "periodic notes/daily notes/2026-10-03.md")
        #expect(model.index["periodic notes/daily notes/2026-10-03.md"] != nil)

        model.weekFolder = "PERIODIC NOTES/Weekly Notes"
        await model.openOrCreateNote(for: .week(LocalDate("2026-10-02")!.isoWeek))
        #expect(model.selection == "periodic notes/Weekly Notes/2026-W40.md", "the folder that exists keeps its case, the rest is as set")
        await model.refresh()
        #expect(model.index.items.keys.filter { $0.lowercased().hasSuffix("2026-w40.md") }.count == 1)
    }

    @Test func tickingABoxInADailyNoteUpdatesItsDot() async throws {
        let model = await folder.model(today: LocalDate("2026-10-02")!)
        let path = "periodic notes/daily notes/2026-10-02.md"
        model.selection = path
        await model.loading?.value
        let document = try #require(model.document)
        #expect(model.agendaMarks[LocalDate("2026-10-02")!]?.hasOpenBoxes == true)
        document.text = "- [x] Call\n"
        #expect(model.agendaMarks[LocalDate("2026-10-02")!]?.hasOpenBoxes != true)
        document.text = "- [x] Call\n- [ ] Write\n"
        #expect(model.agendaMarks[LocalDate("2026-10-02")!]?.hasOpenBoxes == true)
    }
}
