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
        let result = try vault.moveIntoHome(index: await vault.loadIndex())
        #expect(result.moved == ["tasks/A.md": "Ta Da/tasks/A.md", "Projects/P.md": "Ta Da/projects/P.md",
                                 "areas/Home.md": "Ta Da/areas/Home.md", "attachments/front.jpg": "Ta Da/attachments/front.jpg",
                                 ".logbook/2026-09/Old.md": "Ta Da/Logbook/2026-09/Old.md"])
        #expect(try read("notes/Links.md", in: folder) == "See [[Ta Da/tasks/A|it]], [[A]], [[Ta Da/Logbook/2026-09/Old.md]] and [[Ta Da/projects/P]].\n![[Ta Da/attachments/front.jpg|300]] ![[front.jpg]]\n")
        #expect(result.relinked.map(\.path) == ["notes/Links.md"] && result.failed.isEmpty)
        for old in ["tasks", "Projects", "areas", "attachments", ".logbook"] { #expect(!exists(old, in: folder), "\(old)") }
        let index = await vault.loadIndex()
        #expect(index["Ta Da/Logbook/2026-09/Old.md"]?.isLogged == true && index["Ta Da/tasks/A.md"] != nil)
        #expect(vault.oldLayoutFolders().isEmpty)
        #expect(try vault.moveIntoHome(index: index).moved.isEmpty, "a second run finds nothing")
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
        let result = try vault.moveIntoHome(index: await vault.loadIndex())
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
        let result = try vault.moveIntoHome(index: await vault.loadIndex())
        #expect(result.moved == ["tasks/Mine.md": "Ta Da/tasks/Mine.md"])
    }
}
