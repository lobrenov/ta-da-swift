// Settings ▸ Notifications' Badges switch: while it's on, the app icon's badge counts Today's open tasks, those due or at
// their deadline today or earlier. Badge-only notifications set the count at the start of each later day it goes up,
// whether Ta Da is running or not.
import Foundation
import TaDaCore
import UserNotifications
#if os(iOS)
import UIKit
#endif

@MainActor @Observable
final class NotificationsStore {
    /// What Settings shows for the switch.
    enum Access: Equatable { case off, asking, on, denied }

    /// The Badges switch. On only while badges are allowed.
    private(set) var showsBadge: Bool {
        didSet {
            defaults.set(showsBadge, forKey: Keys.showsBadge)
            showBadge()
        }
    }
    /// Notifications or their badges are turned off for Ta Da in System Settings.
    private(set) var isDenied = false
    private var isAsking = false

    private let defaults: any SettingsStore
    private let setBadge: (Int) -> Void
    private let schedule: ([BadgePlan.Change]) -> Void
    @ObservationIgnored private var plan = BadgePlan(count: 0, changes: [])
    /// The badge last set; 0 at launch while the switch is off, so an off switch never asks the notification center.
    @ObservationIgnored private var shown: Int?
    /// The changes last scheduled; none at launch while the switch is off, for the same reason.
    @ObservationIgnored private var scheduled: [BadgePlan.Change]?

    private enum Keys {
        static let showsBadge = "notifications.showsBadge"
    }

    init(defaults: any SettingsStore,
         setBadge: @escaping (Int) -> Void = { UNUserNotificationCenter.current().setBadgeCount($0, withCompletionHandler: nil) },
         schedule: @escaping ([BadgePlan.Change]) -> Void = NotificationsStore.scheduleBadges) {
        self.defaults = defaults
        self.setBadge = setBadge
        self.schedule = schedule
        showsBadge = defaults.bool(forKey: Keys.showsBadge)
        shown = showsBadge ? nil : 0
        scheduled = showsBadge ? nil : []
    }

    var access: Access {
        if isAsking { return .asking }
        if isDenied { return .denied }
        return showsBadge ? .on : .off
    }

    /// Turns the switch on, first asking to show badges, or off. Denied, the switch stays off.
    func setOn(_ on: Bool) async {
        guard on else { return showsBadge = false }
        isAsking = true
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.badge])
        let allowed = await readAccess()
        isAsking = false
        showsBadge = allowed
    }

    /// Sets Today's open tasks and the later days the count goes up, shown and scheduled while the switch is on.
    func update(_ plan: BadgePlan) {
        self.plan = plan
        showBadge()
    }

    /// Reads access again when the app becomes active: the switch turns off when badges were turned off in System
    /// Settings, and can be turned on again once they're back.
    func refresh() async {
        guard showsBadge || isDenied else { return }
        if !(await readAccess()) { showsBadge = false }
    }

    /// Whether badges are allowed; sets `isDenied` when they were asked for and refused or turned off.
    private func readAccess() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let allowed = settings.badgeSetting == .enabled
        isDenied = !allowed && settings.authorizationStatus != .notDetermined
        return allowed
    }

    /// Where badges are turned on: Ta Da's page in System Settings ▸ Notifications, or its notification settings on iPhone.
    static var settingsURL: URL {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")!
        #else
        URL(string: UIApplication.openNotificationSettingsURLString)!
        #endif
    }

    private func showBadge() {
        let badge = showsBadge ? plan.count : 0
        if badge != shown {
            shown = badge
            setBadge(badge)
        }
        let changes = showsBadge ? plan.changes : []
        if changes != scheduled {
            scheduled = changes
            schedule(changes)
        }
    }

    /// Replaces the pending notifications with one per change, each setting the badge at the start of its day, with no
    /// alert or sound. Ta Da schedules no other notifications.
    nonisolated static func scheduleBadges(_ changes: [BadgePlan.Change]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for change in changes {
            let content = UNMutableNotificationContent()
            content.badge = NSNumber(value: change.count)
            let start = DateComponents(year: change.date.year, month: change.date.month, day: change.date.day, hour: 0, minute: 0)
            let trigger = UNCalendarNotificationTrigger(dateMatching: start, repeats: false)
            center.add(UNNotificationRequest(identifier: "badge.\(change.date)", content: content, trigger: trigger),
                       withCompletionHandler: nil)
        }
    }
}
