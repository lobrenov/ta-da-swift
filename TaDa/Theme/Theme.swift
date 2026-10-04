// The 15 design tokens from the Theme tokens artboard, theme sets (a light and a dark scheme) and the
// appearance setting. Schemes and sets are in BundledThemes.swift.
import SwiftUI
import AppKit

nonisolated struct Theme: Identifiable, Hashable, Sendable {
    let name: String
    let isDark: Bool
    let bg, side, surface, border, code, fg, strong, muted, accent, due, deadline, done, doing, blocked, link: NSColor

    var id: String { name }

    static func named(_ name: String) -> Theme? {
        all.first { $0.name == name }
    }
}

/// A light and a dark scheme; Ta Da shows one or the other with the appearance.
nonisolated struct ThemeSet: Identifiable, Hashable, Sendable {
    let name: String
    let light: Theme
    let dark: Theme

    var id: String { name }

    init(name: String, light: String, dark: String) {
        self.name = name
        self.light = Theme.named(light)!
        self.dark = Theme.named(dark)!
    }

    static func named(_ name: String) -> ThemeSet? {
        all.first { $0.name == name }
    }
}

/// Which scheme of the pair to show: the Mac's appearance, or always light or dark.
enum Appearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"

    var id: Self { self }

    /// The Mac's own appearance, read from the global defaults so the app's override doesn't hide it.
    static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}

nonisolated extension Theme {
    init(name: String, isDark: Bool,
         bg: UInt32, side: UInt32, surface: UInt32, border: UInt32, code: UInt32,
         fg: UInt32, strong: UInt32, muted: UInt32, accent: UInt32, due: UInt32,
         deadline: UInt32, done: UInt32, doing: UInt32, blocked: UInt32, link: UInt32) {
        func c(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                    green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        self.init(name: name, isDark: isDark,
                  bg: c(bg), side: c(side), surface: c(surface), border: c(border), code: c(code),
                  fg: c(fg), strong: c(strong), muted: c(muted), accent: c(accent), due: c(due),
                  deadline: c(deadline), done: c(done), doing: c(doing), blocked: c(blocked), link: c(link))
    }

    func color(_ keyPath: KeyPath<Theme, NSColor>) -> Color {
        Color(nsColor: self[keyPath: keyPath])
    }
}

extension EnvironmentValues {
    /// The active theme. Every themed view reads its colours from here.
    @Entry var theme: Theme = ThemeSet.standard.dark
}
