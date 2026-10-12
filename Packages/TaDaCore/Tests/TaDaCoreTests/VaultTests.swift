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
        #expect(index.items.keys.sorted() == ["deep/er/b.MD", "notes/note.md", "projects/P.md", "root.md", "tasks/a.md"])
        #expect(index["notes/note.md"]?.properties.kind == .note)
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

@Test func placeholdersAreListedByThePathTheyWillHave() async throws {
    try await withTemporaryFolder { folder in
        for path in ["tasks/.Not here.md.icloud", ".Top.MD.icloud", ".obsidian/.Hidden.md.icloud", "tasks/.Image.png.icloud",
                     "tasks/.Report.pdf.icloud", ".trash/attachments/.Gone.png.icloud", "tasks/Here.md"] {
            try writeFile("", path, in: folder)
        }
        #expect(Vault(root: folder).placeholderPaths() == ["Top.MD", "tasks/Image.png", "tasks/Not here.md"])
    }
}

@Test func pathsOfURLsAreTheOnesAScanLists() async throws {
    try await withTemporaryFolder { folder in
        try writeFile(task, "Vault/tasks/a.md", in: folder)
        try writeFile(task, "Vault/B.MD", in: folder)
        let vault = Vault(root: folder.appending(path: "Vault"))
        #expect(vault.path(of: folder.appending(path: "Vault/tasks/a.md")) == "tasks/a.md")
        #if os(macOS)
        // The temporary directory is under /var, a symlink to /private/var.
        #expect(vault.path(of: URL(filePath: "/private" + folder.appending(path: "Vault/B.MD").path)) == "B.MD")
        #else
        #expect(vault.path(of: folder.appending(path: "Vault/B.MD")) == "B.MD")
        #endif
        for outside in ["Vault/.trash/a.md", "Vault/tasks/a.txt", "Vault", "Other/a.md"] {
            #expect(vault.path(of: folder.appending(path: outside)) == nil)
        }
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
        #expect(result.relinked.map(\.path) == ["tasks/Linked.md", "tasks/Linked CRLF.md"])
        #expect(result.failed.isEmpty)
        let after = try vault.read("tasks/Linked.md")
        #expect(changedLines(linked, after) == (["project: \"[[old name]]\" # keep?"], ["project: \"[[New - Name]]\""]))
        #expect(try vault.read("tasks/Linked CRLF.md").contains("project: \"[[New - Name]]\"\r\n"))
        #expect(try vault.read("tasks/Other task.md") == other)

        let reloaded = await vault.loadIndex()
        let project = try #require(reloaded["projects/New - Name.md"])
        #expect(reloaded.tasks(in: project).map(\.title) == ["Linked", "Linked CRLF"])
    }
}

@Test func renamingAProjectKeepsALinkChangedSinceTheIndexWasRead() async throws {
    try await withTemporaryFolder { folder in
        try writeFile("---\ntype: project\nstatus: Doing\n---\n", "projects/Old.md", in: folder)
        try writeFile("---\ntype: task\nstatus: Doing\nproject: \"[[Old]]\"\n---\n", "tasks/Moved.md", in: folder)
        let vault = Vault(root: folder)
        let index = await vault.loadIndex()
        let moved = "---\ntype: task\nstatus: Doing\nproject: \"[[Elsewhere]]\"\n---\nMoved in Obsidian.\n"
        try writeFile(moved, "tasks/Moved.md", in: folder)

        _ = try vault.renameProject(at: "projects/Old.md", to: "New", index: index)
        #expect(try vault.read("tasks/Moved.md") == moved)
    }
}

@Test func aTaskThatCantBeRelinkedDoesntStopTheOthers() async throws {
    try await withTemporaryFolder { folder in
        try writeFile("---\ntype: project\nstatus: Doing\n---\n", "projects/Old.md", in: folder)
        let linked = "---\ntype: task\nstatus: Doing\nproject: \"[[Old]]\"\n---\n"
        try writeFile(linked, "tasks/A.md", in: folder)
        try writeFile(linked, "tasks/B.md", in: folder)
        let vault = Vault(root: folder)
        let index = await vault.loadIndex()
        try Data([0xff, 0xfe]).write(to: folder.appending(path: "tasks/A.md"))

        let result = try vault.renameProject(at: "projects/Old.md", to: "New", index: index)
        #expect(result.path == "projects/New.md")
        #expect(result.failed == ["tasks/A.md"])
        #expect(result.relinked.map(\.path) == ["tasks/B.md"])
        #expect(try vault.read("tasks/B.md") == linked.replacingOccurrences(of: "[[Old]]", with: "[[New]]"))
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
        #expect(vault.modificationDate(of: "tasks/A.md") != nil)
        #expect(vault.modificationDate(of: "tasks/missing.md") == nil)
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

@Test func changesReportNewChangedAndRemovedFiles() async throws {
    try await withTemporaryFolder { folder in
        try writeFile(task, "tasks/A.md", in: folder)
        try writeFile(task, "tasks/B.md", in: folder)
        try writeFile("note", "notes/N.md", in: folder)
        let vault = Vault(root: folder)
        let known = vault.modificationDates()
        #expect(known.keys.sorted() == ["notes/N.md", "tasks/A.md", "tasks/B.md"])
        #expect(vault.changes(since: known).isEmpty)

        try await Task.sleep(for: .milliseconds(20))
        try writeFile(task.replacingOccurrences(of: "Not Started", with: "Done"), "tasks/A.md", in: folder)
        try FileManager.default.removeItem(at: folder.appending(path: "tasks/B.md"))
        try writeFile(task, "tasks/C.md", in: folder)
        try writeFile("still a note", "notes/N.md", in: folder)
        let changes = vault.changes(since: known)
        #expect(changes.changed.keys.sorted() == ["notes/N.md", "tasks/A.md", "tasks/C.md"])
        #expect(changes.changed["tasks/A.md"]??.properties.status == .done)
        #expect(changes.changed["notes/N.md"]??.properties.kind == .note)
        #expect(changes.removed == ["tasks/B.md"])
        #expect(vault.changes(since: changes.dates).isEmpty)
    }
}

@Test func unreadableFilesAreRetriedLater() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try Data([0xff, 0xfe]).write(to: folder.appending(path: "Bad.md"))
        let changes = vault.changes(since: [:])
        #expect(changes.changed.isEmpty)
        #expect(changes.dates["Bad.md"] == nil, "no date recorded, so it's checked again")
    }
}

@Test func localFilesHaveNoConflicts() async throws {
    try await withTemporaryFolder { folder in
        try writeFile(task, "A.md", in: folder)
        #expect(Conflicts.versions(of: folder.appending(path: "A.md")).isEmpty)
    }
}

@Test func theWatcherReportsChanges() async throws {
    try await withTemporaryFolder { folder in
        let fired = Fired()
        let watcher = try #require(VaultWatcher(root: folder, latency: 0.05) { fired.set() })
        try await Task.sleep(for: .milliseconds(200))
        #if os(macOS)
        try writeFile(task, "tasks/New.md", in: folder)
        #else
        // On iOS the watcher hears coordinated writes only.
        try Vault(root: folder).write(task, to: "New.md")
        #endif
        for _ in 0..<40 where !fired.value { try await Task.sleep(for: .milliseconds(50)) }
        #expect(fired.value)
        _ = watcher
    }
}

private final class Fired: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    var value: Bool { lock.withLock { fired } }
    func set() { lock.withLock { fired = true } }
}

@Test func guardedWritesNeverOverwriteSomeoneElsesChange() async throws {
    try await withTemporaryFolder { folder in
        try writeFile(task, "A.md", in: folder)
        let vault = Vault(root: folder)
        #expect(try vault.write(task + "mine\n", to: "A.md", ifUnchangedFrom: task) == nil)
        #expect(try vault.read("A.md") == task + "mine\n")

        try writeFile(task + "theirs\n", "A.md", in: folder)
        #expect(try vault.write(task + "mine again\n", to: "A.md", ifUnchangedFrom: task + "mine\n") == task + "theirs\n")
        #expect(try vault.read("A.md") == task + "theirs\n")
        #expect(throws: (any Error).self) { try vault.write("x", to: "Gone.md", ifUnchangedFrom: "") }
    }
}
