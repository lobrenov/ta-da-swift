// Add Subtask (⌘L): makes the caret's line in the focused editor a subtask, or completes (or reopens) it.
// Works through NSTextView, so the live editor and Source mode both get it with their own undo.
import AppKit
import TaDaCore

enum AddSubtask {
    /// The live editor or Source mode, when it has keyboard focus. Text fields (title, search) don't count.
    static var focusedEditor: NSTextView? {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
              !textView.isFieldEditor, textView.isEditable else { return nil }
        return textView
    }

    static func perform(in textView: NSTextView) {
        let string = textView.string as NSString
        let caret = textView.selectedRange().location
        var start = 0, end = 0, contentsEnd = 0
        string.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        let line = string.substring(with: NSRange(location: start, length: contentsEnd - start))

        let range: NSRange, text: String, newCaret: Int, actionName: String
        switch SubtaskLine.edit(for: line[...]) {
        case let .convert(offset, inserted):
            range = NSRange(location: start + offset, length: 0)
            text = inserted
            newCaret = caret >= range.location ? caret + inserted.utf16.count : caret
            actionName = "Add Subtask"
        case let .setMarker(offset, marker):
            range = NSRange(location: start + offset, length: 1)
            text = String(marker)
            newCaret = caret
            actionName = marker == "x" ? "Complete Subtask" : "Reopen Subtask"
        case .none:
            NSSound.beep()
            return
        }
        // Its own undo step, apart from typing before or after it.
        textView.breakUndoCoalescing()
        textView.insertText(text, replacementRange: range)
        textView.setSelectedRange(NSRange(location: newCaret, length: 0))
        textView.undoManager?.setActionName(actionName)
        textView.breakUndoCoalescing()
    }
}
