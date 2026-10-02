// Source mode: the whole file, frontmatter included, in a plain-text editor with line numbers,
// a current-line highlight and colouring by role (SourceHighlighter).
import AppKit
import SwiftUI

struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme
    /// A new document replaces the text and its undo history.
    let documentID: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = SourceTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: SourceTextView.gutter, height: 28)
        textView.setAccessibilityLabel("Source")

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        textView.apply(theme)
        textView.string = text
        textView.rehighlight()
        textView.setSelectedRange(NSRange())
        context.coordinator.documentID = documentID
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        guard let textView = coordinator.textView else { return }
        if textView.theme != theme {
            textView.apply(theme)
            textView.rehighlight()
        }
        let newDocument = coordinator.documentID != documentID
        if newDocument || textView.string != text {
            // Changed outside this editor: a new file, a property edit or a reload from disk.
            let selection = textView.selectedRange()
            textView.string = text
            textView.rehighlight()
            let length = (text as NSString).length
            textView.setSelectedRange(newDocument ? NSRange() : NSRange(location: min(selection.location, length), length: 0))
            textView.undoManager?.removeAllActions(withTarget: textView.textStorage!)
            if newDocument { textView.scroll(.zero) }
            coordinator.documentID = documentID
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: SourceTextView?
        var text: Binding<String>?
        var documentID = ""

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            textView.rehighlight()
            text?.wrappedValue = textView.string
        }
    }
}

final class SourceTextView: NSTextView {
    /// Room left of the text for line numbers: 44pt of numbers and a 16pt gap. Mirrored on the right.
    static let gutter: CGFloat = 60
    static let lineHeight: CGFloat = 23

    private(set) var theme: Theme?
    /// UTF-16 offset where each line starts, for line numbers.
    private var lineStarts: [Int] = [0]

    private var font13: NSFont { NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular) }

    private var paragraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = Self.lineHeight
        style.maximumLineHeight = Self.lineHeight
        return style
    }

    /// Centres the glyphs in the fixed line height.
    private var baselineOffset: CGFloat {
        (Self.lineHeight - (font13.ascender - font13.descender)) / 2 - 1
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        backgroundColor = theme.bg
        drawsBackground = true
        insertionPointColor = theme.accent
        selectedTextAttributes = [.backgroundColor: theme.surface]
        typingAttributes = [.font: font13, .foregroundColor: theme.fg, .paragraphStyle: paragraph, .baselineOffset: baselineOffset]
        needsDisplay = true
    }

    /// Recolours the whole text. Files are small; this runs after every edit.
    func rehighlight() {
        guard let theme, let storage = textStorage else { return }
        let text = string
        let full = NSRange(location: 0, length: (text as NSString).length)
        lineStarts = [0]
        (text as NSString).enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, line, enclosing, _ in
            // A line ending starts another line.
            if enclosing.length > line.length { self.lineStarts.append(enclosing.location + enclosing.length) }
        }
        storage.beginEditing()
        storage.setAttributes([.font: font13, .foregroundColor: theme.fg, .paragraphStyle: paragraph, .baselineOffset: baselineOffset], range: full)
        for run in SourceHighlighter.runs(in: text) {
            let (color, weight) = style(run.role, theme)
            storage.addAttribute(.foregroundColor, value: color, range: run.range)
            if weight != .regular {
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13.5, weight: weight), range: run.range)
            }
        }
        storage.endEditing()
        needsDisplay = true
    }

    private func style(_ role: SourceHighlighter.Role, _ t: Theme) -> (NSColor, NSFont.Weight) {
        switch role {
        case .punct, .check, .doneText: (t.muted, .regular)
        case .key: (t.accent, .medium)
        case .value: (t.fg, .regular)
        case .string, .checkDone: (t.done, .regular)
        case .date: (t.due, .regular)
        case .heading: (t.strong, .bold)
        case .link: (t.link, .medium)
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
    }

    /// Paints the current line and the line numbers under the text.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let theme, let layoutManager, let textContainer else { return }
        let text = string as NSString
        let origin = textContainerOrigin
        let caretLine = lineNumber(at: min(selectedRange().location, text.length))
        let numberAttributes: (Bool) -> [NSAttributedString.Key: Any] = { current in
            let style = NSMutableParagraphStyle()
            style.alignment = .right
            style.minimumLineHeight = Self.lineHeight
            style.maximumLineHeight = Self.lineHeight
            return [.font: self.font13, .foregroundColor: current ? theme.fg : theme.muted,
                    .paragraphStyle: style, .baselineOffset: self.baselineOffset]
        }

        func draw(line: Int, in fragment: NSRect) {
            let row = NSRect(x: bounds.minX + 8, y: fragment.minY + origin.y, width: bounds.width - 16, height: fragment.height)
            if line == caretLine {
                theme.code.setFill()
                NSBezierPath(roundedRect: row, xRadius: 4, yRadius: 4).fill()
            }
            let number = NSRect(x: origin.x - Self.gutter, y: row.minY, width: Self.gutter - 16, height: Self.lineHeight)
            ("\(line)" as NSString).draw(in: number, withAttributes: numberAttributes(line == caretLine))
        }

        let visible = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, glyphRange, _ in
            let start = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            // Only a line's first fragment gets a number when it wraps.
            guard start == 0 || text.character(at: start - 1) == 0x0A || text.character(at: start - 1) == 0x0D else { return }
            draw(line: self.lineNumber(at: start), in: fragment)
        }
        // The empty line after a final newline, or in an empty file.
        if layoutManager.extraLineFragmentTextContainer != nil {
            draw(line: lineStarts.count, in: layoutManager.extraLineFragmentRect)
        }
    }

    /// 1-based line containing a UTF-16 offset.
    private func lineNumber(at offset: Int) -> Int {
        var low = 0, high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        return max(low, 1)
    }
}
