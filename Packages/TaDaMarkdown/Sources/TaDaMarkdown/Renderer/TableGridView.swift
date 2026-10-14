//
//  TableGridView.swift
//  TaDaMarkdown
//
//  Ta Da fork: a table as a grid of cell editors over its hidden source lines, on the Mac. The cells are the
//  editors; the grid draws the header fill and the borders, sizes each row to its tallest cell, and writes every
//  change back as one splice of the table's lines, padded (`MarkdownTable.markdown`).
//

#if os(macOS)
import AppKit

/// A cell and the selection in it, to restore on undo and redo.
struct CellFocus: Equatable {
    var row: Int
    var column: Int
    var selection: NSRange
}

/// One undoable change of a table's lines: typing coalesces into one, each structural change is its own.
final class TableEdit {
    let ordinal: Int
    let location: Int
    let before: String
    var after: String
    let beforeFocus: CellFocus?
    var afterFocus: CellFocus?
    let actionName: String

    init(ordinal: Int, location: Int, before: String, after: String, beforeFocus: CellFocus?, afterFocus: CellFocus?,
         actionName: String) {
        self.ordinal = ordinal
        self.location = location
        self.before = before
        self.after = after
        self.beforeFocus = beforeFocus
        self.afterFocus = afterFocus
        self.actionName = actionName
    }
}

final class TableGridView: NSView {
    weak var host: NativeTextView?
    var ordinal: Int
    private(set) var table: MarkdownTable
    private(set) var layout: MarkdownStyler.TableLayout
    private(set) var editors: [[TableCellEditor]] = []
    private var isUpdating = false
    /// Where the typing that `coalescingTableEdit` holds last ended, as a location in its cell.
    private var typingEnd: (row: Int, column: Int, location: Int)?

    override var isFlipped: Bool { true }

    init(host: NativeTextView, ordinal: Int, table: MarkdownTable) {
        self.host = host
        self.ordinal = ordinal
        self.table = table
        layout = MarkdownStyler.TableLayout(columnWidths: [], rowContentHeights: [])
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func editor(row: Int, column: Int) -> TableCellEditor? {
        editors.indices.contains(row) && editors[row].indices.contains(column) ? editors[row][column] : nil
    }

    // MARK: - Layout

    /// Shows `newTable`: adds or drops cells, sets the text of those that differ, and sizes the rows to their
    /// tallest cell. The cell being edited keeps its text and caret.
    func update(table newTable: MarkdownTable, availableWidth: CGFloat) {
        guard let host else { return }
        isUpdating = true
        defer { isUpdating = false }
        table = newTable
        resizeEditors(host: host)
        let config = host.configuration
        let estimate = MarkdownStyler.tableLayout(
            newTable, baseFont: host.baseFont, theme: config.theme,
            codeBackgroundColor: config.services.syntaxHighlighter.backgroundColor(),
            latex: config.services.latex, availableWidth: availableWidth, extensions: config.extensions
        ).layout
        let widths = estimate.columnWidths
        let baseLineHeight = ceil(host.baseFont.ascender - host.baseFont.descender + host.baseFont.leading)
        var heights: [CGFloat] = []
        for (r, row) in editors.enumerated() {
            var height = baseLineHeight
            for (c, editor) in row.enumerated() {
                editor.syncConfiguration(from: host)
                let want = newTable.cell(row: r, column: c)
                if editor.text.trimmingCharacters(in: .whitespaces) != want { editor.setText(want) }
                height = max(height, editor.contentHeight(width: widths[c]))
            }
            heights.append(height)
        }
        layout = MarkdownStyler.TableLayout(columnWidths: widths, rowContentHeights: heights)
        let (hPad, vPad) = (MarkdownStyler.TableLayout.cellHPadding, MarkdownStyler.TableLayout.cellVPadding)
        for (r, row) in editors.enumerated() {
            for (c, editor) in row.enumerated() {
                editor.textView.frame = CGRect(x: layout.columnLeft[c], y: layout.rowTop[r],
                                               width: widths[c] + 2 * hPad, height: heights[r] + 2 * vPad)
            }
        }
        if frame.size != layout.size { setFrameSize(layout.size) }
        needsDisplay = true
    }

    private func resizeEditors(host: NativeTextView) {
        while editors.count > table.rowCount {
            editors.removeLast().forEach { $0.textView.removeFromSuperview() }
        }
        for r in 0..<table.rowCount {
            if r >= editors.count { editors.append([]) }
            while editors[r].count > table.columnCount { editors[r].removeLast().textView.removeFromSuperview() }
            while editors[r].count < table.columnCount {
                let editor = TableCellEditor(host: host, row: r, column: editors[r].count)
                editor.grid = self
                editor.coordinator.onDisplayTextChange = { [weak self, weak editor] text in
                    guard let self, let editor else { return }
                    self.cellDidChange(editor, text: text)
                }
                addSubview(editor.textView)
                editors[r].append(editor)
            }
            for (c, editor) in editors[r].enumerated() { (editor.row, editor.column) = (r, c) }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let host, layout.columnWidths.isEmpty == false else { return }
        let border = MarkdownStyler.TableLayout.borderWidth
        let vPad = MarkdownStyler.TableLayout.cellVPadding
        let muted = host.configuration.theme.mutedText.resolved(under: effectiveAppearance)
        muted.withAlphaComponent(0.08).setFill()
        NSBezierPath(rect: CGRect(x: border, y: border, width: layout.size.width - 2 * border,
                                  height: layout.rowContentHeights[0] + 2 * vPad)).fill()
        muted.withAlphaComponent(0.5).setStroke()
        let outer = NSBezierPath(rect: CGRect(x: border / 2, y: border / 2, width: layout.size.width - border,
                                              height: layout.size.height - border))
        outer.lineWidth = border
        outer.stroke()
        let separators = NSBezierPath()
        separators.lineWidth = border
        for i in 1..<max(1, layout.columnWidths.count) {
            let x = layout.columnLeft[i] - border / 2
            separators.move(to: CGPoint(x: x, y: 0))
            separators.line(to: CGPoint(x: x, y: layout.size.height))
        }
        for i in 1..<max(1, layout.rowContentHeights.count) {
            let y = layout.rowTop[i] - border / 2
            separators.move(to: CGPoint(x: 0, y: y))
            separators.line(to: CGPoint(x: layout.size.width, y: y))
        }
        separators.stroke()
    }

    // MARK: - Focus

    /// Gives the keyboard to a cell, with the caret at the end of its text unless `selection` says otherwise.
    func focus(row: Int, column: Int, selection: NSRange? = nil) {
        guard let editor = editor(row: row, column: column) else { return }
        window?.makeFirstResponder(editor.textView)
        let length = (editor.textView.string as NSString).length
        let wanted = selection ?? NSRange(location: length, length: 0)
        let location = min(wanted.location, length)
        editor.textView.setSelectedRange(NSRange(location: location, length: min(wanted.length, length - location)))
    }

    var focusedCell: CellFocus? {
        for row in editors {
            for editor in row where editor.textView.hasEditingFocus {
                return CellFocus(row: editor.row, column: editor.column, selection: editor.textView.selectedRange())
            }
        }
        return nil
    }

    func cellDidBecomeFocused(_ editor: TableCellEditor) {
        host?.focusedTableCell = editor
        host?.coalescingTableEdit = nil
    }

    func cellDidResignFocus(_ editor: TableCellEditor) {
        if host?.focusedTableCell === editor { host?.focusedTableCell = nil }
        host?.coalescingTableEdit = nil
    }

    // MARK: - Writing

    /// A cell's text changed by typing or a command inside the cell.
    private func cellDidChange(_ editor: TableCellEditor, text: String) {
        guard !isUpdating, let host else { return }
        let old = table.cell(row: editor.row, column: editor.column)
        var newTable = table
        newTable.setCell(row: editor.row, column: editor.column, to: text)
        // The edit's span in the cell, as a plain-text diff.
        let (oldNS, newNS) = (old as NSString, text as NSString)
        var prefix = 0
        while prefix < min(oldNS.length, newNS.length), oldNS.character(at: prefix) == newNS.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < min(oldNS.length, newNS.length) - prefix,
              oldNS.character(at: oldNS.length - 1 - suffix) == newNS.character(at: newNS.length - 1 - suffix) { suffix += 1 }
        let removed = oldNS.length - prefix - suffix
        let inserted = newNS.length - prefix - suffix
        let after = CellFocus(row: editor.row, column: editor.column, selection: editor.textView.selectedRange())
        let before = CellFocus(row: editor.row, column: editor.column,
                               selection: inserted == 0 ? NSRange(location: prefix + removed, length: 0)
                                                        : NSRange(location: prefix, length: removed))
        let continues = host.coalescingTableEdit != nil && typingEnd.map {
            $0.row == editor.row && $0.column == editor.column
                && (removed == 0 ? prefix == $0.location : prefix + removed == $0.location)
        } == true
        commit(newTable, actionName: "Typing", beforeFocus: before, afterFocus: after, coalesces: continues)
        typingEnd = (editor.row, editor.column, prefix + inserted)
    }

    /// Writes `newTable` over the table's lines as one splice and registers its undo. With `coalesces`, a typing
    /// edit continues the one on top of the undo stack instead.
    func commit(_ newTable: MarkdownTable, actionName: String, beforeFocus: CellFocus?, afterFocus: CellFocus?,
                coalesces: Bool = false) {
        guard let host, let range = host.tableRange(ordinal: ordinal) else { return }
        let old = (host.string as NSString).substring(with: range)
        let markdown = newTable.markdown
        table = newTable
        guard markdown != old else {
            host.updateWideTableOverlays()
            return
        }
        host.replaceTableText(range, with: markdown)
        if coalesces, let edit = host.coalescingTableEdit {
            edit.after = markdown
            edit.afterFocus = afterFocus
            return
        }
        let edit = TableEdit(ordinal: ordinal, location: range.location, before: old, after: markdown,
                             beforeFocus: beforeFocus, afterFocus: afterFocus, actionName: actionName)
        host.registerTableEdit(edit)
        host.coalescingTableEdit = actionName == "Typing" ? edit : nil
    }
}
#endif
