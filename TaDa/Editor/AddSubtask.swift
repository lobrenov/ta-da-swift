// Add Subtask (⌘L): makes the caret's line in the focused editor a subtask, or starts a new one below it.
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
        let ending = string.range(of: "\r\n").location == NSNotFound ? "\n" : "\r\n"

        let location: Int, text: String, newCaret: Int
        switch SubtaskLine.insertion(for: line[...], ending: ending) {
        case let .convert(offset, inserted):
            location = start + offset
            text = inserted
            newCaret = caret >= location ? caret + inserted.utf16.count : caret
        case let .newSubtask(inserted):
            location = contentsEnd
            text = inserted
            newCaret = contentsEnd + inserted.utf16.count
        }
        // Its own undo step, apart from typing before or after it.
        textView.breakUndoCoalescing()
        textView.insertText(text, replacementRange: NSRange(location: location, length: 0))
        textView.setSelectedRange(NSRange(location: newCaret, length: 0))
        textView.undoManager?.setActionName("Add Subtask")
        textView.breakUndoCoalescing()
    }
}
