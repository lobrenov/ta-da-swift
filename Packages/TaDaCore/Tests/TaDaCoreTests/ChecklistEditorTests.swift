import Testing
@testable import TaDaCore

private let text = "---\ntype: task\n---\nÜber 🙂\n\n- [ ] Open\n  - [x] Done\n> - [-] Cancelled\n1. [?] Icon\n"

private func boxes(_ text: String) -> [Checkbox] { Item(parsing: text, title: "t")!.checkboxes }

@Test func clickCompletesAndReopens() throws {
    let b = boxes(text)
    let completed = try #require(ChecklistEditor.click(b[0], in: text))
    #expect(changedLines(text, completed) == (["- [ ] Open"], ["- [x] Open"]))
    let reopened = try #require(ChecklistEditor.click(b[1], in: text))
    #expect(changedLines(text, reopened) == (["  - [x] Done"], ["  - [ ] Done"]))
    let uncancelled = try #require(ChecklistEditor.click(b[2], in: text))
    #expect(changedLines(text, uncancelled) == (["> - [-] Cancelled"], ["> - [ ] Cancelled"]))
    #expect(ChecklistEditor.click(b[3], in: text) == nil)
}

@Test func setMarkerChangesOneByte() throws {
    let b = boxes(text)
    let after = try #require(ChecklistEditor.setMarker("/", of: b[3], in: text))
    #expect(changedLines(text, after) == (["1. [?] Icon"], ["1. [/] Icon"]))
    #expect(after.utf8.count == text.utf8.count)
    #expect(ChecklistEditor.setMarker("y", of: b[0], in: text) == nil)
    #expect(ChecklistEditor.setMarker("✓", of: b[0], in: text) == nil)
}

@Test func staleBoxesAreRefused() {
    let box = boxes(text)[0]
    #expect(ChecklistEditor.click(box, in: text.replacingOccurrences(of: "- [ ] Open", with: "- [x] Open")) == nil)
    #expect(ChecklistEditor.click(box, in: "---\ntype: task\n---\n") == nil)
    #expect(ChecklistEditor.click(Checkbox(marker: " ", lineIndex: 5, column: 0), in: text) == nil)
}

@Test func clickKeepsCRLF() throws {
    let crlf = "---\r\ntype: task\r\n---\r\n- [ ] A\r\n- [ ] B\r\n"
    let after = try #require(ChecklistEditor.click(boxes(crlf)[1], in: crlf))
    #expect(after == "---\r\ntype: task\r\n---\r\n- [ ] A\r\n- [x] B\r\n")
}
