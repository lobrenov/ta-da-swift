// Settings ▸ Notifications' Badges switch: while it's on, the app icon's badge counts Today's open tasks, those due or at
// their deadline today or earlier.
import Foundation
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
    @ObservationIgnored private var count = 0
    /// The badge last set; 0 at launch while the switch is off, so an off switch never asks the notification center.
    @ObservationIgnored private var shown: Int?

    private enum Keys {
        static let showsBadge = "notifications.showsBadge"
    }

    init(defaults: any SettingsStore,
         setBadge: @escaping (Int) -> Void = { UNUserNotificationCenter.current().setBadgeCount($0, withCompletionHandler: nil) }) {
        self.defaults = defaults
        self.setBadge = setBadge
        showsBadge = defaults.bool(forKey: Keys.showsBadge)
        shown = showsBadge ? nil : 0
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

    /// Sets the number of Today's open tasks, shown while the switch is on.
    func update(count: Int) {
        self.count = count
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
        let badge = showsBadge ? count : 0
        guard badge != shown else { return }
        shown = badge
        setBadge(badge)
    }
}
