import Foundation
import Testing
@testable import TaDaCore

private let tuesday = LocalDate("2026-10-13")!

private var mondayFirst: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    return calendar
}

private func parse(_ text: String, today: LocalDate = tuesday, order: DayOrder = .dayMonth) -> String? {
    DatePhrase.parse(text, today: today, order: order, calendar: mondayFirst)?.description
}

@Test(arguments: [
    ("today", "2026-10-13"), ("tod", "2026-10-13"), ("t", "2026-10-13"), ("to", "2026-10-13"), ("  TODAY ", "2026-10-13"),
    ("tomorrow", "2026-10-14"), ("tmr", "2026-10-14"), ("tom", "2026-10-14"),
    ("fri", "2026-10-16"), ("friday", "2026-10-16"), ("f", "2026-10-16"), ("next fri", "2026-10-16"), ("next fr", "2026-10-16"),
    ("this friday", "2026-10-16"), ("on fri", "2026-10-16"), ("fri 3pm", "2026-10-16"), ("friday at 15:00", "2026-10-16"),
    ("fri 3 pm", "2026-10-16"),
    ("tue", "2026-10-13"), ("tu", "2026-10-13"), ("th", "2026-10-15"), ("w", "2026-10-14"), ("we", "2026-10-14"),
    ("s", "2026-10-17"), ("sa", "2026-10-17"), ("su", "2026-10-18"), ("m", "2026-10-19"), ("mon", "2026-10-19"),
    ("next mon", "2026-10-19"), ("on t", "2026-10-13"),
    ("weekend", "2026-10-17"), ("wee", "2026-10-17"), ("this weekend", "2026-10-17"),
    ("next week", "2026-10-19"), ("n", "2026-10-19"), ("next", "2026-10-19"), ("next w", "2026-10-19"),
    ("next month", "2026-11-01"), ("next m", "2026-11-01"),
    ("end of month", "2026-10-31"), ("eom", "2026-10-31"), ("e", "2026-10-31"),
])
func datePhraseWords(_ text: String, _ expected: String) {
    #expect(parse(text) == expected)
}

@Test(arguments: [
    ("3d", "2026-10-16"), ("3 days", "2026-10-16"), ("in 3 days", "2026-10-16"), ("+3", "2026-10-16"), ("in 3", "2026-10-16"),
    ("2w", "2026-10-27"), ("in 2 weeks", "2026-10-27"), ("2 wks", "2026-10-27"),
    ("1m", "2026-11-13"), ("in 1 month", "2026-11-13"), ("1y", "2027-10-13"), ("1 yr", "2027-10-13"),
    ("25", "2026-10-25"), ("25th", "2026-10-25"), ("the 25th", "2026-10-25"), ("13", "2026-10-13"), ("12", "2026-11-12"),
    ("1st", "2026-11-01"), ("31", "2026-10-31"),
])
func datePhraseNumbers(_ text: String, _ expected: String) {
    #expect(parse(text) == expected)
}

@Test(arguments: [
    ("25/12", "2026-12-25"), ("25.12", "2026-12-25"), ("25-12", "2026-12-25"), ("25/12/", "2026-12-25"),
    ("dec 25", "2026-12-25"), ("25 dec", "2026-12-25"), ("december 25th", "2026-12-25"), ("25th of december", "2026-12-25"),
    ("Dec 25, 2026", "2026-12-25"), ("25 de", "2026-12-25"), ("dec. 25", "2026-12-25"), ("25dec", "2026-12-25"),
    ("25/12/27", "2027-12-25"), ("25/12/2027", "2027-12-25"), ("25 dec 2027", "2027-12-25"), ("2027-12-25", "2027-12-25"),
    ("1/1", "2027-01-01"), ("13/10", "2026-10-13"), ("12/10", "2027-10-12"), ("29/2", "2028-02-29"), ("sept 3", "2027-09-03"),
    ("1/1/2020", "2020-01-01"),
])
func datePhraseDates(_ text: String, _ expected: String) {
    #expect(parse(text) == expected)
}

@Test(arguments: ["", "  ", "xyz", "31/2", "0", "32", "3pm", "ma", "25 ju", "this", "13/13", "2027-12", "1/1/123", "9999y", "2027-12-251"])
func datePhraseRejects(_ text: String) {
    #expect(parse(text) == nil)
}

@Test func datePhraseNumericOrderFollowsTheSetting() {
    #expect(parse("12/25", order: .monthDay) == "2026-12-25")
    #expect(parse("5/12", order: .monthDay) == "2027-05-12")
    #expect(parse("5/12", order: .dayMonth) == "2026-12-05")
    #expect(parse("12/25", order: .dayMonth) == nil)
}

@Test func datePhraseOnAFridayGivesToday() {
    let friday = LocalDate("2026-10-16")!
    #expect(parse("fri", today: friday) == "2026-10-16")
    #expect(parse("next fri", today: friday) == "2026-10-16")
    #expect(parse("sat", today: friday) == "2026-10-17")
}

@Test func datePhraseMonthEndsAndYears() {
    #expect(parse("1m", today: LocalDate("2026-01-31")!) == "2026-02-28")
    #expect(parse("1m", today: LocalDate("2028-01-31")!) == "2028-02-29")
    #expect(parse("1y", today: LocalDate("2028-02-29")!) == "2029-02-28")
    #expect(parse("31", today: LocalDate("2026-04-30")!) == "2026-05-31")
    #expect(parse("dec 25", today: LocalDate("2026-12-26")!) == "2027-12-25")
    #expect(parse("jan 3", today: LocalDate("2026-12-31")!) == "2027-01-03")
    #expect(parse("tomorrow", today: LocalDate("2026-12-31")!) == "2027-01-01")
    #expect(parse("eom", today: LocalDate("2028-02-10")!) == "2028-02-29")
}
