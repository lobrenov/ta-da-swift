// The six bundled schemes and the three theme sets that pair them, from the Theme tokens artboard.
import SwiftUI

nonisolated extension Theme {
    static let all: [Theme] = [
        Theme(name: "Ayu Light", isDark: false,
              bg: 0xf8f9fa, side: 0xeff0f1, surface: 0xdfe1e2, border: 0xe8eaeb, code: 0xf0f1f3,
              fg: 0x5c6166, strong: 0x333538, muted: 0x686868, accent: 0x3096dc, due: 0xb88435,
              deadline: 0xe56a6b, done: 0x5ba038, doing: 0x3ca07f, blocked: 0xcf794d, link: 0x9e75c7),
        Theme(name: "Ayu Mirage", isDark: true,
              bg: 0x1f2430, side: 0x191e27, surface: 0x3b3f47, border: 0x30353f, code: 0x282c37,
              fg: 0xcccac2, strong: 0xe3e2dd, muted: 0x8e8e8d, accent: 0x6dcbfa, due: 0xfacc6e,
              deadline: 0xed8274, done: 0x87d96c, doing: 0x90e1c6, blocked: 0xf3a771, link: 0xdabafa),
        Theme(name: "TokyoNight Day", isDark: false,
              bg: 0xe1e2e7, side: 0xd9dadf, surface: 0x99a7df, border: 0xcfd4e0, code: 0xd8dbe4,
              fg: 0x2f53a4, strong: 0x1a2e5a, muted: 0x4161ab, accent: 0x2e7de9, due: 0x8c6c3e,
              deadline: 0xf52a65, done: 0x587539, doing: 0x007197, blocked: 0xc04b52, link: 0x9854f1),
        Theme(name: "TokyoNight", isDark: true,
              bg: 0x1a1b26, side: 0x15161f, surface: 0x33467c, border: 0x2b2c3b, code: 0x222430,
              fg: 0xc0caf5, strong: 0xdce2fa, muted: 0x7e84a2, accent: 0x7aa2f7, due: 0xe0af68,
              deadline: 0xf7768e, done: 0x9ece6a, doing: 0x7dcfff, blocked: 0xec927b, link: 0xbb9af7),
        Theme(name: "Catppuccin Latte", isDark: false,
              bg: 0xeff1f5, side: 0xe7e9ec, surface: 0xd5d7df, border: 0xdfe1e7, code: 0xe7e9ee,
              fg: 0x4c4f69, strong: 0x2a2b3a, muted: 0x66697f, accent: 0x1e66f5, due: 0xc07a19,
              deadline: 0xd20f39, done: 0x3f9d2a, doing: 0x179299, blocked: 0xd84e2b, link: 0xc965af),
        Theme(name: "Catppuccin Mocha", isDark: true,
              bg: 0x1e1e2e, side: 0x191926, surface: 0x3a3b4e, border: 0x303042, code: 0x272738,
              fg: 0xcdd6f4, strong: 0xe4e8f9, muted: 0x8489a1, accent: 0x89b4fa, due: 0xf9e2af,
              deadline: 0xf38ba8, done: 0xa6e3a1, doing: 0x94e2d5, blocked: 0xf6b6ac, link: 0xf5c2e7),
    ]
}

nonisolated extension ThemeSet {
    static let all: [ThemeSet] = [
        ThemeSet(name: "Ayu", light: "Ayu Light", dark: "Ayu Mirage"),
        ThemeSet(name: "TokyoNight", light: "TokyoNight Day", dark: "TokyoNight"),
        ThemeSet(name: "Catppuccin", light: "Catppuccin Latte", dark: "Catppuccin Mocha"),
    ]
    /// The set a new install starts with.
    static let standard = all[0]
}
