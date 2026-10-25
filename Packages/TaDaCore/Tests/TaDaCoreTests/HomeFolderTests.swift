import Foundation
import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-02")!
private let done = "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-01\n---\n"

@Test func newFilesGoInTaDasFolder() {
    #expect(Vault.taskFolder == "Ta Da/tasks" && Vault.projectFolder == "Ta Da/projects" && Vault.areaFolder == "Ta Da/areas")
    #expect(Vault.attachmentFolder == "Ta Da/attachments" && Vault.logbookFolder(for: today) == "Ta Da/logbook/2026-10")
}

@Test func theLogbookHoldsLoggedFiles() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(done, "Ta Da/logbook/2026-09/Old.md", in: folder)
        try writeFile(done, "Ta Da/logbook/2026-10/New.md", in: folder)
        try writeFile(done, "tasks/Live.md", in: folder)
        let index = await vault.loadIndex()
        #expect(Set(index.logged.map(\.path)) == ["Ta Da/logbook/2026-09/Old.md", "Ta Da/logbook/2026-10/New.md"])
        let moved = try vault.log(["tasks/Live.md"], index: index, today: today)
        #expect(moved == ["tasks/Live.md": "Ta Da/logbook/2026-10/Live.md"])
        try writeFile("---\ntype: task\nstatus: Doing\n---\n", "Ta Da/logbook/2026-09/Old.md", in: folder)
        let back = try vault.unlog(["Ta Da/logbook/2026-09/Old.md"], index: await vault.loadIndex(), today: today)
        #expect(back == ["Ta Da/logbook/2026-09/Old.md": "Ta Da/tasks/Old.md"])
    }
}

@Test func untypedFilesInTaDasFolderArentNotes() async throws {
    #expect(!Item.isNotePath("Ta Da/Readme.md") && !Item.isNotePath("ta da/deep/Readme.md"))
    #expect(Item.isNotePath("tasks/Readme.md") && Item.isNotePath("Ta Da 2/Readme.md"))
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["Ta Da/tasks", "Ta Da/logbook/2026-10", "Empty"] {
            try FileManager.default.createDirectory(at: folder.appending(path: path), withIntermediateDirectories: true)
        }
        #expect(vault.emptyFolders() == ["Empty"])
    }
}

@Test func embedsPreferTaDasAttachments() {
    let link = WikiLink(inner: "front.jpg")!
    #expect(Vault.attachmentPath(for: link, in: ["a/front.jpg", "Ta Da/attachments/front.jpg"]) == "Ta Da/attachments/front.jpg")
    #expect(Vault.attachmentPath(for: link, in: ["b/front.jpg", "a/front.jpg"]) == "a/front.jpg")
}

@Test func theLogbookIsFoundInAnyCase() {
    #expect(Item.isLogged("ta da/logbook/2026-10/X.md"))
    #expect(!Item.isLogged("Ta Da/tasks/X.md") && !Item.isLogged("Logbook/X.md"))
}
