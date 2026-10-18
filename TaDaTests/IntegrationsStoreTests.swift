import CoreGraphics
import EventKit
import Foundation
import Testing
import TaDaCore
@testable import TaDa

/// Settings ▸ Integrations' stored choices and the fetch window. EventKit isn't asked for access.
@MainActor
struct IntegrationsStoreTests {
    @Test func switchesStartOffAndShowNothing() {
        let store = IntegrationsStore(defaults: TestSettings())
        for kind in IntegrationsStore.Kind.allCases {
            #expect(!store.isOn(kind) && !store.isShown(kind))
        }
        #expect(store.todayEvents.isEmpty && store.todayReminders.isEmpty)
    }

    @Test func untickedCalendarsAndListsAreKeptPerDevice() {
        let settings = TestSettings()
        let store = IntegrationsStore(defaults: settings)
        store.setHidden(true, "work", .events)
        store.setHidden(true, "groceries", .reminders)
        store.setHidden(true, "home", .events)
        store.setHidden(false, "home", .events)

        let reopened = IntegrationsStore(defaults: settings)
        #expect(reopened.isHidden("work", .events) && !reopened.isHidden("home", .events))
        #expect(reopened.isHidden("groceries", .reminders) && !reopened.isHidden("work", .reminders))
        #expect(!reopened.isHidden("added later", .events))
    }

    @Test func turningOffNeedsNoAccess() async {
        let store = IntegrationsStore(defaults: TestSettings())
        await store.setOn(false, .events)
        #expect(!store.isOn(.events) && store.access(.events) != .granted)
    }

    @Test func fetchWindowReachesTheEndOfNextMonth() {
        #expect(AppModel.endOfNextMonth(after: LocalDate("2026-10-13")!) == LocalDate("2026-11-30"))
        #expect(AppModel.endOfNextMonth(after: LocalDate("2026-11-30")!) == LocalDate("2026-12-31"))
        #expect(AppModel.endOfNextMonth(after: LocalDate("2026-12-01")!) == LocalDate("2027-01-31"))
        #expect(AppModel.endOfNextMonth(after: LocalDate("2028-01-31")!) == LocalDate("2028-02-29"))
    }

    @Test func dayOnlyDueDatesKeepTheirDayInAnyTimeZone() {
        let utc = TimeZone(identifier: "UTC")!
        let dayOnly = DateComponents(timeZone: utc, year: 2026, month: 10, day: 14)
        #expect(IntegrationsStore.dueDay(dayOnly) == LocalDate("2026-10-14"))
        #expect(IntegrationsStore.dueDay(DateComponents(year: 2026, month: 10)) == nil)
        // A timed one is the day its moment falls on in the device's time zone.
        let timed = DateComponents(timeZone: utc, year: 2026, month: 10, day: 14, hour: 23, minute: 30)
        let moment = Calendar(identifier: .gregorian).date(from: timed)!
        #expect(IntegrationsStore.dueDay(timed) == LocalDate(moment))
    }

    @Test func windowReachesUpcomingsLastDateButNoMoreThanAYear() {
        let today = LocalDate("2026-10-13")!
        #expect(AppModel.integrationsWindowEnd(today: today, upcomingLast: nil) == LocalDate("2026-11-30"))
        #expect(AppModel.integrationsWindowEnd(today: today, upcomingLast: LocalDate("2026-10-20")) == LocalDate("2026-11-30"))
        #expect(AppModel.integrationsWindowEnd(today: today, upcomingLast: LocalDate("2027-02-01")) == LocalDate("2027-02-01"))
        #expect(AppModel.integrationsWindowEnd(today: today, upcomingLast: LocalDate("2029-01-01")) == LocalDate("2027-10-13"))
    }

    @Test func accessFollowsTheStatusTheSwitchAndAsking() {
        typealias Store = IntegrationsStore
        #expect(Store.access(status: .notDetermined, isOn: false, isAsking: false) == .off)
        #expect(Store.access(status: .notDetermined, isOn: true, isAsking: true) == .asking)
        #expect(Store.access(status: .fullAccess, isOn: true, isAsking: false) == .granted)
        #expect(Store.access(status: .fullAccess, isOn: false, isAsking: false) == .off)
        for status in [EKAuthorizationStatus.denied, .restricted, .writeOnly] {
            #expect(Store.access(status: status, isOn: true, isAsking: false) == .denied)
        }
    }

    @Test func oneFetchFillsTodayUpcomingAndTheDots() {
        let model = AppModel(defaults: TestSettings())
        let today = model.today
        func at(_ day: LocalDate, _ hour: Int) -> Date { Calendar.current.date(byAdding: .hour, value: hour, to: day.date())! }
        let events = [
            ExternalEvent(identifier: "a", title: "Standup", start: at(today, 9), end: at(today, 10), isAllDay: false, color: "#FF9500"),
            ExternalEvent(identifier: "b", title: "Trip", start: at(today.adding(days: 2), 0), end: at(today.adding(days: 4), 0),
                          isAllDay: true, color: "#1BADF8"),
        ]
        let reminders = [
            ExternalReminder(identifier: "r1", title: "Overdue", due: today.adding(days: -2), color: "#FF453A"),
            ExternalReminder(identifier: "r2", title: "Soon", due: today.adding(days: 3), color: "#0A84FF"),
            ExternalReminder(identifier: "r3", title: "Later", due: today.adding(days: 20), color: "#0A84FF"),
        ]
        model.integrations.apply(events: events, reminders: reminders, window: (today, today, today.adding(days: 40)))

        #expect(model.todayEvents.map(\.event.title) == ["Standup"])
        #expect(model.todayReminders.map(\.title) == ["Overdue"])
        #expect(model.upcomingEvents[today.adding(days: 3)]?.first?.placement == .allDay(day: 2, of: 2))
        #expect(model.upcomingReminders[today.adding(days: 3)]?.map(\.title) == ["Soon"])
        #expect(model.hasEvents(on: today) && model.hasEvents(on: today.adding(days: 2)))
        #expect(!model.hasEvents(on: today.adding(days: 1)) && !model.hasEvents(on: today.adding(days: 4)))
    }

    @Test func pastDaysKeepTheirEventsAndOverdueReminders() {
        let model = AppModel(defaults: TestSettings())
        let today = model.today
        func at(_ day: LocalDate, _ hour: Int) -> Date { Calendar.current.date(byAdding: .hour, value: hour, to: day.date())! }
        let events = [ExternalEvent(identifier: "a", title: "Dentist", start: at(today.adding(days: -3), 9), end: at(today.adding(days: -3), 10),
                                    isAllDay: false, color: "#FF9500")]
        let reminders = [ExternalReminder(identifier: "r1", title: "Overdue", due: today.adding(days: -2), color: "#FF453A"),
                         ExternalReminder(identifier: "r2", title: "Too early", due: today.adding(days: -9), color: "#FF453A")]
        model.integrations.apply(events: events, reminders: reminders, window: (today, today.adding(days: -5), today.adding(days: 40)))

        #expect(model.events(on: today.adding(days: -3)).map(\.event.title) == ["Dentist"])
        #expect(model.hasEvents(on: today.adding(days: -3)) && !model.hasEvents(on: today.adding(days: -2)))
        #expect(model.reminders(on: today.adding(days: -2)).map(\.title) == ["Overdue"])
        #expect(model.reminders(on: today.adding(days: -9)).isEmpty, "before the window")
    }

    @Test func theWindowStartsAtTheMonthShownAndStaysWhileItCoversTheSelection() async throws {
        let folder = try TestFolder()
        let model = await folder.model(today: LocalDate("2026-10-18")!)
        let window = { model.integrations.window }
        model.agendaSelection = .day(LocalDate("2026-07-15")!)
        model.agendaMonthOpen = true
        #expect(model.agendaRange == LocalDate("2026-06-29")!...LocalDate("2026-08-02")!)
        #expect(window()?.today == LocalDate("2026-10-18") && window()?.first == LocalDate("2026-06-29"))
        #expect(window()?.last == LocalDate("2026-11-30"))

        model.agendaSelection = .week(LocalDate("2026-07-01")!.isoWeek)
        #expect(window()?.first == LocalDate("2026-06-29"), "still covered")
        model.agendaSelection = .day(LocalDate("2026-05-10")!)
        #expect(window()?.first == LocalDate("2026-04-27"), "left the covered range")
        model.agendaSelection = .day(LocalDate("2026-10-18")!)
        model.agendaMonthOpen = false
        #expect(window()?.first == LocalDate("2026-04-27"), "later days stay covered")
    }

    @Test func coloursBecomeSRGBHex() {
        #expect(IntegrationsStore.hex(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)) == "#FF8000")
        #expect(IntegrationsStore.hex(nil) == "#8E8E93")
    }
}
