import AppKit
import SwiftUI
import Testing
import TaDaCore
@testable import TaDa

/// Arrow keys in the lists and Add Subtask (⌘L), in a real window with key events sent to it.
/// One test at a time: a key the list doesn't take goes to the key window, which could be another test's.
@MainActor
@Suite(.serialized)
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

    private func press(_ key: Int, code: UInt16, in window: NSWindow) async throws {
        let characters = String(Character(Unicode.Scalar(UInt16(key))!))
        // Through the event queue, as a real key press, so the window's key monitor sees it.
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                                      windowNumber: window.windowNumber, context: nil, characters: characters,
                                                      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
            NSApp.postEvent(event, atStart: false)
        }
        try await settle()
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

