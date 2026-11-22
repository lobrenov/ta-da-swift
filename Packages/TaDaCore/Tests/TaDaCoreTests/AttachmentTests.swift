import Foundation
import Testing
@testable import TaDaCore

@Test func saveAttachmentNumbersATakenName() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        let saved = try [("front.jpg", 1), ("Front.jpg", 2), ("a [b] #c.png", 3)].map { try vault.saveAttachment(Data([$1]), as: $0) }
        #expect(saved == ["Ta Da/attachments/front.jpg", "Ta Da/attachments/Front 2.jpg", "Ta Da/attachments/a b c.png"])
        #expect(try Data(contentsOf: vault.url(for: saved[1])) == Data([2]))
    }
}

@Test func attachmentPathPrefersAPathThenAttachmentsThenTheFirstMatch() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["notes/b/front.jpg", "notes/a/Front.JPG", ".trash/attachments/gone.png", "img/odometer.png", "Ta Da/attachments/odometer.png"] {
            try writeFile("x", path, in: folder)
        }
        let path = { (link: String) throws -> String? in vault.attachmentPath(for: try #require(WikiLink(link))) }
        #expect(try path("[[odometer.png]]") == "Ta Da/attachments/odometer.png")
        #expect(try path("[[img/odometer.png]]") == "img/odometer.png")
        #expect(try path("[[elsewhere/odometer.png]]") == "Ta Da/attachments/odometer.png")
        #expect(try path("[[front.jpg]]") == "notes/a/Front.JPG")
        #expect(try path("[[gone.png]]") == nil)
        #expect(try path("[[Note]]") == nil)
    }
}

@Test func attachmentPathsListAttachmentsNewestFirstOutsideHiddenFolders() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["Ta Da/attachments/old.png", "notes/new.JPG", ".trash/attachments/gone.png", "notes/readme.md", "notes/README.MD", "notes/Makefile"] {
            try writeFile("x", path, in: folder)
        }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)],
                                              ofItemAtPath: vault.url(for: "Ta Da/attachments/old.png").path(percentEncoded: false))
        #expect(vault.attachmentPaths() == ["notes/new.JPG", "Ta Da/attachments/old.png"])
    }
}

@Test func attachmentPathsListNotYetDownloadedAttachmentsUnderTheirRealNames() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["Ta Da/attachments/here.png", "notes/.Waiting.JPG.icloud", ".trash/attachments/.Gone.png.icloud", "notes/.Hidden.txt", ".Top.png.icloud",
                     "notes/.kia-contract.pdf.icloud", "notes/.Note.md.icloud"] {
            try writeFile("x", path, in: folder)
        }
        #expect(vault.attachmentPaths() == ["Ta Da/attachments/here.png", "Top.png", "notes/Waiting.JPG", "notes/kia-contract.pdf"])
        #expect(vault.attachmentPath(for: try #require(WikiLink("[[waiting.jpg]]"))) == "notes/Waiting.JPG")
    }
}

@Test func attachmentPathsListAnyFileWithAnExtensionOtherThanMarkdown() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["a.pdf", "notes/b.XLSX", "c.zip", "d.png", "notes.md", "LICENSE", ".hidden.pdf", ".obsidian/e.pdf", ".trash/f.pdf",
                     "Ta Da/settings.json", "Ta Da/other.json"] {
            try writeFile("x", path, in: folder)
        }
        #expect(Set(vault.attachmentPaths()) == ["a.pdf", "notes/b.XLSX", "c.zip", "d.png", "Ta Da/other.json"])
        #expect(vault.attachmentPath(for: try #require(WikiLink("[[b.xlsx]]"))) == "notes/b.XLSX")
        #expect(vault.attachmentPath(for: try #require(WikiLink("[[a.pdf|Contract]]"))) == "a.pdf")
    }
}

@Test func anAttachmentHasAnExtensionOtherThanMarkdownAndAnImageHasAnImageOne() {
    #expect(["a.pdf", "b.XLSX", "c.png", "dir/d.zip", "clip.mp3", "x.7z"].allSatisfy(Vault.isAttachment))
    #expect(!["Note", "note.md", "Note.MD", "Ta Da/settings.json", "name.", ".hidden", "Version 1.2", "Meeting 2026.11.22", "a.b c"].contains(where: Vault.isAttachment))
    #expect(Vault.isImage("c.PNG") && !Vault.isImage("a.pdf"))
}

@Test func anEmbedNamesAnImageByItsFilenameUnlessAnotherComesFirst() {
    let paths = ["Ta Da/attachments/front.jpg", "notes/front.jpg", "notes/odometer.png"]
    #expect(Vault.embedTarget(for: "Ta Da/attachments/front.jpg", in: paths) == "front.jpg")
    #expect(Vault.embedTarget(for: "notes/front.jpg", in: paths) == "notes/front.jpg")
    #expect(Vault.embedTarget(for: "notes/odometer.png", in: paths) == "odometer.png")
}

@Test func retargetingEmbedsChangesOnlyThoseThatShowTheImage() {
    let paths = ["Ta Da/attachments/front.jpg", "notes/front.jpg", "Ta Da/attachments/odometer.png"]
    let text = """
    ---
    type: task
    cover: "![[front.jpg]]"
    ---
    ![[front.jpg]]
    Then ![[ front.jpg |320]] and ![[Ta Da/attachments/front.jpg]], not ![[notes/front.jpg]] or ![[odometer.png]].
    `![[front.jpg]]`

        ![[front.jpg]]

    """
    let expected = """
    ---
    type: task
    cover: "![[front.jpg]]"
    ---
    ![[Front side.jpg]]
    Then ![[ Front side.jpg |320]] and ![[Ta Da/attachments/Front side.jpg]], not ![[notes/front.jpg]] or ![[odometer.png]].
    `![[front.jpg]]`

        ![[front.jpg]]

    """
    #expect(Vault.retargetEmbeds(in: text, from: "Ta Da/attachments/front.jpg", to: "Ta Da/attachments/Front side.jpg", paths: paths) == expected)
}

@Test func renamingAnImageKeepsItsFolderAndExtensionAndRefusesATakenName() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["Ta Da/attachments/front.jpg", "notes/odometer.png", "docs/Contract.pdf"] { try writeFile("x", path, in: folder) }
        let paths = vault.attachmentPaths()
        let renamed = Vault.renamedAttachment("Ta Da/attachments/front.jpg", to: "Front: side?")
        #expect(renamed == "Ta Da/attachments/Front - side.jpg")
        #expect(Vault.renamedAttachment("Ta Da/attachments/front.jpg", to: "back.JPG") == "Ta Da/attachments/back.jpg")
        #expect(Vault.renamedAttachment("Ta Da/attachments/front.jpg", to: "back.png") == "Ta Da/attachments/back.png.jpg")
        #expect(!Vault.attachmentName(of: renamed, isTakenBesides: "Ta Da/attachments/front.jpg", in: paths))
        #expect(Vault.attachmentName(of: "Ta Da/attachments/Odometer.PNG", isTakenBesides: "Ta Da/attachments/front.jpg", in: paths))
        #expect(!Vault.attachmentName(of: "Ta Da/attachments/Front.jpg", isTakenBesides: "Ta Da/attachments/front.jpg", in: paths))
        #expect(Vault.attachmentName(of: "Ta Da/attachments/contract.PDF", isTakenBesides: "Ta Da/attachments/front.jpg", in: paths))
        try vault.renameAttachment("Ta Da/attachments/front.jpg", to: renamed)
        try vault.renameAttachment(renamed, to: "Ta Da/attachments/front side.jpg")
        #expect(Set(vault.attachmentPaths()) == ["Ta Da/attachments/front side.jpg", "notes/odometer.png", "docs/Contract.pdf"])
        try writeFile("y", "Ta Da/attachments/odometer.png", in: folder)
        #expect(throws: CocoaError.self) { try vault.renameAttachment("notes/odometer.png", to: "Ta Da/attachments/odometer.png") }
    }
}

@Test func anImagesEmbeddersAreTheFilesWhoseEmbedsShowIt() throws {
    let paths = ["Ta Da/attachments/front.jpg", "notes/front.jpg"]
    let a = try #require(Item(parsing: "---\ntype: task\n---\n![[front.jpg]] ![[front.jpg]]\n", path: "Ta Da/tasks/A.md"))
    let b = try #require(Item(parsing: "---\ntype: task\n---\n![[notes/front.jpg]]\n", path: "Ta Da/tasks/B.md"))
    let index = VaultIndex([a, b])
    #expect(index.embedders(ofAttachment: "Ta Da/attachments/front.jpg", among: paths).map { "\($0.item.title) \($0.count)" } == ["A 2"])
    #expect(index.embedders(ofAttachment: "notes/front.jpg", among: paths).map { "\($0.item.title) \($0.count)" } == ["B 1"])
}

@Test func renamingAPDFKeepsItsExtensionAndRetargetsItsEmbeds() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("x", "docs/old.pdf", in: folder)
        let paths = vault.attachmentPaths()
        let renamed = Vault.renamedAttachment("docs/old.pdf", to: "New contract")
        #expect(renamed == "docs/New contract.pdf")
        let text = "---\ntype: task\n---\n![[old.pdf]] ![[docs/old.pdf|Old]] [[old]]\n"
        #expect(Vault.retargetEmbeds(in: text, from: "docs/old.pdf", to: renamed, paths: paths)
                == "---\ntype: task\n---\n![[New contract.pdf]] ![[docs/New contract.pdf|Old]] [[old]]\n")
    }
}

@Test func copyAttachmentCopiesTheFileAndRefusesATakenPath() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder.appending(path: "Vault"))
        try writeFile("pdf", "Source/report.pdf", in: folder)
        let source = folder.appending(path: "Source/report.pdf")
        try vault.copyAttachment(from: source, to: "Ta Da/attachments/report.pdf")
        #expect(try Data(contentsOf: vault.url(for: "Ta Da/attachments/report.pdf")) == Data("pdf".utf8))
        #expect(throws: (any Error).self) { try vault.copyAttachment(from: source, to: "Ta Da/attachments/report.pdf") }
    }
}

@Test func aSettingsPlaceholderIsNotAnAttachment() async throws {
    try await withTemporaryFolder { folder in
        for path in ["Ta Da/.settings.json.icloud", "notes/.settings.json.icloud"] { try writeFile("", path, in: folder) }
        #expect(Vault(root: folder).attachmentPaths() == ["notes/settings.json"])
    }
}
