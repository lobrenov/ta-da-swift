import Testing
@testable import TaDaCore

@Test func readerReadsEveryProperty() throws {
    let yaml = """
    type: task
    status: Doing
    area: Personal
    contexts:
      - "@computer"
      - "@home"
    project: "[[Ta Da MVP]]"
    createdDate: 2026-09-28
    completedDate: 2026-10-01
    dueDate: 2026-10-02
    deadline: "2026-10-06"
    repeat: Weekly · Fri
    custom: kept but not read

    """
    let read = try #require(PropertyReader.read(yaml))
    let p = read.properties
    #expect(p.kind == .task)
    #expect(p.status == .doing)
    #expect(p.area == "Personal")
    #expect(p.contexts == ["@computer", "@home"])
    #expect(p.project?.target == "Ta Da MVP")
    #expect(p.createdDate == LocalDate("2026-09-28"))
    #expect(p.completedDate == LocalDate("2026-10-01"))
    #expect(p.dueDate == LocalDate("2026-10-02"))
    #expect(p.deadline == LocalDate("2026-10-06"))
    #expect(p.repeatRule == "Weekly · Fri")
    #expect(read.warnings.isEmpty)
}

@Test func readerAcceptsFlowAndBlockContexts() throws {
    #expect(try #require(PropertyReader.read("type: task\nstatus: Done\ncontexts: [\"@a\", '@b', c]\n")).properties.contexts == ["@a", "@b", "c"])
    #expect(try #require(PropertyReader.read("type: task\nstatus: Done\ncontexts:\n- \"@a\"\n- c\n")).properties.contexts == ["@a", "c"])
    #expect(try #require(PropertyReader.read("type: task\nstatus: Done\ncontexts: \"@solo\"\n")).properties.contexts == ["@solo"])
    #expect(try #require(PropertyReader.read("type: task\nstatus: Done\ncontexts: []\n")).properties.contexts == [])
    #expect(try #require(PropertyReader.read("type: task\nstatus: Done\ncontexts:\n")).properties.contexts == [])
}

@Test func readerTreatsEmptyAndNullAsMissing() throws {
    let read = try #require(PropertyReader.read("type: project\nstatus: Doing\narea:\ndueDate: ~\ndeadline: null\nrepeat: \"\"\ncompletedDate:\n"))
    let p = read.properties
    #expect(p.area == nil && p.dueDate == nil && p.deadline == nil && p.repeatRule == nil && p.completedDate == nil)
    #expect(read.warnings.isEmpty)
}

@Test func readerKeepsValuesAsWritten() throws {
    let read = try #require(PropertyReader.read("type: task\nstatus: Doing\narea: yes\nrepeat: 2026\ncontexts: [on, \"null\"]\n"))
    #expect(read.properties.area == "yes")
    #expect(read.properties.repeatRule == "2026")
    #expect(read.properties.contexts == ["on", "null"])
}

@Test func readerMatchesTypeCaseInsensitively() {
    #expect(PropertyReader.read("type: Project\nstatus: Doing\n")?.properties.kind == .project)
}

@Test(arguments: ["", "# only a comment\n", "status: Doing\n", "type: note\n", "type:\n", "- type: task\n", "just text\n", "type: [task]\n"])
func readerIgnoresNonTaDaFrontmatter(_ yaml: String) {
    #expect(PropertyReader.read(yaml) == nil)
}

@Test func readerDefaultsAndWarnsOnBadStatus() throws {
    let missing = try #require(PropertyReader.read("type: task\n"))
    #expect(missing.properties.status == .notStarted)
    #expect(missing.warnings == [.missingStatus])

    let unknown = try #require(PropertyReader.read("type: task\nstatus: Someday\n"))
    #expect(unknown.properties.status == .notStarted)
    #expect(unknown.warnings == [.unknownStatus("Someday")])

    let caseless = try #require(PropertyReader.read("type: task\nstatus: not started\n"))
    #expect(caseless.properties.status == .notStarted && caseless.warnings.isEmpty)
}

@Test func readerWarnsOnInvalidValues() throws {
    let yaml = "type: task\nstatus: Doing\ndueDate: 2026-02-30\ndeadline: tomorrow\nproject: Ta Da MVP\narea: [a, b]\ncontexts:\n  - \"@ok\"\n  - {nested: map}\n"
    let read = try #require(PropertyReader.read(yaml))
    #expect(read.properties.dueDate == nil && read.properties.deadline == nil)
    #expect(read.properties.project == nil)
    #expect(read.properties.area == nil)
    #expect(read.properties.contexts == ["@ok"])
    #expect(Set(read.warnings) == [
        .invalidProject("Ta Da MVP"),
        .unexpectedValue(key: "area"),
        .unexpectedValue(key: "contexts"),
        .invalidDate(key: "dueDate", value: "2026-02-30"),
        .invalidDate(key: "deadline", value: "tomorrow"),
    ])
}

@Test func readerWarnsOnUnquotedProjectLink() throws {
    // Unquoted, YAML reads [[Ta Da MVP]] as a nested list.
    let read = try #require(PropertyReader.read("type: task\nstatus: Doing\nproject: [[Ta Da MVP]]\n"))
    #expect(read.properties.project == nil)
    #expect(read.warnings == [.unexpectedValue(key: "project")])
}

@Test func readerIgnoresProjectOnProjects() throws {
    let read = try #require(PropertyReader.read("type: project\nstatus: Doing\nproject: \"[[Other]]\"\n"))
    #expect(read.properties.project == nil && read.warnings.isEmpty)
}

@Test func readerFallsBackToTypeLineOnInvalidYAML() throws {
    // `@` can't start a plain YAML scalar, so an unquoted context breaks the whole block.
    let read = try #require(PropertyReader.read("type: task\nstatus: Done\ncontexts:\n  - @computer\n"))
    #expect(read.properties.kind == .task)
    #expect(read.properties.status == .notStarted)
    guard case let .invalidYAML(problem, line) = try #require(read.warnings.first) else {
        Issue.record("expected invalidYAML, got \(read.warnings)")
        return
    }
    #expect(!problem.isEmpty)
    #expect(line == 5)

    #expect(PropertyReader.read("type: \"project\"\r\nstatus: [unclosed\r\n")?.properties.kind == .project)
    #expect(PropertyReader.read("title: x\nstatus: [unclosed\n") == nil)
    #expect(PropertyReader.read("  type: task\nstatus: [unclosed\n") == nil)
}

@Test func readerWarnsOnDuplicateKeys() throws {
    let read = try #require(PropertyReader.read("type: task\nstatus: Doing\nstatus: Done\n"))
    #expect(read.warnings.count == 1)
    if case .invalidYAML = read.warnings.first {} else { Issue.record("expected invalidYAML, got \(read.warnings)") }
}

@Test func readerHandlesCRLFAndUnicode() throws {
    let read = try #require(PropertyReader.read("type: task\r\nstatus: Doing\r\narea: Café ☕️\r\ncontexts:\r\n  - \"@büro\"\r\nproject: \"[[Dan’s site]]\"\r\ndueDate: 2026-10-02\r\n"))
    #expect(read.properties.area == "Café ☕️")
    #expect(read.properties.contexts == ["@büro"])
    #expect(read.properties.project?.title == "Dan’s site")
    #expect(read.properties.dueDate == LocalDate("2026-10-02"))
    #expect(read.warnings.isEmpty)
}
