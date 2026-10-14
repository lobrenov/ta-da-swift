//
//  NativeTextView+TableGrid.swift
//  TaDaMarkdown
//
//  Ta Da fork: the live table grids (`TableGridView`) over the document's tables. Each sits in the wide-table scroll
//  view where its table's first line is, keyed by the table's ordinal in the document. A table's source lines stay in
//  the text, hidden; an edit is one splice of them, registered as one undo step.
//

#if os(macOS)
import AppKit

extension NativeTextView {

    /// The grid of the document's `ordinal`th table.
    func tableGrid(ordinal: Int) -> TableGridView? {
        wideTableOverlays[ordinal]?.documentView as? TableGridView
    }

    /// The source lines of the `ordinal`th table.
    func tableRange(ordinal: Int) -> NSRange? {
        guard let coordinator = delegate as? NativeTextViewCoordinator else { return nil }
        let tokens = coordinator.parsedDocument(for: string).tableTokens
        guard tokens.indices.contains(ordinal) else { return nil }
        // An indented table's lines start at the line start, so its indentation is rewritten with it.
        var range = tokens[ordinal].range
        let lineStart = (string as NSString).lineRange(for: NSRange(location: range.location, length: 0)).location
        if lineStart < range.location { range = NSRange(location: lineStart, length: NSMaxRange(range) - lineStart) }
        return range
    }

    /// Replaces table lines as an edit the editor's input handling leaves alone and the undo manager doesn't record
    /// (`registerTableEdit` does).
    func replaceTableText(_ range: NSRange, with text: String) {
        guard let coordinator = delegate as? NativeTextViewCoordinator, NSMaxRange(range) <= (string as NSString).length
        else { return }
        let manager = undoManager
        manager?.disableUndoRegistration()
        coordinator.isProgrammaticEdit = true
        isEditingTableText = true
        defer {
            isEditingTableText = false
            coordinator.isProgrammaticEdit = false
            manager?.enableUndoRegistration()
        }
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
    }

    func registerTableEdit(_ edit: TableEdit) {
        undoManager?.registerUndo(withTarget: self) { $0.applyTableEdit(edit, forward: false) }
        undoManager?.setActionName(edit.actionName)
    }

    /// Undo (`forward` false) or redo of a table edit: restores the lines and the cell's caret.
    func applyTableEdit(_ edit: TableEdit, forward: Bool) {
        coalescingTableEdit = nil
        let (replaced, text) = forward ? (edit.before, edit.after) : (edit.after, edit.before)
        replaceTableText(NSRange(location: edit.location, length: (replaced as NSString).length), with: text)
        undoManager?.registerUndo(withTarget: self) { $0.applyTableEdit(edit, forward: !forward) }
        undoManager?.setActionName(edit.actionName)
        if let focus = forward ? edit.afterFocus : edit.beforeFocus {
            tableGrid(ordinal: edit.ordinal)?.focus(row: focus.row, column: focus.column, selection: focus.selection)
        }
    }

    /// Creates, positions and drops the grids to match the document's tables, and lets each size its cells. A grid
    /// whose measured height differs from the space the styler reserved has the table restyled with the measure.
    func performTableGridUpdate() {
        guard !isUpdatingTableGrids else { return }
        isUpdatingTableGrids = true
        defer { isUpdatingTableGrids = false }
        for _ in 0..<3 {
            guard let mismatched = reconcileTableGrids() else { return }
            guard !mismatched.isEmpty, let coordinator = delegate as? NativeTextViewCoordinator else { return }
            let parsed = coordinator.parsedDocument(for: string)
            coordinator.restyleTextView(self, paragraphCandidates: mismatched, tokens: parsed.tokens,
                                        classified: parsed.classified, blocks: parsed.blocks)
        }
    }

    /// One pass; the paragraphs to restyle, or nil when there is nothing to reconcile.
    private func reconcileTableGrids() -> [NSRange]? {
        guard let storage = textStorage, let bridge = layoutBridge, let container = bridge.firstTextContainer,
              let coordinator = delegate as? NativeTextViewCoordinator else {
            removeAllWideTableOverlays()
            return nil
        }
        let containerWidth = container.size.width
        guard containerWidth.isFinite, containerWidth > 0 else { return nil }
        let tokens = coordinator.parsedDocument(for: string).tableTokens
        guard !tokens.isEmpty else {
            removeAllWideTableOverlays()
            return nil
        }
        let breakout = configuration.readingWidth != nil
        let host: NSView = breakout ? (superview ?? self) : self
        let viewWidth = host.bounds.width
        let text = string as NSString
        let strip = MarkdownTextLayoutFragment.scrollableBlockScrollerStrip

        var seen: Set<Int> = []
        var mismatched: [NSRange] = []
        for (ordinal, token) in tokens.enumerated() {
            guard NSMaxRange(token.range) <= storage.length,
                  let table = MarkdownStyler.tableMeta(for: text.substring(with: token.range)).parsed else { continue }
            var anchor: NSRange?
            storage.enumerateAttribute(.scrollableBlockSourceID, in: token.range) { value, range, stop in
                if value is Int { anchor = range; stop.pointee = true }
            }
            guard let anchor else { continue }
            // Only the text up to the table's first line needs laying out to place it.
            bridge.ensureLayout(forCharacterRange: anchor)
            let anchorRect = bridge.boundingRect(forCharacterRange: anchor, in: container)
            guard !anchorRect.isEmpty else { continue }
            seen.insert(ordinal)

            let overlay: WideTableOverlay
            let grid: TableGridView
            if let existing = wideTableOverlays[ordinal], let existingGrid = existing.documentView as? TableGridView {
                (overlay, grid) = (existing, existingGrid)
            } else {
                wideTableOverlays[ordinal]?.removeFromSuperview()
                grid = TableGridView(host: self, ordinal: ordinal, table: table)
                overlay = WideTableOverlay(sourceID: ordinal, grid: grid, ownerTextView: self)
                host.addSubview(overlay)
                wideTableOverlays[ordinal] = overlay
                if let saved = tableHorizontalScrollOffsets[ordinal], saved > 0 { overlay.horizontalOffset = saved }
            }
            overlay.anchorTextLocation = token.range.location
            grid.ordinal = ordinal
            grid.update(table: table, availableWidth: containerWidth)

            let isWide = grid.layout.size.width - containerWidth > 0.5
            let gridHeight = grid.layout.size.height
            let (gutter, topMargin) = (TableGridView.gutter, TableGridView.topMargin)
            let totalHeight = gridHeight + topMargin + (isWide ? strip : 0)
            let reserved = storage.attribute(.scrollableBlockTotalHeight, at: anchor.location, effectiveRange: nil) as? CGFloat
            if reserved.map({ abs($0 - (gridHeight + (isWide ? strip : 0))) > 0.5 }) ?? true {
                tableGridHeights[ordinal] = gridHeight
                mismatched.append(text.paragraphRange(for: token.range))
            }

            let columnLeft = (breakout ? frame.origin.x : 0) + textContainerOrigin.x + anchorRect.minX
            let breakoutTop = frame.origin.y + textContainerOrigin.y + anchorRect.minY
            // The overlay reaches into the gutter left of the table and the margin above it, where the grips are.
            let overlayFrame: NSRect = breakout
                ? NSRect(x: 0, y: breakoutTop - topMargin, width: viewWidth, height: totalHeight)
                : NSRect(x: columnLeft - gutter, y: textContainerOrigin.y + anchorRect.minY - topMargin,
                         width: containerWidth + gutter, height: totalHeight)
            if !overlay.frame.equalTo(overlayFrame) {
                host.setNeedsDisplay(overlay.frame)
                overlay.frame = overlayFrame
                host.setNeedsDisplay(overlayFrame)
            }
            overlay.leftContentInset = breakout ? max(0, columnLeft - gutter) : 0
        }
        for (id, overlay) in wideTableOverlays where !seen.contains(id) {
            host.setNeedsDisplay(overlay.frame)
            overlay.removeFromSuperview()
            wideTableOverlays.removeValue(forKey: id)
        }
        return mismatched
    }

    /// The caret leaves a table's grid for the line above or below it.
    func leaveTable(ordinal: Int, above: Bool) {
        guard let range = tableRange(ordinal: ordinal) else { return }
        window?.makeFirstResponder(self)
        // Past a document edge there is no line to go to: a line break there makes one, as one undo step.
        if above, range.location == 0 {
            MarkdownLists.performEdit(self, replace: NSRange(location: 0, length: 0), with: "\n")
            undoManager?.setActionName("Insert Line")
            setSelectedRange(NSRange(location: 0, length: 0))
            return
        }
        let length = (string as NSString).length
        if !above, NSMaxRange(range) >= length {
            MarkdownLists.performEdit(self, replace: NSRange(location: length, length: 0), with: "\n")
            undoManager?.setActionName("Insert Line")
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
            return
        }
        setSelectedRange(NSRange(location: above ? range.location - 1 : NSMaxRange(range) + 1, length: 0))
    }

    /// A selection that lands in a table's source (Find, the slash menu's Table, a click that reaches the text) gives
    /// the keyboard to the cell it falls in, and the text view's own caret moves off the source.
    func focusTableCell(ordinal: Int, selection: NSRange) {
        performTableGridUpdate()
        guard let range = tableRange(ordinal: ordinal), let grid = tableGrid(ordinal: ordinal) else { return }
        let source = (string as NSString).substring(with: range)
        guard let cell = MarkdownTable.cellLocation(in: source, offset: selection.location - range.location) else { return }
        let row = min(cell.row, grid.table.rowCount - 1)
        let column = min(cell.column, grid.table.columnCount - 1)
        let length = (grid.table.cell(row: row, column: column) as NSString).length
        var mapped = NSRange(location: min(cell.offset, length), length: 0)
        if selection.length > 0, let end = MarkdownTable.cellLocation(in: source, offset: NSMaxRange(selection) - range.location),
           end.row == cell.row, end.column == cell.column {
            mapped.length = min(end.offset, length) - mapped.location
        }
        let outside = NSMaxRange(range) + 1 <= (string as NSString).length ? NSMaxRange(range) + 1 : range.location - 1
        if outside >= 0 { setSelectedRange(NSRange(location: outside, length: 0)) }
        grid.focus(row: row, column: column, selection: mapped)
    }

    /// ↓ (`above`) on the line straight above a table, or ↑ on the one below it, enters its first or last row.
    /// False when the caret isn't there.
    func enterTable(from selector: Selector) -> Bool {
        let down = selector == #selector(NSResponder.moveDown(_:))
        guard down || selector == #selector(NSResponder.moveUp(_:)), selectedRange().length == 0,
              let grid = firstTableGrid(adjacentToCaretMovingDown: down) else { return false }
        grid.focus(row: down ? 0 : grid.table.rowCount - 1, column: 0, selection: NSRange(location: 0, length: 0))
        return true
    }

    private func firstTableGrid(adjacentToCaretMovingDown down: Bool) -> TableGridView? {
        guard let coordinator else { return nil }
        let text = string as NSString
        let caret = min(selectedRange().location, text.length)
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        for (ordinal, token) in coordinator.parsedDocument(for: string).tableTokens.enumerated() {
            let touches = down ? NSMaxRange(line) == token.range.location : line.location == NSMaxRange(token.range) + 1
            if touches { return tableGrid(ordinal: ordinal) }
        }
        return nil
    }

    private var coordinator: NativeTextViewCoordinator? { delegate as? NativeTextViewCoordinator }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, hidesSyntaxUnlessFocused {
            hasEditingFocus = true
            (delegate as? NativeTextViewCoordinator)?.editingFocusDidChange(in: self)
            if let cell = tableCell { cell.grid?.cellDidBecomeFocused(cell) }
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted, hidesSyntaxUnlessFocused {
            hasEditingFocus = false
            (delegate as? NativeTextViewCoordinator)?.editingFocusDidChange(in: self)
            if let cell = tableCell { cell.grid?.cellDidResignFocus(cell) }
        }
        return accepted
    }
}
#endif
