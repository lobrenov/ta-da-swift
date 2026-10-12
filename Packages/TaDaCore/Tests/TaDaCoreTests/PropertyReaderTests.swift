import Testing
@testable import TaDaCore

@Test func readerReadsEveryProperty() throws {
    let yaml = """
    type: task
    status: Doing
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
    #expect(p.project?.target == "Ta Da MVP")
    #expect(p.createdDate == LocalDate("2026-09-28"))
    #expect(p.completedDate == LocalDate("2026-10-01"))
    #expect(p.dueDate == LocalDate("2026-10-02"))
    #expect(p.deadline == LocalDate("2026-10-06"))
    #expect(p.repeatRule == "Weekly · Fri")
    #expect(read.warnings.isEmpty)
}

@Test func readerReadsAreaAsLinkOrTitle() throws {
    let link = try #require(PropertyReader.read("type: project\nstatus: Doing\narea: \"[[Personal]]\"\n"))
    #expect(link.properties.area?.title == "Personal" && link.warnings.isEmpty)
    let plain = try #require(PropertyReader.read("type: task\nstatus: Doing\narea: Personal\n"))
    #expect(plain.properties.area?.title == "Personal" && plain.warnings.isEmpty)
}

@Test func readerIgnoresAreaWhenTaskHasProject() throws {
    let read = try #require(PropertyReader.read("type: task\nstatus: Doing\narea: Personal\nproject: \"[[Ta Da MVP]]\"\n"))
    #expect(read.properties.area == nil && read.properties.project?.title == "Ta Da MVP")
    #expect(read.warnings == [.areaIgnored("Personal")])
    let empty = try #require(PropertyReader.read("type: task\nstatus: Doing\narea: Personal\nproject:\n"))
    #expect(empty.properties.area?.title == "Personal" && empty.warnings.isEmpty)
}

@Test func readerReadsAreas() throws {
    let read = try #require(PropertyReader.read("type: area\ncreatedDate: 2026-10-09\narea: \"[[Other]]\"\nproject: \"[[P]]\"\n"))
    #expect(read.properties.kind == .area && read.properties.createdDate == LocalDate("2026-10-09"))
    #expect(read.properties.area == nil && read.properties.project == nil)
    #expect(read.warnings.isEmpty, "areas have no status")
}

@Test func readerIgnoresContexts() throws {
    let read = try #require(PropertyReader.read("type: task\nstatus: Doing\ncontexts:\n  - \"@ok\"\n  - {nested: map}\n"))
    #expect(read.warnings.isEmpty)
}

@Test func readerTreatsEmptyAndNullAsMissing() throws {
    let read = try #require(PropertyReader.read("type: project\nstatus: Doing\narea:\ndueDate: ~\ndeadline: null\nrepeat: \"\"\ncompletedDate:\n"))
    let p = read.properties
    #expect(p.area == nil && p.dueDate == nil && p.deadline == nil && p.repeatRule == nil && p.completedDate == nil)
    #expect(read.warnings.isEmpty)
}

@Test func readerKeepsValuesAsWritten() throws {
    let read = try #require(PropertyReader.read("type: task\nstatus: Doing\narea: yes\nrepeat: 2026\n"))
    #expect(read.properties.area?.title == "yes")
    #expect(read.properties.repeatRule == "2026")
}

@Test func readerMatchesTypeCaseInsensitively() {
    #expect(PropertyReader.read("type: Project\nstatus: Doing\n")?.properties.kind == .project)
    #expect(PropertyReader.read("type: AREA\n")?.properties.kind == .area)
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
    let yaml = "type: task\nstatus: Doing\ndueDate: 2026-02-30\ndeadline: tomorrow\nproject: Ta Da MVP\narea: [a, b]\n"
    let read = try #require(PropertyReader.read(yaml))
    #expect(read.properties.dueDate == nil && read.properties.deadline == nil)
    #expect(read.properties.project == nil)
    #expect(read.properties.area == nil)
    #expect(Set(read.warnings) == [
        .invalidProject("Ta Da MVP"),
        .unexpectedValue(key: "area"),
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
    let area = try #require(PropertyReader.read("type: project\r\nstatus: Doing\r\narea: Café ☕️\r\n"))
    #expect(area.properties.area?.title == "Café ☕️" && area.warnings.isEmpty)
    let read = try #require(PropertyReader.read("type: task\r\nstatus: Doing\r\nproject: \"[[Dan’s site]]\"\r\ndueDate: 2026-10-02\r\n"))
    #expect(read.properties.project?.title == "Dan’s site")
    #expect(read.properties.dueDate == LocalDate("2026-10-02"))
    #expect(read.warnings.isEmpty)
}

/// The canvas's TagModel edge cases for `tags:`, plus a comma-split string.
private let tagCases: [(yaml: String, tags: [String])] = [
    ("tags: [a, b c]", ["a", "b c"]),
    ("tags:\n  - \"#errands\"", ["errands"]),
    ("tags:\n  - errands\n  - Home/Garden/\n  - \"\"\n  - [nested]", ["errands", "Home/Garden"]),
    ("tags: \"errands, quick win, #home/garden\"", ["errands", "quick win", "home/garden"]),
    ("tags: errands, #comment", ["errands"]),
    ("tags: errands", ["errands"]),
    ("tags: [Errands, errands, \"#errands\"]", ["Errands"]),
    ("tags:", []),
    ("tags: []", []),
    ("tags: ~", []),
    ("tags: 2026", ["2026"]),
]

@Test(arguments: tagCases)
func readerReadsTags(_ yaml: String, _ tags: [String]) throws {
    let read = try #require(PropertyReader.read("type: task\nstatus: Doing\n\(yaml)\n"))
    #expect(read.properties.tags.map(\.name) == tags)
    #expect(read.warnings.isEmpty)
}

@Test func readerWarnsOnTagsMapping() throws {
    let read = try #require(PropertyReader.read("type: area\ntags:\n  a: b\n"))
    #expect(read.properties.tags.isEmpty && read.warnings == [.unexpectedValue(key: "tags")])
}

@Test func noteReaderReadsCreatedDateAndTagsOnly() {
    let read = PropertyReader.readNote("createdDate: 2026-10-04\ntags: [a, b]\nstatus: Done\ncustom: kept\n")
    #expect(read.properties.kind == .note && read.properties.createdDate == LocalDate("2026-10-04"))
    #expect(read.properties.tags.map(\.name) == ["a", "b"] && read.properties.status == .notStarted)
    #expect(read.warnings.isEmpty)
}

@Test func noteReaderReadsNothingFromMissingOrNonMappingYAML() {
    for yaml in [nil, "", "- a\n- b\n", "just text\n"] as [String?] {
        let read = PropertyReader.readNote(yaml)
        #expect(read.properties == Properties(kind: .note) && read.warnings.isEmpty, "\(String(describing: yaml))")
    }
}

@Test func noteReaderWarnsOnInvalidYAMLAndBadDates() {
    #expect(PropertyReader.readNote("tags: [a\n").warnings.count == 1)
    #expect(PropertyReader.readNote("createdDate: soon\n").warnings == [.invalidDate(key: "createdDate", value: "soon")])
}

@Test func brokenYAMLWithTypeNoteIsANoteOnlyAtNotePaths() {
    let text = "---\ntype: note\ntags: [a\n---\n"
    #expect(Item(parsing: text, path: "x.md")?.properties.kind == .note)
    #expect(Item(parsing: text, path: "tasks/x.md") == nil)
    #expect(Item(parsing: "---\ntags: [a\n---\n", path: "tasks/x.md") == nil)
}
