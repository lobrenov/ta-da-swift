import CoreGraphics
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

    @Test func coloursBecomeSRGBHex() {
        #expect(IntegrationsStore.hex(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)) == "#FF8000")
        #expect(IntegrationsStore.hex(nil) == "#8E8E93")
    }
}
