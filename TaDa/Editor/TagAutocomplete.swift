// The tag autocomplete menu: tags in use after `#` and a first character, from `VaultIndex.tagSuggestions`.
// The editor engine tracks the query and routes the keys; LiveEditor shows the choices in a compact popup menu under
// the `#` on the Mac and in a list above the keyboard bar on iPhone. A pick writes the full path and a space; with no
// match the menu says "New tag" and the typed text stays.
import SwiftUI
import TaDaCore

extension TagNode {
    /// The text that replaces the query.
    var insertion: String { "#\(tag.name) " }
}

extension LinkMenuSource {
    /// The tags in use for `query`, leaving out those only the open file's body carries, such as the one being typed.
    func tagSuggestions(_ query: String) -> [TagNode] {
        let own = Set(openPath.flatMap { index[$0] }?.tags.filter { !$0.inFrontmatter }.map(\.tag.path) ?? [])
        return index.tagSuggestions(query).filter { !(own.contains($0.tag.path) && $0.count == 1) }
    }
}

/// A row's tag glyph, path (parent muted) and count.
struct TagSuggestionRow: View {
    let node: TagNode
    let isHighlighted: Bool
    let theme: Theme
    var glyphSize: CGFloat = 11
    var countSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(theme.color(\.accent))
            TagName(tag: node.tag)
                .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(node.count)")
                .font(.system(size: countSize, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.color(\.muted))
        }
        .environment(\.theme, theme)
    }
}

#if os(macOS)
import AppKit

extension TagNode: PopupMenuItem {
    var title: String { tag.name }
    var accessibilityValue: String { count == 1 ? "1 file" : "\(count) files" }
}

/// Shows, moves through and picks from the tag menu. Owned by LiveEditor.
final class TagMenuController {
    enum Key { case up, down, confirm }

    private var shown: [TagNode]?
    private lazy var menu: PopupMenu<TagNode, TagSuggestionRow> = {
        var style = PopupMenuStyle.compact
        style.width = 230
        style.maxListHeight = 216
        style.keepsHighlight = true
        return PopupMenu(style: style, takesKeys: false, emptyText: "New tag") { node, isHighlighted, theme in
            TagSuggestionRow(node: node, isHighlighted: isHighlighted, theme: theme)
        }
    }()

    /// Shows the menu under `anchor` (the `#`, in screen coordinates), or refreshes it.
    func show(_ choices: [TagNode], anchor: CGRect, theme: Theme, pick: @escaping (TagNode) -> Void,
              dismiss: @escaping () -> Void) {
        guard anchor != .zero, let parent = NSApp.keyWindow else { return }
        let highlight = shown == choices ? menu.highlight : 0
        shown = choices
        // A click elsewhere or a scroll ends the query; the typed text stays.
        menu.onDismiss = dismiss
        menu.show([PopupMenuSection(items: choices)], highlight: choices.isEmpty ? nil : highlight, theme: theme,
                  below: anchor, inset: 8, gap: 6, in: parent, pick: pick)
    }

    func hide() {
        menu.hide()
        shown = nil
    }

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
}
#else

/// The `#` query's choices, above the keyboard bar: a tap picks one. With no match it says "New tag".
struct PhoneTagList: View {
    let choices: [TagNode]
    let highlight: Int
    let theme: Theme
    let pick: (TagNode) -> Void

    private static let rowHeight: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if choices.isEmpty {
                    Text("New tag")
                        .foregroundStyle(theme.color(\.muted))
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                }
                ForEach(Array(choices.enumerated()), id: \.element.id) { offset, node in
                    Button { pick(node) } label: {
                        TagSuggestionRow(node: node, isHighlighted: offset == highlight, theme: theme, glyphSize: 15,
                                         countSize: 13)
                            .padding(.horizontal, 12)
                            .frame(height: Self.rowHeight)
                            .background(offset == highlight ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 16))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tag \(node.tag.name)")
                    .accessibilityValue(node.count == 1 ? "1 file" : "\(node.count) files")
                }
            }
            .padding(4)
        }
        .scrollIndicators(.never)
        .frame(height: min(CGFloat(max(choices.count, 1)) * Self.rowHeight + 8, 162))
        .font(.system(size: 17))
        .glassEffect(in: .rect(cornerRadius: 20))
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}
#endif
