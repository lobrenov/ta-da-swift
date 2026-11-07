// The slash menu: markdown formats in a popup menu under the `/`.
// The editor engine tracks the `/query` and routes the keys; LiveEditor bridges the two.
// On iPhone the choices list above the keyboard bar (`PhoneSlashList`).
import SwiftUI
import TaDaCore
#if os(macOS)
import AppKit

/// Shows, moves through and picks from the slash menu. Owned by LiveEditor.
final class SlashMenuController {
    enum Key { case up, down, confirm }

    private let menu = PopupMenu(style: .full(confirm: "Insert", maxListHeight: 284), takesKeys: false,
                                 emptyText: "No matching formats", row: SlashMenuRow.init)
    private var commands: [SlashCommand] = []
    private var query = ""

    /// Shows the menu under `anchor` (the `/`, in screen coordinates), or refreshes it.
    func show(query: String, atLineStart: Bool, inTableCell: Bool = false, anchor: CGRect, theme: Theme,
              pick: @escaping (SlashCommand) -> Void, dismiss: @escaping () -> Void) {
        guard anchor != .zero, let parent = NSApp.keyWindow else { return }
        // A table cell takes neither a table nor an image.
        let commands = SlashCommand.matching(query, atLineStart: atLineStart).filter { !inTableCell || ($0 != .table && $0 != .image) }
        let highlight = commands != self.commands || query != self.query ? 0 : menu.highlight
        self.commands = commands
        self.query = query
        // A click elsewhere or a scroll ends the command; the editor's `/` text stays.
        menu.onDismiss = dismiss
        menu.show(Self.sections(of: commands, query: query), highlight: highlight, theme: theme,
                  below: anchor, inset: 8, gap: 6, in: parent, pick: pick)
    }

    func hide() { menu.hide() }

    /// Returns `true` when the menu used the key. ↵ with no matches falls through to the editor.
    func handle(_ key: Key) -> Bool {
        guard menu.isOpen else { return false }
        switch key {
        case .up: menu.move(by: -1)
        case .down: menu.move(by: 1)
        case .confirm: return menu.pickHighlighted()
        }
        return true
    }

    /// Grouped under labels while nothing is typed; ranked flat once it is.
    private static func sections(of commands: [SlashCommand], query: String) -> [PopupMenuSection<SlashCommand>] {
        guard query.isEmpty else { return [PopupMenuSection(items: commands)] }
        return SlashCommand.Group.allCases.map { group in
            PopupMenuSection(label: group.rawValue, items: commands.filter { $0.group == group })
        }
    }
}

extension SlashCommand: PopupMenuItem {}

private struct SlashMenuRow: View {
    let command: SlashCommand
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 12) {
            SlashCommandIcon(command: command)
                .foregroundStyle(theme.color(isHighlighted ? \.accent : \.muted))
                .frame(width: 20, height: 20)
            Text(command.title)
                .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(command.hint)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.color(\.muted))
        }
    }
}
#endif

/// The command's SF Symbol, or its `H1`–`H3` or `[[ ]]` glyph; `size` is the symbol's point size.
struct SlashCommandIcon: View {
    let command: SlashCommand
    var size: CGFloat = 13

    var body: some View {
        switch command {
        case .heading1: glyph("H1")
        case .heading2: glyph("H2")
        case .heading3: glyph("H3")
        case .wikiLink: Text("[[ ]]").font(.system(size: size * 9.5 / 13, weight: .semibold, design: .monospaced))
        default: Image(systemName: symbol).font(.system(size: size))
        }
    }

    private func glyph(_ text: String) -> some View {
        Text(text).font(.system(size: size * 11 / 13, weight: .bold))
    }

    private var symbol: String {
        switch command {
        case .bulletedList: "list.bullet"
        case .numberedList: "list.number"
        case .task: "checkmark.square"
        case .quote: "text.quote"
        case .callout: "text.bubble"
        case .divider: "minus"
        case .codeBlock: "terminal"
        case .table: "tablecells"
        case .link: "link"
        case .image: "photo"
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .highlight: "highlighter"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        case .heading1, .heading2, .heading3, .wikiLink: ""
        }
    }
}

#if os(iOS)
/// The `/` query's choices, above the keyboard bar: a tap picks one.
struct PhoneSlashList: View {
    let choices: [SlashCommand]
    let highlight: Int
    let theme: Theme
    let pick: (SlashCommand) -> Void

    private static let rowHeight: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(choices.enumerated()), id: \.element) { offset, command in
                    Button { pick(command) } label: {
                        HStack(spacing: 12) {
                            SlashCommandIcon(command: command, size: 17)
                                .foregroundStyle(theme.color(offset == highlight ? \.accent : \.muted))
                                .frame(width: 28, height: 28)
                            Text(command.title)
                                .foregroundStyle(theme.color(offset == highlight ? \.strong : \.fg))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(command.hint)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(theme.color(\.muted))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: Self.rowHeight)
                        .background(offset == highlight ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 16))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(command.hint)
                }
            }
            .padding(4)
        }
        .scrollIndicators(.never)
        .frame(height: min(CGFloat(choices.count) * Self.rowHeight + 8, 162))
        .font(.system(size: 17))
        .glassEffect(in: .rect(cornerRadius: 20))
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}
#endif
