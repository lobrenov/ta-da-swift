import Testing
@testable import TaDaCore

private func date(_ text: String?) -> LocalDate? { text.flatMap(LocalDate.init) }

/// The next dates as strings; `rollover` is the day after `done` unless given.
private func next(_ phrase: String, due: String? = nil, deadline: String? = nil, done: String? = nil,
                  rollover: String? = nil) -> [String?]? {
    let rollover = date(rollover) ?? date(done)!.adding(days: 1)
    let result = RepeatRule.parse(phrase)!.next(dueDate: date(due), deadline: date(deadline), completedDate: date(done),
                                                rolloverDay: rollover)
    return result.map { [$0.dueDate?.description, $0.deadline?.description] }
}

/// Moves `due` forward `steps` times, each the day after it.
private func chain(_ phrase: String, from due: String, steps: Int) -> [String] {
    var current = due
    return (0..<steps).map { _ in
        current = next(phrase, due: current, done: current)![0]!
        return current
    }
}

// 26 Oct 2026 is a Monday.
@Test(arguments: [
    // Regular schedule: early, on time, late
    ("every week on Mon", "2026-10-26", "2026-10-22", "2026-11-02"),
    ("every week on Mon", "2026-10-26", "2026-10-26", "2026-11-02"),
    ("every week on Mon", "2026-10-26", "2026-11-04", "2026-11-09"),
    // A daily task closed two weeks late moves to the rollover day
    ("every day", "2026-10-12", "2026-10-26", "2026-10-27"),
    ("every 3 days", "2026-10-12", "2026-10-26", "2026-10-27"),
    ("every 3 days", "2026-10-12", "2026-10-27", "2026-10-30"),
    ("every weekday", "2026-10-30", "2026-10-30", "2026-11-02"),
    ("every weekday", "2026-10-26", "2026-10-26", "2026-10-27"),
    // Intervals
    ("every 2 weeks on Mon", "2026-10-26", "2026-10-26", "2026-11-09"),
    ("every 2 weeks on Mon, Thu", "2026-10-26", "2026-10-26", "2026-10-29"),
    ("every 2 weeks on Mon, Thu", "2026-10-29", "2026-10-29", "2026-11-09"),
    ("every week on Thu, Mon", "2026-10-29", "2026-10-29", "2026-11-02"),
    ("every 2 months", "2026-10-15", "2026-10-15", "2026-12-15"),
    ("every 2 years", "2026-10-26", "2026-10-26", "2028-10-26"),
    // No `on …`: the day comes from dueDate
    ("every week", "2026-10-28", "2026-10-28", "2026-11-04"),
    ("every month", "2026-10-15", "2026-10-15", "2026-11-15"),
    ("every month", "2026-01-31", "2026-01-31", "2026-02-28"),
    ("every year", "2026-10-26", "2026-10-26", "2027-10-26"),
    // Month days
    ("every month on the 31st", "2026-01-31", "2026-01-31", "2026-02-28"),
    ("every month on the 31st", "2028-01-31", "2028-01-31", "2028-02-29"),
    ("every month on the last day", "2026-01-31", "2026-01-31", "2026-02-28"),
    ("every month on the 15th", "2026-10-20", "2026-10-20", "2026-11-15"),
    // Ordinal and last weekdays
    ("every month on the 2nd Tue", "2026-10-13", "2026-10-13", "2026-11-10"),
    ("every month on the last Fri", "2026-10-30", "2026-10-30", "2026-11-27"),
    ("every month on the last Fri", "2026-11-27", "2026-11-27", "2026-12-25"),
    ("every month on the 5th Mon", "2026-08-31", "2026-08-31", "2026-11-30"),
    // Years
    ("every year on Oct 26", "2026-10-26", "2026-10-26", "2027-10-26"),
    ("every year on Mar 1", "2026-10-26", "2026-10-26", "2027-03-01"),
    ("every year on Feb 29", "2028-02-29", "2028-02-29", "2029-02-28"),
    ("every year on Feb 29", "2031-02-28", "2031-02-28", "2032-02-29"),
    ("every year", "2028-02-29", "2028-02-29", "2029-02-28"),
] as [(String, String, String, String)])
func nextDueDate(phrase: String, due: String, done: String, expected: String) {
    #expect(next(phrase, due: due, done: done) == [expected, nil])
}

@Test func monthEndsDoNotDrift() {
    #expect(chain("every month on the 31st", from: "2026-01-31", steps: 5)
        == ["2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31", "2026-06-30"])
    #expect(chain("every month on the 31st", from: "2027-12-31", steps: 3) == ["2028-01-31", "2028-02-29", "2028-03-31"])
    #expect(chain("every 2 months on the 31st", from: "2026-01-31", steps: 3) == ["2026-03-31", "2026-05-31", "2026-07-31"])
    #expect(chain("every month on the last day", from: "2028-01-31", steps: 3) == ["2028-02-29", "2028-03-31", "2028-04-30"])
    #expect(chain("every year on Feb 29", from: "2028-02-29", steps: 4)
        == ["2029-02-28", "2030-02-28", "2031-02-28", "2032-02-29"])
}

@Test func aFifthWeekdayTheMonthLacksIsSkipped() {
    #expect(chain("every month on the 5th Mon", from: "2026-08-31", steps: 2) == ["2026-11-30", "2027-03-29"])
}

@Test func missedOccurrencesAreSkippedToTheRolloverDay() {
    #expect(next("every day", due: "2026-10-12", done: "2026-10-12", rollover: "2026-10-27") == ["2026-10-27", nil])
    #expect(next("every week on Mon", due: "2026-10-05", done: "2026-10-05", rollover: "2026-10-27") == ["2026-11-02", nil])
    #expect(next("every month on the 15th", due: "2026-06-15", done: "2026-06-15", rollover: "2026-10-27")
        == ["2026-11-15", nil])
}

@Test func aTaskWithOnlyADeadlineMovesTheDeadline() {
    #expect(next("every week", deadline: "2026-10-28", done: "2026-10-28") == [nil, "2026-11-04"])
}

@Test func aTaskWithNoDatesGetsADueDateFromCompletedDate() {
    #expect(next("every week", done: "2026-10-28") == ["2026-11-04", nil])
    #expect(next("every month on the 1st", done: "2026-10-28") == ["2026-11-01", nil])
}

@Test func aTaskWithNoDatesAndNoCompletedDateMovesToTheRolloverDay() {
    let rule = RepeatRule.parse("every day")!
    let day = LocalDate("2026-10-27")!
    #expect(rule.next(dueDate: nil, deadline: nil, completedDate: nil, rolloverDay: day)
        == RepeatRule.Next(dueDate: day))
}

@Test func theDeadlineKeepsItsDistanceFromTheDueDate() {
    #expect(next("every week on Mon", due: "2026-10-26", deadline: "2026-10-30", done: "2026-10-26")
        == ["2026-11-02", "2026-11-06"])
    #expect(next("every month on the 31st", due: "2026-01-31", deadline: "2026-02-03", done: "2026-01-31")
        == ["2026-02-28", "2026-03-03"])
    #expect(next("every day", due: "2026-10-12", deadline: "2026-10-10", done: "2026-10-26") == ["2026-10-27", "2026-10-25"])
}

@Test(arguments: [
    ("every 3 days when done", "2026-10-27", "2026-10-30"),
    ("every 2 weeks when done", "2026-10-27", "2026-11-10"),
    ("every month when done", "2026-01-31", "2026-02-28"),
    ("every 2 months when done", "2026-10-27", "2026-12-27"),
    ("every year when done", "2028-02-29", "2029-02-28"),
    ("every weekday when done", "2026-10-30", "2026-11-02"),
    ("every week on Mon when done", "2026-10-27", "2026-11-02"),
    ("every 2 weeks on Mon when done", "2026-10-27", "2026-11-09"),
    ("every 2 weeks on Mon, Thu when done", "2026-10-27", "2026-11-05"),
    ("every month on the 2nd Tue when done", "2026-10-14", "2026-11-10"),
    ("every 2 months on the last Fri when done", "2026-10-31", "2026-12-25"),
    ("every month on the 15th when done", "2026-10-20", "2026-11-15"),
    ("every 2 months on the 15th when done", "2026-10-20", "2026-12-15"),
    ("every 2 months on the 31st when done", "2026-01-05", "2026-02-28"),
    ("every 2 months on the 31st when done", "2026-01-31", "2026-03-31"),
    ("every 2 years on Oct 26 when done", "2026-10-27", "2028-10-26"),
])
func nextWhenDone(phrase: String, done: String, expected: String) {
    #expect(next(phrase, due: "2026-10-10", done: done) == [expected, nil])
}

@Test func whenDoneKeepsTheDeadlineDistanceAndIgnoresAMissedDueDate() {
    #expect(next("every 2 weeks when done", due: "2026-10-01", deadline: "2026-10-04", done: "2026-10-27")
        == ["2026-11-10", "2026-11-13"])
}

@Test func whenDoneDoesNotMoveUpToTheRolloverDay() {
    #expect(next("every 3 days when done", due: "2026-10-10", done: "2026-10-27", rollover: "2026-11-20") == ["2026-10-30", nil])
}

@Test func whenDoneWithoutACompletedDateCountsFromTheDueDateThenTheDayBeforeRollover() {
    let rule = RepeatRule.parse("every 3 days when done")!
    let rollover = LocalDate("2026-10-27")!
    #expect(rule.next(dueDate: LocalDate("2026-10-26"), deadline: nil, completedDate: nil, rolloverDay: rollover)?.dueDate
        == LocalDate("2026-10-29"))
    #expect(rule.next(dueDate: nil, deadline: nil, completedDate: nil, rolloverDay: rollover)?.dueDate
        == LocalDate("2026-10-29"))
}

@Test(arguments: [
    ("2026-11-09", "2026-11-02"),
    ("2026-11-02", "2026-11-02"),
    ("2026-11-01", nil),
    ("2026-10-26", nil),
] as [(String, String?)])
func untilIsInclusive(until: String, expected: String?) {
    #expect(next("every week on Mon until \(until)", due: "2026-10-26", done: "2026-10-26") == expected.map { [$0, nil] })
}

@Test func untilAppliesToTheDeadlineWhenThatIsAllThereIs() {
    #expect(next("every week until 2026-11-04", deadline: "2026-10-28", done: "2026-10-28") == [nil, "2026-11-04"])
    #expect(next("every week until 2026-11-03", deadline: "2026-10-28", done: "2026-10-28") == nil)
}

@Test func untilAppliesToWhenDoneRules() {
    #expect(next("every 3 days until 2026-10-30 when done", done: "2026-10-27") == ["2026-10-30", nil])
    #expect(next("every 3 days until 2026-10-29 when done", done: "2026-10-27") == nil)
}

@Test func weeksAlignAcrossAYearBoundary() {
    #expect(next("every 2 weeks on Mon, Thu", due: "2026-12-31", done: "2026-12-31") == ["2027-01-11", nil])
    #expect(next("every 2 weeks on Mon, Thu", due: "2026-12-31", rollover: "2027-01-12") == ["2027-01-14", nil])
}

@Test func weeksRunMondayToSunday() {
    #expect(next("every 2 weeks on Sun, Mon", due: "2026-10-26", done: "2026-10-26") == ["2026-11-01", nil])
    #expect(next("every 2 weeks on Mon", due: "2026-10-05", rollover: "2026-10-27") == ["2026-11-02", nil])
}

@Test func nothingIsNextPastYear9999() {
    #expect(next("every week on Mon", deadline: "9999-12-31", done: "9999-12-31", rollover: "9999-12-31") == nil)
    #expect(next("every day", due: "9999-12-31", done: "9999-12-31", rollover: "9999-12-31") == nil)
    #expect(next("every day when done", due: "9999-12-31", done: "9999-12-31", rollover: "9999-12-31") == nil)
    #expect(next("every week", due: "9999-12-24", deadline: "9999-12-31", done: "9999-12-24", rollover: "9999-12-31") == nil)
}

@Test func datesAreCountedFromTheAnchor() {
    let monthly = RepeatRule.parse("every month")!
    #expect(monthly.dates(after: date("2026-01-31")!, from: date("2026-01-31")!, through: date("2026-05-31")!).map(\.description)
        == ["2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31"])
    let daily = RepeatRule.parse("every day")!
    #expect(daily.dates(after: date("2026-10-01")!, from: date("2026-10-10")!, through: date("2026-10-12")!).map(\.description)
        == ["2026-10-10", "2026-10-11", "2026-10-12"])
}

@Test func datesStopAtUntil() {
    let rule = RepeatRule.parse("every week on Mon until 2026-11-09")!
    #expect(rule.dates(after: date("2026-10-26")!, from: date("2026-10-26")!, through: date("2026-12-31")!).map(\.description)
        == ["2026-11-02", "2026-11-09"])
}
