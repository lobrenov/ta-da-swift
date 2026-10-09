import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-02")!

private let items = [
    makeItem("projects/Alpha.md", "type: project\nstatus: Doing\ndeadline: 2026-10-02"),
    makeItem("projects/Beta.md", "type: project\nstatus: Doing"),
    makeItem("projects/Shipped.md", "type: project\nstatus: Done"),
    makeItem("tasks/Overdue due.md", "type: task\nstatus: Doing\ndueDate: 2026-09-30\nproject: \"[[Alpha]]\""),
    makeItem("tasks/Overdue deadline.md", "type: task\nstatus: Blocked\ndueDate: 2026-10-09\ndeadline: 2026-10-01"),
    makeItem("tasks/Due today.md", "type: task\nstatus: Not Started\ndueDate: 2026-10-02\nproject: \"[[Beta]]\""),
    makeItem("tasks/Deadline today.md", "type: task\nstatus: Not Started\ndeadline: 2026-10-02"),
    makeItem("tasks/Done today.md", "type: task\nstatus: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-05\nproject: \"[[Alpha]]\""),
    makeItem("tasks/Done earlier.md", "type: task\nstatus: Done\ncompletedDate: 2026-10-01\ndueDate: 2026-10-01\nproject: \"[[Alpha]]\""),
    makeItem("tasks/Same day.md", "type: task\nstatus: Doing\ndueDate: 2026-10-05\ndeadline: 2026-10-05"),
    makeItem("tasks/Tomorrow.md", "type: task\nstatus: Not Started\ndueDate: 2026-10-03\ndeadline: 2026-10-08\nproject: \"[[Beta]]\""),
    makeItem("tasks/Undated.md", "type: task\nstatus: Not Started\nproject: \"[[Unknown]]\""),
    makeItem("tasks/Shipped task.md", "type: task\nstatus: Doing\nproject: \"[[Shipped]]\""),
]
private let index = VaultIndex(items)

@Test func todayHasOpenTasksDueOrAtDeadlineAndTasksDoneToday() {
    #expect(index.today(today).map(\.title) == ["Overdue due", "Overdue deadline", "Deadline today", "Due today", "Done today"])
}

@Test func overdueIsOpenAndPastEitherDate() {
    let overdue = items.filter { index.isOverdue($0, today: today) }.map(\.title)
    #expect(overdue == ["Overdue due", "Overdue deadline"])
}

@Test func upcomingStartsTomorrowWithOneEntryPerDate() {
    let entries = index.upcoming(after: today).map { "\($0.date) \($0.kind) \($0.item.title)" }
    #expect(entries == [
        "2026-10-03 due Tomorrow",
        "2026-10-05 due Same day",
        "2026-10-05 deadline Same day",
        "2026-10-08 deadline Tomorrow",
        "2026-10-09 due Overdue deadline",
    ])
}

@Test func looseTasksHaveNoResolvableProject() {
    #expect(index.loose().map(\.title) == ["Deadline today", "Overdue deadline", "Same day", "Undated"])
}

@Test func activeProjectsCountAllTheirTasks() {
    let projects = index.activeProjects().map { "\($0.project.title) \($0.done)/\($0.total) open \($0.open)" }
    #expect(projects == ["Alpha 2/3 open 1", "Beta 0/2 open 2"])
    #expect(index.activeProjects()[0].fraction == 2.0 / 3)
    #expect(VaultIndex([items[1]]).activeProjects()[0].fraction == 0)
}

@Test func progressCountsTheTasksOfAnyProject() {
    #expect(index.progress(of: items[0]) == index.activeProjects()[0])
    let shipped = index.progress(of: items[2])
    #expect((shipped.done, shipped.total) == (0, 1), "a done project isn't active but has progress")
}

@Test func perItemTestsAgreeWithTheLists() {
    for item in items {
        #expect(index.isInToday(item, today: today) == index.today(today).contains(item), "\(item.title)")
        #expect(index.upcomingEntries(of: item, after: today) == index.upcoming(after: today).filter { $0.item == item }, "\(item.title)")
        #expect(index.isLoose(item) == index.loose().contains(item), "\(item.title)")
    }
    let deadlineFirst = makeItem("tasks/Late.md", "type: task\nstatus: Doing\ndueDate: 2026-10-20\ndeadline: 2026-10-15")
    #expect(index.upcomingEntries(of: deadlineFirst, after: today).map(\.kind) == [.deadline, .due])
}

@Test func groupingPutsLooseFirstThenProjectsByTitle() {
    let groups = index.grouped(index.today(today))
    #expect(groups.map { $0.parent?.title ?? "Loose" } == ["Loose", "Alpha", "Beta"])
    #expect(groups.map { $0.tasks.map(\.title) } == [["Overdue deadline", "Deadline today"], ["Overdue due", "Done today"], ["Due today"]])
    #expect(index.grouped([]).isEmpty)
}

@Test func searchMatchesWordsIgnoringCaseAndDiacritics() {
    let search = VaultIndex([
        makeItem("tasks/Update Dan’s website.md", "type: task\nstatus: Doing\narea: Game Jams"),
        makeItem("tasks/Café run.md", "type: task\nstatus: Doing\narea: \"[[Errands]]\""),
        makeItem("tasks/Other.md", "type: task\nstatus: Doing", body: "Mentions the website."),
    ])
    #expect(search.search("WEBSITE").map(\.title) == ["Update Dan’s website", "Other"])
    #expect(search.search("cafe err").map(\.title) == ["Café run"])
    #expect(search.search("gamejams dan").map(\.title) == ["Update Dan’s website"])
    #expect(search.search("  ").isEmpty)
}

/// The design's counts, from SampleVault on Friday 2 October 2026.
@Test func sampleVaultMatchesTheDesign() async throws {
    let index = await Vault(root: sampleVault).loadIndex()
    #expect(index.today(today).count == 7)
    let projects = Dictionary(uniqueKeysWithValues: index.activeProjects().map { ($0.project.title, $0) })
    #expect(projects["Ta Da MVP"].map { ($0.open, $0.done, $0.total) } ?? (0, 0, 0) == (6, 2, 8))
    #expect(index.upcoming(after: today).first?.item.title == "Update 2DS before the next session")
    #expect(index.loose().map(\.title) == [
        "Message Max about a coat and a jacket", "Resolve the cabin payback", "Shift my physio appointment",
        "Submit timesheet", "Update 2DS before the next session", "Update my claude.md files",
    ])
    // The design has no area files, so its areas don't resolve.
    for item in index.items.values {
        #expect(index.warnings(for: item).allSatisfy { warning in
            switch warning { case .areaIgnored, .unresolvedArea: true; default: false }
        }, "\(item.path)")
    }
}
