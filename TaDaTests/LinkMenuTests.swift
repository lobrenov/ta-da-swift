import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct LinkMenuTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "Ta Da/areas/Home.md": "---\ntype: area\n---\n",
            "Ta Da/projects/Sell the Kombi.md": "---\ntype: project\nstatus: Doing\narea: \"[[Home]]\"\n---\n",
            "Ta Da/tasks/Photograph the Kombi.md": "---\ntype: task\nstatus: Doing\nproject: \"[[Sell the Kombi]]\"\n---\n",
            "Ta Da/tasks/Kombi service history.md": "---\ntype: task\nstatus: Done\nproject: \"[[Sell the Kombi]]\"\n---\n",
            "Ta Da/tasks/Submit timesheet.md": "---\ntype: task\nstatus: Not Started\n---\n",
            "Ta Da/tasks/Fix the gate.md": "---\ntype: task\nstatus: Blocked\narea: \"[[Home]]\"\n---\n",
            "Ta Da/attachments/front.jpg": "x",
            "notes/odometer.png": "x",
        ])
    }

    @Test func openingFilesMakesThemRecentAndRenamingFollows() async throws {
        let model = await folder.model(selecting: "Ta Da/tasks/Submit timesheet.md")
        model.selection = "Ta Da/projects/Sell the Kombi.md"
        await model.loading?.value
        #expect(model.recentFiles == ["Ta Da/projects/Sell the Kombi.md", "Ta Da/tasks/Submit timesheet.md"])
        await model.rename("Ta Da/tasks/Submit timesheet.md", to: "Submit the timesheet")
        #expect(model.recentFiles == ["Ta Da/projects/Sell the Kombi.md", "Ta Da/tasks/Submit the timesheet.md"])
        #expect(AppModel(defaults: folder.defaults).recentFiles == model.recentFiles)
    }

    @Test func anEmptyLinkQueryListsRecentFilesButTheOpenOne() async {
        let model = await folder.model()
        let search = LinkMenuSearch()
        search.source = LinkMenuSource(index: model.index, vault: model.vault, openPath: "Ta Da/tasks/Submit timesheet.md")
        let all = search.choices(.link, query: "")
        #expect(all.label == nil && all.choices.map(\.title) == ["Fix the gate", "Home", "Kombi service history",
                                                                 "Photograph the Kombi", "Sell the Kombi"])
        search.source.recent = ["Ta Da/tasks/Submit timesheet.md", "Ta Da/tasks/Photograph the Kombi.md", "gone.md"]
        let recent = search.choices(.link, query: "")
        #expect(recent.label == "Recent" && recent.choices.map(\.title) == ["Photograph the Kombi"])
    }

    @Test func aLinkQueryRanksRecentFilesFirstAndHintsTheParent() async {
        let model = await folder.model()
        let search = LinkMenuSearch()
        search.source = LinkMenuSource(index: model.index, vault: model.vault, recent: ["Ta Da/tasks/Photograph the Kombi.md"])
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
        #expect(model.attachments.first?.hasPrefix("Ta Da/attachments/Pasted image ") == true)
        #expect(model.embed(.file(folder.url.appending(path: "notes/odometer.png"))) == "![[odometer.png]]")
        #expect(model.attachments.count == 3, "a folder image isn't copied")
        let outside = FileManager.default.temporaryDirectory.appending(path: "front.jpg")
        try Data([3]).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        #expect(model.embed(.file(outside)) == "![[front 2.jpg]]", "a copy numbers a taken name")
        await model.savingImage?.value
        #expect(try Data(contentsOf: folder.url.appending(path: "Ta Da/attachments/front 2.jpg")) == Data([3]))
    }

    #if os(macOS)
    @Test func addLinkListsTheMatchesThenALinkToTheFieldsText() async {
        let model = await folder.model()
        let search = LinkMenuSearch()
        search.source = LinkMenuSource(index: model.index, vault: model.vault)
        let sections = AddLink.sections("kombi", search: search)
        #expect(sections.map { $0.items.map(\.title) } == [["Kombi service history", "Photograph the Kombi", "Sell the Kombi"], ["Link “kombi”"]])
        #expect(sections[0].label == "Add Link" && sections[1].label == nil)
        let none = AddLink.sections(" crash reporting ", search: search)
        #expect(none.map { $0.items.map(\.title) } == [["Link “crash reporting”"]])
        #expect(none[0].items[0].accessibilityValue == "New")
        #expect(AddLink.sections("", search: search).flatMap(\.items).allSatisfy { if case .file = $0 { true } else { false } })
        #expect(AddLink.sections("a|b", search: search).flatMap(\.items).allSatisfy { if case .file = $0 { true } else { false } })
    }

    @Test func addLinkWritesTheSelectionAsTheAlias() async throws {
        let model = await folder.model()
        let search = LinkMenuSearch()
        search.source = LinkMenuSource(index: model.index, vault: model.vault)
        let choice = try #require(AddLink.sections("sell", search: search)[0].items.first)
        #expect(AddLink.markdown(choice, selection: "selling the van") == "[[Sell the Kombi|selling the van]]")
        #expect(AddLink.markdown(choice, selection: "sell the kombi") == "[[Sell the Kombi]]", "a case-only difference")
        #expect(AddLink.markdown(.new("crash reporting"), selection: "crash reporting") == "[[crash reporting]]")
        #expect(AddLink.markdown(.new("release plan"), selection: "release notes") == "[[release plan|release notes]]")
    }
    #endif
}
