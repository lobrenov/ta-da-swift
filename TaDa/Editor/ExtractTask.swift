// Extract to Task (⌥⌘E): the subtask on a line of the open file's editor becomes a task file, filed under the file's
// project or area, and its line (with the lines indented under it) is deleted as one undoable edit. A selection becomes
// a task named by it and is replaced with the task's link.
// The checkbox menu's row, the text menu's row and Task ▸ Extract to Task call it; the window shows `ExtractedToast` after.
#if os(macOS)
import AppKit
import SwiftUI
import TaDaCore

enum ExtractTask {
    /// Whether the line holding UTF-16 `location` is a subtask that can be extracted.
    static func canExtract(in textView: NSTextView, at location: Int) -> Bool {
        SubtaskExtraction.extract(lineAt: location, in: textView.string) != nil
    }

    static func perform(in textView: NSTextView, at location: Int, model: AppModel) {
        guard let path = model.document?.path,
              let extract = SubtaskExtraction.extract(lineAt: location, in: textView.string) else {
            NSSound.beep()
            return
        }
        let lines = (textView.string as NSString).substring(with: extract.range)
        Task {
            guard let extracted = await model.extractTask(extract, from: path) else { return }
            guard NSMaxRange(extract.range) <= (textView.string as NSString).length,
                  (textView.string as NSString).substring(with: extract.range) == lines else {
                model.errorMessage = "“\(Item.title(ofPath: extracted.path))” was made a task, but its subtask changed meanwhile, so its line is still in the file."
                return
            }
            textView.breakUndoCoalescing()
            textView.insertText("", replacementRange: extract.range)
            textView.undoManager?.setActionName("Extract to Task")
            textView.breakUndoCoalescing()
            model.extracted = extracted
        }
    }

    /// `selection`, which holds `selectedText`, cut back to its first and last non-blank characters; nil when that is
    /// nothing or spans lines.
    static func extractableRange(_ selection: NSRange, selectedText: String) -> NSRange? {
        let text = selectedText as NSString
        let blanks = CharacterSet.whitespacesAndNewlines
        var start = 0, end = text.length
        while start < end, blanks.contains(Unicode.Scalar(text.character(at: start)) ?? "a") { start += 1 }
        while end > start, blanks.contains(Unicode.Scalar(text.character(at: end - 1)) ?? "a") { end -= 1 }
        guard start < end else { return nil }
        let trimmed = text.substring(with: NSRange(location: start, length: end - start))
        guard trimmed.rangeOfCharacter(from: .newlines) == nil else { return nil }
        return NSRange(location: selection.location + start, length: end - start)
    }

    /// `selectedText` with its trimmed part, as `extractableRange` finds it, replaced by `replacement(trimmed)`; the blanks
    /// around it stay. nil when nothing can be extracted.
    static func replacingTrimmed(in selectedText: String, with replacement: (String) -> String) -> String? {
        let text = selectedText as NSString
        guard let range = extractableRange(NSRange(location: 0, length: text.length), selectedText: selectedText) else { return nil }
        return text.substring(to: range.location) + replacement(text.substring(with: range)) + text.substring(from: NSMaxRange(range))
    }

    /// Extract to Task on a selection: a task named by the selected text, trimmed, which `replace` swaps for the task's
    /// `[[link]]`, if unchanged meanwhile. A selected subtask line extracts the subtask.
    static func perform(selection: NSRange, in textView: NSTextView, model: AppModel,
                        replace: @escaping @MainActor (String) -> Void) {
        let text = textView.string as NSString
        guard NSMaxRange(selection) <= text.length,
              let range = extractableRange(selection, selectedText: text.substring(with: selection)) else {
            NSSound.beep()
            return
        }
        let line = text.lineRange(for: NSRange(location: range.location, length: 0))
        let content = text.substring(with: line)
        let first = content.firstIndex { !$0.isWhitespace }.map { content.utf16.distance(from: content.startIndex, to: $0) }
        let last = content.lastIndex { !$0.isWhitespace }.map { content.utf16.distance(from: content.startIndex, to: content.index(after: $0)) }
        if SubtaskExtraction.extract(lineAt: range.location, in: textView.string) != nil,
           first == range.location - line.location, last == NSMaxRange(range) - line.location {
            return perform(in: textView, at: range.location, model: model)
        }
        let selected = text.substring(with: range)
        guard let path = model.document?.path else { return NSSound.beep() }
        let extract = SubtaskExtraction.Extract(title: selected, status: .notStarted, body: "", range: range)
        Task {
            guard let extracted = await model.extractTask(extract, from: path) else { return }
            guard NSMaxRange(range) <= (textView.string as NSString).length,
                  (textView.string as NSString).substring(with: range) == selected else {
                model.errorMessage = "“\(Item.title(ofPath: extracted.path))” was made a task, but the text changed meanwhile, so it is still in the file."
                return
            }
            replace("[[\(Item.title(ofPath: extracted.path))]]")
            model.extracted = extracted
        }
    }
}

/// "Extracted to a task in <parent>", the new file's path and Open, at the foot of the document for a few seconds.
struct ExtractedToast: View {
    let model: AppModel
    let extracted: AppModel.Extracted
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.color(\.done))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Extracted to a task in \(extracted.parent ?? "Loose")")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.color(\.strong))
                Text(extracted.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.color(\.muted))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button("Open") {
                model.extracted = nil
                model.openLink(to: extracted.path)
            }
            .buttonStyle(ActionButtonStyle(kind: .primary, height: 26))
        }
        .popupChrome(theme: theme, width: 420, padding: 10)
        .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.15), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
        .task(id: extracted.id) {
            try? await Task.sleep(for: .seconds(6))
            if model.extracted?.id == extracted.id { model.extracted = nil }
        }
    }
}
#endif
