// Increase Contrast: a theme's low-contrast roles pulled toward its stronger ones, derived from the theme itself.
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

nonisolated extension Theme {
    /// Text on `bg` reaches 4.5:1 and a hairline 3:1 (WCAG AA).
    static let increasedTextRatio = 4.5, increasedLineRatio = 3.0

    /// The theme with its low-contrast roles strengthened:
    /// - `muted` moves toward `fg` (then `strong`) until it reaches 4.5:1 on `bg`, by at least a quarter of the way.
    /// - `border` moves toward the new `muted` (then `fg`) until it reaches 3:1 on `bg`, by at least 30%.
    /// - `surface` and `code` move 10% toward `fg`.
    /// - The accent and status colours move toward `strong` only while under 3:1 on `bg`.
    /// `bg`, `side`, `fg` and `strong` stay.
    var increasedContrast: Theme {
        let newMuted = Self.strengthened(muted, bg: bg, ratio: Self.increasedTextRatio, minimum: 0.25, toward: [fg, strong])
        let newBorder = Self.strengthened(border, bg: bg, ratio: Self.increasedLineRatio, minimum: 0.3, toward: [newMuted, fg, strong])
        func lift(_ color: PlatformColor) -> PlatformColor {
            Self.strengthened(color, bg: bg, ratio: Self.increasedLineRatio, minimum: 0, toward: [strong])
        }
        return Theme(name: name, isDark: isDark,
                     bg: bg, side: side, surface: Self.mix(surface, fg, 0.1), border: newBorder, code: Self.mix(code, fg, 0.1),
                     fg: fg, strong: strong, muted: newMuted, accent: lift(accent), due: lift(due),
                     deadline: lift(deadline), done: lift(done), doing: lift(doing), blocked: lift(blocked),
                     link: lift(link))
    }

    /// This theme, strengthened when `isIncreased`.
    func contrasted(_ isIncreased: Bool) -> Theme {
        isIncreased ? increasedContrast : self
    }

    /// The system's Increase Contrast setting, for views that can't read the environment.
    @MainActor static var systemIncreasesContrast: Bool {
        #if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        #else
        UIAccessibility.isDarkerSystemColorsEnabled
        #endif
    }

    /// `color` mixed toward each target in turn, in 5% steps from `minimum`, stopping at the first mix with `ratio` on `bg`.
    /// A colour already past `ratio` still moves by `minimum`.
    private static func strengthened(_ color: PlatformColor, bg: PlatformColor, ratio: Double, minimum: Double,
                                     toward targets: [PlatformColor]) -> PlatformColor {
        var result = color
        for target in targets {
            for step in stride(from: minimum, through: 1, by: 0.05) {
                result = mix(color, target, step)
                if contrastRatio(result, bg) >= ratio { return result }
            }
        }
        return result
    }

    private static func mix(_ a: PlatformColor, _ b: PlatformColor, _ amount: Double) -> PlatformColor {
        let (ar, ag, ab) = rgb(a), (br, bgreen, bb) = rgb(b)
        let t = CGFloat(amount)
        #if os(macOS)
        return NSColor(srgbRed: ar + (br - ar) * t, green: ag + (bgreen - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
        #else
        return UIColor(red: ar + (br - ar) * t, green: ag + (bgreen - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
        #endif
    }

    private static func rgb(_ color: PlatformColor) -> (CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    /// The WCAG contrast ratio of two opaque sRGB colours, 1 to 21.
    static func contrastRatio(_ a: PlatformColor, _ b: PlatformColor) -> Double {
        func luminance(_ color: PlatformColor) -> Double {
            let (r, g, b) = rgb(color)
            func linear(_ v: CGFloat) -> Double {
                let v = Double(v)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
