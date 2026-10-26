import Foundation
import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-02")!
private let path = "Ta Da/tasks/Water.md"

private func done(_ extra: String = "", repeat rule: String = "every week", status: String = "Done", body: String = "") -> String {
    "---\ntype: task\nstatus: \(status)\n\(extra)completedDate: 2026-10-01\nrepeat: \(rule)\n---\n\(body)"
}

@Test func movingForwardChangesOnlyTheTasksLines() {
    let text = "---\ntype: task\nstatus: Done\ndueDate: 2026-09-28\ndeadline: 2026-09-30\ncompletedDate: 2026-10-01\n"
        + "repeat: every week\ntags: [a]\n---\nIntro [x]\n- [x] one\n- [/] two\n- [-] three\n- [>] four\n- [!] icon\n- [X] five\n"
    #expect(Recurrence.moveForward(text, path: path, today: today, projectClosed: false)
        == "---\ntype: task\nstatus: Not Started\ndueDate: 2026-10-05\ndeadline: 2026-10-07\ncompletedDate:\n"
        + "repeat: every week\ntags: [a]\n---\nIntro [x]\n- [ ] one\n- [ ] two\n- [ ] three\n- [>] four\n- [!] icon\n- [ ] five\n")
}

@Test func movingForwardKeepsCRLFAndAddsMissingKeys() {
    let text = "---\r\ntype: task\r\nstatus: Cancelled\r\ncompletedDate: 2026-10-01\r\nrepeat: every day\r\n---\r\n- [x] a\r\n"
    #expect(Recurrence.moveForward(text, path: path, today: today, projectClosed: false)
        == "---\r\ntype: task\r\nstatus: Not Started\r\ncompletedDate:\r\nrepeat: every day\r\ndueDate: 2026-10-02\r\n---\r\n- [ ] a\r\n")
}

@Test func deadlineOnlyTasksMoveTheirDeadline() {
    let text = done("deadline: 2026-09-30\n")
    let moved = Recurrence.moveForward(text, path: path, today: today, projectClosed: false)
    #expect(moved.contains("deadline: 2026-10-07\n") && !moved.contains("dueDate"))
}

@Test func nestedAndFencedCheckboxesFollowTheSubtaskRules() {
    let body = "- [x] top\n    - [x] nested\n> - [x] quoted\n```\n- [x] fenced\n```\n"
    let moved = Recurrence.moveForward(done("dueDate: 2026-09-28\n", body: body), path: path, today: today, projectClosed: false)
    #expect(moved.hasSuffix("- [ ] top\n    - [ ] nested\n> - [ ] quoted\n```\n- [x] fenced\n```\n"))
}

@Test func aTaskThatDoesntMoveForwardIsUnchanged() {
    for text in [done(repeat: "every week until 2026-10-01"), done(repeat: "Weekly · Fri"), done(status: "Doing"),
                 "---\ntype: project\nstatus: Done\nrepeat: every week\n---\n"] {
        #expect(Recurrence.moveForward(text, path: path, today: today, projectClosed: false) == text)
    }
}

@Test func theRunMovesRepeatingTasksForwardAndLogsTheRest() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(done("dueDate: 2026-09-28\n"), "Ta Da/tasks/Rolls.md", in: folder)
        try writeFile(done("dueDate: 2026-09-28\n", status: "Cancelled"), "Ta Da/tasks/Skipped.md", in: folder)
        try writeFile(done(repeat: "every week until 2026-10-01"), "Ta Da/tasks/Ended.md", in: folder)
        try writeFile(done(repeat: "Weekly · Fri"), "Ta Da/tasks/Unreadable.md", in: folder)
        try writeFile("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-01\nrepeat: every week\n---\n", "Ta Da/projects/Series.md", in: folder)
        let index = await vault.loadIndex()
        let paths = index.filesToLog(completedBefore: today).map(\.path)
        #expect(paths.count == 5)
        let moved = try vault.log(paths, index: index, today: today)
        #expect(moved == ["Ta Da/tasks/Ended.md": "Ta Da/logbook/2026-10/Ended.md",
                          "Ta Da/tasks/Unreadable.md": "Ta Da/logbook/2026-10/Unreadable.md",
                          "Ta Da/projects/Series.md": "Ta Da/logbook/2026-10/Series.md"])
        let rolled = try String(contentsOf: folder.appending(path: "Ta Da/tasks/Rolls.md"), encoding: .utf8)
        #expect(rolled.contains("status: Not Started\ndueDate: 2026-10-05\ncompletedDate:\n"))
        #expect(try String(contentsOf: folder.appending(path: "Ta Da/tasks/Skipped.md"), encoding: .utf8).contains("status: Not Started"))
    }
}

@Test func theDailyRunWaitsForTheDayButLogNowRollsEverything() {
    let index = VaultIndex([
        Item(parsing: "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-02\nrepeat: every day\n---\n", path: "Ta Da/tasks/Today.md")!,
        Item(parsing: "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-01\nrepeat: every day\n---\n", path: "Ta Da/tasks/Yesterday.md")!,
    ])
    #expect(index.filesToLog(completedBefore: today).map(\.title) == ["Yesterday"])
    #expect(index.filesToLog(completedBefore: nil).map(\.title) == ["Today", "Yesterday"])
}

@Test func aRepeatingTaskUnderAnOpenProjectRollsAndAClosedProjectLogsWithIt() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("---\ntype: project\nstatus: Doing\n---\n", "Ta Da/projects/Chores.md", in: folder)
        try writeFile(done("project: \"[[Chores]]\"\n"), "Ta Da/tasks/Water.md", in: folder)
        var index = await vault.loadIndex()
        _ = try vault.log(index.filesToLog(completedBefore: nil).map(\.path), index: index, today: today)
        index = await vault.loadIndex()
        #expect(index["Ta Da/tasks/Water.md"]?.properties.status == .notStarted)

        try writeFile("---\ntype: project\nstatus: Done\ncompletedDate: 2026-09-30\n---\n", "Ta Da/projects/Chores.md", in: folder)
        try writeFile(done("project: \"[[Chores]]\"\n", status: "Done"), "Ta Da/tasks/Water.md", in: folder)
        index = await vault.loadIndex()
        let paths = index.filesToLog(completedBefore: nil).map(\.path)
        #expect(paths.count == 2)
        let moved = try vault.log(paths, index: index, today: today)
        #expect(moved.count == 2 && moved.values.allSatisfy { $0.hasPrefix("Ta Da/logbook/2026-") })
    }
}

@Test func aFileChangedSinceTheIndexIsRereadWhenLogging() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(done(), "Ta Da/tasks/Doing.md", in: folder)
        try writeFile(done(), "Ta Da/tasks/Unrepeated.md", in: folder)
        try writeFile(done(), "Ta Da/tasks/Ended.md", in: folder)
        let index = await vault.loadIndex()
        let doing = done(status: "Doing")
        try writeFile(doing, "Ta Da/tasks/Doing.md", in: folder)
        try writeFile("---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-01\n---\n", "Ta Da/tasks/Unrepeated.md", in: folder)
        try writeFile(done(repeat: "every week until 2026-10-01"), "Ta Da/tasks/Ended.md", in: folder)
        let moved = try vault.log(index.filesToLog(completedBefore: nil).map(\.path), index: index, today: today)
        #expect(moved == ["Ta Da/tasks/Unrepeated.md": "Ta Da/logbook/2026-10/Unrepeated.md",
                          "Ta Da/tasks/Ended.md": "Ta Da/logbook/2026-10/Ended.md"])
        #expect(try String(contentsOf: folder.appending(path: "Ta Da/tasks/Doing.md"), encoding: .utf8) == doing)
    }
}

@Test func aRollThatFailsWithNothingElseMovedThrows() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(done(), "Ta Da/tasks/Rolls.md", in: folder)
        let index = await vault.loadIndex()
        let tasks = folder.appending(path: "Ta Da/tasks").path
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tasks)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tasks) }
        #expect(throws: (any Error).self) { try vault.log(["Ta Da/tasks/Rolls.md"], index: index, today: today) }
    }
}
