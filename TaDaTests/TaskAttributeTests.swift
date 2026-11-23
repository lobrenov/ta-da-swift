import Foundation
import MarkdownEngine
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

    @Test func removingAnAttributeTakesASpaceWithIt() {
        func removed(_ text: String, _ source: String) -> String? {
            let ns = text as NSString
            return TaskAttributeText.removalRange(of: source, at: ns.range(of: source), in: text).map { ns.replacingCharacters(in: $0, with: "") }
        }
        #expect(removed("- [ ] Buy milk >2026-10-09", ">2026-10-09") == "- [ ] Buy milk")
        #expect(removed("- [ ] >2026-10-09 Buy milk", ">2026-10-09") == "- [ ] Buy milk")
        #expect(removed("- [ ] Buy >2026-10-09 milk", ">2026-10-09") == "- [ ] Buy milk")
        #expect(removed("- [ ] Buy @[[Home]]", "@[[Home]]") == "- [ ] Buy")
        #expect(TaskAttributeText.removalRange(of: ">2026-10-09", at: NSRange(location: 0, length: 3), in: "- [ ] x") == nil)
    }

    @Test func theBarOffersAttributesOnSubtaskLinesOnly() {
        let text = "Notes\n- [ ] Buy milk\n- plain\n> quote\n- [x] Done\n"
        func on(_ marker: String) -> Bool {
            TaskAttributeText.isSubtaskLine(in: text, at: (text as NSString).range(of: marker).location + 2)
        }
        #expect(on("Buy milk") && on("Done"))
        #expect(!on("Notes") && !on("plain") && !on("quote"))
    }

    @Test func chipsLabelDatesAsTaskRowsDoAndTintOverdueOnes() {
        let theme = Theme.all[0]
        let style = LiveEditor.taskAttributeStyle(theme: theme, index: index(), today: today)
        let due = style.due("2026-10-02")
        #expect(due.label == "Today" && due.tint == theme.accent)
        #expect(style.due("2026-10-04").label == LocalDate("2026-10-04")!.rowLabel(today: today))
        let overdue = style.due("2026-10-01")
        #expect(overdue.label == LocalDate("2026-10-01")!.rowLabel(today: today) && overdue.tint == theme.deadline)
        #expect(style.due("2026-10-09").tint == theme.accent)
    }

    @Test func parentChipsDrawTheirIconInLinkAndUnresolvedOnesStruckAndMuted() {
        let theme = Theme.all[0]
        let style = LiveEditor.taskAttributeStyle(theme: theme, index: index(), today: today)
        for title in ["Ta Da MVP", "Home"] {
            let chip = style.parent(title, nil)
            #expect(chip.label == title && chip.tint == theme.link && !chip.strikethrough && chip.drawIcon != nil, "\(title)")
        }
        for title in ["Nowhere", "Plan"] {
            let chip = style.parent(title, nil)
            #expect(chip.label == title && chip.tint == theme.muted && chip.strikethrough && chip.drawIcon == nil, "\(title): not a project or area")
        }
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
}
