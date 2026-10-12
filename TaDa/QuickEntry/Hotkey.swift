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

    /// The modifiers in the system's order, then the key: ⌃⌥⇧⌘.
    var displayString: String {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined() + key
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
