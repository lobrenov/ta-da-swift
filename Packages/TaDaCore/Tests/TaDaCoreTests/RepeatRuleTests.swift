import Testing
@testable import TaDaCore

private let mon = 2, tue = 3, thu = 5, fri = 6, sun = 1

@Test(arguments: [
    ("every day", RepeatRule(frequency: .day)!),
    ("every 3 days", RepeatRule(frequency: .day, interval: 3)!),
    ("every weekday", RepeatRule(frequency: .weekday)!),
    ("every week", RepeatRule(frequency: .week)!),
    ("every 2 weeks", RepeatRule(frequency: .week, interval: 2)!),
    ("every week on Mon, Thu", RepeatRule(frequency: .week, weekdays: [mon, thu])!),
    ("every 2 weeks on Sun", RepeatRule(frequency: .week, interval: 2, weekdays: [sun])!),
    ("every month", RepeatRule(frequency: .month)!),
    ("every 6 months", RepeatRule(frequency: .month, interval: 6)!),
    ("every month on the 15th", RepeatRule(frequency: .month, monthDay: .day(15))!),
    ("every month on the 1st", RepeatRule(frequency: .month, monthDay: .day(1))!),
    ("every month on the 31st", RepeatRule(frequency: .month, monthDay: .day(31))!),
    ("every month on the last day", RepeatRule(frequency: .month, monthDay: .lastDay)!),
    ("every month on the 2nd Tue", RepeatRule(frequency: .month, monthDay: .nth(2, weekday: tue))!),
    ("every 3 months on the 5th Mon", RepeatRule(frequency: .month, interval: 3, monthDay: .nth(5, weekday: mon))!),
    ("every month on the last Fri", RepeatRule(frequency: .month, monthDay: .lastWeekday(fri))!),
    ("every year", RepeatRule(frequency: .year)!),
    ("every 2 years", RepeatRule(frequency: .year, interval: 2)!),
    ("every year on Oct 26", RepeatRule(frequency: .year, yearDate: .init(month: 10, day: 26))!),
    ("every year on Feb 29", RepeatRule(frequency: .year, yearDate: .init(month: 2, day: 29))!),
    ("every 2 years on Oct 26", RepeatRule(frequency: .year, interval: 2, yearDate: .init(month: 10, day: 26))!),
    ("every 999 days", RepeatRule(frequency: .day, interval: 999)!),
    ("every day until 2026-12-31", RepeatRule(frequency: .day, until: LocalDate("2026-12-31"))!),
    ("every week when done", RepeatRule(frequency: .week, whenDone: true)!),
    ("every week on Mon until 2027-01-01 when done",
     RepeatRule(frequency: .week, weekdays: [mon], until: LocalDate("2027-01-01"), whenDone: true)!),
])
func parsesAndWritesCanonicalForms(_ phrase: String, _ rule: RepeatRule) {
    #expect(RepeatRule.parse(phrase) == rule)
    #expect(rule.phrase == phrase)
}

@Test func suffixesReadInEitherOrder() {
    let rule = RepeatRule(frequency: .month, monthDay: .day(1), until: LocalDate("2027-01-01"), whenDone: true)!
    #expect(RepeatRule.parse("every month on the 1st when done until 2027-01-01") == rule)
    #expect(RepeatRule.parse("every month on the 1st until 2027-01-01 when done") == rule)
    #expect(RepeatRule.parse("every month on the 1st when done until 2027-01-01")?.phrase
            == "every month on the 1st until 2027-01-01 when done")
}

@Test func readsCaseDayNamesAndSpacing() {
    #expect(RepeatRule.parse("Every Week On Monday, THU")?.weekdays == [mon, thu])
    #expect(RepeatRule.parse("  every   week \t on  Mon,Thu  ")?.weekdays == [mon, thu])
    #expect(RepeatRule.parse("EVERY MONTH ON THE LAST FRIDAY")?.monthDay == .lastWeekday(fri))
    #expect(RepeatRule.parse("every month on the 2nd tuesday")?.monthDay == .nth(2, weekday: tue))
    #expect(RepeatRule.parse("every year on october 26")?.yearDate == .init(month: 10, day: 26))
    #expect(RepeatRule.parse("every 1 week")?.phrase == "every week")
    #expect(RepeatRule.parse("every 1 weekday")?.phrase == "every weekday")
    #expect(RepeatRule.parse("every week on Mon, Mon")?.weekdays == [mon])
    #expect(RepeatRule.parse("every month on the 15")?.monthDay == .day(15))
}

@Test func weekdaysWriteMondayFirst() {
    #expect(RepeatRule.parse("every week on sun, fri, mon")?.phrase == "every week on Mon, Fri, Sun")
}

@Test func ordinalsUseTheRightSuffix() {
    for (day, text) in [(1, "1st"), (2, "2nd"), (3, "3rd"), (4, "4th"), (11, "11th"), (12, "12th"), (13, "13th"),
                        (21, "21st"), (22, "22nd"), (23, "23rd"), (30, "30th")] {
        #expect(RepeatRule(frequency: .month, monthDay: .day(day))!.phrase == "every month on the \(text)")
    }
}

@Test func monthAndYearRulesReadWithoutADay() {
    #expect(RepeatRule.parse("every month")?.monthDay == nil)
    #expect(RepeatRule.parse("every year")?.yearDate == nil)
}

@Test func constructedRulesRoundTrip() {
    let rules = [
        RepeatRule(frequency: .week, interval: 999, weekdays: [1, 7], until: LocalDate("2030-01-01"), whenDone: true),
        RepeatRule(frequency: .month, monthDay: .nth(5, weekday: 7)),
        RepeatRule(frequency: .month, monthDay: .lastWeekday(1), whenDone: true),
        RepeatRule(frequency: .month, monthDay: .lastDay),
        RepeatRule(frequency: .year, yearDate: .init(month: 12, day: 31)),
    ]
    for rule in rules {
        #expect(rule != nil)
        if let rule { #expect(RepeatRule.parse(rule.phrase) == rule, "\(rule.phrase)") }
    }
}

@Test func outOfRangeValuesGiveNoRule() {
    #expect(RepeatRule(frequency: .day, interval: 0) == nil)
    #expect(RepeatRule(frequency: .day, interval: 1000) == nil)
    #expect(RepeatRule(frequency: .weekday, interval: 2) == nil)
    #expect(RepeatRule(frequency: .week, weekdays: [0]) == nil)
    #expect(RepeatRule(frequency: .week, weekdays: [8]) == nil)
    #expect(RepeatRule(frequency: .month, monthDay: .day(0)) == nil)
    #expect(RepeatRule(frequency: .month, monthDay: .day(32)) == nil)
    #expect(RepeatRule(frequency: .month, monthDay: .nth(0, weekday: 2)) == nil)
    #expect(RepeatRule(frequency: .month, monthDay: .nth(6, weekday: 2)) == nil)
    #expect(RepeatRule(frequency: .month, monthDay: .nth(1, weekday: 8)) == nil)
    #expect(RepeatRule(frequency: .month, monthDay: .lastWeekday(0)) == nil)
    #expect(RepeatRule(frequency: .year, yearDate: .init(month: 13, day: 1)) == nil)
    #expect(RepeatRule(frequency: .year, yearDate: .init(month: 0, day: 1)) == nil)
    #expect(RepeatRule(frequency: .year, yearDate: .init(month: 2, day: 30)) == nil)
    #expect(RepeatRule(frequency: .year, yearDate: .init(month: 4, day: 31)) == nil)
}

@Test func fieldsOutsideTheFrequencyAreDropped() {
    let rule = RepeatRule(frequency: .day, weekdays: [2], monthDay: .lastDay, yearDate: .init(month: 1, day: 1))
    #expect(rule == RepeatRule(frequency: .day))
    #expect(RepeatRule(frequency: .week, monthDay: .lastDay, yearDate: .init(month: 1, day: 1))?.monthDay == nil)
    #expect(RepeatRule(frequency: .month, weekdays: [2])?.weekdays == [])
}

@Test(arguments: [
    "", "   ", "Weekly · Fri", "every", "every 0 days", "every -1 days", "every 1000 days", "every week on Funday", "every week on",
    "every month on the 32nd", "every month on the 0th", "every month on the 6th Mon",
    "every month on 15th", "every month on the last", "every month on the 2nd Funday", "every year on Feb 30",
    "every year on Octember 5", "every year on Oct", "every day on Mon", "every weekday on Mon", "every 2 weekdays",
    "every fortnight", "each week", "every week until", "every week until tomorrow", "every week until 2026-02-30",
    "every week until 2026-10-01 until 2026-11-01", "every week when done when done", "every week when",
    "every week sometimes", "every week on Mon extra",
])
func invalidPhrasesAreNotRules(_ phrase: String) {
    #expect(RepeatRule.parse(phrase) == nil)
}

@Test(arguments: [
    "every week on Mon, Thu until 2027-01-01 when done", "every 2 months on the last Sun when done",
    "every year on Dec 25 until 2030-12-25", "every weekday when done", "every 10 days", "every month on the 13th",
])
func writingThenReadingKeepsTheRule(_ phrase: String) throws {
    let rule = try #require(RepeatRule.parse(phrase))
    #expect(RepeatRule.parse(rule.phrase) == rule)
    #expect(rule.phrase == phrase)
}
