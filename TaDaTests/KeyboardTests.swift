import AppKit
import SwiftUI
import Testing
import TaDaCore
@testable import TaDa

/// The list keys and Add Subtask (⌘L), in a real window with key events sent to it.
@MainActor
struct KeyboardTests {
    let defaults: UserDefaults
    let suite = "TaDaTests-\(UUID().uuidString)"
    let folder = FileManager.default.temporaryDirectory.appending(path: "TaDaVault-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        for (path, text) in [
            ("tasks/A.md", "---\ntype: task\nstatus: Not Started\ndueDate: 2026-10-01\n---\nFirst line.\n"),
            ("tasks/B.md", "---\ntype: task\nstatus: Not Started\ndueDate: 2026-10-02\n---\n- [ ] One\n"),
            ("tasks/C.md", "---\ntype: task\nstatus: Not Started\ndueDate: 2026-10-03\n---\n"),
        ] {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }

    private func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    private func window(for model: AppModel) async throws -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.makeKeyAndOrderFront(nil)
        try await settle()
        return window
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(400)) }

    private func press(_ key: Int, code: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) async throws {
        let characters = String(Character(Unicode.Scalar(UInt16(key))!))
        // Straight to the window, which hands it to its first responder. AppKit would send it to the key
        // window, which can be another test's.
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                                      windowNumber: window.windowNumber, context: nil, characters: characters,
                                                      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            window.sendEvent(event)
        }
        try await settle()
    }

    /// Waits up to 5 s for a list to have the keyboard.
    private func listHasKeyboard(in window: NSWindow) async throws {
        for _ in 0..<50 where !(window.firstResponder is ListKeyView) { try await Task.sleep(for: .milliseconds(100)) }
    }

    private func down(_ window: NSWindow) async throws { try await press(NSDownArrowFunctionKey, code: 125, in: window) }
    private func up(_ window: NSWindow) async throws { try await press(NSUpArrowFunctionKey, code: 126, in: window) }

    /// The live editor, once the selected file has loaded into it.
    private func loadedEditor(in window: NSWindow) async throws -> NSTextView {
        for _ in 0..<50 {
            if let content = window.contentView, let textView = editor(in: content), !textView.string.isEmpty { return textView }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CancellationError()
    }

    private func editor(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, !textView.isFieldEditor, textView.isEditable { return textView }
        return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }

    @Test func arrowKeysMoveThroughTheListButNotWhileEditing() async throws {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        model.today = LocalDate("2026-10-03")!
        await model.choose(folder)
        let window = try await window(for: model)
        defer { window.orderOut(nil) }

        try await listHasKeyboard(in: window)
        try await down(window)
        #expect(model.selection == "tasks/A.md")
        try await down(window)
        try await down(window)
        try await down(window)
        #expect(model.selection == "tasks/C.md", "stops at the last task")
        try await up(window)
        #expect(model.selection == "tasks/B.md")

        let textView = try await loadedEditor(in: window)
        window.makeFirstResponder(textView)
        try await down(window)
        #expect(model.selection == "tasks/B.md", "the editor keeps its arrow keys")

        // Picking a row (as a click does) takes the keyboard from the editor.
        model.selection = "tasks/C.md"
        try await settle()
        #expect(!(window.firstResponder is NSTextView))
        try await up(window)
        #expect(model.selection == "tasks/B.md")
        try await press(0x1B, code: 53, in: window)
        #expect(model.selection == nil, "Escape clears the selection")
    }

    @Test func commandDeleteTrashesTheTaskAndRestoresItInTrash() async throws {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        model.today = LocalDate("2026-10-03")!
        await model.choose(folder)
        let window = try await window(for: model)
        defer { window.orderOut(nil) }

        try await listHasKeyboard(in: window)
        try await down(window)
        try await press(NSDeleteCharacter, code: 51, modifiers: .command, in: window)
        for _ in 0..<50 where model.trash.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(model.trash.map(\.id) == [".trash/A.md"], "within 5 s")

        // Trash takes the keyboard when it replaces the editor.
        window.makeFirstResponder(try await loadedEditor(in: window))
        model.show(.trash)
        try await listHasKeyboard(in: window)
        try await down(window)
        #expect(model.trashSelection == [".trash/A.md"])
        try await press(NSDeleteCharacter, code: 51, modifiers: .command, in: window)
        for _ in 0..<50 where !model.trash.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(model.trash.isEmpty && model.index["tasks/A.md"] != nil, "within 5 s")
    }

    @Test func addSubtaskEditsTheLineInTheLiveEditor() async throws {
        defer { cleanUp() }
        let model = AppModel(defaults: defaults)
        model.today = LocalDate("2026-10-03")!
        await model.choose(folder)
        model.selection = "tasks/A.md"
        let window = try await window(for: model)
        defer { window.orderOut(nil) }

        let textView = try await loadedEditor(in: window)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        AddSubtask.perform(in: textView)
        try await settle()
        #expect(model.document?.text == "---\ntype: task\nstatus: Not Started\ndueDate: 2026-10-01\n---\n- [ ] First line.\n")
        #expect(model.document?.item?.subtasks.total == 1)
        #expect(textView.selectedRange().location == 11, "the caret stays on its letter")

        AddSubtask.perform(in: textView)
        try await settle()
        #expect(model.document?.text.hasSuffix("---\n- [x] First line.\n") == true, "a subtask completes")
        #expect(model.document?.item?.subtasks.done == 1)
        #expect(textView.selectedRange().location == 11)

        // The test runner never ends the event, so both edits sit in one undo group here; in the app each
        // ⌘L is its own step (TaDaUITests). What matters here is that the undo reaches the document.
        textView.undoManager?.undo()
        try await settle()
        #expect(textView.string == "First line.\n")
        #expect(model.document?.body == "First line.\n")
    }
}

