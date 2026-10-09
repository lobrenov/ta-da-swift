import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct LinkMenuTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "areas/Home.md": "---\ntype: area\n---\n",
            "projects/Sell the Kombi.md": "---\ntype: project\nstatus: Doing\narea: \"[[Home]]\"\n---\n",
            "tasks/Photograph the Kombi.md": "---\ntype: task\nstatus: Doing\nproject: \"[[Sell the Kombi]]\"\n---\n",
            "tasks/Kombi service history.md": "---\ntype: task\nstatus: Done\nproject: \"[[Sell the Kombi]]\"\n---\n",
            "tasks/Submit timesheet.md": "---\ntype: task\nstatus: Not Started\n---\n",
            "tasks/Fix the gate.md": "---\ntype: task\nstatus: Blocked\narea: \"[[Home]]\"\n---\n",
            "attachments/front.jpg": "x",
            "notes/odometer.png": "x",
        ])
    }

    @Test func openingFilesMakesThemRecentAndRenamingFollows() async throws {
        let model = await folder.model(selecting: "tasks/Submit timesheet.md")
        model.selection = "projects/Sell the Kombi.md"
        await model.loading?.value
        #expect(model.recentFiles == ["projects/Sell the Kombi.md", "tasks/Submit timesheet.md"])
        await model.rename("tasks/Submit timesheet.md", to: "Submit the timesheet")
        #expect(model.recentFiles == ["projects/Sell the Kombi.md", "tasks/Submit the timesheet.md"])
        #expect(AppModel(defaults: folder.defaults).recentFiles == model.recentFiles)
    }

    @Test func anEmptyLinkQueryListsRecentFilesButTheOpenOne() async {
        let model = await folder.model()
        let search = LinkMenuSearch()
        search.source = LinkMenuSource(index: model.index, vault: model.vault, openPath: "tasks/Submit timesheet.md")
        let all = search.choices(.link, query: "")
        #expect(all.label == nil && all.choices.map(\.title) == ["Fix the gate", "Home", "Kombi service history",
                                                                 "Photograph the Kombi", "Sell the Kombi"])
        search.source.recent = ["tasks/Submit timesheet.md", "tasks/Photograph the Kombi.md", "gone.md"]
        let recent = search.choices(.link, query: "")
        #expect(recent.label == "Recent" && recent.choices.map(\.title) == ["Photograph the Kombi"])
    }

    @Test func aLinkQueryRanksRecentFilesFirstAndHintsTheParent() async {
        let model = await folder.model()
        let search = LinkMenuSearch()
        search.source = LinkMenuSource(index: model.index, vault: model.vault, recent: ["tasks/Photograph the Kombi.md"])
        let choices = search.choices(.link, query: "kombi").choices
        #expect(choices.map(\.title) == ["Kombi service history", "Photograph the Kombi", "Sell the Kombi"])
        #expect(choices.map(\.hint) == ["Sell the Kombi", "Sell the Kombi", "Project"])
        #expect(choices.map(\.markdown).last == "[[Sell the Kombi]]")
        let hints = search.choices(.link, query: "").choices.map { "\($0.title): \($0.hint)" }
        #expect(hints == ["Photograph the Kombi: Sell the Kombi"])
        search.source.recent = []
        #expect(search.choices(.link, query: "e").choices.map(\.hint).contains("Loose task"))
        #expect(search.choices(.link, query: "gate").choices.map(\.hint) == ["Home"])
        #expect(search.choices(.link, query: "home").choices.map(\.hint) == ["Area"])
    }

    @Test func anEmbedQueryListsTheFoldersImages() async {
        let model = await folder.model()
        let search = LinkMenuSearch()
        search.source = LinkMenuSource(index: model.index, vault: model.vault)
        let all = search.choices(.embed, query: "")
        #expect(all.label == "Attachments" && Set(all.choices.map(\.title)) == ["front.jpg", "odometer.png"])
        let od = search.choices(.embed, query: "od").choices
        #expect(od.map(\.markdown) == ["![[odometer.png]]"])
    }
}
