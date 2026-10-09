//
//  NativeTextViewCoordinatorIOS.swift
//  TaDaMarkdown
//
//  The UITextViewDelegate methods. Keystrokes and selection changes go to the
//  shared path in `+TextDelegate.swift`.
//

#if os(iOS)
import UIKit

extension NativeTextViewCoordinator: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        textDidChange(in: textView)
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        selectionDidChange(in: textView)
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        shouldChangeText(in: textView, affectedCharRange: range, replacementString: text)
    }

    /// macOS turns autocorrection off inside code; iOS keeps the keyboard's own settings.
    func updateAutocorrectSettings(
        _ textView: UITextView,
        caretLocation: Int,
        codeTokens: [MarkdownToken]? = nil,
        latexTokens: [MarkdownToken]? = nil,
        allTokens: [MarkdownToken]? = nil
    ) {}

    /// macOS overlays copy buttons on code blocks; iOS has none.
    func updateCodeBlockSelection(textView: UITextView, parsed: ParsedDocument? = nil) {}
}
#endif
