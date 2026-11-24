import Testing
@testable import TaDaCore

private let open = "---\ntype: task\nstatus: Not Started\n---\nBody\n"
private let done = "---\ntype: task\nstatus: Done\ncompletedDate: 2026-11-24\n---\nBody\n"

@Test func undoingAChangeGivesBackTheOriginalText() {
    let change = TextChange(from: open, to: done)
    #expect(change.undone(in: done) == open)
    #expect(change.inverse.undone(in: open) == done)
}

@Test func undoingKeepsTextTypedAfterTheChange() {
    let change = TextChange(from: open, to: done)
    #expect(change.undone(in: done + "More\n") == open + "More\n")
}

@Test func undoingRefusesTextChangedWithinTheChange() {
    let change = TextChange(from: open, to: done)
    #expect(change.undone(in: done.replacingOccurrences(of: "Done", with: "Doing")) == nil)
    #expect(change.undone(in: "") == nil)
}

@Test func noChangeUndoesToTheSameText() {
    #expect(TextChange(from: open, to: open).undone(in: open) == open)
}
