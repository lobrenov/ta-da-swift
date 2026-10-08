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

    @Test func tabAndShiftTabWorkAfterAQuotesMarkers() {
        let tv = makeEditor("> [!note] T\n> - a\n> - b\n")
        select(tv, "b"); tab(tv)
        #expect(tv.string == "> [!note] T\n> - a\n> \t- b\n")
        backtab(tv)
        #expect(tv.string == "> [!note] T\n> - a\n> - b\n")
        select(tv, "a"); tab(tv)
        #expect(tv.string == "> [!note] T\n> - a\n> - b\n")
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

private let testCalloutStyle = CalloutStyle(
    tint: { _ in .systemBlue }, drawIcon: { _, _, _ in }, titleColor: .labelColor, bodyColor: .textColor,
    foldColor: .gray, targetColor: .systemRed, fillOpacity: 0.09, ringOpacity: 0.24)

@Suite("Ta Da fork — callouts")
struct CalloutTests {

    private func header(_ line: String) -> [String]? {
        let ns = line as NSString
        let quote = QuoteLine.parse(NSRange(location: 0, length: ns.length), of: ns)
        return CalloutHeader.parse(ns, content: quote.content).map {
            [ns.substring(with: $0.type), ns.substring(with: $0.fold), ns.substring(with: $0.title)]
        }
    }

    private func callouts(_ text: String) -> [[Int]] {
        let ns = text as NSString
        let lines = QuoteLine.lines(in: NSRange(location: 0, length: ns.length), of: ns)
        return Callout.find(in: lines, of: ns).map { [$0.level, $0.first, $0.last] }
    }

    private func attrs(_ text: String, caret: Int = -1, folds: [String: Bool] = [:], callouts: Bool = true) -> [StyledRange] {
        var config = MarkdownEditorConfiguration.default
        if callouts { config.callouts = testCalloutStyle }
        config.calloutFoldOverrides = folds
        return MarkdownASTStyler.styleAttributes(text: text, fontName: NSFont.systemFont(ofSize: 14).fontName,
                                                 fontSize: 14, caretLocation: caret, configuration: config)
    }

    private func calloutLines(_ attrs: [StyledRange]) -> [CalloutLine] {
        attrs.compactMap { $0.attributes[.calloutLine] as? CalloutLine }
    }

    /// The last value styled for `key` over exactly `range`.
    private func last(_ key: NSAttributedString.Key, at range: NSRange, in attrs: [StyledRange]) -> Any? {
        attrs.last { $0.range == range && $0.attributes[key] != nil }?.attributes[key]
    }

    @Test func titleLinesParse() {
        #expect(header("> [!note] Title") == ["note", "", "Title"])
        #expect(header("> [!FAQ]+ Why plain files?  ") == ["FAQ", "+", "Why plain files?"])
        #expect(header(">[!tip]-") == ["tip", "-", ""])
        #expect(header("> [!note]Title") == nil)
        #expect(header("> [!] x") == nil)
        #expect(header("> [note] x") == nil)
    }

    @Test func calloutsNestAndEndWithTheirLevel() {
        #expect(callouts("> [!note] A\n> body\n> > [!quote] B\n> > inner\n> after\n") == [[1, 0, 4], [2, 2, 3]])
    }

    @Test func onlyTheFirstLineAtALevelOpensOne() {
        #expect(callouts("> text\n> [!note] not a title\n").isEmpty)
        #expect(callouts("> [!a]\n> [!b]\n") == [[1, 0, 1]])
    }

    @Test func eachLineGetsItsPanelAndTheTitleHidesItsSyntaxBehindTheIcon() throws {
        let styled = attrs("> [!warning] Two\n> body\n\nafter")
        let lines = calloutLines(styled)
        try #require(lines.count == 2)
        #expect(lines[0].isTitle && lines[0].panels.first?.opens == true && lines[0].title?.type == "warning")
        #expect(lines[1].panels.first?.opens == false && lines[1].panels.first?.bottomPadding == 11)
        // `[!warning] ` is hidden; its last character makes room for the 16pt icon and 8pt gap.
        #expect(last(.kern, at: NSRange(location: 12, length: 1), in: styled) as? CGFloat == 24)
    }

    @Test func theCaretOnTheTitleLineShowsItsSyntax() {
        let styled = attrs("> [!warning] Two\n> body", caret: 5)
        #expect(calloutLines(styled).first?.title == nil)
        #expect(last(.kern, at: NSRange(location: 12, length: 1), in: styled) == nil)
    }

    @Test func anUntitledCalloutMakesRoomForItsName() throws {
        let kern = try #require(last(.kern, at: NSRange(location: 7, length: 1), in: attrs("> [!faq]\n> x")) as? CGFloat)
        #expect(kern > 24)
        #expect(calloutLines(attrs("> [!faq]\n> x")).first?.title?.name == "Faq")
    }

    @Test func aFoldedBodyHidesUntilTheCaretIsInIt() {
        let text = "> [!tip]- Hidden\n> body\n\nafter"
        func bodyHeight(_ styled: [StyledRange]) -> CGFloat? {
            (styled.last { $0.range.location == 17 && $0.attributes[.paragraphStyle] != nil }?
                .attributes[.paragraphStyle] as? NSParagraphStyle)?.maximumLineHeight
        }
        #expect(bodyHeight(attrs(text, caret: 26)) == 0.1)
        #expect(calloutLines(attrs(text, caret: 26)).first?.isFolded == true)
        #expect(bodyHeight(attrs(text, caret: 20)) != 0.1)
        #expect(bodyHeight(attrs(text, caret: 26, folds: ["> [!tip]- Hidden": false])) != 0.1)
    }

    @Test func plainQuotesAndDisabledCalloutsStayQuotes() {
        #expect(calloutLines(attrs("> quote\n> more")).isEmpty)
        #expect(calloutLines(attrs("> [!note] A\n> b", callouts: false)).isEmpty)
        #expect(attrs("> [!note] A\n> b", callouts: false).contains { $0.attributes[.blockquoteLevel] != nil })
    }
}

@Suite("Ta Da fork — inline bubbles")
struct InlineBubbleTests {

    private struct Mark: MarkdownExtension {
        var id: String { HighlightExtension.identifier }
        var inline: InlineSyntax? { InlineSyntax(open: "==", close: "==") }
        func contentAttributes(theme: MarkdownEditorTheme) -> [NSAttributedString.Key: Any] { [:] }
        func html(childrenHTML: String) -> String { childrenHTML }
        func bubble(theme: MarkdownEditorTheme) -> InlineBubble? { InlineBubble(fill: .yellow, horizontalPadding: 4, margin: -1) }
    }

    private func attrs(_ text: String, caret: Int = -1) -> [StyledRange] {
        var config = MarkdownEditorConfiguration.default
        config.inlineCode.bubble = InlineBubble(fill: .gray, ring: .black, text: .red, horizontalPadding: 6, margin: 1)
        config.extensions = [Mark()]
        return MarkdownASTStyler.styleAttributes(text: text, fontName: NSFont.systemFont(ofSize: 14).fontName,
                                                 fontSize: 14, caretLocation: caret, configuration: config)
    }

    private func kern(at location: Int, in attrs: [StyledRange]) -> CGFloat? {
        attrs.last { $0.range == NSRange(location: location, length: 1) && $0.attributes[.kern] != nil }?
            .attributes[.kern] as? CGFloat
    }

    @Test func inlineCodeIsABubbleWhoseHiddenMarkersHoldItsPadding() {
        let styled = attrs("a `b` c")
        #expect(styled.contains { $0.range == NSRange(location: 2, length: 3) && $0.attributes[.markdownInlineBubble] is InlineBubbleSpan })
        #expect(styled.contains { $0.range == NSRange(location: 3, length: 1) && $0.attributes[.foregroundColor] as? NSColor == .red })
        #expect(!styled.contains { $0.attributes[.backgroundColor] != nil })
        #expect(kern(at: 2, in: styled) == 7 && kern(at: 4, in: styled) == 7)
        #expect(kern(at: 2, in: attrs("a `b` c", caret: 3)) == nil)
    }

    @Test func anExtensionSpanCanBeABubble() {
        let styled = attrs("a ==b== c")
        #expect(styled.contains { $0.range == NSRange(location: 2, length: 5) && $0.attributes[.markdownInlineBubble] is InlineBubbleSpan })
        #expect(kern(at: 3, in: styled) == 3 && kern(at: 6, in: styled) == 3)
    }
}

@MainActor
@Suite("Ta Da fork — callout menu and folding")
struct CalloutInteractionTests {

    /// An editor showing `text` with callouts on, the caret at 0.
    private func editor(_ text: String) throws -> (tv: NativeTextView, window: NSWindow, coordinator: NativeTextViewCoordinator) {
        _ = NSApplication.shared
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text), fontName: "SF Pro", fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        coordinator.configuration.callouts = testCalloutStyle
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.configuration = coordinator.configuration
        tv.isEditable = true
        tv.allowsUndo = true
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
        return (tv, window, coordinator)
    }

    /// A mouse event on the icon of the callout titled at `location`.
    private func iconEvent(_ type: NSEvent.EventType, titleAt location: Int, in tv: NativeTextView, window: NSWindow) throws -> NSEvent {
        let storage = try #require(tv.textStorage)
        let line = try #require(storage.attribute(.calloutLine, at: location, effectiveRange: nil) as? CalloutLine)
        let title = try #require(line.title)
        let lineRange = (storage.string as NSString).lineRange(for: NSRange(location: location, length: 0))
        let rect = try #require(tv.layoutBridge).boundingRect(forCharacterRange: lineRange, in: try #require(tv.textContainer))
        let viewPoint = CGPoint(x: title.iconX + title.iconSize / 2 + tv.textContainerOrigin.x,
                                y: rect.midY + tv.textContainerOrigin.y)
        return try #require(NSEvent.mouseEvent(
            with: type, location: tv.convert(viewPoint, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    @Test func rightClickOnATitleGoesToTheHookAndEditsOnce() throws {
        let (tv, window, coordinator) = try editor("Intro\n\n> [!note] T\n> body\n")
        var requests: [CalloutMenuRequest] = []
        tv.onCalloutMenu = { requests.append($0) }

        #expect(tv.menu(for: try iconEvent(.rightMouseDown, titleAt: 7, in: tv, window: window)) == nil)
        let request = try #require(requests.first)
        #expect(request.type == "note" && request.fold == nil)
        #expect(tv.calloutMenuTarget == 7)
        request.setFold("-")
        #expect(tv.string == "Intro\n\n> [!note]- T\n> body\n")
        // The title line changed since the request, so a second pick does nothing.
        request.setType("tip")
        #expect(tv.string == "Intro\n\n> [!note]- T\n> body\n")
        request.close()
        #expect(tv.calloutMenuTarget == nil)
        withExtendedLifetime((window, coordinator)) {}
    }

    @Test func aTypeReplacesOnlyTheTypeAndUndoesInOneStep() throws {
        let (tv, window, coordinator) = try editor("Intro\n\n> [!note]+ T\n> body\n")
        var requests: [CalloutMenuRequest] = []
        tv.onCalloutMenu = { requests.append($0) }
        _ = tv.menu(for: try iconEvent(.rightMouseDown, titleAt: 7, in: tv, window: window))
        try #require(requests.first).setType("warning")
        #expect(tv.string == "Intro\n\n> [!warning]+ T\n> body\n")
        tv.undoManager?.undo()
        #expect(tv.string == "Intro\n\n> [!note]+ T\n> body\n")
        withExtendedLifetime((window, coordinator)) {}
    }

    @Test func aClickOnTheIconFoldsOnScreenOnly() throws {
        let text = "Intro\n\n> [!note]+ T\n> body\n"
        let (tv, window, coordinator) = try editor(text)
        #expect(tv.toggleCalloutFoldIfHit(event: try iconEvent(.leftMouseDown, titleAt: 7, in: tv, window: window)))
        #expect(coordinator.configuration.calloutFoldOverrides == ["> [!note]+ T": true])
        let title = try #require(tv.textStorage?.attribute(.calloutLine, at: 7, effectiveRange: nil) as? CalloutLine)
        #expect(title.isFolded)
        #expect(tv.string == text)
        // Opening it again matches the file, so the override goes.
        #expect(tv.toggleCalloutFoldIfHit(event: try iconEvent(.leftMouseDown, titleAt: 7, in: tv, window: window)))
        #expect(coordinator.configuration.calloutFoldOverrides.isEmpty)
        withExtendedLifetime((window, coordinator)) {}
    }

    @Test func aCalloutThatDoesNotFoldIgnoresTheClick() throws {
        let (tv, window, coordinator) = try editor("Intro\n\n> [!note] T\n> body\n")
        #expect(!tv.toggleCalloutFoldIfHit(event: try iconEvent(.leftMouseDown, titleAt: 7, in: tv, window: window)))
        withExtendedLifetime((window, coordinator)) {}
    }
}

@Suite("Ta Da fork — inline code edges")
struct InlineCodeEdgeTests {

    @Test func aCaretAfterTheClosingBacktickIsOutsideTheCode() {
        let text = "- a `x`"
        #expect(MarkdownDetection.isInsideCodeBlock(location: 6, in: text))
        #expect(!MarkdownDetection.isInsideCodeBlock(location: 7, in: text))
    }

    @MainActor
    @Test func returnAfterInlineCodeContinuesTheList() {
        let tv = NSTextView()
        tv.string = "- [ ] a `x`"
        let end = NSRange(location: 11, length: 0)
        #expect(!MarkdownLists.handleInsertion(textView: tv, affectedCharRange: end, replacementString: "\n",
                                               isInsideCodeBlock: MarkdownDetection.isInsideCodeBlock(location: 11, in: tv.string)))
        #expect(tv.string == "- [ ] a `x`\n- [ ] ")
    }
}

@MainActor
@Suite("Ta Da fork — bubble and callout geometry")
struct FragmentGeometryTests {

    /// The laid-out fragments of an editor showing `text`, the caret at 0.
    private func fragments(_ text: String, _ configure: (inout MarkdownEditorConfiguration) -> Void) throws
        -> (fragments: [MarkdownTextLayoutFragment], keep: Any) {
        _ = NSApplication.shared
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text), fontName: "SF Pro", fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        configure(&coordinator.configuration)
        let tv = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.configuration = coordinator.configuration
        tv.delegate = coordinator
        let scrollView = NSScrollView(frame: tv.frame)
        scrollView.documentView = tv
        let window = NSWindow(contentRect: tv.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scrollView
        let layoutManager = try #require(tv.textLayoutManager)
        let layoutDelegate = MarkdownLayoutManagerDelegate()
        coordinator.layoutDelegate = layoutDelegate
        layoutManager.delegate = layoutDelegate
        let bridge = LayoutBridge(layoutManager)
        coordinator.layoutBridge = bridge
        tv.layoutBridge = bridge
        coordinator.textView = tv
        coordinator.rebuildTextStorageAndStyle(tv, from: text)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        var fragments: [MarkdownTextLayoutFragment] = []
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: []) {
            if let fragment = $0 as? MarkdownTextLayoutFragment { fragments.append(fragment) }
            return true
        }
        return (fragments, (window, coordinator, layoutDelegate))
    }

    @Test func aBubblePadsBothSidesOfItsTextEqually() throws {
        let (fragments, keep) = try fragments("Intro\n\nab `cd` ef") {
            $0.inlineCode.bubble = InlineBubble(fill: .gray, horizontalPadding: 6, margin: 1)
        }
        let fragment = try #require(fragments.last)
        let shape = try #require(fragment.inlineBubbleShapes(at: .zero).first)
        let font = try #require(fragment.textStorage?.attribute(.font, at: 11, effectiveRange: nil) as? NSFont)
        let content = ("cd" as NSString).size(withAttributes: [.font: font]).width
        // Each hidden backtick takes padding + margin; the bubble stops a margin short of each.
        #expect(abs(shape.rect.width - (content + 12)) < 0.5)
        withExtendedLifetime(keep) {}
    }

    @Test func aQuotedItemNestsOneLevelPerTabAndStaysPutUnderTheCaret() throws {
        let text = "Intro\n\n> [!note] T\n> - a\n> \t- b\n"
        let (_, keep) = try fragments(text) { $0.callouts = testCalloutStyle }
        let (window, coordinator, _) = try #require(keep as? (NSWindow, NativeTextViewCoordinator, MarkdownLayoutManagerDelegate))
        let tv = try #require(coordinator.textView as? NativeTextView)
        let ns = text as NSString
        func x(_ needle: String) throws -> CGFloat {
            try #require(tv.layoutBridge).boundingRect(forCharacterRange: ns.range(of: needle), in: try #require(tv.textContainer)).minX
        }
        let a = try x("a"), b = try x("b")
        #expect(abs(b - a - 27.5) < 0.5)
        tv.setSelectedRange(NSRange(location: NSMaxRange(ns.range(of: "b")), length: 0))
        #expect(abs(try x("b") - b) < 0.5)
        withExtendedLifetime((window, coordinator)) {}
    }

    @Test func aCalloutEndingTheDocumentDrawsItsBottomPadding() throws {
        let (fragments, keep) = try fragments("Intro\n\n> [!note] T\n> body") { $0.callouts = testCalloutStyle }
        let last = try #require(fragments.last)
        let line = try #require(last.textLineFragments.last)
        #expect(last.renderingSurfaceBounds.maxY >= line.typographicBounds.maxY + 11)
        withExtendedLifetime(keep) {}
    }
}


@MainActor
@Suite("Ta Da fork — auto-closed pairs")
struct AutoPairTests {

    private func makeEditor(_ text: String = "", configure: (inout MarkdownEngine.ListStyle) -> Void = { _ in }) -> NativeTextView {
        _ = NSApplication.shared
        let textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.isEditable = true
        textView.allowsUndo = true
        var configuration = MarkdownEditorConfiguration.default
        configuration.lists.autoCloseFormattingEnabled = true
        configure(&configuration.lists)
        textView.configuration = configuration
        let coordinator = NativeTextViewCoordinator(
            text: .constant(text), fontName: "SF Pro Text", fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        coordinator.configuration = configuration
        coordinator.textView = textView
        textView.delegate = coordinator
        textView.string = text
        coordinator.lastSyncedText = text
        coordinator.lastComputedStorage = text
        coordinator.previousDisplayLength = (text as NSString).length
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        objc_setAssociatedObject(textView, &Self.coordinatorKey, coordinator, .OBJC_ASSOCIATION_RETAIN)
        return textView
    }
    private static var coordinatorKey = 0

    private func type(_ tv: NSTextView, _ text: String) {
        for character in text { tv.insertText(String(character), replacementRange: tv.selectedRange()) }
    }

    /// The text with `|` at the caret.
    private func shown(_ tv: NSTextView) -> String {
        (tv.string as NSString).replacingCharacters(in: tv.selectedRange(), with: "|")
    }

    private func typed(_ text: String, configure: (inout MarkdownEngine.ListStyle) -> Void = { _ in }) -> String {
        let tv = makeEditor(configure: configure)
        type(tv, text)
        return shown(tv)
    }

    @Test func anAddedCloserIsSteppedOver() {
        let tv = makeEditor()
        type(tv, "(")
        #expect(shown(tv) == "(|)")
        type(tv, "test)")
        #expect(shown(tv) == "(test)|")
        #expect(typed("((a))") == "((a))|")
        #expect(typed("{x} [y]") == "{x} [y]|")
    }

    @Test func aCloserTheEditorDidNotAddIsTyped() {
        let tv = makeEditor("(a)")
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        type(tv, ")")
        #expect(shown(tv) == "(a)|)")
    }

    @Test func leavingThePairForgetsItsCloser() {
        let tv = makeEditor()
        type(tv, "(a")
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        type(tv, ")")
        #expect(shown(tv) == "(a)|)")
    }

    @Test func undoForgetsThePairs() {
        let tv = makeEditor("x")
        type(tv, "(a")
        tv.undoManager?.undo()
        #expect(tv.autoPairs.isEmpty)
    }

    @Test func formattingMarkersPairAndAreSteppedOver() {
        #expect(typed("a **b** c") == "a **b** c|")
        #expect(typed("*i* _u_ __s__") == "*i* _u_ __s__|")
        #expect(typed("~~gone~~ ==hi==") == "~~gone~~ ==hi==|")
        #expect(typed("`code` then") == "`code` then|")
        let tv = makeEditor("a ")
        type(tv, "**")
        #expect(shown(tv) == "a **|**")
    }

    @Test func markersStayPlainWhereTheyCantFormat() {
        #expect(typed("* item") == "* item|")
        #expect(typed("snake_case") == "snake_case|")
        #expect(typed("2*3") == "2*3|")
        #expect(typed("2 * 3") == "2 * 3|")
        #expect(typed("a == b") == "a == b|")
        #expect(typed("~") == "~|")
    }

    @Test func aRunPastTheLongestMarkerStaysUnpaired() {
        #expect(typed("***") == "***|")
        #expect(typed("```") == "```|")
        #expect(typed("~~~") == "~~~|")
        #expect(typed("===") == "===|")
    }

    @Test func markersDontPairInCode() {
        let tv = makeEditor("```\nx \n```")
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        type(tv, "*")
        #expect(shown(tv) == "```\nx *|\n```")
    }

    @Test func wikiLinksCompleteAndAreSteppedOver() {
        #expect(typed("[[Note]] ") == "[[Note]] |")
        #expect(typed("![[Image]]") == "![[Image]]|")
        #expect(typed("[[Note]]", configure: { $0.autoClosePairsEnabled = false }) == "[[Note]]|")
    }

    @Test func eachToggleTurnsItsPairsOff() {
        #expect(typed("(a", configure: { $0.autoClosePairsEnabled = false }) == "(a|")
        #expect(typed("**b", configure: { $0.autoCloseFormattingEnabled = false }) == "**b|")
        #expect(typed("[[a", configure: { $0.autoClosePairsEnabled = false; $0.autoCloseWikiLinksEnabled = false }) == "[[a|")
    }
}
