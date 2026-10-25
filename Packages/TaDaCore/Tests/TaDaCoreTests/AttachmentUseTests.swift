import Foundation
import Testing
@testable import TaDaCore

private func note(embedding names: String...) -> String {
    "---\ntype: task\nstatus: Not Started\n---\n" + names.map { "![[\($0)]]\n" }.joined()
}

/// Writes the files, loads the index and trash, and returns each `Ta Da/attachments/` image's use by filename.
private func uses(_ files: [String: String], images: [String], in folder: URL) async throws -> (groups: AttachmentGroups, byName: [String: AttachmentUse]) {
    let vault = Vault(root: folder)
    for (path, text) in files { try writeFile(text, path, in: folder) }
    for path in images { try writeFile("x", path, in: folder) }
    let groups = await vault.attachmentGroups(index: await vault.loadIndex(), trashed: vault.trashedItems())
    return (groups, Dictionary((groups.candidates + groups.inUse).map { ($0.attachment.name, $0) }, uniquingKeysWith: { first, _ in first }))
}

@Test func attachmentsAreGroupedAndSortedByFilenameInFinderOrder() async throws {
    try await withTemporaryFolder { folder in
        let images = ["b 10.png", "B 2.png", "a.png", "c.png"].map { "Ta Da/attachments/" + $0 }
        let (groups, _) = try await uses(["Ta Da/tasks/Live.md": note(embedding: "c.png", "b 10.png")], images: images, in: folder)
        #expect(groups.candidates.map(\.attachment.name) == ["a.png", "B 2.png"])
        #expect(groups.inUse.map(\.attachment.name) == ["b 10.png", "c.png"])
    }
}

@Test func eachCleanUpReasonIsTold() async throws {
    try await withTemporaryFolder { folder in
        let files = [
            "Ta Da/logbook/2026-09/Logged.md": note(embedding: "logged.png", "both.png"),
            ".trash/Trashed.md": note(embedding: "trashed.png", "both.png"),
            "Ta Da/tasks/Live.md": note(embedding: "live.png", "gone.png"),
        ]
        let images = ["logged", "trashed", "both", "none", "live"].map { "Ta Da/attachments/\($0).png" }
        let (groups, byName) = try await uses(files, images: images, in: folder)
        #expect(byName["logged.png"]?.cleanUpReason == .loggedOnly)
        #expect(byName["trashed.png"]?.cleanUpReason == .trashedOnly)
        #expect(byName["both.png"]?.cleanUpReason == .loggedAndTrashed)
        #expect(byName["none.png"]?.cleanUpReason == .unused)
        #expect(byName["live.png"]?.cleanUpReason == nil)
        #expect(byName["live.png"]?.live.map(\.title) == ["Live"])
        #expect(byName["both.png"]?.logged.map(\.title) == ["Logged"])
        #expect(byName["both.png"]?.trashed.map(\.item.title) == ["Trashed"])
        #expect(groups.inUse.map(\.attachment.name) == ["live.png"])
    }
}

@Test func aLiveEmbedKeepsAnImageInUseAlongsideLoggedAndTrashedOnes() async throws {
    try await withTemporaryFolder { folder in
        let files = [
            "Ta Da/logbook/2026-09/Logged.md": note(embedding: "a.png"),
            ".trash/Trashed.md": note(embedding: "a.png"),
            "Ta Da/tasks/Live.md": note(embedding: "a.png"),
        ]
        let (_, byName) = try await uses(files, images: ["Ta Da/attachments/a.png"], in: folder)
        let use = try #require(byName["a.png"])
        #expect(use.isInUse && use.cleanUpReason == nil)
        #expect(use.live.count == 1 && use.logged.count == 1 && use.trashed.count == 1)
    }
}

@Test func anEmbedCountsOnlyForTheImageItResolvesTo() async throws {
    try await withTemporaryFolder { folder in
        let files = [
            "Ta Da/tasks/Live.md": note(embedding: "front.jpg"),
            ".trash/Trashed.md": note(embedding: "side.jpg"),
        ]
        let (_, byName) = try await uses(files, images: ["Ta Da/attachments/front.jpg", "Ta Da/attachments/side.jpg"], in: folder)
        #expect(byName["front.jpg"]?.isInUse == true)
        #expect(byName["side.jpg"]?.cleanUpReason == .trashedOnly)
    }
}

@Test func aSameNamedImageThatWinsResolutionLeavesTheAttachmentsOneUnused() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(note(embedding: "A/dup.png"), "Ta Da/tasks/Live.md", in: folder)
        for path in ["Ta Da/attachments/dup.png", "Ta Da/attachments/other.png", "A/dup.png"] { try writeFile("x", path, in: folder) }
        let groups = await vault.attachmentGroups(index: await vault.loadIndex(), trashed: [])
        #expect(groups.candidates.map(\.attachment.path) == ["Ta Da/attachments/dup.png", "Ta Da/attachments/other.png"])
        #expect(groups.inUse.isEmpty)
    }
}

@Test func onlyTheAttachmentsFolderIsListed() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        for path in ["Ta Da/attachments/a.png", "Ta Da/attachments/sub/b.png", "Ta Da/attachments/note.txt", "Ta Da/other/c.png",
                     "attachments/d.png", "notes/e.png", ".trash/attachments/f.png"] {
            try writeFile("x", path, in: folder)
        }
        #expect(vault.taDaAttachments().map(\.path) == ["Ta Da/attachments/a.png"])
        let image = try #require(vault.taDaAttachments().first)
        #expect(image.size == 1 && image.isDownloaded && image.added != nil)
    }
}

@Test func placeholdersAreListedUnderTheirRealNamesWithTheirRecordedSize() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["NSURLNameKey": "Waiting.png", "NSURLFileSizeKey": 4096], format: .binary, options: 0)
        let folderURL = vault.url(for: Vault.attachmentFolder)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try plist.write(to: folderURL.appending(path: ".Waiting.png.icloud"))
        try writeFile("not a plist", "Ta Da/attachments/.NoSize.png.icloud", in: folder)
        try writeFile("x", "Ta Da/attachments/.Hidden.png", in: folder)
        let found = Dictionary(uniqueKeysWithValues: vault.taDaAttachments().map { ($0.name, $0) })
        #expect(Set(found.keys) == ["Waiting.png", "NoSize.png"])
        #expect(found["Waiting.png"]?.path == "Ta Da/attachments/Waiting.png")
        #expect(found["Waiting.png"]?.size == 4096 && found["Waiting.png"]?.isDownloaded == false)
        #expect(found["NoSize.png"]?.size == nil)
    }
}

@Test func totalSizesAddUpTheGroupsCountingUnknownSizesAsZero() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(note(embedding: "used.png"), "Ta Da/tasks/Live.md", in: folder)
        try writeFile(String(repeating: "x", count: 10), "Ta Da/attachments/used.png", in: folder)
        try writeFile(String(repeating: "x", count: 5), "Ta Da/attachments/spare.png", in: folder)
        try writeFile("not a plist", "Ta Da/attachments/.NoSize.png.icloud", in: folder)
        let groups = await vault.attachmentGroups(index: await vault.loadIndex(), trashed: [])
        #expect(groups.inUseSize == 10 && groups.candidatesSize == 5 && groups.totalSize == 15)
        #expect(Attachment.totalSize(of: []) == 0)
    }
}

@Test func theFoldersSpellingOnDiskIsKeptSoItsImagesStillResolve() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(note(embedding: "a.png"), "Ta Da/tasks/Live.md", in: folder)
        try writeFile("x", "Ta Da/Attachments/a.png", in: folder)
        let groups = await vault.attachmentGroups(index: await vault.loadIndex(), trashed: [])
        #expect(groups.inUse.map(\.attachment.path) == ["Ta Da/Attachments/a.png"])
        #expect(groups.candidates.isEmpty)
    }
}

@Test func markdownFilesStillToDownloadAreReported() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("x", "Ta Da/attachments/a.png", in: folder)
        for path in ["Ta Da/tasks/.Waiting.md.icloud", ".trash/.Binned.md.icloud", "Ta Da/logbook/2026-09/.Old.md.icloud",
                     ".other/.Hidden.md.icloud", "Ta Da/attachments/.b.png.icloud"] {
            try writeFile("x", path, in: folder)
        }
        let groups = await vault.attachmentGroups(index: await vault.loadIndex(), trashed: [])
        #expect(groups.pendingFiles == [".trash/Binned.md", "Ta Da/logbook/2026-09/Old.md", "Ta Da/tasks/Waiting.md"])
    }
}

@Test func anImageAndItsPlaceholderAreListedOnceAsDownloaded() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("xyz", "Ta Da/attachments/a.png", in: folder)
        try writeFile("x", "Ta Da/attachments/.a.png.icloud", in: folder)
        let found = vault.taDaAttachments()
        #expect(found.map(\.path) == ["Ta Da/attachments/a.png"])
        #expect(found.first?.isDownloaded == true && found.first?.size == 3)
    }
}
