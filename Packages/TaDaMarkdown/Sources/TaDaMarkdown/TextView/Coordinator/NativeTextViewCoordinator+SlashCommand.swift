//
//  NativeTextViewCoordinator+SlashCommand.swift
//  TaDaMarkdown
//
//  Ta Da fork: a `/` typed at a line start or after whitespace opens a slash
//  command. The engine tracks the `/query` and routes the menu keys; the
//  embedder draws the menu and inserts through `SlashCommandProxy`.
//

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Ta Da fork: the `/query` being typed, delivered through
/// ``NativeTextViewWrapper/onSlashCommandChange``.
public struct SlashCommandState: Equatable, Sendable {
    /// The `/` through the caret, in display coordinates.
    public let range: NSRange
    /// The text after the `/`.
    public let query: String
    /// Only spaces or tabs precede the `/` on its line.
    public let isAtLineStart: Bool
    /// The line above is blank, or there is none.
    public let followsBlankLine: Bool
    /// The `/` in screen coordinates, to anchor the menu.
    public let anchorRect: CGRect
}

/// Ta Da fork: acts on the open slash command. Pass one to
/// ``NativeTextViewWrapper/slashCommandProxy``.
@MainActor
public final class SlashCommandProxy {
    weak var coordinator: NativeTextViewCoordinator?

    public init() {}

    /// Ta Da fork: the editor's text view, for edits the embedder makes itself.
    public var textView: PlatformTextView? { coordinator?.textView }

    /// Replaces the `/query` with `text` (one undo step) and selects `selection`, which is relative to `text`.
    public func insert(_ text: String, selecting selection: NSRange) {
        coordinator?.insertSlashCommand(text, selecting: selection)
    }

    /// Indents the selected list lines (and their children), as Tab does.
    public func indent() {
        guard let textView = coordinator?.textView else { return }
        let maximumLevel = (textView as? NativeTextView)?.configuration.lists.maximumNestingLevel
            ?? MarkdownEditorConfiguration.default.lists.maximumNestingLevel
        _ = MarkdownLists.indentListLines(textView, selection: textView.currentSelectedRange, maximumLevel: maximumLevel)
    }

    /// Outdents the selected list lines (and their children), as Shift-Tab does.
    public func outdent() {
        guard let coordinator, let textView = coordinator.textView else { return }
        _ = coordinator.handleBacktab(textView)
    }

    #if os(iOS)
    /// Ta Da fork: replaces the selection with `text` as typing does, so a typed opener pairs (and a typed closer
    /// steps over one) as Autocomplete's switches say. UIKit's `insertText` bypasses the editor's input handling.
    public func type(_ text: String) {
        guard let textView = coordinator?.textView else { return }
        textView.replaceCharacters(in: textView.selectedRange, with: text)
    }
    #endif

    /// Closes the menu until the next `/` is typed.
    public func dismiss() {
        coordinator?.dismissSlashCommand()
    }

    /// Ta Da fork: formats the selection as the editor's formatting commands do, for iOS's formatting bar.
    public func apply(_ format: MarkdownFormat) {
        guard let coordinator, let textView = coordinator.textView else { return }
        switch format {
        case .bold: coordinator.didMarkdownBold(nil)
        case .italic: coordinator.didMarkdownItalic(nil)
        case .inlineCode: coordinator.didMarkdownInlineCode(nil)
        case .nextHeading:
            let text = textView.string as NSString
            let line = text.substring(with: text.lineRange(for: textView.currentSelectedRange))
            let level = line.prefix { $0 == "#" }.count
            coordinator.didMarkdownHeading(level: level >= 3 ? 0 : level + 1)
        }
    }
}

/// Ta Da fork: a format ``SlashCommandProxy/apply(_:)`` toggles. `nextHeading` steps the line through
/// headings 1 to 3, then back to body text.
public enum MarkdownFormat: Sendable {
    case bold, italic, inlineCode, nextHeading
}

extension NativeTextViewCoordinator {

    private static let slashQueryStops = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/"))

    /// From `shouldChangeTextIn`, for interactive edits: a typed `/` after whitespace starts a query.
    func noteSlashCommandEdit(_ range: NSRange, replacement: String?, in text: NSString, codeTokens: [MarkdownToken]) {
        guard onSlashCommandChange != nil, replacement == "/", range.length == 0 else { return }
        if range.location > 0 {
            guard let previous = Unicode.Scalar(text.character(at: range.location - 1)),
                  CharacterSet.whitespacesAndNewlines.contains(previous) else { return }
        }
        guard !MarkdownDetection.isInsideCodeBlock(location: range.location, codeTokens: codeTokens) else { return }
        slashAnchor = range.location
    }

    /// From every selection change: follows the caret, or closes once it leaves the `/query`.
    func updateSlashCommand(in tv: PlatformTextView) {
        guard let anchor = slashAnchor else { return }
        let text = tv.string as NSString
        let selection = tv.currentSelectedRange
        guard selection.length == 0, anchor < text.length, text.character(at: anchor) == 0x2F,
              selection.location > anchor else { return dismissSlashCommand() }
        let range = NSRange(location: anchor, length: selection.location - anchor)
        let query = text.substring(with: NSRange(location: anchor + 1, length: range.length - 1))
        guard query.count <= 40, query.rangeOfCharacter(from: Self.slashQueryStops) == nil else {
            return dismissSlashCommand()
        }
        let line = text.lineRange(for: NSRange(location: anchor, length: 0))
        let lead = text.substring(with: NSRange(location: line.location, length: anchor - line.location))
        let followsBlankLine: Bool = {
            guard line.location > 0 else { return true }
            let above = text.lineRange(for: NSRange(location: line.location - 1, length: 0))
            return text.substring(with: above).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }()
        slashCommand = SlashCommandQuery(range: range, query: query,
                                         isAtLineStart: lead.allSatisfy { $0 == " " || $0 == "\t" },
                                         followsBlankLine: followsBlankLine)
        reportSlashCommand()
    }

    func dismissSlashCommand() {
        slashAnchor = nil
        guard slashCommand != nil else { return }
        slashCommand = nil
        reportSlashCommand()
    }

    #if os(macOS)
    /// From `doCommandBy`: ↑/↓ move, ↵/⇥ insert, esc closes. `true` when the key was consumed.
    func handleSlashCommandKey(_ commandSelector: Selector) -> Bool {
        guard slashCommand != nil, let handler = onSlashCommandKey else { return false }
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            dismissSlashCommand()
            return true
        case #selector(NSResponder.moveUp(_:)): return handler(.moveUp)
        case #selector(NSResponder.moveDown(_:)): return handler(.moveDown)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)): return handler(.confirm)
        default: return false
        }
    }
    #endif

    func insertSlashCommand(_ insertion: String, selecting selection: NSRange) {
        guard let tv = textView, let range = slashCommand?.range else { return }
        dismissSlashCommand()
        guard NSMaxRange(range) <= (tv.string as NSString).length else { return }
        tv.breakUndoCoalescing()
        isProgrammaticEdit = true
        defer { isProgrammaticEdit = false }
        guard tv.shouldChangeText(in: range, replacementString: insertion) else { return }
        tv.optionalTextStorage?.replaceCharacters(in: range, with: insertion)
        tv.didChangeText()
        tv.undoManager?.setActionName("Insert Formatting")
        tv.breakUndoCoalescing()
        tv.setSelectedRange(NSRange(location: range.location + selection.location, length: selection.length))
    }

    /// Deferred so layout has caught up (the anchor rect is current) and SwiftUI isn't mid-update.
    /// Reads the latest query when it runs, so a burst of keystrokes reports once.
    private func reportSlashCommand() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var state: SlashCommandState?
            if let command = slashCommand, let tv = textView {
                let anchor = tv.anchorRect(forCharacterRange: NSRange(location: command.range.location, length: 1))
                state = SlashCommandState(range: command.range, query: command.query,
                                          isAtLineStart: command.isAtLineStart,
                                          followsBlankLine: command.followsBlankLine, anchorRect: anchor)
            }
            guard state != reportedSlashCommand else { return }
            reportedSlashCommand = state
            onSlashCommandChange?(state)
        }
    }
}

/// Ta Da fork: the open `/query` (see `NativeTextViewCoordinator+SlashCommand`).
struct SlashCommandQuery {
    let range: NSRange
    let query: String
    let isAtLineStart: Bool
    let followsBlankLine: Bool
}
