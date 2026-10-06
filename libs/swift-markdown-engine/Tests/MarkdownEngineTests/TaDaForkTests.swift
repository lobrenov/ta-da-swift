//
//  TaDaForkTests.swift
//  MarkdownEngineTests
//
//  Behaviour added or changed by the Ta Da fork (see FORK.md).
//

import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@Suite("Ta Da fork — alternative checkboxes")
struct AlternativeCheckboxTests {

    private func item(_ text: String) -> ListItem? {
        for block in DocumentAST.parse(text) { if case .list(_, let items) = block { return items.first } }
        return nil
    }

    @Test(arguments: TaskMarker.all)
    func everyReferenceMarkerParsesAsACheckbox(marker: Character) {
        let parsed = item("- [\(marker)] thing\n")
        #expect(parsed?.checkbox == NSRange(location: 2, length: 3))
        #expect(parsed?.taskMarker == marker)
        #expect(parsed?.checked == (marker == "x" || marker == "X"))
    }

    @Test func unknownMarkersStayText() {
        #expect(item("- [y] thing\n")?.checkbox == nil)
        #expect(item("- [] thing\n")?.checkbox == nil)
    }

    @Test func aBoxFollowsOneToFourSpacesOrTabsAndNeedsOneAfterIt() {
        #expect(item("-  [ ] two spaces\n")?.checkbox == NSRange(location: 3, length: 3))
        #expect(item("-  [ ] two spaces\n")?.contentRange == NSRange(location: 7, length: 10))
        #expect(item("-\t[x]\ttabs\n")?.checkbox == NSRange(location: 2, length: 3))
        #expect(item("- [ ] \n")?.checkbox == NSRange(location: 2, length: 3))
        #expect(item("- [ ]\n")?.checkbox == nil)
        #expect(item("- [ ]")?.checkbox == nil)
        #expect(item("- [x]NoSpace\n")?.checkbox == nil)
        #expect(item("-     [ ] five spaces\n")?.checkbox == nil)
    }

    @Test func caretHelpersReadBoxesTheSameWay() {
        #expect(MarkdownStyler.bulletSyntaxRange(at: 0, in: "- [x]NoSpace\n") != nil)
        #expect(MarkdownStyler.bulletSyntaxRange(at: 0, in: "-  [ ] two spaces\n") == nil)
        #expect(MarkdownStyler.taskSyntaxRange(at: 0, in: "-  [ ] two spaces\n") != nil)
        let ordered = "1. [x]NoSpace"
        #expect(MarkdownStyler.orderedListRegex.firstMatch(in: ordered, range: NSRange(location: 0, length: 13)) != nil)
    }

    @Test func checkboxAttributeCarriesTheMarkerAndOnlyDoneStrikes() {
        func attrs(_ text: String) -> [StyledRange] {
            MarkdownASTStyler.styleAttributes(text: text, fontName: NSFont.systemFont(ofSize: 14).fontName, fontSize: 14)
        }
        let cancelled = attrs("- [-] dropped")
        #expect(cancelled.contains { $0.attributes[.taskCheckbox] as? String == "-" })
        #expect(!cancelled.contains { $0.attributes[.strikethroughStyle] != nil })
        let done = attrs("- [x] finished")
        #expect(done.contains { $0.attributes[.taskCheckbox] as? String == "x" })
        #expect(done.contains {
            $0.attributes[.strikethroughStyle] != nil
                && $0.attributes[.foregroundColor] as? NSColor == MarkdownEditorConfiguration.default.theme.mutedText
        })
    }

    @Test func referenceStyleCoversEveryMarker() {
        let style = TaskCheckboxStyle.default
        for marker in TaskMarker.all {
            #expect(style.symbolNames[marker].flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) } != nil,
                    "no SF Symbol for [\(marker)]")
        }
        #expect(Set(style.menuItems.map(\.marker)) == Set(TaskMarker.all).subtracting(["X"]))
    }
}

@Suite("Ta Da fork — lists in blockquotes")
struct QuotedListTests {

    private func quotedItems(_ text: String) -> [ListItem] {
        for block in DocumentAST.parse(text) { if case .blockquote(_, _, let items) = block { return items } }
        return []
    }

    private func attrs(_ text: String) -> [StyledRange] {
        MarkdownASTStyler.styleAttributes(text: text, fontName: NSFont.systemFont(ofSize: 14).fontName, fontSize: 14)
    }

    @Test func quoteLinesThatAreListItemsParseAsItems() {
        let items = quotedItems("> - [ ] open\n> plain\n>> 1. [x] done\n> * bullet\n")
        #expect(items.map(\.taskMarker) == [" ", "x", nil])
        #expect(items.map(\.checkbox) == [NSRange(location: 4, length: 3), NSRange(location: 27, length: 3), nil])
        #expect(items.map(\.marker) == [NSRange(location: 2, length: 1), NSRange(location: 24, length: 2), NSRange(location: 38, length: 1)])
        #expect(quotedItems("> plain\n> -not a bullet\n").isEmpty)
    }

    @Test func quotedItemsGetTheirBoxOrBulletInsideTheQuote() {
        let text = "Intro\n\n> - [x] done\n> - bullet\n"
        let styled = attrs(text)
        #expect(styled.contains { $0.attributes[.taskCheckbox] as? String == "x" })
        #expect(styled.contains { $0.attributes[.bulletMarker] as? Bool == true })
        #expect(styled.contains { $0.attributes[.strikethroughStyle] != nil })
        #expect(styled.contains { $0.attributes[.blockquoteLevel] as? Int == 1 })
        // The item sits one list level in from the quote's text, as a list does from body text.
        let line = (text as NSString).range(of: "> - [x] done")
        let style = styled.last { NSIntersectionRange($0.range, line).length > 0 && $0.attributes[.paragraphStyle] != nil }?
            .attributes[.paragraphStyle] as? NSParagraphStyle
        let quoteIndent = MarkdownTextLayoutFragment.blockquoteIndentPerLevel * 1.5
        #expect(style?.firstLineHeadIndent == quoteIndent + MarkdownEditorConfiguration.default.lists.indentPerLevel)
    }

    @Test func caretHelpersSeeQuotedSyntax() {
        #expect(MarkdownStyler.taskSyntaxRange(at: 2, in: "> - [ ] a\n") == NSRange(location: 2, length: 5))
        #expect(MarkdownStyler.bulletSyntaxRange(at: 2, in: "> - a\n") == NSRange(location: 2, length: 2))
        #expect(MarkdownStyler.bulletSyntaxRange(at: 2, in: "> text\n") == nil)
    }

    @MainActor
    @Test func returnContinuesAQuotedItemAndAnEmptyOneLeavesOnlyTheQuote() {
        func enter(_ text: String) -> String {
            let tv = NSTextView()
            tv.string = text
            let end = NSRange(location: (text as NSString).length, length: 0)
            #expect(!MarkdownLists.handleInsertion(textView: tv, affectedCharRange: end, replacementString: "\n",
                                                   isInsideCodeBlock: false))
            return tv.string
        }
        #expect(enter("> - [x] a") == "> - [x] a\n> - [ ] ")
        #expect(enter(">>   1. a") == ">>   1. a\n>>   2. ")
        #expect(enter("> - [ ] ") == "> ")
        #expect(enter("> plain") == "> plain\n> ")
    }
}

@MainActor
@Suite("Ta Da fork — Tab and Shift-Tab")
struct ListIndentTests {

    private func makeEditor(_ text: String) -> NativeTextView {
        _ = NSApplication.shared
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.isEditable = true
        textView.allowsUndo = true
        textView.configuration = .default
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text), fontName: "SF Pro Text", fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        coordinator.textView = textView
        textView.delegate = coordinator
        textView.string = text
        coordinator.lastSyncedText = text
        coordinator.lastComputedStorage = text
        coordinator.previousDisplayLength = (text as NSString).length
        objc_setAssociatedObject(textView, &Self.coordinatorKey, coordinator, .OBJC_ASSOCIATION_RETAIN)
        return textView
    }
    private static var coordinatorKey = 0

    private func select(_ tv: NSTextView, _ needle: String, through end: String? = nil) {
        let ns = tv.string as NSString
        let start = ns.range(of: needle).location
        let stop = end.map { NSMaxRange(ns.range(of: $0)) } ?? start
        tv.setSelectedRange(NSRange(location: start, length: stop - start))
    }

    private func tab(_ tv: NSTextView) {
        tv.insertText("\t", replacementRange: tv.selectedRange())
    }

    private func backtab(_ tv: NSTextView) {
        tv.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
    }

    @Test func firstItemHasNoSiblingSoTabDoesNothing() {
        let tv = makeEditor("Intro\n\n- [ ] a\n- [ ] b\n")
        select(tv, "a"); tab(tv)
        #expect(tv.string == "Intro\n\n- [ ] a\n- [ ] b\n")
    }

    @Test func itemNestsUnderItsPreviousSibling() {
        let tv = makeEditor("- [ ] a\n- [ ] b\n")
        select(tv, "b"); tab(tv)
        #expect(tv.string == "- [ ] a\n\t- [ ] b\n")
        #expect(tv.selectedRange().location == ("- [ ] a\n\t- [ ] " as NSString).length)
    }

    @Test func siblingCanBeSeparatedByBlankLinesAndDeeperItems() {
        let tv = makeEditor("- a\n\t- a1\n\n- b\n")
        select(tv, "b"); tab(tv)
        #expect(tv.string == "- a\n\t- a1\n\n\t- b\n")
    }

    @Test func tabIndentsEverySelectedItem() {
        let tv = makeEditor("- a\n- b\n- c\n- d\n")
        select(tv, "b", through: "d"); tab(tv)
        #expect(tv.string == "- a\n\t- b\n\t- c\n\t- d\n")
        // The selection still covers b through d.
        #expect((tv.string as NSString).substring(with: tv.selectedRange()) == "b\n\t- c\n\t- d")
    }

    @Test func childrenMoveWithTheirParent() {
        let tv = makeEditor("- a\n- b\n\t- b1\n\t\t- b2\n- c\n")
        select(tv, "b"); tab(tv)
        #expect(tv.string == "- a\n\t- b\n\t\t- b1\n\t\t\t- b2\n- c\n")
        select(tv, "b"); backtab(tv)
        #expect(tv.string == "- a\n- b\n\t- b1\n\t\t- b2\n- c\n")
    }

    @Test func shiftTabOutdentsEverySelectedItem() {
        let tv = makeEditor("- a\n\t- b\n  - c\n- d\n")
        select(tv, "b", through: "d"); backtab(tv)
        #expect(tv.string == "- a\n- b\n- c\n- d\n")
    }

    @Test func tabStopsAtTheMaximumNestingLevel() {
        let tv = makeEditor("- a\n\t- b\n\t\t- c\n\t\t\t- d\n\t\t\t- e\n")
        select(tv, "e"); tab(tv)
        #expect(tv.string == "- a\n\t- b\n\t\t- c\n\t\t\t- d\n\t\t\t- e\n")
    }

    @Test func oneUndoRevertsAMultiLineIndent() {
        let tv = makeEditor("- a\n- b\n- c\n")
        select(tv, "b", through: "c"); tab(tv)
        #expect(tv.string == "- a\n\t- b\n\t- c\n")
        tv.undoManager?.undo()
        #expect(tv.string == "- a\n- b\n- c\n")
    }
}

@Suite("Ta Da fork — wiki-link aliases")
struct WikiLinkAliasTests {

    private struct Titles: WikiLinkResolver {
        func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? {
            displayName == "Target" ? WikiLinkResolution(id: displayName, exists: true) : nil
        }
    }

    @Test func aliasedLinkResolvesAndLinksByItsTarget() {
        var config = MarkdownEditorConfiguration.default
        config.services = MarkdownEditorServices(wikiLinks: Titles())
        let storage = "See [[Target|the alias]]."
        let display = WikiLinkService.makeDisplayState(from: storage)
        let attrs = MarkdownASTStyler.styleAttributes(
            text: display.display, fontName: NSFont.systemFont(ofSize: 14).fontName, fontSize: 14,
            wikiLinkIDProvider: { range in display.metadata[WikiLinkService.RangeKey(range)]?.id },
            configuration: config
        )
        #expect(attrs.contains { $0.attributes[.link] as? String == "Target" })
    }
}

@MainActor
@Suite("Ta Da fork — undo and redo reach the binding")
struct UndoBindingTests {

    private final class Box { var text = "" }

    @Test func undoAndRedoArePublished() async throws {
        _ = NSApplication.shared
        let box = Box()
        box.text = "First line.\n"
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        #expect(textView.textLayoutManager != nil, "the AppKit bug is TextKit 2 only")
        textView.isEditable = true
        textView.allowsUndo = true
        textView.configuration = .default
        let coordinator = NativeTextViewCoordinator(
            text: Binding(get: { box.text }, set: { box.text = $0 }), fontName: "SF Pro Text", fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        coordinator.documentId = "A"
        coordinator.textView = textView
        textView.delegate = coordinator
        textView.string = box.text
        coordinator.lastSyncedText = box.text
        coordinator.lastComputedStorage = box.text
        coordinator.previousDisplayLength = (box.text as NSString).length

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("- [ ] ", replacementRange: textView.selectedRange())
        try await Task.sleep(for: .milliseconds(50))
        #expect(box.text == "- [ ] First line.\n")

        textView.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(50))
        #expect(textView.string == "First line.\n")
        #expect(box.text == "First line.\n")

        textView.undoManager?.redo()
        try await Task.sleep(for: .milliseconds(50))
        #expect(box.text == "- [ ] First line.\n")
    }
}


@MainActor
@Suite("Ta Da fork — slash commands")
struct SlashCommandTests {

    private final class Recorder {
        var text = ""
        var states: [SlashCommandState?] = []
        var keys: [InlinePreviewKey] = []
        var last: SlashCommandState? { states.last ?? nil }
    }

    private func makeEditor(_ text: String, _ recorder: Recorder) -> (NativeTextView, SlashCommandProxy) {
        _ = NSApplication.shared
        recorder.text = text
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.isEditable = true
        textView.allowsUndo = true
        textView.configuration = .default
        let coordinator = NativeTextViewCoordinator(
            text: Binding(get: { recorder.text }, set: { recorder.text = $0 }), fontName: "SF Pro Text", fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        coordinator.documentId = "A"
        coordinator.textView = textView
        coordinator.onSlashCommandChange = { recorder.states.append($0) }
        coordinator.onSlashCommandKey = { recorder.keys.append($0); return true }
        textView.delegate = coordinator
        textView.string = text
        coordinator.lastSyncedText = text
        coordinator.lastComputedStorage = text
        coordinator.previousDisplayLength = (text as NSString).length
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        objc_setAssociatedObject(textView, &Self.coordinatorKey, coordinator, .OBJC_ASSOCIATION_RETAIN)
        let proxy = SlashCommandProxy()
        proxy.coordinator = coordinator
        return (textView, proxy)
    }
    private static var coordinatorKey = 0

    private func type(_ tv: NSTextView, _ text: String) async throws {
        for character in text { tv.insertText(String(character), replacementRange: tv.selectedRange()) }
        try await Task.sleep(for: .milliseconds(30))
    }

    @Test func theProxyReachesTheTextView() {
        let (tv, proxy) = makeEditor("Intro\n", Recorder())
        #expect(proxy.textView === tv)
    }

    @Test func slashAtLineStartOpensAndFollowsTheQuery() async throws {
        let recorder = Recorder()
        let (tv, _) = makeEditor("Intro\n", recorder)
        try await type(tv, "/ta")
        let state = try #require(recorder.last)
        #expect(state.query == "ta")
        #expect(state.range == NSRange(location: 6, length: 3))
        #expect(state.isAtLineStart && !state.followsBlankLine)
    }

    @Test func slashAfterTextIsMidLineAndInsideAWordIsIgnored() async throws {
        let recorder = Recorder()
        let (tv, _) = makeEditor("Ship it ", recorder)
        try await type(tv, "/bo")
        #expect(recorder.last?.isAtLineStart == false)

        let other = Recorder()
        let (url, _) = makeEditor("and", other)
        try await type(url, "/or")
        #expect(other.states.isEmpty)
    }

    @Test func spaceOrLeavingTheQueryCloses() async throws {
        let recorder = Recorder()
        let (tv, _) = makeEditor("", recorder)
        try await type(tv, "/h")
        #expect(recorder.last?.query == "h")
        try await type(tv, " ")
        #expect(recorder.states.last! == nil)
    }

    @Test func keysRouteToTheMenuAndEscapeCloses() async throws {
        let recorder = Recorder()
        let (tv, _) = makeEditor("", recorder)
        try await type(tv, "/")
        tv.doCommand(by: #selector(NSResponder.moveDown(_:)))
        tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(recorder.keys == [.moveDown, .confirm])
        tv.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        try await Task.sleep(for: .milliseconds(30))
        #expect(recorder.states.last! == nil)
        #expect(tv.string == "/")
        // Closed: typing more doesn't reopen it until a new `/`.
        try await type(tv, "h")
        #expect(recorder.states.last! == nil)
    }

    @Test func insertReplacesTheQueryAsOneUndoStep() async throws {
        let recorder = Recorder()
        let (tv, proxy) = makeEditor("Intro\n", recorder)
        try await type(tv, "/bo")
        proxy.insert("****", selecting: NSRange(location: 2, length: 0))
        try await Task.sleep(for: .milliseconds(30))
        #expect(tv.string == "Intro\n****")
        #expect(tv.selectedRange() == NSRange(location: 8, length: 0))
        #expect(recorder.text == "Intro\n****")
        #expect(recorder.states.last! == nil)
        tv.undoManager?.undo()
        #expect(tv.string == "Intro\n/bo")
    }

    @Test func slashInsideCodeIsIgnored() async throws {
        let recorder = Recorder()
        let (tv, _) = makeEditor("```\n\n```\n", recorder)
        tv.setSelectedRange(NSRange(location: 4, length: 0))
        try await type(tv, "/")
        #expect(recorder.states.isEmpty)
    }
}

@MainActor
@Suite("Ta Da fork — task marker menu hook")
struct TaskMarkerMenuHookTests {

    /// An editor showing `text` and a mouse event of `type` on its first box. The window and
    /// coordinator come back too, so the test keeps them alive.
    private func editor(_ text: String, click type: NSEvent.EventType) throws
        -> (tv: NativeTextView, event: NSEvent, window: NSWindow, coordinator: NativeTextViewCoordinator) {
        _ = NSApplication.shared
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text), fontName: "SF Pro", fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.isEditable = true
        tv.delegate = coordinator
        let scrollView = NSScrollView(frame: tv.frame)
        scrollView.documentView = tv
        let window = NSWindow(contentRect: tv.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scrollView
        let bridge = LayoutBridge(try #require(tv.textLayoutManager))
        coordinator.layoutBridge = bridge
        tv.layoutBridge = bridge
        coordinator.textView = tv
        coordinator.rebuildTextStorageAndStyle(tv, from: text)
        coordinator.lastSyncedText = text
        coordinator.lastComputedStorage = text
        coordinator.previousDisplayLength = (text as NSString).length
        tv.setSelectedRange(NSRange(location: 0, length: 0))

        let storage = try #require(tv.textStorage)
        var box = NSRange(location: NSNotFound, length: 0)
        storage.enumerateAttribute(.taskCheckbox, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value != nil, box.location == NSNotFound { box = range }
        }
        try #require(box.location != NSNotFound)
        let anchor = try #require(tv.layoutBridge).boundingRect(forCharacterRange: box, in: try #require(tv.textContainer))
        let size = TaskCheckboxGeometry.size(for: tv.baseFont, style: tv.configuration.taskCheckbox)
        let containerPoint = CGPoint(x: TaskCheckboxGeometry.boxX(contentX: anchor.minX, size: size,
                                                                  style: tv.configuration.taskCheckbox) + size / 2,
                                     y: anchor.midY)
        let viewPoint = CGPoint(x: containerPoint.x + tv.textContainerOrigin.x, y: containerPoint.y + tv.textContainerOrigin.y)
        let event = try #require(NSEvent.mouseEvent(
            with: type, location: tv.convert(viewPoint, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        return (tv, event, window, coordinator)
    }

    @Test func rightClickOnABoxGoesToTheHookAndSetsTheMarkerOnce() throws {
        let (tv, event, window, coordinator) = try editor("Intro\n\n- [ ] a\n", click: .rightMouseDown)
        var requests: [TaskMarkerMenuRequest] = []
        tv.onTaskMarkerMenu = { requests.append($0) }

        #expect(tv.menu(for: event) == nil)
        let request = try #require(requests.first)
        #expect(request.marker == " ")
        request.setMarker("x")
        #expect(tv.string == "Intro\n\n- [x] a\n")
        // The box changed since the request, so a second pick does nothing.
        request.setMarker("/")
        #expect(tv.string == "Intro\n\n- [x] a\n")
        withExtendedLifetime((window, coordinator)) {}
    }

    @Test func aClickOnAQuotedBoxTogglesIt() throws {
        let (tv, event, window, coordinator) = try editor("Intro\n\n> - [ ] a\n", click: .leftMouseDown)
        #expect(tv.toggleTaskCheckboxIfHit(event: event) == true)
        #expect(tv.string == "Intro\n\n> - [x] a\n")
        withExtendedLifetime((window, coordinator)) {}
    }
}
