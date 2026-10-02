import Foundation
import Testing
@testable import TaDaCore

private let task = "---\ntype: task\nstatus: Not Started\n---\n"

@Test func scanFindsMarkdownRecursivelySkippingHiddenFolders() async throws {
    try await withTemporaryFolder { folder in
        for path in ["tasks/a.md", "projects/P.md", "deep/er/b.MD", "notes/note.md", "root.md",
                     ".obsidian/x.md", ".trash/old.md", "tasks/.hidden.md", "tasks/readme.txt", "Bundle.app/c.md"] {
            try writeFile(path.hasPrefix("notes") ? "plain note" : task, path, in: folder)
        }
        let vault = Vault(root: folder)
        #expect(vault.markdownPaths() == ["deep/er/b.MD", "notes/note.md", "projects/P.md", "root.md", "tasks/a.md"])
        let index = await vault.loadIndex()
        #expect(index.items.keys.sorted() == ["deep/er/b.MD", "projects/P.md", "root.md", "tasks/a.md"])
        #expect(index["deep/er/b.MD"]?.title == "b")
    }
}

@Test func scanSkipsUnreadableFiles() async throws {
    try await withTemporaryFolder { folder in
        try writeFile(task, "good.md", in: folder)
        try Data([0xff, 0xfe]).write(to: folder.appending(path: "binary.md"))
        #expect(await Vault(root: folder).loadIndex().items.keys.sorted() == ["good.md"])
    }
}

@Test func vaultResolvesPathsUnderARootWithSpacesAndSymlinks() async throws {
    try await withTemporaryFolder { folder in
        try writeFile(task, "My Vault/tasks/Dan’s task.md", in: folder)
        // The temporary directory is under /var, a symlink to /private/var.
        let vault = Vault(root: folder.appending(path: "My Vault"))
        #expect(vault.markdownPaths() == ["tasks/Dan’s task.md"])
        #expect(try vault.read("tasks/Dan’s task.md") == task)
    }
}

@Test func createNumbersTakenNames() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        let first = try vault.create(task, in: Vault.taskFolder, title: "Game Jam: Starfall")
        let second = try vault.create(task, in: Vault.taskFolder, title: "game jam: starfall")
        let root = try vault.create(task, in: "", title: "Root")
        #expect(first == "tasks/Game Jam - Starfall.md")
        #expect(second == "tasks/game jam - starfall 2.md")
        #expect(root == "Root.md")
        #expect(try vault.read(first) == task)
    }
}

@Test func renameMovesInPlace() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(task, "tasks/Old.md", in: folder)
        try writeFile(task, "tasks/Taken.md", in: folder)
        #expect(try vault.rename("tasks/Old.md", to: "Old") == "tasks/Old.md")
        #expect(try vault.rename("tasks/Old.md", to: "Taken") == "tasks/Taken 2.md")
        #expect(try vault.rename("tasks/Taken 2.md", to: "taken 2") == "tasks/taken 2.md")
        #expect(vault.markdownPaths() == ["tasks/Taken.md", "tasks/taken 2.md"])
    }
}

@Test func renamingAProjectRelinksItsTasks() async throws {
    try await withTemporaryFolder { folder in
        try writeFile("---\ntype: project\nstatus: Doing\n---\n", "projects/Old Name.md", in: folder)
        let linked = "---\ntype: task\nstatus: Doing\nproject: \"[[old name]]\" # keep?\ndueDate: 2026-10-02\n---\nBody [[Old Name]]\n"
        try writeFile(linked, "tasks/Linked.md", in: folder)
        try writeFile(linked.replacingOccurrences(of: "\n", with: "\r\n"), "tasks/Linked CRLF.md", in: folder)
        let other = "---\ntype: task\nstatus: Doing\nproject: \"[[Other]]\"\n---\n"
        try writeFile(other, "tasks/Other task.md", in: folder)
        let vault = Vault(root: folder)
        let index = await vault.loadIndex()

        let result = try vault.renameProject(at: "projects/Old Name.md", to: "New: Name", index: index)
        #expect(result.path == "projects/New - Name.md")
        #expect(result.relinked == ["tasks/Linked.md", "tasks/Linked CRLF.md"])
        let after = try vault.read("tasks/Linked.md")
        #expect(changedLines(linked, after) == (["project: \"[[old name]]\" # keep?"], ["project: \"[[New - Name]]\""]))
        #expect(try vault.read("tasks/Linked CRLF.md").contains("project: \"[[New - Name]]\"\r\n"))
        #expect(try vault.read("tasks/Other task.md") == other)

        let reloaded = await vault.loadIndex()
        let project = try #require(reloaded["projects/New - Name.md"])
        #expect(reloaded.tasks(in: project).map(\.title) == ["Linked", "Linked CRLF"])
    }
}

@Test func updateReparsesTheChangedFile() async throws {
    try await withTemporaryFolder { folder in
        try writeFile(task, "tasks/A.md", in: folder)
        let vault = Vault(root: folder)
        let item = try vault.update("tasks/A.md") { Completion.toggle(.notStarted, in: $0, today: LocalDate("2026-10-03")!) }
        #expect(item?.properties.status == .done)
        #expect(item?.properties.completedDate == LocalDate("2026-10-03"))
        #expect(try vault.read("tasks/A.md") == "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-03\n---\n")
        #expect(try vault.update("tasks/A.md") { _ in "no longer a task" } == nil)
    }
}

@Test func bookmarksRoundTrip() async throws {
    try await withTemporaryFolder { folder in
        let bookmark = try Vault.bookmark(for: folder)
        let resolved = try Vault.resolve(bookmark)
        #expect(resolved.folder.resolvingSymlinksInPath() == folder.resolvingSymlinksInPath())
        #expect(resolved.refreshed == nil)
    }
}
