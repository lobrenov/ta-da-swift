//
//  NativeTextViewCoordinator+SlashCommand.swift
//  MarkdownEngine
//
//  Ta Da fork: a `/` typed at a line start or after whitespace opens a slash
//  command. The engine tracks the `/query` and routes the menu keys; the
//  embedder draws the menu and inserts through `SlashCommandProxy`.
//

import AppKit

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

    /// Replaces the `/query` with `text` (one undo step) and selects `selection`, which is relative to `text`.
    public func insert(_ text: String, selecting selection: NSRange) {
        coordinator?.insertSlashCommand(text, selecting: selection)
    }

    /// Closes the menu until the next `/` is typed.
    public func dismiss() {
        coordinator?.dismissSlashCommand()
    }
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
    func updateSlashCommand(in tv: NSTextView) {
        guard let anchor = slashAnchor else { return }
        let text = tv.string as NSString
        let selection = tv.selectedRange()
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

    func insertSlashCommand(_ insertion: String, selecting selection: NSRange) {
        guard let tv = textView, let range = slashCommand?.range else { return }
        dismissSlashCommand()
        guard NSMaxRange(range) <= (tv.string as NSString).length else { return }
        tv.breakUndoCoalescing()
        isProgrammaticEdit = true
        defer { isProgrammaticEdit = false }
        guard tv.shouldChangeText(in: range, replacementString: insertion) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: insertion)
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
                let anchor = tv.firstRect(forCharacterRange: NSRange(location: command.range.location, length: 1),
                                          actualRange: nil)
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
