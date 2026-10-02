// The 15 design tokens from the Themes artboard. Schemes are in BundledThemes.swift.
import SwiftUI
import AppKit

nonisolated struct Theme: Identifiable, Hashable, Sendable {
    let name: String
    let isDark: Bool
    let bg, side, surface, border, code, fg, strong, muted, accent, due, deadline, done, doing, blocked, link: NSColor

    var id: String { name }

    static func named(_ name: String) -> Theme {
        all.first { $0.name == name } ?? all[0]
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
    @Entry var theme: Theme = Theme.all[0]
}
