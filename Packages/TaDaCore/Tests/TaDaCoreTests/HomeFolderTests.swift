import Foundation
import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-02")!
private let done = "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-01\n---\n"

@Test func newFilesGoInTaDasFolder() {
    #expect(Vault.taskFolder == "Ta Da/tasks" && Vault.projectFolder == "Ta Da/projects" && Vault.areaFolder == "Ta Da/areas")
    #expect(Vault.attachmentFolder == "Ta Da/attachments" && Vault.logbookFolder(for: today) == "Ta Da/Logbook/2026-10")
}

@Test func bothLogbooksHoldLoggedFiles() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(done, ".logbook/2026-09/Old.md", in: folder)
        try writeFile(done, "Ta Da/Logbook/2026-10/New.md", in: folder)
        try writeFile(done, "tasks/Live.md", in: folder)
        let index = await vault.loadIndex()
        #expect(Set(index.logged.map(\.path)) == [".logbook/2026-09/Old.md", "Ta Da/Logbook/2026-10/New.md"])
        let moved = try vault.log(["tasks/Live.md"], index: index, today: today)
        #expect(moved == ["tasks/Live.md": "Ta Da/Logbook/2026-10/Live.md"])
        try writeFile("---\ntype: task\nstatus: Doing\n---\n", ".logbook/2026-09/Old.md", in: folder)
        let back = try vault.unlog([".logbook/2026-09/Old.md"], index: await vault.loadIndex(), today: today)
        #expect(back == [".logbook/2026-09/Old.md": "Ta Da/tasks/Old.md"])
    }
}

@Test func untypedFilesInTaDasFolderArentNotes() async throws {
    #expect(!Item.isNotePath("Ta Da/Readme.md") && !Item.isNotePath("ta da/deep/Readme.md"))
    #expect(!Item.isNotePath("tasks/Readme.md") && Item.isNotePath("Ta Da 2/Readme.md"))
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["Ta Da/tasks", "Ta Da/Logbook/2026-10", "Empty"] {
            try FileManager.default.createDirectory(at: folder.appending(path: path), withIntermediateDirectories: true)
        }
        #expect(vault.emptyFolders() == ["Empty"])
    }
}

@Test func embedsPreferTaDasAttachmentsThenTheOldFolder() {
    let link = WikiLink(inner: "front.jpg")!
    #expect(Vault.attachmentPath(for: link, in: ["a/front.jpg", "attachments/front.jpg", "Ta Da/attachments/front.jpg"])
        == "Ta Da/attachments/front.jpg")
    #expect(Vault.attachmentPath(for: link, in: ["a/front.jpg", "attachments/front.jpg"]) == "attachments/front.jpg")
    #expect(Vault.attachmentPath(for: link, in: ["b/front.jpg", "a/front.jpg"]) == "a/front.jpg")
}
