import AppKit
import Foundation
import SwiftUI
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct SourceModeTests {
    let folder: TestFolder
    static let task = "---\ntype: task\nstatus: Doing\n---\nBody.\n"

    init() throws {
        folder = try TestFolder(["tasks/Task.md": Self.task])
    }

    @Test func sourceModeEndsWhenNothingIsSelected() async {
        let model = await folder.model()
        model.selection = "tasks/Task.md"
        model.isSourceMode = true
        model.domain = .loose
        #expect(model.selection == nil)
        #expect(!model.isSourceMode)
    }

    @Test func typingInSourceEditsTheWholeFileAndBrokenYAMLOnlyWarns() async throws {
        let model = await folder.model()
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 1280, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.orderFrontRegardless()
        model.selection = "tasks/Task.md"
        model.isSourceMode = true

        func sourceView(in view: NSView) -> SourceTextView? {
            if let textView = view as? SourceTextView { return textView }
            return view.subviews.lazy.compactMap(sourceView(in:)).first
        }
        for _ in 0..<50 where sourceView(in: window.contentView!) == nil { try await Task.sleep(for: .milliseconds(100)) }
        let editor = try #require(sourceView(in: window.contentView!), "within 5 s")
        let document = try #require(model.document)
        #expect(editor.string == Self.task)

        // Change the status on line 3.
        let status = (editor.string as NSString).range(of: "Doing")
        editor.setSelectedRange(status)
        editor.insertText("Blocked", replacementRange: status)
        #expect(document.text == Self.task.replacingOccurrences(of: "Doing", with: "Blocked"))
        #expect(model.index["tasks/Task.md"]?.properties.status == .blocked)

        // Break the YAML: the file still loads, with a warning.
        let line2 = (editor.string as NSString).range(of: "type: task")
        editor.insertText("type: task\nstatus: [unclosed", replacementRange: NSRange(location: line2.location, length: (editor.string as NSString).range(of: "Blocked").upperBound - line2.location))
        let item = try #require(model.index["tasks/Task.md"])
        #expect(item.warnings.contains { if case .invalidYAML = $0 { true } else { false } })

        // Switching back to Live keeps the text.
        model.isSourceMode = false
        try await Task.sleep(for: .milliseconds(300))
        #expect(document.text.contains("status: [unclosed"))
    }
}
