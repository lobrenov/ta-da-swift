import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-02")!

private func occurrences(_ frontmatter: String, _ from: String, _ through: String, extra: [Item] = []) -> [String] {
    let task = makeItem("tasks/T.md", "type: task\n" + frontmatter)
    return VaultIndex([task] + extra)
        .occurrences(of: task, from: LocalDate(from)!, through: LocalDate(through)!, today: today)
        .map { "\($0.date)\($0.kind == .deadline ? " deadline" : "")\($0.estimated ? " ~" : "")" }
}

@Test func anOpenTasksOccurrencesFollowItsCurrentDate() {
    let open = "status: Doing\ndueDate: 2026-10-05\nrepeat: every week"
    #expect(occurrences(open, "2026-10-01", "2026-10-31") == ["2026-10-12", "2026-10-19", "2026-10-26"])
    #expect(occurrences(open, "2026-09-01", "2026-10-05").isEmpty)
    #expect(occurrences(open, "2026-10-20", "2026-10-19").isEmpty)
}

@Test func anOpenTasksPastDatesAreNotListed() {
    #expect(occurrences("status: Doing\ndueDate: 2026-09-07\nrepeat: every week", "2026-09-01", "2026-10-12")
            == ["2026-10-05", "2026-10-12"])
    #expect(occurrences("status: Doing\ndueDate: 2026-09-07\nrepeat: every week on Mon", "2026-09-01", "2026-10-12")
            == ["2026-10-05", "2026-10-12"])
    #expect(occurrences("status: Doing\ndueDate: 2026-09-07\nrepeat: every 3 days when done", "2026-09-01", "2026-10-10")
            == ["2026-10-05 ~", "2026-10-08 ~"])
}

@Test func occurrencesDontDriftFromTheAnchorWithADay() {
    #expect(occurrences("status: Doing\ndueDate: 2026-01-31\nrepeat: every month on the 31st", "2026-10-03", "2027-02-28")
            == ["2026-10-31", "2026-11-30", "2026-12-31", "2027-01-31", "2027-02-28"])
}

@Test func aMonthOrYearRuleWithoutADayDriftsAsLoggingDoes() {
    #expect(occurrences("status: Doing\ndueDate: 2026-10-31\nrepeat: every month", "2026-11-01", "2027-02-28")
            == ["2026-11-30", "2026-12-30", "2027-01-30", "2027-02-28"])
    #expect(occurrences("status: Doing\ndueDate: 2026-01-31\nrepeat: every month", "2026-10-03", "2026-12-31")
            == ["2026-10-31", "2026-11-30", "2026-12-30"])
    #expect(occurrences("status: Doing\ndueDate: 2028-02-29\nrepeat: every year", "2028-03-01", "2031-03-01")
            == ["2029-02-28", "2030-02-28", "2031-02-28"])
}

@Test func aFarAwayRangeIsCheap() {
    #expect(occurrences("status: Doing\ndueDate: 2026-10-05\nrepeat: every day", "2126-01-01", "2126-01-07").count == 7)
}

@Test func whenDoneOccurrencesChainAndAreEstimated() {
    #expect(occurrences("status: Doing\ndueDate: 2026-10-05\nrepeat: every 2 weeks when done", "2026-10-01", "2026-11-05")
            == ["2026-10-19 ~", "2026-11-02 ~"])
    #expect(occurrences("status: Doing\ndueDate: 2026-10-05\nrepeat: every 2 weeks when done", "2026-11-01", "2026-11-05")
            == ["2026-11-02 ~"])
}

@Test func aCompletedTaskProjectsFromItsNextDate() {
    let done = "status: Done\ncompletedDate: 2026-10-01\ndueDate: 2026-09-28\nrepeat: every week"
    #expect(occurrences(done, "2026-10-01", "2026-10-20") == ["2026-10-05", "2026-10-12", "2026-10-19"])
    #expect(occurrences(done, "2026-10-06", "2026-10-20") == ["2026-10-12", "2026-10-19"])
    let doneToday = "status: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nrepeat: every day"
    #expect(occurrences(doneToday, "2026-10-01", "2026-10-05") == ["2026-10-03", "2026-10-04", "2026-10-05"])
    let overdue = "status: Cancelled\ncompletedDate: 2026-09-20\ndueDate: 2026-09-20\nrepeat: every day"
    #expect(occurrences(overdue, "2026-10-01", "2026-10-03") == ["2026-10-02", "2026-10-03"])
    let whenDone = "status: Done\ncompletedDate: 2026-10-01\ndueDate: 2026-09-28\nrepeat: every 3 days when done"
    #expect(occurrences(whenDone, "2026-10-01", "2026-10-12") == ["2026-10-04", "2026-10-07 ~", "2026-10-10 ~"])
}

@Test func aCompletedTasksKindsAndOffsetComeFromItsNextDates() {
    #expect(occurrences("status: Done\ncompletedDate: 2026-10-01\nrepeat: every week", "2026-10-01", "2026-10-22")
            == ["2026-10-08", "2026-10-15", "2026-10-22"])
    let both = "status: Done\ncompletedDate: 2026-10-01\ndueDate: 2026-09-28\ndeadline: 2026-09-30\nrepeat: every week"
    #expect(occurrences(both, "2026-10-01", "2026-10-14") == ["2026-10-05", "2026-10-07 deadline", "2026-10-12", "2026-10-14 deadline"])
    let deadlineOnly = "status: Done\ncompletedDate: 2026-10-01\ndeadline: 2026-09-28\nrepeat: every week"
    #expect(occurrences(deadlineOnly, "2026-10-01", "2026-10-14") == ["2026-10-05 deadline", "2026-10-12 deadline"])
    let whenDone = "status: Done\ncompletedDate: 2026-10-01\ndueDate: 2026-09-28\ndeadline: 2026-09-30\nrepeat: every 3 days when done"
    #expect(occurrences(whenDone, "2026-10-01", "2026-10-08") == ["2026-10-04", "2026-10-06 deadline", "2026-10-07 ~"])
}

@Test func untilEndsOccurrences() {
    #expect(occurrences("status: Doing\ndueDate: 2026-10-05\nrepeat: every week until 2026-10-20", "2026-10-01", "2026-11-30")
            == ["2026-10-12", "2026-10-19"])
    #expect(occurrences("status: Done\ncompletedDate: 2026-10-01\ndueDate: 2026-09-28\nrepeat: every week until 2026-10-01",
                        "2026-10-01", "2026-11-30").isEmpty)
    #expect(occurrences("status: Doing\ndueDate: 2026-10-05\nrepeat: every 2 weeks when done until 2026-10-20", "2026-10-01", "2026-11-30")
            == ["2026-10-19 ~"])
}

@Test func deadlinesFollowTheDueOffset() {
    #expect(occurrences("status: Doing\ndeadline: 2026-10-05\nrepeat: every week", "2026-10-10", "2026-10-21")
            == ["2026-10-12 deadline", "2026-10-19 deadline"])
    let both = "status: Doing\ndueDate: 2026-10-05\ndeadline: 2026-10-07\nrepeat: every week"
    #expect(occurrences(both, "2026-10-10", "2026-10-21") == ["2026-10-12", "2026-10-14 deadline", "2026-10-19", "2026-10-21 deadline"])
    #expect(occurrences(both, "2026-10-13", "2026-10-14") == ["2026-10-14 deadline"])
    let before = "status: Doing\ndueDate: 2026-10-05\ndeadline: 2026-10-03\nrepeat: every week"
    #expect(occurrences(before, "2026-10-10", "2026-10-12") == ["2026-10-10 deadline", "2026-10-12"])
}

@Test func nothingWithoutAReadableRuleDateOrOpenSeries() {
    #expect(occurrences("status: Doing\ndueDate: 2026-10-05\nrepeat: Weekly · Fri", "2026-10-01", "2026-10-31").isEmpty)
    #expect(occurrences("status: Doing\nrepeat: every week", "2026-10-01", "2026-10-31").isEmpty)
    let closed = makeItem("projects/Shipped.md", "type: project\nstatus: Done")
    #expect(occurrences("status: Done\ncompletedDate: 2026-10-01\ndueDate: 2026-09-28\nrepeat: every week\nproject: \"[[Shipped]]\"",
                        "2026-10-01", "2026-10-31", extra: [closed]).isEmpty)
    let project = makeItem("projects/P.md", "type: project\nstatus: Doing\ndueDate: 2026-10-05\nrepeat: every week")
    #expect(VaultIndex([project]).occurrences(of: project, from: today, through: LocalDate("2026-10-31")!, today: today).isEmpty)
}

@Test func occurrencesMarkTheirDaysExceptDailyAndWeekdayRules() {
    func marks(_ rule: String, status: String = "Doing\ndueDate: 2026-10-05") -> [LocalDate] {
        let task = makeItem("tasks/T.md", "type: task\nstatus: \(status)\nrepeat: \(rule)")
        return VaultIndex([task]).dayMarks(from: LocalDate("2026-10-06")!, through: LocalDate("2026-10-14")!, today: today).keys.sorted()
    }
    #expect(marks("every week") == [LocalDate("2026-10-12")!])
    #expect(marks("every 2 days") == ["2026-10-07", "2026-10-09", "2026-10-11", "2026-10-13"].map { LocalDate($0)! })
    #expect(marks("every day").isEmpty)
    #expect(marks("every weekday").isEmpty)
    #expect(marks("every 3 days when done") == [LocalDate("2026-10-08")!, LocalDate("2026-10-11")!, LocalDate("2026-10-14")!])
    #expect(marks("every week", status: "Done\ncompletedDate: 2026-10-01\ndueDate: 2026-09-28") == [LocalDate("2026-10-12")!])
}

@Test func theOccurrencesOfAllTasksAreOrderedByDateKindThenTitle() {
    let items = [
        makeItem("tasks/B.md", "type: task\nstatus: Doing\ndueDate: 2026-10-05\nrepeat: every week"),
        makeItem("tasks/A.md", "type: task\nstatus: Doing\ndeadline: 2026-10-05\nrepeat: every week"),
        makeItem("tasks/C.md", "type: task\nstatus: Doing\ndueDate: 2026-10-05\nrepeat: every week"),
        makeItem("tasks/Unreadable.md", "type: task\nstatus: Doing\ndueDate: 2026-10-05\nrepeat: Weekly · Fri"),
        makeItem("tasks/Plain.md", "type: task\nstatus: Doing\ndueDate: 2026-10-12"),
        makeItem("tasks/Mon.md", "type: task\nstatus: Doing\ndueDate: 2026-10-06\nrepeat: every 6 days")
    ]
    let found = VaultIndex(items).occurrences(from: LocalDate("2026-10-10")!, through: LocalDate("2026-10-19")!, today: today)
        .map { "\($0.date) \($0.item.title)\($0.kind == .deadline ? " deadline" : "")" }
    #expect(found == ["2026-10-12 B", "2026-10-12 C", "2026-10-12 Mon", "2026-10-12 A deadline", "2026-10-18 Mon",
                      "2026-10-19 B", "2026-10-19 C", "2026-10-19 A deadline"])
    #expect(VaultIndex(items).occurrences(from: LocalDate("2026-10-19")!, through: LocalDate("2026-10-10")!, today: today).isEmpty)
}
