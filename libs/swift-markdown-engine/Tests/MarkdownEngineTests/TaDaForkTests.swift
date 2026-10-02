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

    @Test func checkboxAttributeCarriesTheMarkerAndOnlyDoneStrikes() {
        func attrs(_ text: String) -> [StyledRange] {
            MarkdownASTStyler.styleAttributes(text: text, fontName: NSFont.systemFont(ofSize: 14).fontName, fontSize: 14)
        }
        let cancelled = attrs("- [-] dropped")
        #expect(cancelled.contains { $0.attributes[.taskCheckbox] as? String == "-" })
        #expect(!cancelled.contains { $0.attributes[.strikethroughStyle] != nil })
        let done = attrs("- [x] finished")
        #expect(done.contains { $0.attributes[.taskCheckbox] as? String == "x" })
        #expect(done.contains { $0.attributes[.strikethroughStyle] != nil })
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
