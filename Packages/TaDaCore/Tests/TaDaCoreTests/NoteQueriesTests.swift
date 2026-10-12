import Foundation
import Testing
@testable import TaDaCore

/// Notes at the top level and nested, an empty folder, folders holding only typed or non-Markdown files, untyped files
/// in `tasks/` and `attachments/`, and hidden, trashed and logged files.
private let noteVault = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "Fixtures/NoteVault").standardized

private func noteIndex() async -> VaultIndex { await Vault(root: noteVault).loadIndex() }

private func describe(_ nodes: [FolderNode], depth: Int = 0) -> [String] {
    nodes.flatMap { [String(repeating: "  ", count: depth) + "\($0.name) \($0.count)"] + describe($0.children, depth: depth + 1) }
}

@Test func notesAreTheUntypedFilesOutsideTheToDoFolders() async {
    let index = await noteIndex()
    #expect(index.notes.map(\.path).sorted() == [
        "Loose idea.md", "Meetings/2026/Standup.md", "Meetings/Ark planning call.md", "Reading list.md", "Work/Clients/Brief.md",
    ])
    #expect(index["Typed/Task elsewhere.md"]?.properties.kind == .task)
    #expect(index["tasks/Untyped in tasks.md"] == nil && index["attachments/Untyped in attachments.md"] == nil)
}

@Test func emptyFoldersLeaveOutFilledHiddenAndReservedFolders() {
    #expect(Vault(root: noteVault).emptyFolders() == ["Empty"])
}

@Test func emptyFoldersCountNestedEmptyFolders() async throws {
    try await withTemporaryFolder { folder in
        for path in ["A/B/C", "D/E", "tasks/Inside", ".hidden/F", "Bundle.app/G"] {
            try FileManager.default.createDirectory(at: folder.appending(path: path), withIntermediateDirectories: true)
        }
        try writeFile("note", "D/note.md", in: folder)
        #expect(Vault(root: folder).emptyFolders() == ["A", "A/B", "A/B/C", "D/E"])
    }
}

@Test func folderTreeRollsUpCountsAndSortsByName() async {
    let index = await noteIndex()
    #expect(describe(index.folderTree(emptyFolders: Vault(root: noteVault).emptyFolders())) == [
        "Empty 0",
        "Meetings 2",
        "  2026 1",
        "Work 1",
        "  Clients 1",
    ])
}

@Test func folderTreeAddsTheParentsOfEmptyFolders() {
    let index = VaultIndex([makeItem("b/Note.md", "tags: []")])
    #expect(describe(index.folderTree(emptyFolders: ["a/x/y", "C/z"])) == ["a 0", "  x 0", "    y 0", "b 1", "C 0", "  z 0"])
}

@Test func notesInAFolderLeaveOutSubfolders() async {
    let index = await noteIndex()
    #expect(index.looseNotes().map(\.title) == ["Loose idea", "Reading list"])
    #expect(index.notes(in: "Meetings").map(\.title) == ["Ark planning call"])
    #expect(index.notes(in: "Work").isEmpty)
    #expect(index.notes(in: "Empty").isEmpty)
}

@Test func notesCountInTagsUntaggedSearchAndBacklinks() async throws {
    let index = await noteIndex()
    let work = try #require(Tag("work"))
    #expect(index.tagTree().first { $0.tag.path == "work" }?.count == 3)
    #expect(index.tagBrowser(work).notes.map(\.title) == ["Ark planning call", "Standup"])
    #expect(index.untagged().map(\.title) == ["Brief", "Loose idea", "Task elsewhere"])
    #expect(index.tagBrowser(nil).notes.map(\.title) == ["Brief", "Loose idea"])
    #expect(index.search("ark").map(\.title) == ["Ark planning call"])
    #expect(index.search("brief").map(\.path) == ["Work/Clients/Brief.md"])
    let ship = try #require(index["tasks/Ship it.md"])
    #expect(index.backlinks(to: ship).map(\.title) == ["Ark planning call"])
    #expect(index.items(titled: "reading list").map(\.path) == ["Reading list.md"])
}

@Test func notesStayOutOfTheToDoLists() async {
    let index = await noteIndex()
    let today = LocalDate("2026-10-10")!
    #expect(index.loose().map(\.title) == ["Ship it", "Task elsewhere"])
    #expect(index.today(today).isEmpty && index.upcoming(after: today).isEmpty)
    #expect(index.filesToLog(completedBefore: nil).isEmpty)
}
