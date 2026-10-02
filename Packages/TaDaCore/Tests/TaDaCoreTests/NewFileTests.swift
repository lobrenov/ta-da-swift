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
