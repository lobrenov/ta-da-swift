// Add Subtask (⌘L): makes the caret's line (or each selected line) in the focused editor a subtask, or completes (or reopens) it.
// Works through NSTextView, so the live editor and Source mode both get it with their own undo.
#if os(macOS)
import AppKit
import SwiftUI
import TaDaCore

/// Holds an editor's text view. Each editor publishes its holder as a focused value while it has the keyboard.
protocol TextViewHolder: AnyObject {
    var textView: NSTextView? { get }
}

extension FocusedValues {
    /// The live or Source editor that has the keyboard. Add Subtask edits it, and is off while there's none.
    @Entry var editor: (any TextViewHolder)?
}

enum AddSubtask {
    static func perform(in textView: NSTextView) {
        guard let plan = SubtaskLine.plan(in: textView.string, selection: textView.selectedRange()) else {
            NSSound.beep()
            return
        }
        // Its own undo step, apart from typing before or after it.
        textView.breakUndoCoalescing()
        textView.insertText(plan.text, replacementRange: plan.range)
        textView.setSelectedRange(plan.selection)
        textView.undoManager?.setActionName(plan.actionName)
        textView.breakUndoCoalescing()
    }
}
#endif
