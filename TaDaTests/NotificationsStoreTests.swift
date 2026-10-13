import Foundation
import Testing
@testable import TaDa

/// Settings ▸ Notifications' Badges switch and the badge it sets. The notification center isn't asked for access.
@MainActor
struct NotificationsStoreTests {
    @Test func offSetsNoBadge() {
        var badges: [Int] = []
        let store = NotificationsStore(defaults: TestSettings()) { badges.append($0) }
        store.update(count: 3)
        #expect(store.access == .off && badges.isEmpty)
    }

    @Test func onShowsTheCountAndOffClearsIt() async {
        let settings = TestSettings()
        settings.set(true, forKey: "notifications.showsBadge")
        var badges: [Int] = []
        let store = NotificationsStore(defaults: settings) { badges.append($0) }
        store.update(count: 3)
        store.update(count: 3)
        store.update(count: 2)
        await store.setOn(false)
        #expect(badges == [3, 2, 0])
        #expect(!NotificationsStore(defaults: settings).showsBadge)
    }
}
