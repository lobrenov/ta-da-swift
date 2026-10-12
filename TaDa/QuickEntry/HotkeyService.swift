// Registers the global hotkey with Carbon, which needs no Accessibility permission and works in the sandbox.
#if os(macOS)
import Carbon.HIToolbox

/// Holds one global hotkey and calls `onPress` on the main actor when it's pressed, whichever app is active.
final class HotkeyService {
    var onPress: (() -> Void)?
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Registers `hotkey` in place of the one before; nil leaves none. Returns false when another app or a macOS
    /// shortcut has the keys: a macOS shortcut wins while it's on, and the hotkey works once it's turned off.
    @discardableResult
    func register(_ hotkey: Hotkey?) -> Bool {
        if let hotkeyRef { UnregisterEventHotKey(hotkeyRef) }
        hotkeyRef = nil
        guard let hotkey else { return true }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x5461_4461), id: 1) // "TaDa"
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &hotkeyRef)
        return status == noErr && !Self.isMacOSShortcut(hotkey)
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue().onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Whether a turned-on macOS shortcut (System Settings ▸ Keyboard ▸ Keyboard Shortcuts) uses the keys.
    private static func isMacOSShortcut(_ hotkey: Hotkey) -> Bool {
        var shortcuts: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&shortcuts) == noErr,
              let list = shortcuts?.takeRetainedValue() as? [[String: Any]] else { return false }
        return list.contains {
            $0[kHISymbolicHotKeyEnabled as String] as? Bool == true
                && $0[kHISymbolicHotKeyCode as String] as? Int == Int(hotkey.keyCode)
                && $0[kHISymbolicHotKeyModifiers as String] as? Int == Int(hotkey.modifiers)
        }
    }
}
#endif
