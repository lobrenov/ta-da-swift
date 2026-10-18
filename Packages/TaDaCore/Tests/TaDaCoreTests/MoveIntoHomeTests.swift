import Foundation
import Testing
@testable import TaDaCore

private let task = "---\ntype: task\nstatus: Doing\n---\n"
private let logged = "---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-30\n---\n"

private func read(_ path: String, in folder: URL) throws -> String {
    try String(contentsOf: folder.appending(path: path), encoding: .utf8)
}

private func exists(_ path: String, in folder: URL) -> Bool {
    FileManager.default.fileExists(atPath: folder.appending(path: path).path(percentEncoded: false))
}

@Test func theOldLayoutMovesWholeIntoTaDa() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(task, "tasks/A.md", in: folder)
        try writeFile("---\ntype: project\nstatus: Doing\n---\n", "Projects/P.md", in: folder)
        try writeFile("---\ntype: area\n---\n", "areas/Home.md", in: folder)
        try writeFile("jpg", "attachments/front.jpg", in: folder)
        try writeFile(logged, ".logbook/2026-09/Old.md", in: folder)
        try writeFile("", "tasks/.DS_Store", in: folder)
        try writeFile("See [[tasks/A|it]], [[A]], [[.logbook/2026-09/Old.md]] and [[Projects/P]].\n![[attachments/front.jpg|300]] ![[front.jpg]]\n",
                      "notes/Links.md", in: folder)
        #expect(vault.oldLayoutFolders().map(\.to) == ["Ta Da/Logbook", "Ta Da/projects", "Ta Da/areas", "Ta Da/attachments", "Ta Da/tasks"])
        let result = vault.moveIntoHome(index: await vault.loadIndex())
        #expect(result.moved == ["tasks/A.md": "Ta Da/tasks/A.md", "Projects/P.md": "Ta Da/projects/P.md",
                                 "areas/Home.md": "Ta Da/areas/Home.md", "attachments/front.jpg": "Ta Da/attachments/front.jpg",
                                 ".logbook/2026-09/Old.md": "Ta Da/Logbook/2026-09/Old.md"])
        #expect(try read("notes/Links.md", in: folder) == "See [[Ta Da/tasks/A|it]], [[A]], [[Ta Da/Logbook/2026-09/Old.md]] and [[Ta Da/projects/P]].\n![[Ta Da/attachments/front.jpg|300]] ![[front.jpg]]\n")
        #expect(result.relinked.map(\.path) == ["notes/Links.md"] && result.failed.isEmpty)
        for old in ["tasks", "Projects", "areas", "attachments", ".logbook"] { #expect(!exists(old, in: folder), "\(old)") }
        let index = await vault.loadIndex()
        #expect(index["Ta Da/Logbook/2026-09/Old.md"]?.isLogged == true && index["Ta Da/tasks/A.md"] != nil)
        #expect(vault.oldLayoutFolders().isEmpty)
        #expect(vault.moveIntoHome(index: index).moved.isEmpty, "a second run finds nothing")
    }
}

@Test func movingIntoAFilledFolderNumbersTakenNamesAndLinksFollow() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("Not a Ta Da file.\n", "Ta Da/tasks/A.md", in: folder)
        try writeFile("new", "Ta Da/attachments/front.jpg", in: folder)
        try writeFile(task, "tasks/A.md", in: folder)
        try writeFile(task, "tasks/deep/B.md", in: folder)
        try writeFile("old", "attachments/front.jpg", in: folder)
        try writeFile("[[A]], [[tasks/A.md]], [[tasks/deep/B]] ![[attachments/front.jpg]] ![[front.jpg]]\n", "Links.md", in: folder)
        let result = vault.moveIntoHome(index: await vault.loadIndex())
        #expect(result.moved == ["tasks/A.md": "Ta Da/tasks/A 2.md", "tasks/deep/B.md": "Ta Da/tasks/deep/B.md",
                                 "attachments/front.jpg": "Ta Da/attachments/front 2.jpg"])
        #expect(try read("Links.md", in: folder)
                == "[[A 2]], [[Ta Da/tasks/A 2.md]], [[Ta Da/tasks/deep/B]] ![[Ta Da/attachments/front 2.jpg]] ![[front.jpg]]\n")
        #expect(try read("Ta Da/attachments/front.jpg", in: folder) == "new" && !exists("tasks", in: folder))
    }
}

@Test func aFileAnotherDeviceMovedIsSkipped() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(task, "Ta Da/tasks/Here.md", in: folder)
        try writeFile(task, "tasks/Mine.md", in: folder)
        // An iCloud Drive placeholder whose file isn't on this device any more.
        try writeFile("", "tasks/.Gone.md.icloud", in: folder)
        let result = vault.moveIntoHome(index: await vault.loadIndex())
        #expect(result.moved == ["tasks/Mine.md": "Ta Da/tasks/Mine.md"])
        #expect(result.notMoved == ["tasks/Gone.md"], "not downloaded yet")
        #expect(vault.oldLayoutFolders().map(\.from) == ["tasks"], "offered again")
        try FileManager.default.removeItem(at: folder.appending(path: "tasks/.Gone.md.icloud"))
        try writeFile(task, "tasks/Gone.md", in: folder)
        try FileManager.default.removeItem(at: folder.appending(path: "tasks/Gone.md"))
        #expect(vault.moveIntoHome(index: await vault.loadIndex()).notMoved.isEmpty, "a file that's gone is skipped")
    }
}

@Test func aNumberedProjectKeepsItsTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("Not a Ta Da file.\n", "Ta Da/projects/P.md", in: folder)
        try writeFile("---\ntype: project\nstatus: Doing\n---\n", "projects/P.md", in: folder)
        try writeFile("---\ntype: task\nstatus: Doing\nproject: \"[[P]]\"\n---\n", "tasks/T.md", in: folder)
        let result = vault.moveIntoHome(index: await vault.loadIndex())
        #expect(result.moved["projects/P.md"] == "Ta Da/projects/P 2.md")
        #expect(try read("Ta Da/tasks/T.md", in: folder).contains("project: \"[[P 2]]\""))
        #expect(result.relinked.map(\.path) == ["Ta Da/tasks/T.md"])
    }
}

@Test func filesGoIntoTaDasFolderAsNamedOnDisk() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(task, "ta da/Tasks/Here.md", in: folder)
        try writeFile(task, "tasks/A.md", in: folder)
        try writeFile("pdf", "attachments/report.pdf", in: folder)
        try writeFile("[[attachments/report.pdf]] ![[attachments/report.pdf]] ![[tasks/A#Top]]\n", "Links.md", in: folder)
        let result = vault.moveIntoHome(index: await vault.loadIndex())
        #expect(result.moved == ["tasks/A.md": "ta da/Tasks/A.md", "attachments/report.pdf": "ta da/attachments/report.pdf"])
        #expect(try read("Links.md", in: folder) == "[[ta da/attachments/report.pdf]] ![[ta da/attachments/report.pdf]] ![[ta da/Tasks/A#Top]]\n")
    }
}
