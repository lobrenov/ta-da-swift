import Testing
@testable import TaDaCore

private let date = LocalDate("2026-10-02")!
private let week = ISOWeek(year: 2026, week: 40)!

@Test func namesDefaultToPeriodicNotes() {
    let names = DailyNoteNames()
    #expect(names.path(for: date) == "Periodic Notes/Daily Notes/2026-10-02.md")
    #expect(names.path(for: week) == "Periodic Notes/Weekly Notes/2026-W40.md")
    #expect(names.path(for: ISOWeek(year: 2026, week: 3)!) == "Periodic Notes/Weekly Notes/2026-W03.md")
}

@Test func namesRoundTripInAnyFolder() {
    for names in [DailyNoteNames(), DailyNoteNames(dailyFolder: "Journal/2026", weekFolder: "Weeks"),
                  DailyNoteNames(dailyFolder: "Notes", weekFolder: "Notes"), DailyNoteNames(dailyFolder: "", weekFolder: "")] {
        #expect(names.date(atPath: names.path(for: date)) == date)
        #expect(names.week(atPath: names.path(for: week)) == week)
        #expect(names.week(atPath: names.path(for: date)) == nil && names.date(atPath: names.path(for: week)) == nil)
    }
}

@Test func pathsOutsideTheNamePatternsAreNotRead() {
    let names = DailyNoteNames()
    for path in ["Periodic Notes/Daily Notes/2026-10-02 standup.md", "Periodic Notes/Daily Notes/2026-10-32.md",
                 "Periodic Notes/Daily Notes/Sub/2026-10-02.md", "Periodic Notes/Weekly Notes/2026-10-02.md",
                 "Other/2026-10-02.md", "Periodic Notes/Daily Notes/2026-10-02.txt", "2026-10-02.md"] {
        #expect(names.date(atPath: path) == nil, "\(path)")
    }
    for path in ["Periodic Notes/Weekly Notes/2027-W53.md", "Periodic Notes/Weekly Notes/2026-W00.md",
                 "Periodic Notes/Weekly Notes/2026-W4.md", "Periodic Notes/Weekly Notes/2026-w40.md",
                 "Periodic Notes/Weekly Notes/2026-W+1.md", "Periodic Notes/Daily Notes/2026-W40.md"] {
        #expect(names.week(atPath: path) == nil, "\(path)")
    }
}

private func daily(_ path: String, body: String = "") -> Item {
    Item(parsing: NewFile.note(today: date) + body, path: path)!
}

@Test func lookupsFindTheNoteAtTheExactPath() {
    let names = DailyNoteNames(dailyFolder: "Journal", weekFolder: "Journal")
    let index = VaultIndex([daily("Journal/2026-10-02.md"), daily("Journal/2026-W40.md"), daily("Journal/2026-10-03 renamed.md"),
                            daily("Periodic Notes/Daily Notes/2026-10-01.md")])
    #expect(index.dailyNote(for: date, names: names)?.path == "Journal/2026-10-02.md")
    #expect(index.weekNote(for: week, names: names)?.path == "Journal/2026-W40.md")
    #expect(index.dailyNote(for: LocalDate("2026-10-03")!, names: names) == nil, "a renamed note isn't found")
    #expect(index.dailyNote(for: date) == nil && index.weekNote(for: week) == nil, "other folders aren't searched")
    #expect(index.dailyNote(for: LocalDate("2026-10-01")!)?.title == "2026-10-01")
}

@Test func aTypedFileAtTheNamePathIsNotANote() {
    let task = makeItem("Periodic Notes/Daily Notes/2026-10-02.md", "type: task\nstatus: Doing")
    #expect(VaultIndex([task]).dailyNote(for: date) == nil)
}

@Test func openCheckboxCountCountsUncheckedBoxes() {
    let note = daily("a.md", body: "- [ ] a\n- [/] b\n- [>] c\n- [x] d\n- [X] e\n- [-] f\n- [?] g\n- plain\n")
    #expect(VaultIndex().openCheckboxCount(note) == 3)
}

@Test func dailyNoteTextIsTheNoteFrontmatterThenTheTemplateBody() throws {
    #expect(NewFile.dailyNote(template: nil, today: date) == NewFile.note(today: date))
    let template = "---\ntype: task\ntags: [x]\n---\n## Plan\n- [ ] \n"
    let text = NewFile.dailyNote(template: template, today: date)
    #expect(text == "---\ncreatedDate: 2026-10-02\ntags: []\n---\n## Plan\n- [ ] \n")
    #expect(try #require(Item(parsing: text, path: "Journal/2026-10-02.md")).properties.kind == .note)
    #expect(NewFile.dailyNote(template: "No frontmatter\n", today: date) == NewFile.note(today: date) + "No frontmatter\n")
}

@Test func marksShowOpenTasksAndUncheckedBoxes() {
    let index = VaultIndex([
        makeItem("tasks/Due.md", "type: task\nstatus: Doing\ndueDate: 2026-10-02"),
        makeItem("tasks/Deadline.md", "type: task\nstatus: Doing\ndeadline: 2026-10-04"),
        makeItem("tasks/Done.md", "type: task\nstatus: Done\ndueDate: 2026-10-03\ncompletedDate: 2026-10-03"),
        makeItem("tasks/Outside.md", "type: task\nstatus: Doing\ndueDate: 2026-10-20"),
        daily("Periodic Notes/Daily Notes/2026-10-02.md", body: "- [ ] a\n- [x] b\n"),
        daily("Periodic Notes/Daily Notes/2026-10-03.md", body: "- [/] a\n"),
        daily("Periodic Notes/Daily Notes/2026-10-05.md", body: "- [x] a\n- [-] b\n"),
        daily("Periodic Notes/Daily Notes/2026-10-06.md", body: "- [-] a\n"),
        daily("Periodic Notes/Daily Notes/2026-10-07.md"),
    ])
    let marks = index.dayMarks(from: date, through: LocalDate("2026-10-08")!, today: date)
    #expect(marks == [
        date: DayMarks(hasOpenTasks: true, hasOpenBoxes: true),
        LocalDate("2026-10-03")!: DayMarks(hasOpenTasks: false, hasOpenBoxes: true),
        LocalDate("2026-10-04")!: DayMarks(hasOpenTasks: true, hasOpenBoxes: false),
    ])
    #expect(index.dayMarks(from: date, through: date.adding(days: -1), today: date).isEmpty)
}

@Test func marksOnTheDesignVault() async {
    let index = await Vault(root: sampleVault).loadIndex()
    let marks = index.dayMarks(from: date, through: date.adding(days: 6), today: date)
    #expect(marks[date]?.hasOpenTasks == true && marks.values.allSatisfy { !$0.hasOpenBoxes })
}
