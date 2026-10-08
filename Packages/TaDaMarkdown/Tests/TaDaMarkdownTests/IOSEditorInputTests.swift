//
//  IOSEditorInputTests.swift
//  TaDaMarkdownTests
//
//  Typing, taps and presses on the iOS editor go through the shared input path.
//

#if os(iOS)
import SwiftUI
import Testing
import UIKit
@testable import TaDaMarkdown

@MainActor
final class IOSEditorHarness {
    private final class Box {
        var text: String
        var markerRequests: [TaskMarkerMenuRequest] = []
        var calloutRequests: [CalloutMenuRequest] = []
        var toggles: [Character] = []
        init(_ text: String) { self.text = text }
    }

    private let box: Box
    var text: String { box.text }
    var markerRequests: [TaskMarkerMenuRequest] { box.markerRequests }
    var calloutRequests: [CalloutMenuRequest] { box.calloutRequests }
    var toggles: [Character] { box.toggles }
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let textView: NativeTextView

    init(_ text: String) throws {
        let box = Box(text)
        self.box = box
        var configuration = MarkdownEditorConfiguration.default
        configuration.callouts = CalloutStyle(
            tint: { _ in .systemTeal }, drawIcon: { _, _, _ in },
            titleColor: .label, bodyColor: .label, foldColor: .secondaryLabel, targetColor: .systemBlue,
            fillOpacity: 0.09, ringOpacity: 0.24
        )
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let editor = NativeTextViewWrapper(
            text: binding,
            configuration: configuration,
            fontName: UIFont.systemFont(ofSize: 17).fontName,
            fontSize: 17,
            documentId: "doc",
            onTaskMarkerMenu: { box.markerRequests.append($0) },
            onCalloutMenu: { box.calloutRequests.append($0) },
            onTaskCheckboxToggle: { box.toggles.append($0) }
        )
        window.rootViewController = UIHostingController(rootView: editor)
        window.makeKeyAndVisible()
        func find(_ view: UIView) -> NativeTextView? {
            if let textView = view as? NativeTextView { return textView }
            for subview in view.subviews { if let textView = find(subview) { return textView } }
            return nil
        }
        Self.settle(window)
        textView = try #require(find(window))
        textView.becomeFirstResponder()
    }

    static func settle(_ window: UIWindow) {
        for _ in 0..<3 {
            window.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// Lets queued main-queue work run (the binding is published asynchronously), then lays out.
    func settle() async {
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(30))
            window.layoutIfNeeded()
        }
    }

    /// Types `typed` at the caret as the keyboard does: the delegate may take the keystroke itself.
    func type(_ typed: String) async {
        let range = textView.selectedRange
        if textView.delegate?.textView?(textView, shouldChangeTextIn: range, replacementText: typed) ?? true {
            textView.insertText(typed)
        }
        await settle()
    }

    /// Puts the caret after `marker`'s first occurrence and types `typed`.
    func type(_ typed: String, after marker: String) async {
        let location = NSMaxRange((textView.string as NSString).range(of: marker))
        textView.selectedRange = NSRange(location: location, length: 0)
        await type(typed)
    }

    /// The view point of the first task box, found by probing along its line.
    func boxPoint() -> CGPoint? {
        guard let storage = textView.optionalTextStorage, let bridge = textView.layoutBridge else { return nil }
        var boxRange: NSRange?
        storage.enumerateAttribute(.taskCheckbox, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value != nil { boxRange = range; stop.pointee = true }
        }
        guard let boxRange else { return nil }
        let line = bridge.boundingRect(forCharacterRange: boxRange, in: textView.textContainer)
        let y = line.midY + textView.textContainerOrigin.y
        return stride(from: CGFloat(0), to: 120, by: 1)
            .map { CGPoint(x: $0, y: y) }
            .first { textView.taskCheckboxHit(atViewPoint: $0) != nil }
    }
}

@MainActor
@Suite(.serialized)
struct IOSEditorInputTests {
    @Test func loadsTheDocument() async throws {
        let editor = try IOSEditorHarness("- [ ] First")
        #expect(editor.textView.string == "- [ ] First")
    }

    @Test func returnContinuesATaskList() async throws {
        let editor = try IOSEditorHarness("- [ ] First")
        await editor.type("\n", after: "First")
        #expect(editor.textView.string == "- [ ] First\n- [ ] ")
        #expect(editor.text == "- [ ] First\n- [ ] ")
    }

    @Test func tabIndentsAListItemUnderItsSibling() async throws {
        let editor = try IOSEditorHarness("- a\n- b")
        let caret = NSMaxRange((editor.textView.string as NSString).range(of: "- b")) - 1
        editor.textView.selectedRange = NSRange(location: caret, length: 0)
        await editor.type("\t")
        #expect(editor.textView.string == "- a\n\t- b")
    }

    @Test func shiftTabOutdents() async throws {
        let editor = try IOSEditorHarness("- a\n\t- b")
        editor.textView.selectedRange = NSRange(location: (editor.textView.string as NSString).length, length: 0)
        editor.textView.outdent()
        await editor.settle()
        #expect(editor.textView.string == "- a\n- b")
    }

    @Test func doubleBracketClosesAWikilink() async throws {
        let editor = try IOSEditorHarness("See ")
        await editor.type("[", after: "See ")
        await editor.type("[")
        #expect(editor.textView.string == "See [[]]")
    }

    @Test func tappingABoxTogglesItAndUndoRestoresIt() async throws {
        let editor = try IOSEditorHarness("- [ ] Task\n\nBody")
        let point = try #require(editor.boxPoint())
        editor.textView.handleTap(at: point)
        await editor.settle()
        #expect(editor.textView.string == "- [x] Task\n\nBody")
        #expect(editor.text == "- [x] Task\n\nBody")
        #expect(editor.toggles == [" "])
        editor.textView.undoManager?.undo()
        await editor.settle()
        #expect(editor.textView.string == "- [ ] Task\n\nBody")
    }

    @Test func pressAndHoldOnABoxRequestsItsMenu() async throws {
        let editor = try IOSEditorHarness("- [ ] Task")
        let point = try #require(editor.boxPoint())
        editor.textView.handlePress(at: point)
        let request = try #require(editor.markerRequests.first)
        #expect(request.marker == " ")
        request.setMarker("/")
        await editor.settle()
        #expect(editor.textView.string == "- [/] Task")
    }

    @Test func pressAndHoldOnACalloutTitleRequestsItsMenu() async throws {
        let editor = try IOSEditorHarness("> [!note] Title\n> Body\n\nAfter")
        let bridge = try #require(editor.textView.layoutBridge)
        let line = bridge.boundingRect(forCharacterRange: NSRange(location: 0, length: 5), in: editor.textView.textContainer)
        editor.textView.handlePress(at: CGPoint(x: 200, y: line.midY + editor.textView.textContainerOrigin.y))
        let request = try #require(editor.calloutRequests.first)
        #expect(request.type == "note")
        request.setType("tip")
        request.close()
        await editor.settle()
        #expect(editor.textView.string == "> [!tip] Title\n> Body\n\nAfter")
    }
}
#endif
