import Foundation
import Testing
import TaDaCore
@testable import TaDa

/// What the `>` and `@` queries list and write, the chips' look, and Extract to Task with attributes.
@MainActor
struct TaskAttributeTests {
    /// Friday 2 October 2026.
    let today = LocalDate("2026-10-02")!

    private func dates(_ query: String) -> [DateChoice] {
        DateChoice.choices(query: query, today: today, firstWeekday: 2, order: .dayMonth, includesPick: true)
    }

    @Test func fridayOnAFridayIsTodayAndComesFirst() {
        let choices = dates("fri")
        #expect(choices.first?.kind == .typed)
        #expect(choices.first?.markdown == ">2026-10-02 ")
        #expect(choices.map(\.kind) == [.typed, .tomorrow, .nextWeek, .pick], "Today isn't listed twice")
    }

    @Test func aPhraseGivesItsDayAndAnEmptyQueryTheQuickRows() {
        #expect(dates("next fri").first?.markdown == ">2026-10-02 ", "a weekday is its soonest coming day, today included")
        #expect(dates("sat").map(\.kind) == [.typed, .today, .nextWeek, .pick])
        #expect(dates("2026-12-25").first?.markdown == ">2026-12-25 ")
        let quick = dates("")
        #expect(quick.map(\.title) == ["Today", "Tomorrow", "Next week", "Pick a date…"])
        #expect(quick.compactMap(\.token) == [">2026-10-02", ">2026-10-03", ">2026-10-05"])
        #expect(dates("zzz").map(\.kind) == [.today, .tomorrow, .nextWeek, .pick], "text that isn't a date adds no typed row")
    }

    private func index() -> VaultIndex {
        let files = [
            ("Ta Da/projects/Ta Da MVP.md", "---\ntype: project\nstatus: Doing\n---\n"),
            ("Ta Da/projects/Garden Shed.md", "---\ntype: project\nstatus: Doing\narea: \"[[Home]]\"\n---\n"),
            ("Ta Da/projects/Shipped.md", "---\ntype: project\nstatus: Done\n---\n"),
            ("Ta Da/areas/Home.md", "---\ntype: area\n---\n"),
            ("Ta Da/areas/Work.md", "---\ntype: area\n---\n"),
            ("Ta Da/tasks/Plan.md", "---\ntype: task\nstatus: Doing\nproject: \"[[Ta Da MVP]]\"\n---\n"),
        ]
        return VaultIndex(files.compactMap { Item(parsing: $0.1, path: $0.0) })
    }

    @Test func parentsAreProjectsAndAreasFilteredByTheQuery() {
        let index = index()
        #expect(ParentChoice.choices(index: index, query: "").map(\.title) == ["Ta Da MVP", "Home", "Garden Shed", "Work"],
                "no Loose tasks, no done project, no New project without a name")
        #expect(ParentChoice.choices(index: index, query: "ta").map(\.title) == ["Ta Da MVP", "ta"], "a name ends with New project")
        let shed = ParentChoice.choices(index: index, query: "shed")
        #expect(shed.map(\.title) == ["Garden Shed", "shed"])
        #expect(shed.map(\.kind).last == .new)
        #expect(shed.first?.markdown == "@[[Garden Shed]] ")
        #expect(shed.first?.token == "@[[Garden Shed]]")
        if case .project(_, _, let open) = ParentChoice.choices(index: index, query: "mvp")[0].kind { #expect(open == 1) } else { Issue.record("not a project") }
        #expect(ParentChoice.choices(index: index, query: "home").first?.kind == .area)
    }

    @Test func removingAnAttributeTakesTheSpaceCoreTakes() {
        func removed(_ text: String, _ source: String) -> String? {
            let ns = text as NSString
            return TaskAttributeText.removalRange(of: source, isDue: source.hasPrefix(">"), at: ns.range(of: source), in: text)
                .map { ns.replacingCharacters(in: $0, with: "") }
        }
        #expect(removed("- [ ] Buy milk >2026-10-09", ">2026-10-09") == "- [ ] Buy milk")
        #expect(removed("- [ ] >2026-10-09 Buy milk", ">2026-10-09") == "- [ ] Buy milk", "first after the box: the space after it")
        #expect(removed("- [ ] Buy >2026-10-09 milk", ">2026-10-09") == "- [ ] Buy milk", "else the space before it")
        #expect(removed("- [ ] Buy @[[Home]]\n- [ ] Next", "@[[Home]]") == "- [ ] Buy\n- [ ] Next")
        #expect(TaskAttributeText.removalRange(of: ">2026-10-09", isDue: true, at: NSRange(location: 0, length: 3), in: "- [ ] x") == nil)
        #expect(TaskAttributeText.removalRange(of: ">2026-10-09", isDue: true, at: NSRange(location: 0, length: 11), in: ">2026-10-09") == nil, "not a subtask line")
    }

    @Test func returnPicksOnlyWhatTheUserMeant() {
        #expect(DateChoice.highlight(in: dates("fri")) == 0)
        #expect(DateChoice.highlight(in: dates("")) == nil, "no day typed: ↵ is a newline")
        #expect(DateChoice.highlight(in: dates("zzz")) == nil)
        let index = index()
        #expect(ParentChoice.highlight(in: ParentChoice.choices(index: index, query: "mvp")) == 0)
        #expect(ParentChoice.highlight(in: ParentChoice.choices(index: index, query: "zzz")) == nil, "only New project: needs a click or an arrow")
    }

    @Test func extractTakesTheDueDateAndTheNamedParentOverTheHosts() async throws {
        let folder = try TestFolder([
            "Ta Da/projects/Launch.md": "---\ntype: project\nstatus: Doing\n---\n",
            "Ta Da/areas/Home.md": "---\ntype: area\n---\n",
            "Meetings/Kickoff.md": "- [ ] Book venue >2026-10-09 @[[Launch]]\n- [ ] Water plants @[[Home]]\n- [ ] Nothing\n",
        ])
        let model = await folder.model(today: today)
        func extract(_ title: String) async throws -> (extracted: AppModel.Extracted, text: String) {
            let text = try folder.read("Meetings/Kickoff.md")
            let line = (text as NSString).range(of: title).location
            let extract = try #require(SubtaskExtraction.extract(lineAt: line, in: text))
            let extracted = try #require(await model.extractTask(extract, from: "Meetings/Kickoff.md"))
            return (extracted, try folder.read(extracted.path))
        }

        let venue = try await extract("Book venue")
        #expect(venue.extracted.parent == "Launch")
        #expect(venue.text.contains("project: \"[[Launch]]\"") && venue.text.contains("dueDate: 2026-10-09"))
        let plants = try await extract("Water plants")
        #expect(plants.extracted.parent == "Home")
        #expect(plants.text.contains("area: \"[[Home]]\""))
        let nothing = try await extract("Nothing")
        #expect(nothing.extracted.parent == nil)
    }

    @Test func newProjectReturnsTheProjectItMade() async throws {
        let folder = try TestFolder(["Ta Da/areas/Home.md": "---\ntype: area\n---\n"])
        let model = await folder.model(today: today)
        let project = try #require(await model.newProject(named: "Garden Shed", linking: []))
        #expect(project.title == "Garden Shed" && project.properties.kind == .project)
        #expect(model.index.parentItem(titled: "Garden Shed")?.path == project.path)
    }

    @Test func tickingALineThatChangedWritesNothingAndSaysSo() async throws {
        let folder = try TestFolder(["Meetings/Kickoff.md": "- [ ] Book venue\n"])
        let model = await folder.model(today: today)
        let box = try #require(model.index["Meetings/Kickoff.md"]?.checkboxes.first)
        #expect(await model.tick(box, in: "Meetings/Kickoff.md"))
        #expect(model.errorMessage == nil)
        #expect(try folder.read("Meetings/Kickoff.md") == "- [x] Book venue\n")
        #expect(await model.tick(box, in: "Meetings/Kickoff.md") == false, "the stale box no longer matches")
        #expect(model.errorMessage?.contains("Book venue") == true)
        #expect(try folder.read("Meetings/Kickoff.md") == "- [x] Book venue\n")
    }

    @Test func staleTicksAreDropped() {
        let tick = SubtaskCards.Tick(path: "A.md", line: 3, marker: " ", text: "Book venue")
        func lines(_ line: Int, _ text: String) -> [String: [Checkbox]] { ["A.md": [Checkbox(marker: " ", lineIndex: line, column: 3, text: text)]] }
        #expect(SubtaskCards.current([tick], in: lines(3, "Book venue")) == [tick])
        #expect(SubtaskCards.current([tick], in: [:]).isEmpty, "the line left the list")
        #expect(SubtaskCards.current([tick], in: lines(4, "Book venue")).isEmpty, "another line now")
        #expect(SubtaskCards.current([tick], in: lines(3, "Book hall")).isEmpty)
    }

    @Test func datingALineUpdatesTheDotsAndTheParentCardsAreStored() async throws {
        let folder = try TestFolder([
            "Ta Da/projects/Launch.md": "---\ntype: project\nstatus: Doing\n---\n",
            "Meetings/Kickoff.md": "- [ ] Book venue @[[Launch]]\n- [ ] Call\n",
        ])
        let model = await folder.model(today: today)
        model.noteSubtasks = true
        let launch = try #require(model.index["Ta Da/projects/Launch.md"])
        #expect(model.subtaskCards(of: launch).flatMap(\.lines).map(\.title) == ["Book venue"])
        #expect(model.parentSubtasks[launch.path]?.count == 1)
        let day = LocalDate("2026-10-03")!
        #expect(model.agendaMarks[day]?.hasOpenTasks != true)

        await model.edit("Meetings/Kickoff.md") { $0.replacingOccurrences(of: "- [ ] Call", with: "- [ ] Call >2026-10-03") }
        #expect(model.agendaMarks[day]?.hasOpenTasks == true, "a date added to a line shows its dot")
    }
}
