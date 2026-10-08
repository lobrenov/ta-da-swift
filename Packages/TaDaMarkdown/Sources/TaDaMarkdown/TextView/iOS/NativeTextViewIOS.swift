//
//  NativeTextViewIOS.swift
//  TaDaMarkdown
//
//  The iOS editor: a TextKit 2 `UITextView` with the state the shared
//  styling, input and layout code reads from the macOS `NativeTextView`.
//

#if os(iOS)
import UIKit

final class NativeTextView: UITextView {
    var configuration: MarkdownEditorConfiguration = .default

    /// The pairs whose closers typing steps over (`MarkdownAutoPairs`).
    var autoPairs: [AutoPair] = []

    weak var layoutBridge: LayoutBridge?
    var baseFont: UIFont = .systemFont(ofSize: UIFont.systemFontSize)

    /// See ``NativeTextViewWrapper/onTaskMarkerMenu``.
    var onTaskMarkerMenu: ((TaskMarkerMenuRequest) -> Void)?
    /// See ``NativeTextViewWrapper/onCalloutMenu``.
    var onCalloutMenu: ((CalloutMenuRequest) -> Void)?
    /// The title line location of the callout whose menu is open.
    var calloutMenuTarget: Int?
    /// Skips the next scroll-to-caret, after an edit that places the caret itself.
    var suppressAutoRevealOnce = false

    init() {
        super.init(frame: .zero, textContainer: nil)
        textContainer.textView = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Lays out the visible part of the document, as AppKit's `ensureLayout` would.
    func ensureVisibleLayout() {
        guard let layoutManager = textLayoutManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange else { return }
        layoutManager.ensureLayout(for: viewport)
    }
}
#endif
