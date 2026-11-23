import Foundation
import Testing
import TaDaCore
@testable import TaDa

/// Subtask lines from notes as cards: where the model places them, what ticking writes, and the setting.
@MainActor
struct SubtaskCardsModelTests {
    let folder: TestFolder
    let today = LocalDate("2026-10-03")!

    init() throws {
        folder = try TestFolder([
            "Ta Da/projects/Launch.md": "---\ntype: project\nstatus: Doing\n---\n",
            "Ta Da/areas/Home.md": "---\ntype: area\n---\n",
            "Meetings/Kickoff.md": "- [ ] Book venue >2026-10-03 @[[Launch]]\n- [ ] Overdue >2026-10-01\n- [ ] Next week >2026-10-09\n"
                + "- [ ] Chase @[[Home]]\n- [ ] Loose line\n- [x] Done line >2026-10-03\n",
            "Ta Da/tasks/Own.md": "---\ntype: task\nstatus: Doing\n---\n- [ ] Dated subtask >2026-10-03\n- [ ] Plain subtask\n",
        ])
    }

    private func texts(_ cards: [SubtaskCard]) -> [String] { cards.flatMap(\.lines).map(\.title) }

    @Test func offByDefaultShowsNothing() async {
        let model = await folder.model(today: today)
        #expect(!model.noteSubtasks)
        #expect(model.agendaSubtasks.isEmpty && model.looseSubtasks.isEmpty)
        #expect(model.subtaskCards(of: model.index["Ta Da/projects/Launch.md"]!).isEmpty)
        #expect(model.agendaMarks[LocalDate("2026-10-03")!]?.hasOpenTasks != true)
    }

    @Test func listsPlaceLinesByDateParentAndLoose() async {
        let model = await folder.model(today: today)
        model.noteSubtasks = true

        #expect(texts(model.agendaSubtasks) == ["Book venue", "Overdue", "Dated subtask"], "Today's, with the overdue one; cards by file title")
        #expect(texts(model.looseSubtasks) == ["Loose line"])
        #expect(texts(model.subtaskCards(of: model.index["Ta Da/projects/Launch.md"]!)) == ["Book venue"])
        #expect(texts(model.subtaskCards(of: model.index["Ta Da/areas/Home.md"]!)) == ["Chase"])
        #expect(model.agendaMarks[LocalDate("2026-10-03")!]?.hasOpenTasks == true)

        model.agendaSelection = .week(today.isoWeek)
        #expect(texts(model.agendaSubtasks) == ["Book venue", "Overdue", "Dated subtask"], "Monday the 28th to Sunday the 4th")
        #expect(model.subtaskCards(on: LocalDate("2026-10-09")!).flatMap(\.lines).map(\.title) == ["Next week"])
    }

    @Test func tickingWritesOneCharacter() async throws {
        let model = await folder.model(today: today)
        model.noteSubtasks = true
        let card = try #require(model.agendaSubtasks.first { $0.path == "Meetings/Kickoff.md" })
        let box = try #require(card.lines.first { $0.title == "Book venue" })
        let before = try folder.read("Meetings/Kickoff.md")

        await model.tick(box, in: card.path)
        let after = try folder.read("Meetings/Kickoff.md")
        #expect(after == before.replacingOccurrences(of: "- [ ] Book venue", with: "- [x] Book venue"))
        #expect(!texts(model.agendaSubtasks).contains("Book venue"), "the list reloads without it")
    }

    @Test func openingALineQueuesItsScroll() throws {
        let model = AppModel(defaults: folder.defaults)
        let box = Checkbox(marker: " ", lineIndex: 7, column: 3)
        model.open(box, in: "Meetings/Kickoff.md")
        #expect(model.pendingLine == AppModel.PendingLine(path: "Meetings/Kickoff.md", line: 7))
    }

    @Test func settingOffHidesCardsAndDots() async throws {
        let model = await folder.model(today: today)
        model.noteSubtasks = true
        #expect(!model.agendaSubtasks.isEmpty)
        model.noteSubtasks = false
        #expect(model.agendaSubtasks.isEmpty && model.looseSubtasks.isEmpty)
        #expect(model.agendaMarks[LocalDate("2026-10-03")!]?.hasOpenTasks != true)

        model.noteSubtasks = true
        await model.finishSavingSettings()
        let reopened = await folder.model(today: today)
        #expect(reopened.noteSubtasks, "the switch is in Ta Da/settings.json")
    }
}
