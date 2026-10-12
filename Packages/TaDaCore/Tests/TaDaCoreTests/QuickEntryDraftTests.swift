import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-12")!

private func full(_ kind: Item.Kind, parent: Parent?) -> QuickEntryDraft {
    var draft = QuickEntryDraft()
    draft.kind = kind
    draft.title = "Call Bea"
    draft.status = .doing
    draft.parent = parent
    draft.dueDate = LocalDate("2026-10-14")
    draft.deadline = LocalDate("2026-10-20")
    draft.tags = [Tag("people/bea")!]
    return draft
}

@Test func freshDraftIsALooseNotStartedTask() {
    let draft = QuickEntryDraft()
    #expect(draft.kind == .task && draft.title.isEmpty && draft.status == .notStarted && draft.parent == nil)
    #expect(draft.folder == "tasks")
    #expect(draft.text(today: today) == NewFile.task(today: today))
}

@Test func taskDraftWritesEveryField() throws {
    let text = full(.task, parent: .project("Game Jam")).text(today: today)
    #expect(text == "---\ntype: task\nstatus: Doing\nproject: \"[[Game Jam]]\"\ncreatedDate: 2026-10-12\ntags: [people/bea]\ndueDate: 2026-10-14\ndeadline: 2026-10-20\n---\n")
    let item = try #require(Item(parsing: text, path: "tasks/Call Bea.md"))
    #expect(item.properties.kind == .task && item.properties.status == .doing && item.warnings.isEmpty)
    #expect(item.properties.project?.title == "Game Jam" && item.properties.area == nil)
    #expect(item.properties.dueDate == LocalDate("2026-10-14") && item.properties.deadline == LocalDate("2026-10-20"))
    #expect(item.properties.tags.map(\.name) == ["people/bea"])
}

@Test func taskDraftCanNameAnArea() throws {
    let item = try #require(Item(parsing: full(.task, parent: .area("Personal")).text(today: today), path: "t.md"))
    #expect(item.properties.area?.title == "Personal" && item.properties.project == nil)
}

@Test func projectDraftWritesEveryField() throws {
    let draft = full(.project, parent: .area("Personal"))
    #expect(draft.folder == "projects")
    let item = try #require(Item(parsing: draft.text(today: today), path: "projects/Call Bea.md"))
    #expect(item.properties.kind == .project && item.properties.status == .doing && item.warnings.isEmpty)
    #expect(item.properties.area?.title == "Personal")
    #expect(item.properties.dueDate == LocalDate("2026-10-14") && item.properties.deadline == LocalDate("2026-10-20"))
    #expect(item.properties.tags.map(\.name) == ["people/bea"])
}

@Test func areaDraftWritesOnlyTags() {
    let draft = full(.area, parent: .area("Personal"))
    #expect(draft.folder == "areas")
    #expect(draft.text(today: today) == "---\ntype: area\ncreatedDate: 2026-10-12\ntags: [people/bea]\n---\n")
}

@Test func closedStatusSetsCompletedDate() throws {
    var draft = QuickEntryDraft()
    draft.status = .done
    let item = try #require(Item(parsing: draft.text(today: today), path: "t.md"))
    #expect(item.properties.status == .done && item.properties.completedDate == today)
}

@Test func changingKindKeepsWhatTheKindHas() {
    let task = full(.task, parent: .project("Game Jam"))
    let project = task.changingKind(to: .project)
    #expect(project.kind == .project && project.title == task.title && project.tags == task.tags)
    #expect(project.status == .doing && project.dueDate == task.dueDate && project.deadline == task.deadline)
    #expect(project.parent == nil)
    #expect(full(.task, parent: .area("Personal")).changingKind(to: .project).parent == .area("Personal"))

    let area = task.changingKind(to: .area)
    var expected = QuickEntryDraft()
    expected.kind = .area
    expected.title = task.title
    expected.tags = task.tags
    #expect(area == expected)

    let back = area.changingKind(to: .task)
    #expect(back.status == .notStarted && back.parent == nil && back.dueDate == nil && back.tags == task.tags)
}
