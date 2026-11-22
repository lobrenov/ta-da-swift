import Foundation
import TaDaCore
import Testing
@testable import TaDa

/// Settings ▸ Notifications' Badges switch and the badge it sets. The notification center isn't asked for access.
@MainActor
struct NotificationsStoreTests {
    @Test func offSetsNoBadge() {
        var badges: [Int] = []
        var schedules: [[BadgePlan.Change]] = []
        let store = NotificationsStore(defaults: TestSettings(), setBadge: { badges.append($0) }, schedule: { schedules.append($0) })
        store.update(plan(3, later: [5]))
        #expect(store.access == .off && badges.isEmpty && schedules.isEmpty)
    }

    @Test func onShowsTheCountAndOffClearsIt() async {
        let settings = TestSettings()
        settings.set(true, forKey: "notifications.showsBadge")
        var badges: [Int] = []
        let store = NotificationsStore(defaults: settings, setBadge: { badges.append($0) }, schedule: { _ in })
        store.update(plan(3))
        store.update(plan(3))
        store.update(plan(2))
        await store.setOn(false)
        #expect(badges == [3, 2, 0])
        #expect(!NotificationsStore(defaults: settings).showsBadge)
    }

    @Test func onSchedulesTheLaterChangesOnceAndOffCancelsThem() async {
        let settings = TestSettings()
        settings.set(true, forKey: "notifications.showsBadge")
        var schedules: [[Int]] = []
        let store = NotificationsStore(defaults: settings, setBadge: { _ in }, schedule: { schedules.append($0.map(\.count)) })
        store.update(plan(3, later: [4, 6]))
        store.update(plan(3, later: [4, 6]))
        store.update(plan(2, later: [4, 6]))
        store.update(plan(2, later: [3]))
        await store.setOn(false)
        #expect(schedules == [[4, 6], [3], []])
    }

    private func plan(_ count: Int, later: [Int] = []) -> BadgePlan {
        let start = LocalDate("2026-10-02")!
        return BadgePlan(count: count, changes: later.enumerated().map { BadgePlan.Change(date: start.adding(days: $0.offset + 1), count: $0.element) })
    }
}
