import Foundation
import Testing
@testable import TaDaCore

private let task = "---\ntype: task\nstatus: Not Started\n---\n"
private let project = "---\ntype: project\nstatus: Doing\n---\n"
private let area = "---\ntype: area\n---\n"
private func task(in project: String) -> String { "---\ntype: task\nproject: \"[[\(project)]]\"\n---\n" }
private func filed(_ kind: String, in area: String) -> String { "---\ntype: \(kind)\nstatus: Doing\narea: \"[[\(area)]]\"\n---\n" }
private let today = LocalDate("2026-10-09")!

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

@Test func trashedItemsLeaveOutOtherNotesAndHiddenFiles() async throws {
    try await withTemporaryFolder { folder in
        try writeFile(task, ".trash/Task.md", in: folder)
        try writeFile("An Obsidian note\n", ".trash/Note.md", in: folder)
        try writeFile(task, ".trash/sub/Nested.md", in: folder)
        try writeFile(task, ".trash/.hidden.md", in: folder)
        try writeFile(task, ".trash/.git/Inside.md", in: folder)
        #expect(Set(Vault(root: folder).trashedItems().map(\.id)) == [".trash/Task.md", ".trash/sub/Nested.md"])
    }
}

@Test func restoreSortsFilesByKindAndLeavesAProjectsTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project, ".trash/P.md", in: folder)
        try writeFile(task(in: "P"), ".trash/One.md", in: folder)
        try writeFile(task, ".trash/Loose.md", in: folder)
        try writeFile(task, "tasks/Loose.md", in: folder)
        let restored = try vault.restore([".trash/Loose.md", ".trash/P.md"], index: await vault.loadIndex(), today: today)
        #expect(Set(restored) == ["projects/P.md", "tasks/Loose 2.md"])
        #expect(vault.trashedItems().map(\.id) == [".trash/One.md"])
    }
}

@Test func restoringATaskBringsBackItsProjectAndArea() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(area, ".trash/Home.md", in: folder)
        try writeFile(filed("project", in: "Home"), ".trash/P.md", in: folder)
        try writeFile(task(in: "P"), ".trash/One.md", in: folder)
        try writeFile(task(in: "P"), ".trash/Two.md", in: folder)
        let restored = try vault.restore([".trash/One.md"], index: await vault.loadIndex(), today: today)
        #expect(restored == ["areas/Home.md", "projects/P.md", "tasks/One.md"])
        #expect(vault.trashedItems().map(\.id) == [".trash/Two.md"])
    }
}

@Test func restoringAProjectBringsBackItsAreaAndAnAreaComesBackAlone() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(area, ".trash/Home.md", in: folder)
        try writeFile(area, ".trash/Work.md", in: folder)
        try writeFile(filed("project", in: "Home"), ".trash/P.md", in: folder)
        try writeFile(filed("task", in: "Work"), ".trash/Filed.md", in: folder)
        #expect(try vault.restore([".trash/P.md"], index: await vault.loadIndex(), today: today) == ["areas/Home.md", "projects/P.md"])
        #expect(try vault.restore([".trash/Work.md"], index: await vault.loadIndex(), today: today) == ["areas/Work.md"])
        #expect(vault.trashedItems().map(\.id) == [".trash/Filed.md"])
    }
}

@Test func restoringKeepsAParentThatsInTheVault() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project, "projects/P.md", in: folder)
        try writeFile(project, ".trash/P.md", in: folder)
        try writeFile(task(in: "P"), ".trash/One.md", in: folder)
        #expect(try vault.restore([".trash/One.md"], index: await vault.loadIndex(), today: today) == ["tasks/One.md"])
        #expect(vault.trashedItems().map(\.id) == [".trash/P.md"])
    }
}

@Test func restoringRecreatesAParentDeletedForever() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(task(in: "Gone"), ".trash/One.md", in: folder)
        try writeFile(filed("project", in: "Gone area"), ".trash/P.md", in: folder)
        let restored = try vault.restore([".trash/One.md", ".trash/P.md"], index: await vault.loadIndex(), today: today)
        #expect(Set(restored) == ["projects/Gone.md", "tasks/One.md", "areas/Gone area.md", "projects/P.md"])
        #expect(try vault.read("projects/Gone.md") == NewFile.project(today: today))
        #expect(try vault.read("areas/Gone area.md") == NewFile.area(today: today))
    }
}

@Test func restoringAParentUnderANewNameRelinksTheFile() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("A note, not a project\n", "projects/P.md", in: folder)
        try writeFile(project, ".trash/P.md", in: folder)
        try writeFile(task(in: "P"), ".trash/One.md", in: folder)
        #expect(try vault.restore([".trash/One.md"], index: await vault.loadIndex(), today: today) == ["projects/P 2.md", "tasks/One.md"])
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

@Test func anAreaGoesToTheTrashWithItsProjectsAndTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(area, "areas/Home.md", in: folder)
        try writeFile(filed("project", in: "Home"), "projects/P.md", in: folder)
        try writeFile(task(in: "P"), "tasks/One.md", in: folder)
        try writeFile(filed("task", in: "Home"), "tasks/Filed.md", in: folder)
        try writeFile(task, "tasks/Loose.md", in: folder)
        let moved = try vault.moveToTrash("areas/Home.md", index: await vault.loadIndex())
        #expect(moved == ["areas/Home.md", "projects/P.md", "tasks/Filed.md", "tasks/One.md"])
        #expect(vault.markdownPaths() == ["tasks/Loose.md"])
        let trashed = vault.trashedItems()
        let home = try #require(trashed.first { $0.id == ".trash/Home.md" })
        let contents = TrashedItem.contents(of: home.item, in: trashed)
        #expect(contents.projects.map(\.id) == [".trash/P.md"])
        #expect(contents.tasks.map(\.id) == [".trash/Filed.md", ".trash/One.md"])
    }
}

@Test func discardTakesAnAreasTrashedProjectsAndTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(area, ".trash/Home.md", in: folder)
        try writeFile(filed("project", in: "Home"), ".trash/P.md", in: folder)
        try writeFile(task(in: "P"), ".trash/One.md", in: folder)
        try writeFile(filed("task", in: "Home"), ".trash/Filed.md", in: folder)
        try writeFile(task, ".trash/Other.md", in: folder)
        try vault.discard([".trash/Home.md"]) { try FileManager.default.removeItem(at: $0) }
        #expect(vault.trashedItems().map(\.id) == [".trash/Other.md"])
    }
}

@Test func discardGoesOnPastAFailureAndReportsIt() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(task, ".trash/A.md", in: folder)
        try writeFile(task, ".trash/B.md", in: folder)
        try writeFile(task, ".trash/C.md", in: folder)
        let error = #expect(throws: DiscardError.self) {
            try vault.discard([".trash/A.md", ".trash/B.md", ".trash/C.md"]) { url in
                if url.lastPathComponent == "A.md" { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.removeItem(at: url)
            }
        }
        #expect(error?.failed == [".trash/A.md"])
        #expect(vault.trashedItems().map(\.id) == [".trash/A.md"])
    }
}

@Test func trashingDeletesOnlyOniOSWhereTheSystemTrashIsUnsupported() async throws {
    try await withTemporaryFolder { folder in
        let url = folder.appending(path: "a.md")
        try CoordinatedFileIO.write("text", to: url)
        #if os(iOS)
        try CoordinatedFileIO.trashOrDelete(url) { _ in throw CocoaError(.featureUnsupported) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #else
        #expect(throws: CocoaError.self) {
            try CoordinatedFileIO.trashOrDelete(url) { _ in throw CocoaError(.featureUnsupported) }
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #endif

        #expect(throws: CocoaError.self) {
            try CoordinatedFileIO.trashOrDelete(url) { _ in throw CocoaError(.fileWriteNoPermission) }
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
