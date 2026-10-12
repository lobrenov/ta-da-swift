import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct NoteModelTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "projects/Ark.md": "---\ntype: project\nstatus: Doing\n---\n",
            "Idea.md": "Loose idea\n",
            "Meetings/Ark call.md": "---\ncreatedDate: 2026-10-01\ntags: [work]\n---\n- [ ] Dates\n",
            "Meetings/2026/Standup.md": "Nothing to report.\n",
            "Links.md": "[[Meetings/Ark call]]\n",
        ])
        try FileManager.default.createDirectory(at: folder.url.appending(path: "Empty"), withIntermediateDirectories: true)
    }

    private func tree(_ model: AppModel) -> [String] {
        func describe(_ nodes: [FolderNode]) -> [String] { nodes.flatMap { ["\($0.path) \($0.count)"] + describe($0.children) } }
        return describe(model.folderTree)
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.url.appending(path: path).path(percentEncoded: false))
    }

    @Test func theTreeHasNoteFoldersAndEmptyOnesAndLooseCountsTheTopLevel() async {
        let model = await folder.model()
        #expect(tree(model) == ["Empty 0", "Meetings 2", "Meetings/2026 1"])
        #expect(model.looseNoteCount == 2)
        #expect(model.untaggedCount == 4, "the project and three notes")
    }

    @Test func aFolderPageSwitchesToNotesAndFoldsAreKept() async {
        let model = await folder.model()
        model.show(.folder("Meetings"))
        #expect(model.sidebarMode == .notes && model.shownFolder == "Meetings")
        model.show(.loose)
        #expect(model.sidebarMode == .projects && model.shownFolder == nil)
        model.toggleFolderFolded("Meetings")
        #expect(AppModel(defaults: folder.defaults).isFolderFolded("Meetings"))
    }

    @Test func openingANoteShowsItsFolder() async {
        let model = await folder.model()
        model.openLink(to: "Meetings/2026/Standup.md")
        #expect(model.domain == .folder("Meetings/2026") && model.selection == "Meetings/2026/Standup.md")
    }

    @Test func newNotesAndFoldersGoInTheShownFolder() async throws {
        let model = await folder.model()
        model.show(.folder("Meetings"))
        await model.newNote()
        #expect(model.selection == "Meetings/Untitled.md" && model.titleFocus == "Meetings/Untitled.md")
        #expect(try folder.read("Meetings/Untitled.md") == "---\ncreatedDate: 2026-10-03\ntags: []\n---\n")
        model.show(.loose)
        await model.newNote()
        #expect(model.domain == .folder("") && model.selection == "Untitled.md")
        await model.newTaskOrNote()
        #expect(model.selection == "Untitled 2.md")
        model.show(.loose)
        await model.newTaskOrNote()
        #expect(model.domain == .loose && model.selection == "tasks/Untitled.md")

        model.show(.folder("Meetings"))
        model.toggleFolderFolded("Meetings")
        await model.newFolder()
        #expect(model.folderNameFocus == "Meetings/Untitled folder" && !model.isFolderFolded("Meetings"))
        #expect(tree(model).contains("Meetings/Untitled folder 0"))
    }

    @Test func renamingAFolderMovesTheOpenNoteFoldsAndLinks() async throws {
        let model = await folder.model(selecting: "Meetings/Ark call.md")
        model.show(.folder("Meetings"))
        model.selection = "Meetings/Ark call.md"
        await model.loading?.value
        model.toggleFolderFolded("Meetings/2026")
        await model.renameFolder("Meetings", to: "Calls")
        #expect(model.domain == .folder("Calls") && model.selection == "Calls/Ark call.md")
        #expect(model.document?.path == "Calls/Ark call.md" && model.index["Calls/Ark call.md"] != nil)
        #expect(model.isFolderFolded("Calls/2026") && !model.isFolderFolded("Meetings/2026"))
        #expect(tree(model) == ["Calls 2", "Calls/2026 1", "Empty 0"])
        #expect(try folder.read("Links.md") == "[[Calls/Ark call]]\n")
    }

    @Test func trashingAFolderAsksFirstAndShowsItsParent() async {
        let model = await folder.model()
        model.show(.folder("Meetings/2026"))
        model.trashFolder("Meetings")
        let request = try? #require(model.folderTrashConfirmation)
        #expect(request?.count == 2 && exists("Meetings"))
        if let request { await model.confirmTrashFolder(request) }
        #expect(model.folderTrashConfirmation == nil && !exists("Meetings") && exists(".trash/Meetings/2026/Standup.md"))
        #expect(model.domain == .folder("") && tree(model) == ["Empty 0"])
        #expect(Set(model.trash.map(\.id)) == [".trash/Meetings/Ark call.md", ".trash/Meetings/2026/Standup.md"])
    }

    @Test func aFolderStaysWhenItsLastNoteMoves() async {
        let model = await folder.model()
        await model.moveNote("Meetings/2026/Standup.md", to: "")
        #expect(model.index["Standup.md"] != nil && tree(model) == ["Empty 0", "Meetings 1", "Meetings/2026 0"])
    }

    @Test func convertingANoteOpensItInToDo() async throws {
        let model = await folder.model()
        model.show(.folder("Meetings"))
        await model.convert("Meetings/Ark call.md", to: .task, parent: .project("Ark"))
        #expect(model.domain == .project("projects/Ark.md") && model.selection == "tasks/Ark call.md")
        #expect(model.sidebarMode == .projects && model.index["tasks/Ark call.md"]?.properties.kind == .task)
        #expect(try folder.read("Links.md") == "[[tasks/Ark call]]\n")
    }

    @Test func trashedNotesRestoreToTheirFolder() async {
        let model = await folder.model()
        await model.moveToTrash(["Meetings/Ark call.md", "Idea.md"])
        await model.restore([".trash/Meetings/Ark call.md", ".trash/Idea.md"])
        #expect(model.index["Meetings/Ark call.md"] != nil && model.index["Idea.md"] != nil)
        #expect(model.trashNote == "2 items restored to Meetings/ and the top level")
    }

    @Test func convertingTheOpenNoteReloadsIt() async throws {
        let model = await folder.model()
        model.show(.folder("Meetings"))
        model.selection = "Meetings/Ark call.md"
        await model.loading?.value
        await model.convert("Meetings/Ark call.md", to: .task)
        let document = try #require(model.document)
        #expect(document.path == "tasks/Ark call.md" && document.text.hasPrefix("---\ntype: task\n"))
        #expect(document.diskText == nil && !document.isDirty && model.index["tasks/Ark call.md"]?.properties.kind == .task)
    }

    @Test func movingTheOpenNoteKeepsItsUnsavedEdits() async throws {
        let model = await folder.model()
        model.show(.folder("Meetings"))
        model.selection = "Meetings/Ark call.md"
        await model.loading?.value
        let document = try #require(model.document)
        document.text += "More.\n"
        await model.moveNote("Meetings/Ark call.md", to: "")
        #expect(model.document === document && document.path == "Ark call.md" && !document.isDirty)
        #expect(try folder.read("Ark call.md").hasSuffix("More.\n"))
    }

    @Test func trashingANestedFolderShowsItsParent() async {
        let model = await folder.model()
        model.show(.folder("Meetings/2026"))
        model.trashFolder("Meetings/2026")
        if let request = model.folderTrashConfirmation { await model.confirmTrashFolder(request) }
        #expect(model.domain == .folder("Meetings") && tree(model) == ["Empty 0", "Meetings 1"])
    }

    @Test func aFailedMoveLeavesThePageAndSelection() async throws {
        let model = await folder.model()
        try folder.write("a file", "Blocked")
        model.show(.folder("Meetings"))
        model.selection = "Meetings/Ark call.md"
        await model.loading?.value
        await model.moveNote("Meetings/Ark call.md", to: "Blocked")
        #expect(model.errorMessage != nil && model.domain == .folder("Meetings") && model.selection == "Meetings/Ark call.md")
    }

    @Test func aNewFolderCanGoInAFolderWhosePageIsntShowing() async {
        let model = await folder.model()
        await model.newFolder(in: "Meetings/2026")
        #expect(model.domain == .today && model.folderNameFocus == "Meetings/2026/Untitled folder")
    }
}
