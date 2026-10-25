// Extract to Task (⌥⌘E): the subtask on a line of the open file's editor becomes a task file, filed under the file's
// project or area, and its line (with the lines indented under it) is deleted as one undoable edit.
// The checkbox menu's row and Task ▸ Extract to Task call it; the window shows `ExtractedToast` after.
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
