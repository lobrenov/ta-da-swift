// The 15 design tokens from the Theme tokens artboard, theme sets (a light and a dark scheme) and the
// appearance setting. Schemes and sets are in BundledThemes.swift.
import SwiftUI
#if os(macOS)
import AppKit

typealias PlatformColor = NSColor
#else
import UIKit

typealias PlatformColor = UIColor
#endif

nonisolated struct Theme: Identifiable, Hashable, Sendable {
    let name: String
    let isDark: Bool
    let bg, side, surface, border, code, fg, strong, muted, accent, due, deadline, done, doing, blocked, link: PlatformColor

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

    #if os(macOS)
    /// The Mac's own appearance: themes set each window's appearance, never the app's.
    static var systemIsDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
    #else
    /// The device's own appearance: themes override each window's style, never the scene's.
    static var systemIsDark: Bool {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.traitCollection.userInterfaceStyle == .dark
    }
    #endif
}

nonisolated extension Theme {
    init(name: String, isDark: Bool,
         bg: UInt32, side: UInt32, surface: UInt32, border: UInt32, code: UInt32,
         fg: UInt32, strong: UInt32, muted: UInt32, accent: UInt32, due: UInt32,
         deadline: UInt32, done: UInt32, doing: UInt32, blocked: UInt32, link: UInt32) {
        func c(_ hex: UInt32) -> PlatformColor {
            let red = CGFloat((hex >> 16) & 0xff) / 255, green = CGFloat((hex >> 8) & 0xff) / 255, blue = CGFloat(hex & 0xff) / 255
            #if os(macOS)
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
            #else
            return UIColor(red: red, green: green, blue: blue, alpha: 1)
            #endif
        }
        self.init(name: name, isDark: isDark,
                  bg: c(bg), side: c(side), surface: c(surface), border: c(border), code: c(code),
                  fg: c(fg), strong: c(strong), muted: c(muted), accent: c(accent), due: c(due),
                  deadline: c(deadline), done: c(done), doing: c(doing), blocked: c(blocked), link: c(link))
    }

    func color(_ keyPath: KeyPath<Theme, PlatformColor>) -> Color {
        #if os(macOS)
        Color(nsColor: self[keyPath: keyPath])
        #else
        Color(uiColor: self[keyPath: keyPath])
        #endif
    }
}

extension EnvironmentValues {
    /// The active theme. Every themed view reads its colours from here.
    @Entry var theme: Theme = ThemeSet.standard.dark
}
