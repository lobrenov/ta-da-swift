import Foundation
import Testing
@testable import TaDaCore

@Test func localDateParsesAndPrintsYYYYMMDD() throws {
    let date = try #require(LocalDate("2026-10-02"))
    #expect((date.year, date.month, date.day) == (2026, 10, 2))
    #expect(date.description == "2026-10-02")
}

@Test(arguments: [
    "", "2026-10-2", "2026/10/02", "2026-10-02T09:00", " 2026-10-02", "26-10-02",
    "2026-13-01", "2026-00-10", "2026-04-31", "2026-02-29", "1900-02-29", "0000-01-01", "２０２６-10-02",
])
func localDateRejects(_ text: String) {
    #expect(LocalDate(text) == nil)
}

@Test func localDateAcceptsLeapDays() {
    #expect(LocalDate("2028-02-29") != nil)
    #expect(LocalDate("2000-02-29") != nil)
}

@Test func localDatesOrderByDay() throws {
    let dates = ["2026-10-02", "2025-12-31", "2026-09-30", "2026-10-01"].compactMap(LocalDate.init)
    #expect(dates.sorted().map(\.description) == ["2025-12-31", "2026-09-30", "2026-10-01", "2026-10-02"])
}

@Test func localDateArithmetic() throws {
    let date = try #require(LocalDate("2026-10-30"))
    #expect(date.adding(days: 3).description == "2026-11-02")
    #expect(date.adding(days: -30).description == "2026-09-30")
    #expect(LocalDate("2028-02-28")!.adding(days: 1).description == "2028-02-29")
    #expect(LocalDate("2026-12-31")!.adding(days: 1).description == "2027-01-01")
    #expect(date.days(to: LocalDate("2026-11-02")!) == 3)
    #expect(date.days(to: LocalDate("2026-10-02")!) == -28)
    #expect(LocalDate("2026-10-02")!.weekday == 6) // Friday
}

@Test func localDateFromDateUsesTheCalendarsTimeZone() throws {
    // 2026-10-02 23:30 in Melbourne is 13:30 UTC the same day; 00:30 on the 3rd is still the 2nd in UTC.
    var melbourne = Calendar(identifier: .gregorian)
    melbourne.timeZone = try #require(TimeZone(identifier: "Australia/Melbourne"))
    let lateNight = try #require(melbourne.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 0, minute: 30)))
    #expect(LocalDate(lateNight, calendar: melbourne).description == "2026-10-03")
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try #require(TimeZone(identifier: "UTC"))
    #expect(LocalDate(lateNight, calendar: utc).description == "2026-10-02")
    // Across a daylight-saving change (Melbourne, 4 Oct 2026).
    #expect(LocalDate("2026-10-03")!.adding(days: 2).description == "2026-10-05")
    #expect(LocalDate(LocalDate("2026-10-04")!.date(in: melbourne), calendar: melbourne).description == "2026-10-04")
}

@Test func localDateMonths() {
    #expect(LocalDate("2026-10-14")!.startOfMonth.description == "2026-10-01")
    #expect(LocalDate("2026-10-14")!.addingMonths(3).description == "2027-01-01")
    #expect(LocalDate("2026-01-31")!.addingMonths(-1).description == "2025-12-01")
}

@Test func addingMonthsKeepsTheDayOrTheMonthsLast() {
    #expect(LocalDate("2026-01-31")!.adding(months: 1)?.description == "2026-02-28")
    #expect(LocalDate("2028-01-31")!.adding(months: 1)?.description == "2028-02-29")
    #expect(LocalDate("2026-03-31")!.adding(months: -1)?.description == "2026-02-28")
    #expect(LocalDate("2026-10-13")!.adding(months: 14)?.description == "2027-12-13")
    #expect(LocalDate("2026-10-13")!.adding(months: 12 * 8000) == nil)
}

@Test func thisWeekendIsTheComingSaturdayOrToday() {
    #expect(LocalDate("2026-10-02")!.thisWeekend == LocalDate("2026-10-03")!)
    #expect(LocalDate("2026-10-03")!.thisWeekend == LocalDate("2026-10-03")!)
    #expect(LocalDate("2026-10-04")!.thisWeekend == LocalDate("2026-10-04")!)
    #expect(LocalDate("2026-10-05")!.thisWeekend == LocalDate("2026-10-10")!)
}

@Test func nextWeekIsTheFirstDayOfTheFollowingWeek() {
    #expect(LocalDate("2026-10-02")!.nextWeek(firstWeekday: 2) == LocalDate("2026-10-05")!)
    #expect(LocalDate("2026-10-05")!.nextWeek(firstWeekday: 2) == LocalDate("2026-10-12")!)
    #expect(LocalDate("2026-10-04")!.nextWeek(firstWeekday: 2) == LocalDate("2026-10-05")!)
    #expect(LocalDate("2026-10-02")!.nextWeek(firstWeekday: 1) == LocalDate("2026-10-04")!)
}
