import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-02")!

private func note(_ path: String, _ body: String) -> Item { makeItem(path, "tags: []", body: body) }

/// A project "Ta Da MVP" in an area "Work", an unrelated area, and a task and a note with every kind of line.
private func vault() -> VaultIndex {
    VaultIndex([
        makeItem("Ta Da/areas/Work.md", "type: area"),
        makeItem("Ta Da/projects/Ta Da MVP.md", "type: project\nstatus: Doing\narea: \"[[Work]]\"", body: """
        - [ ] Own dated >2026-10-09
        - [ ] Own plain
        - [ ] Own to self @[[Ta Da MVP]]
        - [ ] Own to self and dated >2026-10-09 @[[Ta Da MVP]]
        """),
        makeItem("Ta Da/tasks/Draft.md", "type: task\nstatus: Doing\nproject: \"[[Ta Da MVP]]\"", body: """
        - [ ] Plain subtask
        - [ ] Filed elsewhere @[[Work]]
        """),
        makeItem("Ta Da/tasks/Finished.md", "type: task\nstatus: Done", body: "- [ ] Stale >2026-10-09\n"),
        note("Meetings/Standup.md", """
        - [ ] Loose
        - [/] Doing >2026-10-09
        - [x] Done >2026-10-09
        - [-] Cancelled >2026-10-09
        - [?] Icon >2026-10-09
        - [ ] Overdue >2026-09-30
        - [ ] Both >2026-10-03 @[[Ta Da MVP]]
        - [ ] Unresolved @[[Nowhere]]
        - [ ] Unresolved but dated >2026-10-02 @[[Nowhere]]
        - [ ] Parent with nest @[[Ta Da MVP]]
          - [ ] Child >2026-10-02 @[[Work]]
        > - [ ] Quoted >2026-10-02
        > [!todo]
        > - [ ] Callout @[[Work]]
        ```
        - [ ] Code >2026-10-02
        ```
        - [ ] Two dates >2026-10-04 >2026-10-02
        """),
        note("Daily/A note.md", "- [ ] Dated >2026-10-02\n- [ ] Another >2026-10-09\n"),
    ])
}

private func summary(_ cards: [SubtaskCard]) -> [String] {
    cards.map { "\($0.path): \($0.lines.map(\.title).joined(separator: " | "))" }
}

private func day(_ text: String) -> LocalDate { LocalDate(text)! }

@Test func aDayListsItsDatedLinesAndTodayAddsTheOverdue() {
    let index = vault()
    #expect(summary(index.noteSubtasks(on: today, today: today)) == [
        "Daily/A note.md: Dated",
        "Meetings/Standup.md: Overdue | Unresolved but dated",
    ])
    #expect(summary(index.noteSubtasks(on: day("2026-10-03"), today: today)) == ["Meetings/Standup.md: Both"])
    #expect(summary(index.noteSubtasks(on: day("2026-09-30"), today: today)) == ["Meetings/Standup.md: Overdue"])
    #expect(summary(index.noteSubtasks(on: day("2026-10-04"), today: today)) == ["Meetings/Standup.md: Two dates >2026-10-02"])
}

@Test func anyFileWithADatedLineListsItOnItsDay() {
    #expect(summary(vault().noteSubtasks(on: day("2026-10-09"), today: today)) == [
        "Daily/A note.md: Another",
        "Meetings/Standup.md: Doing",
        "Ta Da/projects/Ta Da MVP.md: Own dated | Own to self and dated",
    ])
}

@Test func aRangeListsLinesDueWithinItWithoutTheOverdue() {
    #expect(summary(vault().noteSubtasks(from: day("2026-10-03"), through: day("2026-10-09"))) == [
        "Daily/A note.md: Another",
        "Meetings/Standup.md: Doing | Both | Two dates >2026-10-02",
        "Ta Da/projects/Ta Da MVP.md: Own dated | Own to self and dated",
    ])
}

@Test func aProjectListsLinesNamingItExceptItsOwn() throws {
    let index = vault()
    let project = try #require(index["Ta Da/projects/Ta Da MVP.md"])
    #expect(summary(index.noteSubtasks(parent: project)) == ["Meetings/Standup.md: Both | Parent with nest"])
}

@Test func anAreaListsLinesNamingIt() throws {
    let index = vault()
    let area = try #require(index["Ta Da/areas/Work.md"])
    #expect(summary(index.noteSubtasks(parent: area)) == ["Ta Da/tasks/Draft.md: Filed elsewhere"])
}

@Test func looseLinesAreANotesOpenLinesWithNeitherAttribute() {
    #expect(summary(vault().looseNoteSubtasks()) == ["Meetings/Standup.md: Loose | Unresolved"])
}

@Test func anUnresolvedParentDoesNotPlaceTheLine() throws {
    let index = vault()
    let all = [index.noteSubtasks(on: today, today: today), index.noteSubtasks(from: day("2026-10-01"), through: day("2026-10-31"))]
    #expect(all.flatMap { $0 }.flatMap(\.lines).filter { $0.text.contains("Nowhere") }.map(\.title) == ["Unresolved but dated", "Unresolved but dated"])
}

@Test func onlyOpenUnnestedUnquotedLinesAreListed() {
    let index = vault()
    let titles = index.noteSubtasks(from: day("2000-01-01"), through: day("2100-01-01")).flatMap(\.lines).map(\.title)
    for skipped in ["Done", "Cancelled", "Icon", "Child", "Quoted", "Code", "Stale"] { #expect(!titles.contains(skipped), "\(skipped)") }
}

@Test func aParentResolvesToTheProjectBeforeTheArea() throws {
    let index = VaultIndex([
        makeItem("Ta Da/areas/Home.md", "type: area"), makeItem("Ta Da/projects/Home.md", "type: project\nstatus: Doing"),
        note("N.md", "- [ ] a @[[Home]]\n"),
    ])
    #expect(index.parentItem(titled: "home")?.properties.kind == .project)
    let project = try #require(index["Ta Da/projects/Home.md"]), area = try #require(index["Ta Da/areas/Home.md"])
    #expect(summary(index.noteSubtasks(parent: project)) == ["N.md: a"])
    #expect(index.noteSubtasks(parent: area).isEmpty)
}

@Test func linesOfDifferentFilesGroupByTitleThenPathAndKeepFileOrder() {
    let index = VaultIndex([note("b/Same.md", "- [ ] b2\n- [ ] b1\n"), note("a/Same.md", "- [ ] a1\n"), note("A first.md", "- [ ] f\n")])
    #expect(summary(index.looseNoteSubtasks()) == ["A first.md: f", "a/Same.md: a1", "b/Same.md: b2 | b1"])
    #expect(index.looseNoteSubtasks().last?.lines.map(\.lineIndex) == [3, 4])
}

@Test func linesAreFileLinesSoAClickTicksThem() throws {
    let text = "---\ntags: []\n---\nIntro\n- [ ] Call >2026-10-02\n"
    let index = VaultIndex([try #require(Item(parsing: text, path: "N.md"))])
    let box = try #require(index.noteSubtasks(on: today, today: today).first?.lines.first)
    #expect(ChecklistEditor.click(box, in: text) == "---\ntags: []\n---\nIntro\n- [x] Call >2026-10-02\n")
}

@Test func crlfNotesListTheirLines() {
    let index = VaultIndex([note("N.md", "- [ ] a >2026-10-02\r\n  - [ ] b >2026-10-02\r\n- [ ] c\r\n")])
    #expect(summary(index.noteSubtasks(on: today, today: today)) == ["N.md: a"])
    #expect(summary(index.looseNoteSubtasks()) == ["N.md: c"])
}

@Test func datedLinesMarkTheirDayAsOpenTasks() {
    let index = vault()
    let marks = index.dayMarks(from: day("2026-09-28"), through: day("2026-10-10"), today: today)
    #expect(marks.keys.sorted() == ["2026-09-30", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-09"].map(day))
    #expect(marks.values.allSatisfy { $0.hasOpenTasks })
    #expect(index.dayMarks(from: day("2026-09-28"), through: day("2026-10-10"), today: today, includingSubtasks: false).isEmpty)
}
