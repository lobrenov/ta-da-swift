import Foundation
import Testing
@testable import TaDaCore

private let task = "---\ntype: task\nstatus: Not Started\n---\n"
private let project = "---\ntype: project\nstatus: Doing\n---\n"
private func task(in project: String) -> String { "---\ntype: task\nproject: \"[[\(project)]]\"\n---\n" }

@Test func moveToTrashCreatesTheFolderAndNumbersTakenNames() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(task, "tasks/A.md", in: folder)
        try writeFile(task, "deep/a.md", in: folder)
        var index = await vault.loadIndex()
        #expect(try vault.moveToTrash("tasks/A.md", index: index) == ["tasks/A.md"])
        index.remove("tasks/A.md")
        #expect(try vault.moveToTrash("deep/a.md", index: index) == ["deep/a.md"])
        #expect(vault.markdownPaths().isEmpty)
        let trashed = vault.trashedItems()
        #expect(Set(trashed.map(\.id)) == [".trash/A.md", ".trash/a 2.md"])
        #expect(trashed.allSatisfy { $0.deleted.map { abs($0.timeIntervalSinceNow) < 60 } ?? false })
    }
}

@Test func aProjectGoesToTheTrashWithItsTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project, "projects/P.md", in: folder)
        try writeFile(task(in: "P"), "tasks/One.md", in: folder)
        try writeFile(task(in: "P"), "notes/Two.md", in: folder)
        try writeFile(task, "tasks/Loose.md", in: folder)
        let moved = try vault.moveToTrash("projects/P.md", index: await vault.loadIndex())
        #expect(moved == ["projects/P.md", "tasks/One.md", "notes/Two.md"])
        #expect(vault.markdownPaths() == ["tasks/Loose.md"])
        let trashed = vault.trashedItems()
        let p = try #require(trashed.first { $0.id == ".trash/P.md" })
        #expect(TrashedItem.tasks(of: p.item, in: trashed).map(\.id) == [".trash/One.md", ".trash/Two.md"])
    }
}

@Test func trashedItemsLeaveOutOtherNotes() async throws {
    try await withTemporaryFolder { folder in
        try writeFile(task, ".trash/Task.md", in: folder)
        try writeFile("An Obsidian note\n", ".trash/Note.md", in: folder)
        try writeFile(task, ".trash/sub/Nested.md", in: folder)
        #expect(Set(Vault(root: folder).trashedItems().map(\.id)) == [".trash/Task.md", ".trash/sub/Nested.md"])
    }
}

@Test func restoreSortsFilesByKindAndBringsAProjectsTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project, ".trash/P.md", in: folder)
        try writeFile(task(in: "P"), ".trash/One.md", in: folder)
        try writeFile(task, ".trash/Loose.md", in: folder)
        try writeFile(task, "tasks/Loose.md", in: folder)
        let restored = try vault.restore([".trash/Loose.md", ".trash/P.md"])
        #expect(restored == ["projects/P.md", "tasks/One.md", "tasks/Loose 2.md"])
        #expect(vault.trashedItems().isEmpty)
        #expect(try vault.read("tasks/One.md") == task(in: "P"))
    }
}

@Test func restoringARenamedProjectRelinksItsTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project, "projects/P.md", in: folder)
        try writeFile(project, ".trash/P.md", in: folder)
        try writeFile(task(in: "P"), ".trash/One.md", in: folder)
        #expect(try vault.restore([".trash/P.md"]) == ["projects/P 2.md", "tasks/One.md"])
        #expect(try vault.read("tasks/One.md") == task(in: "P 2"))
    }
}

@Test func discardTakesAProjectsTrashedTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project, ".trash/P.md", in: folder)
        try writeFile(task(in: "P"), ".trash/One.md", in: folder)
        try writeFile(task, ".trash/Other.md", in: folder)
        try vault.discard([".trash/P.md"]) { try FileManager.default.removeItem(at: $0) }
        #expect(vault.trashedItems().map(\.id) == [".trash/Other.md"])
    }
}
