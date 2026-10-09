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
        #expect(titles("tasks/One.md", model) == ["Move", "Schedule", "Set Deadline…", "Reveal in Finder", "Delete"])
        #expect(titles("projects/Ta Da MVP.md", model) == ["Schedule", "Set Deadline…", "Reveal in Finder", "Delete"])

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

    @Test func anAreasMenuMakesFilesInItOpensItAndDeletes() async throws {
        try folder.write("---\ntype: area\n---\n", "areas/Home.md")
        let model = await folder.model()
        #expect(titles("areas/Home.md", model) == ["New Task in Home", "New Project in Home", "Open Area File", "Reveal in Finder", "Delete"])
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
