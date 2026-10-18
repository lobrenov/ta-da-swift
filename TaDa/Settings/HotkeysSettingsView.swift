// Settings ▸ Hotkeys: the global hotkey that opens Quick Entry, which can be recorded, then the app's other keys, which can't.
#if os(macOS)
import SwiftUI

struct HotkeysSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme

    private var isRecording: Bool { model.isRecordingHotkey }

    var body: some View {
        SettingsPage(title: "Hotkeys", summary: "Ta Da’s keyboard shortcuts. Quick Entry’s works in any app while Ta Da is open.", spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Global")
                VStack(spacing: 0) {
                    quickEntryRow
                    if isRecording {
                        note("Hold one or more of ⌃ ⌥ ⇧ ⌘ and press a key. esc cancels.")
                    } else if model.quickEntryHotkey == nil {
                        note("No shortcut: Quick Entry won’t open from other apps.")
                    } else if model.quickEntryHotkeyTaken {
                        takenWarning
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
            }
            keyList("Files and views", Self.fileKeys)
            keyList("Tasks", Self.taskKeys)
            keyList("Editor", Self.editorKeys)
            keyList("In Quick Entry", Self.quickEntryKeys)
        }
    }

    typealias KeyRow = (what: String, keys: [String])

    static let fileKeys: [KeyRow] = [("New task or note", ["⌘N"]), ("New project", ["⇧⌘N"]), ("New area", ["⌥⌘N"]),
                                     ("Search files", ["⌥⌘F"]), ("Agenda, Loose tasks, Trash, Logbook", ["⌘1–⌘4"]),
                                     ("Live or Source", ["⌘E"]), ("Toggle sidebar", ["⌃⌘S"]), ("Settings", ["⌘,"])]

    static let taskKeys: [KeyRow] = [("Move to a project or area", ["⌘P"]), ("Schedule", ["⌘S"]), ("Set deadline", ["⌘D"]),
                                     ("Tags", ["⌘T"]), ("Move to the trash", ["⌫", "⌘⌫"])]

    static let editorKeys: [KeyRow] = [("Bold", ["⌘B"]), ("Italic", ["⌘I"]), ("Highlight", ["⇧⌘H"]), ("Strikethrough", ["⇧⌘S"]),
                                       ("Add or complete a subtask", ["⌘L"]), ("Indent", ["⇥"]), ("Outdent", ["⇧⇥"])]

    static let quickEntryKeys: [KeyRow] = [("Create the file", ["↵"]), ("Create and open the file", ["⌘↵"]), ("Move", ["⌘P"]),
                                           ("Due date", ["⌘S"]), ("Deadline", ["⌘D"]), ("Close", ["esc"])]

    private func keyList(_ title: String, _ rows: [KeyRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: title)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Hairline() }
                    HStack(spacing: 12) {
                        Text(row.what)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(Array(row.keys.enumerated()), id: \.offset) { index, key in
                            if index > 0 { Text("or").foregroundStyle(theme.color(\.muted)) }
                            KeyCap(key: key, size: 11.5, theme: theme)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
        }
    }

    private var quickEntryRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Quick Entry")
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color(\.strong))
                Text("Opens a new task, project or area over any app.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.muted))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HotkeyRecorder(hotkey: $model.quickEntryHotkey, isRecording: $model.isRecordingHotkey, isTaken: model.quickEntryHotkeyTaken)
            iconButton("arrow.counterclockwise", help: "Restore ⌃Space", label: "Restore the default, Control Space",
                       disabled: model.quickEntryHotkey == .quickEntryDefault) {
                model.isRecordingHotkey = false
                model.quickEntryHotkey = .quickEntryDefault
            }
            iconButton("xmark", help: "Clear", label: "Clear the shortcut", disabled: model.quickEntryHotkey == nil) {
                model.isRecordingHotkey = false
                model.quickEntryHotkey = nil
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var takenWarning: some View {
        let keys = model.quickEntryHotkey?.displayString ?? ""
        let isDefault = model.quickEntryHotkey == .quickEntryDefault
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(theme.color(\.blocked))
                    .frame(width: 16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isDefault ? "macOS uses ⌃Space to switch input sources." : "Another app or macOS uses \(keys).")
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.color(\.strong))
                    Text(isDefault
                         ? "Pick another shortcut, or turn off Select the previous input source in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Input Sources."
                         : "Pick another shortcut, or turn it off in System Settings ▸ Keyboard ▸ Keyboard Shortcuts.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingsButton("Open Keyboard Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
            .padding(.leading, 26)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Hairline() }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(theme.color(\.muted))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Hairline() }
    }

    private func iconButton(_ systemImage: String, help: String, label: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.color(\.muted))
                .frame(width: 28, height: 28)
                .background(theme.color(\.code), in: .rect(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(label)
    }
}

/// The hotkey's keys in a field; a click records the next chord, esc, another click or leaving the window cancels.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey?
    @Binding var isRecording: Bool
    let isTaken: Bool
    @State private var monitor: Any?
    @Environment(\.theme) private var theme
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            HStack(spacing: 4) {
                if isRecording {
                    Text("Type a shortcut…")
                } else if let hotkey {
                    ForEach(hotkey.modifierSymbols + [hotkey.key], id: \.self) { key in
                        Text(key)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.color(\.strong))
                            .frame(minWidth: 12)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(theme.color(\.surface), in: .rect(cornerRadius: 4))
                    }
                } else {
                    Text("Record Shortcut")
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(theme.color(isRecording ? \.accent : \.muted))
            .padding(.horizontal, 10)
            .frame(minWidth: 150, minHeight: 28)
            .background(theme.color(\.code), in: .rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(isRecording ? \.accent : isTaken ? \.blocked : \.border)))
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.color(\.surface)).padding(-3).opacity(isRecording ? 1 : 0))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quick Entry")
        .accessibilityValue(isRecording ? "Recording" : hotkey?.spokenString ?? "None")
        .onChange(of: isRecording) { _, recording in recording ? startMonitor() : stopMonitor() }
        .onChange(of: activeState) { _, state in if state != .key { isRecording = false } }
        .onDisappear {
            stopMonitor()
            isRecording = false
        }
    }

    private func startMonitor() {
        stopMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                isRecording = false
            } else if let chord = Hotkey(event) {
                hotkey = chord
                isRecording = false
            }
            return nil
        }
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

#Preview {
    HotkeysSettingsView(model: AppModel())
}
#endif
