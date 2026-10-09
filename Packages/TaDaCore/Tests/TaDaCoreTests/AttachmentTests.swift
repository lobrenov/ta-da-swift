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
