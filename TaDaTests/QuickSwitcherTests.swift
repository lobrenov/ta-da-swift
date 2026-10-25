import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct QuickSwitcherTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "Ta Da/areas/Home.md": "---\ntype: area\n---\n",
            "Ta Da/projects/Sell the Kombi.md": "---\ntype: project\nstatus: Doing\narea: \"[[Home]]\"\n---\n",
            "Ta Da/tasks/Photograph the Kombi.md": "---\ntype: task\nstatus: Doing\nproject: \"[[Sell the Kombi]]\"\n---\n",
            "Ta Da/tasks/Submit timesheet.md": "---\ntype: task\nstatus: Not Started\n---\n",
            "Ta Da/logbook/Kombi service history.md": "---\ntype: task\nstatus: Done\nproject: \"[[Sell the Kombi]]\"\ncompletedDate: 2026-09-14\n---\n",
            "notes/Kombi odometer.md": "Readings.\n",
        ])
    }

    private func search(_ model: AppModel, recent: [String] = []) -> QuickSwitcherSearch {
        let search = QuickSwitcherSearch()
        search.links.source = LinkMenuSource(index: model.index, vault: model.vault, recent: recent)
        return search
    }

    @Test func anEmptyQueryListsRecentFilesWithTheOpenOneAndNoNewTask() async {
        let model = await folder.model()
        let sections = search(model, recent: ["Ta Da/tasks/Submit timesheet.md", "Ta Da/logbook/Kombi service history.md",
                                              "gone.md", "Ta Da/areas/Home.md"]).sections("")
        #expect(sections.map(\.label) == ["Recent"])
        #expect(sections[0].items.map(\.title) == ["Submit timesheet", "Kombi service history", "Home"])
        #expect(search(model).sections(" ").isEmpty)
    }

    @Test func aQueryGroupsMatchesByKindWithLoggedFilesLastAndThenANewTask() async {
        let model = await folder.model()
        let sections = search(model).sections("kombi")
        #expect(sections.map(\.label) == ["Tasks", "Projects", "Notes", nil])
        #expect(sections.map { $0.items.map(\.title) } == [
            ["Photograph the Kombi", "Kombi service history"], ["Sell the Kombi"], ["Kombi odometer"], ["New task “kombi”"],
        ])
        #expect(sections[0].items.map(\.accessibilityValue) == ["Sell the Kombi", "Logbook · Sep"])
        #expect(sections[1].items.map(\.accessibilityValue) == ["Project"])
        #expect(sections.last?.items.first == .newTask("kombi"))
    }

    @Test func recentFilesRankFirstWithinTheirGroup() async {
        let model = await folder.model()
        let sections = search(model, recent: ["Ta Da/tasks/Submit timesheet.md"]).sections("t")
        #expect(sections[0].items.map(\.title).prefix(2) == ["Submit timesheet", "Photograph the Kombi"])
    }

    @Test func switchingToAProjectOrAreaShowsItsBrowserAndATaskOpensWhereItLives() async {
        let model = await folder.model(selecting: "Ta Da/projects/Sell the Kombi.md")
        model.domain = .project("Ta Da/projects/Sell the Kombi.md")
        model.switchTo("Ta Da/projects/Sell the Kombi.md")
        #expect(model.domain == .project("Ta Da/projects/Sell the Kombi.md") && model.selection == nil)
        model.switchTo("Ta Da/areas/Home.md")
        #expect(model.domain == .area("Ta Da/areas/Home.md") && model.selection == nil)
        model.switchTo("Ta Da/tasks/Photograph the Kombi.md")
        #expect(model.domain == .project("Ta Da/projects/Sell the Kombi.md") && model.selection == "Ta Da/tasks/Photograph the Kombi.md")
        model.switchTo("Ta Da/logbook/Kombi service history.md")
        #expect(model.domain == .logbook && model.selection == "Ta Da/logbook/Kombi service history.md")
    }

    @Test func aTitledNewTaskIsFiledInTheShownProjectAndOpened() async throws {
        let model = await folder.model()
        model.open("Ta Da/projects/Sell the Kombi.md")
        await model.newTask(titled: "Clean the seats")

        let path = "Ta Da/tasks/Clean the seats.md"
        #expect(try folder.read(path).contains("project: \"[[Sell the Kombi]]\""))
        #expect(model.domain == .project("Ta Da/projects/Sell the Kombi.md") && model.selection == path)
        #expect(model.titleFocus == nil)
    }

    @Test func aTitledNewTaskElsewhereOpensInLooseTasks() async throws {
        let model = await folder.model()
        model.show(.logbook)
        await model.newTask(titled: "Renew the rego")
        #expect(model.domain == .loose && model.selection == "Ta Da/tasks/Renew the rego.md")
    }
}
