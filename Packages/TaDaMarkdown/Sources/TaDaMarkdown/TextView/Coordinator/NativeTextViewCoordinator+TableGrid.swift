//
//  NativeTextViewCoordinator+TableGrid.swift
//  TaDaMarkdown
//
//  Ta Da fork: with `configuration.liveTables` the caret never rests in a table's source lines: the grid is the
//  table, so the caret steps over it as it passes (from before it to after it, and back).
//

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

extension NativeTextViewCoordinator {

    /// From every selection change: a caret in a table's lines, or at the end of its last line, moves past it.
    func snapCaretOutOfTable(in textView: PlatformTextView) {
        #if os(macOS)
        let selection = textView.currentSelectedRange
        guard configuration.liveTables, selection.length == 0,
              !((textView as? NativeTextView)?.hidesSyntaxUnlessFocused ?? false) else { return }
        let text = textView.string as NSString
        guard let table = parsedDocument(for: textView.string).tableTokens.first(where: {
            selection.location >= $0.range.location && selection.location <= NSMaxRange($0.range)
        }) else { return }
        let cameFromBefore = (previousCaretLocation ?? 0) < table.range.location
        let target = cameFromBefore ? min(NSMaxRange(table.range) + 1, text.length) : max(table.range.location - 1, 0)
        guard target < table.range.location || target > NSMaxRange(table.range) else { return }
        textView.setSelectedRange(NSRange(location: target, length: 0))
        #endif
    }
}
