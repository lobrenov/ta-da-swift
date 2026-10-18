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

private func week(_ text: String) -> ISOWeek { LocalDate(text)!.isoWeek }

@Test(arguments: [
    ("2026-10-02", 2026, 40), ("2026-09-28", 2026, 40), ("2026-10-04", 2026, 40), ("2026-10-05", 2026, 41),
    ("2020-12-31", 2020, 53), ("2021-01-03", 2020, 53), ("2021-01-04", 2021, 1),
    ("2026-12-31", 2026, 53), ("2027-01-01", 2026, 53), ("2027-01-03", 2026, 53), ("2027-01-04", 2027, 1),
    ("2024-12-30", 2025, 1), ("2025-12-29", 2026, 1), ("2026-01-01", 2026, 1), ("2016-01-01", 2015, 53),
])
func isoWeekOfADate(_ text: String, _ year: Int, _ number: Int) {
    #expect((week(text).year, week(text).week) == (year, number))
}

@Test func isoWeekDaysRunMondayToSunday() throws {
    let days = ISOWeek(year: 2026, week: 53)!.days
    #expect(days.map(\.description) == ["2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02", "2027-01-03"])
    #expect(days.allSatisfy { $0.isoWeek == ISOWeek(year: 2026, week: 53) })
    #expect(days.map(\.weekday) == [2, 3, 4, 5, 6, 7, 1])
    #expect(ISOWeek(year: 2027, week: 1)!.firstDay.description == "2027-01-04")
    #expect(ISOWeek(year: 2020, week: 1)!.firstDay.description == "2019-12-30")
}

@Test func isoWeeksExistOnlyWhenTheYearHasThem() {
    #expect(ISOWeek(year: 2026, week: 53) != nil && ISOWeek(year: 2027, week: 53) == nil)
    #expect(ISOWeek(year: 2020, week: 53) != nil && ISOWeek(year: 2026, week: 0) == nil && ISOWeek(year: 2026, week: 54) == nil)
    #expect(ISOWeek(year: 2026, week: 40)!.description == "2026-W40")
}

@Test func addingWeeksCrossesYears() {
    #expect(ISOWeek(year: 2026, week: 52)!.adding(weeks: 1) == ISOWeek(year: 2026, week: 53))
    #expect(ISOWeek(year: 2026, week: 53)!.adding(weeks: 1) == ISOWeek(year: 2027, week: 1))
    #expect(ISOWeek(year: 2027, week: 1)!.adding(weeks: -2) == ISOWeek(year: 2026, week: 52))
    #expect(ISOWeek(year: 2026, week: 40)!.adding(weeks: 0) == ISOWeek(year: 2026, week: 40))
    #expect(ISOWeek(year: 2026, week: 53)! < ISOWeek(year: 2027, week: 1)!)
}

/// 2026-03-29 and 2026-10-25 are daylight-saving changes in Europe, 2026-03-08 and 2026-11-01 in the US.
@Test(arguments: ["2026-03-08", "2026-03-29", "2026-10-25", "2026-11-01"])
func isoWeekMathIgnoresDaylightSaving(_ text: String) {
    let date = LocalDate(text)!
    let week = date.isoWeek
    #expect(week.days.contains(date) && week.days.count == 7)
    #expect(week.days.map(\.weekday) == [2, 3, 4, 5, 6, 7, 1])
    #expect(week.adding(weeks: 1).firstDay == week.firstDay.adding(days: 7))
    #expect(week.adding(weeks: 1).adding(weeks: -1) == week)
}

@Test func monthsListTheirIsoWeeks() {
    #expect(LocalDate("2026-10-15")!.isoWeeksOfMonth.map(\.description) == ["2026-W40", "2026-W41", "2026-W42", "2026-W43", "2026-W44"])
    #expect(LocalDate("2026-12-01")!.isoWeeksOfMonth.map(\.description) == ["2026-W49", "2026-W50", "2026-W51", "2026-W52", "2026-W53"])
    #expect(LocalDate("2027-01-20")!.isoWeeksOfMonth.map(\.description) == ["2026-W53", "2027-W01", "2027-W02", "2027-W03", "2027-W04"])
    #expect(LocalDate("2026-02-10")!.isoWeeksOfMonth.map(\.description) == ["2026-W05", "2026-W06", "2026-W07", "2026-W08", "2026-W09"])
}
