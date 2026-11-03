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
    #expect(index.loose().map(\.title) == ["Overdue deadline", "Deadline today", "Same day", "Undated"])
}

@Test func filedTasksSortByEarliestDateThenTitle() {
    #expect(index.tasks(in: items[0]).map(\.title) == ["Overdue due", "Done earlier", "Done today"])
    #expect(index.tasks(in: items[1]).map(\.title) == ["Due today", "Tomorrow"])
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

@Test func progressOverGivenTasksLeavesCancelledOutOfTheTotal() {
    let tasks = [makeItem("tasks/A.md", "type: task\nstatus: Done"), makeItem("tasks/B.md", "type: task\nstatus: Cancelled"),
                 makeItem("tasks/C.md", "type: task\nstatus: Doing")]
    let progress = ProjectProgress(project: items[0], tasks: tasks)
    #expect((progress.done, progress.total) == (1, 2))
    #expect(progress.fraction == 0.5)
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
    #expect(search.search("jams dan").map(\.title) == ["Update Dan’s website"])
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
        "Submit timesheet", "Update my claude.md files", "Update 2DS before the next session",
    ])
    // The design has no area files, so its areas don't resolve, and its `Weekly · Fri` isn't a rule.
    for item in index.items.values {
        #expect(index.warnings(for: item).allSatisfy { warning in
            switch warning { case .areaIgnored, .unresolvedArea, .invalidRepeat("Weekly · Fri"): true; default: false }
        }, "\(item.path)")
    }
}

@Test func cancelledTasksAreClosedAndLeftOutOfProgress() {
    let index = VaultIndex([
        makeItem("projects/Gamma.md", "type: project\nstatus: Doing"),
        makeItem("projects/Dropped.md", "type: project\nstatus: Cancelled"),
        makeItem("tasks/Cancelled today.md", "type: task\nstatus: Cancelled\ncompletedDate: 2026-10-02\ndueDate: 2026-10-01\nproject: \"[[Gamma]]\""),
        makeItem("tasks/Cancelled loose.md", "type: task\nstatus: Cancelled\ncompletedDate: 2026-10-01\ndeadline: 2026-10-05"),
        makeItem("tasks/Done.md", "type: task\nstatus: Done\ncompletedDate: 2026-10-01\nproject: \"[[Gamma]]\""),
        makeItem("tasks/Open.md", "type: task\nstatus: Doing\nproject: \"[[Gamma]]\""),
    ])
    #expect(index.today(today).map(\.title) == ["Cancelled today"])
    #expect(index.upcoming(after: today).isEmpty)
    #expect(index.loose().isEmpty)
    #expect(index.tasks.filter { index.isOverdue($0, today: today) }.isEmpty)
    #expect(index.activeProjects().map { "\($0.project.title) \($0.done)/\($0.total)" } == ["Gamma 1/2"])
}

// MARK: Tags, on TagVault

private func tagIndex() async -> VaultIndex { await Vault(root: tagVault).loadIndex() }

private func describe(_ nodes: [TagNode], depth: Int = 0) -> [String] {
    nodes.flatMap { [String(repeating: "  ", count: depth) + "\($0.tag.name) \($0.count)"] + describe($0.children, depth: depth + 1) }
}

@Test func tagTreeRollsUpCountsAndLeavesOutTrashedFiles() async {
    #expect(describe(await tagIndex().tagTree()) == [
        "errands 4",
        "Home 4",
        "  home/garden 3",
        "logged-only 1",
        "people 2",
        "  people/dan 1",
        "  People/Max 1",
        "quick win 2",
        "Work 2",
        "  Work/Clients 2",
    ])
}

@Test func itemsTaggedIncludeChildren() async throws {
    let index = await tagIndex()
    #expect(index.items(tagged: try #require(Tag("home"))).map(\.title) == ["Buy mulch", "Garden", "Home", "Prune the lemon tree"])
    #expect(index.items(tagged: try #require(Tag("HOME/GARDEN"))).map(\.title) == ["Buy mulch", "Garden", "Prune the lemon tree"])
    #expect(index.items(tagged: try #require(Tag("logged-only"))).map(\.title) == ["Old errand"])
    #expect(index.items(tagged: try #require(Tag("errands"))).map(\.title).contains("Old errand"))
    #expect(index.items(tagged: try #require(Tag("trashed-only"))).isEmpty)
}

@Test func untaggedIsEveryLiveFileWithoutATag() async {
    #expect(await tagIndex().untagged().map(\.title) == ["Untagged task", "Work"])
}

@Test func tagBrowserListsParentsThenOpenTasksWithLooseLastThenCompleted() async throws {
    let index = await tagIndex()
    func groups(_ browser: TagBrowser) -> [String] {
        browser.groups.map { "\($0.parent?.title ?? "Loose"): \($0.tasks.map(\.title).joined(separator: ", "))" }
    }

    let errands = index.tagBrowser(try #require(Tag("errands")))
    #expect(errands.areasAndProjects.isEmpty && errands.completed.map(\.title) == ["Old errand"] && errands.children.isEmpty)
    #expect(groups(errands) == ["Home: ", "Garden: Buy mulch, Prune the lemon tree", "Loose: Message Max"])

    let home = index.tagBrowser(try #require(Tag("Home")))
    #expect(home.areasAndProjects.map(\.title) == ["Home", "Garden"])
    #expect(home.children.map(\.tag.name) == ["home/garden"])

    let people = index.tagBrowser(try #require(Tag("people")))
    #expect(groups(people) == ["Loose: Message Max"])
    #expect(people.completed.map(\.title) == ["Call Dan"])
    #expect(people.children.map { "\($0.tag.name) \($0.count)" } == ["people/dan 1", "People/Max 1"])

    let untagged = index.tagBrowser(nil)
    #expect(untagged.areasAndProjects.map(\.title) == ["Work"] && groups(untagged) == ["Loose: Untagged task"])
    #expect(untagged.children.isEmpty)
}

@Test func tagSuggestionsMatchSegmentStartsFirstSegmentFirstThenByUse() async {
    let index = await tagIndex()
    func names(_ query: String, limit: Int = 50) -> [String] { index.tagSuggestions(query, limit: limit).map(\.tag.name) }
    #expect(names("pe") == ["people", "people/dan", "People/Max"])
    #expect(names("gar") == ["home/garden"])
    #expect(names("C") == ["Work/Clients"])
    #expect(names("w") == ["Work", "Work/Clients"])
    #expect(names("logged") == ["logged-only"])
    #expect(names("win").isEmpty, "a space doesn't start a segment")
    #expect(names("home/g") == ["home/garden"])
    #expect(names("") == ["errands", "Home", "home/garden", "people", "quick win", "Work", "Work/Clients", "logged-only", "people/dan", "People/Max"])
    #expect(names("", limit: 2) == ["errands", "Home"])
}

@Test func loggedFilesCountAsTagCarriersAndFollowEdits() throws {
    let logged = makeItem("Ta Da/logbook/2026-09/Done chore.md", "type: task\nstatus: Done\ntags: [chore, shared]")
    let loggedProject = makeItem("Ta Da/logbook/2026-09/Old plan.md", "type: project\nstatus: Done\ntags: [chore]")
    let live = makeItem("tasks/Live.md", "type: task\nstatus: Not Started\ntags: [shared]")
    var index = VaultIndex([logged, loggedProject, live])
    #expect(describe(index.tagTree()) == ["chore 2", "shared 2"])
    #expect(index.tagSuggestions("ch").map(\.tag.name) == ["chore"])
    let chore = index.tagBrowser(try #require(Tag("chore")))
    #expect(chore.completed.map(\.title) == ["Done chore"] && chore.areasAndProjects.map(\.title) == ["Old plan"])
    #expect(index.untagged().isEmpty)
    #expect(index.items(tagged: try #require(Tag("shared"))).map(\.title) == ["Done chore", "Live"])

    index.update(makeItem(logged.path, "type: task\nstatus: Done\ntags: [other]"))
    #expect(describe(index.tagTree()) == ["chore 1", "other 1", "shared 1"])
    index.remove(logged.path)
    #expect(describe(index.tagTree()) == ["chore 1", "shared 1"])
}

@Test func agendaDayIsTodaysListForTodayAndDatedTasksOtherwise() {
    #expect(index.agendaDay(today, today: today).map(\.title) == index.today(today).map(\.title))
    #expect(index.agendaDay(LocalDate("2026-10-05")!, today: today).map(\.title) == ["Done today", "Same day"])
    #expect(index.agendaDay(LocalDate("2026-10-01")!, today: today).map(\.title) == ["Done earlier", "Overdue deadline"])
    #expect(index.agendaDay(LocalDate("2026-10-04")!, today: today).isEmpty)
    let cancelled = VaultIndex([makeItem("tasks/Dropped.md", "type: task\nstatus: Cancelled\ndueDate: 2026-10-03\ncompletedDate: 2026-10-01")])
    #expect(cancelled.agendaDay(LocalDate("2026-10-03")!, today: today).isEmpty)
}

@Test func agendaWeekHasEntriesDatedWithinTheWeek() {
    let entries = index.agendaWeek(ISOWeek(year: 2026, week: 41)!).map { "\($0.date) \($0.kind) \($0.item.title)" }
    #expect(entries == [
        "2026-10-05 due Done today",
        "2026-10-05 due Same day",
        "2026-10-05 deadline Same day",
        "2026-10-08 deadline Tomorrow",
        "2026-10-09 due Overdue deadline",
    ])
    #expect(index.agendaWeek(ISOWeek(year: 2026, week: 42)!).isEmpty)
}

@Test func agendaOnTheDesignVault() async {
    let design = await Vault(root: sampleVault).loadIndex()
    #expect(design.agendaDay(today, today: today).map(\.path) == design.today(today).map(\.path))
    let tomorrow = today.adding(days: 1)
    #expect(design.agendaDay(tomorrow, today: today).allSatisfy { $0.properties.dueDate == tomorrow || $0.properties.deadline == tomorrow })
    let entries = design.agendaWeek(today.isoWeek)
    #expect(!entries.isEmpty && entries.allSatisfy { today.isoWeek.days.contains($0.date) })
    #expect(entries.map(\.date) == entries.map(\.date).sorted())
}
