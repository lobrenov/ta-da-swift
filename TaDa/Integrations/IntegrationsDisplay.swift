// What Settings ▸ Integrations says for each switch, calendar colours as SwiftUI colours, and the system settings link.
import SwiftUI

extension IntegrationsStore.Kind {
    /// "Calendars", "Reminders".
    var name: String { self == .events ? "Calendars" : "Reminders" }
    var noun: String { self == .events ? "calendars" : "reminders" }
    var toggleLabel: String { self == .events ? "Show events" : "Show reminders" }
    var macHint: String {
        self == .events ? "Calendar events in Today and Upcoming"
            : "Reminders with a due date: due or overdue in Today, by date in Upcoming"
    }
    var phoneHint: String { self == .events ? "In Today and Upcoming" : "Those with a due date" }

    /// Where access is turned on: System Settings' Privacy & Security pane on the Mac, Ta Da's settings on iPhone.
    var privacySettingsURL: URL {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(self == .events ? "Calendars" : "Reminders")")!
        #else
        URL(string: UIApplication.openSettingsURLString)!
        #endif
    }
}

extension IntegrationsStore {
    func sources(_ kind: Kind) -> [Source] {
        kind == .events ? calendarSources : listSources
    }
}

extension IntegrationsStore.Access {
    /// The line beside a section's name; nil when off.
    var status: String? {
        switch self {
        case .off: nil
        case .asking: "Asking…"
        case .granted: "Full access"
        case .denied: "No access"
        }
    }

    var statusDot: KeyPath<Theme, PlatformColor> {
        switch self {
        case .granted: \.done
        case .denied: \.deadline
        case .off, .asking: \.muted
        }
    }
}

extension Color {
    /// A calendar's or list's `#RRGGBB` colour.
    init(calendarHex hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x8E8E93
        self.init(.sRGB, red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
    }
}
