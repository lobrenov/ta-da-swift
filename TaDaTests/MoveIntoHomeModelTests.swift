import Foundation
import Testing
import TaDaCore
@testable import TaDa

/// Asking once about moving a folder's old layout into `Ta Da/`, and moving it.
@MainActor
struct MoveIntoHomeModelTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "projects/Kombi.md": "---\ntype: project\nstatus: Doing\n---\n",
            "tasks/Service.md": "---\ntype: task\nstatus: Doing\nproject: \"[[Kombi]]\"\n---\nSee [[projects/Kombi]].\n",
        ])
    }

    @Test func anOldLayoutIsOfferedUntilNotNow() async throws {
        let model = await folder.model()
        #expect(model.oldLayoutFolders == ["projects", "tasks"] && model.offersMove)
        model.declineMove()
        #expect(!model.offersMove)
        #expect(await folder.model().offersMove == false, "kept for the folder")
    }

    @Test func movingFollowsTheOpenFileAndStopsOffering() async throws {
        let model = await folder.model(selecting: "tasks/Service.md")
        await model.moveIntoHome()
        #expect(model.errorMessage == nil)
        #expect(model.selection == "Ta Da/tasks/Service.md" && model.document?.path == "Ta Da/tasks/Service.md")
        #expect(model.document?.body == "See [[Ta Da/projects/Kombi]].\n")
        #expect(model.index.parent(of: model.index["Ta Da/tasks/Service.md"]!)?.path == "Ta Da/projects/Kombi.md")
        #expect(model.index["tasks/Service.md"] == nil && model.oldLayoutFolders.isEmpty && !model.offersMove)
    }

    @Test func aNewLayoutIsntOffered() async throws {
        let folder = try TestFolder(["Ta Da/tasks/A.md": "---\ntype: task\n---\n"])
        #expect(await folder.model().offersMove == false)
    }
}
