// The five bundled schemes from the Themes artboard.
import AppKit

nonisolated extension Theme {
    static let all: [Theme] = [
        Theme(name: "Tomorrow Night", isDark: true,
              bg: 0x1d1f21, side: 0x18191b, surface: 0x373b41, border: 0x2c2e31, code: 0x26282b,
              fg: 0xc5c8c6, strong: 0xeaeaea, muted: 0x969896, accent: 0x81a2be, due: 0xf0c674,
              deadline: 0xcc6666, done: 0xb5bd68, doing: 0x8abeb7, blocked: 0xde935f, link: 0xb294bb),
        Theme(name: "Solarized Light", isDark: false,
              bg: 0xfdf6e3, side: 0xf4eddb, surface: 0xe9e2cb, border: 0xe4ddc8, code: 0xf3ecd8,
              fg: 0x4f6169, strong: 0x073642, muted: 0x5f7178, accent: 0x268bd2, due: 0xb58900,
              deadline: 0xdc322f, done: 0x859900, doing: 0x2aa198, blocked: 0xcb4b16, link: 0xc3317a),
        Theme(name: "Dracula", isDark: true,
              bg: 0x282a36, side: 0x21222c, surface: 0x44475a, border: 0x343746, code: 0x303241,
              fg: 0xf8f8f2, strong: 0xffffff, muted: 0xa7acd0, accent: 0xbd93f9, due: 0xf1fa8c,
              deadline: 0xff5555, done: 0x50fa7b, doing: 0x8be9fd, blocked: 0xffb86c, link: 0xff79c6),
        Theme(name: "Nord", isDark: true,
              bg: 0x2e3440, side: 0x292e39, surface: 0x434c5e, border: 0x3b4252, code: 0x353b49,
              fg: 0xd8dee9, strong: 0xeceff4, muted: 0xa0aabd, accent: 0x81a1c1, due: 0xebcb8b,
              deadline: 0xbf616a, done: 0xa3be8c, doing: 0x88c0d0, blocked: 0xd08770, link: 0xb48ead),
        Theme(name: "Gruvbox Light", isDark: false,
              bg: 0xfbf1c7, side: 0xf2e5bc, surface: 0xebdbb2, border: 0xe6d6ac, code: 0xf2e5bc,
              fg: 0x3c3836, strong: 0x282828, muted: 0x665c54, accent: 0x076678, due: 0xb57614,
              deadline: 0x9d0006, done: 0x79740e, doing: 0x427b58, blocked: 0xaf3a03, link: 0x8f3f71),
    ]
}
