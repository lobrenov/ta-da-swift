// The text menu: a right-click on Live editor text opens the compact popup menu at the pointer, its rows by what's
// under it (a link, a selection or a caret). Format ▸, Paragraph ▸ and Insert ▸ are submenus that run the slash menu's
// commands. The editor engine reports the right-click; LiveEditor bridges the two.
#if os(macOS)
import SwiftUI
import AppKit
import TaDaCore

/// One row of the text menu.
struct TextMenuRow: PopupMenuItem {
    enum Action: Equatable {
        case openLink, copyLink
        case cut, copy, paste, pasteAsPlainText, selectAll
        case extractToTask
        /// A slash command: an inline format from Format ▸, a block from Paragraph ▸, an insertion from Insert ▸.
        case command(SlashCommand)
        /// Paragraph ▸ Body.
        case body
        /// A row that only opens its submenu.
        case submenu
    }

    enum Icon: Equatable {
        case symbol(String)
        case glyph(String)
        case command(SlashCommand)
    }

    let action: Action
    let title: String
    let icon: Icon
    var key: String? = nil
    var isChecked = false
    var isEnabled = true
    var submenu: [Self] = []

    var accessibilityValue: String { isChecked ? "Current" : "" }
}

/// What the text menu's rows depend on.
struct TextMenuTarget {
    var hasSelection: Bool
    var onLink: Bool
    var canExtract: Bool
    /// The inline formats the selection, or the word at the caret, is in.
    var formats: Set<SlashCommand>
    /// The line's block (`.heading1` to `.quote`); nil for body text and deeper headings.
    var block: SlashCommand?
    var isBody: Bool
}

enum TextMenu {
    /// The paragraph blocks Paragraph ▸ lists, in order, around Body.
    static let paragraphs: [SlashCommand] = [.heading1, .heading2, .heading3]
    static let lists: [SlashCommand] = [.bulletedList, .numberedList, .task, .quote]
    static let formats: [SlashCommand] = [.bold, .italic, .strikethrough, .highlight, .inlineCode]
    static let insertions: [SlashCommand] = [.wikiLink, .link, .image, .table, .callout, .codeBlock, .divider]

    /// Commands inserted as blocks, on their own lines.
    static let blockInsertions: Set<SlashCommand> = [.table, .callout, .codeBlock, .divider]

    static func keys(for command: SlashCommand) -> String? {
        switch command {
        case .bold: "⌘B"
        case .italic: "⌘I"
        case .strikethrough: "⇧⌘S"
        case .highlight: "⇧⌘H"
        default: nil
        }
    }

    /// The menu's sections; a divider falls between them.
    static func sections(for target: TextMenuTarget) -> [[TextMenuRow]] {
        var sections: [[TextMenuRow]] = []
        if target.onLink {
            sections.append([TextMenuRow(action: .openLink, title: "Open Link", icon: .symbol("arrow.up.forward")),
                             TextMenuRow(action: .copyLink, title: "Copy Link", icon: .symbol("link"))])
        }
        sections.append([
            TextMenuRow(action: .cut, title: "Cut", icon: .symbol("scissors"), key: "⌘X", isEnabled: target.hasSelection),
            TextMenuRow(action: .copy, title: "Copy", icon: .symbol("doc.on.doc"), key: "⌘C", isEnabled: target.hasSelection),
            TextMenuRow(action: .paste, title: "Paste", icon: .symbol("doc.on.clipboard"), key: "⌘V"),
            TextMenuRow(action: .pasteAsPlainText, title: "Paste as Plain Text", icon: .symbol("doc.plaintext"), key: "⌥⇧⌘V"),
            TextMenuRow(action: .selectAll, title: "Select All", icon: .symbol("selection.pin.in.out"), key: "⌘A"),
        ])
        if target.hasSelection, target.canExtract {
            sections.append([TextMenuRow(action: .extractToTask, title: "Extract to Task",
                                         icon: .symbol("arrow.up.forward.square"), key: "⌥⌘E")])
        }
        sections.append([
            TextMenuRow(action: .submenu, title: "Format", icon: .glyph("Aa"), submenu: formats.map {
                TextMenuRow(action: .command($0), title: $0.title, icon: .command($0), key: keys(for: $0),
                            isChecked: target.formats.contains($0))
            }),
            TextMenuRow(action: .submenu, title: "Paragraph", icon: .glyph("¶"),
                        submenu: (paragraphs.map { paragraph($0, target) }
                                  + [TextMenuRow(action: .body, title: "Body", icon: .glyph("T"), isChecked: target.isBody)]
                                  + lists.map { paragraph($0, target) })),
            TextMenuRow(action: .submenu, title: "Insert", icon: .symbol("plus"), submenu: insertions.map {
                TextMenuRow(action: .command($0), title: $0.title, icon: .command($0))
            }),
        ])
        return sections
    }

    private static func paragraph(_ command: SlashCommand, _ target: TextMenuTarget) -> TextMenuRow {
        TextMenuRow(action: .command(command), title: command.title, icon: .command(command), isChecked: target.block == command)
    }
}

/// Shows, moves through and picks from the text menu. Owned by LiveEditor.
final class TextMenuController {
    private let menu = PopupMenu(style: .compact, takesKeys: true, row: TextMenuRowView.init)

    /// Opens the menu under `anchor` (screen coordinates). `pick` runs the chosen row after the menu has closed; `close`
    /// runs however the menu closes.
    func show(_ sections: [[TextMenuRow]], anchor: CGRect, theme: Theme, pick: @escaping (TextMenuRow) -> Void,
              close: @escaping () -> Void) {
        guard anchor != .zero, let parent = NSApp.keyWindow else { return close() }
        menu.onDismiss = { [weak self] in
            self?.hide()
            close()
        }
        menu.show(sections.map { PopupMenuSection(items: $0) }, highlight: nil, theme: theme, below: anchor,
                  inset: 0, gap: 4, in: parent) { [weak self] item in
            guard item.isEnabled, item.submenu.isEmpty else { return }
            self?.hide()
            close()
            pick(item)
        }
    }

    func hide() { menu.hide() }
}

private struct TextMenuRowView: View {
    let item: TextMenuRow
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 14, height: 20)
                .foregroundStyle(theme.color(isHighlighted ? \.accent : \.muted))
            Text(item.title)
                .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            if item.isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.color(\.accent))
            }
            if let key = item.key {
                Text(key)
                    .font(.system(size: 11.5))
                    .tracking(0.5)
                    .foregroundStyle(theme.color(\.muted))
            }
        }
        .opacity(item.isEnabled ? 1 : 0.45)
    }

    @ViewBuilder private var icon: some View {
        switch item.icon {
        case .symbol(let name): Image(systemName: name).font(.system(size: 12))
        case .glyph(let text): Text(text).font(.system(size: text.count > 1 ? 11 : 12, weight: .semibold))
        case .command(let command): SlashCommandIcon(command: command, size: 12)
        }
    }
}
#endif
