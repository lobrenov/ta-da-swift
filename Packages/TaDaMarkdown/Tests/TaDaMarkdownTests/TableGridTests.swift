//
//  TableGridTests.swift
//  TaDaMarkdownTests
//
//  Ta Da fork: the live table grid on the Mac: cells as editors over the hidden source, writes as one padded splice,
//  one undo history, and the caret stepping over the source.
//

#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import TaDaMarkdown

@MainActor
struct GridHarness {
    let coordinator: NativeTextViewCoordinator
    let host: NativeTextView
    let window: NSWindow
    private let layoutDelegate = MarkdownLayoutManagerDelegate()

    init(_ text: String) {
        _ = NSApplication.shared
        var config = MarkdownEditorConfiguration.default
        config.liveTables = true
        coordinator = NativeTextViewCoordinator(
            text: .constant(text), fontName: NSFont.systemFont(ofSize: 14).fontName, fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil
        )
        coordinator.configuration = config
        host = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        host.isEditable = true
        host.allowsUndo = true
        host.configuration = config
        host.baseFont = NSFont.systemFont(ofSize: 14)
        host.textContainer?.lineFragmentPadding = 0
        let tlm = host.textLayoutManager!
        tlm.delegate = layoutDelegate
        coordinator.layoutDelegate = layoutDelegate
        let bridge = LayoutBridge(tlm)
        host.layoutBridge = bridge
        coordinator.layoutBridge = bridge
        host.delegate = coordinator
        coordinator.textView = host
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.contentView = host
        coordinator.rebuildTextStorageAndStyle(host, from: text)
        coordinator.lastSyncedText = text
        coordinator.lastComputedStorage = text
        coordinator.previousDisplayLength = (text as NSString).length
    }

    var grid: TableGridView { host.tableGrid(ordinal: 0)! }

    func cell(_ row: Int, _ column: Int) -> NativeTextView { grid.editor(row: row, column: column)!.textView }

    /// Types `text` into a cell the way a keyboard does.
    func type(_ text: String, row: Int, column: Int) {
        grid.focus(row: row, column: column)
        for character in text {
            cell(row, column).insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
    }
}

@MainActor
@Suite("Live table grid")
struct TableGridTests {
    static let source = "Before\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nAfter\n"

    @Test func aTableBecomesAGridOfCellEditors() {
        let h = GridHarness(Self.source)
        #expect(h.grid.editors.count == 2)
        #expect(h.grid.editors[0].count == 2)
        #expect(h.cell(0, 0).string == "a")
        #expect(h.cell(1, 1).string == "2")
        #expect(h.grid.frame.height > 0)
    }

    @Test func typingInACellRewritesTheTableLinesPadded() {
        let h = GridHarness(Self.source)
        h.type("xyz", row: 1, column: 0)
        #expect(h.cell(1, 0).string == "1xyz")
        #expect(h.host.string == "Before\n\n| a    | b   |\n| ---- | --- |\n| 1xyz | 2   |\n\nAfter\n")
    }

    @Test func markdownTypedInACellIsKept() {
        let h = GridHarness(Self.source)
        h.type("**b**", row: 1, column: 1)
        #expect(h.host.string.contains("| 2**b** |"))
    }

    @Test func aWikiLinkAndAChecklistTypeIntoACell() {
        let h = GridHarness(Self.source)
        h.type("[[Note]]", row: 1, column: 0)
        #expect(h.host.string.contains("1[[Note]]"))
        h.type("- [ ] x", row: 1, column: 1)
        #expect(h.host.string.contains("2- [ ] x"))
    }

    @Test func returnInACellMakesABr() {
        let h = GridHarness(Self.source)
        h.grid.focus(row: 1, column: 0)
        h.cell(1, 0).insertNewline(nil)
        h.cell(1, 0).insertText("z", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(h.host.string.contains("| 1<br>z |"))
        #expect(h.cell(1, 0).string == "1\nz")
    }

    @Test func listContinuesInACell() {
        let h = GridHarness("| a |\n|---|\n|  |\n")
        h.type("- a", row: 1, column: 0)
        h.cell(1, 0).insertNewline(nil)
        #expect(h.cell(1, 0).string == "- a\n- ")
        #expect(h.host.string.contains("- a<br>- "))
    }

    @Test func typingCoalescesIntoOneUndoStepAndUndoRestoresTheTableAndCaret() {
        let h = GridHarness(Self.source)
        h.type("xyz", row: 1, column: 0)
        let edited = h.host.string
        h.host.undoManager?.undo()
        #expect(h.host.string == Self.source)
        #expect(h.cell(1, 0).string == "1")
        #expect(h.cell(1, 0).hasEditingFocus)
        h.host.undoManager?.redo()
        #expect(h.host.string == edited)
        #expect(h.cell(1, 0).string == "1xyz")
        #expect(h.host.undoManager?.canUndo == true)
    }

    @Test func theCaretNeverRestsInTheSource() {
        let h = GridHarness(Self.source)
        let ns = Self.source as NSString
        let start = ns.range(of: "| a").location
        h.coordinator.previousCaretLocation = start - 1
        h.host.setSelectedRange(NSRange(location: start + 3, length: 0))
        let end = ns.range(of: "| 1 | 2 |").upperBound
        #expect(h.host.selectedRange().location == end + 1)
        h.coordinator.previousCaretLocation = end + 1
        h.host.setSelectedRange(NSRange(location: end, length: 0))
        #expect(h.host.selectedRange().location == start - 1)
    }

    @Test func aCheckboxInACellTogglesAndOpensItsMenu() {
        let h = GridHarness("| a |\n|---|\n| - [ ] x |\n")
        var requests: [TaskMarkerMenuRequest] = []
        h.host.onTaskMarkerMenu = { requests.append($0) }
        h.host.updateWideTableOverlays()
        let cell = h.cell(1, 0)
        var hit: (range: NSRange, marker: Character, rect: CGRect)?
        for x in stride(from: 0, to: cell.bounds.width, by: 2) where hit == nil {
            for y in stride(from: 0, to: cell.bounds.height, by: 2) where hit == nil {
                hit = cell.taskCheckboxHit(atViewPoint: CGPoint(x: x, y: y))
            }
        }
        let box = try! #require(hit)
        #expect(cell.taskMarkerMenu(for: box) == nil)
        #expect(requests.count == 1)
        cell.toggleTaskCheckbox(box)
        #expect(h.host.string.contains("- [x] x"))
    }
}
#endif
