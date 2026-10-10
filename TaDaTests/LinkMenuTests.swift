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
        search.source = LinkMenuSource(index: model.index, vault: model.vault, attachments: model.attachments)
        let all = search.choices(.embed, query: "")
        #expect(all.label == "Attachments" && Set(all.choices.map(\.title)) == ["front.jpg", "odometer.png"])
        let od = search.choices(.embed, query: "od").choices
        #expect(od.map(\.markdown) == ["![[odometer.png]]"])
    }

    @Test func anEmbedChoiceUsesThePathWhenTheFilenameFindsAnotherImage() async throws {
        try folder.write("x", "notes/front.jpg")
        let model = await folder.model()
        let search = LinkMenuSearch()
        search.source = LinkMenuSource(index: model.index, vault: model.vault, attachments: model.attachments)
        #expect(Set(search.choices(.embed, query: "front").choices.map(\.markdown)) == ["![[front.jpg]]", "![[notes/front.jpg]]"])
    }

    @Test func pastedImagesAreSavedInAttachmentsAndFolderImagesAreEmbeddedWhereTheyAre() async throws {
        let model = await folder.model()
        let pasted = try #require(model.embed(.data(Data([1, 2]), extension: "png")))
        await model.savingImage?.value
        #expect(pasted.hasPrefix("![[Pasted image ") && pasted.hasSuffix(".png]]"))
        #expect(model.attachments.first?.hasPrefix("attachments/Pasted image ") == true)
        #expect(model.embed(.file(folder.url.appending(path: "notes/odometer.png"))) == "![[odometer.png]]")
        #expect(model.attachments.count == 3, "a folder image isn't copied")
        let outside = FileManager.default.temporaryDirectory.appending(path: "front.jpg")
        try Data([3]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        #expect(model.embed(.file(outside)) == "![[front 2.jpg]]", "a copy numbers a taken name")
        await model.savingImage?.value
        #expect(try Data(contentsOf: folder.url.appending(path: "attachments/front 2.jpg")) == Data([3]))
    }
}
