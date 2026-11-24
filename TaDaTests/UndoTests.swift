import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct UndoTests {
    let folder: TestFolder
    static let open = "---\ntype: task\nstatus: Doing\n---\nBody\n"

    init() throws {
        folder = try TestFolder([
            "Ta Da/projects/P.md": "---\ntype: project\nstatus: Doing\n---\n",
            "Ta Da/tasks/One.md": Self.open,
            "Ta Da/tasks/Two.md": "---\ntype: task\nstatus: Doing\nproject: \"[[P]]\"\n---\n",
        ])
    }

    private func model() async -> AppModel {
        let model = await folder.model()
        model.undoManager = UndoManager()
        return model
    }

    /// Waits for an undo or redo, which runs in a task of its own.
    private func settle(until done: () throws -> Bool) async throws {
        for _ in 0..<100 where try !done() { try await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func completingUndoesAndRedoes() async throws {
        let model = await model()
        await model.toggleCompletion(try #require(model.index["Ta Da/tasks/One.md"]))
        let done = try folder.read("Ta Da/tasks/One.md")
        #expect(done.contains("status: Done"))
        #expect(model.undoManager?.undoActionName == "Complete")
        #expect(model.undoToast?.message == "Completed “One”")

        model.undoManager?.undo()
        try await settle { try folder.read("Ta Da/tasks/One.md") == Self.open }
        #expect(try folder.read("Ta Da/tasks/One.md") == Self.open)
        #expect(model.index["Ta Da/tasks/One.md"]?.properties.status == .doing)

        model.undoManager?.redo()
        try await settle { try folder.read("Ta Da/tasks/One.md") == done }
        #expect(try folder.read("Ta Da/tasks/One.md") == done)
    }

    @Test func aFileChangedSinceIsLeftAndCounted() async throws {
        let model = await model()
        await model.setStatus(.done, in: "Ta Da/tasks/One.md")
        let changed = "---\ntype: task\nstatus: Blocked\n---\nBody\n"
        try folder.write(changed, "Ta Da/tasks/One.md")
        model.undoManager?.undo()
        try await settle { model.errorMessage != nil }
        #expect(model.errorMessage == "1 file changed since, so it wasn’t undone.")
        #expect(try folder.read("Ta Da/tasks/One.md") == changed)
    }

    @Test func deletingUndoesToTheSameFolders() async throws {
        let model = await model()
        await model.moveToTrash(["Ta Da/projects/P.md"])
        #expect(model.index["Ta Da/tasks/Two.md"] == nil)
        #expect(model.undoToast?.message == "Moved “P” to the Trash")
        model.undoManager?.undo()
        try await settle { model.index["Ta Da/tasks/Two.md"] != nil && model.trash.isEmpty }
        #expect(model.index["Ta Da/projects/P.md"] != nil && model.index["Ta Da/tasks/Two.md"] != nil)
        #expect(model.trash.isEmpty)
    }

    @Test func aChangeToSeveralFilesIsOneStep() async throws {
        let model = await model()
        let paths = ["Ta Da/tasks/One.md", "Ta Da/tasks/Two.md"]
        let before = try paths.map { try folder.read($0) }
        await model.setDate(.due, to: LocalDate("2026-10-05"), of: paths)
        #expect(model.undoManager?.undoActionName == "Set Due Date")
        #expect(model.undoToast == nil)
        model.undoManager?.undo()
        try await settle { try paths.map { try folder.read($0) } == before }
        #expect(try paths.map { try folder.read($0) } == before)
        #expect(model.undoManager?.canUndo == false)
    }

    @Test func undoingOnTheOpenFileKeepsTextTypedAfterTheChange() async throws {
        let model = await model()
        model.selection = "Ta Da/tasks/One.md"
        try await settle { model.document?.path == "Ta Da/tasks/One.md" }
        let document = try #require(model.document)
        await model.setStatus(.done, in: document.path)
        document.text += "Typed\n"
        model.undoManager?.undo()
        try await settle { document.text.contains("status: Doing") }
        #expect(document.text == Self.open + "Typed\n")
    }
}
