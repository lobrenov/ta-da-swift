import Foundation
import Testing
@testable import TaDaCore

@Test(arguments: [
    ("Game Jam: Starfall", "Game Jam - Starfall"),
    ("Ta Da MVP", "Ta Da MVP"),
    ("a/b\\c|d", "a-b-c-d"),
    ("What? *Now* \"quoted\" <tag>", "What Now quoted tag"),
    ("[[Link]] #tag ^block", "Link tag block"),
    ("Dan’s café ☕️", "Dan’s café ☕️"),
    ("  spaced   out  ", "spaced out"),
    ("..hidden", "hidden"),
    ("line\nbreak", "line break"),
    ("", "Untitled"),
    ("???", "Untitled"),
])
func sanitiseTitles(_ title: String, _ expected: String) {
    #expect(FileNaming.sanitise(title) == expected)
}

@Test func sanitiseLimitsLength() {
    let name = FileNaming.sanitise(String(repeating: "☕️", count: 100))
    #expect(name.utf8.count <= 200 && !name.isEmpty)
}

@Test func filenameAddsANumberWhenTaken() {
    #expect(FileNaming.filename(for: "Task", existing: []) == "Task.md")
    #expect(FileNaming.filename(for: "Task", existing: ["Task.md"]) == "Task 2.md")
    #expect(FileNaming.filename(for: "Task", existing: ["task.md", "Task 2.md"]) == "Task 3.md")
    #expect(FileNaming.filename(for: "A: B", existing: ["A - B.md"]) == "A - B 2.md")
    #expect(FileNaming.filename(for: "front", extension: "jpg", existing: ["Front.JPG", "front.md"]) == "front 2.jpg")
}

@Test func splitSeparatesTheExtension() {
    #expect(FileNaming.split("Pasted image 1.png") == ("Pasted image 1", "png"))
    #expect(FileNaming.split("archive.tar.gz") == ("archive.tar", "gz"))
    #expect(FileNaming.split("README") == ("README", ""))
    #expect(FileNaming.split(".hidden") == (".hidden", ""))
}

@Test func pastedImagesAreNamedByTheLocalTime() {
    let date = Date(timeIntervalSince1970: 1_790_727_322) // 2026-09-30 00:15:22 UTC
    #expect(FileNaming.pastedImage(at: date, timeZone: TimeZone(identifier: "Pacific/Auckland")!) == "Pasted image 20260930131522.png")
    #expect(FileNaming.pastedImage(at: date, timeZone: TimeZone(identifier: "UTC")!) == "Pasted image 20260930001522.png")
    #expect(FileNaming.pastedImage(at: date, extension: "jpg", timeZone: TimeZone(identifier: "UTC")!) == "Pasted image 20260930001522.jpg")
}
