import Foundation
import Testing
@testable import TaDaCore

private let melbourne: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Australia/Melbourne")!
    return calendar
}()

private func at(_ day: String, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0, in calendar: Calendar = melbourne) -> Date {
    let d = LocalDate(day)!
    return calendar.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: hour, minute: minute, second: second))!
}

private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> ExternalEvent {
    ExternalEvent(identifier: title, title: title, start: start, end: end, isAllDay: allDay, color: "#3366CC")
}

private func day(_ text: String) -> LocalDate { LocalDate(text)! }

@Test func singleDayEventShowsItsStartOnItsDayOnly() {
    let e = event("Event", at("2026-10-14", 9), at("2026-10-14", 10))
    #expect(e.placement(on: day("2026-10-14"), calendar: melbourne) == .time(e.start))
    #expect(e.placement(on: day("2026-10-13"), calendar: melbourne) == nil)
    #expect(e.placement(on: day("2026-10-15"), calendar: melbourne) == nil)
}

@Test func timedMultiDayEventStartsThenAllDayThenUntil() {
    let e = event("Event", at("2026-10-12", 20), at("2026-10-14", 10, 30))
    #expect(e.placement(on: day("2026-10-12"), calendar: melbourne) == .time(e.start))
    #expect(e.placement(on: day("2026-10-13"), calendar: melbourne) == .allDay(day: 2, of: 3))
    #expect(e.placement(on: day("2026-10-14"), calendar: melbourne) == .until(e.end))
    #expect(DayEvent(event: e, placement: .allDay(day: 2, of: 3)).dayOfSpan == nil)
}

@Test(arguments: [false, true])
func allDayMultiDayEventIsAllDayOnEachDay(eventKitStyleEnd: Bool) throws {
    // EventKit may end an all-day event at the next midnight or at 23:59:59 on its last day.
    let end = eventKitStyleEnd ? at("2026-10-14", 23, 59, 59) : at("2026-10-15")
    let e = event("Event", at("2026-10-12"), end, allDay: true)
    #expect(e.days(in: melbourne) == day("2026-10-12")...day("2026-10-14"))
    for (index, text) in ["2026-10-12", "2026-10-13", "2026-10-14"].enumerated() {
        let placement = try #require(e.placement(on: day(text), calendar: melbourne))
        #expect(placement == .allDay(day: index + 1, of: 3))
        #expect(DayEvent(event: e, placement: placement).dayOfSpan! == (index + 1, 3))
    }
    #expect(e.placement(on: day("2026-10-15"), calendar: melbourne) == nil)
}

@Test func singleAllDayEventHasNoDayOfSpan() {
    let e = event("Event", at("2026-10-14"), at("2026-10-15"), allDay: true)
    #expect(e.placement(on: day("2026-10-14"), calendar: melbourne) == .allDay(day: 1, of: 1))
    #expect(DayEvent(event: e, placement: .allDay(day: 1, of: 1)).dayOfSpan == nil)
}

@Test func eventCrossingMidnightRunsUntilItsEndNextDay() {
    let e = event("Event", at("2026-10-14", 22), at("2026-10-15", 2))
    #expect(e.placement(on: day("2026-10-14"), calendar: melbourne) == .time(e.start))
    #expect(e.placement(on: day("2026-10-15"), calendar: melbourne) == .until(e.end))
}

@Test func eventEndingExactlyAtMidnightDoesNotCoverTheNextDay() {
    let evening = event("Event", at("2026-10-14", 22), at("2026-10-15"))
    #expect(evening.days(in: melbourne) == day("2026-10-14")...day("2026-10-14"))
    #expect(evening.placement(on: day("2026-10-15"), calendar: melbourne) == nil)

    let twoDays = event("Event", at("2026-10-14", 10), at("2026-10-16"))
    #expect(twoDays.placement(on: day("2026-10-15"), calendar: melbourne) == .allDay(day: 2, of: 2))
    #expect(twoDays.placement(on: day("2026-10-16"), calendar: melbourne) == nil)
}

@Test func zeroLengthEventAtMidnightCoversItsDay() {
    let e = event("Event", at("2026-10-14"), at("2026-10-14"))
    #expect(e.placement(on: day("2026-10-14"), calendar: melbourne) == .time(e.start))
}

@Test func daysFollowTheCalendarsTimeZone() {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    // 08:00 on the 14th in Melbourne is 21:00 on the 13th in UTC.
    let e = event("Event", at("2026-10-14", 8), at("2026-10-14", 9))
    #expect(e.placement(on: day("2026-10-14"), calendar: melbourne) == .time(e.start))
    #expect(e.placement(on: day("2026-10-13"), calendar: utc) == .time(e.start))
    #expect(e.placement(on: day("2026-10-14"), calendar: utc) == nil)
}

@Test func daylightSavingDaysAreStillOneDay() {
    // Melbourne's clocks go forward on 4 Oct 2026 (a 23-hour day) and back on 5 Apr 2026 (a 25-hour day).
    let short = event("Event", at("2026-10-04"), at("2026-10-05"), allDay: true)
    #expect(short.days(in: melbourne) == day("2026-10-04")...day("2026-10-04"))
    let long = event("Event", at("2026-04-05"), at("2026-04-06"), allDay: true)
    #expect(long.days(in: melbourne) == day("2026-04-05")...day("2026-04-05"))
    let across = event("Event", at("2026-10-03", 18), at("2026-10-05", 9))
    #expect(across.placement(on: day("2026-10-04"), calendar: melbourne) == .allDay(day: 2, of: 3))
    #expect(across.placement(on: day("2026-10-05"), calendar: melbourne) == .until(across.end))
}

@Test func eventHasEndedOnceItsEndPasses() {
    let e = event("Event", at("2026-10-14", 9), at("2026-10-14", 10))
    #expect(!e.hasEnded(now: at("2026-10-14", 9, 30)))
    #expect(e.hasEnded(now: at("2026-10-14", 10)))
    #expect(e.hasEnded(now: at("2026-10-14", 11)))
}

@Test func dayEventsSortAllDayFirstThenStartThenTitle() {
    let events = [
        event("Lunch", at("2026-10-14", 12), at("2026-10-14", 13)),
        event("Breakfast", at("2026-10-14", 8), at("2026-10-14", 9)),
        event("Conference", at("2026-10-13"), at("2026-10-16"), allDay: true),
        event("Brunch", at("2026-10-14", 8), at("2026-10-14", 9)),
        event("Overnight", at("2026-10-13", 22), at("2026-10-14", 7)),
        event("Holiday", at("2026-10-14"), at("2026-10-15"), allDay: true),
        event("Tomorrow", at("2026-10-15", 9), at("2026-10-15", 10)),
    ]
    #expect(DayEvent.on(day("2026-10-14"), from: events, calendar: melbourne).map(\.event.title)
        == ["Conference", "Holiday", "Overnight", "Breakfast", "Brunch", "Lunch"])
}

@Test func eventsByDayAreClippedToTheRange() {
    let events = [
        event("Trip", at("2026-10-12"), at("2026-10-20"), allDay: true),
        event("Call", at("2026-10-16", 9), at("2026-10-16", 10)),
        event("Later", at("2026-11-02", 9), at("2026-11-02", 10)),
    ]
    let byDay = DayEvent.byDay(events, from: day("2026-10-15"), through: day("2026-10-17"), calendar: melbourne)
    #expect(byDay.keys.sorted() == [day("2026-10-15"), day("2026-10-16"), day("2026-10-17")])
    #expect(byDay[day("2026-10-16")]?.map(\.event.title) == ["Trip", "Call"])
    #expect(byDay[day("2026-10-15")]?.first?.placement == .allDay(day: 4, of: 8))
}

@Test func endBeforeStartIsTreatedAsZeroLength() {
    let e = event("Event", at("2026-10-14", 9), at("2026-10-14", 8))
    #expect(e.end == e.start)
}
