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

    @Test func theCaretStepsOverTheSourceAsItPasses() {
        let h = GridHarness(Self.source)
        let ns = Self.source as NSString
        let start = ns.range(of: "| a").location
        h.coordinator.previousCaretLocation = start - 1
        h.host.setSelectedRange(NSRange(location: start, length: 0))
        let end = ns.range(of: "| 1 | 2 |").upperBound
        #expect(h.host.selectedRange().location == end + 1)
        h.coordinator.previousCaretLocation = end + 1
        h.host.setSelectedRange(NSRange(location: end, length: 0))
        #expect(h.host.selectedRange().location == start - 1)
    }

    @Test func aCaretLandingInTheSourceFocusesTheCellItIsIn() {
        let h = GridHarness(Self.source)
        let ns = Self.source as NSString
        h.coordinator.previousCaretLocation = 0
        h.host.setSelectedRange(NSRange(location: ns.range(of: "| 1 | 2 |").location + 6, length: 0))
        #expect(h.grid.focusedCell?.row == 1 && h.grid.focusedCell?.column == 1)
        let outside = h.host.selectedRange().location
        #expect(outside < ns.range(of: "| a").location || outside > ns.range(of: "| 1 | 2 |").upperBound)
    }

    @Test func aTableInsertedBySlashStartsWithItsFirstHeaderCellSelected() {
        let h = GridHarness("Before\n\n")
        h.host.setSelectedRange(NSRange(location: 8, length: 0))
        let template = "| Column | Column |\n| --- | --- |\n|  |  |"
        MarkdownLists.performEdit(h.host, replace: NSRange(location: 8, length: 0), with: template)
        h.host.setSelectedRange(NSRange(location: 10, length: 6))
        #expect(h.grid.focusedCell == CellFocus(row: 0, column: 0, selection: NSRange(location: 0, length: 6)))
    }

    @Test func aCheckboxInACellTogglesAndOpensItsMenu() {
        let h = GridHarness("| a |\n|---|\n| - [ ] x |\n")
        var requests: [TaskMarkerMenuRequest] = []
        h.host.onTaskMarkerMenu = { requests.append($0) }
        h.host.updateWideTableOverlays(immediately: true)
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

@MainActor
@Suite("Live table grid keys")
struct TableGridKeyTests {
    static let source = "Before\n\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\nAfter\n"

    private func focused(_ h: GridHarness) -> (row: Int, column: Int)? {
        h.grid.focusedCell.map { ($0.row, $0.column) }
    }

    @Test func tabMovesToTheNextCellAndShiftTabBack() {
        let h = GridHarness(Self.source)
        h.grid.focus(row: 0, column: 0)
        h.cell(0, 0).doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(focused(h)! == (0, 1))
        h.cell(0, 1).doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(focused(h)! == (1, 0))
        h.cell(1, 0).doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        #expect(focused(h)! == (0, 1))
        h.grid.focus(row: 0, column: 0)
        h.cell(0, 0).doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        #expect(focused(h)! == (0, 0))
        #expect(h.host.string == Self.source)
    }

    @Test func tabOnTheLastCellAddsARowAsOneUndoStep() {
        let h = GridHarness(Self.source)
        h.grid.focus(row: 2, column: 1)
        h.cell(2, 1).doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(h.grid.table.rowCount == 4)
        #expect(focused(h)! == (3, 0))
        #expect(h.host.string.contains("|     |     |"))
        h.host.undoManager?.undo()
        #expect(h.grid.table.rowCount == 3)
        #expect(h.host.string.contains("| 3 | 4 |"))
        #expect(h.host.string == Self.source)
    }

    @Test func tabOnAListLineIndentsInsteadOfMoving() {
        let h = GridHarness("| a |\n|---|\n|  |\n")
        h.type("- a", row: 1, column: 0)
        h.cell(1, 0).insertNewline(nil)
        h.type("b", row: 1, column: 0)
        h.cell(1, 0).doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(focused(h)! == (1, 0))
        #expect(h.cell(1, 0).string != "- a\n- b")
        #expect(h.cell(1, 0).string.contains("\n  - b") || h.cell(1, 0).string.contains("\n\t- b"))
    }

    @Test func arrowsMoveBetweenCellsVertically() {
        let h = GridHarness(Self.source)
        h.grid.focus(row: 1, column: 1)
        h.cell(1, 1).doCommand(by: #selector(NSResponder.moveUp(_:)))
        #expect(focused(h)! == (0, 1))
        h.cell(0, 1).doCommand(by: #selector(NSResponder.moveDown(_:)))
        #expect(focused(h)! == (1, 1))
        h.cell(1, 1).doCommand(by: #selector(NSResponder.moveDown(_:)))
        #expect(focused(h)! == (2, 1))
    }

    @Test func upFromTheHeaderAndDownFromTheLastRowLeaveTheTable() {
        let h = GridHarness(Self.source)
        let ns = Self.source as NSString
        let start = ns.range(of: "| a").location
        let end = ns.range(of: "| 3 | 4 |").upperBound
        h.grid.focus(row: 0, column: 0)
        h.cell(0, 0).doCommand(by: #selector(NSResponder.moveUp(_:)))
        #expect(h.window.firstResponder === h.host)
        #expect(h.host.selectedRange() == NSRange(location: start - 1, length: 0))
        h.grid.focus(row: 2, column: 0)
        h.cell(2, 0).doCommand(by: #selector(NSResponder.moveDown(_:)))
        #expect(h.window.firstResponder === h.host)
        #expect(h.host.selectedRange() == NSRange(location: end + 1, length: 0))
    }

    @Test func leftAtACellsStartAndRightAtItsEndStepBetweenCells() {
        let h = GridHarness(Self.source)
        h.grid.focus(row: 1, column: 0, selection: NSRange(location: 0, length: 0))
        h.cell(1, 0).doCommand(by: #selector(NSResponder.moveLeft(_:)))
        #expect(focused(h)! == (0, 1))
        h.cell(0, 1).doCommand(by: #selector(NSResponder.moveRight(_:)))
        #expect(focused(h)! == (1, 0))
        #expect(h.cell(1, 0).selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func leftPastTheFirstCellAndRightPastTheLastLeaveTheTable() {
        let h = GridHarness(Self.source)
        let ns = Self.source as NSString
        let start = ns.range(of: "| a").location
        h.grid.focus(row: 0, column: 0, selection: NSRange(location: 0, length: 0))
        h.cell(0, 0).doCommand(by: #selector(NSResponder.moveLeft(_:)))
        #expect(h.window.firstResponder === h.host)
        #expect(h.host.selectedRange().location == start - 1)
        h.grid.focus(row: 2, column: 1)
        h.cell(2, 1).doCommand(by: #selector(NSResponder.moveRight(_:)))
        #expect(h.window.firstResponder === h.host)
    }

    @Test func downFromTheLineAboveAndUpFromTheLineBelowEnterTheTable() {
        let h = GridHarness(Self.source)
        let ns = Self.source as NSString
        let start = ns.range(of: "| a").location
        let end = ns.range(of: "| 3 | 4 |").upperBound
        h.window.makeFirstResponder(h.host)
        h.host.setSelectedRange(NSRange(location: start - 1, length: 0))
        h.host.doCommand(by: #selector(NSResponder.moveDown(_:)))
        #expect(focused(h)! == (0, 0))
        h.window.makeFirstResponder(h.host)
        h.host.setSelectedRange(NSRange(location: end + 1, length: 0))
        h.host.doCommand(by: #selector(NSResponder.moveUp(_:)))
        #expect(focused(h)! == (2, 0))
    }
}

@MainActor
@Suite("Live table grid handles")
struct TableGridHandleTests {
    nonisolated static let source = "Before\n\n| h1 | h2 |\n|:---|---:|\n| r1 | a |\n| r2 | b |\n| r3 | c |\n\nAfter\n"

    private func harness(_ source: String = TableGridHandleTests.source) -> (GridHarness, NSPasteboard) {
        let h = GridHarness(source)
        let board = NSPasteboard(name: NSPasteboard.Name("TaDaMarkdownTests.\(UUID().uuidString)"))
        h.grid.pasteboard = board
        return (h, board)
    }

    @Test func aGripClickSelectsARowOrColumn() {
        let (h, _) = harness()
        let grid = h.grid
        grid.select(.row(2))
        #expect(grid.selectedHandle == .row(2))
        #expect(h.window.firstResponder === grid)
        grid.select(.column(1))
        #expect(grid.selectedHandle == .column(1))
        grid.keyDown(with: key(53))
        #expect(grid.selectedHandle == nil)
        grid.select(.row(1))
        grid.focus(row: 1, column: 0)
        #expect(grid.selectedHandle == nil)
    }

    @Test func gripsAreInTheGutterAndAboveTheColumns() {
        let (h, _) = harness()
        let grid = h.grid
        let layout = grid.layout
        let rowY = TableGridView.topMargin + layout.rowTop[2] + 4
        #expect(grid.handle(at: CGPoint(x: 4, y: rowY)) == .row(2))
        let columnX = TableGridView.gutter + layout.columnLeft[1] + 4
        #expect(grid.handle(at: CGPoint(x: columnX, y: 4)) == .column(1))
        #expect(grid.handle(at: CGPoint(x: columnX, y: rowY)) == nil)
        grid.updateHover(atViewPoint: CGPoint(x: columnX, y: rowY))
        #expect(grid.hoverRow == 2 && grid.hoverColumn == 1)
        grid.updateHover(atViewPoint: nil)
        #expect(grid.hoverRow == nil && grid.hoverColumn == nil)
    }

    @Test func copyPutsAValidTableOnThePasteboard() throws {
        let (h, board) = harness()
        h.grid.select(.row(2))
        h.grid.copy(nil)
        let rowText = try #require(board.string(forType: .string))
        let row = try #require(MarkdownTable.parse(rowText))
        #expect(row.header == ["h1", "h2"])
        #expect(row.alignments == [.left, .right])
        #expect(row.rows == [["r2", "b"]])
        h.grid.select(.column(1))
        h.grid.copy(nil)
        let columnText = try #require(board.string(forType: .string))
        let column = try #require(MarkdownTable.parse(columnText))
        #expect(column.header == ["h2"])
        #expect(column.rows == [["a"], ["b"], ["c"]])
        #expect(h.host.string.contains("r2"))
    }

    @Test func cutCopiesAndDeletesAsOneUndoStep() throws {
        let (h, board) = harness()
        let before = h.host.string
        h.grid.select(.row(2))
        h.grid.cut(nil)
        #expect(board.string(forType: .string)?.contains("r2") == true)
        #expect(!h.host.string.contains("r2"))
        #expect(h.grid.table.rows.count == 2)
        h.host.undoManager?.undo()
        #expect(h.host.string == before)
    }

    @Test func deleteRemovesTheSelectionAndTheHeaderPromotesTheNextRow() {
        let (h, _) = harness()
        h.grid.select(.column(0))
        h.grid.keyDown(with: key(51))
        #expect(h.grid.table.header == ["h2"])
        h.grid.select(.row(0))
        h.grid.keyDown(with: key(51))
        #expect(h.grid.table.header == ["a"])
        #expect(h.grid.table.rows == [["b"], ["c"]])
    }

    @Test func deletingTheLastRowOrOnlyColumnDeletesTheTable() {
        let (h, _) = harness("Before\n\n| a |\n|---|\n\nAfter\n")
        let before = h.host.string
        h.grid.select(.row(0))
        h.grid.deleteSelected()
        #expect(h.host.string == "Before\n\n\nAfter\n")
        #expect(h.host.tableGrid(ordinal: 0) == nil)
        h.host.undoManager?.undo()
        #expect(h.host.string == before)
        #expect(h.host.tableGrid(ordinal: 0) != nil)
        h.grid.select(.column(0))
        h.grid.deleteSelected()
        #expect(h.host.tableGrid(ordinal: 0) == nil)
    }

    @Test func movingARowIsOneUndoStepAndTheHeaderStaysFirst() {
        let (h, _) = harness()
        let before = h.host.string
        h.grid.move(.row(1), toGap: 4)
        #expect(h.grid.table.rows.map { $0[0] } == ["r2", "r3", "r1"])
        #expect(h.grid.selectedHandle == .row(3))
        h.host.undoManager?.undo()
        #expect(h.host.string == before)
        h.grid.move(.row(0), toGap: 3)
        #expect(h.host.string == before)
        h.grid.move(.row(3), toGap: 0)
        #expect(h.grid.table.header == ["h1", "h2"])
        #expect(h.grid.table.rows.map { $0[0] } == ["r3", "r1", "r2"])
    }

    @Test func movingAColumnKeepsItsAlignmentAndIsOneUndoStep() {
        let (h, _) = harness()
        let before = h.host.string
        h.grid.move(.column(0), toGap: 2)
        #expect(h.grid.table.header == ["h2", "h1"])
        #expect(h.grid.table.alignments == [.right, .left])
        h.host.undoManager?.undo()
        #expect(h.host.string == before)
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
}

@MainActor
@Suite("Live table grid menu")
struct TableGridMenuTests {
    static let source = "Before\n\n| h1 | h2 |\n|:---|---:|\n| r1 | a |\n| r2 | b |\n\nAfter\n"

    private func request(_ h: GridHarness, _ handle: TableHandle) -> (RightClickMenuRequest, () -> Int) {
        var requests: [RightClickMenuRequest] = []
        h.host.onRightClickMenu = { requests.append($0) }
        h.grid.showMenu(for: handle)
        return (requests[0], { requests.count })
    }

    private func item(_ request: RightClickMenuRequest, _ title: String) -> RightClickMenuItem {
        request.sections.flatMap { $0 }.first { $0.title == title }!
    }

    @Test func aRowGripOffersInsertAndDelete() {
        let h = GridHarness(Self.source)
        let (menu, _) = request(h, .row(1))
        #expect(menu.sections.map { $0.map(\.title) } == [["Insert above", "Insert below", "Delete row"]])
        #expect(h.grid.menuHandle == .row(1))
        item(menu, "Insert below").action()
        #expect(h.grid.table.rows == [["r1", "a"], ["", ""], ["r2", "b"]])
        h.host.undoManager?.undo()
        #expect(h.grid.table.rows == [["r1", "a"], ["r2", "b"]])
        menu.close()
        #expect(h.grid.menuHandle == nil)
    }

    @Test func theHeaderGripHasTheSameItemsAndDeletingItPromotesTheNextRow() {
        let h = GridHarness(Self.source)
        let (menu, _) = request(h, .row(0))
        #expect(menu.sections.flatMap { $0 }.map(\.title) == ["Insert above", "Insert below", "Delete row"])
        item(menu, "Delete row").action()
        #expect(h.grid.table.header == ["r1", "a"])
        #expect(h.grid.table.rows == [["r2", "b"]])
    }

    @Test func deleteRowOnAOneRowTableDeletesTheTable() {
        let h = GridHarness("Before\n\n| a | b |\n|---|---|\n\nAfter\n")
        let (menu, _) = request(h, .row(0))
        item(menu, "Delete row").action()
        #expect(h.host.tableGrid(ordinal: 0) == nil)
        #expect(h.host.string == "Before\n\n\nAfter\n")
    }

    @Test func aColumnGripOffersInsertDeleteAndAlignmentWithTheCurrentChecked() {
        let h = GridHarness(Self.source)
        let (menu, _) = request(h, .column(1))
        #expect(menu.sections.map { $0.map(\.title) } == [["Insert left", "Insert right", "Delete column"],
                                                          ["Align left", "Align centre", "Align right"]])
        #expect(menu.sections[1].map(\.isChecked) == [false, false, true])
        item(menu, "Align centre").action()
        #expect(h.host.string.contains("| :-: |") || h.host.string.contains(":-:"))
        #expect(h.grid.table.alignments == [.left, .center])
        item(menu, "Insert left").action()
        #expect(h.grid.table.header == ["h1", "", "h2"])
        item(menu, "Delete column").action()
        #expect(h.grid.table.columnCount == 2)
    }

    @Test func deleteColumnOnAOneColumnTableDeletesTheTable() {
        let h = GridHarness("Before\n\n| a |\n|---|\n| 1 |\n\nAfter\n")
        let (menu, _) = request(h, .column(0))
        item(menu, "Delete column").action()
        #expect(h.host.tableGrid(ordinal: 0) == nil)
    }
}

@MainActor
@Suite("Live table grid at the document's edges")
struct TableGridEdgeTests {
    @Test func downFromTheLastRowOfATableEndingTheDocumentAddsALineToWriteOn() {
        let source = "x\n\n| a |\n|---|\n| 1 |"
        let h = GridHarness(source)
        h.grid.focus(row: 1, column: 0)
        h.cell(1, 0).doCommand(by: #selector(NSResponder.moveDown(_:)))
        #expect(h.host.string == source + "\n")
        #expect(h.window.firstResponder === h.host)
        #expect(h.host.selectedRange() == NSRange(location: (source + "\n").count, length: 0))
        h.host.undoManager?.undo()
        #expect(h.host.string == source)
    }

    @Test func upFromATableStartingTheDocumentAddsALineAbove() {
        let source = "| a |\n|---|\n| 1 |\n\nx"
        let h = GridHarness(source)
        h.grid.focus(row: 0, column: 0)
        h.cell(0, 0).doCommand(by: #selector(NSResponder.moveUp(_:)))
        #expect(h.host.string == "\n" + source)
        #expect(h.host.selectedRange() == NSRange(location: 0, length: 0))
        h.cell(0, 0).doCommand(by: #selector(NSResponder.moveLeft(_:)))
        #expect(h.host.string == "\n" + source)
    }

    @Test func aCaretLandingAtADocumentEdgeFocusesACell() {
        let source = "| a |\n|---|\n| 1 |"
        let h = GridHarness(source)
        h.host.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(h.grid.focusedCell?.row == 0)
        h.window.makeFirstResponder(h.host)
        h.host.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        #expect(h.grid.focusedCell?.row == 1)
    }

    @Test func rightPastTheLastCellOfATableEndingTheDocumentAddsALine() {
        let source = "| a |\n|---|\n| 1 |"
        let h = GridHarness(source)
        h.grid.focus(row: 1, column: 0)
        h.cell(1, 0).doCommand(by: #selector(NSResponder.moveRight(_:)))
        #expect(h.host.string == source + "\n")
    }
}

@MainActor
@Suite("Live table grid details")
struct TableGridDetailTests {
    @Test func anIndentedTableKeepsItsIndentationThroughEdits() {
        let source = "- item\n\n  | a | b |\n  |---|---|\n  | 1 | 2 |\n"
        let h = GridHarness(source)
        h.type("x", row: 1, column: 0)
        #expect(h.host.string == "- item\n\n  | a   | b   |\n  | --- | --- |\n  | 1x  | 2   |\n")
        h.grid.deleteRow(1)
        #expect(h.host.string.hasPrefix("- item\n\n  | a   | b   |"))
    }

    @Test func settingsFontChangesReachTheCells() {
        let h = GridHarness("| a |\n|---|\n| 1 |\n")
        let before = h.cell(1, 0).font?.pointSize
        h.host.baseFont = NSFont.systemFont(ofSize: 20)
        h.host.updateWideTableOverlays(immediately: true)
        #expect(h.cell(1, 0).font?.pointSize == 20)
        #expect(before != 20)
    }

    @Test func aClickOnABorderFocusesTheNearestCellAndClearsTheSelection() {
        let h = GridHarness("| a | b |\n|---|---|\n| 1 | 2 |\n")
        let grid = h.grid
        grid.select(.row(1))
        let border = CGPoint(x: TableGridView.gutter + grid.layout.columnLeft[1] - 0.5,
                             y: TableGridView.topMargin + grid.layout.rowTop[1] + 4)
        #expect(grid.claims(border))
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: grid.convert(border, to: nil), modifierFlags: [], timestamp: 0,
                                       windowNumber: h.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        grid.mouseDown(with: event)
        #expect(grid.selectedHandle == nil)
        #expect(grid.focusedCell != nil)
    }

    @Test func theProxyReachesTheFocusedCell() {
        let h = GridHarness("| a |\n|---|\n| 1 |\n")
        let proxy = SlashCommandProxy()
        proxy.coordinator = h.coordinator
        #expect(proxy.textView === h.host)
        h.grid.focus(row: 1, column: 0)
        #expect(proxy.textView === h.cell(1, 0))
    }

    @Test func typingElsewhereDoesNotRelayoutAnUnchangedGrid() {
        let h = GridHarness("| a |\n|---|\n| 1 |\n\ntext\n")
        let grid = h.grid
        let frame = h.cell(1, 0).frame
        h.cell(1, 0).frame = frame.offsetBy(dx: 3, dy: 0)
        h.host.updateWideTableOverlays(immediately: true)
        #expect(h.cell(1, 0).frame == frame.offsetBy(dx: 3, dy: 0))
        grid.needsRelayout = true
        h.host.updateWideTableOverlays(immediately: true)
        #expect(h.cell(1, 0).frame == frame)
    }
}

/// Timings for a large table (prints; the grid's cost is per cell). Not asserted tightly: machines differ.
@MainActor
@Suite("Live table grid timing")
struct TableGridTimingTests {
    @Test func aHundredByFiveTableOpensAndTypesQuickly() {
        var lines = ["Intro text", "", "| " + (0..<6).map { "H\($0)" }.joined(separator: " | ") + " |",
                     "|" + String(repeating: "---|", count: 6)]
        for r in 0..<100 { lines.append("| " + (0..<6).map { "r\(r)c\($0) **b**" }.joined(separator: " | ") + " |") }
        lines += ["", "Outro text", ""]
        let source = lines.joined(separator: "\n")
        let clock = ContinuousClock()
        var h: GridHarness!
        let open = clock.measure { h = GridHarness(source) }
        let inCell = clock.measure {
            h.grid.focus(row: 50, column: 2)
            for _ in 0..<10 { h.cell(50, 2).insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }
        h.window.makeFirstResponder(h.host)
        let end = (source as NSString).length
        let inMain = clock.measure {
            for _ in 0..<10 {
                h.host.setSelectedRange(NSRange(location: end - 1, length: 0))
                h.host.insertText("y", replacementRange: NSRange(location: NSNotFound, length: 0))
            }
        }
        print("TABLE TIMING open=\(open) perCellKeystroke=\(inCell / 10) perMainKeystroke=\(inMain / 10)")
    }
}
#endif
