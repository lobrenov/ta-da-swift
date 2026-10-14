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
        return tokens.indices.contains(ordinal) ? tokens[ordinal].range : nil
    }

    /// Replaces table lines as an edit the editor's input handling leaves alone and the undo manager doesn't record
    /// (`registerTableEdit` does).
    func replaceTableText(_ range: NSRange, with text: String) {
        guard let coordinator = delegate as? NativeTextViewCoordinator, NSMaxRange(range) <= (string as NSString).length
        else { return }
        let manager = undoManager
        manager?.disableUndoRegistration()
        coordinator.isProgrammaticEdit = true
        defer {
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
              let tlm = textLayoutManager, let coordinator = delegate as? NativeTextViewCoordinator else {
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
        tlm.ensureLayout(for: tlm.documentRange)

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

            let isWide = grid.frame.width - containerWidth > 0.5
            let gridHeight = grid.frame.height
            let totalHeight = gridHeight + (isWide ? strip : 0)
            let reserved = storage.attribute(.scrollableBlockTotalHeight, at: anchor.location, effectiveRange: nil) as? CGFloat
            if reserved.map({ abs($0 - totalHeight) > 0.5 }) ?? true {
                tableGridHeights[ordinal] = gridHeight
                mismatched.append(text.paragraphRange(for: token.range))
            }

            let columnLeft = (breakout ? frame.origin.x : 0) + textContainerOrigin.x + anchorRect.minX
            let breakoutTop = frame.origin.y + textContainerOrigin.y + anchorRect.minY
            let overlayFrame: NSRect = breakout
                ? NSRect(x: 0, y: breakoutTop, width: viewWidth, height: totalHeight)
                : NSRect(x: columnLeft, y: textContainerOrigin.y + anchorRect.minY, width: containerWidth, height: totalHeight)
            if !overlay.frame.equalTo(overlayFrame) {
                host.setNeedsDisplay(overlay.frame)
                overlay.frame = overlayFrame
                host.setNeedsDisplay(overlayFrame)
            }
            overlay.leftContentInset = breakout ? max(0, columnLeft) : 0
        }
        for (id, overlay) in wideTableOverlays where !seen.contains(id) {
            host.setNeedsDisplay(overlay.frame)
            overlay.removeFromSuperview()
            wideTableOverlays.removeValue(forKey: id)
        }
        return mismatched
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, hidesSyntaxUnlessFocused {
            hasEditingFocus = true
            tableCell?.grid?.cellDidBecomeFocused(tableCell!)
            (delegate as? NativeTextViewCoordinator)?.editingFocusDidChange(in: self)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted, hidesSyntaxUnlessFocused {
            hasEditingFocus = false
            if let cell = tableCell { cell.grid?.cellDidResignFocus(cell) }
            (delegate as? NativeTextViewCoordinator)?.editingFocusDidChange(in: self)
        }
        return accepted
    }
}
#endif
