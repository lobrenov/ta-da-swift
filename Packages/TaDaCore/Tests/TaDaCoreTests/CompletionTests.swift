import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-02")!

@Test func completingFillsAnEmptyCompletedDate() {
    let text = "---\ntype: task\nstatus: Doing\ncompletedDate:\ndueDate: 2026-10-02\n---\nBody\n"
    let after = Completion.setStatus(.done, in: text, today: today)
    #expect(changedLines(text, after) == (["status: Doing", "completedDate:"], ["status: Done", "completedDate: 2026-10-02"]))
}

@Test func completingAppendsAMissingCompletedDate() {
    let text = "---\ntype: task\nstatus: Not Started\n---\n"
    #expect(Completion.toggle(.notStarted, in: text, today: today) == "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-02\n---\n")
}

@Test func reopeningClearsCompletedDate() {
    let text = "---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-27\n---\n"
    #expect(Completion.toggle(.done, in: text, today: today) == "---\ntype: task\nstatus: Not Started\ncompletedDate:\n---\n")
    #expect(Completion.setStatus(.blocked, in: text, today: today) == "---\ntype: task\nstatus: Blocked\ncompletedDate:\n---\n")
}

@Test func cancellingSetsCompletedDate() {
    let text = "---\ntype: task\nstatus: Doing\n---\n"
    #expect(Completion.setStatus(.cancelled, in: text, today: today) == "---\ntype: task\nstatus: Cancelled\ncompletedDate: 2026-10-02\n---\n")
}

@Test func togglingACancelledFileReopensIt() {
    let text = "---\ntype: task\nstatus: Cancelled\ncompletedDate: 2026-09-27\n---\n"
    #expect(Completion.toggle(.cancelled, in: text, today: today) == "---\ntype: task\nstatus: Not Started\ncompletedDate:\n---\n")
}

@Test func nonDoneStatusWithoutCompletedDateTouchesOnlyStatus() {
    let text = "---\ntype: task\nstatus: Doing\n---\n"
    #expect(Completion.setStatus(.blocked, in: text, today: today) == "---\ntype: task\nstatus: Blocked\n---\n")
}

@Test func completionKeepsCRLF() {
    let text = "---\r\ntype: task\r\nstatus: Doing\r\n---\r\n"
    #expect(Completion.setStatus(.done, in: text, today: today) == "---\r\ntype: task\r\nstatus: Done\r\ncompletedDate: 2026-10-02\r\n---\r\n")
}

/// Completing or reopening any SampleVault file changes only its status and completedDate lines.
@Test func sampleVaultCompletionTouchesOnlyStatusLines() throws {
    for url in try sampleFiles() {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard let item = Item(parsing: text, path: url.lastPathComponent) else { continue }
        let after = Completion.toggle(item.properties.status, in: text, today: today)
        let changes = changedLines(text, after)
        for line in changes.removed + changes.added {
            #expect(line.hasPrefix("status:") || line.hasPrefix("completedDate:"), "\(url.lastPathComponent): \(line)")
        }
        let reread = try #require(Item(parsing: after, path: "x.md"))
        #expect(reread.properties.status == (item.properties.status == .done ? .notStarted : .done))
        #expect(reread.properties.completedDate == (item.properties.status == .done ? nil : today))
        #expect(reread.warnings == item.warnings)
    }
}
