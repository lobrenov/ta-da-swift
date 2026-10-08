//
//  NativeTextViewIOS.swift
//  TaDaMarkdown
//
//  The iOS editor: a TextKit 2 `UITextView` with the state the shared
//  styling, input and layout code reads from the macOS `NativeTextView`.
//

#if os(iOS)
import SwiftUI
import UIKit

final class NativeTextView: UITextView {
    var configuration: MarkdownEditorConfiguration = .default

    /// The pairs whose closers typing steps over (`MarkdownAutoPairs`). Every applied edit
    /// moves them; undo and redo forget them.
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
    /// What the selection and text delegates are reacting to: typing or a tap.
    var inputKind: EditorInputKind = .other

    /// The attributes typed text starts with: the body font and paragraph style,
    /// so a heading's style never carries into the next line.
    var baseTypingAttributes: [NSAttributedString.Key: Any]?

    /// The embedder's header, above the text; it scrolls with it.
    private var headerHost: UIHostingController<AnyView>?
    private var headerHeight: CGFloat = 0
    /// The vertical text inset before the header's height is added.
    var bodyInsets = UIEdgeInsets.zero {
        didSet { applyInsets() }
    }

    init() {
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.textContainer = container
        let contentStorage = NSTextContentStorage()
        contentStorage.addTextLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: container)
        container.textView = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var coordinator: NativeTextViewCoordinator? { delegate as? NativeTextViewCoordinator }

    /// Each document keeps its own undo stack (see `NativeTextViewCoordinator.undoManager(forDocument:)`).
    override var undoManager: UndoManager? {
        coordinator.map { $0.undoManager(forDocument: $0.documentId) } ?? super.undoManager
    }

    override var typingAttributes: [NSAttributedString.Key: Any] {
        get { baseTypingAttributes ?? super.typingAttributes }
        set { super.typingAttributes = baseTypingAttributes ?? newValue }
    }

    // MARK: Input kind

    override func insertText(_ text: String) {
        inputKind = .key
        defer { inputKind = .other }
        super.insertText(text)
    }

    override func deleteBackward() {
        inputKind = .key
        defer { inputKind = .other }
        super.deleteBackward()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        inputKind = .click
        super.touchesEnded(touches, with: event)
        DispatchQueue.main.async { [weak self] in self?.inputKind = .other }
    }

    // MARK: Layout

    /// Lays out the visible part of the document, as AppKit's `ensureLayout` would.
    func ensureVisibleLayout() {
        guard let layoutManager = textLayoutManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange else { return }
        layoutManager.ensureLayout(for: viewport)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutHeader()
    }

    // MARK: Header

    func setHeader(_ header: AnyView?) {
        guard let header else {
            headerHost?.view.removeFromSuperview()
            headerHost = nil
            headerHeight = 0
            applyInsets()
            return
        }
        if let headerHost {
            headerHost.rootView = header
        } else {
            let host = UIHostingController(rootView: header)
            host.view.backgroundColor = .clear
            host.sizingOptions = .intrinsicContentSize
            addSubview(host.view)
            headerHost = host
        }
        setNeedsLayout()
    }

    private func layoutHeader() {
        guard let view = headerHost?.view else { return }
        let width = bounds.width
        guard width > 0 else { return }
        let height = ceil(view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        if abs(height - headerHeight) > 0.5 {
            headerHeight = height
            applyInsets()
        }
    }

    private func applyInsets() {
        var insets = bodyInsets
        insets.top += headerHeight
        if textContainerInset != insets { textContainerInset = insets }
    }
}
#endif
