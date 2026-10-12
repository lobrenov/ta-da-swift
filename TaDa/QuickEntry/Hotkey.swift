// A global hotkey: a key and its modifiers, as Carbon's `RegisterEventHotKey` takes them.

/// A key with at least one modifier, e.g. ⌃Space. `key` is the key's name as shown; `keyCode` and `modifiers` are
/// Carbon's (`kVK_…`; `controlKey`, `optionKey`, `shiftKey`, `cmdKey`).
struct Hotkey: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    static let control: UInt32 = 0x1000
    static let option: UInt32 = 0x0800
    static let shift: UInt32 = 0x0200
    static let command: UInt32 = 0x0100

    /// ⌃Space.
    static let quickEntryDefault = Hotkey(keyCode: 49, modifiers: control, key: "Space")

    /// The modifiers then the key, e.g. ⌃Space.
    var displayString: String { (modifierSymbols + [key]).joined() }

    /// The modifiers in the system's order: ⌃⌥⇧⌘.
    var modifierSymbols: [String] {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1)
    }

    /// How the settings keep it.
    var dictionary: [String: Any] { ["keyCode": Int(keyCode), "modifiers": Int(modifiers), "key": key] }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    init?(_ dictionary: [String: Any]) {
        guard let keyCode = dictionary["keyCode"] as? Int, let modifiers = dictionary["modifiers"] as? Int,
              let key = dictionary["key"] as? String else { return nil }
        self.init(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers), key: key)
    }
}

#if os(macOS)
import AppKit

extension Hotkey {
    /// The chord a key press makes, when it holds one or more of ⌃⌥⌘ (⇧ alone isn't enough).
    init?(_ event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= Self.control }
        if flags.contains(.option) { modifiers |= Self.option }
        if flags.contains(.shift) { modifiers |= Self.shift }
        if flags.contains(.command) { modifiers |= Self.command }
        guard modifiers & ~Self.shift != 0 else { return nil }
        let code = UInt32(event.keyCode)
        guard let key = Self.names[code] ?? event.characters(byApplyingModifiers: [])?.uppercased(), !key.isEmpty
        else { return nil }
        self.init(keyCode: code, modifiers: modifiers, key: key)
    }

    /// Names for keys that don't type a character.
    private static let names: [UInt32: String] = [
        49: "Space", 36: "↩", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
#endif
