import AppKit
import CoreTransferable
import Foundation
import Testing
import UniformTypeIdentifiers
import TaDaCore
@testable import TaDa

@MainActor
struct FileMenuTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "projects/Ta Da MVP.md": "---\ntype: project\nstatus: Doing\n---\n",
            "tasks/One.md": "---\ntype: task\nstatus: Doing\n---\n",
            "tasks/Two.md": "---\ntype: task\nstatus: Doing\n---\n",
            "tasks/Three.md": "---\ntype: task\nstatus: Doing\n---\n",
        ])
    }

    private func titles(_ path: String, _ model: AppModel) -> [String] {
        FileMenuAction.actions(for: path, model: model).map(\.title)
    }

    @Test func everyFileCanBeRevealedInFinderWithoutAShortcut() async {
        let model = await folder.model()
        #expect(titles("tasks/One.md", model) == ["Move", "Schedule", "Set Deadline…", "Tags…", "Reveal in Finder", "Delete"])
        #expect(titles("projects/Ta Da MVP.md", model) == ["Move", "Schedule", "Set Deadline…", "Tags…", "Reveal in Finder", "Delete"])

        let paths = ["tasks/One.md", "tasks/Two.md", "tasks/Three.md"]
        model.arrowKeyList = AppModel.ArrowKeyList(id: UUID(), paths: paths, allowsMultipleSelection: true)
        model.selection = paths[0]
        model.extendSelection(to: paths[2])
        #expect(titles(paths[1], model) == ["Move 3 Tasks", "Schedule 3 Tasks", "Set Deadline…", "Reveal in Finder", "Delete 3 Tasks"])
        #expect(model.picked == Set(paths), "the menu bar's Reveal in Finder shows the picked tasks")

        await model.moveToTrash(["tasks/One.md"])
        model.show(.trash)
        let actions = FileMenuAction.actions(for: ".trash/One.md", model: model)
        #expect(actions.map(\.title) == ["Restore", "Reveal in Finder", "Delete Forever"])
        #expect(actions.first { $0.title == "Reveal in Finder" }?.shortcut == "")
    }

    @Test func aNotesMenuConvertsMovesAndTrashes() async throws {
        try folder.write("A note\n", "Meetings/Ark.md")
        let model = await folder.model()
        let row = FileMenuAction.noteActions(for: "Meetings/Ark.md", model: model, onRow: true, at: .zero, in: NSWindow())
        #expect(row.map(\.title) == ["Task…", "Project…", "Area…", "Tags…", "Move to Folder…",
                                     "Reveal in Finder", "Move to Trash"])
        let page = FileMenuAction.noteActions(for: "Meetings/Ark.md", model: model, onRow: false, at: nil, in: nil)
        #expect(page.map(\.title) == ["Task…", "Project…", "Area…", "Reveal in Finder", "Move to Trash"])
        #expect(page.prefix(3).map(\.shortcut) == ["tasks/", "projects/", "areas/"])
        page[1].run()
        #expect(model.convertRequest?.path == "Meetings/Ark.md" && model.convertRequest?.kind == .project)
        page[4].run()
        for _ in 0..<100 where model.trash.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.index["Meetings/Ark.md"] == nil && model.trash.map(\.id) == [".trash/Meetings/Ark.md"])
    }

    @Test func aNotesMenuMovesToFoldersAndActsOnPickedNotes() async throws {
        try folder.write("A\n", "Meetings/Ark.md")
        try folder.write("B\n", "Meetings/Budget.md")
        try folder.write("C\n", "Loose.md")
        let model = await folder.model()
        let window = NSWindow()
        let row = FileMenuAction.noteActions(for: "Meetings/Ark.md", model: model, onRow: true, at: .zero, in: window)
        #expect(row.map(\.title).contains("Move to Folder…"))
        #expect(FileMenuAction.moveTargets(for: "Meetings/Ark.md", model: model).map(\.path) == [""])
        #expect(FileMenuAction.moveTargets(for: "Loose.md", model: model).map(\.path) == ["Meetings"])
        #expect(!titles("Meetings/Ark.md", model).contains("Move to Folder…"), "VoiceOver's actions have no point to open it at")

        model.show(.folder("Meetings"))
        model.arrowKeyList = AppModel.ArrowKeyList(id: UUID(), paths: ["Meetings/Ark.md", "Meetings/Budget.md"], allowsMultipleSelection: true)
        model.selection = "Meetings/Ark.md"
        model.extendSelection(to: "Meetings/Budget.md")
        #expect(titles("Meetings/Ark.md", model) == ["Reveal in Finder", "Move 2 Files to Trash"])
    }

    @Test func tagsWithoutAPointOpensTheNote() async throws {
        try folder.write("A\n", "Meetings/Ark.md")
        let model = await folder.model()
        FileMenuAction.actions(for: "Meetings/Ark.md", model: model).first { $0.title == "Tags…" }?.run()
        #expect(model.selection == "Meetings/Ark.md" && model.propertyMenuRequest?.onChip == true)
    }

    @Test func tagsOpensTheMenuForTheOneFileTheMenuActsOn() async {
        let model = await folder.model()
        let tags = FileMenuAction.actions(for: "tasks/One.md", model: model).first { $0.title == "Tags…" }
        #expect(tags?.shortcut == "⌘T")
        tags?.run()
        #expect(model.propertyMenuRequest?.menu == .tags)
        #expect(model.propertyMenuRequest?.paths == ["tasks/One.md"] && model.propertyMenuRequest?.onChip == false)
    }

    @Test func anAreasMenuMakesFilesInItOpensItAndDeletes() async throws {
        try folder.write("---\ntype: area\n---\n", "areas/Home.md")
        let model = await folder.model()
        #expect(titles("areas/Home.md", model) == ["New Task in Home", "New Project in Home", "Open Area File", "Tags…", "Reveal in Finder", "Delete"])
        FileMenuAction.actions(for: "areas/Home.md", model: model).first { $0.title == "Open Area File" }?.run()
        #expect(model.domain == .area("areas/Home.md") && model.selection == "areas/Home.md")
    }

    @Test func aDraggedTaskIsItsFile() async throws {
        let model = await folder.model()
        let url = try #require(model.vault?.url(for: "tasks/One.md"))
        let file = TaskFile(path: "tasks/One.md", url: url)
        #expect(file.exportedContentTypes().contains(.fileURL))
        #expect(model.vault?.path(of: url) == "tasks/One.md", "a drop finds the task again")
    }
}
