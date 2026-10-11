import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-02")!

@Test func newTaskParsesBack() throws {
    let text = NewFile.task(project: "Ta Da MVP", today: today)
    #expect(text == "---\ntype: task\nstatus: Not Started\nproject: \"[[Ta Da MVP]]\"\ncreatedDate: 2026-10-02\n---\n")
    let item = try #require(Item(parsing: text, path: "New task.md"))
    #expect(item.properties.kind == .task && item.properties.status == .notStarted)
    #expect(item.properties.project?.title == "Ta Da MVP")
    #expect(item.properties.createdDate == today)
    #expect(item.warnings.isEmpty)
}

@Test func newLooseTaskAndProjectParseBack() throws {
    let loose = try #require(Item(parsing: NewFile.task(today: today), path: "t.md"))
    #expect(loose.properties.project == nil && loose.warnings.isEmpty)
    let project = try #require(Item(parsing: NewFile.project(today: today), path: "p.md"))
    #expect(project.properties.kind == .project && project.properties.createdDate == today && project.warnings.isEmpty)
}

@Test func newFilesNameOneParent() throws {
    let areaTask = NewFile.task(area: "Personal", today: today)
    #expect(areaTask == "---\ntype: task\nstatus: Not Started\narea: \"[[Personal]]\"\ncreatedDate: 2026-10-02\n---\n")
    let both = try #require(Item(parsing: NewFile.task(project: "Ta Da MVP", area: "Personal", today: today), path: "t.md"))
    #expect(both.properties.project?.title == "Ta Da MVP" && both.properties.area == nil && both.warnings.isEmpty)
    let project = try #require(Item(parsing: NewFile.project(area: "Work", today: today), path: "p.md"))
    #expect(project.properties.area?.title == "Work" && project.warnings.isEmpty)
}

@Test func newAreaParsesBack() throws {
    let text = NewFile.area(today: today)
    #expect(text == "---\ntype: area\ncreatedDate: 2026-10-02\n---\n")
    let area = try #require(Item(parsing: text, path: "areas/Personal.md"))
    #expect(area.properties.kind == .area && area.properties.createdDate == today && area.warnings.isEmpty)
}

@Test func newTaskWithTagsParsesBack() throws {
    let text = NewFile.task(area: "Personal", tags: [Tag("errands")!, Tag("Quick Win")!, Tag("quick win")!, Tag("a, b")!], today: today)
    #expect(text == "---\ntype: task\nstatus: Not Started\narea: \"[[Personal]]\"\ncreatedDate: 2026-10-02\ntags: [errands, Quick Win, \"a, b\"]\n---\n")
    let item = try #require(Item(parsing: text, path: "t.md"))
    #expect(item.properties.tags.map(\.name) == ["errands", "Quick Win", "a, b"] && item.warnings.isEmpty)
    #expect(NewFile.task(tags: [], today: today) == NewFile.task(today: today))
}
