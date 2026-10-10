import Foundation
import Testing
@testable import TaDaCore

@Test func saveAttachmentNumbersATakenName() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        let saved = try [("front.jpg", 1), ("Front.jpg", 2), ("a [b] #c.png", 3)].map { try vault.saveAttachment(Data([$1]), as: $0) }
        #expect(saved == ["attachments/front.jpg", "attachments/Front 2.jpg", "attachments/a b c.png"])
        #expect(try Data(contentsOf: vault.url(for: saved[1])) == Data([2]))
    }
}

@Test func attachmentPathPrefersAPathThenAttachmentsThenTheFirstMatch() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["notes/b/front.jpg", "notes/a/Front.JPG", ".trash/attachments/gone.png", "img/odometer.png", "attachments/odometer.png"] {
            try writeFile("x", path, in: folder)
        }
        let path = { (link: String) throws -> String? in vault.attachmentPath(for: try #require(WikiLink(link))) }
        #expect(try path("[[odometer.png]]") == "attachments/odometer.png")
        #expect(try path("[[img/odometer.png]]") == "img/odometer.png")
        #expect(try path("[[elsewhere/odometer.png]]") == "attachments/odometer.png")
        #expect(try path("[[front.jpg]]") == "notes/a/Front.JPG")
        #expect(try path("[[gone.png]]") == nil)
        #expect(try path("[[Note]]") == nil)
    }
}

@Test func attachmentPathsListImagesNewestFirstOutsideHiddenFolders() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["attachments/old.png", "notes/new.JPG", ".trash/attachments/gone.png", "notes/readme.md", "notes/report.pdf"] {
            try writeFile("x", path, in: folder)
        }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)],
                                              ofItemAtPath: vault.url(for: "attachments/old.png").path(percentEncoded: false))
        #expect(vault.attachmentPaths() == ["notes/new.JPG", "attachments/old.png"])
    }
}

@Test func attachmentPathsListNotYetDownloadedImagesUnderTheirRealNames() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["attachments/here.png", "notes/.Waiting.JPG.icloud", ".trash/attachments/.Gone.png.icloud", "notes/.Hidden.txt", ".Top.png.icloud"] {
            try writeFile("x", path, in: folder)
        }
        #expect(vault.attachmentPaths() == ["attachments/here.png", "Top.png", "notes/Waiting.JPG"])
        #expect(vault.attachmentPath(for: try #require(WikiLink("[[waiting.jpg]]"))) == "notes/Waiting.JPG")
    }
}

@Test func anEmbedNamesAnImageByItsFilenameUnlessAnotherComesFirst() {
    let paths = ["attachments/front.jpg", "notes/front.jpg", "notes/odometer.png"]
    #expect(Vault.embedTarget(for: "attachments/front.jpg", in: paths) == "front.jpg")
    #expect(Vault.embedTarget(for: "notes/front.jpg", in: paths) == "notes/front.jpg")
    #expect(Vault.embedTarget(for: "notes/odometer.png", in: paths) == "odometer.png")
}

@Test func retargetingEmbedsChangesOnlyThoseThatShowTheImage() {
    let paths = ["attachments/front.jpg", "notes/front.jpg", "attachments/odometer.png"]
    let text = """
    ---
    type: task
    cover: "![[front.jpg]]"
    ---
    ![[front.jpg]]
    Then ![[ front.jpg |320]] and ![[attachments/front.jpg]], not ![[notes/front.jpg]] or ![[odometer.png]].
    `![[front.jpg]]`

        ![[front.jpg]]

    """
    let expected = """
    ---
    type: task
    cover: "![[front.jpg]]"
    ---
    ![[Front side.jpg]]
    Then ![[ Front side.jpg |320]] and ![[attachments/Front side.jpg]], not ![[notes/front.jpg]] or ![[odometer.png]].
    `![[front.jpg]]`

        ![[front.jpg]]

    """
    #expect(Vault.retargetEmbeds(in: text, from: "attachments/front.jpg", to: "attachments/Front side.jpg", paths: paths) == expected)
}

@Test func renamingAnImageKeepsItsFolderAndExtensionAndRefusesATakenName() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["attachments/front.jpg", "notes/odometer.png"] { try writeFile("x", path, in: folder) }
        let paths = vault.attachmentPaths()
        let renamed = Vault.renamedAttachment("attachments/front.jpg", to: "Front: side?")
        #expect(renamed == "attachments/Front - side.jpg")
        #expect(Vault.renamedAttachment("attachments/front.jpg", to: "back.JPG") == "attachments/back.jpg")
        #expect(Vault.renamedAttachment("attachments/front.jpg", to: "back.png") == "attachments/back.png.jpg")
        #expect(!Vault.attachmentName(of: renamed, isTakenBesides: "attachments/front.jpg", in: paths))
        #expect(Vault.attachmentName(of: "attachments/Odometer.PNG", isTakenBesides: "attachments/front.jpg", in: paths))
        #expect(!Vault.attachmentName(of: "attachments/Front.jpg", isTakenBesides: "attachments/front.jpg", in: paths))
        try vault.renameAttachment("attachments/front.jpg", to: renamed)
        try vault.renameAttachment(renamed, to: "attachments/front side.jpg")
        #expect(Set(vault.attachmentPaths()) == ["attachments/front side.jpg", "notes/odometer.png"])
        try writeFile("y", "attachments/odometer.png", in: folder)
        #expect(throws: CocoaError.self) { try vault.renameAttachment("notes/odometer.png", to: "attachments/odometer.png") }
    }
}

@Test func anImagesEmbeddersAreTheFilesWhoseEmbedsShowIt() throws {
    let paths = ["attachments/front.jpg", "notes/front.jpg"]
    let a = try #require(Item(parsing: "---\ntype: task\n---\n![[front.jpg]] ![[front.jpg]]\n", path: "tasks/A.md"))
    let b = try #require(Item(parsing: "---\ntype: task\n---\n![[notes/front.jpg]]\n", path: "tasks/B.md"))
    let index = VaultIndex([a, b])
    #expect(index.embedders(ofAttachment: "attachments/front.jpg", among: paths).map { "\($0.item.title) \($0.count)" } == ["A 2"])
    #expect(index.embedders(ofAttachment: "notes/front.jpg", among: paths).map { "\($0.item.title) \($0.count)" } == ["B 1"])
}
