import Foundation
import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-12")!

private func read(_ path: String, in folder: URL) throws -> String {
    try String(contentsOf: folder.appending(path: path), encoding: .utf8)
}

private func exists(_ path: String, in folder: URL) -> Bool {
    FileManager.default.fileExists(atPath: folder.appending(path: path).path(percentEncoded: false))
}

// MARK: Frontmatter

@Test func insertAtTopGoesAfterTheOpeningFence() {
    let keys: [(key: String, value: PropertyValue)] = [("type", .text("task")), ("status", .text("Not Started"))]
    #expect(FrontmatterEditor.insertAtTop(keys, in: "---\ntags: [a]\n---\nBody\n")
        == "---\ntype: task\nstatus: Not Started\ntags: [a]\n---\nBody\n")
    #expect(FrontmatterEditor.insertAtTop(keys, in: "---\r\ntags: []\r\n---\r\n") == "---\r\ntype: task\r\nstatus: Not Started\r\ntags: []\r\n---\r\n")
    #expect(FrontmatterEditor.insertAtTop(keys, in: "Body\n") == "---\ntype: task\nstatus: Not Started\n---\nBody\n")
    #expect(FrontmatterEditor.contains("tags", in: "---\ntags:\n---\n") && !FrontmatterEditor.contains("tags", in: "tags: x\n"))
}

// MARK: Conversion

@Test func convertingSplicesKeysAheadOfTheNotesOwn() {
    let note = "---\ncreatedDate: 2026-10-04\ntags: [work/ark]\n---\n- [ ] Dates\n"
    #expect(NoteConversion.text(note, to: .task, status: .notStarted, parent: .project("Ark"), today: today)
        == "---\ntype: task\nstatus: Not Started\nproject: \"[[Ark]]\"\ncreatedDate: 2026-10-04\ntags: [work/ark]\n---\n- [ ] Dates\n")
    #expect(NoteConversion.text(note, to: .area, status: .doing, parent: .area("Work"), today: today)
        == "---\ntype: area\ncreatedDate: 2026-10-04\ntags: [work/ark]\n---\n- [ ] Dates\n")
    #expect(NoteConversion.text("Body\n", to: .project, status: .notStarted, parent: .area("Work"), today: today)
        == "---\ntype: project\nstatus: Not Started\narea: \"[[Work]]\"\ncreatedDate: 2026-10-12\n---\nBody\n")
}

@Test func convertingSetsKeysTheNoteAlreadyHas() throws {
    let note = "---\ntype: meeting\nstatus: whatever\ncreatedDate:\narea: \"[[Old]]\"\ntags: []\n---\n"
    let text = NoteConversion.text(note, to: .task, status: .done, parent: nil, today: today)
    #expect(text == "---\ntype: task\nstatus: Done\ncreatedDate: 2026-10-12\narea:\ntags: []\ncompletedDate: 2026-10-12\n---\n")
    let task = try #require(Item(parsing: text, path: "tasks/x.md"))
    #expect(task.properties.kind == .task && task.properties.area == nil && task.warnings.isEmpty)
}

@Test func convertMovesTheNoteNumbersTakenNamesAndFollowsLinks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("---\ntags: []\n---\nAgenda\n", "Meetings/Ark.md", in: folder)
        try writeFile("---\ntype: project\nstatus: Done\n---\n", ".logbook/2026-09/Ark.md", in: folder)
        try writeFile("See [[Meetings/Ark|the call]], [[Ark#Agenda]] and [[Meetings/Ark.md]].\n", "Links.md", in: folder)
        let result = try vault.convert("Meetings/Ark.md", to: .project, index: await vault.loadIndex(), today: today)
        #expect(result.path == "projects/Ark 2.md" && result.failed.isEmpty)
        #expect(try read("projects/Ark 2.md", in: folder) == "---\ntype: project\nstatus: Not Started\ncreatedDate: 2026-10-12\ntags: []\n---\nAgenda\n")
        #expect(!exists("Meetings/Ark.md", in: folder))
        #expect(try read("Links.md", in: folder) == "See [[projects/Ark 2|the call]], [[Ark 2#Agenda]] and [[projects/Ark 2.md]].\n")
        #expect(result.relinked.map(\.path) == ["Links.md"])
    }
}

@Test func convertKeepsCRLFAndCreatedDatesItCantRead() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("---\r\ncreatedDate: 2024-01-05 10:22\r\n---\r\nBody\r\n", "Note.md", in: folder)
        let result = try vault.convert("Note.md", to: .area, index: await vault.loadIndex(), today: today)
        #expect(try read(result.path, in: folder) == "---\r\ntype: area\r\ncreatedDate: 2024-01-05 10:22\r\n---\r\nBody\r\n")
    }
}

@Test func convertReadsBackFromOddFrontmatter() throws {
    for note in ["---\nnever closed\n", "---\n- a\n---\n", "---\n---\n"] {
        let text = NoteConversion.text(note, to: .task, status: .notStarted, parent: nil, today: today)
        #expect(Item(parsing: text, path: "tasks/x.md")?.properties.kind == .task, "\(note)")
    }
}

@Test func aFailedMovePutsTheNoteBack() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("Body\n", "Note.md", in: folder)
        try writeFile("not a folder", "tasks", in: folder)
        let index = await vault.loadIndex()
        #expect(throws: (any Error).self) { try vault.convert("Note.md", to: .task, index: index, today: today) }
        #expect(try read("Note.md", in: folder) == "Body\n")
    }
}

@Test func convertLeavesTypedFilesAlone() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("---\ntype: task\nstatus: Doing\n---\n", "tasks/T.md", in: folder)
        let result = try vault.convert("tasks/T.md", to: .project, index: await vault.loadIndex(), today: today)
        #expect(result.path == "tasks/T.md" && exists("tasks/T.md", in: folder))
    }
}

// MARK: Folders and moves

@Test func foldersAreMadeNumberedRenamedAndTrashedWhole() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        #expect(try vault.createFolder(named: "Untitled folder", in: "") == "Untitled folder")
        #expect(try vault.createFolder(named: "untitled folder", in: "") == "untitled folder 2")
        #expect(try vault.createFolder(named: "Calls: 2026", in: "Untitled folder") == "Untitled folder/Calls - 2026")
        #expect(vault.emptyFolders() == ["Untitled folder", "Untitled folder/Calls - 2026", "untitled folder 2"])

        try writeFile("Body\n", "Work/Meetings/Ark.md", in: folder)
        try writeFile("[[Work/Meetings/Ark]] and [[work/meetings/Ark.md|call]] and [[Ark]] and [[Work/Other]]\n", "Links.md", in: folder)
        try writeFile("[[Work/Meetings/Ark]]\n", "Work/Meetings/Self.md", in: folder)
        let renamed = try vault.renameFolder("Work/Meetings", to: "Calls", index: await vault.loadIndex())
        #expect(renamed.path == "Work/Calls" && renamed.failed.isEmpty)
        #expect(try read("Links.md", in: folder) == "[[Work/Calls/Ark]] and [[Work/Calls/Ark.md|call]] and [[Ark]] and [[Work/Other]]\n")
        #expect(try read("Work/Calls/Self.md", in: folder) == "[[Work/Calls/Ark]]\n")
        #expect(renamed.relinked.map(\.path).sorted() == ["Links.md", "Work/Calls/Self.md"])
        #expect(try vault.renameFolder("Work/Calls", to: "Calls", index: await vault.loadIndex()).path == "Work/Calls")

        #expect(try vault.trashFolder("Work/Calls") == ".trash/Work/Calls")
        #expect(Set(vault.trashedItems().map(\.id)) == [".trash/Work/Calls/Ark.md", ".trash/Work/Calls/Self.md"])
        try FileManager.default.createDirectory(at: folder.appending(path: "Work/Empty"), withIntermediateDirectories: true)
        #expect(try vault.trashFolder("Work/Empty") == ".trash/Work/Empty")
        #expect(!exists("Work/Empty", in: folder) && !exists(".trash/Work/Empty", in: folder), "an empty folder is removed")
    }
}

@Test func caseOnlyFolderRenamesKeepTheNameAndRelink() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("Body\n", "Meetings/Ark.md", in: folder)
        try writeFile("[[Meetings/Ark]]\n", "Links.md", in: folder)
        let renamed = try vault.renameFolder("Meetings", to: "meetings", index: await vault.loadIndex())
        #expect(renamed.path == "meetings")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).contains("meetings"))
        #expect(try read("Links.md", in: folder) == "[[meetings/Ark]]\n")
    }
}

@Test func movingANoteNumbersItsNameAndFollowsPathLinks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("A\n", "Inbox/Idea.md", in: folder)
        try writeFile("B\n", "Idea.md", in: folder)
        try writeFile("[[Inbox/Idea]] [[Idea]]\n", "Links.md", in: folder)
        let index = await vault.loadIndex()
        #expect(try vault.moveNote("Inbox/Idea.md", to: "Inbox", index: index).path == "Inbox/Idea.md")
        let moved = try vault.moveNote("Inbox/Idea.md", to: "", index: index)
        #expect(moved.path == "Idea 2.md")
        #expect(try read("Links.md", in: folder) == "[[Idea 2]] [[Idea]]\n", "the plain link found the top-level note, so it stays")
    }
}

// MARK: Trash

@Test func trashedNotesKeepTheirFolderAndGoBackToIt() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("A\n", "Meetings/Ark.md", in: folder)
        try writeFile("B\n", "Loose.md", in: folder)
        #expect(try vault.moveToTrash("Meetings/Ark.md", index: await vault.loadIndex()) == ["Meetings/Ark.md"])
        #expect(try vault.moveToTrash("Loose.md", index: await vault.loadIndex()) == ["Loose.md"])
        #expect(Set(vault.trashedItems().map(\.id)) == [".trash/Meetings/Ark.md", ".trash/Loose.md"])

        try FileManager.default.removeItem(at: folder.appending(path: "Meetings"))
        try writeFile("Taken\n", "Loose.md", in: folder)
        let restored = try vault.restore([".trash/Meetings/Ark.md", ".trash/Loose.md"], index: await vault.loadIndex(), today: today)
        #expect(Set(restored) == ["Meetings/Ark.md", "Loose 2.md"])
        #expect(try read("Meetings/Ark.md", in: folder) == "A\n")
        #expect(!exists(".trash/Meetings", in: folder), "emptied folders in .trash go")
    }
}

@Test func aFolderTrashedAfterOneOfItsNotesMergesAndComesBackWhole() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("A\n", "Meetings/Ark.md", in: folder)
        try writeFile("B\n", "Meetings/2026/Standup.md", in: folder)
        _ = try vault.moveToTrash("Meetings/Ark.md", index: await vault.loadIndex())
        try writeFile("A again\n", "Meetings/Ark.md", in: folder)
        #expect(try vault.trashFolder("Meetings") == ".trash/Meetings")
        #expect(!exists("Meetings", in: folder))
        let trashed = Set(vault.trashedItems().map(\.id))
        #expect(trashed == [".trash/Meetings/Ark.md", ".trash/Meetings/Ark 2.md", ".trash/Meetings/2026/Standup.md"])
        let restored = try vault.restore(Array(trashed), index: await vault.loadIndex(), today: today)
        #expect(Set(restored) == ["Meetings/Ark.md", "Meetings/Ark 2.md", "Meetings/2026/Standup.md"])
        #expect(!exists(".trash/Meetings", in: folder))
    }
}

@Test func aNoteWhoseFolderIsNowAFileRestoresToTheTopLevel() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("A\n", "Meetings/Ark.md", in: folder)
        _ = try vault.moveToTrash("Meetings/Ark.md", index: await vault.loadIndex())
        try FileManager.default.removeItem(at: folder.appending(path: "Meetings"))
        try writeFile("a file", "Meetings", in: folder)
        #expect(try vault.restore([".trash/Meetings/Ark.md"], index: await vault.loadIndex(), today: today) == ["Ark.md"])
    }
}
