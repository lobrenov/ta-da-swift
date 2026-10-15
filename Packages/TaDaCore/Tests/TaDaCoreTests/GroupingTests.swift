import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-16")!

private let tasks = [
    makeItem("tasks/Overdue.md", "type: task\nstatus: Doing\ndueDate: 2026-10-14\ntags: [bug]"),
    makeItem("tasks/Deadline today.md", "type: task\nstatus: Blocked\ndueDate: 2026-10-20\ndeadline: 2026-10-16"),
    makeItem("tasks/Next week.md", "type: task\nstatus: Not Started\ndeadline: 2026-10-23\ntags: [Home/Garden]"),
    makeItem("tasks/Undated.md", "type: task\nstatus: Not Started\ntags: [dev, bug]"),
    makeItem("tasks/Shipped.md", "type: task\nstatus: Done\ndueDate: 2026-10-14\ntags: [home]"),
    makeItem("tasks/Dropped.md", "type: task\nstatus: Cancelled"),
]

private func titles(_ sections: [ListSection]) -> [String] {
    sections.map { "\($0.title): \($0.tasks.map(\.title).joined(separator: ", "))" }
}

@Test func statusSectionsRunDoingBlockedNotStartedDoneCancelled() {
    #expect(titles(ListSection.sections(tasks, by: .status, today: today)) == [
        "Doing: Overdue",
        "Blocked: Deadline today",
        "Not Started: Next week, Undated",
        "Done: Shipped",
        "Cancelled: Dropped",
    ])
}

@Test func dateSectionsMergeDueDateAndDeadline() {
    #expect(titles(ListSection.sections(tasks, by: .date, today: today)) == [
        "Today: Overdue, Deadline today",
        "Upcoming: Next week",
        "Someday: Undated",
        "Completed: Shipped, Dropped",
    ])
}

@Test func openSectionsPutCompletedLast() {
    #expect(titles(ListSection.sections(tasks, by: .open, today: today)) == [
        "Open: Overdue, Deadline today, Next week, Undated",
        "Completed: Shipped, Dropped",
    ])
}

@Test func sectionsLeaveEmptyGroupsOut() {
    #expect(titles(ListSection.sections(Array(tasks[2...3]), by: .date, today: today)) == [
        "Upcoming: Next week",
        "Someday: Undated",
    ])
    #expect(ListSection.sections([], by: .status, today: today).isEmpty)
}

@Test func tagFilterPassesFilesWithAnyPickedTagOrAChildOfOne() {
    #expect(TagFilter().apply(tasks).count == tasks.count, "nothing picked passes every file")
    #expect(TagFilter(picked: ["bug"]).apply(tasks).map(\.title) == ["Overdue", "Undated"])
    #expect(TagFilter(picked: ["dev", "home"]).apply(tasks).map(\.title) == ["Next week", "Undated", "Shipped"])
    #expect(TagFilter(picked: ["home/garden"]).apply(tasks).map(\.title) == ["Next week"])
    #expect(TagFilter(picked: ["hom"]).apply(tasks).isEmpty, "a prefix isn't a parent")
}

@Test func tagFilterListsTheTagsOfTheFilesWithCounts() {
    let tags = TagFilter.tags(of: tasks).map { "\($0.tag.name) \($0.count)" }
    #expect(tags == ["bug 2", "dev 1", "Home 2", "Home/Garden 1"], "a parent counts its children’s files, spelt as first met")
    let picked = TagFilter(picked: ["home"]).apply(tasks).count
    #expect(picked == 2)
}

@Test func tagFilterListsAParentOnlyItsChildrenCarry() {
    let files = [makeItem("tasks/A.md", "type: task\ntags: [people/max, people/sam]")]
    #expect(TagFilter.tags(of: files).map { "\($0.tag.name) \($0.count)" } == ["people 1", "people/max 1", "people/sam 1"])
}

@Test func dateGroupTakesTheNearerOfEitherDate() {
    let item = makeItem("tasks/A.md", "type: task\ndueDate: 2026-10-17\ndeadline: 2026-10-15")
    #expect(ListSection.dateGroup(of: item, today: today) == .today)
    let closed = makeItem("tasks/B.md", "type: task\nstatus: Done\ndueDate: 2026-10-01")
    #expect(titles(ListSection.sections([closed], by: .date, today: today)) == ["Completed: B"])
}

@Test func ongoingFollowsDoing() {
    let items = [makeItem("projects/P.md", "type: project\nstatus: Ongoing"), makeItem("tasks/D.md", "type: task\nstatus: Doing")]
    #expect(ListSection.sections(items, by: .status, today: today).map(\.title) == ["Doing", "Ongoing"])
}
