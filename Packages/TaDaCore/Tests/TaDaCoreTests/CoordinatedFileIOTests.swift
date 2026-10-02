import Foundation
import Testing
@testable import TaDaCore

@Test func coordinatedReadWriteRoundTripsBytes() async throws {
    try await withTemporaryFolder { folder in
        let url = folder.appending(path: "a.md")
        let text = "---\r\ntype: task\r\n---\r\nÜber 🙂\n"
        try CoordinatedFileIO.write(text, to: url)
        #expect(try CoordinatedFileIO.read(url) == text)
        #expect(try Data(contentsOf: url) == Data(text.utf8))
        try CoordinatedFileIO.write("replaced", to: url)
        #expect(try CoordinatedFileIO.read(url) == "replaced")
    }
}

@Test func coordinatedCreateRefusesToOverwrite() async throws {
    try await withTemporaryFolder { folder in
        let url = folder.appending(path: "new/folder/a.md")
        try CoordinatedFileIO.create("first", at: url)
        #expect(throws: (any Error).self) { try CoordinatedFileIO.create("second", at: url) }
        #expect(try CoordinatedFileIO.read(url) == "first")
    }
}

@Test func coordinatedMoveAndErrors() async throws {
    try await withTemporaryFolder { folder in
        let a = folder.appending(path: "a.md"), b = folder.appending(path: "b.md")
        try CoordinatedFileIO.write("x", to: a)
        try CoordinatedFileIO.move(a, to: b)
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(try CoordinatedFileIO.read(b) == "x")
        #expect(throws: (any Error).self) { try CoordinatedFileIO.read(folder.appending(path: "missing.md")) }
        try Data([0xff, 0xfe, 0x00]).write(to: a)
        #expect(throws: FileIOError.notUTF8("a.md")) { try CoordinatedFileIO.read(a) }
    }
}
