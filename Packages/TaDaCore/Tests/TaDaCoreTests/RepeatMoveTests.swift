import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-02")!

private func move(_ frontmatter: String, completing: Bool = false, project: String? = nil) -> RepeatMove? {
    let task = makeItem("tasks/T.md", "type: task\n" + frontmatter + (project == nil ? "" : "\nproject: \"[[P]]\""))
    let parent = project.map { makeItem("projects/P.md", "type: project\nstatus: \($0)") }
    return VaultIndex([task] + [parent].compactMap { $0 }).repeatMove(of: task, today: today, completing: completing)
}

@Test func aCompletedTaskMovesToTheDayAfterTodayWhenCompletedToday() {
    #expect(move("status: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nrepeat: every day") == .moves(to: LocalDate("2026-10-03")!))
    #expect(move("status: Cancelled\ncompletedDate: 2026-10-01\ndueDate: 2026-10-01\nrepeat: every day") == .moves(to: LocalDate("2026-10-02")!))
}

@Test func aTaskThatCantMoveHasNoMove() {
    #expect(move("status: Doing\ndueDate: 2026-10-02\nrepeat: every day") == nil)
    #expect(move("status: Done\ncompletedDate: 2026-10-02\nrepeat: Weekly · Fri") == nil)
    #expect(move("status: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02") == nil)
}

@Test func completingAnOpenTaskSaysWhereItWouldMove() {
    #expect(move("status: Doing\ndueDate: 2026-10-05\nrepeat: every week", completing: true) == .moves(to: LocalDate("2026-10-12")!))
}

@Test func aSeriesEndsAtUntilOrWithItsClosedProject() {
    #expect(move("status: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nrepeat: every day until 2026-10-02") == .ends)
    #expect(move("status: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nrepeat: every day", project: "Done") == .ends)
    #expect(move("status: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nrepeat: every day", project: "Doing")
            == .moves(to: LocalDate("2026-10-03")!))
}

@Test func completingAlwaysCountsAsCompletedToday() {
    #expect(move("status: Done\ncompletedDate: 2026-09-20\ndueDate: 2026-09-20\nrepeat: every day", completing: true)
            == .moves(to: LocalDate("2026-10-03")!))
}
